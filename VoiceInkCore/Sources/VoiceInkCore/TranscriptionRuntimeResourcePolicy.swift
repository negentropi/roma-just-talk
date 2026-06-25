import Foundation

fileprivate enum VoiceInkTranscriptionRecordingStartupLoadAction: Equatable, Sendable {
    case none
    case loadLocalWhisperModel
    case loadLocalFluidAudioModel
}

fileprivate enum VoiceInkTranscriptionModelSelectionResourceAction: Equatable, Sendable {
    case preserveLocalWhisperModel
    case clearLocalWhisperModelAndMarkLoaded

    var localWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeUpdate {
        switch self {
        case .preserveLocalWhisperModel:
            return .preserve
        case .clearLocalWhisperModelAndMarkLoaded:
            return .clearLoadedModel(isModelLoadedAfterUpdate: true)
        }
    }
}

public struct VoiceInkLocalWhisperRuntimeUpdate: Equatable, Sendable {
    private let shouldClearLoadedModel: Bool
    private let isModelLoadedAfterUpdate: Bool?

    fileprivate init(
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

    public func applyRuntimeState(
        clearLoadedModel: () -> Void,
        setIsModelLoaded: (Bool) -> Void
    ) {
        if shouldClearLoadedModel {
            clearLoadedModel()
        }

        if let isModelLoadedAfterUpdate {
            setIsModelLoaded(isModelLoadedAfterUpdate)
        }
    }
}

public struct VoiceInkTranscriptionModelDeletionPlan: Equatable, Sendable {
    private let shouldClearCurrentModel: Bool
    private let localWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeUpdate

    public init(currentModelName: String?, deletedModelName: String) {
        let shouldClearCurrentModel = currentModelName == deletedModelName
        self.shouldClearCurrentModel = shouldClearCurrentModel
        self.localWhisperRuntimeUpdate = shouldClearCurrentModel
            ? .clearLoadedModel(isModelLoadedAfterUpdate: false)
            : .preserve
    }

    public func applyRuntimeState(
        clearCurrentModel: () -> Void,
        applyLocalWhisperRuntimeUpdate: (VoiceInkLocalWhisperRuntimeUpdate) -> Void
    ) {
        guard shouldClearCurrentModel else { return }

        clearCurrentModel()
        applyLocalWhisperRuntimeUpdate(localWhisperRuntimeUpdate)
    }
}

public struct VoiceInkTranscriptionRuntimeResourcePlan: Equatable, Sendable {
    public let shouldPrewarmModel: Bool
    private let recordingStartupLoadAction: VoiceInkTranscriptionRecordingStartupLoadAction
    private let modelSelectionResourceAction: VoiceInkTranscriptionModelSelectionResourceAction

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

    public var modelSelectionLocalWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeUpdate {
        modelSelectionResourceAction.localWhisperRuntimeUpdate
    }

    public func applyRecordingStartupRuntimeState(
        loadLocalWhisperModel: () async -> Void,
        loadLocalFluidAudioModel: () async -> Void
    ) async {
        switch recordingStartupLoadAction {
        case .none:
            break
        case .loadLocalWhisperModel:
            await loadLocalWhisperModel()
        case .loadLocalFluidAudioModel:
            await loadLocalFluidAudioModel()
        }
    }
}

public struct VoiceInkModelPrewarmSampleResource: Equatable, Sendable {
    public let name: String
    public let fileExtension: String
    public let subdirectory: String?

    public init(name: String, fileExtension: String, subdirectory: String?) {
        self.name = name
        self.fileExtension = fileExtension
        self.subdirectory = subdirectory
    }
}

public enum VoiceInkModelPrewarmSamplePolicy {
    public static let sampleResourceName = "sound7"
    public static let sampleFileExtension = "wav"
    public static let sampleDisplayName = "sound7.wav"

