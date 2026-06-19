import Foundation

public enum VoiceInkTranscriptionRecordingStartupLoadAction: Equatable, Sendable {
    case none
    case loadLocalWhisperModel
    case loadLocalFluidAudioModel
}

public struct VoiceInkTranscriptionRuntimeResourcePlan: Equatable, Sendable {
    public let shouldPrewarmModel: Bool
    public let recordingStartupLoadAction: VoiceInkTranscriptionRecordingStartupLoadAction

    public init(serviceRoute: VoiceInkTranscriptionServiceRoute) {
        switch serviceRoute {
        case .localWhisper:
            self.shouldPrewarmModel = true
            self.recordingStartupLoadAction = .loadLocalWhisperModel
        case .localFluidAudio:
            self.shouldPrewarmModel = true
            self.recordingStartupLoadAction = .loadLocalFluidAudioModel
        case .cloud, .nativeApple:
            self.shouldPrewarmModel = false
            self.recordingStartupLoadAction = .none
        }
    }
}
