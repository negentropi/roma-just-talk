import Foundation
@testable import VoiceInkCore

final class AIReasoningConfigTests: XCTestCase {
    func testTemperatureUsesRequiredGPT5Temperature() {
        XCTAssertEqual(VoiceInkAIReasoningConfig.temperature(forModelName: "gpt-5.4"), 1)
        XCTAssertEqual(
            VoiceInkAIReasoningConfig.temperature(forModelName: "llama-3.3-70b-versatile", defaultTemperature: 0.2),
            0.2
        )
    }

    func testReasoningEffortMatchesProviderModelPolicy() {
        XCTAssertEqual(VoiceInkAIReasoningConfig.reasoningEffort(for: .gemini, modelName: "gemini-2.5-flash"), "none")
        XCTAssertEqual(VoiceInkAIReasoningConfig.reasoningEffort(for: .gemini, modelName: "gemini-3.1-pro-preview"), "low")
        XCTAssertEqual(VoiceInkAIReasoningConfig.reasoningEffort(for: .openAI, modelName: "gpt-5.4"), "none")
        XCTAssertEqual(VoiceInkAIReasoningConfig.reasoningEffort(for: .cerebras, modelName: "gpt-oss-120b"), "low")
        XCTAssertEqual(VoiceInkAIReasoningConfig.reasoningEffort(for: .groq, modelName: "qwen/qwen3-32b"), "none")
        XCTAssertNil(VoiceInkAIReasoningConfig.reasoningEffort(for: .groq, modelName: "llama-3.3-70b-versatile"))
    }

    func testExtraBodyParametersMatchProviderModelPolicy() {
        XCTAssertEqual(
            VoiceInkAIReasoningConfig.extraBodyParameters(for: .cerebras, modelName: "gpt-oss-120b")?["reasoning_format"] as? String,
            "hidden"
        )
        XCTAssertEqual(
            VoiceInkAIReasoningConfig.extraBodyParameters(for: .groq, modelName: "openai/gpt-oss-120b")?["include_reasoning"] as? Bool,
            false
        )
        XCTAssertNil(VoiceInkAIReasoningConfig.extraBodyParameters(for: .openAI, modelName: "gpt-5.4"))
    }

    func testChatRequestParametersCombineTemperatureAndReasoningPolicy() {
        let openAIParameters = VoiceInkAIReasoningConfig.chatRequestParameters(
            for: .openAI,
            modelName: "gpt-5.4",
            defaultTemperature: 0.2
        )
        XCTAssertEqual(openAIParameters.temperature, 1)
        XCTAssertEqual(openAIParameters.reasoningEffort, "none")
        XCTAssertNil(openAIParameters.extraBodyParameters)

        let groqParameters = VoiceInkAIReasoningConfig.chatRequestParameters(
            for: .groq,
            modelName: "openai/gpt-oss-120b",
            defaultTemperature: 0.2
        )
        XCTAssertEqual(groqParameters.temperature, 0.2)
        XCTAssertEqual(groqParameters.reasoningEffort, "low")
        XCTAssertEqual(groqParameters.extraBodyParameters?["include_reasoning"] as? Bool, false)

        let customParameters = VoiceInkAIReasoningConfig.chatRequestParameters(
            for: nil,
            modelName: "custom-model",
            defaultTemperature: 0.2
        )
        XCTAssertEqual(customParameters.temperature, 0.2)
        XCTAssertNil(customParameters.reasoningEffort)
        XCTAssertNil(customParameters.extraBodyParameters)
    }

    func testMacOSExtraAIProvidersUseNoSharedReasoningOverrides() {
        let providersWithoutOverrides: [VoiceInkAIModelProvider] = [
            .anthropic,
            .assemblyAI,
            .deepgram,
            .elevenLabs,
            .mistral,
            .openRouter,
            .soniox,
            .speechmatics
        ]

        for provider in providersWithoutOverrides {
            let model = VoiceInkAIModelCatalog.defaultModel(for: provider)
            XCTAssertNil(VoiceInkAIReasoningConfig.reasoningEffort(for: provider, modelName: model))
            XCTAssertNil(VoiceInkAIReasoningConfig.extraBodyParameters(for: provider, modelName: model))
        }
    }
}
