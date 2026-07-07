import Foundation
import VoiceInkCore

final class AssemblyAIPublicAPITests: XCTestCase {
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
                errorDomain: "AssemblyAIPublicAPITests"
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
