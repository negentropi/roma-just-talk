import Foundation
import AppKit
import Carbon.HIToolbox
import os
import VoiceInkCore

struct SpecialShortcutOptions: Equatable {
    var pasteLastTranscriptOnEmptyTap = VoiceInkPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
    var doubleShiftTapIntervalMilliseconds = VoiceInkPreferenceDefault.specialShortcutDoubleShiftTapInterval

    var doubleShiftTapInterval: TimeInterval { Double(doubleShiftTapIntervalMilliseconds) / 1_000 }
}

struct SpecialShortcutOwner {
    let action: ShortcutAction
    let shortcut: Shortcut

    func matchesBareShift(_ keyCode: UInt16) -> Bool {
        shortcut.isModifierOnly && shortcut.modifierFlags == [.shift] &&
            (shortcut.keyCode == keyCode || shortcut.keyCode == UInt16.max)
    }
}

@MainActor
class RecordingShortcutManager: ObservableObject {
    @Published var primaryRecordingShortcut: ShortcutSelection {
        didSet {
            VoiceInkRecordingShortcutPreference.saveSelection(primaryRecordingShortcut, for: .primary)
            refreshShortcutMonitoring()
        }
    }
    @Published var secondaryRecordingShortcut: ShortcutSelection {
        didSet {
            if secondaryRecordingShortcut == .none {
                ShortcutStore.setShortcut(nil, for: .secondaryRecording)
            }
            VoiceInkRecordingShortcutPreference.saveSelection(secondaryRecordingShortcut, for: .secondary)
            refreshShortcutMonitoring()
        }
    }
    @Published var primaryRecordingShortcutMode: Mode {
        didSet {
            VoiceInkRecordingShortcutPreference.saveMode(primaryRecordingShortcutMode, for: .primary)
            primaryRecordingShortcutModeSource.primaryMode = primaryRecordingShortcutMode
            refreshShortcutMonitoring()
            NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
        }
    }
    @Published var secondaryRecordingShortcutMode: Mode {
        didSet {
            VoiceInkRecordingShortcutPreference.saveMode(secondaryRecordingShortcutMode, for: .secondary)
            refreshShortcutMonitoring()
        }
    }
    @Published var isMiddleClickToggleEnabled: Bool {
        didSet {
            VoiceInkRecordingShortcutPreference.saveMiddleClickToggleEnabled(isMiddleClickToggleEnabled)
            refreshShortcutMonitoring()
        }
    }
    @Published var middleClickActivationDelay: Int {
        didSet {
            let normalizedDelay = VoiceInkRecordingShortcutPreference.normalizedMiddleClickActivationDelay(
                middleClickActivationDelay
            )
            if normalizedDelay != middleClickActivationDelay {
                middleClickActivationDelay = normalizedDelay
            }
            VoiceInkRecordingShortcutPreference.saveMiddleClickActivationDelay(normalizedDelay)
        }
    }
    @Published var specialShortcutPasteLastTranscriptOnEmptyTap: Bool {
        didSet {
            VoiceInkRecordingShortcutPreference.saveShouldPasteLastTranscriptOnEmptyTap(specialShortcutPasteLastTranscriptOnEmptyTap)
            specialOptionsSource.options = specialOptions
        }
    }
    
    @Published var specialShortcutDoubleShiftTapInterval: Int {
        didSet {
            let interval = VoiceInkRecordingShortcutPreference.normalizedDoubleShiftTapInterval(specialShortcutDoubleShiftTapInterval)
            if interval != specialShortcutDoubleShiftTapInterval { specialShortcutDoubleShiftTapInterval = interval }
            VoiceInkRecordingShortcutPreference.saveDoubleShiftTapInterval(interval)
            specialOptionsSource.options = specialOptions
            refreshShortcutMonitoring()
        }
    }
    private var shortcutMonitoringGeneration: UInt64 = 0

    private var engine: VoiceInkEngine
    private var recorderUIManager: RecorderUIManager
    private var miniRecorderShortcutManager: MiniRecorderShortcutManager
    private let powerModeShortcutManager: PowerModeShortcutManager
    private let shortcutMonitor = ShortcutMonitor()
    private var shortcutChangeObserver: NSObjectProtocol?
    private var permissionChangeObserver: NSObjectProtocol?
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private let primaryRecordingShortcutModeSource: RecordingShortcutModeSource
    private let specialOptionsSource: RecordingShortcutSpecialOptionsSource
    private var hasShownInputMonitoringPermissionNotification = false
    private var hasShownAccessibilityPermissionNotification = false
    private var hasShownShortcutMonitorFailureNotification = false

    // MARK: - Helper Properties
    private var canHandleShortcutAction: Bool {
        Self.canHandleShortcutAction(for: engine.recordingState)
    }
    
    // Middle-click event monitoring
    private var middleClickMonitors: [Any?] = []
    private var middleClickTask: Task<Void, Never>?

    typealias Mode = VoiceInkRecordingShortcutMode
    typealias ShortcutSelection = VoiceInkRecordingShortcutSelection

    private static func canHandleShortcutAction(for recordingState: VoiceInkRecordingState) -> Bool {
        recordingState.acceptsRecordingShortcutAction
    }

