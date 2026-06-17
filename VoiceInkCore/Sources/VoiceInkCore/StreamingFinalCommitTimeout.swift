import Foundation

public enum VoiceInkStreamingFinalCommitSource: Equatable, Sendable {
    case cloud
    case localFluidAudio
}

public enum VoiceInkStreamingFinalCommitTimeout {
    public static let cloudNanoseconds: UInt64 = 10_000_000_000
    public static let localFluidAudioNanoseconds: UInt64 = 1_000_000_000

    public static func nanoseconds(for source: VoiceInkStreamingFinalCommitSource) -> UInt64 {
        switch source {
        case .cloud:
            cloudNanoseconds
        case .localFluidAudio:
            localFluidAudioNanoseconds
        }
    }
}
