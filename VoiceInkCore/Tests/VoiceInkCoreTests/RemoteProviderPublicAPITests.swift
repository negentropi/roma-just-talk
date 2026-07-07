import Foundation
import VoiceInkCore

final class RemoteProviderPublicAPITests: XCTestCase {
    func testProviderAPIKeyVerifierPublicRoutesRejectMissingKeysWithoutNetwork() async {
        let verifier = VoiceInkProviderAPIKeyVerifier()
        let missingAPIKeyResult = VoiceInkAPIKeyVerificationResult(
            isValid: false,
            errorMessage: "API key is missing or empty."
        )

        XCTAssertEqual(
            VoiceInkAPIKeyVerificationResult(legacyResult: (true, nil)),
            VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
        )
        XCTAssertEqual(
            VoiceInkAPIKeyVerificationResult(legacyResult: (false, "invalid key")),
            VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "invalid key")
        )

        for provider in VoiceInkProviderKind.userAPIKeyProviders {
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: provider)
            XCTAssertEqual(result, missingAPIKeyResult)
        }

        let missingStoredProviderKeyIsValid = await verifier.verifyStoredAPIKey(nil, for: .groq, environment: [:])
        XCTAssertFalse(missingStoredProviderKeyIsValid)
        let missingStoredProviderKeyResult = await verifier.verifyStoredAPIKeyDetailed(
            "$MISSING_GROQ_API_KEY",
            for: VoiceInkProviderKind.groq,
            environment: [:]
        )
        XCTAssertEqual(missingStoredProviderKeyResult, missingAPIKeyResult)
        let unsupportedProviderResult = await verifier.verifyAPIKeyDetailed("key", for: .localWhisper)
        XCTAssertEqual(
            unsupportedProviderResult,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "Local (Whisper) does not support API key verification."
            )
        )

        for provider in VoiceInkTranscriptionModelProvider.allCases where provider != .local {
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: provider)
            XCTAssertEqual(result, missingAPIKeyResult)
        }
        let missingStoredTranscriptionProviderKeyResult = await verifier.verifyStoredAPIKeyDetailed(
            "$MISSING_CARTESIA_API_KEY",
            for: VoiceInkTranscriptionModelProvider.cartesia,
            environment: [:]
        )
        XCTAssertEqual(missingStoredTranscriptionProviderKeyResult, missingAPIKeyResult)
        let unsupportedTranscriptionProviderResult = await verifier.verifyAPIKeyDetailed(
            "key",
            for: VoiceInkTranscriptionModelProvider.local
        )
        XCTAssertEqual(
            unsupportedTranscriptionProviderResult,
            VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "Local (Whisper) does not support API key verification."
            )
        )

        for provider in VoiceInkMacOSTranscriptionModelProvider.allCases where provider.coreTranscriptionModelProvider != nil {
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: provider)
            XCTAssertEqual(result, missingAPIKeyResult)
        }
        let missingStoredMacOSProviderKeyResult = await verifier.verifyStoredAPIKeyDetailed(
            "$MISSING_GROQ_API_KEY",
            for: VoiceInkMacOSTranscriptionModelProvider.groq,
            environment: [:]
        )
        XCTAssertEqual(missingStoredMacOSProviderKeyResult, missingAPIKeyResult)
        let unsupportedMacOSProviderResult = await verifier.verifyStoredAPIKeyDetailed(
            "key",
            for: VoiceInkMacOSTranscriptionModelProvider.whisper
        )
        XCTAssertEqual(
            unsupportedMacOSProviderResult,
            VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "Unsupported provider")
        )
    }

    func testCartesiaRequestClientAndProviderVerifierExposePublicAPI() async {
        let request = VoiceInkCartesiaRequestBuilder.makeVoicesRequest(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
            apiKey: "cartesia-key",
            timeout: 10
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.cartesia.ai/voices?limit=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "cartesia-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cartesia-Version"), "2026-03-01")
        XCTAssertEqual(request.timeoutInterval, 10)

        let client = VoiceInkCartesiaClient()
        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = VoiceInkAPIKeyVerificationResult(
            isValid: false,
            errorMessage: "API key is missing or empty."
        )
        let detailedBlankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.cartesiaAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertEqual(detailedBlankAPIKeyResult, blankAPIKeyResult)
        let verifierBlankAPIKeyResult = await VoiceInkProviderAPIKeyVerifier().verifyAPIKeyDetailed(
            " \n\t ",
            for: VoiceInkTranscriptionModelProvider.cartesia
        )
        XCTAssertEqual(verifierBlankAPIKeyResult, blankAPIKeyResult)
    }

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
                errorDomain: "RemoteProviderPublicAPITests.OpenAICompatibleTranscription",
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
                errorDomain: "RemoteProviderPublicAPITests.OpenAICompatibleTranscription",
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
                errorDomain: "RemoteProviderPublicAPITests.Deepgram",
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
                errorDomain: "RemoteProviderPublicAPITests.Gemini",
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
                errorDomain: "RemoteProviderPublicAPITests.Mistral",
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
                errorDomain: "RemoteProviderPublicAPITests.ElevenLabs",
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

    func testSonioxRequestClientAndCodecExposePublicAPI() async throws {
        let preparedRequest = VoiceInkSonioxRequestBuilder.makeUploadFileRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            audioData: Data("WAVDATA".utf8),
            fileName: "sample.wav",
            boundary: "Boundary-test",
            timeout: 30
        )
        let publicPreparedRequest = VoiceInkPreparedSonioxUploadRequest(
            request: preparedRequest.request,
            body: preparedRequest.body
        )

        XCTAssertEqual(publicPreparedRequest.request.url?.absoluteString, "https://api.soniox.com/v1/files")
        XCTAssertEqual(publicPreparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer soniox-key")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=Boundary-test")
        XCTAssertEqual(publicPreparedRequest.request.timeoutInterval, 30)
        XCTAssertEqual(publicPreparedRequest.body, preparedRequest.body)

        let body = try XCTUnwrap(String(data: publicPreparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"sample.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))

        let createRequest = try VoiceInkSonioxRequestBuilder.makeCreateTranscriptionRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            fileID: "file-123",
            model: "stt-async-v4",
            language: "en",
            customVocabulary: ["Roma", "Felix"],
            timeout: 30
        )
        XCTAssertEqual(createRequest.url?.absoluteString, "https://api.soniox.com/v1/transcriptions")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "Authorization"), "Bearer soniox-key")
        let createBody = try XCTUnwrap(createRequest.httpBody)
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["file_id"] as? String, "file-123")
        XCTAssertEqual(createJSON["model"] as? String, "stt-async-v4")
        XCTAssertEqual(createJSON["enable_speaker_diarization"] as? Bool, false)
        XCTAssertEqual(createJSON["language_hints"] as? [String], ["en"])

        let statusRequest = VoiceInkSonioxRequestBuilder.makeTranscriptionStatusRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            id: "tx-123",
            timeout: 30
        )
        XCTAssertEqual(statusRequest.url?.absoluteString, "https://api.soniox.com/v1/transcriptions/tx-123")

        let transcriptRequest = VoiceInkSonioxRequestBuilder.makeTranscriptRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            id: "tx-123",
            timeout: 30
        )
        XCTAssertEqual(transcriptRequest.url?.absoluteString, "https://api.soniox.com/v1/transcriptions/tx-123/transcript")

        let filesRequest = VoiceInkSonioxRequestBuilder.makeFilesRequest(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: "soniox-key",
            timeout: 10
        )
        XCTAssertEqual(filesRequest.url?.absoluteString, "https://api.soniox.com/v1/files")
        XCTAssertEqual(filesRequest.value(forHTTPHeaderField: "Accept"), "application/json")

        let client = VoiceInkSonioxTranscriptionClient()
        let transcribeWithAllLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
                apiKey: "soniox-key",
                model: "stt-async-v4",
                audioData: Data("WAVDATA".utf8),
                fileName: "sample.wav",
                language: "en",
                customVocabulary: ["Roma", "Felix"],
                maxWaitSeconds: 300,
                timeout: 30,
                errorDomain: "RemoteProviderPublicAPITests.Soniox"
            )
        }
        let transcribeWithDefaultedLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
                apiKey: "soniox-key",
                model: "stt-async-v4",
                audioData: Data("WAVDATA".utf8)
            )
        }
        _ = transcribeWithAllLabels
        _ = transcribeWithDefaultedLabels

        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
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

    func testSpeechmaticsRequestClientAndCodecExposePublicAPI() async throws {
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
        let publicPreparedRequest = VoiceInkPreparedSpeechmaticsUploadRequest(
            request: preparedRequest.request,
            body: preparedRequest.body
        )

        XCTAssertEqual(publicPreparedRequest.request.url?.absoluteString, "https://asr.api.speechmatics.com/v2/jobs")
        XCTAssertEqual(publicPreparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "Authorization"), "Bearer speechmatics-key")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=Boundary-test")
        XCTAssertEqual(publicPreparedRequest.request.timeoutInterval, 30)

        let body = try XCTUnwrap(String(data: publicPreparedRequest.body, encoding: .utf8))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"config\""))
        XCTAssertTrue(body.contains(#""language":"cmn""#))
        XCTAssertTrue(body.contains(#""operating_point":"enhanced""#))
        XCTAssertTrue(body.contains(#""additional_vocab""#))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"data_file\"; filename=\"sample.wav\""))

        let statusRequest = VoiceInkSpeechmaticsRequestBuilder.makeJobStatusRequest(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: "speechmatics-key",
            id: "job-123",
            timeout: 30
        )
        XCTAssertEqual(statusRequest.url?.absoluteString, "https://asr.api.speechmatics.com/v2/jobs/job-123")

        let transcriptRequest = VoiceInkSpeechmaticsRequestBuilder.makeTranscriptRequest(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: "speechmatics-key",
            id: "job-123",
            timeout: 30
        )
        XCTAssertEqual(transcriptRequest.url?.absoluteString, "https://asr.api.speechmatics.com/v2/jobs/job-123/transcript?format=txt")

        let jobsRequest = VoiceInkSpeechmaticsRequestBuilder.makeJobsRequest(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: "speechmatics-key",
            timeout: 10
        )
        XCTAssertEqual(jobsRequest.url?.absoluteString, "https://asr.api.speechmatics.com/v2/jobs")
        XCTAssertEqual(jobsRequest.value(forHTTPHeaderField: "Authorization"), "Bearer speechmatics-key")
        XCTAssertEqual(jobsRequest.timeoutInterval, 10)

        let client = VoiceInkSpeechmaticsTranscriptionClient()
        let transcribeWithAllLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
                apiKey: "speechmatics-key",
                audioData: Data("WAVDATA".utf8),
                fileName: "sample.wav",
                language: "zh",
                operatingPoint: "enhanced",
                customVocabulary: ["Roma", "Felix"],
                maxWaitSeconds: 300,
                timeout: 30,
                maxRetries: 2,
                errorDomain: "RemoteProviderPublicAPITests.Speechmatics"
            )
        }
        let transcribeWithDefaultedLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
                apiKey: "speechmatics-key",
                audioData: Data("WAVDATA".utf8)
            )
        }
        _ = transcribeWithAllLabels
        _ = transcribeWithDefaultedLabels

        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
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
            try VoiceInkSpeechmaticsTranscriptionCodec.submittedJobID(from: Data(#"{"id":"job-123"}"#.utf8)),
            "job-123"
        )
        XCTAssertEqual(
            try VoiceInkSpeechmaticsTranscriptionCodec.jobStatus(from: Data(#"{"job":{"status":"done"}}"#.utf8)),
            "done"
        )
        XCTAssertEqual(VoiceInkSpeechmaticsTranscriptionCodec.speechmaticsLanguage(from: "zh"), "cmn")
        XCTAssertEqual(
            VoiceInkSpeechmaticsTranscriptionCodec.transcript(from: Data("speechmatics text".utf8)),
            "speechmatics text"
        )
    }

    func testAssemblyAIRequestClientAndCodecExposePublicAPI() async throws {
        let preparedRequest = VoiceInkAssemblyAIRequestBuilder.makeUploadAudioRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assemblyai-key",
            audioData: Data("WAVDATA".utf8),
            timeout: 30
        )
        let publicPreparedRequest = VoiceInkPreparedAssemblyAIUploadRequest(
            request: preparedRequest.request,
            body: preparedRequest.body
        )

        XCTAssertEqual(publicPreparedRequest.request.url?.absoluteString, "https://api.assemblyai.com/v2/upload")
        XCTAssertEqual(publicPreparedRequest.request.httpMethod, "POST")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "Authorization"), "assemblyai-key")
        XCTAssertEqual(publicPreparedRequest.request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(publicPreparedRequest.request.timeoutInterval, 30)
        XCTAssertEqual(publicPreparedRequest.body, Data("WAVDATA".utf8))

        let createRequest = try VoiceInkAssemblyAIRequestBuilder.makeCreateTranscriptRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assemblyai-key",
            audioURL: "https://cdn.example/audio.wav",
            model: "universal-3-pro",
            language: "en",
            prompt: "Domain prompt",
            customVocabulary: ["Roma", "Felix"],
            timeout: 30
        )
        XCTAssertEqual(createRequest.url?.absoluteString, "https://api.assemblyai.com/v2/transcript")
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "Authorization"), "assemblyai-key")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let createBody = try XCTUnwrap(createRequest.httpBody)
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["audio_url"] as? String, "https://cdn.example/audio.wav")
        XCTAssertEqual(createJSON["speech_models"] as? [String], ["universal-3-pro", "universal-2"])
        XCTAssertEqual(createJSON["language_code"] as? String, "en")
        XCTAssertEqual(createJSON["punctuate"] as? Bool, true)
        XCTAssertEqual(createJSON["format_text"] as? Bool, true)
        XCTAssertEqual(
            createJSON["prompt"] as? String,
            "Domain prompt\n\nBoost these terms when they appear in the audio: Roma, Felix."
        )

        let statusRequest = VoiceInkAssemblyAIRequestBuilder.makeTranscriptStatusRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assemblyai-key",
            id: "tx-123",
            timeout: 30
        )
        XCTAssertEqual(statusRequest.url?.absoluteString, "https://api.assemblyai.com/v2/transcript/tx-123")

        let transcriptsRequest = VoiceInkAssemblyAIRequestBuilder.makeTranscriptsRequest(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: "assemblyai-key",
            timeout: 10
        )
        XCTAssertEqual(transcriptsRequest.url?.absoluteString, "https://api.assemblyai.com/v2/transcript")
        XCTAssertEqual(transcriptsRequest.value(forHTTPHeaderField: "Authorization"), "assemblyai-key")
        XCTAssertEqual(transcriptsRequest.timeoutInterval, 10)

        let client = VoiceInkAssemblyAITranscriptionClient()
        let transcribeWithAllLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
                apiKey: "assemblyai-key",
                model: "universal-3-pro",
                audioData: Data("WAVDATA".utf8),
                language: "en",
                prompt: "Domain prompt",
                customVocabulary: ["Roma", "Felix"],
                maxWaitSeconds: 300,
                timeout: 30,
                maxRetries: 2,
                errorDomain: "RemoteProviderPublicAPITests.AssemblyAI"
            )
        }
        let transcribeWithDefaultedLabels = {
            try await client.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
                apiKey: "assemblyai-key",
                model: "universal-3-pro",
                audioData: Data("WAVDATA".utf8)
            )
        }
        _ = transcribeWithAllLabels
        _ = transcribeWithDefaultedLabels

        let blankAPIKeyIsValid = await client.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
            apiKey: " \n\t "
        )
        XCTAssertFalse(blankAPIKeyIsValid)

        let blankAPIKeyResult = await client.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
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
            try VoiceInkAssemblyAITranscriptionCodec.uploadedAudioURL(from: Data(#"{"upload_url":"https://cdn.example/audio.wav"}"#.utf8)),
            "https://cdn.example/audio.wav"
        )
        XCTAssertEqual(
            try VoiceInkAssemblyAITranscriptionCodec.createdTranscriptID(from: Data(#"{"id":"tx-123"}"#.utf8)),
            "tx-123"
        )
        let publicTranscriptStatus = VoiceInkAssemblyAITranscriptStatus(
            status: "completed",
            text: "assemblyai text",
            error: nil
        )
        let decodedTranscriptStatus = try VoiceInkAssemblyAITranscriptionCodec.transcriptStatus(
            from: Data(#"{"status":"completed","text":"assemblyai text","error":null}"#.utf8)
        )
        XCTAssertEqual(decodedTranscriptStatus, publicTranscriptStatus)
        XCTAssertEqual(publicTranscriptStatus.status, "completed")
        XCTAssertEqual(publicTranscriptStatus.text, "assemblyai text")
        XCTAssertNil(publicTranscriptStatus.error)
    }
}
