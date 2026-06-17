import Foundation
@testable import VoiceInkCore

final class AIProviderCatalogTests: XCTestCase {
    func testMacOSAIEnhancementProviderIdentityIsShared() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.allCases.map(\.rawValue),
            [
                "Cerebras",
                "Groq",
                "Gemini",
                "Anthropic",
                "OpenAI",
                "OpenRouter",
                "Mistral",
                "ElevenLabs",
                "Deepgram",
                "Soniox",
                "Speechmatics",
                "AssemblyAI",
                "Ollama",
                "Local CLI",
                "Custom"
            ]
        )
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind(rawValue: "OpenRouter"), .openRouter)
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind(rawValue: "Local CLI"), .localCLI)
    }

    func testMacOSAIEnhancementProviderMapsToSharedModelProvider() {
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.anthropic.aiModelProvider, .anthropic)
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.cerebras.aiModelProvider, .cerebras)
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.deepgram.aiModelProvider, .deepgram)
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.openRouter.aiModelProvider, .openRouter)
        XCTAssertNil(VoiceInkAIEnhancementProviderKind.ollama.aiModelProvider)
        XCTAssertNil(VoiceInkAIEnhancementProviderKind.localCLI.aiModelProvider)
        XCTAssertNil(VoiceInkAIEnhancementProviderKind.custom.aiModelProvider)
    }

    func testMacOSAIEnhancementProviderAPIKeyRequirementIsShared() {
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.ollama.requiresUserAPIKey)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.localCLI.requiresUserAPIKey)
        XCTAssertTrue(VoiceInkAIEnhancementProviderKind.custom.requiresUserAPIKey)
        XCTAssertTrue(VoiceInkAIEnhancementProviderKind.groq.requiresUserAPIKey)
        XCTAssertTrue(VoiceInkAIEnhancementProviderKind.anthropic.requiresUserAPIKey)
    }

    func testMacOSAIEnhancementRequestURLsAreShared() {
        let expectedURLs: [VoiceInkAIModelProvider: String?] = [
            .anthropic: "https://api.anthropic.com/v1/messages",
            .assemblyAI: "https://api.assemblyai.com/v2/transcript",
            .cerebras: "https://api.cerebras.ai/v1/chat/completions",
            .deepgram: nil,
            .elevenLabs: "https://api.elevenlabs.io/v1/speech-to-text",
            .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/v1/chat/completions",
            .groq: "https://api.groq.com/openai/v1/chat/completions",
            .mistral: "https://api.mistral.ai/v1/chat/completions",
            .openAI: "https://api.openai.com/v1/chat/completions",
            .openRouter: "https://openrouter.ai/api/v1/chat/completions",
            .soniox: "https://api.soniox.com/v1",
            .speechmatics: "https://asr.api.speechmatics.com/v2"
        ]

        XCTAssertEqual(VoiceInkAIModelProvider.allCases.count, expectedURLs.count)

        for (provider, expectedURL) in expectedURLs {
            XCTAssertEqual(provider.postProcessingRequestURL?.absoluteString, expectedURL)
        }
    }

    func testMacOSAIEnhancementConsoleURLsAreShared() {
        let expectedURLs: [VoiceInkAIModelProvider: String] = [
            .anthropic: "https://console.anthropic.com/settings/keys",
            .assemblyAI: "https://www.assemblyai.com/dashboard/api-keys",
            .cerebras: "https://cloud.cerebras.ai/",
            .deepgram: "https://console.deepgram.com/api-keys",
            .elevenLabs: "https://elevenlabs.io/speech-synthesis",
            .gemini: "https://makersuite.google.com/app/apikey",
            .groq: "https://console.groq.com/keys",
            .mistral: "https://console.mistral.ai/api-keys",
            .openAI: "https://platform.openai.com/api-keys",
            .openRouter: "https://openrouter.ai/keys",
            .soniox: "https://console.soniox.com/",
            .speechmatics: "https://portal.speechmatics.com/manage-access/"
        ]

        XCTAssertEqual(VoiceInkAIModelProvider.allCases.count, expectedURLs.count)

        for (provider, expectedURL) in expectedURLs {
            XCTAssertEqual(provider.apiKeyConsoleURL.absoluteString, expectedURL)
        }
    }
}
