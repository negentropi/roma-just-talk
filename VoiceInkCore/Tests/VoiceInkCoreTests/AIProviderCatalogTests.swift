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

    func testMacOSAIEnhancementCredentialStateIsShared() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.groq.textEnhancementCredentialState(
                savedAPIKey: "saved-groq-key",
                isLocalCLIConfigured: false
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "saved-groq-key", isAPIKeyValid: true)
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.groq.textEnhancementCredentialState(
                savedAPIKey: nil,
                isLocalCLIConfigured: true
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.localCLI.textEnhancementCredentialState(
                savedAPIKey: "ignored-key",
                isLocalCLIConfigured: true
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: true)
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.localCLI.textEnhancementCredentialState(
                savedAPIKey: nil,
                isLocalCLIConfigured: false
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.ollama.textEnhancementCredentialState(
                savedAPIKey: nil,
                isLocalCLIConfigured: false
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: true)
        )
    }

    func testProviderAPIKeyVerificationProgressPresentsSharedFeedback() {
        XCTAssertTrue(VoiceInkProviderAPIKeyVerificationProgress.verifying.isVerifying)
        XCTAssertFalse(VoiceInkProviderAPIKeyVerificationProgress.idle.isVerifying)
        XCTAssertTrue(VoiceInkProviderAPIKeyVerificationProgress.success.isSuccess)

        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.verifying.macOSVerifyButtonTitle,
            "Verifying..."
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.success.macOSVerifyButtonTitle,
            "Verify"
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.success.macOSVerifyButtonSystemImageName,
            "checkmark"
        )

        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.success.macOSInlineFeedback,
            VoiceInkProviderAPIKeyVerificationFeedback(
                text: "API key verified successfully!",
                tone: .success
            )
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.failure(message: nil).macOSInlineFeedback,
            VoiceInkProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                tone: .failure
            )
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.unsupportedProviderFailure.macOSInlineFeedback?.text,
            "Unsupported provider"
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback,
            VoiceInkProviderAPIKeyVerificationFeedback(
                text: "Key verified",
                systemImageName: "checkmark.seal.fill",
                tone: .success
            )
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback.effectiveSystemImageName,
            "checkmark.seal.fill"
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationFeedback(text: "FYI", tone: .success).effectiveSystemImageName,
            "info.circle"
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.success.iOSResultFeedback,
            VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyVerificationProgress.failure(message: "bad").iOSResultFeedback,
            VoiceInkProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                systemImageName: "xmark.seal",
                tone: .failure
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyDraftUsesSharedBlankPolicy() {
        let draft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " \n\t "
        )

        XCTAssertFalse(draft.hasEnteredKey)
        XCTAssertFalse(draft.canVerify)
        XCTAssertNil(draft.keyToSaveAfterSuccessfulVerification)
        XCTAssertNil(draft.resolvedVerificationCandidate(environment: [:]))
    }

    func testMacOSAIEnhancementAPIKeyDraftResolvesEnvironmentReferences() {
        let draft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " $GROQ_API_KEY "
        )

        XCTAssertTrue(draft.hasEnteredKey)
        XCTAssertTrue(draft.canVerify)
        XCTAssertEqual(draft.keyToSaveAfterSuccessfulVerification, "$GROQ_API_KEY")
        XCTAssertEqual(
            draft.resolvedVerificationCandidate(environment: ["GROQ_API_KEY": "resolved-key"]),
            "resolved-key"
        )
    }

    func testMacOSAIEnhancementAPIKeyDraftFallsBackToStoredRuntimeKey() {
        let draft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " \n\t ",
            storedRuntimeKey: "stored-key"
        )

        XCTAssertFalse(draft.hasEnteredKey)
        XCTAssertTrue(draft.canVerify)
        XCTAssertNil(draft.keyToSaveAfterSuccessfulVerification)
        XCTAssertEqual(draft.resolvedVerificationCandidate(environment: [:]), "stored-key")
    }

    func testMacOSAIEnhancementAPIKeyDraftRejectsNoKeyProviders() {
        let draft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .ollama,
            enteredKey: "entered-key",
            storedRuntimeKey: "stored-key"
        )

        XCTAssertTrue(draft.hasEnteredKey)
        XCTAssertFalse(draft.canVerify)
        XCTAssertNil(draft.keyToSaveAfterSuccessfulVerification)
        XCTAssertNil(draft.resolvedVerificationCandidate(environment: [:]))
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanSavesEnteredReferenceAndAppliesResolvedRuntimeKey() {
        let draft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " $GROQ_API_KEY "
        )

        XCTAssertEqual(
            draft.verificationApplicationPlan(
                for: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil),
                resolvedRuntimeKey: "resolved-key"
            ),
            VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: true,
                runtimeAPIKey: "resolved-key",
                keyToSave: "$GROQ_API_KEY",
                errorMessage: nil
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanPropagatesFailureWithoutSaving() {
        let draft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: "bad-key"
        )

        XCTAssertEqual(
            draft.verificationApplicationPlan(
                for: VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "invalid"),
                resolvedRuntimeKey: "bad-key"
            ),
            VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: false,
                runtimeAPIKey: nil,
                keyToSave: nil,
                errorMessage: "invalid"
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanNoOpsForNoKeyProviders() {
        let draft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .ollama,
            enteredKey: "ignored-key"
        )

        XCTAssertEqual(
            draft.verificationApplicationPlan(
                for: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil),
                resolvedRuntimeKey: "ignored-key"
            ),
            VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: true,
                runtimeAPIKey: nil,
                keyToSave: nil,
                errorMessage: nil
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyFormStateBuildsDraftForSelectedProvider() {
        let state = VoiceInkAIEnhancementAPIKeyFormState(enteredKey: " $GROQ_API_KEY ")
        let draft = state.draft(for: .groq)

        XCTAssertTrue(draft.hasEnteredKey)
        XCTAssertTrue(draft.canVerify)
        XCTAssertEqual(draft.keyToSaveAfterSuccessfulVerification, "$GROQ_API_KEY")
        XCTAssertEqual(
            draft.resolvedVerificationCandidate(environment: ["GROQ_API_KEY": "resolved-key"]),
            "resolved-key"
        )
    }

    func testMacOSAIEnhancementAPIKeyFormStateTracksVerificationLifecycle() {
        let state = VoiceInkAIEnhancementAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .failure(message: "bad request")
        )

        let verifyingState = state.verifying()
        let completedState = verifyingState.completedVerification()

        XCTAssertEqual(verifyingState.enteredKey, "entered-key")
        XCTAssertEqual(verifyingState.verificationProgress, .verifying)
        XCTAssertTrue(verifyingState.isVerifying)
        XCTAssertEqual(completedState.enteredKey, "")
        XCTAssertEqual(completedState.verificationProgress, .idle)
        XCTAssertFalse(completedState.isVerifying)
    }

    func testMacOSAIEnhancementAPIKeyFormStateBuildsSharedFailureAlertCopy() {
        let state = VoiceInkAIEnhancementAPIKeyFormState(enteredKey: "bad-key")

        XCTAssertEqual(
            state.verificationFailureAlertMessage(
                for: VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: "invalid key"
                )
            ),
            "invalid key"
        )
        XCTAssertEqual(
            state.verificationFailureAlertMessage(
                for: VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: nil
                )
            ),
            "Verification failed"
        )
    }

    func testMacOSAIEnhancementAPIKeyFailureMessagesAreShared() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.missingVerificationCandidateMessage,
            "Environment variable is missing or empty"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage,
            "Invalid or missing base URL configuration"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.localCLI.unsupportedAPIKeyVerificationMessage,
            "Local CLI does not support API key verification."
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.custom.invalidTextEnhancementRequestURLMessage,
            "Custom has an invalid API endpoint URL. Please update it in AI settings."
        )
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

    func testMacOSAIEnhancementConnectionStatusPresentationIsShared() {
        let presentation = VoiceInkAIEnhancementProviderSettingsPresentation.macOS

        XCTAssertEqual(presentation.connectedText, "Connected")
        XCTAssertEqual(presentation.disconnectedText, "Disconnected")
        XCTAssertEqual(
            presentation.connectionStatus(
                surface: .apiKey,
                isAPIKeyValid: true,
                isCheckingOllama: false,
                hasOllamaModels: false
            ),
            .status(text: "Connected", tone: .connected)
        )
        XCTAssertNil(
            presentation.connectionStatus(
                surface: .apiKey,
                isAPIKeyValid: false,
                isCheckingOllama: false,
                hasOllamaModels: false
            )
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                surface: .ollama,
                isAPIKeyValid: false,
                isCheckingOllama: true,
                hasOllamaModels: false
            ),
            .checking
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                surface: .ollama,
                isAPIKeyValid: false,
                isCheckingOllama: false,
                hasOllamaModels: true
            ),
            .status(text: "Connected", tone: .connected)
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                surface: .ollama,
                isAPIKeyValid: false,
                isCheckingOllama: false,
                hasOllamaModels: false
            ),
            .status(text: "Disconnected", tone: .disconnected)
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                surface: .localCLI,
                isAPIKeyValid: true,
                isCheckingOllama: false,
                hasOllamaModels: false
            ),
            .status(text: "Connected", tone: .connected)
        )
    }

    func testMacOSAIEnhancementSettingsChromeAndOllamaPresentationIsShared() {
        let presentation = VoiceInkAIEnhancementProviderSettingsPresentation.macOS

        XCTAssertEqual(presentation.sectionTitle, "AI Provider Integration")
        XCTAssertEqual(presentation.providerPickerTitle, "Provider")
        XCTAssertEqual(presentation.modelPickerTitle, "Model")
        XCTAssertEqual(presentation.noModelsLoadedText, "No models loaded")
        XCTAssertEqual(presentation.refreshButtonTitle, "Refresh")
        XCTAssertEqual(presentation.defaultAPIKeyRemoveButtonTitle, "Remove")
        XCTAssertEqual(presentation.getAPIKeyButtonTitle, "Get API Key")
        XCTAssertEqual(presentation.errorAlertTitle, "Error")
        XCTAssertEqual(presentation.errorAlertDismissButtonTitle, "OK")
        XCTAssertEqual(presentation.ollamaBaseURLFieldTitle, "Base URL")
        XCTAssertEqual(presentation.ollamaSaveButtonTitle, "Save")
        XCTAssertEqual(presentation.ollamaEditButtonTitle, "Edit")
        XCTAssertEqual(presentation.ollamaResetButtonHelp, "Reset to default")
        XCTAssertEqual(
            presentation.ollamaConnectionFailureMessage,
            "Could not connect to Ollama. Please check if Ollama is running and the base URL is correct."
        )
        XCTAssertEqual(
            presentation.ollamaServerText(baseURL: "http://localhost:11434"),
            "Server: http://localhost:11434"
        )
    }

    func testMacOSCustomProviderSettingsPresentationAndSubmitPolicyAreShared() {
        let presentation = VoiceInkAIEnhancementProviderSettingsPresentation.macOS

        XCTAssertEqual(presentation.apiKeyFieldTitle, "API Key")
        XCTAssertEqual(presentation.verifyAndSaveButtonTitle, "Verify and Save")
        XCTAssertEqual(presentation.customProviderBaseURLFieldTitle, "API Endpoint URL")
        XCTAssertEqual(
            presentation.customProviderBaseURLPlaceholder,
            "e.g. https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(presentation.customProviderModelFieldTitle, "Model Name")
        XCTAssertEqual(
            presentation.customProviderModelPlaceholder,
            "e.g. gemini-3.1-pro-preview, gpt-5.5"
        )
        XCTAssertEqual(presentation.customProviderAPIKeySetText, "API Key Set")
        XCTAssertEqual(presentation.customProviderRemoveKeyButtonTitle, "Remove Key")

        XCTAssertTrue(
            presentation.canSubmitCustomProvider(
                baseURL: "https://api.example.test/v1/chat/completions",
                modelName: "custom-model",
                hasDraftAPIKey: true
            )
        )
        XCTAssertTrue(
            presentation.canSubmitCustomProvider(
                baseURL: " ",
                modelName: " ",
                hasDraftAPIKey: true
            )
        )
        XCTAssertFalse(
            presentation.canSubmitCustomProvider(
                baseURL: "",
                modelName: "custom-model",
                hasDraftAPIKey: true
            )
        )
        XCTAssertFalse(
            presentation.canSubmitCustomProvider(
                baseURL: "https://api.example.test/v1/chat/completions",
                modelName: "",
                hasDraftAPIKey: true
            )
        )
        XCTAssertFalse(
            presentation.canSubmitCustomProvider(
                baseURL: "https://api.example.test/v1/chat/completions",
                modelName: "custom-model",
                hasDraftAPIKey: false
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

    func testMacOSAIEnhancementDefaultTextEnhancementModelsAreShared() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.groq.defaultTextEnhancementModel(from: defaults),
                VoiceInkAIModelCatalog.defaultModel(for: .groq)
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.openRouter.defaultTextEnhancementModel(from: defaults),
                VoiceInkAIModelCatalog.defaultModel(for: .openRouter)
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.ollama.defaultTextEnhancementModel(from: defaults),
                VoiceInkAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback,
                "llama2"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.localCLI.defaultTextEnhancementModel(from: defaults),
                VoiceInkAIEnhancementProviderKind.localCLITextEnhancementModel
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.custom.defaultTextEnhancementModel(from: defaults),
                ""
            )

            VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel("llama3", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderModel("custom-model", to: defaults)

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.ollama.defaultTextEnhancementModel(from: defaults),
                "llama3"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.custom.defaultTextEnhancementModel(from: defaults),
                "custom-model"
            )
        }
    }

    func testMacOSAIEnhancementStaticTextEnhancementModelsAreShared() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.groq.staticTextEnhancementModels,
            VoiceInkAIModelCatalog.availableModels(for: .groq)
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.openRouter.staticTextEnhancementModels,
            VoiceInkAIModelCatalog.availableModels(for: .openRouter)
        )
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.ollama.staticTextEnhancementModels, [])
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.localCLI.staticTextEnhancementModels, [])
        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.custom.staticTextEnhancementModels, [])
    }

    func testMacOSAIEnhancementAvailableModelSourcesAreShared() {
        let ollamaModels = ["llama3", "mistral"]
        let openRouterModels = ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"]

        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.ollama.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            ollamaModels
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.openRouter.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            openRouterModels
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.groq.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            VoiceInkAIModelCatalog.availableModels(for: .groq)
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.localCLI.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            []
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.custom.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            []
        )
    }

    func testMacOSAIEnhancementModelCatalogSourcePolicyIsShared() {
        let expectedSources: [VoiceInkAIEnhancementProviderKind: VoiceInkAIEnhancementModelCatalogSource] = [
            .anthropic: .staticModels,
            .assemblyAI: .staticModels,
            .cerebras: .staticModels,
            .custom: .none,
            .deepgram: .staticModels,
            .elevenLabs: .staticModels,
            .gemini: .staticModels,
            .groq: .staticModels,
            .localCLI: .none,
            .mistral: .staticModels,
            .ollama: .ollamaRuntime,
            .openAI: .staticModels,
            .openRouter: .openRouterRemote,
            .soniox: .staticModels,
            .speechmatics: .staticModels
        ]

        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.allCases.count, expectedSources.count)

        for (provider, source) in expectedSources {
            XCTAssertEqual(provider.textEnhancementModelCatalogSource, source)
        }
    }

    func testMacOSAIEnhancementUserInitiatedModelRefreshPolicyIsShared() {
        XCTAssertTrue(VoiceInkAIEnhancementProviderKind.openRouter.supportsUserInitiatedTextEnhancementModelRefresh)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.ollama.supportsUserInitiatedTextEnhancementModelRefresh)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.groq.supportsUserInitiatedTextEnhancementModelRefresh)
        XCTAssertFalse(VoiceInkAIEnhancementProviderKind.custom.supportsUserInitiatedTextEnhancementModelRefresh)
    }

    func testMacOSAIEnhancementSettingsSurfacesAreShared() {
        let expectedSurfaces: [VoiceInkAIEnhancementProviderKind: VoiceInkAIEnhancementSettingsSurface] = [
            .anthropic: .apiKey,
            .assemblyAI: .apiKey,
            .cerebras: .apiKey,
            .custom: .custom,
            .deepgram: .apiKey,
            .elevenLabs: .apiKey,
            .gemini: .apiKey,
            .groq: .apiKey,
            .localCLI: .localCLI,
            .mistral: .apiKey,
            .ollama: .ollama,
            .openAI: .apiKey,
            .openRouter: .apiKey,
            .soniox: .apiKey,
            .speechmatics: .apiKey
        ]

        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.allCases.count, expectedSurfaces.count)

        for (provider, surface) in expectedSurfaces {
            XCTAssertEqual(provider.textEnhancementSettingsSurface, surface)
        }
    }

    func testMacOSAIEnhancementRequestURLSelectionIsShared() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.groq.textEnhancementRequestURLString(from: defaults),
                VoiceInkAIModelProvider.groq.postProcessingRequestURL?.absoluteString
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.openRouter.textEnhancementRequestURLString(from: defaults),
                VoiceInkAIModelProvider.openRouter.postProcessingRequestURL?.absoluteString
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.ollama.textEnhancementRequestURLString(from: defaults),
                VoiceInkPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.localCLI.textEnhancementRequestURLString(from: defaults),
                ""
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.custom.textEnhancementRequestURLString(from: defaults),
                ""
            )

            VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL("http://example.local:11434", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL("https://api.example.com", to: defaults)

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.ollama.textEnhancementRequestURLString(from: defaults),
                "http://example.local:11434"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.custom.textEnhancementRequestURLString(from: defaults),
                "https://api.example.com"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderKind.custom.textEnhancementRequestURL(from: defaults)?.absoluteString,
                "https://api.example.com"
            )

            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL("http://[::1", to: defaults)

            XCTAssertNil(VoiceInkAIEnhancementProviderKind.custom.textEnhancementRequestURL(from: defaults))
            XCTAssertNil(VoiceInkAIEnhancementProviderKind.localCLI.textEnhancementRequestURL(from: defaults))
        }
    }

    func testMacOSAIEnhancementRefreshModelSelectionRepairIsShared() {
        let openRouterModels = [
            "anthropic/claude-3.5-sonnet",
            "openai/gpt-4o"
        ]
        let ollamaModels = [
            "llama3",
            "mistral"
        ]

        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.openRouter.textEnhancementModelToSelectAfterRefresh(
                currentModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter),
                refreshedModels: openRouterModels,
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter)
            ),
            "anthropic/claude-3.5-sonnet"
        )
        XCTAssertNil(
            VoiceInkAIEnhancementProviderKind.openRouter.textEnhancementModelToSelectAfterRefresh(
                currentModel: "custom/openrouter-model",
                refreshedModels: openRouterModels,
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter)
            )
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.ollama.textEnhancementModelToSelectAfterRefresh(
                currentModel: "missing-local-model",
                refreshedModels: ollamaModels,
                defaultModel: VoiceInkAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
            ),
            "llama3"
        )
        XCTAssertNil(
            VoiceInkAIEnhancementProviderKind.ollama.textEnhancementModelToSelectAfterRefresh(
                currentModel: "mistral",
                refreshedModels: ollamaModels,
                defaultModel: VoiceInkAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
            )
        )
        XCTAssertNil(
            VoiceInkAIEnhancementProviderKind.groq.textEnhancementModelToSelectAfterRefresh(
                currentModel: VoiceInkAIModelCatalog.defaultModel(for: .groq),
                refreshedModels: openRouterModels,
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .groq)
            )
        )
        XCTAssertNil(
            VoiceInkAIEnhancementProviderKind.openRouter.textEnhancementModelToSelectAfterRefresh(
                currentModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter),
                refreshedModels: [],
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter)
            )
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

    func testMacOSAIEnhancementExecutionRoutesAreShared() {
        let expectedRoutes: [VoiceInkAIEnhancementProviderKind: VoiceInkAIEnhancementExecutionRoute] = [
            .anthropic: .anthropicMessages,
            .assemblyAI: .openAICompatibleChatCompletions,
            .cerebras: .openAICompatibleChatCompletions,
            .custom: .openAICompatibleChatCompletions,
            .deepgram: .openAICompatibleChatCompletions,
            .elevenLabs: .openAICompatibleChatCompletions,
            .gemini: .openAICompatibleChatCompletions,
            .groq: .openAICompatibleChatCompletions,
            .localCLI: .localCLI,
            .mistral: .openAICompatibleChatCompletions,
            .ollama: .ollama,
            .openAI: .openAICompatibleChatCompletions,
            .openRouter: .openAICompatibleChatCompletions,
            .soniox: .openAICompatibleChatCompletions,
            .speechmatics: .openAICompatibleChatCompletions
        ]

        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.allCases.count, expectedRoutes.count)

        for (provider, route) in expectedRoutes {
            XCTAssertEqual(provider.textEnhancementExecutionRoute, route)
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

    func testAIEnhancementProvidersExposeOptionalConsoleURLs() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.groq.apiKeyConsoleURL?.absoluteString,
            "https://console.groq.com/keys"
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.openRouter.apiKeyConsoleURL?.absoluteString,
            "https://openrouter.ai/keys"
        )
        XCTAssertNil(VoiceInkAIEnhancementProviderKind.custom.apiKeyConsoleURL)
        XCTAssertNil(VoiceInkAIEnhancementProviderKind.ollama.apiKeyConsoleURL)
        XCTAssertNil(VoiceInkAIEnhancementProviderKind.localCLI.apiKeyConsoleURL)
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.AIProviderCatalogTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        run(defaults)
    }
}
