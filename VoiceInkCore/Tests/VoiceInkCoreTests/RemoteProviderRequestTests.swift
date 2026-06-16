#if canImport(XCTest)
import Foundation
import XCTest
@testable import VoiceInkCore

final class RemoteProviderRequestTests: XCTestCase {
    func testChatRequestBuilderUsesOpenAICompatibleEndpointAndBody() throws {
        let request = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
            baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
            apiKey: "llm-key",
            model: "llama-3.3-70b-versatile",
            messages: [
                VoiceInkOpenAICompatibleChatMessage(role: "system", content: "System"),
                VoiceInkOpenAICompatibleChatMessage(role: "user", content: "User")
            ],
            temperature: 0.2
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer llm-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try JSONDecoder().decode(
            VoiceInkOpenAICompatibleChatRequest.self,
            from: try XCTUnwrap(request.httpBody)
        )
        XCTAssertEqual(body.model, "llama-3.3-70b-versatile")
        XCTAssertEqual(body.messages.map(\.role), ["system", "user"])
        XCTAssertEqual(body.messages.map(\.content), ["System", "User"])
        XCTAssertEqual(body.temperature, 0.2)
    }

    func testChatCodecReturnsFirstMessageContentOrEmptyString() throws {
        let response = VoiceInkOpenAICompatibleChatResponse(
            choices: [
                VoiceInkOpenAICompatibleChatChoice(
                    message: VoiceInkOpenAICompatibleChatMessage(role: "assistant", content: "Clean text")
                )
            ]
        )

        XCTAssertEqual(
            try VoiceInkOpenAICompatibleChatCodec.firstMessageContent(from: JSONEncoder().encode(response)),
            "Clean text"
        )
        XCTAssertEqual(
            try VoiceInkOpenAICompatibleChatCodec.firstMessageContent(
                from: JSONEncoder().encode(VoiceInkOpenAICompatibleChatResponse(choices: []))
            ),
            ""
        )
    }

    func testOpenAICompatibleTranscriptionRequestBuilderUsesMultipartAudioRequest() throws {
        let preparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
            apiKey: "stt-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            model: "whisper-large-v3",
            boundary: "Boundary-test",
            language: "en"
        )

