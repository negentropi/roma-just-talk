import XCTest
import RomaCore

final class IOSOllamaPostProcessingTests: XCTestCase {
    func testConfiguredOllamaServiceControlsPostProcessingAvailability() {
        let state = RomaProviderAPIKeyState()

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
            XCTAssertEqual(RomaProviderKind.ollama.models(for: .postProcessing), ["llama3.2"])

            let modelsRequest = RomaOpenAICompatibleModelsRequestBuilder.make(
                baseURL: RomaProviderKind.ollama.apiBaseURL,
                apiKey: "local-ollama"
            )
            let chatRequest = try RomaOpenAICompatibleChatRequestBuilder.make(
                baseURL: RomaProviderKind.ollama.apiBaseURL,
                apiKey: "local-ollama",
                model: "llama3.2",
                messages: [RomaOpenAICompatibleChatMessage(role: "user", content: "Polish")],
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
        let previousBaseURL = RomaDynamicAIProviderPreference.ollamaBaseURL()
        let previousModel = RomaDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
        RomaDynamicAIProviderPreference.saveOllamaBaseURL(baseURL)
        RomaDynamicAIProviderPreference.saveOllamaSelectedModel(model)
        defer {
            RomaDynamicAIProviderPreference.saveOllamaBaseURL(previousBaseURL)
            RomaDynamicAIProviderPreference.saveOllamaSelectedModel(previousModel)
        }
        try run()
    }
}
