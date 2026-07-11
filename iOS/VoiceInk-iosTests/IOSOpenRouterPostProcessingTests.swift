import XCTest
import VoiceInkCore

final class IOSOpenRouterPostProcessingTests: XCTestCase {
    func testVerifiedOpenRouterCredentialUnlocksPostProcessing() {
        let state = VoiceInkProviderAPIKeyState(
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
        XCTAssertFalse(VoiceInkProviderKind.openRouter.models(for: .postProcessing).isEmpty)
    }

    func testOpenRouterUsesCompatibleModelAndChatRoutes() throws {
        let modelsRequest = VoiceInkOpenAICompatibleModelsRequestBuilder.make(
            baseURL: VoiceInkProviderKind.openRouter.apiBaseURL,
            apiKey: "openrouter-key"
        )
        let chatRequest = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
            baseURL: VoiceInkProviderKind.openRouter.apiBaseURL,
            apiKey: "openrouter-key",
            model: VoiceInkAIModelCatalog.defaultModel(for: .openRouter),
            messages: [VoiceInkOpenAICompatibleChatMessage(role: "user", content: "Polish")],
            temperature: 0.2
        )

        XCTAssertEqual(modelsRequest.url?.absoluteString, "https://openrouter.ai/api/v1/models")
        XCTAssertEqual(chatRequest.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
    }

    func testOpenRouterModelResponseExtractsNonblankIDsInOrder() throws {
        let data = try JSONEncoder().encode(VoiceInkOpenAICompatibleModelsResponse(data: [
            VoiceInkOpenAICompatibleModelRecord(id: "model/b"),
            VoiceInkOpenAICompatibleModelRecord(id: " "),
            VoiceInkOpenAICompatibleModelRecord(id: "model/b"),
            VoiceInkOpenAICompatibleModelRecord(id: "model/a")
        ]))

        XCTAssertEqual(
            try VoiceInkOpenAICompatibleModelsCodec.modelIDs(from: data),
            ["model/b", "model/a"]
        )
    }
}
