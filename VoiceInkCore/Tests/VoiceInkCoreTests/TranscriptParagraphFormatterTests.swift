import Foundation
@testable import VoiceInkCore

final class TranscriptParagraphFormatterTests: XCTestCase {
    func testFormatReturnsEmptyForWhitespaceOnlyInput() {
        XCTAssertEqual(VoiceInkTranscriptParagraphFormatter.format(" \n\t "), "")
    }

    func testFormatTrimsAndKeepsShortTextInOneParagraph() {
        XCTAssertEqual(
            VoiceInkTranscriptParagraphFormatter.format("  This is one sentence. This is another sentence.  "),
            "This is one sentence. This is another sentence."
        )
    }

    func testFormatSplitsAfterFourSignificantSentencesWhenChunkHitsWordTarget() {
        let sentence = "This sentence has many ordinary English words that should count clearly in tokenizer."
        let input = Array(repeating: sentence, count: 5).joined(separator: " ")
        let firstParagraph = Array(repeating: sentence, count: 4).joined(separator: " ")
        let expected = "\(firstParagraph)\n\n\(sentence)"

        XCTAssertEqual(VoiceInkTranscriptParagraphFormatter.format(input), expected)
    }
}
