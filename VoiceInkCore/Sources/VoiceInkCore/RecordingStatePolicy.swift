import Foundation

public enum VoiceInkRecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
}

public enum VoiceInkRecorderUIToggleAction: Equatable, Sendable {
    case toggleRecord
    case cancelRecording
    case dismissRecorder
}

public enum VoiceInkRecordingPermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case undetermined
}

public enum VoiceInkRecordingPermissionAction: Equatable, Sendable {
    case startRecording
    case requestPermission
    case presentPermissionDenied

    public func applyRuntimeState(
        startRecording: @escaping () -> Void,
        presentPermissionDenied: @escaping () -> Void,
        requestPermission: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        switch self {
        case .startRecording:
            startRecording()
        case .presentPermissionDenied:
            presentPermissionDenied()
        case .requestPermission:
            requestPermission { granted in
                VoiceInkRecordingPermissionPolicy.action(afterPermissionRequestGranted: granted)
                    .applyRuntimeState(
                        startRecording: startRecording,
                        presentPermissionDenied: presentPermissionDenied,
                        requestPermission: requestPermission
                    )
            }
        }
    }
}

public enum VoiceInkRecordingPermissionSettingsAction: Equatable, Sendable {
    case openSettings
    case ignore

    public func applyRuntimeState(openSettings: () -> Void) {
        switch self {
        case .openSettings:
            openSettings()
        case .ignore:
            return
        }
    }
}

public enum VoiceInkRecordingPermissionPolicy {
    public static func action(for status: VoiceInkRecordingPermissionStatus) -> VoiceInkRecordingPermissionAction {
        switch status {
        case .granted:
            return .startRecording
        case .denied:
            return .presentPermissionDenied
        case .undetermined:
            return .requestPermission
        }
    }

    public static func action(afterPermissionRequestGranted isGranted: Bool) -> VoiceInkRecordingPermissionAction {
        isGranted ? .startRecording : .presentPermissionDenied
    }

    public static func settingsOpenAction(
        hasSettingsURL: Bool,
        canOpenSettingsURL: Bool
    ) -> VoiceInkRecordingPermissionSettingsAction {
        hasSettingsURL && canOpenSettingsURL ? .openSettings : .ignore
    }
}

public struct VoiceInkRecorderProcessingPresentation: Equatable, Sendable {
    public let label: String
    public let progressAnimationInterval: TimeInterval

    public init(
        label: String,
        progressAnimationInterval: TimeInterval
    ) {
        self.label = label
        self.progressAnimationInterval = progressAnimationInterval
    }
}

public struct VoiceInkRecordingFlowState: Equatable, Sendable {
    public static let durationUpdateInterval: TimeInterval = 0.1

    public private(set) var recordingState: VoiceInkRecordingState
    public private(set) var animate: Bool
    public private(set) var isRecordingSheetPresented: Bool
    public private(set) var currentDuration: TimeInterval

    public init(
        recordingState: VoiceInkRecordingState = .idle,
        animate: Bool = false,
        isRecordingSheetPresented: Bool = false,
        currentDuration: TimeInterval = 0
    ) {
        self.recordingState = recordingState
        self.animate = animate
        self.isRecordingSheetPresented = isRecordingSheetPresented
        self.currentDuration = currentDuration
    }

    public mutating func prepareRecordingStart() {
        recordingState = .recording
        animate = true
    }

    public mutating func completeRecordingStart() {
        currentDuration = 0
        isRecordingSheetPresented = true
    }

    public mutating func failRecordingStart() {
        recordingState = .idle
        animate = false
        isRecordingSheetPresented = false
    }

    public mutating func finishRecording() {
        recordingState = .idle
        animate = false
        isRecordingSheetPresented = false
    }

    public mutating func cancelRecording() {
        finishRecording()
        currentDuration = 0
    }

    public mutating func setRecordingSheetPresented(_ isPresented: Bool) {
        isRecordingSheetPresented = isPresented
    }

    public mutating func advanceDuration(by interval: TimeInterval = durationUpdateInterval) {
        currentDuration += interval
    }

