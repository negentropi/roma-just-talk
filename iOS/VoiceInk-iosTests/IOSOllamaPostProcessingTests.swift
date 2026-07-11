import XCTest
import VoiceInkCore

final class IOSOllamaPostProcessingTests: XCTestCase {
    func testConfiguredOllamaServiceControlsPostProcessingAvailability() {
        let state = VoiceInkProviderAPIKeyState()

        XCTAssertFalse(
            state.availableProviders(
                for: .postProcessing,
                localWhisperModelAvailable: false,
                localEnhancementServiceAvailable: false
            ).contains(.ollama)
        )
        XCTAssertTrue(
            state.availableProviders(
                for: .postProcessing,
                localWhisperModelAvailable: false,
                localEnhancementServiceAvailable: true
            ).contains(.ollama)
        )
        XCTAssertEqual(
            state.runtimeAPIKey(for: .ollama),
            "local-ollama"
        )
    }

    func testOllamaUsesOpenAICompatibleLocalRoutesAndSelectedModel() throws {
        try withOllamaConfiguration(
            baseURL: "http://localhost:11434",
            model: "llama3.2"
        ) {
            XCTAssertEqual(VoiceInkProviderKind.ollama.models(for: .postProcessing), ["llama3.2"])

            let modelsRequest = VoiceInkOpenAICompatibleModelsRequestBuilder.make(
                baseURL: VoiceInkProviderKind.ollama.apiBaseURL,
                apiKey: "local-ollama"
            )
            let chatRequest = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
                baseURL: VoiceInkProviderKind.ollama.apiBaseURL,
                apiKey: "local-ollama",
                model: "llama3.2",
                messages: [VoiceInkOpenAICompatibleChatMessage(role: "user", content: "Polish")],
                temperature: 0.2
            )

            XCTAssertEqual(modelsRequest.url?.absoluteString, "http://localhost:11434/v1/models")
            XCTAssertEqual(chatRequest.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        }
    }

    private func withOllamaConfiguration(
        baseURL: String,
        model: String,
        run: () throws -> Void
    ) rethrows {
        let previousBaseURL = VoiceInkDynamicAIProviderPreference.ollamaBaseURL()
        let previousModel = VoiceInkDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
        VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL(baseURL)
        VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel(model)
        defer {
            VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL(previousBaseURL)
            VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel(previousModel)
        }
        try run()
    }
}
