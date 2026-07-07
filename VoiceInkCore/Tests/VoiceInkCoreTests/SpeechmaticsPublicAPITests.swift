import Foundation
import VoiceInkCore

final class SpeechmaticsPublicAPITests: XCTestCase {
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
                errorDomain: "SpeechmaticsPublicAPITests"
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
}
