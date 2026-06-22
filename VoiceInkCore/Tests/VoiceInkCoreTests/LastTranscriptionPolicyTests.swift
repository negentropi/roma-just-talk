import Foundation
@testable import VoiceInkCore

final class LastTranscriptionPolicyTests: XCTestCase {
    func testFirstPasteableCandidateSkipsExcludedPendingBlankAndCanceledCandidates() {
        let excluded = UUID()
        let expected = UUID()
        let candidates = [
            candidate(id: excluded, rawText: "excluded"),
            candidate(rawText: "still pending", status: .pending),
            candidate(rawText: "   "),
            candidate(rawText: VoiceInkTranscriptPresentation.canceledTranscriptionText, status: .canceled),
            candidate(id: expected, rawText: "legacy usable", status: nil)
        ]

        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.firstPasteableCandidate(
                in: candidates,
                excluding: excluded
            )?.id,
            expected
        )
    }

    func testFirstPasteableCandidatePreservesCandidateOrder() {
        let older = UUID()
        let newest = UUID()
        let candidates = [
            candidate(id: newest, rawText: "newest"),
            candidate(id: older, rawText: "older")
        ]

        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.firstPasteableCandidate(in: candidates)?.id,
            newest
        )
    }

    func testPasteTextUsesOriginalOrEnhancedFallbackPolicy() {
        let enhanced = candidate(rawText: "raw text", enhancedText: "enhanced text")
        let rawOnly = candidate(rawText: "raw text", enhancedText: nil)

        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.pasteText(for: enhanced, preference: .original),
            "raw text"
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.pasteText(for: enhanced, preference: .preferred),
            "enhanced text"
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.pasteText(for: rawOnly, preference: .preferred),
            "raw text"
        )
    }

    func testFetchLimitPreservesMacOSLastTranscriptionFetchWindow() {
        XCTAssertEqual(VoiceInkLastTranscriptionPolicy.fetchLimit, 20)
    }

    private func candidate(
        id: UUID = UUID(),
        rawText: String,
        enhancedText: String? = nil,
        status: VoiceInkTranscriptionStatus? = .completed
    ) -> VoiceInkLastTranscriptionCandidate<UUID> {
        VoiceInkLastTranscriptionCandidate(
            id: id,
            rawText: rawText,
            enhancedText: enhancedText,
            status: status
        )
    }
}
