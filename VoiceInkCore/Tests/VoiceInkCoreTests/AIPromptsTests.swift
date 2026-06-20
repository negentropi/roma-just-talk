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

    func testEnhancementPromptBuilderAppendsContextSectionsInMacOSOrder() {
        let systemMessage = VoiceInkAIEnhancementPromptBuilder.systemMessage(
            basePrompt: "Clean this transcript.",
            context: VoiceInkAIEnhancementPromptContext(
                selectedText: "selected text",
                clipboardText: "clipboard text",
                currentWindowText: "window text",
                customVocabulary: "Roma\nFelix"
            )
        )

        XCTAssertEqual(
            systemMessage,
            """
            Clean this transcript.

            <CURRENTLY_SELECTED_TEXT>
            selected text
            </CURRENTLY_SELECTED_TEXT>

            <CLIPBOARD_CONTEXT>
            clipboard text
            </CLIPBOARD_CONTEXT>

            <CURRENT_WINDOW_CONTEXT>
            window text
            </CURRENT_WINDOW_CONTEXT>

            The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
            <CUSTOM_VOCABULARY>
            Roma
            Felix
            </CUSTOM_VOCABULARY>
            """
        )
    }

    func testEnhancementPromptBuilderSkipsMissingAndEmptyContextSections() {
        XCTAssertEqual(
            VoiceInkAIEnhancementPromptBuilder.systemMessage(
                basePrompt: "Clean this transcript.",
                context: VoiceInkAIEnhancementPromptContext(
                    selectedText: "",
                    clipboardText: nil,
                    currentWindowText: "",
                    customVocabulary: ""
                )
            ),
            "Clean this transcript."
        )
    }

    func testEnhancementVocabularyContextFormatsTermsInOrder() {
        XCTAssertEqual(
            VoiceInkAIEnhancementVocabularyContext.formatted(from: ["Roma", "Felix", "SwiftData"]),
            "Important Vocabulary: Roma, Felix, SwiftData"
        )
    }

    func testEnhancementVocabularyContextNormalizesRawTermsForPostProcessing() {
        XCTAssertEqual(
            VoiceInkAIEnhancementVocabularyContext.formatted(from: [" Roma ", "", "roma", "Felix"]),
            "Important Vocabulary: Roma, Felix"
        )
    }

    func testEnhancementVocabularyContextReturnsEmptyForNoTerms() {
        XCTAssertEqual(
            VoiceInkAIEnhancementVocabularyContext.formatted(from: []),
            ""
        )
    }

    func testEnhancementRequestPayloadReturnsNilForEmptyTranscript() {
        XCTAssertNil(VoiceInkAIEnhancementRequestPayload(transcript: ""))
    }

    func testEnhancementRequestPayloadPreservesMacOSWhitespaceOnlyTranscriptPolicy() throws {
        let payload = try XCTUnwrap(VoiceInkAIEnhancementRequestPayload(transcript: "   "))

        XCTAssertEqual(
            payload.userMessage,
            "\n<TRANSCRIPT>\n   \n</TRANSCRIPT>"
        )
    }

    func testEnhancementRequestPayloadBuildsTaggedUserMessageAndFiltersProviderOutput() throws {
        let payload = try XCTUnwrap(VoiceInkAIEnhancementRequestPayload(transcript: "raw text"))

        XCTAssertEqual(
            payload.userMessage,
            "\n<TRANSCRIPT>\nraw text\n</TRANSCRIPT>"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRequestPayload.enhancedText(
                from: "<thinking>draft</thinking>\nClean text"
            ),
            "Clean text"
        )
    }
}
