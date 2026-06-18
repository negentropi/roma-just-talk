import Foundation
@testable import VoiceInkCore

final class TranscriptionRunProcessorTests: XCTestCase {
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
