import XCTest
import RomaCore

final class IOSCustomEnhancementProviderTests: XCTestCase {
    func testConfiguredCustomProviderUnlocksPostProcessingAndRoute() throws {
        try withCustomConfiguration(
            baseURL: "https://example.com/v1/chat/completions",
            model: "private-model"
        ) {
            let state = RomaProviderAPIKeyState(
                storedKeysByProvider: [.customAI: "custom-key"],
                verifiedProviders: [.customAI]
            )

            XCTAssertEqual(
                state.availableProviders(
                    for: .postProcessing,
                    localWhisperModelAvailable: false
                ),
                [.customAI]
            )
            XCTAssertEqual(RomaProviderKind.customAI.models(for: .postProcessing), ["private-model"])

            let requestURL = try XCTUnwrap(
                RomaProviderKind.customAI.postProcessingChatCompletionsURL
            )
            let request = try RomaOpenAICompatibleChatRequestBuilder.make(
                requestURL: requestURL,
                apiKey: "custom-key",
                model: "private-model",
                messages: [RomaOpenAICompatibleChatMessage(role: "user", content: "Polish")],
                temperature: 0.2
            )
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://example.com/v1/chat/completions"
            )
        }
    }

    func testCustomProviderRequiresConfiguredModel() throws {
        try withCustomConfiguration(baseURL: "https://example.com/v1/chat/completions", model: "") {
            XCTAssertFalse(RomaProviderKind.customAI.supportsModelUse(.postProcessing))
        }
    }

    private func withCustomConfiguration(
        baseURL: String,
        model: String,
        run: () throws -> Void
    ) rethrows {
        let previousBaseURL = RomaDynamicAIProviderPreference.customProviderBaseURL()
        let previousModel = RomaDynamicAIProviderPreference.customProviderModel()
        RomaDynamicAIProviderPreference.saveCustomProviderBaseURL(baseURL)
        RomaDynamicAIProviderPreference.saveCustomProviderModel(model)
        defer {
            RomaDynamicAIProviderPreference.saveCustomProviderBaseURL(previousBaseURL)
            RomaDynamicAIProviderPreference.saveCustomProviderModel(previousModel)
        }
        try run()
    }
}