    public func stopRecordingPlan(audioFileURL: String?) -> VoiceInkRecordingStopPlan {
        var flowStateAfterStop = self
        flowStateAfterStop.finishRecording()

        return VoiceInkRecordingStopPlan(
            flowStateAfterStop: flowStateAfterStop,
            pendingDraft: audioFileURL.map {
                VoiceInkRecordingTranscriptionDraft.pending(
                    duration: currentDuration,
                    audioFileURL: $0
                )
            }
        )
    }
}

public struct VoiceInkRecordingStopPlan: Equatable, Sendable {
    public let flowStateAfterStop: VoiceInkRecordingFlowState
    public let pendingDraft: VoiceInkRecordingTranscriptionDraft?

    public init(
        flowStateAfterStop: VoiceInkRecordingFlowState,
        pendingDraft: VoiceInkRecordingTranscriptionDraft?
    ) {
        self.flowStateAfterStop = flowStateAfterStop
        self.pendingDraft = pendingDraft
    }
}

public enum VoiceInkAudioRecorderStopMode: Equatable, Sendable {
    case keepRecordingFile
    case discardRecordingFile
}

public struct VoiceInkAudioRecorderStopPlan: Equatable, Sendable {
    public let shouldStopRecorder: Bool
    public let shouldInvalidateMeterTimer: Bool
    public let isRecordingAfterStop: Bool
    public let shouldClearAudioLevels: Bool
    public let shouldDeleteCurrentRecordingFile: Bool
    public let shouldClearCurrentRecordingURL: Bool
    public let shouldScheduleSessionDeactivation: Bool

    public init(
        shouldStopRecorder: Bool,
        shouldInvalidateMeterTimer: Bool,
        isRecordingAfterStop: Bool,
        shouldClearAudioLevels: Bool,
        shouldDeleteCurrentRecordingFile: Bool,
        shouldClearCurrentRecordingURL: Bool,
        shouldScheduleSessionDeactivation: Bool
    ) {
        self.shouldStopRecorder = shouldStopRecorder
        self.shouldInvalidateMeterTimer = shouldInvalidateMeterTimer
        self.isRecordingAfterStop = isRecordingAfterStop
        self.shouldClearAudioLevels = shouldClearAudioLevels
        self.shouldDeleteCurrentRecordingFile = shouldDeleteCurrentRecordingFile
        self.shouldClearCurrentRecordingURL = shouldClearCurrentRecordingURL
        self.shouldScheduleSessionDeactivation = shouldScheduleSessionDeactivation
    }

    public func applyRuntimeState(
        stopRecorder: () -> Void,
        invalidateMeterTimer: () -> Void,
        setIsRecording: (Bool) -> Void,
        clearAudioLevels: () -> Void,
        deleteCurrentRecordingFile: () -> Void,
        clearCurrentRecordingURL: () -> Void,
        scheduleSessionDeactivation: () -> Void
    ) {
        if shouldStopRecorder {
            stopRecorder()
        }
        if shouldInvalidateMeterTimer {
            invalidateMeterTimer()
        }
        setIsRecording(isRecordingAfterStop)
        if shouldClearAudioLevels {
            clearAudioLevels()
        }
        if shouldDeleteCurrentRecordingFile {
            deleteCurrentRecordingFile()
        }
        if shouldClearCurrentRecordingURL {
            clearCurrentRecordingURL()
        }
        if shouldScheduleSessionDeactivation {
            scheduleSessionDeactivation()
        }
    }
}

public enum VoiceInkAudioRecorderStopPolicy {
    public static func plan(for mode: VoiceInkAudioRecorderStopMode) -> VoiceInkAudioRecorderStopPlan {
        VoiceInkAudioRecorderStopPlan(
            shouldStopRecorder: true,
            shouldInvalidateMeterTimer: true,
            isRecordingAfterStop: false,
            shouldClearAudioLevels: true,
            shouldDeleteCurrentRecordingFile: mode == .discardRecordingFile,
            shouldClearCurrentRecordingURL: mode == .discardRecordingFile,
            shouldScheduleSessionDeactivation: true
        )
    }
}

