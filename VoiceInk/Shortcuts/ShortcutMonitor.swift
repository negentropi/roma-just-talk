import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os
import VoiceInkCore

private let systemDefinedCGEventTypeRawValue = UInt32(NSEvent.EventType.systemDefined.rawValue)

enum InputMonitoringPermission {
    struct Client {
        var preflight: () -> Bool
        var request: () -> Bool
    }

    static let systemClient = Client(
        preflight: CGPreflightListenEventAccess,
        request: CGRequestListenEventAccess
    )

    static func isGranted(client: Client = systemClient) -> Bool {
        client.preflight()
    }

    @discardableResult
    static func requestAccess(client: Client = systemClient) -> Bool {
        client.request()
    }
}

enum AccessibilityPermission {
    struct Client {
        var preflight: () -> Bool
        var request: () -> Bool
    }

    static let systemClient = Client(
        preflight: AXIsProcessTrusted,
        request: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    )

    static func isGranted(client: Client = systemClient) -> Bool {
        client.preflight()
    }

    @discardableResult
    static func requestAccess(client: Client = systemClient) -> Bool {
        client.request()
    }
}

enum SecureEventInputState {
    struct Client {
        var isEnabled: () -> Bool
    }

    static let systemClient = Client(
        isEnabled: IsSecureEventInputEnabled
    )

    static func isEnabled(client: Client = systemClient) -> Bool {
        client.isEnabled()
    }
}

enum KeyboardState {
    struct Client {
        var isKeyPressed: (UInt16) -> Bool
    }

    static let systemClient = Client { keyCode in
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }
}

final class ShortcutMonitor {
    enum EventKind {
        case keyDown
        case keyUp
        case flagsChanged
        case systemDefined
    }

    private enum ShortcutHandlingScope {
        case all
        case modifierOnly
        case nonModifierOnly

        func contains(_ shortcut: Shortcut) -> Bool {
            switch self {
            case .all:
                return true
            case .modifierOnly:
                return shortcut.isModifierOnly
            case .nonModifierOnly:
                return !shortcut.isModifierOnly
            }
        }
    }

    private struct ShortcutState {
        var shortcut: Shortcut
        var isDown = false
        var isBlockedBySecureInput = false
        var pressedAt: TimeInterval?
        var isInterrupted = false
        var pressContext = VoiceInkShortcutPressContext()
    }