    init(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) {
        ShortcutMigration.migrateLegacyShortcutsIfNeeded()

        self.primaryRecordingShortcut = ShortcutMigration.migrateShortcutSelection(
            action: .primaryRecording,
            allowsNone: false
        )
        self.secondaryRecordingShortcut = ShortcutMigration.migrateShortcutSelection(
            action: .secondaryRecording,
            allowsNone: true
        )

        let primaryRecordingShortcutMode = ShortcutMigration.migrateShortcutMode(
            for: .primaryRecording
        )
        self.primaryRecordingShortcutMode = primaryRecordingShortcutMode
        self.secondaryRecordingShortcutMode = ShortcutMigration.migrateShortcutMode(
            for: .secondaryRecording
        )

        self.isMiddleClickToggleEnabled = VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled()
        self.middleClickActivationDelay = VoiceInkRecordingShortcutPreference.middleClickActivationDelay()
        let specialPasteLastTranscriptOnEmptyTap = VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap()
        self.specialShortcutPasteLastTranscriptOnEmptyTap = specialPasteLastTranscriptOnEmptyTap
        let doubleShiftTapInterval = VoiceInkRecordingShortcutPreference.doubleShiftTapInterval()
        self.specialShortcutDoubleShiftTapInterval = doubleShiftTapInterval

        let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "RecordingShortcutManager")
        let shortcutModeHandler = RecordingShortcutModeHandler(
            logger: logger,
            canHandleShortcutAction: {
                Self.canHandleShortcutAction(for: engine.recordingState)
            },
            isRecorderVisible: {
                recorderUIManager.isActiveForRecordingShortcut(recordingState: engine.recordingState)
            },
            recordingState: {
                engine.recordingState
            },
            toggleMiniRecorder: { powerModeId in
                await recorderUIManager.toggleMiniRecorder(powerModeId: powerModeId)
            },
            cancelRecording: {
                await recorderUIManager.cancelRecording()
            }
        )

        let primaryRecordingShortcutModeSource = RecordingShortcutModeSource(
            primaryMode: primaryRecordingShortcutMode
        )
        let specialOptionsSource = RecordingShortcutSpecialOptionsSource(
            options: SpecialShortcutOptions(
                pasteLastTranscriptOnEmptyTap: specialPasteLastTranscriptOnEmptyTap,
                doubleShiftTapIntervalMilliseconds: doubleShiftTapInterval
            )
        )

