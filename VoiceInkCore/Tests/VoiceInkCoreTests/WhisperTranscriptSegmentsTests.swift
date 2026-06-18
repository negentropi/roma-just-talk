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
}
