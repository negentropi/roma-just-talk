import Foundation
import VoiceInkCore

final class RemoteProviderPublicAPITests: XCTestCase {
    func testDeepgramRequestClientAndCodecExposePublicAPI() async throws {
        let request = try VoiceInkDeepgramRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.deepgram.apiBaseURL,
            apiKey: "deepgram-key",
            model: "nova-3",
            audioData: Data("WAVDATA".utf8),
            language: "en-US",
            smartFormat: true,
            punctuate: true,
            paragraphs: true,
            diarize: false,
            customVocabulary: ["Roma"],
            timeout: 30
        )

        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.deepgram.com")
        XCTAssertEqual(request.url?.path, "/v1/listen")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token deepgram-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
        XCTAssertEqual(request.httpBody, Data("WAVDATA".utf8))
        XCTAssertEqual(request.timeoutInterval, 30)

        let queryItems = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        )
        let query = Dictionary(uniqueKeysWithValues: queryItems.filter { $0.name != "keyterm" }.map { ($0.name, $0.value) })
        XCTAssertEqual(query["model"], "nova-3")
        XCTAssertEqual(query["smart_format"], "true")
        XCTAssertEqual(query["punctuate"], "true")
        XCTAssertEqual(query["paragraphs"], "true")
        XCTAssertEqual(query["diarize"], "false")
        XCTAssertEqual(query["language"], "en-US")
        XCTAssertEqual(queryItems.filter { $0.name == "keyterm" }.map(\.value), ["Roma"])

        let projectsRequest = VoiceInkDeepgramRequestBuilder.makeProjectsRequest(
            baseURL: VoiceInkProviderEndpoint.deepgram.apiBaseURL,
            apiKey: "deepgram-key",
            timeout: 10
        )
        XCTAssertEqual(projectsRequest.url?.absoluteString, "https://api.deepgram.com/v1/projects")
        XCTAssertEqual(projectsRequest.value(forHTTPHeaderField: "Authorization"), "Token deepgram-key")
        XCTAssertEqual(projectsRequest.timeoutInterval, 10)

        let client = VoiceInkDeepgramTranscriptionClient()
        let transcribeWithAllLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.deepgram.apiBaseURL,
                apiKey: "deepgram-key",
                model: "nova-3",
                audioData: Data("WAVDATA".utf8),
                language: "en-US",
                smartFormat: true,
                punctuate: true,
                paragraphs: true,
                diarize: false,
                customVocabulary: ["Roma"],
                errorDomain: "DeepgramPublicAPITests",
                timeout: 30
            )
        }
        let transcribeWithDefaultedLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.deepgram.apiBaseURL,
                apiKey: "deepgram-key",
                model: "nova-3",
                audioData: Data("WAVDATA".utf8)
            )
        }
        _ = transcribeWithAllLabels
        _ = transcribeWithDefaultedLabels

        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.deepgram.apiBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.deepgram.apiBaseURL,
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
            try VoiceInkDeepgramTranscriptionCodec.transcript(from: Data(#"{"results":{"channels":[{"alternatives":[{"transcript":"deepgram text"}]}]}}"#.utf8)),
            "deepgram text"
        )
    }

    func testGeminiRequestClientAndCodecExposePublicAPI() async throws {
        let request = try VoiceInkGeminiRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
            apiKey: "gemini-key",
            model: "gemini-2.5-flash",
            audioData: Data("WAVDATA".utf8),
            mimeType: "audio/wav",
            prompt: VoiceInkGeminiTranscriptionCodec.defaultPrompt,
            timeout: 60
        )

        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, VoiceInkGeminiTranscriptionCodec.defaultPrompt)

        let modelsRequest = VoiceInkGeminiRequestBuilder.makeModelsRequest(
            baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
            apiKey: "gemini-key",
            timeout: 10
        )
        XCTAssertEqual(modelsRequest.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models")

        let client = VoiceInkGeminiTranscriptionClient()
        let transcribeWithAllLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
                apiKey: "gemini-key",
                model: "gemini-2.5-flash",
                audioData: Data("WAVDATA".utf8),
                mimeType: "audio/wav",
                prompt: VoiceInkGeminiTranscriptionCodec.defaultPrompt,
                errorDomain: "GeminiPublicAPITests",
                timeout: 60
            )
        }
        let transcribeWithDefaultedLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
                apiKey: "gemini-key",
                model: "gemini-2.5-flash",
                audioData: Data("WAVDATA".utf8)
            )
        }
        _ = transcribeWithAllLabels
        _ = transcribeWithDefaultedLabels

        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
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
            try VoiceInkGeminiTranscriptionCodec.transcript(from: Data(#"{"candidates":[{"content":{"parts":[{"text":"  gemini text\n"}]}}]}"#.utf8)),
            "gemini text"
        )
    }

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
