import Foundation

public enum VoiceInkTranscriptionRecordingStartupLoadAction: Equatable, Sendable {
    case none
    case loadLocalWhisperModel
    case loadLocalFluidAudioModel
}

public enum VoiceInkTranscriptionModelSelectionResourceAction: Equatable, Sendable {
    case preserveLocalWhisperModel
    case clearLocalWhisperModelAndMarkLoaded

    public var localWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeUpdate {
        switch self {
        case .preserveLocalWhisperModel:
            return .preserve
        case .clearLocalWhisperModelAndMarkLoaded:
            return .clearLoadedModel(isModelLoadedAfterUpdate: true)
        }
    }
}

public struct VoiceInkLocalWhisperRuntimeUpdate: Equatable, Sendable {
    public let shouldClearLoadedModel: Bool
    public let isModelLoadedAfterUpdate: Bool?

    public init(
        shouldClearLoadedModel: Bool,
        isModelLoadedAfterUpdate: Bool?
    ) {
        self.shouldClearLoadedModel = shouldClearLoadedModel
        self.isModelLoadedAfterUpdate = isModelLoadedAfterUpdate
    }

    public static let preserve = Self(
        shouldClearLoadedModel: false,
        isModelLoadedAfterUpdate: nil
    )

    public static func clearLoadedModel(isModelLoadedAfterUpdate: Bool) -> Self {
        Self(
            shouldClearLoadedModel: true,
            isModelLoadedAfterUpdate: isModelLoadedAfterUpdate
        )
    }
}

public struct VoiceInkTranscriptionModelDeletionPlan: Equatable, Sendable {
    public let shouldClearCurrentModel: Bool
    public let localWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeUpdate

    public init(currentModelName: String?, deletedModelName: String) {
        let shouldClearCurrentModel = currentModelName == deletedModelName
        self.shouldClearCurrentModel = shouldClearCurrentModel
        self.localWhisperRuntimeUpdate = shouldClearCurrentModel
            ? .clearLoadedModel(isModelLoadedAfterUpdate: false)
            : .preserve
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