    public static let lookupCandidates = [
        VoiceInkModelPrewarmSampleResource(
            name: sampleResourceName,
            fileExtension: sampleFileExtension,
            subdirectory: "Resources/Sounds"
        ),
        VoiceInkModelPrewarmSampleResource(
            name: sampleResourceName,
            fileExtension: sampleFileExtension,
            subdirectory: "Sounds"
        ),
        VoiceInkModelPrewarmSampleResource(
            name: sampleResourceName,
            fileExtension: sampleFileExtension,
            subdirectory: nil
        )
    ]

    public static func firstAvailableURL(
        lookup: (VoiceInkModelPrewarmSampleResource) -> URL?
    ) -> URL? {
        for candidate in lookupCandidates {
            if let url = lookup(candidate) {
                return url
            }
        }

        return nil
    }
}

public enum VoiceInkModelPrewarmSkipReason: Equatable, Sendable {
    case disabledByUser
    case missingCurrentModel
    case unsupportedRuntime
    case missingSampleAudio
}

public struct VoiceInkModelPrewarmPlan: Equatable, Sendable {
    public let skipReason: VoiceInkModelPrewarmSkipReason?

    public var shouldRun: Bool {
        skipReason == nil
    }

    public var diagnosticMessage: String? {
        switch skipReason {
        case .disabledByUser:
            return VoiceInkModelPrewarmDiagnostics.disabledByUserMessage
        case .missingCurrentModel:
            return nil
        case .unsupportedRuntime:
            return VoiceInkModelPrewarmDiagnostics.unsupportedRuntimeMessage
        case .missingSampleAudio:
            return VoiceInkModelPrewarmDiagnostics.sampleAudioMissingMessage
        case .none:
            return nil
        }
    }

    public init(skipReason: VoiceInkModelPrewarmSkipReason?) {
        self.skipReason = skipReason
    }

    public static func plan(
        isEnabled: Bool,
        hasCurrentModel: Bool,
        shouldPrewarmModel: Bool,
        hasSampleAudio: Bool
    ) -> Self {
        guard isEnabled else {
            return Self(skipReason: .disabledByUser)
        }

        guard hasCurrentModel else {
            return Self(skipReason: .missingCurrentModel)
        }

        guard shouldPrewarmModel else {
            return Self(skipReason: .unsupportedRuntime)
        }

        guard hasSampleAudio else {
            return Self(skipReason: .missingSampleAudio)
        }

        return Self(skipReason: nil)
    }
}

public enum VoiceInkWhisperModelWarmupPolicy {
    public static func shouldScheduleWarmup(
        supportsCoreML: Bool,
        isAlreadyWarming: Bool
    ) -> Bool {
        supportsCoreML && !isAlreadyWarming
    }
}

public enum VoiceInkModelPrewarmDiagnostics {
    public static let initializedMessage = "ModelPrewarmService initialized - listening for wake and app launch"
    public static let appLaunchScheduledMessage = "App launched, scheduling prewarm"
    public static let macActivityScheduledMessage = "Mac activity detected (wake/unlock), scheduling prewarm"
    public static let disabledByUserMessage = "Prewarm disabled by user"
    public static let unsupportedRuntimeMessage = "Skipping prewarm - cloud models don't need it"
    public static let deinitializedMessage = "ModelPrewarmService deinitialized"

    public static var sampleAudioMissingMessage: String {
        "❌ Prewarm audio file (\(VoiceInkModelPrewarmSamplePolicy.sampleDisplayName)) not found"
    }

    public static func prewarmingMessage(modelDisplayName: String) -> String {
        "Prewarming \(modelDisplayName)"
    }

    public static func completedMessage(durationText: String) -> String {
        "Prewarm completed in \(durationText)s"
    }

    public static func failedMessage(errorDescription: String) -> String {
        "❌ Prewarm failed: \(errorDescription)"
    }
}

public enum VoiceInkWhisperModelWarmupDiagnostics {
    public static func failedMessage(modelName: String, errorDescription: String) -> String {
        "❌ Warmup failed for \(modelName): \(errorDescription)"
    }
}
