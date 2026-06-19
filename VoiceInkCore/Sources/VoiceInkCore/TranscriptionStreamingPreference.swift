import Foundation

public struct VoiceInkTranscriptionStreamingModelSnapshot: Equatable, Sendable {
    public let name: String
    public let supportsStreaming: Bool
    public let isStreamingOnly: Bool

    public init(
        name: String,
        supportsStreaming: Bool,
        isStreamingOnly: Bool = false
    ) {
        self.name = name
        self.supportsStreaming = supportsStreaming
        self.isStreamingOnly = isStreamingOnly
    }
}

public enum VoiceInkTranscriptionStreamingPreference {
    public static let keyPrefix = "streaming-enabled-"
    public static let defaultIsEnabled = true

    public static func key(forModelName modelName: String) -> String {
        "\(keyPrefix)\(modelName)"
    }

    public static func isEnabled(
        forModelName modelName: String,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: key(forModelName: modelName)) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(
        _ isEnabled: Bool,
        forModelName modelName: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: key(forModelName: modelName))
    }

    public static func shouldUseStreaming(
        for model: VoiceInkTranscriptionStreamingModelSnapshot,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard model.supportsStreaming else { return false }
        if model.isStreamingOnly {
            return true
        }
        return isEnabled(forModelName: model.name, in: defaults)
    }
}

public enum VoiceInkTranscriptionServiceRoute: Equatable, Sendable {
    case cloud
    case localFluidAudio
    case localWhisper
    case nativeApple
}

public enum VoiceInkTranscriptionStreamingAdapterKind: Equatable, Sendable {
    case cloud
    case localFluidAudio
}

public struct VoiceInkTranscriptionSessionRouteFacts: Equatable, Sendable {
    public let serviceRoute: VoiceInkTranscriptionServiceRoute
    public let streamingSnapshot: VoiceInkTranscriptionStreamingModelSnapshot

    public init(
        serviceRoute: VoiceInkTranscriptionServiceRoute,
        streamingSnapshot: VoiceInkTranscriptionStreamingModelSnapshot
    ) {
        self.serviceRoute = serviceRoute
        self.streamingSnapshot = streamingSnapshot
    }

    public func plan(
        forceStreaming: Bool,
        defaults: UserDefaults = .standard
    ) -> VoiceInkTranscriptionSessionRoutePlan {
        let usesStreaming = forceStreaming
            ? streamingSnapshot.supportsStreaming
            : VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
                for: streamingSnapshot,
                in: defaults
            )

        return VoiceInkTranscriptionSessionRoutePlan(
            serviceRoute: serviceRoute,
            usesStreaming: usesStreaming,
            forceStreaming: forceStreaming
        )
    }
}

public struct VoiceInkTranscriptionSessionRoutePlan: Equatable, Sendable {
    public let serviceRoute: VoiceInkTranscriptionServiceRoute
    public let usesStreaming: Bool
    public let streamingAdapterKind: VoiceInkTranscriptionStreamingAdapterKind?
    public let usesRollingPreload: Bool
    public let finalCommitSource: VoiceInkStreamingFinalCommitSource?

    public init(
        serviceRoute: VoiceInkTranscriptionServiceRoute,
        usesStreaming: Bool,
        forceStreaming: Bool
    ) {
        self.serviceRoute = serviceRoute
        self.usesStreaming = usesStreaming

        guard usesStreaming else {
            self.streamingAdapterKind = nil
            self.usesRollingPreload = false
            self.finalCommitSource = nil
            return
        }

        switch serviceRoute {
        case .localFluidAudio:
            self.streamingAdapterKind = .localFluidAudio
            self.usesRollingPreload = forceStreaming
            self.finalCommitSource = .localFluidAudio
        case .cloud, .localWhisper, .nativeApple:
            self.streamingAdapterKind = .cloud
            self.usesRollingPreload = false
            self.finalCommitSource = .cloud
        }
    }

    public var finalCommitTimeoutNanoseconds: UInt64? {
        finalCommitSource.map(VoiceInkStreamingFinalCommitTimeout.nanoseconds(for:))
    }
}
