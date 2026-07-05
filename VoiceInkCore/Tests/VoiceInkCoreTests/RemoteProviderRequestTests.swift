import Foundation
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

    func testChatRequestBuilderIncludesReasoningAndExtraBodyParameters() throws {
        let request = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
            baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
            apiKey: "llm-key",
            model: "openai/gpt-oss-120b",
            messages: [
                VoiceInkOpenAICompatibleChatMessage(role: "user", content: "User")
            ],
            temperature: 1,
            reasoningEffort: "low",
            extraBodyParameters: ["include_reasoning": false]
        )

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, "openai/gpt-oss-120b")
        XCTAssertEqual(body["temperature"] as? Double, 1)
        XCTAssertEqual(body["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body["include_reasoning"] as? Bool, false)
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

    func testOpenAICompatibleClientUsesSharedHTTPResponseValidationForChatErrors() async throws {
        var capturedPath = ""
        RemoteProviderRequestCapturingURLProtocol.requestHandler = { request in
            capturedPath = request.url?.path ?? ""
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("rate limited".utf8))
        }

        URLProtocol.registerClass(RemoteProviderRequestCapturingURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RemoteProviderRequestCapturingURLProtocol.self)
            RemoteProviderRequestCapturingURLProtocol.requestHandler = nil
        }

        do {
            _ = try await VoiceInkOpenAICompatibleClient().chatCompletion(
                baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
                apiKey: "llm-key",
                model: "llama-3.3-70b-versatile",
                messages: [
                    VoiceInkOpenAICompatibleChatMessage(role: "user", content: "Clean this")
                ]
            )
            XCTFail("Expected non-2xx chat response to throw")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "LLMPostProcessing")
            XCTAssertEqual(nsError.code, 429)
            XCTAssertEqual(nsError.userInfo[NSLocalizedDescriptionKey] as? String, "rate limited")
        }

        XCTAssertEqual(capturedPath, "/openai/v1/chat/completions")
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
        XCTAssertEqual(
            body,
            [
                "--Boundary-test",
                #"Content-Disposition: form-data; name="file"; filename="sample.wav""#,
                "Content-Type: audio/wav",
                "",
                "WAVDATA",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="model""#,
                "",
                "whisper-large-v3",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="language""#,
                "",
                "en",
                "--Boundary-test--",
                ""
            ].joined(separator: "\r\n")
        )
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
        XCTAssertEqual(
            body,
            [
                "--Boundary-test",
                #"Content-Disposition: form-data; name="file"; filename="sample.wav""#,
                "Content-Type: audio/wav",
                "",
                "WAVDATA",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="model""#,
                "",
                "whisper-large-v3",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="response_format""#,
                "",
                "json",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="temperature""#,
                "",
                "0",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="language""#,
                "",
                "en",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="prompt""#,
                "",
                "spell project names correctly",
                "--Boundary-test--",
                ""
            ].joined(separator: "\r\n")
        )
    }

    func testOpenAICompatibleTranscriptionRequestBuilderOmitsOnlyNilAndEmptyOptionalFields() throws {
        let preparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
            apiKey: "stt-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            model: "whisper-large-v3",
            boundary: "Boundary-test",
            language: " ",
            prompt: "",
            responseFormat: nil,
            temperature: "  "
        )

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertFalse(body.contains(#"name="response_format""#))
        XCTAssertFalse(body.contains(#"name="prompt""#))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="language""#))
        XCTAssertTrue(body.contains("\r\n \r\n"))
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="temperature""#))
        XCTAssertTrue(body.contains("\r\n  \r\n"))
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
        XCTAssertEqual(preparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-key")
        XCTAssertEqual(
            preparedRequest.request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-test"
        )

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertEqual(
            body,
            [
                "--Boundary-test",
                #"Content-Disposition: form-data; name="file"; filename="sample.wav""#,
                "Content-Type: audio/wav",
                "",
                "WAVDATA",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="model""#,
                "",
                "custom-whisper",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="response_format""#,
                "",
                "json",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="temperature""#,
                "",
                "0",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="language""#,
                "",
                "en",
                "--Boundary-test",
                #"Content-Disposition: form-data; name="prompt""#,
                "",
                "spell project names correctly",
                "--Boundary-test--",
                ""
            ].joined(separator: "\r\n")
        )
    }

    func testOpenAICompatibleTranscriptionCodecReturnsTextWhenPresent() throws {
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

    func testOpenAICompatibleTranscriptionClientUsesSharedRetryRequest() async throws {
        var requestCount = 0
        RemoteProviderRequestCapturingURLProtocol.requestHandler = { request in
            requestCount += 1
            let statusCode = requestCount == 1 ? 429 : 200
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = requestCount == 1
                ? Data("rate limited".utf8)
                : Data(#"{"text":"transcribed after retry"}"#.utf8)
            return (response, data)
        }

        URLProtocol.registerClass(RemoteProviderRequestCapturingURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RemoteProviderRequestCapturingURLProtocol.self)
            RemoteProviderRequestCapturingURLProtocol.requestHandler = nil
        }

        let text = try await VoiceInkOpenAICompatibleTranscriptionClient().transcribeAudioData(
            baseURL: try XCTUnwrap(URL(string: "https://api.groq.com/openai")),
            apiKey: "stt-key",
            model: "whisper-large-v3",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            errorDomain: "GroqAPI",
            maxRetries: 1
        )

        XCTAssertEqual(text, "transcribed after retry")
        XCTAssertEqual(requestCount, 2)
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

    func testRemoteTranscriptionOptionsPreserveMacOSBatchProviderPolicies() {
        let groq = VoiceInkRemoteTranscriptionOptions.batchDefaults(
            for: .groq,
            prompt: "spell Roma correctly",
            customVocabulary: ["Roma"]
        )
        XCTAssertEqual(groq.prompt, "spell Roma correctly")
        XCTAssertEqual(groq.openAICompatibleResponseFormat, "json")
        XCTAssertEqual(groq.openAICompatibleTemperature, "0")
        XCTAssertEqual(groq.openAICompatibleErrorDomain, "GroqAPI")
        XCTAssertEqual(groq.openAICompatibleTimeout, 60)
        XCTAssertEqual(groq.openAICompatibleMaxRetries, 2)

        let openAI = VoiceInkRemoteTranscriptionOptions.batchDefaults(
            for: .openAI,
            prompt: "spell Roma correctly"
        )
        XCTAssertEqual(openAI.prompt, "spell Roma correctly")
        XCTAssertNil(openAI.openAICompatibleResponseFormat)
        XCTAssertNil(openAI.openAICompatibleTemperature)
        XCTAssertNil(openAI.openAICompatibleTimeout)

        let deepgram = VoiceInkRemoteTranscriptionOptions.batchDefaults(
            for: .deepgram,
            prompt: "ignored"
        )
        XCTAssertNil(deepgram.prompt)
        XCTAssertEqual(deepgram.deepgramParagraphs, true)
        XCTAssertNil(deepgram.deepgramDiarize)
        XCTAssertEqual(deepgram.deepgramTimeout, 30)
        XCTAssertTrue(deepgram.customVocabulary.isEmpty)

        let soniox = VoiceInkRemoteTranscriptionOptions.batchDefaults(
            for: .soniox,
            customVocabulary: [" Roma ", "Felix", "roma", ""]
        )
        XCTAssertEqual(soniox.customVocabulary, ["Roma", "Felix"])

        let speechmatics = VoiceInkRemoteTranscriptionOptions.batchDefaults(
            for: .speechmatics,
            customVocabulary: ["Roma"]
        )
        XCTAssertEqual(speechmatics.customVocabulary, ["Roma"])

        let assemblyAI = VoiceInkRemoteTranscriptionOptions.batchDefaults(
            for: .assemblyAI,
            prompt: "spell project names correctly",
            customVocabulary: ["Roma"]
        )
        XCTAssertEqual(assemblyAI.prompt, "spell project names correctly")
        XCTAssertEqual(assemblyAI.customVocabulary, ["Roma"])

        let gemini = VoiceInkRemoteTranscriptionOptions.batchDefaults(
            for: .gemini,
            prompt: "ignored",
            customVocabulary: ["ignored"]
        )
        XCTAssertNil(gemini.prompt)
        XCTAssertTrue(gemini.customVocabulary.isEmpty)
        XCTAssertNil(gemini.openAICompatibleResponseFormat)
    }

    func testRemoteTranscriptionServiceFileOptionsUseProviderBatchDefaults() throws {
        let groq = VoiceInkRemoteTranscriptionService(provider: .groq)
            .fileTranscriptionOptions(prompt: "spell Roma correctly")
        XCTAssertEqual(groq.prompt, "spell Roma correctly")
        XCTAssertEqual(groq.openAICompatibleResponseFormat, "json")
        XCTAssertEqual(groq.openAICompatibleTemperature, "0")
        XCTAssertEqual(groq.openAICompatibleTimeout, 60)
        XCTAssertEqual(groq.openAICompatibleMaxRetries, 2)

        let deepgram = VoiceInkRemoteTranscriptionService(provider: .deepgram)
            .fileTranscriptionOptions(prompt: "ignored")
        XCTAssertNil(deepgram.prompt)
        XCTAssertEqual(deepgram.deepgramParagraphs, true)
        XCTAssertNil(deepgram.deepgramDiarize)
        XCTAssertEqual(deepgram.deepgramTimeout, 30)

        let soniox = VoiceInkRemoteTranscriptionService(provider: .soniox)
            .fileTranscriptionOptions(
                prompt: "ignored",
                customVocabulary: [" Roma ", "Felix", "roma", ""]
            )
        XCTAssertEqual(soniox.customVocabulary, ["Roma", "Felix"])

        let directTransport = VoiceInkRemoteTranscriptionService(
            transport: .openAICompatible,
            apiBaseURL: try XCTUnwrap(URL(string: "https://custom.example.test"))
        )
            .fileTranscriptionOptions(
                prompt: "custom prompt",
                customVocabulary: ["Roma"]
            )
        XCTAssertEqual(directTransport.prompt, "custom prompt")
        XCTAssertEqual(directTransport.customVocabulary, ["Roma"])
        XCTAssertNil(directTransport.openAICompatibleResponseFormat)
        XCTAssertNil(directTransport.openAICompatibleTimeout)
    }

    func testMacOSCloudTranscriptionPolicyBuildsSharedTransportRequest() async throws {
        let requestCapture = MacOSCloudTranscriptionRequestCapture()

        let text = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
            modelProvider: .soniox,
            apiKey: "soniox-key",
            modelName: "stt-async-v4",
            audioData: Data([4, 5, 6]),
            fileName: "clip.wav",
            language: "en",
            prompt: "ignored",
            customVocabulary: [" Roma ", "Felix", "roma", ""]
        ) { request in
            await requestCapture.store(request)
            return "remote transcript"
        }

        let capturedRequest = await requestCapture.value
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(text, "remote transcript")
        XCTAssertEqual(request.provider, .soniox)
        XCTAssertEqual(request.apiKey, "soniox-key")
        XCTAssertEqual(request.modelName, "stt-async-v4")
        XCTAssertEqual(request.audioData, Data([4, 5, 6]))
        XCTAssertEqual(request.fileName, "clip.wav")
        XCTAssertEqual(request.language, "en")
        XCTAssertNil(request.options.prompt)
        XCTAssertEqual(request.options.customVocabulary, ["Roma", "Felix"])
    }

    func testMacOSCloudTranscriptionPolicyRejectsBlankAPIKeyBeforeTransport() async {
        do {
            _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: .soniox,
                apiKey: " \n\t ",
                modelName: "stt-async-v4",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil,
                customVocabulary: []
            ) { _ in
                XCTFail("Blank API keys should not call transport")
                return "unexpected"
            }
            XCTFail("Expected missing API key error")
        } catch VoiceInkCloudTranscriptionError.missingAPIKey {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMacOSCloudTranscriptionPolicyRejectsUnsupportedBatchProvider() async {
        do {
            _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: .cartesia,
                apiKey: "cartesia-key",
                modelName: "ink-whisper",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil,
                customVocabulary: []
            ) { _ in
                XCTFail("Unsupported provider should not call transport")
                return "unexpected"
            }
            XCTFail("Expected unsupported provider error")
        } catch VoiceInkCloudTranscriptionError.unsupportedProvider {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMacOSCloudTranscriptionPolicyMapsProviderHTTPNSError() async {
        do {
            _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: .assemblyAI,
                apiKey: "assembly-key",
                modelName: "universal-3-pro",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil,
                customVocabulary: []
            ) { _ in
                throw NSError(
                    domain: try XCTUnwrap(VoiceInkMacOSTranscriptionModelProvider.assemblyAI.apiErrorDomain),
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "server failed"]
                )
            }
            XCTFail("Expected API request failure")
        } catch VoiceInkCloudTranscriptionError.apiRequestFailed(let statusCode, let message) {
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(message, "server failed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMacOSCloudTranscriptionPolicyMapsUnknownErrorsToNetworkError() async {
        do {
            _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: .soniox,
                apiKey: "soniox-key",
                modelName: "stt-async-v4",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil,
                customVocabulary: []
            ) { _ in
                throw NSError(
                    domain: "Transport",
                    code: -42,
                    userInfo: [NSLocalizedDescriptionKey: "socket closed"]
                )
            }
            XCTFail("Expected network error")
        } catch VoiceInkCloudTranscriptionError.networkError(let error) {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "Transport")
            XCTAssertEqual(nsError.code, -42)
            XCTAssertEqual(nsError.localizedDescription, "socket closed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoteTranscriptionServiceUsesSharedProviderErrorDomainsForProviderTransports() throws {
        let providers: [(VoiceInkProviderKind, VoiceInkTranscriptionModelProvider)] = [
            (.mistral, .mistral),
            (.assemblyAI, .assemblyAI),
            (.xai, .xai)
        ]

        for (provider, modelProvider) in providers {
            XCTAssertEqual(
                VoiceInkRemoteTranscriptionService(provider: provider)
                    .providerAPIErrorDomain(defaultingTo: modelProvider),
                try XCTUnwrap(provider.transcriptionModelProvider?.apiErrorDomain)
            )
        }

        let directMistral = VoiceInkRemoteTranscriptionService(
            transport: .mistral,
            apiBaseURL: try XCTUnwrap(URL(string: "https://api.mistral.ai"))
        )
        XCTAssertEqual(
            directMistral.providerAPIErrorDomain(defaultingTo: .mistral),
            VoiceInkTranscriptionModelProvider.mistral.apiErrorDomain
        )
    }

    func testRemoteTranscriptionServicePassesFilePromptToTranscriptionRequest() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.RemoteProviderRequestTests.\(UUID().uuidString).wav")
        try Data("WAVDATA".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        var capturedBody = ""
        RemoteProviderRequestCapturingURLProtocol.requestHandler = { request in
            capturedBody = RemoteProviderRequestCapturingURLProtocol.bodyString(from: request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"{"text":"transcribed"}"#.utf8))
        }

        URLProtocol.registerClass(RemoteProviderRequestCapturingURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RemoteProviderRequestCapturingURLProtocol.self)
            RemoteProviderRequestCapturingURLProtocol.requestHandler = nil
        }

        let service = VoiceInkRemoteTranscriptionService(provider: .openAI)
        let text = try await service.transcribeAudioFile(
            apiKey: "stt-key",
            model: "gpt-4o-transcribe",
            fileURL: audioURL,
            language: "en",
            prompt: "spell Roma correctly"
        )

        XCTAssertEqual(text, "transcribed")
        XCTAssertTrue(capturedBody.contains("Content-Disposition: form-data; name=\"prompt\""))
        XCTAssertTrue(capturedBody.contains("spell Roma correctly"))
    }

    func testRemoteTranscriptionServiceUsesSharedAudioFilePolicyForMissingFile() async {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.RemoteProviderRequestTests.missing.\(UUID().uuidString).wav")
        let service = VoiceInkRemoteTranscriptionService(provider: .openAI)

        do {
            _ = try await service.transcribeAudioFile(
                apiKey: "stt-key",
                model: "gpt-4o-transcribe",
                fileURL: audioURL
            )
            XCTFail("Expected audio file not found")
        } catch VoiceInkCloudTranscriptionError.audioFileNotFound {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    func testElevenLabsTranscriptionRequestBuilderUsesMultipartAudioRequest() throws {
        let audioData = Data("WAVDATA".utf8)
        let preparedRequest = VoiceInkElevenLabsRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
            apiKey: "eleven-key",
            model: "scribe_v2",
            audioData: audioData,
            fileName: "sample.wav",
            language: "en",
            boundary: "Boundary-test",
            timeout: 30
        )

        XCTAssertEqual(preparedRequest.request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
        XCTAssertEqual(preparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "xi-api-key"), "eleven-key")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(
            preparedRequest.request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-test"
        )
        XCTAssertEqual(preparedRequest.request.timeoutInterval, 30)

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"sample.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.contains("WAVDATA"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model_id\""))
        XCTAssertTrue(body.contains("scribe_v2"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"temperature\""))
        XCTAssertTrue(body.contains("0.0"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"tag_audio_events\""))
        XCTAssertTrue(body.contains("false"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"language_code\""))
        XCTAssertTrue(body.contains("en"))
        XCTAssertTrue(body.contains("--Boundary-test--"))
    }

    func testElevenLabsUserRequestBuilderUsesUserEndpoint() throws {
        let request = VoiceInkElevenLabsRequestBuilder.makeUserRequest(
            baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
            apiKey: "eleven-key",
            timeout: 10
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "eleven-key")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testElevenLabsClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkElevenLabsTranscriptionClient().verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
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

    func testElevenLabsTranscriptionCodecReturnsText() throws {
        XCTAssertEqual(
            try VoiceInkElevenLabsTranscriptionCodec.transcript(from: Data(#"{"text":"eleven text"}"#.utf8)),
            "eleven text"
        )
    }

    func testXAITranscriptionRequestBuilderUsesMultipartAudioRequestWithFileLast() throws {
        let audioData = Data("WAVDATA".utf8)
        let preparedRequest = VoiceInkXAIRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.xaiAPIBaseURL,
            apiKey: "xai-key",
            audioData: audioData,
            fileName: "sample.wav",
            language: "en",
            format: true,
            boundary: "Boundary-test",
            timeout: 60
        )

        XCTAssertEqual(preparedRequest.request.url?.absoluteString, "https://api.x.ai/v1/stt")
        XCTAssertEqual(preparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer xai-key")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(
            preparedRequest.request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-test"
        )
        XCTAssertEqual(preparedRequest.request.timeoutInterval, 60)

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        let languageIndex = try XCTUnwrap(body.range(of: "name=\"language\"")?.lowerBound)
        let formatIndex = try XCTUnwrap(body.range(of: "name=\"format\"")?.lowerBound)
        let fileIndex = try XCTUnwrap(body.range(of: "name=\"file\"; filename=\"sample.wav\"")?.lowerBound)
        XCTAssertLessThan(languageIndex, fileIndex)
        XCTAssertLessThan(formatIndex, fileIndex)
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.contains("WAVDATA"))
        XCTAssertTrue(body.contains("--Boundary-test--"))
    }

    func testXAITranscriptionRequestBuilderSkipsLanguageAndFormatForAutoDetect() throws {
        let preparedRequest = VoiceInkXAIRequestBuilder.makeTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.xaiAPIBaseURL,
            apiKey: "xai-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            language: "auto",
            format: true,
            boundary: "Boundary-test"
        )

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertFalse(body.contains("name=\"language\""))
        XCTAssertFalse(body.contains("name=\"format\""))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"sample.wav\""))
    }

    func testXAIAPIKeyRequestBuilderUsesAPIKeyEndpoint() throws {
        let request = VoiceInkXAIRequestBuilder.makeAPIKeyRequest(
            baseURL: VoiceInkProviderEndpoint.xaiAPIBaseURL,
            apiKey: "xai-key",
            timeout: 10
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.x.ai/v1/api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xai-key")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testXAIClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkXAITranscriptionClient().verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.xaiAPIBaseURL,
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

    func testXAITranscriptionCodecReturnsText() throws {
        XCTAssertEqual(
            try VoiceInkXAITranscriptionCodec.transcript(from: Data(#"{"text":"xai text"}"#.utf8)),
            "xai text"
        )
    }

    func testSonioxUploadFileRequestBuilderUsesFilesEndpointAndMultipartBody() throws {
        let preparedRequest = VoiceInkSonioxRequestBuilder.makeUploadFileRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            boundary: "Boundary-test",
            timeout: 30
        )

        XCTAssertEqual(preparedRequest.request.url?.absoluteString, "https://api.soniox.com/v1/files")
        XCTAssertEqual(preparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer soniox-key")
        XCTAssertEqual(
            preparedRequest.request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-test"
        )
        XCTAssertEqual(preparedRequest.request.timeoutInterval, 30)

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"sample.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.contains("WAVDATA"))
        XCTAssertTrue(body.contains("--Boundary-test--"))
    }

    func testSonioxCreateTranscriptionRequestBuilderUsesLanguageAndContextPayload() throws {
        let request = try VoiceInkSonioxRequestBuilder.makeCreateTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            fileID: "file-123",
            model: "stt-async-v4",
            language: "en",
            customVocabulary: ["Roma", "Felix"],
            timeout: 30
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.soniox.com/v1/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer soniox-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 30)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["file_id"] as? String, "file-123")
        XCTAssertEqual(json["model"] as? String, "stt-async-v4")
        XCTAssertEqual(json["enable_speaker_diarization"] as? Bool, false)
        XCTAssertEqual(json["enable_language_identification"] as? Bool, true)
        XCTAssertEqual(json["language_hints_strict"] as? Bool, true)
        XCTAssertEqual(json["language_hints"] as? [String], ["en"])
        let context = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(context["terms"] as? [String], ["Roma", "Felix"])
    }

    func testSonioxCreateTranscriptionRequestBuilderEnablesLanguageIdentificationWithoutHints() throws {
        let request = try VoiceInkSonioxRequestBuilder.makeCreateTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            fileID: "file-123",
            model: "stt-async-v4"
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["enable_language_identification"] as? Bool, true)
        XCTAssertNil(json["language_hints"])
        XCTAssertNil(json["language_hints_strict"])
        XCTAssertNil(json["context"])
    }

    func testSonioxStatusTranscriptAndVerificationRequestBuilders() throws {
        let status = VoiceInkSonioxRequestBuilder.makeTranscriptionStatusRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            id: "tx-123",
            timeout: 30
        )
        XCTAssertEqual(status.url?.absoluteString, "https://api.soniox.com/v1/transcriptions/tx-123")
        XCTAssertEqual(status.httpMethod, "GET")
        XCTAssertEqual(status.value(forHTTPHeaderField: "Authorization"), "Bearer soniox-key")
        XCTAssertEqual(status.timeoutInterval, 30)

        let transcript = VoiceInkSonioxRequestBuilder.makeTranscriptRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            id: "tx-123",
            timeout: 30
        )
        XCTAssertEqual(transcript.url?.absoluteString, "https://api.soniox.com/v1/transcriptions/tx-123/transcript")
        XCTAssertEqual(transcript.value(forHTTPHeaderField: "Authorization"), "Bearer soniox-key")

        let files = VoiceInkSonioxRequestBuilder.makeFilesRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            timeout: 10
        )
        XCTAssertEqual(files.url?.absoluteString, "https://api.soniox.com/v1/files")
        XCTAssertEqual(files.httpMethod, "GET")
        XCTAssertEqual(files.value(forHTTPHeaderField: "Authorization"), "Bearer soniox-key")
        XCTAssertEqual(files.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(files.timeoutInterval, 10)
    }

    func testSonioxClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkSonioxTranscriptionClient().verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
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

    func testSonioxTranscriptionCodecReturnsIdsStatusAndTranscript() throws {
        XCTAssertEqual(
            try VoiceInkSonioxTranscriptionCodec.uploadedFileID(from: Data(#"{"id":"file-123"}"#.utf8)),
            "file-123"
        )
        XCTAssertEqual(
            try VoiceInkSonioxTranscriptionCodec.createdTranscriptionID(from: Data(#"{"id":"tx-123"}"#.utf8)),
            "tx-123"
        )
        XCTAssertEqual(
            try VoiceInkSonioxTranscriptionCodec.status(from: Data(#"{"status":"completed"}"#.utf8)),
            "completed"
        )
        XCTAssertEqual(
            VoiceInkSonioxTranscriptionCodec.transcript(from: Data(#"{"text":"soniox text"}"#.utf8)),
            "soniox text"
        )
        XCTAssertEqual(
            VoiceInkSonioxTranscriptionCodec.transcript(from: Data("plain soniox text".utf8)),
            "plain soniox text"
        )
    }

    func testSpeechmaticsSubmitJobRequestBuilderUsesJobsEndpointAndMultipartBody() throws {
        let preparedRequest = try VoiceInkSpeechmaticsRequestBuilder.makeSubmitJobRequest(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: "speechmatics-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            language: "zh",
            operatingPoint: "enhanced",
            customVocabulary: ["Roma", "Felix"],
            boundary: "Boundary-test",
            timeout: 30
        )

        XCTAssertEqual(preparedRequest.request.url?.absoluteString, "https://asr.api.speechmatics.com/v2/jobs")
        XCTAssertEqual(preparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer speechmatics-key")
        XCTAssertEqual(
            preparedRequest.request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-test"
        )
        XCTAssertEqual(preparedRequest.request.timeoutInterval, 30)

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"config\""))
        XCTAssertTrue(body.contains(#""type":"transcription""#))
        XCTAssertTrue(body.contains(#""language":"cmn""#))
        XCTAssertTrue(body.contains(#""operating_point":"enhanced""#))
        XCTAssertTrue(body.contains(#""additional_vocab""#))
        XCTAssertTrue(body.contains(#""content":"Roma""#))
        XCTAssertTrue(body.contains(#""content":"Felix""#))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"data_file\"; filename=\"sample.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.contains("WAVDATA"))
        XCTAssertTrue(body.contains("--Boundary-test--"))
    }

    func testSpeechmaticsSubmitJobRequestBuilderDefaultsAutoLanguage() throws {
        let preparedRequest = try VoiceInkSpeechmaticsRequestBuilder.makeSubmitJobRequest(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: "speechmatics-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            language: nil,
            boundary: "Boundary-test"
        )

        let body = try XCTUnwrap(String(data: preparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains(#""language":"auto""#))
        XCTAssertFalse(body.contains(#""additional_vocab""#))
    }

    func testSpeechmaticsStatusTranscriptAndVerificationRequestBuilders() throws {
        let status = VoiceInkSpeechmaticsRequestBuilder.makeJobStatusRequest(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: "speechmatics-key",
            id: "job-123",
            timeout: 30
        )
        XCTAssertEqual(status.url?.absoluteString, "https://asr.api.speechmatics.com/v2/jobs/job-123")
        XCTAssertEqual(status.httpMethod, "GET")
        XCTAssertEqual(status.value(forHTTPHeaderField: "Authorization"), "Bearer speechmatics-key")
        XCTAssertEqual(status.timeoutInterval, 30)

        let transcript = VoiceInkSpeechmaticsRequestBuilder.makeTranscriptRequest(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: "speechmatics-key",
            id: "job-123",
            timeout: 30
        )
        XCTAssertEqual(
            transcript.url?.absoluteString,
            "https://asr.api.speechmatics.com/v2/jobs/job-123/transcript?format=txt"
        )
        XCTAssertEqual(transcript.httpMethod, "GET")
        XCTAssertEqual(transcript.value(forHTTPHeaderField: "Authorization"), "Bearer speechmatics-key")
        XCTAssertEqual(transcript.timeoutInterval, 30)

        let jobs = VoiceInkSpeechmaticsRequestBuilder.makeJobsRequest(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: "speechmatics-key",
            timeout: 10
        )
        XCTAssertEqual(jobs.url?.absoluteString, "https://asr.api.speechmatics.com/v2/jobs")
        XCTAssertEqual(jobs.httpMethod, "GET")
        XCTAssertEqual(jobs.value(forHTTPHeaderField: "Authorization"), "Bearer speechmatics-key")
        XCTAssertEqual(jobs.timeoutInterval, 10)
    }

    func testSpeechmaticsClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkSpeechmaticsTranscriptionClient().verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
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

    func testSpeechmaticsTranscriptionCodecReturnsIdStatusLanguageAndTranscript() throws {
        XCTAssertEqual(
            try VoiceInkSpeechmaticsTranscriptionCodec.submittedJobID(from: Data(#"{"id":"job-123"}"#.utf8)),
            "job-123"
        )
        XCTAssertEqual(
            try VoiceInkSpeechmaticsTranscriptionCodec.jobStatus(from: Data(#"{"job":{"status":"done"}}"#.utf8)),
            "done"
        )
        XCTAssertEqual(
            VoiceInkSpeechmaticsTranscriptionCodec.speechmaticsLanguage(from: nil),
            "auto"
        )
        XCTAssertEqual(
            VoiceInkSpeechmaticsTranscriptionCodec.speechmaticsLanguage(from: "auto"),
            "auto"
        )
        XCTAssertEqual(
            VoiceInkSpeechmaticsTranscriptionCodec.speechmaticsLanguage(from: "zh"),
            "cmn"
        )
        XCTAssertEqual(
            VoiceInkSpeechmaticsTranscriptionCodec.transcript(from: Data("speechmatics text".utf8)),
            "speechmatics text"
        )
    }

    func testAssemblyAIUploadAudioRequestBuilderUsesUploadEndpointAndAudioBody() throws {
        let preparedRequest = VoiceInkAssemblyAIRequestBuilder.makeUploadAudioRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assembly-key",
            audioData: Data("WAVDATA".utf8),
            timeout: 30
        )

        XCTAssertEqual(preparedRequest.request.url?.absoluteString, "https://api.assemblyai.com/v2/upload")
        XCTAssertEqual(preparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Authorization"), "assembly-key")
        XCTAssertEqual(preparedRequest.request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(preparedRequest.request.timeoutInterval, 30)
        XCTAssertEqual(preparedRequest.body, Data("WAVDATA".utf8))
    }

    func testAssemblyAICreateTranscriptRequestBuilderUsesModelLanguagePromptAndKeyterms() throws {
        let request = try VoiceInkAssemblyAIRequestBuilder.makeCreateTranscriptRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assembly-key",
            audioURL: "https://cdn.example.test/audio.wav",
            model: "universal-3-pro",
            language: "en",
            prompt: "  spell project names  ",
            customVocabulary: [" Roma ", "Felix", "roma", "", "one two three four five six seven"],
            timeout: 30
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.assemblyai.com/v2/transcript")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "assembly-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 30)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["audio_url"] as? String, "https://cdn.example.test/audio.wav")
        XCTAssertEqual(json["speech_models"] as? [String], ["universal-3-pro", "universal-2"])
        XCTAssertEqual(json["punctuate"] as? Bool, true)
        XCTAssertEqual(json["format_text"] as? Bool, true)
        XCTAssertEqual(json["language_code"] as? String, "en")
        XCTAssertNil(json["language_detection"])
        XCTAssertEqual(
            json["prompt"] as? String,
            "spell project names\n\nBoost these terms when they appear in the audio: Roma, Felix."
        )
        XCTAssertNil(json["keyterms_prompt"])
    }

    func testAssemblyAICreateTranscriptRequestBuilderUsesAutoDetectionAndKeytermsPrompt() throws {
        let request = try VoiceInkAssemblyAIRequestBuilder.makeCreateTranscriptRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assembly-key",
            audioURL: "https://cdn.example.test/audio.wav",
            model: "universal-streaming",
            language: nil,
            customVocabulary: ["Roma", "Felix"]
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["speech_models"] as? [String], ["universal-2"])
        XCTAssertEqual(json["language_detection"] as? Bool, true)
        XCTAssertNil(json["language_code"])
        XCTAssertEqual(json["keyterms_prompt"] as? [String], ["Roma", "Felix"])
        XCTAssertNil(json["prompt"])
    }

    func testAssemblyAIStatusAndVerificationRequestBuilders() throws {
        let status = VoiceInkAssemblyAIRequestBuilder.makeTranscriptStatusRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assembly-key",
            id: "tx-123",
            timeout: 30
        )
        XCTAssertEqual(status.url?.absoluteString, "https://api.assemblyai.com/v2/transcript/tx-123")
        XCTAssertEqual(status.httpMethod, "GET")
        XCTAssertEqual(status.value(forHTTPHeaderField: "Authorization"), "assembly-key")
        XCTAssertEqual(status.timeoutInterval, 30)

        let transcripts = VoiceInkAssemblyAIRequestBuilder.makeTranscriptsRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assembly-key",
            timeout: 10
        )
        XCTAssertEqual(transcripts.url?.absoluteString, "https://api.assemblyai.com/v2/transcript")
        XCTAssertEqual(transcripts.httpMethod, "GET")
        XCTAssertEqual(transcripts.value(forHTTPHeaderField: "Authorization"), "assembly-key")
        XCTAssertEqual(transcripts.timeoutInterval, 10)
    }

    func testAssemblyAIClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkAssemblyAITranscriptionClient().verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
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

    func testAssemblyAITranscriptionCodecReturnsUploadIDAndTranscriptStatus() throws {
        XCTAssertEqual(
            try VoiceInkAssemblyAITranscriptionCodec.uploadedAudioURL(
                from: Data(#"{"upload_url":"https://cdn.example.test/audio.wav"}"#.utf8)
            ),
            "https://cdn.example.test/audio.wav"
        )
        XCTAssertEqual(
            try VoiceInkAssemblyAITranscriptionCodec.createdTranscriptID(from: Data(#"{"id":"tx-123"}"#.utf8)),
            "tx-123"
        )
        XCTAssertEqual(
            try VoiceInkAssemblyAITranscriptionCodec.transcriptStatus(
                from: Data(#"{"status":"completed","text":"assembly text","error":null}"#.utf8)
            ),
            VoiceInkAssemblyAITranscriptStatus(
                status: "completed",
                text: "assembly text",
                error: nil
            )
        )
    }

    func testCartesiaVoicesRequestBuilderUsesVersionedVoicesEndpoint() throws {
        let request = VoiceInkCartesiaRequestBuilder.makeVoicesRequest(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
            apiKey: "cartesia-key",
            timeout: 10
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.cartesia.ai/voices?limit=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "cartesia-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cartesia-Version"), "2026-03-01")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testCartesiaClientRejectsBlankAPIKeyWithoutNetwork() async throws {
        let result = await VoiceInkCartesiaClient().verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
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
}

private actor MacOSCloudTranscriptionRequestCapture {
    private var storedValue: VoiceInkMacOSCloudTranscriptionRequest?

    var value: VoiceInkMacOSCloudTranscriptionRequest? {
        storedValue
    }

    func store(_ request: VoiceInkMacOSCloudTranscriptionRequest) {
        storedValue = request
    }
}

private final class RemoteProviderRequestCapturingURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func bodyString(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
