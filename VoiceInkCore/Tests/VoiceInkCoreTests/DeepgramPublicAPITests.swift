import Foundation
import VoiceInkCore

final class DeepgramPublicAPITests: XCTestCase {
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
}