    private var shortcuts: [ShortcutAction: ShortcutState] = [:]
    private var interruptibleActions: Set<ShortcutAction> = []
    private var secureInputBlockedActions: Set<ShortcutAction> = []
    private var onKeyDown: ((ShortcutAction, TimeInterval) -> Void)?
    private var onKeyUp: ((ShortcutAction, TimeInterval, VoiceInkShortcutPressContext) -> Void)?
    private var onPressContextChanged: ((ShortcutAction, VoiceInkShortcutPressContext) -> Void)?
    private var onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var modifierOnlyGlobalMonitor: Any?
    private var modifierOnlyLocalMonitor: Any?
    private var handlesModifierOnlyShortcutsInEventTap = false
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "ShortcutMonitor")

    private static var hasRequestedListenEventAccess = false
    private static var hasRequestedAccessibilityAccess = false
    private static var inputMonitoringClient = InputMonitoringPermission.systemClient
    private static var accessibilityClient = AccessibilityPermission.systemClient
    private static var secureEventInputClient = SecureEventInputState.systemClient
    private static var keyboardStateClient = KeyboardState.systemClient
    private static let nonModifierKeyCodes = (0...127)
        .map(UInt16.init)
        .filter { !Shortcut.isModifierKeyCode($0) }

    deinit {
        stop()
    }

    @discardableResult
    func start(
        shortcuts: [ShortcutAction: Shortcut],
        interruptibleActions: Set<ShortcutAction> = [],
        secureInputBlockedActions: Set<ShortcutAction> = [],
        tracksKeyUpEvidence: Bool = false,
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval, VoiceInkShortcutPressContext) -> Void,
        onPressContextChanged: ((ShortcutAction, VoiceInkShortcutPressContext) -> Void)? = nil,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil
    ) -> Bool {
        stop()

        for (action, shortcut) in shortcuts {
            self.shortcuts[action] = ShortcutState(shortcut: shortcut)
        }

        guard !self.shortcuts.isEmpty else {
            logger.notice("start: no shortcuts configured")
            return true
        }

        self.interruptibleActions = interruptibleActions
        self.secureInputBlockedActions = secureInputBlockedActions
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onPressContextChanged = onPressContextChanged
        self.onShortcutInterrupted = onShortcutInterrupted
        logger.notice("start: installing event tap for \(self.shortcuts.count, privacy: .public) shortcut(s)")

        return installEventTap(tracksKeyUpEvidence: tracksKeyUpEvidence)
    }

    func stop() {
        if let modifierOnlyGlobalMonitor {
            NSEvent.removeMonitor(modifierOnlyGlobalMonitor)
            self.modifierOnlyGlobalMonitor = nil
        }

        if let modifierOnlyLocalMonitor {
            NSEvent.removeMonitor(modifierOnlyLocalMonitor)
            self.modifierOnlyLocalMonitor = nil
        }

        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        shortcuts = [:]
        interruptibleActions = []
        secureInputBlockedActions = []
        onKeyDown = nil
        onKeyUp = nil
        onPressContextChanged = nil
        onShortcutInterrupted = nil
        handlesModifierOnlyShortcutsInEventTap = false
    }

    private func installEventTap(tracksKeyUpEvidence: Bool) -> Bool {
        let hasModifierOnlyShortcut = shortcuts.values.contains { $0.shortcut.isModifierOnly }
        let handlesModifierOnlyShortcutsInEventTap = tracksKeyUpEvidence && hasModifierOnlyShortcut
        let needsModifierOnlyMonitor = hasModifierOnlyShortcut && !handlesModifierOnlyShortcutsInEventTap
        let needsEventTap = shortcuts.values.contains { !$0.shortcut.isModifierOnly }
        let shouldInstallEventTap = needsEventTap || tracksKeyUpEvidence
        self.handlesModifierOnlyShortcutsInEventTap = handlesModifierOnlyShortcutsInEventTap

        if shouldInstallEventTap {
            guard installCGEventTap() else {
                stop()
                return false
            }
        }

        if needsModifierOnlyMonitor {
            guard Self.ensureAccessibilityAccessForMonitoring() else {
                logger.error("installModifierOnlyMonitors: accessibility access is not granted")
                stop()
                return false
            }

            installModifierOnlyEventMonitors()
        }

        guard shouldInstallEventTap else {
            logger.notice("installEventTap: skipped; modifier-only shortcuts use NSEvent monitors")
            return true
        }

        return true
    }

    private func installCGEventTap() -> Bool {
        guard Self.ensureListenEventAccessForMonitoring() else {
            logger.error("installEventTap: listen-event access is not granted")
            return false
        }

        guard Self.ensureAccessibilityAccessForMonitoring() else {
            logger.error("installEventTap: accessibility access is not granted")
            return false
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.resetPressedShortcutsAfterTapInterruption()
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let shouldSuppress = monitor.handleCGEvent(type: type, event: event)
            return shouldSuppress ? nil : Unmanaged.passUnretained(event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("installEventTap: CGEvent.tapCreate failed")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            logger.error("installEventTap: failed to create run loop source")
            return false
        }

        self.eventTap = eventTap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.notice("installEventTap: installed")
        return true
    }

    private func installModifierOnlyEventMonitors() {
        modifierOnlyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            _ = self?.handleNSEvent(event, scope: .modifierOnly)
        }

        modifierOnlyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            _ = self?.handleNSEvent(event, scope: .modifierOnly)
            return event
        }

        let modifierOnlyShortcutCount = shortcuts.values.filter { $0.shortcut.isModifierOnly }.count
        logger.notice("installModifierOnlyMonitors: installed for \(modifierOnlyShortcutCount, privacy: .public) modifier-only shortcut(s)")
    }

    static func preflightListenEventAccess() -> Bool {
        InputMonitoringPermission.isGranted(client: inputMonitoringClient)
    }

    @discardableResult
    static func requestListenEventAccess() -> Bool {
        InputMonitoringPermission.requestAccess(client: inputMonitoringClient)
    }

    static func preflightAccessibilityAccess() -> Bool {
        AccessibilityPermission.isGranted(client: accessibilityClient)
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        AccessibilityPermission.requestAccess(client: accessibilityClient)
    }

    static func isSecureEventInputEnabled() -> Bool {
        SecureEventInputState.isEnabled(client: secureEventInputClient)
    }

    private static func hasPressedNonModifierKey() -> Bool {
        nonModifierKeyCodes.contains { keyboardStateClient.isKeyPressed($0) }
    }

    private static func ensureListenEventAccessForMonitoring() -> Bool {
        if preflightListenEventAccess() {
            return true
        }

        guard !hasRequestedListenEventAccess else {
            return false
        }

        hasRequestedListenEventAccess = true
        return requestListenEventAccess()
    }

    private static func ensureAccessibilityAccessForMonitoring() -> Bool {
        if preflightAccessibilityAccess() {
            return true
        }

        guard !hasRequestedAccessibilityAccess else {
            return false
        }

        hasRequestedAccessibilityAccess = true
        return requestAccessibilityAccess()
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard let eventKind = EventKind(type) else {
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return handleEvent(
            kind: eventKind,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: ProcessInfo.processInfo.systemUptime,
            scope: handlesModifierOnlyShortcutsInEventTap ? .all : .nonModifierOnly
        )
    }

    private func handleNSEvent(_ event: NSEvent, scope: ShortcutHandlingScope) -> Bool {
        guard let eventKind = EventKind(event.type) else {
            return false
        }

        return handleEvent(
            kind: eventKind,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            eventTime: event.timestamp,
            scope: scope
        )
    }

    private func resetPressedShortcutsAfterTapInterruption() {
        let eventTime = ProcessInfo.processInfo.systemUptime
        let pressedActions = shortcuts.compactMap { action, state in
            state.isDown ? action : nil
        }

        guard !pressedActions.isEmpty else {
            return
        }

        for action in pressedActions {
            if var state = shortcuts[action] {
                var context = state.pressContext
                let shouldDispatchKeyUp = !state.isBlockedBySecureInput
                if shouldDispatchKeyUp {
                    context.hasReliableKeyEvidence = false
                }
                state.isDown = false
                state.isBlockedBySecureInput = false
                state.pressedAt = nil
                state.isInterrupted = false
                state.pressContext = VoiceInkShortcutPressContext()
                shortcuts[action] = state
                if shouldDispatchKeyUp {
                    dispatchKeyUp(for: action, eventTime: eventTime, context: context)
                }
            }
        }
    }

    private func handleEvent(
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval,
        scope: ShortcutHandlingScope = .all
    ) -> Bool {
        var shouldSuppress = false
        let isSecureInputEnabled = Self.isSecureEventInputEnabled()

        if isSecureInputEnabled {
            recordUnreliableKeyEvidenceDuringActiveShortcuts()
        }

        if kind == .keyDown {
            recordPressEvidenceDuringActiveShortcuts(
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )
            handleShortcutInterruptions(keyCode: keyCode, eventTime: eventTime)
        } else if kind == .systemDefined {
            recordPressEvidenceDuringActiveShortcuts(
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )
        } else {
            recordPressEvidenceDuringActiveShortcuts(
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )
            recordReleaseEvidenceDuringActiveShortcuts(
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )
        }

        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action] else {
                continue
            }

            guard scope.contains(state.shortcut) else {
                continue
            }

            if state.shortcut.isModifierOnly {
                handleModifierOnlyShortcut(
                    action: action,
                    state: state,
                    kind: kind,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    eventTime: eventTime,
                    isSecureInputEnabled: isSecureInputEnabled
                )
                continue
            }

            let transition = transitionForKeyShortcut(
                state.shortcut,
                isDown: state.isDown,
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )

            switch transition {
            case .none:
                break
            case .suppress:
                shouldSuppress = true
            case .keyDown:
                state.isDown = true
                state.pressedAt = eventTime
                state.isInterrupted = false
                state.pressContext = VoiceInkShortcutPressContext()
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyDown(for: action, eventTime: eventTime)
            case .keyUp:
                let context = state.pressContext
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                state.pressContext = VoiceInkShortcutPressContext()
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyUp(for: action, eventTime: eventTime, context: context)
            }
        }

        return shouldSuppress
    }

    private func recordUnreliableKeyEvidenceDuringActiveShortcuts() {
        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action],
                  state.isDown,
                  !state.isBlockedBySecureInput
            else {
                continue
            }

            state.pressContext.hasReliableKeyEvidence = false
            shortcuts[action] = state
            dispatchPressContextChanged(for: action, context: state.pressContext)
        }
    }

    private func recordPressEvidenceDuringActiveShortcuts(
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard isKeyPressEvidence(kind: kind, keyCode: keyCode, modifierFlags: modifierFlags) else {
            return
        }

        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action],
                  state.isDown,
                  !state.isBlockedBySecureInput,
                  !state.shortcut.representsPressEvent(kind: kind, keyCode: keyCode, modifierFlags: modifierFlags)
            else {
                continue
            }

            state.pressContext.didPressOtherKeyDuringPress = true
            shortcuts[action] = state
            dispatchPressContextChanged(for: action, context: state.pressContext)
        }
    }

    private func recordReleaseEvidenceDuringActiveShortcuts(
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard isKeyReleaseEvidence(kind: kind, keyCode: keyCode, modifierFlags: modifierFlags) else {
            return
        }

        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action],
                  state.isDown,
                  !state.isBlockedBySecureInput,
                  !state.shortcut.representsReleaseEvent(kind: kind, keyCode: keyCode, modifierFlags: modifierFlags)
            else {
                continue
            }

            state.pressContext.didReleaseOtherKeyDuringPress = true
            shortcuts[action] = state
            dispatchPressContextChanged(for: action, context: state.pressContext)
        }
    }

    private func isKeyPressEvidence(
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        switch kind {
        case .keyDown:
            return true
        case .systemDefined:
            return true
        case .flagsChanged:
            return Shortcut.isModifierPressEvent(keyCode: keyCode, modifierFlags: modifierFlags)
        case .keyUp:
            return false
        }
    }

    private func isKeyReleaseEvidence(
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        switch kind {
        case .keyUp:
            return true
        case .flagsChanged:
            return Shortcut.isModifierReleaseEvent(keyCode: keyCode, modifierFlags: modifierFlags)
        case .keyDown, .systemDefined:
            return false
        }
    }

    private enum ShortcutTransition {
        case none
        case suppress
        case keyDown
        case keyUp
    }

    private func transitionForKeyShortcut(
        _ shortcut: Shortcut,
        isDown: Bool,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ShortcutTransition {
        switch kind {
        case .keyDown:
            guard shortcut.matchesKeyEvent(keyCode: keyCode, modifierFlags: modifierFlags) else {
                return .none
            }

            return isDown ? .suppress : .keyDown
        case .keyUp:
            return isDown && keyCode == shortcut.keyCode ? .keyUp : .none
        case .flagsChanged:
            guard isDown else {
                return .none
            }

            let currentFlags = Shortcut.normalizedModifierFlags(
                modifierFlags,
                forKeyCode: shortcut.keyCode
            )
            return currentFlags.isSuperset(of: shortcut.modifierFlags) ? .suppress : .keyUp
        case .systemDefined:
            return .none
        }
    }

    private func handleModifierOnlyShortcut(
        action: ShortcutAction,
        state: ShortcutState,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval,
        isSecureInputEnabled: Bool
    ) {
        var state = state

        guard kind == .flagsChanged else {
            return
        }

        if state.isDown {
            if state.shortcut.shouldReleaseModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
                var context = state.pressContext
                let shouldDispatchKeyUp = !state.isBlockedBySecureInput
                if shouldDispatchKeyUp, Self.hasPressedNonModifierKey() {
                    context.didPressOtherKeyDuringPress = true
                }
                state.isDown = false
                state.isBlockedBySecureInput = false
                state.pressedAt = nil
                state.isInterrupted = false
                state.pressContext = VoiceInkShortcutPressContext()
                shortcuts[action] = state
                if shouldDispatchKeyUp {
                    dispatchKeyUp(for: action, eventTime: eventTime, context: context)
                }
            }

            return
        }

        if state.shortcut.matchesModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
            state.isDown = true
            state.pressedAt = eventTime
            state.isInterrupted = false
            state.pressContext = VoiceInkShortcutPressContext()
            if secureInputBlockedActions.contains(action), isSecureInputEnabled {
                state.isBlockedBySecureInput = true
                shortcuts[action] = state
                logger.notice("handleModifierOnlyShortcut: blocking shortcut until release; Secure Input active")
                return
            }

            state.isBlockedBySecureInput = false
            shortcuts[action] = state
            dispatchKeyDown(for: action, eventTime: eventTime)
        }
    }

    private func handleShortcutInterruptions(keyCode: UInt16, eventTime: TimeInterval) {
        guard !Shortcut.isModifierKeyCode(keyCode) else {
            return
        }

        for action in interruptibleActions {
            guard var state = shortcuts[action],
                  state.isDown,
                  !state.isInterrupted,
                  let pressedAt = state.pressedAt,
                  VoiceInkShortcutInterruptionPolicy.isWithinInterruptionWindow(
                    pressedAt: pressedAt,
                    eventTime: eventTime
                  ),
                  state.shortcut.isInterruptedByAdditionalKeyDown(keyCode: keyCode)
            else {
                continue
            }

            state.isInterrupted = true
            shortcuts[action] = state
            dispatchShortcutInterrupted(for: action, eventTime: eventTime)
        }
    }

    private func dispatchKeyDown(for action: ShortcutAction, eventTime: TimeInterval) {
        logger.notice("dispatchKeyDown: action=\(action.storageName, privacy: .public)")
        DispatchQueue.main.async { [onKeyDown] in
            onKeyDown?(action, eventTime)
        }
    }

    private func dispatchKeyUp(for action: ShortcutAction, eventTime: TimeInterval, context: VoiceInkShortcutPressContext) {
        logger.notice("dispatchKeyUp: action=\(action.storageName, privacy: .public)")
        DispatchQueue.main.async { [onKeyUp] in
            onKeyUp?(action, eventTime, context)
        }
    }

    private func dispatchPressContextChanged(for action: ShortcutAction, context: VoiceInkShortcutPressContext) {
        DispatchQueue.main.async { [onPressContextChanged] in
            onPressContextChanged?(action, context)
        }
    }

    private func dispatchShortcutInterrupted(for action: ShortcutAction, eventTime: TimeInterval) {
        logger.notice("dispatchShortcutInterrupted: action=\(action.storageName, privacy: .public)")
        DispatchQueue.main.async { [onShortcutInterrupted] in
            onShortcutInterrupted?(action, eventTime)
        }
    }

    private static let eventMask: CGEventMask = [
        CGEventType.keyDown.rawValue,
        CGEventType.keyUp.rawValue,
        CGEventType.flagsChanged.rawValue,
        systemDefinedCGEventTypeRawValue
    ].reduce(CGEventMask(0)) { mask, rawValue in
        mask | (CGEventMask(1) << Int(rawValue))
    }
}