        self.engine = engine
        self.recorderUIManager = recorderUIManager
        self.miniRecorderShortcutManager = MiniRecorderShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
        self.shortcutModeHandler = shortcutModeHandler
        self.primaryRecordingShortcutModeSource = primaryRecordingShortcutModeSource
        self.specialOptionsSource = specialOptionsSource
        self.powerModeShortcutManager = PowerModeShortcutManager(
            modeProvider: {
                primaryRecordingShortcutModeSource.primaryMode
            },
            specialOptionsProvider: {
                specialOptionsSource.options
            },
            shortcutModeHandler: shortcutModeHandler
        )

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshShortcutMonitoring()
            }
        }

        permissionChangeObserver = NotificationCenter.default.addObserver(
            forName: .appPermissionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePermissionChange()
            }
        }

        Task { @MainActor in
            PermissionRefreshCenter.shared.startObservingApplicationActivation()
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.refreshShortcutMonitoring()
        }
    }

    private func handlePermissionChange() {
        if ShortcutMonitor.preflightListenEventAccess() {
            hasShownInputMonitoringPermissionNotification = false
        }

        if ShortcutMonitor.preflightAccessibilityAccess() {
            hasShownAccessibilityPermissionNotification = false
        }

        hasShownShortcutMonitorFailureNotification = false
        refreshShortcutMonitoring()
    }
    
    private func refreshShortcutMonitoring() {
        removeAllMonitoring()
        
        refreshShortcutMonitor()
        setupMiddleClickMonitoring()
    }
    
    private func setupMiddleClickMonitoring() {
        guard isMiddleClickToggleEnabled else { return }

        // Mouse Down
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }

            self.middleClickTask?.cancel()
            self.middleClickTask = Task {
                do {
                    let delayMilliseconds = VoiceInkRecordingShortcutPreference.normalizedMiddleClickActivationDelay(
                        self.middleClickActivationDelay
                    )
                    let delay = UInt64(delayMilliseconds) * 1_000_000 // ms to ns
                    try await Task.sleep(nanoseconds: delay)
                    
                    guard self.isMiddleClickToggleEnabled, !Task.isCancelled else { return }
                    
                    Task { @MainActor in
                        guard self.canHandleShortcutAction else { return }
                        await self.recorderUIManager.toggleMiniRecorder()
                    }
                } catch {
                    // Cancelled
                }
            }
        }

        // Mouse Up
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }
            self.middleClickTask?.cancel()
        }

        middleClickMonitors = [downMonitor, upMonitor]
    }
    
    private func refreshShortcutMonitor() {
        let primaryShortcut = primaryRecordingShortcut == .custom ? ShortcutStore.shortcut(for: .primaryRecording) : nil
        let secondaryShortcut = secondaryRecordingShortcut == .custom ? ShortcutStore.shortcut(for: .secondaryRecording) : nil
        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.globalUtilityActions)
        var interruptibleRecordingActions = Set<ShortcutAction>()

        if let primaryShortcut {
            shortcuts[.primaryRecording] = primaryShortcut
            if primaryRecordingShortcutMode.allowsShortcutInterruption {
                interruptibleRecordingActions.insert(.primaryRecording)
            }
        }

        if let secondaryShortcut {
            shortcuts[.secondaryRecording] = secondaryShortcut
            if secondaryRecordingShortcutMode.allowsShortcutInterruption {
                interruptibleRecordingActions.insert(.secondaryRecording)
            }
        }

        let evidenceTrackedActions = Set(shortcuts.keys.filter {
            recordingMode(for: $0)?.tracksKeyUpEvidence == true
        })

        let specialOwner: SpecialShortcutOwner?
        if specialShortcutDoubleShiftTapInterval > 0, primaryRecordingShortcutMode == .special, let primaryShortcut {
            specialOwner = SpecialShortcutOwner(action: .primaryRecording, shortcut: primaryShortcut)
        } else if specialShortcutDoubleShiftTapInterval > 0, secondaryRecordingShortcutMode == .special, let secondaryShortcut {
            specialOwner = SpecialShortcutOwner(action: .secondaryRecording, shortcut: secondaryShortcut)
        } else {
            specialOwner = nil
        }
        let generation = shortcutMonitoringGeneration

        let isMonitoring = shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: interruptibleRecordingActions,
            secureInputBlockedActions: evidenceTrackedActions,
            tracksKeyUpEvidence: !evidenceTrackedActions.isEmpty || specialOwner != nil,
            onKeyDown: { [weak self] action, eventTime in
                let callbackReceivedAt = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in
                    guard let self, self.shortcutMonitoringGeneration == generation else { return }
                    guard let mode = self.recordingMode(for: action) else { return }
                    await self.shortcutModeHandler.handleKeyDown(
                        action: action,
                        eventTime: eventTime,
                        callbackReceivedAt: callbackReceivedAt,
                        mode: mode,
                        specialOptions: self.specialOptions
                    )
                }
            },
            onKeyUp: { [weak self] action, eventTime, context in
                let callbackReceivedAt = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in
                    guard let self, self.shortcutMonitoringGeneration == generation else { return }
                    if let mode = self.recordingMode(for: action) {
                        await self.shortcutModeHandler.handleKeyUp(
                            action: action,
                            eventTime: eventTime,
                            callbackReceivedAt: callbackReceivedAt,
                            mode: mode,
                            context: context,
                            specialOptions: self.specialOptions
                        )
                    } else {
                        await self.handleGlobalShortcut(action)
                    }
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self, self.shortcutMonitoringGeneration == generation, self.recordingMode(for: action) != nil else { return }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            },
            shiftObservedAction: specialOwner?.action,
            onShiftEvent: specialOwner.map { owner in
                { [weak self] event in
                    let callbackReceivedAt = ProcessInfo.processInfo.systemUptime
                    Task { @MainActor in
                        guard let self, self.shortcutMonitoringGeneration == generation else { return }
                        await self.shortcutModeHandler.handleShiftEvent(event, owner: owner, options: self.specialOptions,
                                                                       callbackReceivedAt: callbackReceivedAt)
                    }
                }
            }
        )

        guard !isMonitoring, !shortcuts.isEmpty else {
            return
        }

        if !ShortcutMonitor.preflightListenEventAccess() {
            guard !PermissionNotificationSuppression.shared.isSuppressingPermissionPrompts else { return }
            guard !hasShownInputMonitoringPermissionNotification else { return }
            hasShownInputMonitoringPermissionNotification = true
            showShortcutSettingsNotification(
                VoiceInkMacOSShortcutNotificationPresentation.inputMonitoringPermissionRequired,
                grant: { PermissionGrantCoordinator.grantInputMonitoring() }
            )
            return
        }

        if !ShortcutMonitor.preflightAccessibilityAccess() {
            guard !PermissionNotificationSuppression.shared.isSuppressingPermissionPrompts else { return }
            guard !hasShownAccessibilityPermissionNotification else { return }
            hasShownAccessibilityPermissionNotification = true
            showShortcutSettingsNotification(
                VoiceInkMacOSShortcutNotificationPresentation.accessibilityPermissionRequired,
                grant: { PermissionGrantCoordinator.grantAccessibility() }
            )
            return
        }

        guard !hasShownShortcutMonitorFailureNotification else { return }
        hasShownShortcutMonitorFailureNotification = true
        let presentation = VoiceInkMacOSShortcutNotificationPresentation.monitorStartFailed
        NotificationManager.shared.showNotification(
            title: presentation.title,
            type: .error,
            duration: presentation.duration
        )
    }

    private func showShortcutSettingsNotification(
        _ presentation: VoiceInkMacOSShortcutNotificationPresentation,
        grant: @escaping @MainActor () -> Void
    ) {
        guard let actionButtonLabel = presentation.actionButtonLabel else {
            return
        }

        NotificationManager.shared.showNotification(
            title: presentation.title,
            type: .warning,
            duration: presentation.duration,
            actionButton: (
                label: actionButtonLabel,
                action: {
                    Task { @MainActor in
                        grant()
                    }
                }
            )
        )
    }

    private func recordingMode(for action: ShortcutAction) -> Mode? {
        switch action {
        case .primaryRecording:
            return primaryRecordingShortcutMode
        case .secondaryRecording:
            return secondaryRecordingShortcutMode
        default:
            return nil
        }
    }

    private var specialOptions: SpecialShortcutOptions {
        SpecialShortcutOptions(
            pasteLastTranscriptOnEmptyTap: specialShortcutPasteLastTranscriptOnEmptyTap,
            doubleShiftTapIntervalMilliseconds: specialShortcutDoubleShiftTapInterval
        )
    }

    private func handleGlobalShortcut(_ action: ShortcutAction) async {
        switch action {
        case .translateRecording:
            await engine.toggleWritingAction(.translate)
        case .rewriteSelectionRecording:
            await engine.toggleWritingAction(.rewriteSelection)
        case .draftRecording:
            await engine.toggleWritingAction(.draft)
        case .pasteLastTranscription:
            LastTranscriptionService.pasteLastTranscription(from: engine.modelContext)
        case .pasteLastEnhancement:
            LastTranscriptionService.pasteLastEnhancement(from: engine.modelContext)
        case .retryLastTranscription:
            LastTranscriptionService.retryLastTranscription(
                from: engine.modelContext,
                transcriptionModelManager: engine.transcriptionModelManager,
                serviceRegistry: engine.serviceRegistry,
                enhancementService: engine.enhancementService
            )
        case .openHistoryWindow:
            HistoryWindowController.shared.showHistoryWindow(
                modelContainer: engine.modelContext.container,
                engine: engine
            )
        case .quickAddToDictionary:
            DictionaryQuickAddManager.shared.toggle(modelContainer: engine.modelContext.container)
        default:
            break
        }
    }

    private func removeAllMonitoring() {
        shortcutMonitoringGeneration &+= 1
        shortcutMonitor.stop()
        
        for monitor in middleClickMonitors {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        middleClickMonitors = []
        middleClickTask?.cancel()
        
        var availableRecordingActions: [ShortcutAction] = []
        if primaryRecordingShortcut == .custom, ShortcutStore.shortcut(for: .primaryRecording) != nil {
            availableRecordingActions.append(.primaryRecording)
        }
        if secondaryRecordingShortcut == .custom, ShortcutStore.shortcut(for: .secondaryRecording) != nil {
            availableRecordingActions.append(.secondaryRecording)
        }
        if VoiceInkPowerModePreference.isUIEnabled() {
            availableRecordingActions += PowerModeManager.shared.configurations.powerModeShortcutEntries { id in
                ShortcutStore.shortcut(for: .powerMode(id))
            }.map { .powerMode($0.configuration.id) }
        }
        shortcutModeHandler.resetForMonitorRefresh(availableRecordingActions: availableRecordingActions)
    }
    
    var isShortcutConfigured: Bool {
        let isPrimaryShortcutConfigured = primaryRecordingShortcut != .none && ShortcutStore.shortcut(for: .primaryRecording) != nil
        let isSecondaryShortcutConfigured = secondaryRecordingShortcut == .none || ShortcutStore.shortcut(for: .secondaryRecording) != nil
        return isPrimaryShortcutConfigured && isSecondaryShortcutConfigured
    }
    
    func updateShortcutStatus() {
        // Called when a shortcut changes
        refreshShortcutMonitoring()
    }
    
    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }

        if let permissionChangeObserver {
            NotificationCenter.default.removeObserver(permissionChangeObserver)
        }

        MainActor.assumeIsolated {
            removeAllMonitoring()
        }
    }
}

