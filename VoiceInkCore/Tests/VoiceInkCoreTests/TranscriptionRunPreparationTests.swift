import Foundation
import VoiceInkCore

final class TranscriptionRunPreparationTests: XCTestCase {
    func testMovedTranscriptionRunPreparationSymbolsExposePublicAPI() {
        let skipConfiguration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 2
        )

        XCTAssertTrue(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "Roma works",
            configuration: skipConfiguration,
            promptTriggerForcesPostProcessing: false
        ))
        XCTAssertEqual(VoiceInkWordCounter.count(in: "Roma works"), 2)
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.directTranscription.requestPrompt(" spell Roma "),
            " spell Roma "
        )
        XCTAssertNil(VoiceInkTranscriptionPromptUse.recordedFileTranscription(.deepgram).requestPrompt("ignored"))

        let preparedText = VoiceInkTranscriptionRunPreparation.prepareRawText(
            "Hello.",
            cleanupConfiguration: .disabled
        )
        XCTAssertEqual(preparedText.filteredText, "Hello.")
        XCTAssertEqual(preparedText.transcript(for: .cleanedText), "Hello.")
        XCTAssertTrue(preparedText.shouldSkipPostProcessing(configuration: skipConfiguration))

        let enhancementPlan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
            "Hello.",
            cleanupConfiguration: .disabled
        )
        XCTAssertEqual(
            enhancementPlan.enhancementRequest(
                isEnhancementEnabled: true,
                isEnhancementConfigured: true
            )?.text,
            "Hello."
        )
        XCTAssertEqual(VoiceInkTranscriptionEnhancementRequest(text: "raw").text, "raw")
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

    func testNonBlankRequestPromptDropsBlankAndPreservesOriginalText() {
        XCTAssertNil(VoiceInkTranscriptionPromptUse.nonBlankRequestPrompt(nil))
        XCTAssertNil(VoiceInkTranscriptionPromptUse.nonBlankRequestPrompt(" \n\t "))
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.nonBlankRequestPrompt(" spell Roma correctly "),
            " spell Roma correctly "
        )
    }

    func testRecordedFilePromptUseKeepsSupportedProviderPrompts() {
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.groq)
                .requestPrompt("spell Roma correctly"),
            "spell Roma correctly"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.openAI)
                .requestPrompt("spell Roma correctly"),
            "spell Roma correctly"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.assemblyAI)
                .requestPrompt("spell Roma correctly"),
            "spell Roma correctly"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.localWhisper)
                .requestPrompt("Use custom language prompt."),
            "Use custom language prompt."
        )
    }

    func testRecordedFilePromptUseDropsUnsupportedProviderPrompts() {
        XCTAssertNil(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.deepgram)
                .requestPrompt("ignored")
        )
        XCTAssertNil(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.gemini)
                .requestPrompt("ignored")
        )
        XCTAssertNil(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.soniox)
                .requestPrompt("ignored")
        )
    }

    func testStreamingPromptUseKeepsOnlyAssemblyAIPrompts() {
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.streamingTranscription(.assemblyAI)
                .requestPrompt("spell project names"),
            "spell project names"
        )
        XCTAssertNil(
            VoiceInkTranscriptionPromptUse.streamingTranscription(.deepgram)
                .requestPrompt("ignored")
        )
    }

    func testDirectTranscriptionPromptUseKeepsPrompt() {
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.directTranscription.requestPrompt("custom endpoint prompt"),
            "custom endpoint prompt"
        )
    }

    func testWordCounterCountsNaturalLanguageWords() {
        XCTAssertEqual(VoiceInkWordCounter.count(in: "quick release wins"), 3)
    }

    func testWordCounterIgnoresWhitespaceOnlyText() {
        XCTAssertEqual(VoiceInkWordCounter.count(in: " \n\t "), 0)
    }

    func testWordCounterCountsWordsAcrossPunctuation() {
        XCTAssertEqual(VoiceInkWordCounter.count(in: "Yes, Roma works."), 3)
    }

    func testPostProcessingSkipCurrentConfigurationUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkPostProcessingSkipConfiguration.current(in: defaults),
                VoiceInkPostProcessingSkipConfiguration(
                    isEnabled: VoiceInkPreferenceDefault.skipShortEnhancement,
                    wordThreshold: VoiceInkPreferenceDefault.shortEnhancementWordThreshold
                )
            )
        }
    }

    func testPostProcessingSkipCurrentConfigurationReadsSharedStorageKeys() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: VoiceInkUserDefaultsKey.skipShortEnhancement)
            defaults.set(7, forKey: VoiceInkUserDefaultsKey.shortEnhancementWordThreshold)

            XCTAssertEqual(
                VoiceInkPostProcessingSkipConfiguration.current(in: defaults),
                VoiceInkPostProcessingSkipConfiguration(isEnabled: false, wordThreshold: 7)
            )
        }
    }

    func testPostProcessingSkipDisabledPolicyNeverSkipsPostProcessing() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: false,
            wordThreshold: 3
        )

        XCTAssertFalse(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "yes",
            configuration: configuration,
            promptTriggerForcesPostProcessing: false
        ))
    }

    func testPostProcessingSkipEnabledPolicySkipsAtOrBelowThreshold() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertTrue(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "yes thank you",
            configuration: configuration,
            promptTriggerForcesPostProcessing: false
        ))
    }

    func testPostProcessingSkipEnabledPolicyKeepsPostProcessingAboveThreshold() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertFalse(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "please summarize this longer note",
            configuration: configuration,
            promptTriggerForcesPostProcessing: false
        ))
    }

    func testPostProcessingSkipPromptTriggerForcesPostProcessingForShortTranscript() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertFalse(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "email john",
            configuration: configuration,
            promptTriggerForcesPostProcessing: true
        ))
    }

    func testPostProcessingSkipNonPositiveThresholdFallsBackToExistingDefault() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 0
        )

        XCTAssertEqual(
            configuration.wordThreshold,
            VoiceInkPreferenceDefault.shortEnhancementWordThreshold
        )
        XCTAssertTrue(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "yes thank you",
            configuration: configuration,
            promptTriggerForcesPostProcessing: false
        ))
    }

    func testPrepareRawTextFiltersThenPreparesTranscriptText() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: .removeTrailingPeriod,
            shouldFormatParagraphs: false,
            shouldLowercase: true,
            shouldRemoveFillerWords: true,
            fillerWords: ["um"]
        )

        let prepared = VoiceInkTranscriptionRunPreparation.prepareRawText(
            "Um Hello.",
            cleanupConfiguration: configuration
        ) { text in
            text.replacingOccurrences(of: "Hello", with: "ROMA")
        }

        XCTAssertEqual(prepared.filteredText, "Hello.")
        XCTAssertEqual(prepared.textForWordReplacement, "Hello.")
        XCTAssertEqual(prepared.wordReplacedText, "ROMA.")
        XCTAssertEqual(prepared.cleanedText, "roma")
    }

    func testPrepareRawTextCanPreserveParagraphWhitespaceForRunProcessor() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            shouldFormatParagraphs: false,
            shouldLowercase: false,
            shouldRemoveFillerWords: false
        )

        let prepared = VoiceInkTranscriptionRunPreparation.prepareRawText(
            "First line.\n\nSecond line.",
            cleanupConfiguration: configuration,
            whitespacePolicy: .preserveParagraphs,
            normalizeParagraphSpacingBeforeFormatting: true
        )

        XCTAssertEqual(prepared.filteredText, "First line.\n\nSecond line.")
        XCTAssertEqual(prepared.cleanedText, "First line.\n\nSecond line.")
    }

    func testPostProcessingSkipCanUseCleanedOrWordReplacedText() {
        let prepared = VoiceInkTranscriptionRunPreparedText(
            filteredText: "raw",
            preparedText: VoiceInkPreparedTranscriptionText(
                textForWordReplacement: "raw",
                wordReplacedText: "one two three four",
                cleanedText: "one"
            )
        )
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertTrue(prepared.shouldSkipPostProcessing(configuration: configuration))
        XCTAssertFalse(prepared.shouldSkipPostProcessing(
            configuration: configuration,
            transcriptRole: .wordReplacedText
        ))
    }

    func testPromptTriggerKeepsPostProcessingForShortTranscript() {
        let prepared = VoiceInkTranscriptionRunPreparation.prepareFilteredText(
            "one",
            cleanupConfiguration: .disabled
        )
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )

        XCTAssertFalse(prepared.shouldSkipPostProcessing(
            configuration: configuration,
            promptTriggerForcesPostProcessing: true
        ))
    }

    func testEnhancementTextPlanFiltersPreparesAndSelectsEnhancementText() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: .removeTrailingPeriod,
            shouldFormatParagraphs: false,
            shouldLowercase: true,
            shouldRemoveFillerWords: true,
            fillerWords: ["um"]
        )

        let plan = VoiceInkTranscriptionRunPreparation.prepareRawTextForEnhancement(
            "Um Hello.",
            cleanupConfiguration: configuration
        ) { text in
            text.replacingOccurrences(of: "Hello", with: "ROMA")
        }

        XCTAssertEqual(plan.filteredText, "Hello.")
        XCTAssertEqual(plan.textForEnhancement, "ROMA.")
        XCTAssertEqual(plan.cleanedText, "roma")
    }

    func testEnhancementTextPlanCanUseAlreadyFilteredText() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            shouldFormatParagraphs: false,
            shouldLowercase: true,
            shouldRemoveFillerWords: false
        )

        let plan = VoiceInkTranscriptionRunPreparation.prepareFilteredTextForEnhancement(
            "Hello.",
            cleanupConfiguration: configuration
        ) { text in
            text.replacingOccurrences(of: "Hello", with: "ROMA")
        }

        XCTAssertEqual(plan.filteredText, "Hello.")
        XCTAssertEqual(plan.textForEnhancement, "ROMA.")
        XCTAssertEqual(plan.cleanedText, "roma.")
    }

    func testAudioFileTextPlanFiltersPreparesAndSelectsEnhancementText() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: .removeTrailingPeriod,
            shouldFormatParagraphs: false,
            shouldLowercase: true,
            shouldRemoveFillerWords: true,
            fillerWords: ["um"]
        )

        let plan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
            "Um Hello.",
            cleanupConfiguration: configuration
        ) { text in
            text.replacingOccurrences(of: "Hello", with: "ROMA")
        }

        XCTAssertEqual(plan.textForEnhancement, "ROMA.")
        XCTAssertEqual(plan.cleanedText, "roma")
    }

    func testAudioFileTextPlanSkipUsesEnhancementTextAndPromptTrigger() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )
        let longEnhancementPlan = VoiceInkTranscriptionEnhancementTextPlan(
            textForEnhancement: "one two three four",
            cleanedText: "one"
        )
        let shortEnhancementPlan = VoiceInkTranscriptionEnhancementTextPlan(
            textForEnhancement: "one",
            cleanedText: "one two three four"
        )

        XCTAssertFalse(longEnhancementPlan.shouldSkipEnhancement(configuration: configuration))
        XCTAssertTrue(shortEnhancementPlan.shouldSkipEnhancement(configuration: configuration))
        XCTAssertFalse(shortEnhancementPlan.shouldSkipEnhancement(
            configuration: configuration,
            promptTriggerForcesEnhancement: true
        ))
        XCTAssertFalse(shortEnhancementPlan.shouldSkipEnhancement(configuration: nil))
    }

    func testEnhancementRequestRequiresEnabledConfiguredAndUnskippedText() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )
        let plan = VoiceInkTranscriptionEnhancementTextPlan(
            textForEnhancement: "one two three four",
            cleanedText: "one"
        )
        let shortPlan = VoiceInkTranscriptionEnhancementTextPlan(
            textForEnhancement: "one",
            cleanedText: "one"
        )

        XCTAssertNil(plan.enhancementRequest(
            isEnhancementEnabled: false,
            isEnhancementConfigured: true,
            skipConfiguration: configuration
        ))
        XCTAssertNil(plan.enhancementRequest(
            isEnhancementEnabled: true,
            isEnhancementConfigured: false,
            skipConfiguration: configuration
        ))
        XCTAssertNil(shortPlan.enhancementRequest(
            isEnhancementEnabled: true,
            isEnhancementConfigured: true,
            skipConfiguration: configuration
        ))
        XCTAssertEqual(plan.enhancementRequest(
            isEnhancementEnabled: true,
            isEnhancementConfigured: true,
            skipConfiguration: configuration
        )?.text, "one two three four")
    }

    func testEnhancementRequestUsesPromptDetectedTextAndForcesShortText() {
        let configuration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 3
        )
        let promptId = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let plan = VoiceInkTranscriptionEnhancementTextPlan(
            textForEnhancement: "trigger",
            cleanedText: "trigger"
        )
        let promptDetectionResult = VoiceInkPromptDetectionResult(
            shouldEnableAI: true,
            selectedPromptId: promptId,
            processedText: "without trigger",
            detectedTriggerWord: "trigger",
            originalEnhancementState: false,
            originalPromptId: nil
        )

        XCTAssertEqual(plan.enhancementRequest(
            isEnhancementEnabled: true,
            isEnhancementConfigured: true,
            promptDetectionResult: promptDetectionResult,
            skipConfiguration: configuration
        )?.text, "without trigger")
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.TranscriptionRunPreparationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
