import Foundation
import NaturalLanguage
@testable import VoiceInkCore

final class TranscriptionRunProcessorTests: XCTestCase {
    func testWordCounterCountsWordsWithExplicitLanguageAcrossPunctuation() {
        XCTAssertEqual(
            VoiceInkWordCounter.count(in: "Yes, Roma works.", language: .english),
            3
        )
    }

    func testAIEnhancementResultCarriesMacOSPostProcessingMetadata() {
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

    func testCompletedAIEnhancementResultDerivesDurationAndPreservesMetadata() {
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

    func testTranscribeNormalizesTextAndSkipsPostProcessingWhenDisabled() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: false),
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "hello\n\n\nworld")
            }
        )

        XCTAssertEqual(result.cleanedText, "hello\n\nworld")
        XCTAssertEqual(result.finalText, "hello\n\nworld")
        XCTAssertNil(result.enhancedText)
        XCTAssertNil(result.aiEnhancementModelName)
        XCTAssertNil(result.postProcessingError)
        XCTAssertFalse(result.postProcessingSucceeded)
    }

    func testTranscribeFiltersRawOutputBeforePostProcessing() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(job.transcript, "hello\n\nworld")
            return job.transcript
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "<noise>discard</noise>hello [music]\n\n\nworld")
            }
        )

        XCTAssertEqual(result.cleanedText, "hello\n\nworld")
        XCTAssertEqual(result.finalText, "hello\n\nworld")
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testTranscribeAppliesCleanupPreferencesBeforePostProcessing() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(job.transcript, "hello world")
            return job.transcript
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration(
                punctuationMode: .removeAll,
                shouldLowercase: true
            ),
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "Hello, WORLD.")
            }
        )

        XCTAssertEqual(result.cleanedText, "hello world")
        XCTAssertEqual(result.finalText, "hello world")
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testTranscribeAppliesFillerWordCleanupBeforePostProcessing() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(job.transcript, "hello world")
            return job.transcript
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration(
                shouldRemoveFillerWords: true,
                fillerWords: ["um", "like"]
            ),
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "um, hello like world")
            }
        )

        XCTAssertEqual(result.cleanedText, "hello world")
        XCTAssertEqual(result.finalText, "hello world")
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testTranscribeAppliesParagraphFormattingBeforePostProcessing() async throws {
        let sentence = "This sentence has many ordinary English words that should count clearly in tokenizer."
        let input = Array(repeating: sentence, count: 5).joined(separator: " ")
        let firstParagraph = Array(repeating: sentence, count: 4).joined(separator: " ")
        let expected = "\(firstParagraph)\n\n\(sentence)"
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(job.transcript, expected)
            return job.transcript
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration(
                shouldFormatParagraphs: true
            ),
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: input)
            }
        )

        XCTAssertEqual(result.cleanedText, expected)
        XCTAssertEqual(result.finalText, expected)
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testTranscribeAppliesWordReplacementBeforePostProcessing() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(job.transcript, "hello Roma Just Talk")
            return job.transcript
        }
        let rules = [
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ]

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            applyingWordReplacements: { text in
                VoiceInkWordReplacementEngine.apply(rules, to: text)
            },
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "hello roma")
            }
        )

        XCTAssertEqual(result.cleanedText, "hello Roma Just Talk")
        XCTAssertEqual(result.finalText, "hello Roma Just Talk")
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testTranscriptionRunSettingsApplySnapshotFieldsThroughSharedProcessor() async throws {
        let service = CapturingTranscriptionService(text: "Hello, roma")
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Short transcript policy should skip post-processing")
            return "unexpected"
        }
        let settings = VoiceInkTranscriptionRunSettings(
            configuration: configuration(transcriptionProvider: .assemblyAI, isPostProcessingEnabled: true),
            cleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration(
                punctuationMode: .removeAll
            ),
            postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration(
                isEnabled: true,
                wordThreshold: 10
            ),
            transcriptionLanguage: "fr",
            transcriptionPrompt: "spell Roma as Roma",
            wordReplacementRules: [
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ],
            customVocabulary: [" Roma ", "Felix", "roma", ""]
        )

        let result = try await settings.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            processor: processor,
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in service }
        )

        XCTAssertEqual(service.capturedLanguage, "fr")
        XCTAssertEqual(service.capturedPrompt, "spell Roma as Roma")
        XCTAssertEqual(service.capturedCustomVocabulary, ["Roma", "Felix"])
        XCTAssertEqual(result.cleanedText, "Hello Roma Just Talk")
        XCTAssertEqual(result.finalText, "Hello Roma Just Talk")
        XCTAssertFalse(result.postProcessingSucceeded)
    }

    func testIOSAppSettingsRunSnapshotBuildsRunSettings() {
        let suiteName = "VoiceInkCore.TranscriptionRunProcessorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mode = Mode(
            name: "Meeting",
            transcriptionProvider: .assemblyAI,
            transcriptionModel: "slam-1",
            isPostProcessingEnabled: true,
            postProcessingProvider: .openAI,
            postProcessingModel: "gpt-4o-mini"
        )
        PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.skipShortEnhancement)
        defaults.set(8, forKey: VoiceInkUserDefaultsKey.shortEnhancementWordThreshold)
        VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(["fr": "French Roma style"], to: defaults)

        let expectedRuntimeConfiguration = [mode].runtimeConfiguration(selectedModeId: mode.id)
        let settings = VoiceInkIOSAppSettingsRunSnapshot(
            modes: [mode],
            selectedModeId: mode.id,
            selectedTranscriptionLanguage: "fr",
            wordReplacementRules: [
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ],
            customVocabulary: [" Roma ", "Felix", "roma", ""]
        ).transcriptionRunSettings(defaults: defaults)

        XCTAssertEqual(settings.configuration.transcriptionProvider, .assemblyAI)
        XCTAssertEqual(settings.configuration.transcriptionModel, expectedRuntimeConfiguration.transcriptionModel)
        XCTAssertEqual(settings.configuration.postProcessingProvider, .openAI)
        XCTAssertEqual(settings.configuration.postProcessingModel, expectedRuntimeConfiguration.postProcessingModel)
        XCTAssertEqual(settings.cleanupConfiguration.punctuationMode, .removeAll)
        XCTAssertEqual(settings.postProcessingSkipConfiguration, VoiceInkPostProcessingSkipConfiguration(
            isEnabled: false,
            wordThreshold: 8
        ))
        XCTAssertEqual(settings.transcriptionLanguage, "fr")
        XCTAssertEqual(settings.transcriptionPrompt, "French Roma style")
        XCTAssertEqual(settings.wordReplacementRules, [
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ])
        XCTAssertEqual(settings.customVocabulary, [" Roma ", "Felix", "roma", ""])
    }

    func testTranscribePassesSelectedLanguageToTranscriptionService() async throws {
        let service = CapturingTranscriptionService(text: "bonjour")
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        _ = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: false),
            transcriptionLanguage: "fr",
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in service }
        )

        XCTAssertEqual(service.capturedLanguage, "fr")
    }

    func testTranscribePassesTranscriptionPromptToTranscriptionService() async throws {
        let service = CapturingTranscriptionService(text: "roma")
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        _ = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: false),
            transcriptionPrompt: "spell Roma as Roma",
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in service }
        )

        XCTAssertEqual(service.capturedPrompt, "spell Roma as Roma")
    }

    func testTranscribeDropsTranscriptionPromptForUnsupportedProvider() async throws {
        let service = CapturingTranscriptionService(text: "roma")
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        _ = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(transcriptionProvider: .deepgram, isPostProcessingEnabled: false),
            transcriptionPrompt: "ignored",
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in service }
        )

        XCTAssertNil(service.capturedPrompt)
    }

    func testTranscribePassesNormalizedCustomVocabularyToTranscriptionService() async throws {
        let service = CapturingTranscriptionService(text: "roma")
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        _ = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(transcriptionProvider: .assemblyAI, isPostProcessingEnabled: false),
            customVocabulary: [" Roma ", "Felix", "roma", ""],
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in service }
        )

        XCTAssertEqual(service.capturedCustomVocabulary, ["Roma", "Felix"])
    }

    func testTranscribeDropsCustomVocabularyForUnsupportedProvider() async throws {
        let service = CapturingTranscriptionService(text: "roma")
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        _ = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(transcriptionProvider: .groq, isPostProcessingEnabled: false),
            customVocabulary: [" Roma ", "Felix"],
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in service }
        )

        XCTAssertEqual(service.capturedCustomVocabulary, [])
    }

    func testTranscribeTreatsAutoLanguageAsDetection() async throws {
        let service = CapturingTranscriptionService(text: "hello")
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        _ = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: false),
            transcriptionLanguage: "auto",
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in service }
        )

        XCTAssertNil(service.capturedLanguage)
    }

    func testTranscribeRunsPostProcessingWhenEnabledWithPromptAndKey() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(job.provider, .gemini)
            XCTAssertEqual(job.apiKey, "llm-key")
            XCTAssertEqual(job.model, "gemini-2.5-flash")
            XCTAssertEqual(job.prompt, "Clean this")
            XCTAssertEqual(job.transcript, "raw text")
            return "enhanced text"
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            apiKeyProvider: { provider in provider == .gemini ? "llm-key" : "stt-key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "raw text")
            }
        )

        XCTAssertEqual(result.cleanedText, "raw text")
        XCTAssertEqual(result.finalText, "enhanced text")
        XCTAssertEqual(result.enhancedText, "enhanced text")
        XCTAssertEqual(result.aiEnhancementModelName, "gemini-2.5-flash")
        XCTAssertEqual(result.postProcessingResult?.text, "enhanced text")
        XCTAssertEqual(result.postProcessingResult?.modelName, "gemini-2.5-flash")
        XCTAssertNil(result.postProcessingResult?.promptName)
        XCTAssertNil(result.postProcessingResult?.requestSystemMessage)
        XCTAssertNil(result.postProcessingResult?.requestUserMessage)
        XCTAssertNil(result.postProcessingError)
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testTranscribeRecordsTranscriptionAndEnhancementDurations() async throws {
        let dateSource = SteppingDateSource(offsets: [0, 2, 5, 8])
        let processor = VoiceInkTranscriptionRunProcessor(currentDate: dateSource.now) { _ in
            "enhanced text"
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            apiKeyProvider: { provider in provider == .gemini ? "llm-key" : "stt-key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "raw text")
            }
        )

        XCTAssertEqual(result.transcriptionDuration, 2)
        XCTAssertEqual(result.enhancementDuration, 3)
        XCTAssertEqual(result.postProcessingResult?.duration, 3)
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testTranscribeSkipsPostProcessingForShortTranscriptWhenPolicyEnabled() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration(
                isEnabled: true,
                wordThreshold: 3
            ),
            apiKeyProvider: { provider in provider == .gemini ? "llm-key" : "stt-key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "yes thank you")
            }
        )

        XCTAssertEqual(result.cleanedText, "yes thank you")
        XCTAssertEqual(result.finalText, "yes thank you")
        XCTAssertNil(result.enhancedText)
        XCTAssertNil(result.aiEnhancementModelName)
        XCTAssertNil(result.postProcessingError)
        XCTAssertFalse(result.postProcessingSucceeded)
    }

    func testTranscribeRunsPostProcessingForShortTranscriptWhenPromptTriggerForcesIt() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(job.transcript, "yes thank you")
            return "enhanced short text"
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration(
                isEnabled: true,
                wordThreshold: 3
            ),
            promptTriggerForcesPostProcessing: true,
            apiKeyProvider: { provider in provider == .gemini ? "llm-key" : "stt-key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "yes thank you")
            }
        )

        XCTAssertEqual(result.finalText, "enhanced short text")
        XCTAssertEqual(result.aiEnhancementModelName, "gemini-2.5-flash")
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testEnhancedTextIsNilWhenSuccessfulPostProcessingReturnsCleanedText() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { job in
            job.transcript
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "raw text")
            }
        )

        XCTAssertEqual(result.finalText, "raw text")
        XCTAssertNil(result.enhancedText)
        XCTAssertEqual(result.postProcessingResult?.text, "raw text")
        XCTAssertTrue(result.postProcessingSucceeded)
    }

    func testTranscribeKeepsCleanedTextWhenPostProcessingFails() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            throw StubLocalizedError(message: "provider down")
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "raw text")
            }
        )

        XCTAssertEqual(result.cleanedText, "raw text")
        XCTAssertEqual(result.finalText, "raw text")
        XCTAssertNil(result.enhancedText)
        XCTAssertEqual(result.aiEnhancementModelName, "gemini-2.5-flash")
        XCTAssertNil(result.postProcessingResult)
        XCTAssertEqual(result.postProcessingError, "Post-processing failed: provider down")
        XCTAssertFalse(result.postProcessingSucceeded)
    }

    func testTranscribeThrowsWhenTranscriptionAPIKeyIsMissing() async {
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            "unexpected"
        }

        do {
            _ = try await processor.transcribe(
                fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
                configuration: configuration(isPostProcessingEnabled: false),
                apiKeyProvider: { _ in "" },
                transcriptionServiceProvider: { _ in
                    StubTranscriptionService(text: "raw text")
                }
            )
            XCTFail("Expected missing API key error")
        } catch let error as VoiceInkTranscriptionRunError {
            XCTAssertEqual(error, .noAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeThrowsWhenTranscriptionAPIKeyIsWhitespace() async {
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            "unexpected"
        }

        do {
            _ = try await processor.transcribe(
                fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
                configuration: configuration(isPostProcessingEnabled: false),
                apiKeyProvider: { _ in " \n\t " },
                transcriptionServiceProvider: { _ in
                    StubTranscriptionService(text: "raw text")
                }
            )
            XCTFail("Expected missing API key error")
        } catch let error as VoiceInkTranscriptionRunError {
            XCTAssertEqual(error, .noAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPrefersLocalizedErrorDescription() {
        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: StubLocalizedError(message: "provider down")),
            "provider down"
        )
    }

    func testFallsBackToLocalizedDescription() {
        let error = StubUndescribedError()

        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: error),
            error.localizedDescription
        )
    }

    func testTranscribeRejectsEmptyRemoteTranscriptionUsingProviderPolicy() async {
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        do {
            _ = try await processor.transcribe(
                fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
                configuration: configuration(isPostProcessingEnabled: false),
                apiKeyProvider: { _ in "stt-key" },
                transcriptionServiceProvider: { _ in
                    StubTranscriptionService(text: "")
                }
            )
            XCTFail("Expected empty transcription error")
        } catch let error as VoiceInkTranscriptionRunError {
            XCTAssertEqual(error, .noTranscriptionReturned)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeAllowsEmptyLocalWhisperTranscriptionUsingProviderPolicy() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: VoiceInkModeRuntimeConfiguration(
                transcriptionProvider: .localWhisper,
                transcriptionModel: "ggml-base.en.bin",
                postProcessingProvider: .gemini,
                postProcessingModel: "gemini-2.5-flash",
                prompt: "Clean this",
                isPostProcessingEnabled: false
            ),
            apiKeyProvider: { provider in provider.runtimeAPIKey(userAPIKey: "") },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "")
            }
        )

        XCTAssertEqual(result.cleanedText, "")
        XCTAssertEqual(result.finalText, "")
        XCTAssertNil(result.enhancedText)
    }

    func testTranscribeSkipsPostProcessingWhenPostProcessingAPIKeyIsWhitespace() async throws {
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            XCTFail("Post-processing should not run")
            return "unexpected"
        }

        let result = try await processor.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            configuration: configuration(isPostProcessingEnabled: true),
            apiKeyProvider: { provider in provider == .gemini ? " \n\t " : "stt-key" },
            transcriptionServiceProvider: { _ in
                StubTranscriptionService(text: "raw text")
            }
        )

        XCTAssertEqual(result.cleanedText, "raw text")
        XCTAssertEqual(result.finalText, "raw text")
        XCTAssertFalse(result.postProcessingSucceeded)
    }

    private func configuration(
        transcriptionProvider: VoiceInkProviderKind = .groq,
        isPostProcessingEnabled: Bool
    ) -> VoiceInkModeRuntimeConfiguration {
        VoiceInkModeRuntimeConfiguration(
            transcriptionProvider: transcriptionProvider,
            transcriptionModel: "whisper-large-v3",
            postProcessingProvider: .gemini,
            postProcessingModel: "gemini-2.5-flash",
            prompt: "Clean this",
            isPostProcessingEnabled: isPostProcessingEnabled
        )
    }
}

