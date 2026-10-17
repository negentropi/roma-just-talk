import XCTest
import RomaCore

final class IOSPostProcessingProviderTests: XCTestCase {
    func testMistralCredentialUnlocksSharedPostProcessingSelection() {
        let state = RomaProviderAPIKeyState(
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
            RomaProviderKind.mistral.postProcessingModels,
            RomaAIModelCatalog.availableModels(for: .mistral)
        )
    }

    func testMistralPostProcessingUsesOpenAICompatibleChatRoute() throws {
        let model = try XCTUnwrap(RomaProviderKind.mistral.postProcessingDefaultModel)
        let request = try RomaOpenAICompatibleChatRequestBuilder.make(
            baseURL: RomaProviderKind.mistral.apiBaseURL,
            apiKey: "mistral-key",
            model: model,
            messages: [
                RomaOpenAICompatibleChatMessage(role: "user", content: "Polish this transcript")
            ],
            temperature: 0.2
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mistral-key")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(RomaOpenAICompatibleChatRequest.self, from: body)
        XCTAssertEqual(payload.model, model)
        XCTAssertEqual(payload.messages.first?.content, "Polish this transcript")
    }
}