public enum VoiceInkAudioRecorderStartFailurePolicy {
    public static let returnedFalseErrorCode = 1001
    public static let errorDomainComponent = "AudioRecorder"
    public static let returnedFalseDescription = "Failed to start AVAudioRecorder. The record() method returned false. This often happens in the background if the audio session is not configured correctly or if there is a conflict with another app."

    public static var returnedFalseErrorDomain: String {
        VoiceInkAppIdentity.errorDomain(component: errorDomainComponent)
    }

    public static var returnedFalseUserInfo: [String: String] {
        [NSLocalizedDescriptionKey: returnedFalseDescription]
    }

    public static func returnedFalseError() -> NSError {
        NSError(
            domain: returnedFalseErrorDomain,
            code: returnedFalseErrorCode,
            userInfo: returnedFalseUserInfo
        )
    }
}

public struct VoiceInkAppGroupRecordingState: Equatable, Sendable {
    public let isRecording: Bool
    public let shouldClearStaleState: Bool

    public init(isRecording: Bool, shouldClearStaleState: Bool) {
        self.isRecording = isRecording
        self.shouldClearStaleState = shouldClearStaleState
    }
}

public struct VoiceInkAppGroupRecordingStateWritePlan: Equatable, Sendable {
    public let isRecording: Bool?
    public let lastRecordingTimestamp: TimeInterval

    public init(isRecording: Bool?, lastRecordingTimestamp: TimeInterval) {
        self.isRecording = isRecording
        self.lastRecordingTimestamp = lastRecordingTimestamp
    }
}

public struct VoiceInkAppGroupRecordingStateMutationPlan: Equatable, Sendable {
    public let writePlan: VoiceInkAppGroupRecordingStateWritePlan
    public let darwinNotificationName: String

    public init(
        writePlan: VoiceInkAppGroupRecordingStateWritePlan,
        darwinNotificationName: String
    ) {
        self.writePlan = writePlan
        self.darwinNotificationName = darwinNotificationName
    }
}

public struct VoiceInkAppGroupRecordingStateReadPlan: Equatable, Sendable {
    public let state: VoiceInkAppGroupRecordingState
    public let staleStateRepairMutationPlan: VoiceInkAppGroupRecordingStateMutationPlan?

    public init(
        state: VoiceInkAppGroupRecordingState,
        staleStateRepairMutationPlan: VoiceInkAppGroupRecordingStateMutationPlan?
    ) {
        self.state = state
        self.staleStateRepairMutationPlan = staleStateRepairMutationPlan
    }
}

public enum VoiceInkAppGroupRecordingStatePolicy {
    public static let staleRecordingInterval: TimeInterval = 30

    public enum UserDefaultsKey {
        public static let isRecording = "isRecording"
        public static let lastRecordingTimestamp = "lastRecordingTimestamp"
    }

