import Foundation
import VoiceInkCore

final class ElevenLabsPublicAPITests: XCTestCase {
    func testElevenLabsRequestClientAndCodecExposePublicAPI() async throws {
        let preparedRequest = VoiceInkElevenLabsRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
            apiKey: "eleven-key",
            model: "scribe_v2",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            language: "en",
            boundary: "Boundary-test",
            timeout: 30
        )
        let publicPreparedRequest = VoiceInkPreparedElevenLabsTranscriptionRequest(
            request: preparedRequest.request,
            body: preparedRequest.body
        )

        XCTAssertEqual(publicPreparedRequest.request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "xi-api-key"), "eleven-key")
        XCTAssertEqual(publicPreparedRequest.body, preparedRequest.body)

        let userRequest = VoiceInkElevenLabsRequestBuilder.makeUserRequest(
            baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
            apiKey: "eleven-key",
            timeout: 10
        )
        XCTAssertEqual(userRequest.url?.absoluteString, "https://api.elevenlabs.io/v1/user")

        let client = VoiceInkElevenLabsTranscriptionClient()
        let transcribeWithAllLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
                apiKey: "eleven-key",
                model: "scribe_v2",
                audioData: Data("WAVDATA".utf8),
                fileName: "sample.wav",
                language: "en",
                errorDomain: "ElevenLabsPublicAPITests",
                timeout: 30,
                maxRetries: 2
            )
        }
        let transcribeWithDefaultedLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
                apiKey: "eleven-key",
                model: "scribe_v2",
                audioData: Data("WAVDATA".utf8)
            )
        }
        _ = transcribeWithAllLabels
        _ = transcribeWithDefaultedLabels

        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
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
            try VoiceInkElevenLabsTranscriptionCodec.transcript(from: Data(#"{"text":"eleven text"}"#.utf8)),
            "eleven text"
        )
    }
}