extension TranscriptionRunProcessorTests {
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
        withIsolatedRunPreparationDefaults { defaults in
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
        withIsolatedRunPreparationDefaults { defaults in
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

    func testRunSettingsSelectPromptOverridesModePromptAndRecordsName() async throws {
        let prompt = VoiceInkCustomPrompt(
            title: "Email",
            promptText: "Write an email",
            useSystemInstructions: false
        )
        let baseSettings = VoiceInkTranscriptionRunSettings(
            configuration: configuration(isPostProcessingEnabled: true),
            enhancementContext: VoiceInkAIEnhancementPromptContext(
                surroundingTextBeforeCursor: "Previous sentence."
            )
        )
        let settings = baseSettings.selectingPrompt(prompt.id, from: [prompt])
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(
                job.prompt,
                "Write an email\n\n<SURROUNDING_TEXT_BEFORE_CURSOR>\nPrevious sentence.\n</SURROUNDING_TEXT_BEFORE_CURSOR>"
            )
            XCTAssertEqual(job.transcript, "raw text")
            return "email output"
        }

        let result = try await settings.processTranscribedText(
            "raw text",
            processor: processor,
            apiKeyProvider: { _ in "key" }
        )

        XCTAssertEqual(result.finalText, "email output")
        XCTAssertEqual(result.postProcessingResult?.promptName, "Email")
    }

    func testPromptTriggerSelectsPromptStripsTriggerAndForcesShortEnhancement() async throws {
        let prompt = VoiceInkCustomPrompt(
            title: "Summary",
            promptText: "Summarize",
            triggerWords: ["summary"],
            useSystemInstructions: false
        )
        let processor = VoiceInkTranscriptionRunProcessor { job in
            XCTAssertEqual(job.prompt, "Summarize")
            XCTAssertEqual(job.transcript, "Yes")
            return "Short summary"
        }

        let result = try await processor.processTranscribedText(
            "summary, yes",
            transcriptionModelName: "base",
            configuration: configuration(isPostProcessingEnabled: false),
            postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration(
                isEnabled: true,
                wordThreshold: 10
            ),
            promptLibrary: [prompt],
            apiKeyProvider: { _ in "key" }
        )

        XCTAssertEqual(result.cleanedText, "summary, yes")
        XCTAssertEqual(result.finalText, "Short summary")
        XCTAssertEqual(result.postProcessingResult?.promptName, "Summary")
    }

    private func withIsolatedRunPreparationDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.TranscriptionRunProcessorTests.RunPreparation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct StubTranscriptionService: VoiceInkAudioTranscriptionService {
    let text: String

    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        text
    }

}

private final class SteppingDateSource {
    private let baseDate = Date(timeIntervalSince1970: 1_000)
    private let offsets: [TimeInterval]
    private var index = 0

    init(offsets: [TimeInterval]) {
        self.offsets = offsets
    }

    func now() -> Date {
        defer { index += 1 }
        return baseDate.addingTimeInterval(offsets[min(index, offsets.count - 1)])
    }
}

private final class CapturingTranscriptionService: VoiceInkAudioTranscriptionService {
    let text: String
    private(set) var capturedLanguage: String?
    private(set) var capturedPrompt: String?
    private(set) var capturedCustomVocabulary: [String]?

    init(text: String) {
        self.text = text
    }

    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        capturedLanguage = language
        capturedPrompt = prompt
        capturedCustomVocabulary = customVocabulary
        return text
    }

}

private struct StubLocalizedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct StubUndescribedError: LocalizedError {
    var errorDescription: String? {
        nil
    }
}