    public static func stopRequestedWritePlan(
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateWritePlan {
        VoiceInkAppGroupRecordingStateWritePlan(
            isRecording: nil,
            lastRecordingTimestamp: now.timeIntervalSince1970
        )
    }

    public static func stopRequestedMutationPlan(
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateMutationPlan {
        VoiceInkAppGroupRecordingStateMutationPlan(
            writePlan: stopRequestedWritePlan(now: now),
            darwinNotificationName: VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName
        )
    }

    public static func recordingStateWritePlan(
        isRecording: Bool,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateWritePlan {
        VoiceInkAppGroupRecordingStateWritePlan(
            isRecording: isRecording,
            lastRecordingTimestamp: now.timeIntervalSince1970
        )
    }

    public static func recordingStateMutationPlan(
        isRecording: Bool,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateMutationPlan {
        VoiceInkAppGroupRecordingStateMutationPlan(
            writePlan: recordingStateWritePlan(isRecording: isRecording, now: now),
            darwinNotificationName: VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName
        )
    }

    public static func state(
        storedIsRecording: Bool,
        lastRecordingTimestamp: TimeInterval,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingState {
        guard storedIsRecording else {
            return VoiceInkAppGroupRecordingState(
                isRecording: false,
                shouldClearStaleState: false
            )
        }

        let isStale = now.timeIntervalSince1970 - lastRecordingTimestamp > staleRecordingInterval
        return VoiceInkAppGroupRecordingState(
            isRecording: !isStale,
            shouldClearStaleState: isStale
        )
    }

    public static func readPlan(
        storedIsRecording: Bool,
        lastRecordingTimestamp: TimeInterval,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateReadPlan {
        let currentState = state(
            storedIsRecording: storedIsRecording,
            lastRecordingTimestamp: lastRecordingTimestamp,
            now: now
        )
        let repairMutationPlan: VoiceInkAppGroupRecordingStateMutationPlan?
        if currentState.shouldClearStaleState {
            repairMutationPlan = recordingStateMutationPlan(isRecording: false, now: now)
        } else {
            repairMutationPlan = nil
        }

        return VoiceInkAppGroupRecordingStateReadPlan(
            state: currentState,
            staleStateRepairMutationPlan: repairMutationPlan
        )
    }
}

public enum VoiceInkAppGroupRecordingDiagnostics {
    public static let staleRecordingStateClearedMessage = "Recording state appears stale, clearing it"

    public static func updatedRecordingStateMessage(isRecording: Bool) -> String {
        "Updated recording state: \(isRecording)"
    }
}

public enum VoiceInkIOSRecordingCoordinationDiagnostics {
    public static let clearedStaleRecordingStateOnLaunchMessage = "Cleared stale recording state on app launch"
    public static let recordDeepLinkOpenedMessage = "URL scheme triggered: open app for recording"
    public static let keyboardRecordingRequestOpenedMessage = "App opened via keyboard extension - recording requested"
    public static let recordingManagerInitializedMessage = "RecordingManager initialized"
    public static let keyboardStopRecordingRequestedMessage = "Stop recording requested from keyboard extension"
}

public enum VoiceInkKeyboardRecordingTiming {
    public static let appLaunchRecordingStartDelay: TimeInterval = 0.5
    public static let recordingStatusPollingInterval: TimeInterval = 0.5
    public static let openAppFallbackResetDelay: TimeInterval = 2.0
}

public enum VoiceInkLaunchRecordingRequestAction: Equatable, Sendable {
    case none
    case deferUntilOnboardingCompletes
    case startRecordingAfterLaunchDelay

    public func applyRuntimeState(startRecordingAfterLaunchDelay: () -> Void) {
        switch self {
        case .none, .deferUntilOnboardingCompletes:
            return
        case .startRecordingAfterLaunchDelay:
            startRecordingAfterLaunchDelay()
        }
    }
}

public struct VoiceInkLaunchRecordingRequestState: Equatable, Sendable {
    public private(set) var hasPendingRecordingAfterOnboarding: Bool

    public init(hasPendingRecordingAfterOnboarding: Bool = false) {
        self.hasPendingRecordingAfterOnboarding = hasPendingRecordingAfterOnboarding
    }

    public mutating func requestRecording(
        hasCompletedOnboarding: Bool
    ) -> VoiceInkLaunchRecordingRequestAction {
        guard hasCompletedOnboarding else {
            hasPendingRecordingAfterOnboarding = true
            return .deferUntilOnboardingCompletes
        }

        hasPendingRecordingAfterOnboarding = false
        return .startRecordingAfterLaunchDelay
    }

    public mutating func consumePendingRecordingIfReady(
        hasCompletedOnboarding: Bool
    ) -> VoiceInkLaunchRecordingRequestAction {
        guard hasCompletedOnboarding, hasPendingRecordingAfterOnboarding else {
            return .none
        }

        hasPendingRecordingAfterOnboarding = false
        return .startRecordingAfterLaunchDelay
    }
}

public struct VoiceInkKeyboardRecordingButtonPresentation: Equatable, Sendable {
    public let title: String
    public let systemImageName: String

    public init(title: String, systemImageName: String) {
        self.title = title
        self.systemImageName = systemImageName
    }

    public static let idle = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Record",
        systemImageName: "mic.fill"
    )

    public static let recording = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Stop",
        systemImageName: "stop.fill"
    )

    public static let openAppFallback = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Open \(VoiceInkAppIdentity.displayName)",
        systemImageName: "app"
    )

    public static func current(isRecording: Bool) -> VoiceInkKeyboardRecordingButtonPresentation {
        isRecording ? recording : idle
    }
}

public enum VoiceInkKeyboardRecordingButtonTapAction: Equatable, Sendable {
    case requestStopRecording
    case openMainAppForRecording
}

public struct VoiceInkKeyboardRecordingButtonTapPlan: Equatable, Sendable {
    public let action: VoiceInkKeyboardRecordingButtonTapAction
    public let shouldRefreshButtonStateAfterAction: Bool

    public init(
        action: VoiceInkKeyboardRecordingButtonTapAction,
        shouldRefreshButtonStateAfterAction: Bool
    ) {
        self.action = action
        self.shouldRefreshButtonStateAfterAction = shouldRefreshButtonStateAfterAction
    }

    public func applyRuntimeState(
        requestStopRecording: () -> Void,
        openMainAppForRecording: () -> Void,
        refreshButtonState: () -> Void
    ) {
        switch action {
        case .requestStopRecording:
            requestStopRecording()
            if shouldRefreshButtonStateAfterAction {
                refreshButtonState()
            }
        case .openMainAppForRecording:
            openMainAppForRecording()
        }
    }
}

public enum VoiceInkKeyboardRecordingButtonTapPolicy {
    public static func plan(isRecording: Bool) -> VoiceInkKeyboardRecordingButtonTapPlan {
        if isRecording {
            return VoiceInkKeyboardRecordingButtonTapPlan(
                action: .requestStopRecording,
                shouldRefreshButtonStateAfterAction: true
            )
        }

        return VoiceInkKeyboardRecordingButtonTapPlan(
            action: .openMainAppForRecording,
            shouldRefreshButtonStateAfterAction: false
        )
    }
}

public enum VoiceInkKeyboardOpenAppAction: Equatable, Sendable {
    case openExtensionContext
    case openThroughApplicationOrResponderChain
    case finish
    case showFallback
}

public enum VoiceInkKeyboardOpenAppApplicationAction: Equatable, Sendable {
    case openViaApplication
    case openViaResponderChain
}

public enum VoiceInkKeyboardOpenAppResponderAction: Equatable, Sendable {
    case performResponderChainOpen
    case showFallback
}

public enum VoiceInkKeyboardOpenAppPolicy {
    public static func initialAction(hasExtensionContext: Bool) -> VoiceInkKeyboardOpenAppAction {
        hasExtensionContext ? .openExtensionContext : .openThroughApplicationOrResponderChain
    }

    public static func actionAfterExtensionContextOpen(succeeded: Bool) -> VoiceInkKeyboardOpenAppAction {
        succeeded ? .finish : .openThroughApplicationOrResponderChain
    }

    public static func applicationAction(canOpenURL: Bool) -> VoiceInkKeyboardOpenAppApplicationAction {
        canOpenURL ? .openViaApplication : .openViaResponderChain
    }

    public static func actionAfterApplicationOpen(succeeded: Bool) -> VoiceInkKeyboardOpenAppAction {
        succeeded ? .finish : .showFallback
    }

    public static func responderAction(hasResponder: Bool) -> VoiceInkKeyboardOpenAppResponderAction {
        hasResponder ? .performResponderChainOpen : .showFallback
    }
}

public enum VoiceInkKeyboardOpenAppDiagnostics {
    public static let extensionContextUnavailable = "extensionContext unavailable, trying alternative methods"
    public static let openedViaExtensionContext = "Opened main app via extensionContext"
    public static let extensionContextOpenFailed = "extensionContext.open failed, trying alternative methods"
    public static let openedViaApplication = "Opened main app via UIApplication.open"
    public static let applicationOpenFailed = "UIApplication.open failed"
    public static let attemptedViaResponderChain = "Attempted to open main app via responder chain"
    public static let allMethodsFailed = "All URL opening methods failed"
}

public enum VoiceInkKeyboardStopRecordingRequestAction: Equatable, Sendable {
    case handleStopRequest
    case ignore
}

public enum VoiceInkKeyboardStopRecordingRequestPolicy {
    public static func action(
        recordingState: VoiceInkRecordingState
    ) -> VoiceInkKeyboardStopRecordingRequestAction {
        recordingState.isActivelyRecording ? .handleStopRequest : .ignore
    }
}

public enum VoiceInkRecorderStyle: String, CaseIterable, Identifiable, Sendable {
    case none
    case notch
    case mini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .notch:
            return "Notch"
        case .mini:
            return "Mini"
        }
    }
}

public enum VoiceInkRecorderWindowKind: Equatable, Sendable {
    case none
    case notch
    case mini
}

public struct VoiceInkMacOSRecorderStyleSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let pickerTitle: String

