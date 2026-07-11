import XCTest
import VoiceInkCore

final class IOSPostProcessingProviderTests: XCTestCase {
    func testMistralCredentialUnlocksSharedPostProcessingSelection() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.mistral: "mistral-key"],
            verifiedProviders: [.mistral]
        )

        XCTAssertEqual(
            state.availableProviders(
                for: .postProcessing,
                localWhisperModelAvailable: false
            ),
            [.mistral]
        )
        XCTAssertEqual(
            VoiceInkProviderKind.mistral.postProcessingModels,
            VoiceInkAIModelCatalog.availableModels(for: .mistral)
        )
    }

    func testMistralPostProcessingUsesOpenAICompatibleChatRoute() throws {
        let model = try XCTUnwrap(VoiceInkProviderKind.mistral.postProcessingDefaultModel)
        let request = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
            baseURL: VoiceInkProviderKind.mistral.apiBaseURL,
            apiKey: "mistral-key",
            model: model,
            messages: [
                VoiceInkOpenAICompatibleChatMessage(role: "user", content: "Polish this transcript")
            ],
            temperature: 0.2
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mistral-key")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(VoiceInkOpenAICompatibleChatRequest.self, from: body)
        XCTAssertEqual(payload.model, model)
        XCTAssertEqual(payload.messages.first?.content, "Polish this transcript")
    }
}
