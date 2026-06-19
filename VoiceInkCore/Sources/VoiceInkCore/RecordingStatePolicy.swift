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

    public init(title: String) {
        self.title = title
    }

    public static let noTranscriptionModelSelected = VoiceInkRecordingNotificationPresentation(
        title: "No AI Model Selected"
    )

    public static let failedToStart = VoiceInkRecordingNotificationPresentation(
        title: "Recording failed to start"
    )
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

    var acceptsRollingBufferPreloadPreview: Bool {
        self == .idle || self == .recording
    }

    var acceptsRecordingShortcutAction: Bool {
        self != .transcribing &&
        self != .enhancing &&
        self != .busy
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
}