@MainActor
private final class RecordingShortcutModeSource {
    var primaryMode: RecordingShortcutManager.Mode

    init(primaryMode: RecordingShortcutManager.Mode) {
        self.primaryMode = primaryMode
    }
}

@MainActor
private final class RecordingShortcutSpecialOptionsSource {
    var options: SpecialShortcutOptions

    init(options: SpecialShortcutOptions) {
        self.options = options
    }
}

@MainActor
final class RecordingShortcutModeHandler {
    private let logger: Logger
    private let canHandleShortcutAction: @MainActor () -> Bool
    private let isRecorderVisible: @MainActor () -> Bool
    private let recordingState: @MainActor () -> VoiceInkRecordingState
    private let toggleMiniRecorder: @MainActor (UUID?) async -> Void
    private let cancelRecording: @MainActor () async -> Void

    private var shortcutPressStartTime: TimeInterval?
    private var isHandsFreeRecording = false
    private var isShortcutPressed = false
    private var activeRecordingShortcutAction: ShortcutAction?
    private var interruptedRecordingActions = Set<ShortcutAction>()
    private var activeShortcutCanCancelAccidentalStart = false
    private var lastShortcutPressTime: Date?
    private var activeLatencyTraceToken: VoiceInkLatencyTrace.Token?

    private final class SpecialSession {
        enum Origin { case started, existing }
        enum Startup { case pending, complete }
        var action: ShortcutAction
        let options: SpecialShortcutOptions
        let powerModeId: UUID?
        let origin: Origin
        var startup: Startup

        init(action: ShortcutAction, options: SpecialShortcutOptions,
             powerModeId: UUID?, origin: Origin) {
            self.action = action
            self.options = options
            self.powerModeId = powerModeId
            self.origin = origin
            self.startup = origin == .started ? .pending : .complete
        }
    }

    private struct ShiftPress {
        let keyCode: UInt16
        let downAt: TimeInterval
    }

    private enum SpecialInteraction {
        case idle
        case firstShiftHeld(ShiftPress, SpecialSession?)
        case awaitingSecondShift(ShiftPress, SpecialSession?, releasedAt: TimeInterval, ticket: UInt64)
        case secondShiftHeld(ShiftPress, SpecialSession?)
        case held(SpecialSession, downAt: TimeInterval)
        case latched(SpecialSession)
        case finishHeld(SpecialSession, downAt: TimeInterval)
        case stopping(SpecialSession)

        var session: SpecialSession? {
            switch self {
            case .idle: return nil
            case .firstShiftHeld(_, let session), .awaitingSecondShift(_, let session, _, _),
                 .secondShiftHeld(_, let session): return session
            case .held(let session, _), .latched(let session), .finishHeld(let session, _),
                 .stopping(let session): return session
            }
        }
    }

    private var specialInteraction = SpecialInteraction.idle
    private var specialReleaseTask: Task<Void, Never>?
    private var specialGeneration: UInt64 = 0
    private let sleepForSpecialRelease: @MainActor (TimeInterval) async throws -> Void
    private let scheduleEmptyFallback: @MainActor () -> Void

