public enum VoiceInkStreamingStartupResolution: Equatable, Sendable {
    case proceed
    case cancelStartupAndUseRecordedFileFallback
    case waitForStreamingStartup
}

public enum VoiceInkStreamingStartupResolutionPolicy {
    public static func plan(
        hasPendingStartup: Bool,
        streamingFailed: Bool,
        supportsRecordedFileTranscription: Bool
    ) -> VoiceInkStreamingStartupResolution {
        guard hasPendingStartup, !streamingFailed else {
            return .proceed
        }

        return supportsRecordedFileTranscription
            ? .cancelStartupAndUseRecordedFileFallback
            : .waitForStreamingStartup
    }
}
