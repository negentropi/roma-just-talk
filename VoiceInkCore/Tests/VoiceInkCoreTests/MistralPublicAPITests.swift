import Foundation
import VoiceInkCore

final class MistralPublicAPITests: XCTestCase {
    func testMistralRequestClientAndCodecExposePublicAPI() async throws {
        let preparedRequest = VoiceInkMistralRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
            apiKey: "mistral-key",
            model: "voxtral-mini-latest",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            boundary: "Boundary-test",
            timeout: 30
        )
        let publicPreparedRequest = VoiceInkPreparedMistralTranscriptionRequest(
            request: preparedRequest.request,
            body: preparedRequest.body
        )

        XCTAssertEqual(publicPreparedRequest.request.url?.absoluteString, "https://api.mistral.ai/v1/audio/transcriptions")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "x-api-key"), "mistral-key")
        XCTAssertEqual(publicPreparedRequest.body, preparedRequest.body)

        let modelsRequest = VoiceInkMistralRequestBuilder.makeModelsRequest(
            baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
            apiKey: "mistral-key",
            timeout: 10
        )
        XCTAssertEqual(modelsRequest.url?.absoluteString, "https://api.mistral.ai/v1/models")

        let client = VoiceInkMistralTranscriptionClient()
        let transcribeWithAllLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
                apiKey: "mistral-key",
                model: "voxtral-mini-latest",
                audioData: Data("WAVDATA".utf8),
                fileName: "sample.wav",
                errorDomain: "MistralPublicAPITests",
                timeout: 30,
                maxRetries: 2
            )
        }
        let transcribeWithDefaultedLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
                apiKey: "mistral-key",
                model: "voxtral-mini-latest",
                audioData: Data("WAVDATA".utf8)
            )
        }
        _ = transcribeWithAllLabels
        _ = transcribeWithDefaultedLabels

        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertEqual(
            blankAPIKeyResult,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
        XCTAssertEqual(
            try VoiceInkMistralTranscriptionCodec.transcript(from: Data(#"{"text":"mistral text"}"#.utf8)),
            "mistral text"
        )
    }
}
