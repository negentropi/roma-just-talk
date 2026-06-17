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
        XCTAssertNil(result.postProcessingError)
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

    private func configuration(isPostProcessingEnabled: Bool) -> VoiceInkModeRuntimeConfiguration {
        VoiceInkModeRuntimeConfiguration(
            transcriptionProvider: .groq,
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
        language: String?
    ) async throws -> String {
        text
    }

}

private final class CapturingTranscriptionService: VoiceInkAudioTranscriptionService {
    let text: String
    private(set) var capturedLanguage: String?

    init(text: String) {
        self.text = text
    }

    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?
    ) async throws -> String {
        capturedLanguage = language
        return text
    }

}

private struct StubLocalizedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