private extension ShortcutMonitor.EventKind {
    init?(_ type: CGEventType) {
        if type.rawValue == systemDefinedCGEventTypeRawValue {
            self = .systemDefined
            return
        }

        switch type {
        case .keyDown:
            self = .keyDown
        case .keyUp:
            self = .keyUp
        case .flagsChanged:
            self = .flagsChanged
        default:
            return nil
        }
    }

    init?(_ type: NSEvent.EventType) {
        switch type {
        case .keyDown:
            self = .keyDown
        case .keyUp:
            self = .keyUp
        case .flagsChanged:
            self = .flagsChanged
        case .systemDefined:
            self = .systemDefined
        default:
            return nil
        }
    }
}

#if DEBUG
extension ShortcutMonitor {
    static func configurePermissionClientsForTesting(
        inputMonitoringClient: InputMonitoringPermission.Client = InputMonitoringPermission.systemClient,
        accessibilityClient: AccessibilityPermission.Client = AccessibilityPermission.systemClient
    ) {
        self.inputMonitoringClient = inputMonitoringClient
        self.accessibilityClient = accessibilityClient
        hasRequestedListenEventAccess = false
        hasRequestedAccessibilityAccess = false
    }

    static func resetPermissionClientsForTesting() {
        configurePermissionClientsForTesting()
    }

