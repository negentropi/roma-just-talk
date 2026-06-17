import Foundation
@testable import VoiceInkCore

final class ContextualCapitalizationFormatterTests: XCTestCase {
    func testLowercasesTitlecaseTextAfterMidSentencePrefix() {
        let result = VoiceInkContextualCapitalizationFormatter.format(
            "Model output",
            beforeCursor: "this is the "
        )

        XCTAssertEqual(result, "model output")
    }

    func testKeepsTitlecaseTextAfterSentenceBoundary() {
        let result = VoiceInkContextualCapitalizationFormatter.format(
            "Model output",
            beforeCursor: "this is done. "
        )

        XCTAssertEqual(result, "Model output")
    }

    func testCapitalizesLowercaseTextAtDocumentStart() {
        let result = VoiceInkContextualCapitalizationFormatter.format(
            "model output",
            beforeCursor: ""
        )

        XCTAssertEqual(result, "Model output")
    }

    func testPreservesAcronymsAfterMidSentencePrefix() {
        let result = VoiceInkContextualCapitalizationFormatter.format(
            "API response",
            beforeCursor: "call the "
        )

        XCTAssertEqual(result, "API response")
    }

    func testSkipsCursorContextWhenTextCannotChange() {
        XCTAssertFalse(VoiceInkContextualCapitalizationFormatter.needsCursorContext("API response"))
        XCTAssertFalse(VoiceInkContextualCapitalizationFormatter.needsCursorContext("iPhone setup"))
        XCTAssertFalse(VoiceInkContextualCapitalizationFormatter.needsCursorContext("1234"))
    }

    func testReadsCursorContextWhenTextCanChange() {
        XCTAssertTrue(VoiceInkContextualCapitalizationFormatter.needsCursorContext("Model output"))
        XCTAssertTrue(VoiceInkContextualCapitalizationFormatter.needsCursorContext("model output"))
    }
}
