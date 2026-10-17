public enum RomaStreamingStartupResolution: Equatable, Sendable {
    case proceed
    case cancelStartupAndUseRecordedFileFallback
    case waitForStreamingStartup
}

public enum RomaStreamingStartupResolutionPolicy {
    public static func plan(
        hasPendingStartup: Bool,
        streamingFailed: Bool,
        supportsRecordedFileTranscription: Bool
    ) -> RomaStreamingStartupResolution {
        guard hasPendingStartup, !streamingFailed else {
            return .proceed
        }

        return supportsRecordedFileTranscription
            ? .cancelStartupAndUseRecordedFileFallback
            : .waitForStreamingStartup
    }
}
