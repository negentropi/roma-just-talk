#if canImport(XCTest)
import Foundation
import XCTest
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

    func verifyAPIKey(_ apiKey: String) async -> Bool {
        true
    }
}

private struct StubLocalizedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
#endif
