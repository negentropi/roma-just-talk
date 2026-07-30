import Foundation
import AppKit
import os
import VoiceInkCore

struct SpecialShortcutOptions: Equatable {
    var pasteLastTranscriptOnEmptyTap = VoiceInkPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
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
                pasteLastTranscriptOnEmptyTap: specialPasteLastTranscriptOnEmptyTap
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

        let isMonitoring = shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: interruptibleRecordingActions,
            secureInputBlockedActions: evidenceTrackedActions,
            tracksKeyUpEvidence: !evidenceTrackedActions.isEmpty,
            onKeyDown: { [weak self] action, eventTime in
                let callbackReceivedAt = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in
                    guard let self else { return }
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
                    guard let self else { return }
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
                    guard let self, self.recordingMode(for: action) != nil else { return }
                    await self.shortcutModeHandler.handleInterruption(action: action)
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
            pasteLastTranscriptOnEmptyTap: specialShortcutPasteLastTranscriptOnEmptyTap
        )
    }

    private func handleGlobalShortcut(_ action: ShortcutAction) async {
        switch action {
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
        shortcutMonitor.stop()
        
        for monitor in middleClickMonitors {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        middleClickMonitors = []
        middleClickTask?.cancel()
        
        shortcutModeHandler.reset()
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
    private var activeSpecialOptions = SpecialShortcutOptions()
    private var lastShortcutPressTime: Date?
    private var activeLatencyTraceToken: VoiceInkLatencyTrace.Token?

    init(
        logger: Logger,
        canHandleShortcutAction: @escaping @MainActor () -> Bool,
        isRecorderVisible: @escaping @MainActor () -> Bool,
        recordingState: @escaping @MainActor () -> VoiceInkRecordingState,
        toggleMiniRecorder: @escaping @MainActor (UUID?) async -> Void,
        cancelRecording: @escaping @MainActor () async -> Void
    ) {
        self.logger = logger
        self.canHandleShortcutAction = canHandleShortcutAction
        self.isRecorderVisible = isRecorderVisible
        self.recordingState = recordingState
        self.toggleMiniRecorder = toggleMiniRecorder
        self.cancelRecording = cancelRecording
    }

    func reset() {
        isShortcutPressed = false
        shortcutPressStartTime = nil
        isHandsFreeRecording = false
        activeRecordingShortcutAction = nil
        interruptedRecordingActions.removeAll()
        activeShortcutCanCancelAccidentalStart = false
        activeSpecialOptions = SpecialShortcutOptions()
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
        activeSpecialOptions = specialOptions
        lastShortcutPressTime = now
        shortcutPressStartTime = eventTime

        switch mode {
        case .special:
            await startRecordingIfNeeded(
                mode: mode,
                eventTime: eventTime,
                callbackReceivedAt: callbackReceivedAt ?? eventTime,
                powerModeId: powerModeId
            )

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
        guard isShortcutPressed, activeRecordingShortcutAction == action else { return }
        let handlerEnteredAt = ProcessInfo.processInfo.systemUptime
        let callbackTime = callbackReceivedAt ?? eventTime
        let pressDuration = shortcutPressStartTime.map { eventTime - $0 } ?? 0
        let pressDurationMilliseconds = String(format: "%.1f", pressDuration * 1_000)
        let keyEvidenceDetails = Self.keyEvidenceTraceDetails(context)
        VoiceInkLatencyTrace.shared.event(
            "shortcut.key_up_handler",
            details: "action=\(action.storageName) mode=\(mode.rawValue) sourceTMs=\(pressDurationMilliseconds) sourceToCallbackMs=\(String(format: "%.1f", max(0, callbackTime - eventTime) * 1_000)) callbackToHandlerMs=\(String(format: "%.1f", max(0, handlerEnteredAt - callbackTime) * 1_000)) state=\(String(describing: recordingState())) \(keyEvidenceDetails)",
            token: activeLatencyTraceToken
        )
        isShortcutPressed = false
        activeRecordingShortcutAction = nil
        activeShortcutCanCancelAccidentalStart = false
        switch mode {
        case .special:
            let options = activeSpecialOptions

            if VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(for: context) {
                VoiceInkLatencyTrace.shared.event(
                    "shortcut.key_evidence_rejected",
                    details: keyEvidenceDetails,
                    token: activeLatencyTraceToken
                )
                if isRecorderVisible() {
                    logger.notice("handleShortcutKeyUp: cancelling special recording; unsafe key evidence")
                    await cancelRecording()
                }
                logger.notice("handleShortcutKeyUp: discarding special shortcut; unsafe key evidence")
            } else if isRecorderVisible() {
                guard canHandleShortcutAction() else { return }
                if options.pasteLastTranscriptOnEmptyTap,
                   VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: pressDuration) {
                    SpecialShortcutEmptyTranscriptionFallback.scheduleFallback()
                }
                logger.notice("handleShortcutKeyUp: stopping recording (special shortcut, duration=\(pressDuration, privacy: .public)s)")
                await toggleMiniRecorder(powerModeId)
            }

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
        activeSpecialOptions = SpecialShortcutOptions()
        if !isHandsFreeRecording {
            activeLatencyTraceToken = nil
        }
    }

    nonisolated static func keyEvidenceTraceDetails(_ context: VoiceInkShortcutPressContext) -> String {
        "pressedOtherKey=\(context.didPressOtherKeyDuringPress) releasedOtherKey=\(context.didReleaseOtherKeyDuringPress) reliable=\(context.hasReliableKeyEvidence)"
    }

    func handleInterruption(action: ShortcutAction) async {
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
