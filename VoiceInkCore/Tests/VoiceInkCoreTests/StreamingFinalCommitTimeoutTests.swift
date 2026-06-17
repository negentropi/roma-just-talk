import Foundation
@testable import VoiceInkCore

final class StreamingFinalCommitTimeoutTests: XCTestCase {
    func testStreamingFinalCommitTimeoutPreservesCloudDefault() {
        XCTAssertEqual(VoiceInkStreamingFinalCommitTimeout.cloudNanoseconds, 10_000_000_000)
        XCTAssertEqual(
            VoiceInkStreamingFinalCommitTimeout.nanoseconds(for: .cloud),
            10_000_000_000
        )
    }

    func testStreamingFinalCommitTimeoutPreservesLocalFluidAudioFastCommit() {
        XCTAssertEqual(VoiceInkStreamingFinalCommitTimeout.localFluidAudioNanoseconds, 1_000_000_000)
        XCTAssertEqual(
            VoiceInkStreamingFinalCommitTimeout.nanoseconds(for: .localFluidAudio),
            1_000_000_000
        )
    }
}
