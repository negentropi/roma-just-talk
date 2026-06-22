import Foundation

public enum VoiceInkTranscriptionRecordingStartupLoadAction: Equatable, Sendable {
    case none
    case loadLocalWhisperModel
    case loadLocalFluidAudioModel
}

public enum VoiceInkTranscriptionModelSelectionResourceAction: Equatable, Sendable {
    case preserveLocalWhisperModel
    case clearLocalWhisperModelAndMarkLoaded

    public var localWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeSelectionUpdate {
        switch self {
        case .preserveLocalWhisperModel:
            return VoiceInkLocalWhisperRuntimeSelectionUpdate(
                shouldClearLoadedModel: false,
                isModelLoadedAfterSelection: nil
            )
        case .clearLocalWhisperModelAndMarkLoaded:
            return VoiceInkLocalWhisperRuntimeSelectionUpdate(
                shouldClearLoadedModel: true,
                isModelLoadedAfterSelection: true
            )
        }
    }
}

public struct VoiceInkLocalWhisperRuntimeSelectionUpdate: Equatable, Sendable {
    public let shouldClearLoadedModel: Bool
    public let isModelLoadedAfterSelection: Bool?

    public init(
        shouldClearLoadedModel: Bool,
        isModelLoadedAfterSelection: Bool?
    ) {
        self.shouldClearLoadedModel = shouldClearLoadedModel
        self.isModelLoadedAfterSelection = isModelLoadedAfterSelection
    }
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
