import Foundation
@testable import VoiceInkCore

final class AIModelCatalogTests: XCTestCase {
    func testMacOSAIEnhancementProviderDefaultsAreShared() {
        let expectedDefaults: [VoiceInkAIModelProvider: String] = [
            .anthropic: "claude-sonnet-4-6",
            .assemblyAI: "universal-3-pro",
            .cerebras: "gpt-oss-120b",
            .deepgram: "whisper-1",
            .elevenLabs: "scribe_v2",
            .groq: "openai/gpt-oss-120b",
            .gemini: "gemini-2.5-flash-lite",
            .mistral: "mistral-large-latest",
            .openAI: "gpt-5.4",
            .openRouter: "openai/gpt-oss-120b",
            .soniox: "stt-async-v4",
            .speechmatics: "speechmatics-enhanced"
        ]

        XCTAssertEqual(VoiceInkAIModelProvider.allCases.count, expectedDefaults.count)

        for (provider, expectedDefault) in expectedDefaults {
            XCTAssertEqual(VoiceInkAIModelCatalog.defaultModel(for: provider), expectedDefault)
        }
    }

    func testMacOSAIEnhancementProviderModelListsAreShared() {
        XCTAssertEqual(
            VoiceInkAIModelCatalog.availableModels(for: .anthropic),
            [
                "claude-opus-4-7",
                "claude-opus-4-6",
                "claude-sonnet-4-6",
                "claude-opus-4-5",
                "claude-sonnet-4-5",
                "claude-haiku-4-5"
            ]
        )
        XCTAssertEqual(
            VoiceInkAIModelCatalog.availableModels(for: .mistral),
            [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest"
            ]
        )
        XCTAssertEqual(VoiceInkAIModelCatalog.availableModels(for: .elevenLabs), ["scribe_v1", "scribe_v2"])
        XCTAssertEqual(VoiceInkAIModelCatalog.availableModels(for: .deepgram), ["whisper-1"])
        XCTAssertEqual(VoiceInkAIModelCatalog.availableModels(for: .soniox), ["stt-async-v4"])
        XCTAssertEqual(VoiceInkAIModelCatalog.availableModels(for: .speechmatics), ["speechmatics-enhanced"])
        XCTAssertEqual(VoiceInkAIModelCatalog.availableModels(for: .assemblyAI), ["universal-3-pro"])
    }

    func testOpenRouterKeepsDynamicModelListWithSharedDefault() {
        XCTAssertEqual(VoiceInkAIModelCatalog.defaultModel(for: .openRouter), "openai/gpt-oss-120b")
        XCTAssertEqual(VoiceInkAIModelCatalog.availableModels(for: .openRouter), [])
    }
}