        XCTAssertEqual(
            preparedRequest.request.url?.absoluteString,
            "https://api.groq.com/openai/v1/audio/transcriptions"
        )
        XCTAssertEqual(preparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer stt-key")
        XCTAssertEqual(
            preparedRequest.request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-test"
        )

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"sample.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.contains("WAVDATA"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model\""))
        XCTAssertTrue(body.contains("whisper-large-v3"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"language\""))
        XCTAssertTrue(body.contains("en"))
        XCTAssertTrue(body.contains("--Boundary-test--"))
    }

    func testOpenAICompatibleTranscriptionRequestBuilderIncludesOptionalFields() throws {
        let preparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
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

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"prompt\""))
        XCTAssertTrue(body.contains("spell project names correctly"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"response_format\""))
        XCTAssertTrue(body.contains("json"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"temperature\""))
        XCTAssertTrue(body.contains("0"))
    }

    func testOpenAICompatibleTranscriptionRequestBuilderUsesDirectURLForCustomEndpoints() throws {
        let preparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
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
            preparedRequest.request.url?.absoluteString,
            "https://custom.example.test/v1/audio/transcriptions"
        )
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-key")

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("custom-whisper"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"prompt\""))
    }

    func testOpenAICompatibleTranscriptionCodecReturnsTextWhenPresent() throws {
        let response = VoiceInkOpenAICompatibleTranscriptionResponse(
            text: "transcribed text",
            language: "en",
            duration: 1.2
        )

        XCTAssertEqual(
            try VoiceInkOpenAICompatibleTranscriptionCodec.textIfPresent(from: JSONEncoder().encode(response)),
            "transcribed text"
        )
        XCTAssertNil(
            try VoiceInkOpenAICompatibleTranscriptionCodec.textIfPresent(
                from: JSONEncoder().encode(VoiceInkOpenAICompatibleTranscriptionResponse(text: nil))
            )
        )
    }

    func testOpenAICompatibleTranscriptionCodecCanDisablePlainTextFallback() throws {
        let plainTextData = Data("plain transcription".utf8)

        XCTAssertEqual(
            VoiceInkOpenAICompatibleTranscriptionCodec.transcriptionText(
                from: plainTextData,
                allowPlainTextFallback: true
            ),
            "plain transcription"
        )
        XCTAssertEqual(
            VoiceInkOpenAICompatibleTranscriptionCodec.transcriptionText(
                from: plainTextData,
                allowPlainTextFallback: false
            ),
            ""
        )
    }

    func testOpenAICompatibleModelsRequestBuilderCanSetTimeout() throws {
        let request = VoiceInkOpenAICompatibleModelsRequestBuilder.make(
            baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
            apiKey: "stt-key",
            timeout: 10
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer stt-key")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testOpenAICompatibleClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkOpenAICompatibleClient().verifyAPIKeyDetailed(
            baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
            apiKey: " \n\t "
        )

        XCTAssertEqual(
            result,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
    }

    func testDeepgramTranscriptionRequestBuilderUsesListenEndpointAndBody() throws {
        let audioData = Data("WAVDATA".utf8)
        let request = try VoiceInkDeepgramRequestBuilder.makeTranscriptionRequest(
            baseURL: try XCTUnwrap(URL(string: "https://api.deepgram.com")),
            apiKey: "deepgram-key",
            model: "nova-3",
            audioData: audioData,
            language: "en-US"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token deepgram-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
        XCTAssertEqual(request.httpBody, audioData)
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.deepgram.com")
        XCTAssertEqual(request.url?.path, "/v1/listen")

        let queryItems = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        )
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })
        XCTAssertEqual(query["model"], "nova-3")
        XCTAssertEqual(query["smart_format"], "true")
        XCTAssertEqual(query["punctuate"], "true")
        XCTAssertEqual(query["diarize"], "false")
        XCTAssertEqual(query["language"], "en-US")
    }

    func testDeepgramTranscriptionRequestBuilderCanMatchMacOSLLMkitOptions() throws {
        let request = try VoiceInkDeepgramRequestBuilder.makeTranscriptionRequest(
            baseURL: try XCTUnwrap(URL(string: "https://api.deepgram.com")),
            apiKey: "deepgram-key",
            model: "nova-3",
            audioData: Data("WAVDATA".utf8),
            language: "en-US",
            paragraphs: true,
            diarize: nil,
            customVocabulary: ["Roma", "", "Felix"],
            timeout: 30
        )

        let queryItems = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        )
        let query = Dictionary(uniqueKeysWithValues: queryItems.filter { $0.name != "keyterm" }.map { ($0.name, $0.value) })
        XCTAssertEqual(query["model"], "nova-3")
        XCTAssertEqual(query["smart_format"], "true")
        XCTAssertEqual(query["punctuate"], "true")
        XCTAssertEqual(query["paragraphs"], "true")
        XCTAssertNil(query["diarize"])
        XCTAssertEqual(query["language"], "en-US")
        XCTAssertEqual(queryItems.filter { $0.name == "keyterm" }.map(\.value), ["Roma", "Felix"])
        XCTAssertEqual(request.timeoutInterval, 30)
    }

    func testDeepgramProjectsRequestBuilderUsesProjectsEndpoint() throws {
        let request = VoiceInkDeepgramRequestBuilder.makeProjectsRequest(
            baseURL: try XCTUnwrap(URL(string: "https://api.deepgram.com")),
            apiKey: "deepgram-key",
            timeout: 10
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.deepgram.com/v1/projects")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token deepgram-key")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testDeepgramClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkDeepgramTranscriptionClient().verifyAPIKeyDetailed(
            baseURL: try XCTUnwrap(URL(string: "https://api.deepgram.com")),
            apiKey: " \n\t "
        )

        XCTAssertEqual(
            result,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
    }

    func testDeepgramTranscriptionCodecReturnsFirstTranscriptOrEmptyString() throws {
        let response = """
        {
          "results": {
            "channels": [
              {
                "alternatives": [
                  {
                    "transcript": "deepgram text"
                  }
                ]
              }
            ]
          }
        }
        """

        XCTAssertEqual(
            try VoiceInkDeepgramTranscriptionCodec.transcript(from: Data(response.utf8)),
            "deepgram text"
        )

        let emptyResponse = #"{"results":{"channels":[]}}"#
        XCTAssertEqual(
            try VoiceInkDeepgramTranscriptionCodec.transcript(from: Data(emptyResponse.utf8)),
            ""
        )
    }

    func testGeminiTranscriptionRequestBuilderUsesGenerateContentEndpointAndBody() throws {
        let audioData = Data("WAVDATA".utf8)
        let request = try VoiceInkGeminiRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
            apiKey: "gemini-key",
            model: "gemini-2.5-flash",
            audioData: audioData,
            timeout: 60
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-key")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )
        XCTAssertEqual(request.timeoutInterval, 60)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, VoiceInkGeminiTranscriptionCodec.defaultPrompt)

        let inlineData = try XCTUnwrap(parts.dropFirst().first?["inlineData"] as? [String: Any])
        XCTAssertEqual(inlineData["mimeType"] as? String, "audio/wav")
        XCTAssertEqual(inlineData["data"] as? String, audioData.base64EncodedString())
    }

    func testGeminiModelsRequestBuilderUsesNativeModelsEndpoint() throws {
        let request = VoiceInkGeminiRequestBuilder.makeModelsRequest(
            baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
            apiKey: "gemini-key",
            timeout: 10
        )

        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-key")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testGeminiClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkGeminiTranscriptionClient().verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
            apiKey: " \n\t "
        )

        XCTAssertEqual(
            result,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
    }

    func testGeminiTranscriptionCodecReturnsTrimmedFirstPartOrEmptyString() throws {
        let response = """
        {
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": "  gemini text\\n"
                  }
                ]
              }
            }
          ]
        }
        """

        XCTAssertEqual(
            try VoiceInkGeminiTranscriptionCodec.transcript(from: Data(response.utf8)),
            "gemini text"
        )

        let emptyResponse = #"{"candidates":[]}"#
        XCTAssertEqual(
            try VoiceInkGeminiTranscriptionCodec.transcript(from: Data(emptyResponse.utf8)),
            ""
        )
    }

    func testMistralTranscriptionRequestBuilderUsesMultipartAudioRequest() throws {
        let audioData = Data("WAVDATA".utf8)
        let preparedRequest = VoiceInkMistralRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
            apiKey: "mistral-key",
            model: "voxtral-mini-latest",
            audioData: audioData,
            fileName: "sample.wav",
            boundary: "Boundary-test",
            timeout: 30
        )

        XCTAssertEqual(
            preparedRequest.request.url?.absoluteString,
            "https://api.mistral.ai/v1/audio/transcriptions"
        )
        XCTAssertEqual(preparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "x-api-key"), "mistral-key")
        XCTAssertEqual(
            preparedRequest.request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-test"
        )
        XCTAssertEqual(preparedRequest.request.timeoutInterval, 30)

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model\""))
        XCTAssertTrue(body.contains("voxtral-mini-latest"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"sample.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.contains("WAVDATA"))
        XCTAssertTrue(body.contains("--Boundary-test--"))
    }

    func testMistralModelsRequestBuilderUsesModelsEndpoint() throws {
        let request = VoiceInkMistralRequestBuilder.makeModelsRequest(
            baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
            apiKey: "mistral-key",
            timeout: 10
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mistral-key")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testMistralClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkMistralTranscriptionClient().verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
            apiKey: " \n\t "
        )

        XCTAssertEqual(
            result,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        )
    }

    func testMistralTranscriptionCodecReturnsTextIncludingEmptyString() throws {
        XCTAssertEqual(
            try VoiceInkMistralTranscriptionCodec.transcript(from: Data(#"{"text":"mistral text"}"#.utf8)),
            "mistral text"
        )
        XCTAssertEqual(
            try VoiceInkMistralTranscriptionCodec.transcript(from: Data(#"{"text":""}"#.utf8)),
            ""
        )
    }
}
#endif