    init(
        logger: Logger,
        canHandleShortcutAction: @escaping @MainActor () -> Bool,
        isRecorderVisible: @escaping @MainActor () -> Bool,
        recordingState: @escaping @MainActor () -> VoiceInkRecordingState,
        toggleMiniRecorder: @escaping @MainActor (UUID?) async -> Void,
        cancelRecording: @escaping @MainActor () async -> Void,
        sleepForSpecialRelease: @escaping @MainActor (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        },
        scheduleEmptyFallback: @escaping @MainActor () -> Void = { SpecialShortcutEmptyTranscriptionFallback.scheduleFallback() }
    ) {
        self.logger = logger
        self.canHandleShortcutAction = canHandleShortcutAction
        self.isRecorderVisible = isRecorderVisible
        self.recordingState = recordingState
        self.toggleMiniRecorder = toggleMiniRecorder
        self.cancelRecording = cancelRecording
        self.sleepForSpecialRelease = sleepForSpecialRelease
        self.scheduleEmptyFallback = scheduleEmptyFallback
    }

    func reset() {
        specialGeneration &+= 1
        specialReleaseTask?.cancel()
        specialReleaseTask = nil
        specialInteraction = .idle
        isShortcutPressed = false
        shortcutPressStartTime = nil
        isHandsFreeRecording = false
        activeRecordingShortcutAction = nil
        interruptedRecordingActions.removeAll()
        activeShortcutCanCancelAccidentalStart = false
        activeLatencyTraceToken = nil
    }

    func handleKeyDown(
        action: ShortcutAction,
        eventTime: TimeInterval,
        callbackReceivedAt: TimeInterval? = nil,
        mode: RecordingShortcutManager.Mode,
        specialOptions: SpecialShortcutOptions = SpecialShortcutOptions(),
        powerModeId: UUID? = nil
    ) async {
        specialGeneration &+= 1
        reconcileSpecialRecording()
        switch specialInteraction {
        case .firstShiftHeld(_, nil), .awaitingSecondShift(_, nil, _, _), .secondShiftHeld(_, nil):
            specialReleaseTask?.cancel()
            specialReleaseTask = nil
            specialInteraction = .idle
        default:
            break
        }
        if case .latched(let session) = specialInteraction, session.action == action {
            specialInteraction = .finishHeld(session, downAt: eventTime)
            return
        }
        if mode == .special {
            await handleSpecialKeyDown(action: action, eventTime: eventTime,
                                       callbackReceivedAt: callbackReceivedAt ?? eventTime,
                                       options: specialOptions, powerModeId: powerModeId)
            return
        }
        guard specialInteraction.session == nil else { return }

        if interruptedRecordingActions.remove(action) != nil {
            return
        }

        let now = Date()
        if VoiceInkRecordingShortcutTimingPolicy.isPressWithinCooldown(
            lastPressTime: lastShortcutPressTime,
            now: now
        ) {
            return
        }

        guard !isShortcutPressed else { return }
        isShortcutPressed = true
        activeRecordingShortcutAction = action
        activeShortcutCanCancelAccidentalStart = canCurrentShortcutPressCancelAccidentalStart
        lastShortcutPressTime = now
        shortcutPressStartTime = eventTime

        switch mode {
        case .special:
            break

        case .pushToTalk:
            await startRecordingIfNeeded(
                mode: mode,
                eventTime: eventTime,
                callbackReceivedAt: callbackReceivedAt ?? eventTime,
                powerModeId: powerModeId
            )

        case .toggle, .hybrid:
            if isHandsFreeRecording {
                isHandsFreeRecording = false
                guard canHandleShortcutAction() else { return }
                let traceToken = activeLatencyTraceToken ?? VoiceInkLatencyTrace.shared.currentToken()
                activeLatencyTraceToken = traceToken
                let handlerEnteredAt = ProcessInfo.processInfo.systemUptime
                VoiceInkLatencyTrace.shared.event(
                    "shortcut.key_down_stop_handler",
                    details: shortcutDispatchDetails(
                        eventTime: eventTime,
                        callbackReceivedAt: callbackReceivedAt ?? eventTime,
                        handlerEnteredAt: handlerEnteredAt,
                        traceToken: traceToken
                    ),
                    token: traceToken
                )
                logger.notice("handleShortcutKeyDown: toggling mini recorder (hands-free toggle)")
                await toggleMiniRecorder(powerModeId)
                return
            }

            await startRecordingIfNeeded(
                mode: mode,
                eventTime: eventTime,
                callbackReceivedAt: callbackReceivedAt ?? eventTime,
                powerModeId: powerModeId
            )
        }
    }

