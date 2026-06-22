import Foundation
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

    func testCompletedResultDerivesDurationAndPreservesMetadata() {
        let result = VoiceInkAIEnhancementResult.completed(
            text: "enhanced",
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 12.5),
            modelName: "gpt-5.4",
            promptName: "Polish",
            requestSystemMessage: "system",
            requestUserMessage: "user"
        )

        XCTAssertEqual(result.text, "enhanced")
        XCTAssertEqual(result.duration, 2.5)
        XCTAssertEqual(result.modelName, "gpt-5.4")
        XCTAssertEqual(result.promptName, "Polish")
        XCTAssertEqual(result.requestSystemMessage, "system")
        XCTAssertEqual(result.requestUserMessage, "user")
    }
}
