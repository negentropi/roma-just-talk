import Foundation
@testable import VoiceInkCore

final class LocalWhisperTranscriptionFlowTests: XCTestCase {
    func testRequestBuildersPreservePlatformDefaults() {
        let suiteName = "LocalWhisperTranscriptionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
        VoiceInkTranscriptionPromptPreference.savePrompt("custom local prompt", to: defaults)

        let audioURL = URL(fileURLWithPath: "/tmp/input.wav")
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionRequest.macOS(audioURL: audioURL, defaults: defaults),
            VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: audioURL,
                language: "fr",
                prompt: "custom local prompt",
                failurePlatform: .macOS,
                mapsThrownAudioSampleErrors: false
            )
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionRequest.iOS(audioURL: audioURL, language: "de", prompt: nil),
            VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: audioURL,
                language: "de",
                prompt: "",
                failurePlatform: .iOS
            )
        )
    }

    func testTranscriptionDiagnosticsPreservePlatformLogCopy() {
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.macOSInitiatingLocalTranscriptionMessage(
                modelDisplayName: "Base"
            ),
            "Initiating local transcription for model: Base"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.macOSUsingLoadedModelMessage(modelName: "tiny"),
            "Using already loaded model: tiny"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.macOSModelFileNotFoundMessage(modelName: "small"),
            "❌ Model file not found for: small"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.macOSLoadingModelMessage(modelName: "medium"),
            "Loading model: medium"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.macOSModelLoadFailedMessage(
                modelName: "large",
                localizedDescription: "bad file"
            ),
            "❌ Failed to load model: large - bad file"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.macOSAudioSamplesProcessingFailedMessage,
            "❌ Failed to process audio samples for local Whisper transcription."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.macOSCoreTranscriptionFailedMessage,
            "❌ Core transcription engine failed (whisper_full)."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.macOSTranscriptionCompletedMessage,
            "Whisper transcription completed successfully."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSStartingLocalTranscriptionMessage,
            "Starting local transcription."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSUsingModelMessage(modelPath: "/tmp/model.bin"),
            "Using model at /tmp/model.bin"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSModelLoadFailedMessage(localizedDescription: "missing"),
            "Failed to load model: missing"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSAudioProcessingFailedMessage,
            "Audio processing failed."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSProcessedAudioSamplesMessage(count: 42),
            "Processed 42 audio samples."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSAudioProcessingFailedMessage(
                localizedDescription: "decode"
            ),
            "Audio processing failed: decode"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSTranscriptionFailedMessage,
            "Transcription failed."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSContextResourcesReleasedMessage,
            "Whisper context resources released."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionDiagnostics.iOSTranscriptionCompletedMessage,
            "Transcription completed successfully."
        )
    }

    func testFlowRunsTranscriptionAndReleasesOwnedContext() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/input.wav")
        let context = StubLocalWhisperContext(text: "hello")

        let text = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
            request: VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: audioURL,
                language: "en",
                prompt: "names: Roma",
                failurePlatform: .iOS
            ),
            actions: actions(
                context: context,
                shouldReleaseContext: true,
                samples: [0.1, 0.2],
                expectedAudioURL: audioURL
            )
        )

        XCTAssertEqual(text, "hello")
        XCTAssertEqual(context.samples, [0.1, 0.2])
        XCTAssertEqual(context.language, "en")
        XCTAssertEqual(context.prompt, "names: Roma")
        XCTAssertEqual(context.releaseCount, 1)
    }

    func testFlowLeavesBorrowedContextLoaded() async throws {
        let context = StubLocalWhisperContext(text: "shared model")

        let text = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
            request: VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
                failurePlatform: .macOS
            ),
            actions: actions(context: context, shouldReleaseContext: false)
        )

        XCTAssertEqual(text, "shared model")
        XCTAssertEqual(context.releaseCount, 0)
    }

    func testFlowMapsMissingSamplesToPlatformAudioFailureAndReleasesContext() async throws {
        let context = StubLocalWhisperContext()

        do {
            _ = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
                request: VoiceInkLocalWhisperTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/bad.wav"),
                    failurePlatform: .iOS
                ),
                actions: actions(context: context, shouldReleaseContext: true, samples: nil)
            )
            XCTFail("Expected audio processing failure")
        } catch {
            XCTAssertEqual(errorName(error), "audioProcessingFailed")
            XCTAssertEqual(context.releaseCount, 1)
        }
    }

    func testFlowMapsFailedTranscriptionToPlatformFailureAndReleasesContext() async throws {
        let context = StubLocalWhisperContext(shouldSucceed: false)

        do {
            _ = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
                request: VoiceInkLocalWhisperTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
                    failurePlatform: .macOS
                ),
                actions: actions(context: context, shouldReleaseContext: true)
            )
            XCTFail("Expected transcription failure")
        } catch {
            XCTAssertEqual(errorName(error), "whisperCoreFailed")
            XCTAssertEqual(context.releaseCount, 1)
        }
    }

    func testFlowCanPreserveShellThrownSampleErrorsAndFailureLifetime() async throws {
        let context = StubLocalWhisperContext()

        do {
            _ = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
                request: VoiceInkLocalWhisperTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/missing.wav"),
                    failurePlatform: .macOS,
                    mapsThrownAudioSampleErrors: false
                ),
                actions: actions(
                    context: context,
                    shouldReleaseContext: true,
                    shouldReleaseContextOnFailure: false,
                    readError: StubAudioReadError.readFailed
                )
            )
            XCTFail("Expected shell audio read error")
        } catch StubAudioReadError.readFailed {
            XCTAssertEqual(context.releaseCount, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func actions(
        context: StubLocalWhisperContext,
        shouldReleaseContext: Bool,
        shouldReleaseContextOnFailure: Bool? = nil,
        samples: [Float]? = [0.3],
        expectedAudioURL: URL? = nil,
        readError: Error? = nil
    ) -> VoiceInkLocalWhisperTranscriptionActions<StubLocalWhisperContext> {
        VoiceInkLocalWhisperTranscriptionActions(
            resolveContext: {
                VoiceInkLocalWhisperContextPlan(
                    context: context,
                    shouldReleaseContext: shouldReleaseContext,
                    shouldReleaseContextOnFailure: shouldReleaseContextOnFailure
                )
            },
            readAudioSamples: { audioURL in
                if let expectedAudioURL {
                    XCTAssertEqual(audioURL, expectedAudioURL)
                }
                if let readError {
                    throw readError
                }
                return samples
            },
            runTranscription: { context, samples, language, prompt in
                context.samples = samples
                context.language = language
                context.prompt = prompt
                return context.shouldSucceed
            },
            transcriptionText: { context in
                context.text
            },
            releaseContext: { context in
                context.releaseCount += 1
            }
        )
    }

    private func errorName(_ error: Error) -> String {
        String(describing: error)
    }
}

private enum StubAudioReadError: Error {
    case readFailed
}

private final class StubLocalWhisperContext {
    var text: String
    var shouldSucceed: Bool
    var samples: [Float] = []
    var language: String?
    var prompt: String?
    var releaseCount = 0

    init(text: String = "", shouldSucceed: Bool = true) {
        self.text = text
        self.shouldSucceed = shouldSucceed
    }
}
