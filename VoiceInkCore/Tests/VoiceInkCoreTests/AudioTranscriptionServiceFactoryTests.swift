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

    func testErrorDescriptionsPreserveMacOSCloudTranscriptionCopy() {
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.unsupportedProvider.errorDescription,
            "The model provider is not supported by this service."
        )
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.missingAPIKey.errorDescription,
            "API key for this service is missing. Please configure it in the settings."
        )
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.audioFileNotFound.errorDescription,
            "The audio file to transcribe could not be found."
        )
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.apiRequestFailed(statusCode: 429, message: "rate limited").errorDescription,
            "The API request failed with status code 429: rate limited"
        )
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.networkError(StubNetworkError()).errorDescription,
            "A network error occurred: network offline"
        )
    }

    func testNoTranscriptionReturnedUsesSharedRunErrorDescription() {
        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.noTranscriptionReturned.errorDescription,
            VoiceInkTranscriptionRunError.noTranscriptionReturned.errorDescription
        )
    }

    func testCloudTranscriptionAudioFileLoadsBytesAndFileName() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.AudioTranscriptionServiceFactoryTests.\(UUID().uuidString).wav")
        try Data("WAVDATA".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let audioFile = try VoiceInkCloudTranscriptionAudioFile.load(from: audioURL)

        XCTAssertEqual(audioFile.data, Data("WAVDATA".utf8))
        XCTAssertEqual(audioFile.fileName, audioURL.lastPathComponent)
    }

    func testCloudTranscriptionAudioFileMapsMissingFile() {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.AudioTranscriptionServiceFactoryTests.missing.\(UUID().uuidString).wav")

        do {
            _ = try VoiceInkCloudTranscriptionAudioFile.load(from: audioURL)
            XCTFail("Expected audio file not found")
        } catch VoiceInkCloudTranscriptionError.audioFileNotFound {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIRequestFailureMapsMatchingHTTPNSError() {
        let error = NSError(
            domain: "GroqAPI",
            code: 429,
            userInfo: [NSLocalizedDescriptionKey: "rate limited"]
        )

        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: error,
                matchingErrorDomain: "GroqAPI"
            )?.errorDescription,
            "The API request failed with status code 429: rate limited"
        )
    }

    func testAPIRequestFailureFallsBackToLocalizedDescription() {
        let error = NSError(domain: "GroqAPI", code: 500)

        XCTAssertEqual(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: error,
                matchingErrorDomain: "GroqAPI"
            )?.errorDescription,
            "The API request failed with status code 500: \(error.localizedDescription)"
        )
    }

    func testAPIRequestFailureRejectsWrongDomainMissingDomainAndNonHTTPStatus() {
        XCTAssertNil(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: NSError(domain: "Other", code: 429),
                matchingErrorDomain: "GroqAPI"
            )
        )
        XCTAssertNil(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: NSError(domain: "GroqAPI", code: 429),
                matchingErrorDomain: nil
            )
        )
        XCTAssertNil(
            VoiceInkCloudTranscriptionError.apiRequestFailure(
                from: NSError(domain: "GroqAPI", code: 99),
                matchingErrorDomain: "GroqAPI"
            )
        )
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

private struct StubNetworkError: LocalizedError {
    var errorDescription: String? {
        "network offline"
    }
}