    static func configureSecureEventInputClientForTesting(
        _ secureEventInputClient: SecureEventInputState.Client
    ) {
        self.secureEventInputClient = secureEventInputClient
    }

    static func resetSecureEventInputClientForTesting() {
        secureEventInputClient = SecureEventInputState.systemClient
    }

    static func configureKeyboardStateClientForTesting(
        _ keyboardStateClient: KeyboardState.Client
    ) {
        self.keyboardStateClient = keyboardStateClient
    }

    static func resetKeyboardStateClientForTesting() {
        keyboardStateClient = KeyboardState.systemClient
    }

    func configureForTesting(
        shortcuts: [ShortcutAction: Shortcut],
        interruptibleActions: Set<ShortcutAction> = [],
        secureInputBlockedActions: Set<ShortcutAction> = [],
        handlesModifierOnlyShortcutsInEventTap: Bool = false,
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval, VoiceInkShortcutPressContext) -> Void,
        onPressContextChanged: ((ShortcutAction, VoiceInkShortcutPressContext) -> Void)? = nil,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil
    ) {
        stop()

        for (action, shortcut) in shortcuts {
            self.shortcuts[action] = ShortcutState(shortcut: shortcut)
        }

        self.interruptibleActions = interruptibleActions
        self.secureInputBlockedActions = secureInputBlockedActions
        self.handlesModifierOnlyShortcutsInEventTap = handlesModifierOnlyShortcutsInEventTap
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onPressContextChanged = onPressContextChanged
        self.onShortcutInterrupted = onShortcutInterrupted
    }

    @discardableResult
    func handleKeyDownForTesting(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) -> Bool {
        handleEvent(
            kind: .keyDown,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: eventTime
        )
    }

    @discardableResult
    func handleKeyUpForTesting(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) -> Bool {
        handleEvent(
            kind: .keyUp,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: eventTime
        )
    }

    @discardableResult
    func handleModifierOnlyFlagsChangedForTesting(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) -> Bool {
        handleEvent(
            kind: .flagsChanged,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: eventTime,
            scope: .modifierOnly
        )
    }

    @discardableResult
    func handleEventTapFlagsChangedForTesting(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) -> Bool {
        handleEvent(
            kind: .flagsChanged,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: eventTime,
            scope: handlesModifierOnlyShortcutsInEventTap ? .all : .nonModifierOnly
        )
    }

    @discardableResult
    func handleSystemDefinedForTesting(eventTime: TimeInterval) -> Bool {
        handleEvent(
            kind: .systemDefined,
            keyCode: 0,
            modifierFlags: [],
            eventTime: eventTime
        )
    }
}
#endif
