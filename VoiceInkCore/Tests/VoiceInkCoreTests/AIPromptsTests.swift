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

    func testSelectedTextDiagnosticsPreservesMacOSFailureCopy() {
        XCTAssertEqual(
            VoiceInkSelectedTextDiagnostics.fetchFailedMessage(errorDescription: "permission denied"),
            "Failed to get selected text: permission denied"
        )
    }

    func testScreenContextPrefersFrontmostVisibleNonSelfWindow() {
        let windows = [
            screenWindow(processID: 7, title: "Background"),
            screenWindow(processID: 42, title: "Self"),
            screenWindow(processID: 9, title: "Frontmost")
        ]

        XCTAssertEqual(
            VoiceInkAIEnhancementScreenContext.preferredWindowIndex(
                in: windows,
                currentProcessID: 42,
                frontmostProcessID: 9
            ),
            2
        )
    }

    func testScreenContextFallsBackToFirstVisibleNonSelfWindow() {
        let windows = [
            screenWindow(processID: 42, title: "Self"),
            screenWindow(processID: 7, layer: 1, title: "Menu"),
            screenWindow(processID: 8, isOnScreen: false, title: "Hidden"),
            screenWindow(processID: 10, title: "Fallback")
        ]

        XCTAssertEqual(
            VoiceInkAIEnhancementScreenContext.preferredWindowIndex(
                in: windows,
                currentProcessID: 42,
                frontmostProcessID: 99
            ),
            3
        )
    }

    func testScreenContextTextPreservesMacOSCaptureCopy() {
        XCTAssertEqual(
            VoiceInkAIEnhancementScreenContext.contextText(
                window: screenWindow(
                    processID: 9,
                    title: "Spec.md",
                    applicationName: "Zed"
                ),
                extractedText: "Roadmap\nArchitecture"
            ),
            """
            Active Window: Spec.md
            Application: Zed

            Window Content:
            Roadmap
            Architecture
            """
        )
    }

    func testScreenContextTextUsesExistingFallbacks() {
        XCTAssertEqual(
            VoiceInkAIEnhancementScreenContext.contextText(
                window: screenWindow(processID: nil, title: nil, applicationName: nil),
                extractedText: ""
            ),
            """
            Active Window: Unknown
            Application: Unknown

            Window Content:
            No text detected via OCR
            """
        )
    }

    func testScreenContextExtractedTextPreservesMacOSOCRAssembly() {
        XCTAssertEqual(
            VoiceInkAIEnhancementScreenContext.extractedText(
                fromRecognizedCandidates: ["Roadmap", "Architecture"]
            ),
            "Roadmap\nArchitecture"
        )
        XCTAssertNil(
            VoiceInkAIEnhancementScreenContext.extractedText(
                fromRecognizedCandidates: []
            )
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

    func testPostProcessingRequestRejectsBlankPrompt() {
        XCTAssertNil(VoiceInkPostProcessingRequest(prompt: " \n\t ", transcript: "raw text"))
    }

    func testPostProcessingRequestBuildsSharedIOSMessages() async throws {
        let request = try XCTUnwrap(
            VoiceInkPostProcessingRequest(
                prompt: "Clean this",
                transcript: "raw text"
            )
        )

        let summary = try await request.applyRuntimeState { messages, temperature in
            (messages, temperature)
        }

        XCTAssertEqual(summary.1, 0.2)
        XCTAssertEqual(
            summary.0,
            [
                VoiceInkOpenAICompatibleChatMessage(
                    role: "system",
                    content: "You are a helpful assistant that rewrites raw speech-to-text transcripts to be concise, well-punctuated, and readable notes, preserving meaning."
                ),
                VoiceInkOpenAICompatibleChatMessage(
                    role: "user",
                    content: "Prompt: Clean this\n\nTranscript:\nraw text"
                )
            ]
        )
    }

    func testPostProcessingFinalizedTranscriptFallsBackWhenFilteredResponseIsEmpty() {
        let fallbackTranscript = "raw text"

        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: "",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: "   \n ",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: "<think>hidden reasoning</think>",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
    }

    func testPostProcessingFinalizedTranscriptStripsReasoningTags() {
        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: "<thinking>draft</thinking>\nClean text\n<reasoning>notes</reasoning>",
                fallbackTranscript: "raw text"
            ),
            "Clean text"
        )
    }

    func testPostProcessingFinalizedTranscriptStripsCodexFollowUpPayload() {
        let response = """
        Regards.

        ```json
        {
          "codex_follow_up": true,
          "title": "Follow-up",
          "items": [
            {
              "prompt": "Clean up another short transcript"
            }
          ]
        }
        ```
        """

        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: response,
                fallbackTranscript: "raw text"
            ),
            "Regards."
        )
    }

    func testEnhancementRequestPreparationPreservesMacOSPreflightPolicy() throws {
        do {
            _ = try VoiceInkAIEnhancementRequestPreparation.preparing(
                transcript: "raw text",
                isConfigured: false
            )
            XCTFail("Expected notConfigured error")
        } catch let error as VoiceInkAIEnhancementError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            try VoiceInkAIEnhancementRequestPreparation.preparing(
                transcript: "",
                isConfigured: true
            ),
            .skipEmptyTranscript
        )
        XCTAssertEqual(
            try VoiceInkAIEnhancementRequestPreparation.preparing(
                transcript: "raw text",
                isConfigured: true
            ),
            .execute(try XCTUnwrap(VoiceInkAIEnhancementRequestPayload(transcript: "raw text")))
        )
    }
}

private func screenWindow(
    processID: Int?,
    layer: Int = 0,
    isOnScreen: Bool = true,
    title: String? = nil,
    applicationName: String? = "App"
) -> VoiceInkScreenCaptureWindowFacts {
    VoiceInkScreenCaptureWindowFacts(
        processID: processID,
        layer: layer,
        isOnScreen: isOnScreen,
        title: title,
        applicationName: applicationName
    )
}