    func handleKeyUp(
        action: ShortcutAction,
        eventTime: TimeInterval,
        callbackReceivedAt: TimeInterval? = nil,
        mode: RecordingShortcutManager.Mode,
        context: VoiceInkShortcutPressContext = VoiceInkShortcutPressContext(),
        specialOptions: SpecialShortcutOptions = SpecialShortcutOptions(),
        powerModeId: UUID? = nil
    ) async {
        specialGeneration &+= 1
        reconcileSpecialRecording()
        if case .finishHeld(let session, _) = specialInteraction, session.action == action {
            await handleSpecialKeyUp(action: action, eventTime: eventTime, context: context,
                                     callbackReceivedAt: callbackReceivedAt ?? eventTime)
            return
        }
        if mode == .special {
            await handleSpecialKeyUp(action: action, eventTime: eventTime, context: context,
                                     callbackReceivedAt: callbackReceivedAt ?? eventTime)
            return
        }

        guard isShortcutPressed, activeRecordingShortcutAction == action else { return }
        let pressDuration = shortcutPressStartTime.map { eventTime - $0 } ?? 0
        traceKeyUp(action: action, eventTime: eventTime, callbackReceivedAt: callbackReceivedAt ?? eventTime,
                   mode: mode, pressDuration: pressDuration, context: context)
        isShortcutPressed = false
        activeRecordingShortcutAction = nil
        activeShortcutCanCancelAccidentalStart = false
        switch mode {
        case .special:
            break

        case .toggle:
            isHandsFreeRecording = true

        case .pushToTalk:
            if isRecorderVisible() {
                guard canHandleShortcutAction() else { return }
                logger.notice("handleShortcutKeyUp: stopping recording (push-to-talk key up)")
                await toggleMiniRecorder(powerModeId)
            }

        case .hybrid:
            let pressDuration = shortcutPressStartTime.map { eventTime - $0 } ?? 0
            if VoiceInkRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: pressDuration,
                recordingState: recordingState()
            ) {
                guard canHandleShortcutAction() else { return }
                logger.notice("handleShortcutKeyUp: stopping recording (hybrid push-to-talk, duration=\(pressDuration, privacy: .public)s)")
                await toggleMiniRecorder(powerModeId)
            } else {
                isHandsFreeRecording = true
            }
        }

