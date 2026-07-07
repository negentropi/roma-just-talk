import Foundation
import VoiceInkCore

final class OpenAICompatiblePublicAPITests: XCTestCase {
    func testOpenAICompatibleTranscriptionRequestClientAndCodecExposePublicAPI() async throws {
        let response = VoiceInkOpenAICompatibleTranscriptionResponse(
            text: "transcribed text",
            language: "en",
            duration: 1.2
        )
        XCTAssertEqual(response.text, "transcribed text")
        XCTAssertEqual(response.language, "en")
        XCTAssertEqual(response.duration, 1.2)

        XCTAssertEqual(
            VoiceInkOpenAICompatibleTranscriptionCodec.multipartContentType(boundary: "Boundary-test"),
            "multipart/form-data; boundary=Boundary-test"
        )
        let bodyData = VoiceInkOpenAICompatibleTranscriptionCodec.requestBody(
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            model: "whisper-large-v3",
            boundary: "Boundary-test",
            language: "en",
            prompt: "spell project names correctly",
            responseFormat: "json",
            temperature: "0"
        )
        let body = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="file"; filename="sample.wav""#))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="model""#))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="response_format""#))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="temperature""#))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="language""#))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="prompt""#))
        XCTAssertEqual(
            try VoiceInkOpenAICompatibleTranscriptionCodec.textIfPresent(
                from: Data(#"{"text":"transcribed text","language":"en","duration":1.2}"#.utf8)
            ),
            "transcribed text"
        )
        XCTAssertNil(
            try VoiceInkOpenAICompatibleTranscriptionCodec.textIfPresent(
                from: Data(#"{"text":null}"#.utf8)
            )
        )

        let baseURLPreparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            baseURL: VoiceInkProviderEndpoint.groq.apiBaseURL,
            apiKey: "stt-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            model: "whisper-large-v3",
            boundary: "Boundary-test",
            language: "en",
            prompt: "spell project names correctly",
            responseFormat: "json",
            temperature: "0"
        )
        let publicPreparedRequest = VoiceInkPreparedOpenAICompatibleTranscriptionRequest(
            request: baseURLPreparedRequest.request,
            body: baseURLPreparedRequest.body
        )
        XCTAssertEqual(
            publicPreparedRequest.request.url?.absoluteString,
            "https://api.groq.com/openai/v1/audio/transcriptions"
        )
        XCTAssertEqual(publicPreparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer stt-key")
        XCTAssertEqual(
            publicPreparedRequest.request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-test"
        )
        XCTAssertNil(publicPreparedRequest.request.httpBody)
        XCTAssertEqual(publicPreparedRequest.requestWithHTTPBody().httpBody, publicPreparedRequest.body)

        let directURLPreparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            url: try XCTUnwrap(URL(string: "https://custom.example.test/v1/audio/transcriptions")),
            apiKey: "custom-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            model: "custom-whisper",
            boundary: "Boundary-test",
            language: "en",
            prompt: "spell project names correctly",
            responseFormat: "json",
            temperature: "0"
        )
        XCTAssertEqual(
            directURLPreparedRequest.request.url?.absoluteString,
            "https://custom.example.test/v1/audio/transcriptions"
        )
        XCTAssertEqual(directURLPreparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-key")

        let client = VoiceInkOpenAICompatibleTranscriptionClient()
        let transcribeWithAllLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.groq.apiBaseURL,
                apiKey: "stt-key",
                model: "whisper-large-v3",
                audioData: Data("WAVDATA".utf8),
                fileName: "sample.wav",
                language: "en",
                prompt: "spell project names correctly",
                responseFormat: "json",
                temperature: "0",
                errorDomain: "OpenAICompatiblePublicAPITests",
                timeout: 30,
                maxRetries: 1,
                allowPlainTextFallback: false
            )
        }
        let transcribeWithDirectURL: () async throws -> String = {
            try await client.transcribeAudioData(
                url: try XCTUnwrap(URL(string: "https://custom.example.test/v1/audio/transcriptions")),
                apiKey: "custom-key",
                model: "custom-whisper",
                audioData: Data("WAVDATA".utf8),
                fileName: "sample.wav",
                language: "en",
                prompt: "spell project names correctly",
                responseFormat: "json",
                temperature: "0",
                errorDomain: "OpenAICompatiblePublicAPITests",
                timeout: 30,
                maxRetries: 1,
                allowPlainTextFallback: false
            )
        }
        let transcribeWithDefaultedLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.groq.apiBaseURL,
                apiKey: "stt-key",
                model: "whisper-large-v3",
                audioData: Data("WAVDATA".utf8),
                fileName: "sample.wav"
            )
        }
        _ = transcribeWithAllLabels
        _ = transcribeWithDirectURL
        _ = transcribeWithDefaultedLabels

        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.groq.apiBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.groq.apiBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertEqual(
            blankAPIKeyResult,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
    }
}
