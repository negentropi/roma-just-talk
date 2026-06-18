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