        shortcutPressStartTime = nil
        if !isHandsFreeRecording {
            activeLatencyTraceToken = nil
        }
    }

    func resetForMonitorRefresh(availableRecordingActions: [ShortcutAction]) {
        reconcileSpecialRecording()
        let interaction = specialInteraction
        reset()
        if case .stopping = interaction {
            specialInteraction = interaction
        } else if let session = interaction.session, session.startup == .pending || isRecorderVisible() {
            if !availableRecordingActions.contains(session.action), let fallback = availableRecordingActions.first {
                session.action = fallback
            }
            specialInteraction = .latched(session)
        }
    }

    private func reconcileSpecialRecording() {
        if case .stopping = specialInteraction { return }
        guard let session = specialInteraction.session,
              session.startup == .complete,
              !isRecorderVisible(), recordingState() == .idle else { return }
        specialGeneration &+= 1
        specialReleaseTask?.cancel()
        specialReleaseTask = nil
        specialInteraction = .idle
    }

    private func makeSpecialSession(action: ShortcutAction, options: SpecialShortcutOptions,
                                    powerModeId: UUID? = nil) -> SpecialSession {
        return SpecialSession(action: action, options: options,
                              powerModeId: powerModeId, origin: isRecorderVisible() ? .existing : .started)
    }

    private func handleSpecialKeyDown(action: ShortcutAction, eventTime: TimeInterval,
                                      callbackReceivedAt: TimeInterval, options: SpecialShortcutOptions,
                                      powerModeId: UUID?) async {
        switch specialInteraction {
        case .latched(let session) where session.action == action:
            specialInteraction = .finishHeld(session, downAt: eventTime)
        case .idle:
            guard !isShortcutPressed, canHandleShortcutAction() else { return }
            let session = makeSpecialSession(action: action, options: options, powerModeId: powerModeId)
            specialInteraction = .held(session, downAt: eventTime)
            await startSpecialRecording(session, eventTime: eventTime, callbackReceivedAt: callbackReceivedAt)
        default:
            break
        }
    }

    private func handleSpecialKeyUp(action: ShortcutAction, eventTime: TimeInterval,
                                    context: VoiceInkShortcutPressContext, callbackReceivedAt: TimeInterval) async {
        traceSpecialKeyUp(action: action, eventTime: eventTime, callbackReceivedAt: callbackReceivedAt, context: context)
        switch specialInteraction {
        case .held(let session, let downAt) where session.action == action:
            if VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(for: context) {
                await rejectSpecialInteraction(context: context)
            } else {
                await finishSpecialRecording(session, emptyTapDuration: eventTime - downAt)
            }
        case .finishHeld(let session, _) where session.action == action:
            if VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(for: context) {
                traceRejectedSpecialEvidence(context)
                specialInteraction = .latched(session)
            } else {
                await finishSpecialRecording(session)
            }
        default:
            break
        }
    }

    func handleShiftEvent(_ event: ShiftShortcutEvent, owner: SpecialShortcutOwner,
                          options: SpecialShortcutOptions, callbackReceivedAt: TimeInterval? = nil) async {
        reconcileSpecialRecording()
        specialGeneration &+= 1
        let eventTicket = specialGeneration
        let callbackTime = callbackReceivedAt ?? event.time
        if event.edge == .up, owner.matchesBareShift(event.keyCode) {
            traceSpecialKeyUp(action: owner.action, eventTime: event.time, callbackReceivedAt: callbackTime,
                              context: event.context)
        }
        guard options.doubleShiftTapInterval > 0 else { return }
        if event.edge == .invalidated {
            switch specialInteraction {
            case .held:
                return
            case .finishHeld where !(owner.shortcut.isModifierOnly && owner.shortcut.modifierFlags == [.shift]):
                return
            default:
                break
            }
            await rejectSpecialInteraction(context: event.context)
            return
        }
        if VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(for: event.context) {
            await rejectSpecialInteraction(context: event.context)
            return
        }

        switch (specialInteraction, event.edge) {
        case (.held(let session, let downAt), .up):
            if session.action == owner.action, owner.matchesBareShift(event.keyCode) {
                await finishSpecialRecording(session, emptyTapDuration: event.time - downAt)
            }
        case (.latched(let session), .down):
            if session.action == owner.action, owner.matchesBareShift(event.keyCode) {
                specialInteraction = .finishHeld(session, downAt: event.time)
            }
        case (.finishHeld(let session, _), .up):
            if owner.matchesBareShift(event.keyCode) {
                await finishSpecialRecording(session)
            }
        case (.idle, .down):
            guard !isShortcutPressed, canHandleShortcutAction() else { return }
            if isRecorderVisible(), owner.matchesBareShift(event.keyCode) {
                specialInteraction = .held(makeSpecialSession(action: owner.action, options: options), downAt: event.time)
                return
            }
            guard !isRecorderVisible(), recordingState() == .idle else { return }
            let session = owner.matchesBareShift(event.keyCode)
                ? makeSpecialSession(action: owner.action, options: options) : nil
            specialInteraction = .firstShiftHeld(ShiftPress(keyCode: event.keyCode, downAt: event.time), session)
            if let session {
                await startSpecialRecording(session, eventTime: event.time, callbackReceivedAt: callbackTime)
            }
        case (.firstShiftHeld(let press, let session), .up) where press.keyCode == event.keyCode:
            let interval = session?.options.doubleShiftTapInterval ?? options.doubleShiftTapInterval
            if event.time - press.downAt <= interval {
                specialGeneration &+= 1
                let ticket = specialGeneration
                specialInteraction = .awaitingSecondShift(press, session, releasedAt: event.time, ticket: ticket)
                specialReleaseTask = Task { [weak self, sleepForSpecialRelease] in
                    do {
                        try await sleepForSpecialRelease(interval)
                        guard !Task.isCancelled else { return }
                        await self?.expireSpecialShiftRelease(ticket: ticket)
                    } catch {}
                }
            } else if let session {
                await finishSpecialRecording(session, emptyTapDuration: event.time - press.downAt)
            } else {
                specialInteraction = .idle
            }
        case (.awaitingSecondShift(let first, let session, let releasedAt, let ticket), .down):
            let interval = session?.options.doubleShiftTapInterval ?? options.doubleShiftTapInterval
            if first.keyCode == event.keyCode, event.time >= releasedAt, event.time - releasedAt < interval {
                specialReleaseTask?.cancel()
                specialReleaseTask = nil
                specialInteraction = .secondShiftHeld(ShiftPress(keyCode: event.keyCode, downAt: event.time), session)
            } else {
                await expireSpecialShiftRelease(ticket: ticket)
                guard specialGeneration == eventTicket else { return }
                await handleShiftEvent(event, owner: owner, options: options, callbackReceivedAt: callbackTime)
            }
        case (.secondShiftHeld(let press, let session), .up) where press.keyCode == event.keyCode:
            let interval = session?.options.doubleShiftTapInterval ?? options.doubleShiftTapInterval
            if event.time - press.downAt <= interval {
                if let session {
                    specialInteraction = .latched(session)
                } else {
                    guard !isRecorderVisible(), recordingState() == .idle, canHandleShortcutAction() else {
                        specialInteraction = .idle
                        return
                    }
                    let session = makeSpecialSession(action: owner.action, options: options)
                    specialInteraction = .latched(session)
                    await startSpecialRecording(session, eventTime: event.time, callbackReceivedAt: callbackTime)
                }
            } else if let session {
                await finishSpecialRecording(session)
            } else {
                specialInteraction = .idle
            }
        default:
            break
        }
    }

    private func expireSpecialShiftRelease(ticket: UInt64) async {
        guard case .awaitingSecondShift(let press, let session, let releasedAt, let currentTicket) = specialInteraction,
              ticket == currentTicket else { return }
        specialReleaseTask?.cancel()
        specialReleaseTask = nil
        if let session {
            await finishSpecialRecording(session, emptyTapDuration: releasedAt - press.downAt)
        } else {
            specialInteraction = .idle
        }
    }

    private func rejectSpecialInteraction(context: VoiceInkShortcutPressContext) async {
        switch specialInteraction {
        case .idle, .latched, .stopping:
            break
        default:
            traceRejectedSpecialEvidence(context)
        }
        switch specialInteraction {
        case .finishHeld(let session, _):
            specialInteraction = .latched(session)
        case .firstShiftHeld(_, let session), .awaitingSecondShift(_, let session, _, _),
             .secondShiftHeld(_, let session):
            await discardSpecialSession(session)
        case .held(let session, _):
            await discardSpecialSession(session)
        case .idle, .latched, .stopping:
            break
        }
    }

    private func discardSpecialSession(_ session: SpecialSession?) async {
        specialReleaseTask?.cancel()
        specialReleaseTask = nil
        guard let session, session.origin == .started else {
            specialInteraction = .idle
            return
        }
        specialInteraction = .stopping(session)
        await cancelRecording()
        if specialInteraction.session === session {
            specialInteraction = .idle
            activeLatencyTraceToken = nil
        }
    }

    private func startSpecialRecording(_ session: SpecialSession, eventTime: TimeInterval,
                                       callbackReceivedAt: TimeInterval) async {
        guard session.origin == .started else { return }
        await startRecordingIfNeeded(mode: .special, eventTime: eventTime,
                                     callbackReceivedAt: callbackReceivedAt, powerModeId: session.powerModeId)
        session.startup = .complete
        if specialInteraction.session === session { reconcileSpecialRecording() }
    }

    private func finishSpecialRecording(_ session: SpecialSession, emptyTapDuration: TimeInterval? = nil) async {
        guard specialInteraction.session === session, canHandleShortcutAction(),
              isRecorderVisible() || session.startup == .pending else { return }
        specialReleaseTask?.cancel()
        specialReleaseTask = nil
        specialInteraction = .stopping(session)
        isHandsFreeRecording = false
        if session.options.pasteLastTranscriptOnEmptyTap, let emptyTapDuration,
           VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: emptyTapDuration) {
            scheduleEmptyFallback()
        }
        await toggleMiniRecorder(session.powerModeId)
        if specialInteraction.session === session {
            specialInteraction = .idle
            activeLatencyTraceToken = nil
        }
    }

    private func traceSpecialKeyUp(action: ShortcutAction, eventTime: TimeInterval,
                                   callbackReceivedAt: TimeInterval, context: VoiceInkShortcutPressContext) {
        let session: SpecialSession
        let downAt: TimeInterval
        switch specialInteraction {
        case .firstShiftHeld(let press, .some(let current)), .secondShiftHeld(let press, .some(let current)):
            session = current
            downAt = press.downAt
        case .held(let current, let pressedAt), .finishHeld(let current, let pressedAt):
            session = current
            downAt = pressedAt
        default:
            return
        }
        guard session.action == action else { return }
        traceKeyUp(action: action, eventTime: eventTime, callbackReceivedAt: callbackReceivedAt,
                   mode: .special, pressDuration: eventTime - downAt, context: context)
    }

    private func traceKeyUp(action: ShortcutAction, eventTime: TimeInterval, callbackReceivedAt: TimeInterval,
                            mode: RecordingShortcutManager.Mode, pressDuration: TimeInterval,
                            context: VoiceInkShortcutPressContext) {
        let handlerEnteredAt = ProcessInfo.processInfo.systemUptime
        let pressDurationMilliseconds = String(format: "%.1f", pressDuration * 1_000)
        let keyEvidenceDetails = Self.keyEvidenceTraceDetails(context)
        VoiceInkLatencyTrace.shared.event(
            "shortcut.key_up_handler",
            details: "action=\(action.storageName) mode=\(mode.rawValue) sourceTMs=\(pressDurationMilliseconds) sourceToCallbackMs=\(String(format: "%.1f", max(0, callbackReceivedAt - eventTime) * 1_000)) callbackToHandlerMs=\(String(format: "%.1f", max(0, handlerEnteredAt - callbackReceivedAt) * 1_000)) state=\(String(describing: recordingState())) \(keyEvidenceDetails)",
            token: activeLatencyTraceToken
        )
    }

    private func traceRejectedSpecialEvidence(_ context: VoiceInkShortcutPressContext) {
        VoiceInkLatencyTrace.shared.event("shortcut.key_evidence_rejected",
                                         details: Self.keyEvidenceTraceDetails(context), token: activeLatencyTraceToken)
    }

    nonisolated static func keyEvidenceTraceDetails(_ context: VoiceInkShortcutPressContext) -> String {
        "pressedOtherKey=\(context.didPressOtherKeyDuringPress) releasedOtherKey=\(context.didReleaseOtherKeyDuringPress) reliable=\(context.hasReliableKeyEvidence)"
    }

    func handleInterruption(action: ShortcutAction) async {
        if specialInteraction.session?.action == action {
            await rejectSpecialInteraction(context: VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true))
            return
        }
        guard isShortcutPressed, activeRecordingShortcutAction == action else {
            if canCurrentShortcutPressCancelAccidentalStart {
                interruptedRecordingActions.insert(action)
            }
            return
        }

        guard activeShortcutCanCancelAccidentalStart else { return }

        logger.notice("handleShortcutInterruption: cancelling recording shortcut that became part of a larger key chord")
        reset()
        await cancelRecording()
    }

    private var canCurrentShortcutPressCancelAccidentalStart: Bool {
        !isRecorderVisible() && recordingState() == .idle
    }

    private func startRecordingIfNeeded(
        mode: RecordingShortcutManager.Mode,
        eventTime: TimeInterval,
        callbackReceivedAt: TimeInterval,
        powerModeId: UUID?
    ) async {
        if !isRecorderVisible() {
            guard canHandleShortcutAction() else { return }
            let handlerEnteredAt = ProcessInfo.processInfo.systemUptime
            let traceToken = VoiceInkLatencyTrace.shared.start(
                event: "shortcut.key_down_physical",
                details: "mode=\(mode.rawValue) state=\(String(describing: recordingState()))",
                originTimestamp: eventTime
            )
            activeLatencyTraceToken = traceToken
            VoiceInkLatencyTrace.shared.event(
                "shortcut.key_down_handler",
                details: shortcutDispatchDetails(
                    eventTime: eventTime,
                    callbackReceivedAt: callbackReceivedAt,
                    handlerEnteredAt: handlerEnteredAt,
                    traceToken: traceToken
                ),
                token: traceToken
            )
            logger.notice("handleShortcutKeyDown: starting recording (\(mode.rawValue, privacy: .public) key down)")
            let span = VoiceInkLatencyTrace.shared.begin("shortcut.start_handler", token: traceToken)
            await toggleMiniRecorder(powerModeId)
            VoiceInkLatencyTrace.shared.end(span)
        }
    }

    private func shortcutDispatchDetails(
        eventTime: TimeInterval,
        callbackReceivedAt: TimeInterval,
        handlerEnteredAt: TimeInterval,
        traceToken: VoiceInkLatencyTrace.Token?
    ) -> String {
        let sourceTMilliseconds = VoiceInkLatencyTrace.shared.elapsedMilliseconds(
            token: traceToken,
            at: eventTime
        ) ?? 0
        return "sourceTMs=\(String(format: "%.1f", sourceTMilliseconds)) sourceToCallbackMs=\(String(format: "%.1f", max(0, callbackReceivedAt - eventTime) * 1_000)) callbackToHandlerMs=\(String(format: "%.1f", max(0, handlerEnteredAt - callbackReceivedAt) * 1_000))"
    }

}
