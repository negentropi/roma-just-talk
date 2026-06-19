import Foundation
@testable import VoiceInkCore

final class AudioTranscriptionServiceFactoryTests: XCTestCase {
    func testRemoteProvidersUseRemoteFactory() async throws {
        var capturedProviders: [VoiceInkProviderKind] = []
        let factory = VoiceInkAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: { StubAudioTranscriptionService(text: "local") },
            remoteServiceFactory: { provider in
                capturedProviders.append(provider)
                return StubAudioTranscriptionService(text: "remote-\(provider.rawValue)")
            }
        )

        let service = factory.service(for: .groq)
        let transcript = try await service.transcribeAudioFile(
            apiKey: "key",
            model: "model",
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            language: nil,
            prompt: nil,
            customVocabulary: []
        )

        XCTAssertEqual(capturedProviders, [.groq])
        XCTAssertEqual(transcript, "remote-groq")
    }

    func testLocalWhisperProviderUsesLocalFactory() async throws {
        var localFactoryCallCount = 0
        var capturedRemoteProviders: [VoiceInkProviderKind] = []
        let factory = VoiceInkAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: {
                localFactoryCallCount += 1
                return StubAudioTranscriptionService(text: "local")
            },
            remoteServiceFactory: { provider in
                capturedRemoteProviders.append(provider)
                return StubAudioTranscriptionService(text: "remote")
            }
        )

        let service = factory.service(for: .localWhisper)
        let transcript = try await service.transcribeAudioFile(
            apiKey: "key",
            model: "model",
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            language: nil,
            prompt: nil,
            customVocabulary: []
        )

        XCTAssertEqual(localFactoryCallCount, 1)
        XCTAssertEqual(capturedRemoteProviders, [])
        XCTAssertEqual(transcript, "local")
    }
}

private struct StubAudioTranscriptionService: VoiceInkAudioTranscriptionService {
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