    public init(sectionTitle: String, pickerTitle: String) {
        self.sectionTitle = sectionTitle
        self.pickerTitle = pickerTitle
    }
}

public enum VoiceInkRecorderStylePreference {
    public static let userDefaultsKey = "RecorderType"
    public static let defaultStyle: VoiceInkRecorderStyle = .none
    public static let defaultRawValue = defaultStyle.rawValue
    public static let macOSSettingsPresentation = VoiceInkMacOSRecorderStyleSettingsPresentation(
        sectionTitle: "Interface",
        pickerTitle: "Recorder Style"
    )

    public static func rawValue(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: userDefaultsKey) ?? defaultRawValue
    }

    public static func saveRawValue(
        _ rawValue: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(rawValue, forKey: userDefaultsKey)
    }

    public static func windowKind(forRawValue rawValue: String) -> VoiceInkRecorderWindowKind {
        switch rawValue {
        case VoiceInkRecorderStyle.none.rawValue:
            return .none
        case VoiceInkRecorderStyle.notch.rawValue:
            return .notch
        default:
            return .mini
        }
    }

    public static func hasVisibleRecorder(rawValue: String) -> Bool {
        windowKind(forRawValue: rawValue) != .none
    }
}

public struct VoiceInkRecordingSheetPresentation: Equatable, Sendable {
    public let cancelButtonTitle: String
    public let stopButtonTitle: String
    public let stopButtonSystemImageName: String

