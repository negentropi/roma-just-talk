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

    func testMacOSAIEnhancementProviderStoredValueParsingIsShared() {
        for provider in VoiceInkAIEnhancementProviderKind.allCases {
            XCTAssertEqual(VoiceInkAIEnhancementProviderKind(storedValue: provider.rawValue), provider)
        }

        XCTAssertEqual(VoiceInkAIEnhancementProviderKind(storedValue: "GROQ"), .groq)
        XCTAssertNil(VoiceInkAIEnhancementProviderKind(storedValue: "MissingProvider"))
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

    func testMacOSAIEnhancementSelectableTextProvidersAreShared() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.selectableTextEnhancementProviders,
            [
                .cerebras,
                .groq,
                .gemini,
                .anthropic,
                .openAI,
                .openRouter,
                .mistral,
                .ollama,
                .localCLI,
                .custom
            ]
        )
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.assemblyAI.isSelectableForTextEnhancement)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.deepgram.isSelectableForTextEnhancement)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.elevenLabs.isSelectableForTextEnhancement)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.soniox.isSelectableForTextEnhancement)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.speechmatics.isSelectableForTextEnhancement)
    }

    func testMacOSAIEnhancementConnectedProvidersUseSharedPolicy() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.connectedTextEnhancementProviders(
                hasUserAPIKey: { _ in true },
                isOllamaConnected: true,
                isLocalCLIConfigured: true
            ),
            VoiceInkAIEnhancementProviderKind.selectableTextEnhancementProviders
        )

        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.connectedTextEnhancementProviders(
                hasUserAPIKey: { [.groq, .custom].contains($0) },
                isOllamaConnected: false,
                isLocalCLIConfigured: false
            ),
            [.groq, .custom]
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.connectedTextEnhancementProviders(
                hasUserAPIKey: { _ in false },
                isOllamaConnected: true,
                isLocalCLIConfigured: false
            ),
            [.ollama]
        )
        XCTAssertTrue(
            VoiceInkAIEnhancementProviderKind.localCLI.isConnectedForTextEnhancement(
                hasUserAPIKey: { false },
                isOllamaConnected: false,
                isLocalCLIConfigured: true
            )
        )
        XCTAssertFalse(
            VoiceInkAIEnhancementProviderKind.assemblyAI.isConnectedForTextEnhancement(
                hasUserAPIKey: { true },
                isOllamaConnected: true,
                isLocalCLIConfigured: true
            )
        )
    }

    func testMacOSAIEnhancementModelSelectionPreservesAvailableSelections() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.groq.selectedTextEnhancementModel(
                "llama-3.3-70b-versatile",
                availableModels: VoiceInkAIModelCatalog.availableModels(for: .groq),
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .groq)
            ),
            "llama-3.3-70b-versatile"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.openRouter.selectedTextEnhancementModel(
                "anthropic/claude-sonnet",
                availableModels: ["anthropic/claude-sonnet"],
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter)
            ),
            "anthropic/claude-sonnet"
        )
    }

    func testMacOSAIEnhancementModelSelectionFallsBackForBlankAndUnavailableSelections() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.groq.selectedTextEnhancementModel(
                "",
                availableModels: VoiceInkAIModelCatalog.availableModels(for: .groq),
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .groq)
            ),
            VoiceInkAIModelCatalog.defaultModel(for: .groq)
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.groq.selectedTextEnhancementModel(
                "stale-model",
                availableModels: VoiceInkAIModelCatalog.availableModels(for: .groq),
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .groq)
            ),
            VoiceInkAIModelCatalog.defaultModel(for: .groq)
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.localCLI.selectedTextEnhancementModel(
                "custom-cli-model",
                availableModels: [],
                defaultModel: "local-cli"
            ),
            "local-cli"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.custom.selectedTextEnhancementModel(
                "saved-custom-selection",
                availableModels: [],
                defaultModel: "custom-model"
            ),
            "custom-model"
        )
    }

    func testMacOSAIEnhancementModelSelectionKeepsUnavailableOllamaModel() {
        XCTAssertTrue(VoiceInkAIEnhancementProviderKind.ollama.preservesUnavailableSelectedTextEnhancementModel)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.groq.preservesUnavailableSelectedTextEnhancementModel)
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.ollama.selectedTextEnhancementModel(
                "local-llama",
                availableModels: [],
                defaultModel: "mistral"
            ),
            "local-llama"
        )
    }

    func testMacOSAIEnhancementProviderVerificationRoutesAreShared() {
        let expectedRoutes: [VoiceInkAIEnhancementProviderKind: VoiceInkAIEnhancementAPIKeyVerificationRoute?] = [
            .anthropic: .anthropicMessages,
            .assemblyAI: .sharedProvider(.assemblyAI),
            .cerebras: .openAICompatibleModels,
            .custom: .openAICompatibleModels,
            .deepgram: .sharedProvider(.deepgram),
            .elevenLabs: .sharedProvider(.elevenLabs),
            .gemini: .sharedProvider(.gemini),
            .groq: .openAICompatibleModels,
            .localCLI: nil,
            .mistral: .sharedProvider(.mistral),
            .ollama: nil,
            .openAI: .openAICompatibleModels,
            .openRouter: .openRouterModels,
            .soniox: .sharedProvider(.soniox),
            .speechmatics: .sharedProvider(.speechmatics)
        ]

        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.allCases.count, expectedRoutes.count)

        for (provider, route) in expectedRoutes {
            XCTAssertEqual(provider.apiKeyVerificationRoute, route)
        }
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
