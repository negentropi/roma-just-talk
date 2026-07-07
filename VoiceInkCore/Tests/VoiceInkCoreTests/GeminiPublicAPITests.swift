import Foundation
import VoiceInkCore

final class GeminiPublicAPITests: XCTestCase {
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
}
