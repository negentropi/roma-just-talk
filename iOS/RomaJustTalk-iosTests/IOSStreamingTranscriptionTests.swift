import Foundation
import LLMkit
import XCTest
import RomaCore
@testable import roma_just_talk

@MainActor
final class IOSStreamingTranscriptionTests: XCTestCase {
    func testLivePolicySelectsRealtimeModelAndHonorsPreference() throws {
        let suiteName = "IOSStreamingTranscriptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configuration = Mode(
            name: "Deepgram live",
            transcriptionProvider: .deepgram,
            transcriptionModel: "nova-3"
        ).runtimeConfiguration

        XCTAssertEqual(
            RomaLiveTranscriptionPolicy.request(
                for: configuration,
                defaults: defaults
            ),
            RomaLiveTranscriptionRequest(
                provider: .deepgram,
                selectedModel: "nova-3",
                connectionModel: "nova-3"
            )
        )

        RomaTranscriptionStreamingPreference.saveIsEnabled(
            false,
            forModelName: "nova-3",
            to: defaults
        )
        XCTAssertNil(RomaLiveTranscriptionPolicy.request(
            for: configuration,
            defaults: defaults
        ))
        XCTAssertNil(RomaLiveTranscriptionPolicy.capability(
            for: Mode.defaultLocalWhisper().runtimeConfiguration
        ))
    }

    func testCartesiaIsSelectableVerifiedAndForcedToStreaming() throws {
        let suiteName = "IOSStreamingTranscriptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configuration = Mode(
            name: "Cartesia live",
            transcriptionProvider: .cartesia,
            transcriptionModel: "ink-whisper"
        ).runtimeConfiguration

        RomaTranscriptionStreamingPreference.saveIsEnabled(
            false,
            forModelName: "ink-whisper",
            to: defaults
        )

        XCTAssertEqual(
            RomaLiveTranscriptionPolicy.request(for: configuration, defaults: defaults),
            RomaLiveTranscriptionRequest(
                provider: .cartesia,
                selectedModel: "ink-whisper",
                connectionModel: "ink-whisper",
                isStreamingOnly: true
            )
        )
        XCTAssertNoThrow(try IOSStreamingTranscriptionService.makeClient(provider: .cartesia))
        XCTAssertEqual(
            RomaProviderKind.cartesia.transcriptionServiceKind,
            RomaTranscriptionServiceKind.streamingOnly
        )
        XCTAssertEqual(
            RomaProviderKind.cartesia.models(for: RomaProviderModelUse.transcription),
            ["ink-whisper"]
        )
    }

    func testStreamingServicePublishesPartialAndReturnsCommittedText() async throws {
        let client = StreamingClientHarness()
        let service = IOSStreamingTranscriptionService { _ in client }
        try await service.start(
            request: RomaLiveTranscriptionRequest(
                provider: .deepgram,
                selectedModel: "nova-3",
                connectionModel: "nova-3"
            ),
            apiKey: "key",
            language: "en",
            customVocabulary: ["RomaJustTalk"]
        )

        client.emit(.partial(text: "hello wor"))
        let didPublishPartial = await waitUntil {
            service.partialTranscript == "hello wor"
        }
        XCTAssertTrue(didPublishPartial)
        service.sendAudioChunk(Data([1, 2]))
        service.sendAudioChunk(Data([3, 4]))

        let finalText = try await service.stopAndGetFinalText()

        XCTAssertEqual(finalText, "hello world")
        XCTAssertEqual(client.receivedChunks, [Data([1, 2]), Data([3, 4])])
        XCTAssertEqual(client.connectedModel, "nova-3")
        XCTAssertEqual(client.connectedVocabulary, ["RomaJustTalk"])
        XCTAssertTrue(client.didDisconnect)
    }

    func testStreamingServiceSurfacesProviderFailure() async throws {
        let client = StreamingClientHarness(commitEvent: .error("socket closed"))
        let service = IOSStreamingTranscriptionService { _ in client }
        try await service.start(
            request: RomaLiveTranscriptionRequest(
                provider: .deepgram,
                selectedModel: "nova-3",
                connectionModel: "nova-3"
            ),
            apiKey: "key",
            language: nil,
            customVocabulary: []
        )

        do {
            _ = try await service.stopAndGetFinalText()
            XCTFail("Provider failure must escape so recording can use batch fallback")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("socket closed"))
        }
        XCTAssertTrue(client.didDisconnect)
    }

    func testCommittedTextUsesSharedCleanupAndEnhancementPipeline() async throws {
        let settings = RomaTranscriptionRunSettings(
            configuration: Mode(
                name: "Streaming cleanup",
                transcriptionProvider: .deepgram,
                transcriptionModel: "nova-3",
                isPostProcessingEnabled: true,
                postProcessingProvider: .gemini,
                postProcessingModel: "gemini-2.5-flash",
                promptTemplate: RomaPostProcessingPromptTemplate(
                    type: .custom,
                    customPrompt: "Clean"
                )
            ).runtimeConfiguration,
            cleanupConfiguration: .disabled,
            wordReplacementRules: [
                RomaWordReplacementRule(
                    originalText: "Voice Ink",
                    replacementText: "RomaJustTalk"
                )
            ]
        )
        let processor = RomaTranscriptionRunProcessor { job in
            "Enhanced: \(job.transcript)"
        }

        let result = try await settings.processTranscribedText(
            "Voice Ink works",
            processor: processor,
            apiKeyProvider: { _ in "key" }
        )

        XCTAssertEqual(result.cleanedText, "RomaJustTalk works")
        XCTAssertEqual(result.finalText, "Enhanced: RomaJustTalk works")
        XCTAssertEqual(result.transcriptionModelName, "nova-3")
    }

    func testStreamingFailureRunsSavedFileFallback() async throws {
        var didCancelStreaming = false
        var didPrepareFallback = false
        var didRunFallback = false

        let result: String = try await RomaStreamingFallbackPolicy.run(
            streamingFailed: false,
            streaming: {
                throw RomaStreamingTranscriptionError.connectionFailed("offline")
            },
            cancelStreaming: {
                didCancelStreaming = true
            },
            prepareFallback: {
                didPrepareFallback = true
            },
            fallback: {
                didRunFallback = true
                return "batch result"
            }
        )

        XCTAssertEqual(result, "batch result")
        XCTAssertTrue(didCancelStreaming)
        XCTAssertTrue(didPrepareFallback)
        XCTAssertTrue(didRunFallback)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(
            Double(timeoutNanoseconds) / 1_000_000_000
        )
        while Date() < deadline {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}

private final class StreamingClientHarness: LLMkit.StreamingTranscriptionProvider, @unchecked Sendable {
    private let commitEvent: LLMkit.StreamingTranscriptionEvent
    private let continuation: AsyncStream<LLMkit.StreamingTranscriptionEvent>.Continuation
    let transcriptionEvents: AsyncStream<LLMkit.StreamingTranscriptionEvent>

    private(set) var receivedChunks: [Data] = []
    private(set) var connectedModel: String?
    private(set) var connectedVocabulary: [String] = []
    private(set) var didDisconnect = false

    init(commitEvent: LLMkit.StreamingTranscriptionEvent = .committed(text: "hello world")) {
        self.commitEvent = commitEvent
        (transcriptionEvents, continuation) = AsyncStream.makeStream(
            of: LLMkit.StreamingTranscriptionEvent.self
        )
    }

    func connect(
        apiKey: String,
        model: String,
        language: String?,
        customVocabulary: [String]
    ) async throws {
        connectedModel = model
        connectedVocabulary = customVocabulary
        continuation.yield(.sessionStarted)
    }

    func sendAudioChunk(_ data: Data) async throws {
        receivedChunks.append(data)
    }

    func commit() async throws {
        continuation.yield(commitEvent)
    }

    func disconnect() async {
        didDisconnect = true
        continuation.finish()
    }

    func emit(_ event: LLMkit.StreamingTranscriptionEvent) {
        continuation.yield(event)
    }
}
