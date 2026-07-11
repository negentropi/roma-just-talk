import XCTest
import VoiceInkCore

final class IOSCustomEnhancementProviderTests: XCTestCase {
    func testConfiguredCustomProviderUnlocksPostProcessingAndRoute() throws {
        try withCustomConfiguration(
            baseURL: "https://example.com/v1/chat/completions",
            model: "private-model"
        ) {
            let state = VoiceInkProviderAPIKeyState(
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
            XCTAssertEqual(VoiceInkProviderKind.customAI.models(for: .postProcessing), ["private-model"])

            let requestURL = try XCTUnwrap(
                VoiceInkProviderKind.customAI.postProcessingChatCompletionsURL
            )
            let request = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
                requestURL: requestURL,
                apiKey: "custom-key",
                model: "private-model",
                messages: [VoiceInkOpenAICompatibleChatMessage(role: "user", content: "Polish")],
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
            XCTAssertFalse(VoiceInkProviderKind.customAI.supportsModelUse(.postProcessing))
        }
    }

    private func withCustomConfiguration(
        baseURL: String,
        model: String,
        run: () throws -> Void
    ) rethrows {
        let previousBaseURL = VoiceInkDynamicAIProviderPreference.customProviderBaseURL()
        let previousModel = VoiceInkDynamicAIProviderPreference.customProviderModel()
        VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL(baseURL)
        VoiceInkDynamicAIProviderPreference.saveCustomProviderModel(model)
        defer {
            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL(previousBaseURL)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderModel(previousModel)
        }
        try run()
    }
}
