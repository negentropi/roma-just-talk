import Foundation
@testable import VoiceInkCore

final class AIPromptsTests: XCTestCase {
    func testFinalPromptTextReturnsRawPromptWithoutSystemInstructions() {
        XCTAssertEqual(
            VoiceInkAIPrompts.finalPromptText("Answer the user directly.", useSystemInstructions: false),
            "Answer the user directly."
        )
    }

    func testFinalPromptTextWrapsPromptWithSystemInstructions() {
        let finalPrompt = VoiceInkAIPrompts.finalPromptText(
            "Clean this transcript.",
            useSystemInstructions: true
        )

        XCTAssertTrue(finalPrompt.contains("Clean this transcript."))
        XCTAssertTrue(finalPrompt.contains("[FINAL WARNING]"))
        XCTAssertTrue(finalPrompt.contains("OUTPUT ONLY THE CLEANED UP TEXT"))
    }
}