    public static let iOS = VoiceInkRecordingSheetPresentation(
        cancelButtonTitle: "Cancel",
        stopButtonTitle: "Stop Recording",
        stopButtonSystemImageName: "stop.fill"
    )
}

public struct VoiceInkRecordingNotificationPresentation: Equatable, Sendable {
    public let title: String
    public let duration: TimeInterval
    public let actionButtonTitle: String?

    public init(
        title: String,
        duration: TimeInterval = 3.0,
        actionButtonTitle: String? = nil
    ) {
        self.title = title
        self.duration = duration
        self.actionButtonTitle = actionButtonTitle
    }

    public static let noTranscriptionModelSelected = VoiceInkRecordingNotificationPresentation(
        title: "No AI Model Selected"
    )

    public static let failedToStart = VoiceInkRecordingNotificationPresentation(
        title: "Recording failed to start"
    )

    public static let microphonePermissionRequired = VoiceInkRecordingNotificationPresentation(
        title: "Microphone permission required",
        duration: 8.0,
        actionButtonTitle: "Grant"
    )

    public static func runtimeFailure(localizedDescription: String) -> VoiceInkRecordingNotificationPresentation {
        VoiceInkRecordingNotificationPresentation(
            title: "Recording Failed: \(localizedDescription)"
        )
    }
}

public struct VoiceInkRecordingAlertPresentation: Equatable, Identifiable, Sendable {
    public enum Action: Equatable, Sendable {
        case dismiss
        case openSettings
    }

    public static let microphoneInUseOSStatusCode = 561017449
    public static let iOSRecorderStartReturnedFalseDescription = VoiceInkAudioRecorderStartFailurePolicy.returnedFalseDescription

    public let id: String
    public let title: String
    public let message: String
    public let primaryButtonTitle: String
    public let secondaryButtonTitle: String?
    public let action: Action

