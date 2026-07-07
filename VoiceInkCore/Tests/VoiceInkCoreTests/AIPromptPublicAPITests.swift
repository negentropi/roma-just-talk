import Foundation
import VoiceInkCore

final class AIPromptPublicAPITests: XCTestCase {
    func testMovedAIEnhancementRetrySymbolsExposePublicAPI() async throws {
        XCTAssertEqual(
            VoiceInkAIEnhancementError.transportFailure(.missingAPIKey),
            .notConfigured
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementError.localCLIExecutionFailure(
                VoiceInkLocalCLIExecutionError.timeout(seconds: 45.9)
            ),
            .customError("Local CLI command timed out after 45 seconds.")
        )
        XCTAssertEqual(
            VoiceInkOllamaEnhancementFailure.transportFailure(.httpStatus(404)),
            .modelNotFound
        )
        XCTAssertEqual(
            VoiceInkOllamaServiceDiagnostics.modelFetchFailedMessage(errorDescription: "server down"),
            "Error fetching models: server down"
        )

        var retryState = VoiceInkAIEnhancementRetryState(maxAttempts: 2)
        XCTAssertEqual(retryState.recordFailure(.networkError), .retryAfterDelay(1))

        let plan = retryState.recordNonEnhancementError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        )
        var retryDecisions: [VoiceInkAIEnhancementRetryDecision] = []
        var transportFailures: [Bool] = []
        try await plan?.applyRuntimeState { decision, isTransportNetworkFailure in
            retryDecisions.append(decision)
            transportFailures.append(isTransportNetworkFailure)
        }
        XCTAssertEqual(retryDecisions, [.fail(.networkError)])
        XCTAssertEqual(transportFailures, [true])

        XCTAssertEqual(
            VoiceInkAIEnhancementRateLimitPolicy(minimumInterval: 1).delaySinceLastRequest(
                lastRequest: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 100.25)
            ) ?? -1,
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryProgressPresentation.diagnosticMessage(
                for: .retryImmediately,
                failedAttempts: 1,
                maxAttempts: 3
            ),
            "Request timed out, retrying immediately... (Attempt 1/3)"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementRetryFailurePresentation.diagnosticMessage(
                for: .timeout,
                attempts: 3,
                retryOnTimeoutEnabled: false
            ),
            "Request timed out, failing immediately (retry disabled)."
        )
    }

    func testMovedAIPromptSymbolsExposePublicAPI() throws {
        XCTAssertEqual(
            VoiceInkAIPrompts.finalPromptText("Answer directly.", useSystemInstructions: false),
            "Answer directly."
        )
        XCTAssertTrue(VoiceInkAIPrompts.customPromptTemplate.contains("<SYSTEM_INSTRUCTIONS>"))
        XCTAssertTrue(VoiceInkAIPrompts.assistantMode.contains("You are a powerful AI assistant."))
        XCTAssertEqual(
            VoiceInkAIRequestPrompts.postProcessingSystemPrompt,
            "You are a helpful assistant that rewrites raw speech-to-text transcripts to be concise, well-punctuated, and readable notes, preserving meaning."
        )
        XCTAssertEqual(
            VoiceInkAIRequestPrompts.postProcessingUserPrompt(prompt: "Clean this", transcript: "raw text"),
            "Prompt: Clean this\n\nTranscript:\nraw text"
        )
        XCTAssertEqual(
            VoiceInkAIRequestPrompts.taggedTranscript("raw text"),
            "\n<TRANSCRIPT>\nraw text\n</TRANSCRIPT>"
        )

        let payload = try XCTUnwrap(VoiceInkAIEnhancementRequestPayload(transcript: "raw text"))
        XCTAssertEqual(payload.userMessage, VoiceInkAIRequestPrompts.taggedTranscript("raw text"))
        XCTAssertEqual(
            VoiceInkAIEnhancementOutputFilter.filter("<reasoning>notes</reasoning>\nClean text"),
            "Clean text"
        )
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
        XCTAssertEqual(
            VoiceInkAIEnhancementVocabularyContext.formatted(from: [" Roma ", "Felix"]),
            "Important Vocabulary: Roma, Felix"
        )

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
