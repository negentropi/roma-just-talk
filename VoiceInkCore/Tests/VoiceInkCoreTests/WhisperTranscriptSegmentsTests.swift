import Foundation
@testable import VoiceInkCore

final class WhisperTranscriptSegmentsTests: XCTestCase {
    func testJoinedTextConcatenatesSegmentsWithoutSeparator() {
        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText([" hello", " world", "."]),
            " hello world."
        )
    }

    func testJoinedTextPreservesMacOSRawWhitespacePolicy() {
        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText(["  hello", "\nworld  "]),
            "  hello\nworld  "
        )
    }

    func testJoinedTextReturnsEmptyForNoSegments() {
        XCTAssertEqual(VoiceInkWhisperTranscriptSegments.joinedText([]), "")
    }

    func testJoinedTextFromSegmentLookupPreservesRawOrderAndSkipsMissingSegments() {
        let segments: [Int32: String] = [
            0: " hello",
            2: " world"
        ]

        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText(segmentCount: 3) { segments[$0] },
            " hello world"
        )
    }

    func testJoinedTextFromSegmentLookupReturnsEmptyForNonPositiveCounts() {
        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText(segmentCount: 0) { _ in "ignored" },
            ""
        )
        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText(segmentCount: -1) { _ in "ignored" },
            ""
        )
    }
}