    public init(
        id: String,
        title: String,
        message: String,
        primaryButtonTitle: String = "OK",
        secondaryButtonTitle: String? = nil,
        action: Action = .dismiss
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.action = action
    }

    public static var noModesAvailable: VoiceInkRecordingAlertPresentation {
        VoiceInkRecordingAlertPresentation(
            id: "noModesAvailable",
            title: "No Modes Found",
            message: "Please create a new mode in Settings before recording."
        )
    }

    public static var microphonePermissionDenied: VoiceInkRecordingAlertPresentation {
        VoiceInkRecordingAlertPresentation(
            id: "microphonePermissionDenied",
            title: "Microphone Access Denied",
            message: "To record audio, please grant microphone access in Settings.",
            primaryButtonTitle: "Settings",
            secondaryButtonTitle: "Cancel",
            action: .openSettings
        )
    }

    public static var microphoneInUse: VoiceInkRecordingAlertPresentation {
        VoiceInkRecordingAlertPresentation(
            id: "microphoneInUse",
            title: "Microphone In Use",
            message: "Another app is using the microphone. Please try again."
        )
    }

    public static func recordingFailed(localizedDescription: String) -> VoiceInkRecordingAlertPresentation {
        VoiceInkRecordingAlertPresentation(
            id: "recordingFailed-\(localizedDescription)",
            title: "Recording Failed",
            message: "Could not start recording: \(localizedDescription)"
        )
    }

    public static func recordingStartFailure(
        domain: String,
        code: Int,
        localizedDescription: String
    ) -> VoiceInkRecordingAlertPresentation {
        if domain == NSOSStatusErrorDomain && code == microphoneInUseOSStatusCode {
            return microphoneInUse
        }

        return recordingFailed(localizedDescription: localizedDescription)
    }

    public static func recordingStartFailure(for error: Error) -> VoiceInkRecordingAlertPresentation {
        let nsError = error as NSError
        return recordingStartFailure(
            domain: nsError.domain,
            code: nsError.code,
            localizedDescription: error.localizedDescription
        )
    }
}

public enum VoiceInkRecordingStartAction: Equatable, Sendable {
    case startRecording
    case presentAlert(VoiceInkRecordingAlertPresentation)

    public func applyRuntimeState(
        startRecording: () -> Void,
        presentAlert: (VoiceInkRecordingAlertPresentation) -> Void
    ) {
        switch self {
        case .startRecording:
            startRecording()
        case .presentAlert(let alert):
            presentAlert(alert)
        }
    }
}

public enum VoiceInkRecordingStartPolicy {
    public static func action(modeCount: Int) -> VoiceInkRecordingStartAction {
        modeCount <= 0 ? .presentAlert(.noModesAvailable) : .startRecording
    }
}

public struct VoiceInkMacOSRecordingCancellationPlan: Equatable, Sendable {
    public let shouldClearDeferredStopRequest: Bool
    public let shouldRequestRecordingCancellation: Bool
    public let shouldFinishActiveRecorderCancellation: Bool
    public let shouldClearPartialTranscript: Bool
    public let shouldClearCancelFlag: Bool
    public let recordingStateAfterImmediateCancel: VoiceInkRecordingState?
    public let shouldFinishRecorderSessionImmediately: Bool

    public init(
        shouldClearDeferredStopRequest: Bool,
        shouldRequestRecordingCancellation: Bool,
        shouldFinishActiveRecorderCancellation: Bool,
        shouldClearPartialTranscript: Bool,
        shouldClearCancelFlag: Bool,
        recordingStateAfterImmediateCancel: VoiceInkRecordingState?,
        shouldFinishRecorderSessionImmediately: Bool
    ) {
        self.shouldClearDeferredStopRequest = shouldClearDeferredStopRequest
        self.shouldRequestRecordingCancellation = shouldRequestRecordingCancellation
        self.shouldFinishActiveRecorderCancellation = shouldFinishActiveRecorderCancellation
        self.shouldClearPartialTranscript = shouldClearPartialTranscript
        self.shouldClearCancelFlag = shouldClearCancelFlag
        self.recordingStateAfterImmediateCancel = recordingStateAfterImmediateCancel
        self.shouldFinishRecorderSessionImmediately = shouldFinishRecorderSessionImmediately
    }
}

