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

    public static func recordingStateWritePlan(
        isRecording: Bool,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateWritePlan {
        VoiceInkAppGroupRecordingStateWritePlan(
            isRecording: isRecording,
            lastRecordingTimestamp: now.timeIntervalSince1970
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
    public static let iOSRecorderStartReturnedFalseDescription = "Failed to start AVAudioRecorder. The record() method returned false. This often happens in the background if the audio session is not configured correctly or if there is a conflict with another app."

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

    public static func noModesAvailableIfNeeded(modeCount: Int) -> VoiceInkRecordingAlertPresentation? {
        modeCount <= 0 ? noModesAvailable : nil
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
