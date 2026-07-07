import Foundation
import VoiceInkCore

final class AIPromptPublicAPITests: XCTestCase {
    func testMovedAIPromptSymbolsExposePublicAPI() throws {
        XCTAssertEqual(
            VoiceInkAIPrompts.finalPromptText("Answer directly.", useSystemInstructions: false),
            "Answer directly."
        )
        XCTAssertTrue(VoiceInkAIPrompts.assistantMode.contains("You are a powerful AI assistant."))
        XCTAssertEqual(
            VoiceInkAIRequestPrompts.taggedTranscript("raw text"),
            "\n<TRANSCRIPT>\nraw text\n</TRANSCRIPT>"
        )

        let payload = try XCTUnwrap(VoiceInkAIEnhancementRequestPayload(transcript: "raw text"))
        XCTAssertEqual(payload.userMessage, VoiceInkAIRequestPrompts.taggedTranscript("raw text"))
        XCTAssertEqual(
            VoiceInkAIEnhancementRequestPayload.enhancedText(from: "<think>notes</think>\nClean text"),
            "Clean text"
        )
        XCTAssertEqual(
            try VoiceInkAIEnhancementRequestPreparation.preparing(transcript: "", isConfigured: true),
            .skipEmptyTranscript
        )

        let systemMessage = VoiceInkAIEnhancementPromptBuilder.systemMessage(
            basePrompt: "Clean this transcript.",
            context: VoiceInkAIEnhancementPromptContext(
                selectedText: "selected",
                clipboardText: "clipboard",
                currentWindowText: "window",
                customVocabulary: "Roma"
            )
        )
        XCTAssertTrue(systemMessage.contains("<CURRENTLY_SELECTED_TEXT>"))
        XCTAssertTrue(systemMessage.contains("<CLIPBOARD_CONTEXT>"))
        XCTAssertTrue(systemMessage.contains("<CURRENT_WINDOW_CONTEXT>"))
        XCTAssertTrue(systemMessage.contains("<CUSTOM_VOCABULARY>"))

        let window = VoiceInkScreenCaptureWindowFacts(
            processID: 12,
            layer: 0,
            isOnScreen: true,
            title: "Spec.md",
            applicationName: "Zed"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementScreenContext.contextText(window: window, extractedText: "Roadmap"),
            """
            Active Window: Spec.md
            Application: Zed

            Window Content:
            Roadmap
            """
        )
        XCTAssertEqual(
            VoiceInkSelectedTextDiagnostics.fetchFailedMessage(errorDescription: "permission denied"),
            "Failed to get selected text: permission denied"
        )
    }
}
