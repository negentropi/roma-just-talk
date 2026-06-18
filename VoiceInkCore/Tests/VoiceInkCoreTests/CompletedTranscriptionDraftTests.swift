@testable import VoiceInkCore

final class CompletedTranscriptionDraftTests: XCTestCase {
    func testDraftStoresSuccessfulEnhancementMetadata() {
        let result = VoiceInkAIEnhancementResult(
            text: "enhanced text",
            duration: 1.25,
            modelName: "gpt-5",
            promptName: "Assistant",
            requestSystemMessage: "system",
            requestUserMessage: "user"
        )

        let draft = VoiceInkCompletedTranscriptionDraft(
            cleanedText: "clean text",
            duration: 3.5,
            audioFileURL: "file:///recording.wav",
            transcriptionModelName: "Parakeet",
            transcriptionDuration: 0.75,
            powerModeName: "Focus",
            powerModeEmoji: "F",
            enhancementResult: result
        )

        XCTAssertEqual(draft.text, "clean text")
        XCTAssertEqual(draft.duration, 3.5)
        XCTAssertEqual(draft.enhancedText, "enhanced text")
        XCTAssertEqual(draft.audioFileURL, "file:///recording.wav")
        XCTAssertEqual(draft.transcriptionModelName, "Parakeet")
        XCTAssertEqual(draft.aiEnhancementModelName, "gpt-5")
        XCTAssertEqual(draft.promptName, "Assistant")
        XCTAssertEqual(draft.transcriptionDuration, 0.75)
        XCTAssertEqual(draft.enhancementDuration, 1.25)
        XCTAssertEqual(draft.aiRequestSystemMessage, "system")
        XCTAssertEqual(draft.aiRequestUserMessage, "user")
        XCTAssertEqual(draft.powerModeName, "Focus")
        XCTAssertEqual(draft.powerModeEmoji, "F")
        XCTAssertEqual(draft.transcriptionStatus, .completed)
    }

    func testFailurePolicyCanStoreSharedFailureTextAndClearEnhancementMetadata() {
        let draft = VoiceInkCompletedTranscriptionDraft(
            cleanedText: "clean text",
            duration: 3.5,
            audioFileURL: "file:///recording.wav",
            transcriptionModelName: "Parakeet",
            transcriptionDuration: 0.75,
            enhancementFailureReason: "timeout",
            enhancementFailurePolicy: .storeFailureText
        )

        XCTAssertEqual(draft.enhancedText, "Enhancement failed: timeout")
        XCTAssertNil(draft.aiEnhancementModelName)
        XCTAssertNil(draft.promptName)
        XCTAssertNil(draft.enhancementDuration)
        XCTAssertNil(draft.aiRequestSystemMessage)
        XCTAssertNil(draft.aiRequestUserMessage)
        XCTAssertEqual(draft.transcriptionStatus, .completed)
    }

    func testFailurePolicyCanOmitEnhancedText() {
        let draft = VoiceInkCompletedTranscriptionDraft(
            cleanedText: "clean text",
            duration: 3.5,
            audioFileURL: "file:///recording.wav",
            transcriptionModelName: "Parakeet",
            transcriptionDuration: 0.75,
            enhancementFailureReason: "timeout",
            enhancementFailurePolicy: .omitEnhancedText
        )

        XCTAssertNil(draft.enhancedText)
        XCTAssertNil(draft.aiEnhancementModelName)
        XCTAssertNil(draft.promptName)
        XCTAssertNil(draft.enhancementDuration)
        XCTAssertNil(draft.aiRequestSystemMessage)
        XCTAssertNil(draft.aiRequestUserMessage)
        XCTAssertEqual(draft.transcriptionStatus, .completed)
    }
}
