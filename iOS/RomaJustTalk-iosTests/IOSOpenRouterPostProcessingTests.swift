import XCTest
import RomaCore

final class IOSOpenRouterPostProcessingTests: XCTestCase {
    func testVerifiedOpenRouterCredentialUnlocksPostProcessing() {
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.openRouter: "openrouter-key"],
            verifiedProviders: [.openRouter]
        )

        XCTAssertEqual(
            state.availableProviders(
                for: .postProcessing,
                localWhisperModelAvailable: false
            ),
            [.openRouter]
        )
        XCTAssertFalse(RomaProviderKind.openRouter.models(for: .postProcessing).isEmpty)
    }

    func testOpenRouterUsesCompatibleModelAndChatRoutes() throws {
        let modelsRequest = RomaOpenAICompatibleModelsRequestBuilder.make(
            baseURL: RomaProviderKind.openRouter.apiBaseURL,
            apiKey: "openrouter-key"
        )
        let chatRequest = try RomaOpenAICompatibleChatRequestBuilder.make(
            baseURL: RomaProviderKind.openRouter.apiBaseURL,
            apiKey: "openrouter-key",
            model: RomaAIModelCatalog.defaultModel(for: .openRouter),
            messages: [RomaOpenAICompatibleChatMessage(role: "user", content: "Polish")],
            temperature: 0.2
        )

        XCTAssertEqual(modelsRequest.url?.absoluteString, "https://openrouter.ai/api/v1/models")
        XCTAssertEqual(chatRequest.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
    }

    func testOpenRouterModelResponseExtractsNonblankIDsInOrder() throws {
        let data = try JSONEncoder().encode(RomaOpenAICompatibleModelsResponse(data: [
            RomaOpenAICompatibleModelRecord(id: "model/b"),
            RomaOpenAICompatibleModelRecord(id: " "),
            RomaOpenAICompatibleModelRecord(id: "model/b"),
            RomaOpenAICompatibleModelRecord(id: "model/a")
        ]))

        XCTAssertEqual(
            try RomaOpenAICompatibleModelsCodec.modelIDs(from: data),
            ["model/b", "model/a"]
        )
    }
}
