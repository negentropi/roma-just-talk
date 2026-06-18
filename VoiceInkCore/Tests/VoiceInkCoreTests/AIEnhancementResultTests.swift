import VoiceInkCore

final class AIEnhancementResultTests: XCTestCase {
    func testResultCarriesMacOSPostProcessingMetadata() {
        let result = VoiceInkAIEnhancementResult(
            text: "enhanced",
            duration: 1.25,
            modelName: "gpt-4.1",
            promptName: "Meeting notes",
            requestSystemMessage: "system",
            requestUserMessage: "<transcript>raw</transcript>"
        )

        XCTAssertEqual(result.text, "enhanced")
        XCTAssertEqual(result.duration, 1.25)
        XCTAssertEqual(result.modelName, "gpt-4.1")
        XCTAssertEqual(result.promptName, "Meeting notes")
        XCTAssertEqual(result.requestSystemMessage, "system")
        XCTAssertEqual(result.requestUserMessage, "<transcript>raw</transcript>")
    }
}
