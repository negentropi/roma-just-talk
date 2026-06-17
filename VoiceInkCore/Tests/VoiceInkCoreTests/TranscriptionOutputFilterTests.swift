import Foundation
@testable import VoiceInkCore

final class TranscriptionOutputFilterTests: XCTestCase {
    func testFilterRemovesTagBlocksAndBracketedHallucinations() {
        XCTAssertEqual(
            VoiceInkTranscriptionOutputFilter.filter("Hello [music] <noise>discard</noise> world"),
            "Hello world"
        )
    }

    func testFilterCanRemoveConfiguredFillerWordsCaseInsensitively() {
        XCTAssertEqual(
            VoiceInkTranscriptionOutputFilter.filter("Um, this is LIKE ready.", fillerWords: ["um", "like"]),
            "this is ready."
        )
    }

    func testDefaultWhitespacePolicyCollapsesAllRunsForMacOSOutputFilterCompatibility() {
        XCTAssertEqual(
            VoiceInkTranscriptionOutputFilter.filter("hello\n\nworld"),
            "hello world"
        )
    }

    func testPreserveParagraphsPolicyKeepsParagraphBreaksForRunProcessor() {
        XCTAssertEqual(
            VoiceInkTranscriptionOutputFilter.filter(
                "hello\n\n\nworld",
                whitespacePolicy: .preserveParagraphs
            ),
            "hello\n\n\nworld"
        )
    }
}
