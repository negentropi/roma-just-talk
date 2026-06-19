import Foundation

public enum VoiceInkTranscriptionRecordingStartupLoadAction: Equatable, Sendable {
    case none
    case loadLocalWhisperModel
    case loadLocalFluidAudioModel
}

public enum VoiceInkTranscriptionModelSelectionResourceAction: Equatable, Sendable {
    case preserveLocalWhisperModel
    case clearLocalWhisperModelAndMarkLoaded
}

public struct VoiceInkTranscriptionRuntimeResourcePlan: Equatable, Sendable {
    public let shouldPrewarmModel: Bool
    public let recordingStartupLoadAction: VoiceInkTranscriptionRecordingStartupLoadAction
    public let modelSelectionResourceAction: VoiceInkTranscriptionModelSelectionResourceAction

    public init(serviceRoute: VoiceInkTranscriptionServiceRoute) {
        switch serviceRoute {
        case .localWhisper:
            self.shouldPrewarmModel = true
            self.recordingStartupLoadAction = .loadLocalWhisperModel
            self.modelSelectionResourceAction = .preserveLocalWhisperModel
        case .localFluidAudio:
            self.shouldPrewarmModel = true
            self.recordingStartupLoadAction = .loadLocalFluidAudioModel
            self.modelSelectionResourceAction = .clearLocalWhisperModelAndMarkLoaded
        case .cloud, .nativeApple:
            self.shouldPrewarmModel = false
            self.recordingStartupLoadAction = .none
            self.modelSelectionResourceAction = .clearLocalWhisperModelAndMarkLoaded
        }
    }
}
