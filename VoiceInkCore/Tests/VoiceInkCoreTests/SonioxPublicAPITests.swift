import Foundation
import VoiceInkCore

final class SonioxPublicAPITests: XCTestCase {
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
                errorDomain: "SonioxPublicAPITests"
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
}