public enum VoiceInkMacOSRecordingCancellationPolicy {
    public static func plan(
        recordingState: VoiceInkRecordingState
    ) -> VoiceInkMacOSRecordingCancellationPlan {
        if recordingState.isRecorderCaptureInProgress {
            return VoiceInkMacOSRecordingCancellationPlan(
                shouldClearDeferredStopRequest: true,
                shouldRequestRecordingCancellation: true,
                shouldFinishActiveRecorderCancellation: true,
                shouldClearPartialTranscript: false,
                shouldClearCancelFlag: false,
                recordingStateAfterImmediateCancel: nil,
                shouldFinishRecorderSessionImmediately: true
            )
        }

        if recordingState.isPostRecordingProcessing {
            return VoiceInkMacOSRecordingCancellationPlan(
                shouldClearDeferredStopRequest: true,
                shouldRequestRecordingCancellation: true,
                shouldFinishActiveRecorderCancellation: false,
                shouldClearPartialTranscript: true,
                shouldClearCancelFlag: false,
                recordingStateAfterImmediateCancel: .idle,
                shouldFinishRecorderSessionImmediately: false
            )
        }

        return VoiceInkMacOSRecordingCancellationPlan(
            shouldClearDeferredStopRequest: true,
            shouldRequestRecordingCancellation: false,
            shouldFinishActiveRecorderCancellation: false,
            shouldClearPartialTranscript: true,
            shouldClearCancelFlag: true,
            recordingStateAfterImmediateCancel: .idle,
            shouldFinishRecorderSessionImmediately: true
        )
    }
}

public extension VoiceInkRecordingState {
    var isActivelyRecording: Bool {
        self == .recording
    }

    var isRecorderCaptureInProgress: Bool {
        self == .starting || self == .recording
    }

    var acceptsRollingBufferPreloadPreview: Bool {
        self == .idle || self == .recording
    }

    var acceptsRecordingShortcutAction: Bool {
        self != .transcribing &&
        self != .enhancing &&
        self != .busy
    }

    var isPostRecordingProcessing: Bool {
        recorderProcessingPresentation != nil
    }

    var isRecorderDismissCancelable: Bool {
        switch self {
        case .starting, .recording, .transcribing, .enhancing:
            return true
        case .idle, .busy:
            return false
        }
    }

    var shouldReturnToIdleWhenActivePipelineFinishes: Bool {
        isPostRecordingProcessing || self == .busy
    }

    var recorderUIToggleAction: VoiceInkRecorderUIToggleAction {
        switch self {
        case .recording, .starting:
            return .toggleRecord
        case .transcribing, .enhancing:
            return .cancelRecording
        case .idle, .busy:
            return .dismissRecorder
        }
    }

    var recorderProcessingPresentation: VoiceInkRecorderProcessingPresentation? {
        switch self {
        case .transcribing:
            return VoiceInkRecorderProcessingPresentation(
                label: "Transcribing",
                progressAnimationInterval: 0.18
            )
        case .enhancing:
            return VoiceInkRecorderProcessingPresentation(
                label: "Enhancing",
                progressAnimationInterval: 0.22
            )
        case .idle, .starting, .recording, .busy:
            return nil
        }
    }
}

public enum VoiceInkRecorderUISessionPolicy {
    public static func isActiveForRecordingShortcut(
        hasVisibleRecorderType: Bool,
        recordingState: VoiceInkRecordingState,
        isRecorderSessionActive: Bool
    ) -> Bool {
        if !hasVisibleRecorderType, recordingState == .idle {
            return false
        }

        return isRecorderSessionActive
    }

    public static func shouldClearStaleHiddenRecorderSession(
        hasVisibleRecorderType: Bool,
        recordingState: VoiceInkRecordingState,
        isRecorderSessionActive: Bool
    ) -> Bool {
        !hasVisibleRecorderType && isRecorderSessionActive && recordingState == .idle
    }
}
