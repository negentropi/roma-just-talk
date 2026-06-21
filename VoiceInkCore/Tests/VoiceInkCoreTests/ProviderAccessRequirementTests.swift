import Foundation
@testable import VoiceInkCore

final class ProviderAccessRequirementTests: XCTestCase {
    func testUserAPIKeyProvidersExposeDerivedCredentialMetadata() {
        XCTAssertEqual(
            VoiceInkProviderKind.userAPIKeyProviders,
            [.groq, .openAI, .deepgram, .cerebras, .gemini, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai]
        )

        let expected: [VoiceInkProviderKind: (account: String, verificationKey: String, transport: VoiceInkAPIKeyVerificationTransport)] = [
            .groq: (VoiceInkProviderAPIKeyAccount.groq, "groqKeyVerified", .openAICompatibleModels),
            .openAI: (VoiceInkProviderAPIKeyAccount.openAI, "openAIKeyVerified", .openAICompatibleModels),
            .deepgram: (VoiceInkProviderAPIKeyAccount.deepgram, "deepgramKeyVerified", .deepgramProjects),
            .cerebras: (VoiceInkProviderAPIKeyAccount.cerebras, "cerebrasKeyVerified", .openAICompatibleModels),
            .gemini: (VoiceInkProviderAPIKeyAccount.gemini, "geminiKeyVerified", .geminiModels),
            .mistral: (VoiceInkProviderAPIKeyAccount.mistral, "mistralKeyVerified", .mistralModels),
            .elevenLabs: (VoiceInkProviderAPIKeyAccount.elevenLabs, "elevenLabsKeyVerified", .elevenLabsUser),
            .soniox: (VoiceInkProviderAPIKeyAccount.soniox, "sonioxKeyVerified", .sonioxFiles),
            .speechmatics: (VoiceInkProviderAPIKeyAccount.speechmatics, "speechmaticsKeyVerified", .speechmaticsJobs),
            .assemblyAI: (VoiceInkProviderAPIKeyAccount.assemblyAI, "assemblyAIKeyVerified", .assemblyAITranscripts),
            .xai: (VoiceInkProviderAPIKeyAccount.xAI, "xaiKeyVerified", .xaiAPIKey)
        ]

        for (provider, policy) in expected {
            guard case let .userAPIKey(account, verificationStateKey, verificationTransport) = provider.accessRequirement else {
                XCTFail("\(provider) should require a user API key")
                continue
            }

            XCTAssertTrue(provider.requiresUserAPIKey)
            XCTAssertEqual(account, policy.account)
            XCTAssertEqual(verificationStateKey, policy.verificationKey)
            XCTAssertEqual(verificationTransport, policy.transport)
            XCTAssertEqual(provider.apiKeyAccount, policy.account)
            XCTAssertEqual(provider.apiKeyVerificationStateKey, policy.verificationKey)
            XCTAssertEqual(provider.apiKeyVerificationTransport, policy.transport)
            XCTAssertTrue(provider.canVerifyAPIKey)
        }
    }

    func testProviderEnvironmentFallbacksPreserveMacOSPolicy() {
        XCTAssertEqual(
            VoiceInkProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "ElevenLabs"),
            "ELEVENLABS_API_KEY"
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "elevenlabs"),
            "ELEVENLABS_API_KEY"
        )
        XCTAssertNil(VoiceInkProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "Groq"))
    }

    func testCustomModelAccountIdentifierPreservesMacOSKeychainAccountShape() {
        let id = UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!

        XCTAssertEqual(
            VoiceInkProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: id),
            "customModel_E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE_APIKey"
        )
    }

    func testNonUserKeyProvidersKeepTheirAccessPolicy() {
        guard case .localWhisperModel = VoiceInkProviderKind.localWhisper.accessRequirement else {
            return XCTFail("Local Whisper should use local model availability")
        }
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.requiresUserAPIKey)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyAccount)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyVerificationStateKey)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.apiKeyVerificationTransport)
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.canVerifyAPIKey)

        guard case .bundledService = VoiceInkProviderKind.voiceInk.accessRequirement else {
            return XCTFail("VoiceInk should use bundled service access")
        }
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.requiresUserAPIKey)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyAccount)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyVerificationStateKey)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyVerificationTransport)
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.canVerifyAPIKey)
    }

    func testRuntimeAPIKeyFollowsProviderAccessPolicy() {
        XCTAssertEqual(VoiceInkProviderKind.groq.runtimeAPIKey(userAPIKey: "groq-key"), "groq-key")
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.runtimeAPIKey(userAPIKey: ""), "local")
        XCTAssertEqual(VoiceInkProviderKind.voiceInk.runtimeAPIKey(userAPIKey: "ignored"), "")
    }

    func testProviderCredentialRejectsBlankKeysWithoutNormalizingUsableKeys() {
        XCTAssertNil(VoiceInkProviderCredential.nonBlank(nil))
        XCTAssertNil(VoiceInkProviderCredential.nonBlank(""))
        XCTAssertNil(VoiceInkProviderCredential.nonBlank(" \n\t "))
        XCTAssertEqual(VoiceInkProviderCredential.nonBlank(" key-with-space "), " key-with-space ")
    }

    func testProviderAPIKeyDraftUsesTrimmedEnteredKeyBeforeStoredRuntimeKey() {
        let draft = VoiceInkProviderAPIKeyDraft(
            enteredKey: " entered-key \n",
            storedRuntimeKey: "stored-key"
        )

        XCTAssertTrue(draft.hasEnteredKey)
        XCTAssertTrue(draft.canVerify)
        XCTAssertEqual(draft.verificationCandidate, "entered-key")
        XCTAssertEqual(draft.keyToSaveAfterSuccessfulVerification, "entered-key")
    }

    func testProviderAPIKeyDraftFallsBackToStoredRuntimeKeyForBlankDraft() {
        let draft = VoiceInkProviderAPIKeyDraft(
            enteredKey: " \n\t ",
            storedRuntimeKey: " stored-runtime-key "
        )

        XCTAssertFalse(draft.hasEnteredKey)
        XCTAssertTrue(draft.canVerify)
        XCTAssertEqual(draft.verificationCandidate, " stored-runtime-key ")
        XCTAssertNil(draft.keyToSaveAfterSuccessfulVerification)
    }

    func testProviderAPIKeyDraftRejectsBlankDraftAndBlankStoredRuntimeKey() {
        let draft = VoiceInkProviderAPIKeyDraft(
            enteredKey: " \n\t ",
            storedRuntimeKey: "\n"
        )

        XCTAssertFalse(draft.hasEnteredKey)
        XCTAssertFalse(draft.canVerify)
        XCTAssertNil(draft.verificationCandidate)
        XCTAssertNil(draft.keyToSaveAfterSuccessfulVerification)
    }

    func testProviderAPIKeyVerificationApplicationPlanSavesEnteredKeyOnSuccess() {
        let draft = VoiceInkProviderAPIKeyDraft(
            enteredKey: " entered-key \n",
            storedRuntimeKey: "stored-key"
        )

        let plan = draft.verificationApplicationPlan(for: VoiceInkAPIKeyVerificationResult(
            isValid: true,
            errorMessage: nil
        ))

        XCTAssertEqual(plan.progress, .success)
        XCTAssertEqual(plan.keyToSave, "entered-key")
        XCTAssertTrue(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyVerificationApplicationPlanKeepsStoredKeyOnSuccess() {
        let draft = VoiceInkProviderAPIKeyDraft(
            enteredKey: " \n\t ",
            storedRuntimeKey: "stored-key"
        )

        let plan = draft.verificationApplicationPlan(for: VoiceInkAPIKeyVerificationResult(
            isValid: true,
            errorMessage: nil
        ))

        XCTAssertEqual(plan.progress, .success)
        XCTAssertNil(plan.keyToSave)
        XCTAssertTrue(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyVerificationApplicationPlanPreservesFailureMessage() {
        let draft = VoiceInkProviderAPIKeyDraft(
            enteredKey: "bad-key",
            storedRuntimeKey: nil
        )

        let plan = draft.verificationApplicationPlan(for: VoiceInkAPIKeyVerificationResult(
            isValid: false,
            errorMessage: "bad request"
        ))

        XCTAssertEqual(plan.progress, .failure(message: "bad request"))
        XCTAssertNil(plan.keyToSave)
        XCTAssertFalse(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyMissingVerificationCandidatePlanFailsWithoutStorageSideEffects() {
        let plan = VoiceInkProviderAPIKeyDraft.missingVerificationCandidatePlan()

        XCTAssertEqual(plan.progress, .failure(message: nil))
        XCTAssertNil(plan.keyToSave)
        XCTAssertFalse(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyFormPresentationBuildsProviderCopy() {
        let presentation = VoiceInkProviderKind.deepgram.apiKeyFormPresentation

        XCTAssertEqual(presentation.navigationTitle, "Deepgram")
        XCTAssertEqual(presentation.apiKeySectionTitle, "Deepgram API Key")
        XCTAssertEqual(presentation.apiKeyPlaceholder, "Deepgram API Key")
        XCTAssertEqual(presentation.saveButtonTitle, "Save")
        XCTAssertEqual(presentation.saveButtonSystemImageName, "checkmark.circle.fill")
        XCTAssertEqual(presentation.verifyButtonTitle, "Verify")
        XCTAssertEqual(presentation.verifyButtonSystemImageName, "checkmark.seal")
        XCTAssertEqual(presentation.changeButtonTitle, "Change")
        XCTAssertEqual(presentation.consoleSectionTitle, "Get API Key")
        XCTAssertEqual(presentation.consoleLinkTitle, "Deepgram API Console")
        XCTAssertEqual(presentation.consoleLeadingSystemImageName, "link")
        XCTAssertEqual(presentation.consoleTrailingSystemImageName, "arrow.up.right.square")
    }

    func testProviderAPIKeyCardPresentationPreservesMacOSCloudCardCopy() {
        let presentation = VoiceInkProviderAPIKeyCardPresentation(providerDisplayName: "Cartesia")

        XCTAssertEqual(presentation.configureButtonTitle, "Configure")
        XCTAssertEqual(presentation.configureButtonSystemImageName, "gear")
        XCTAssertEqual(presentation.removeAPIKeyButtonTitle, "Remove API Key")
        XCTAssertEqual(presentation.removeAPIKeyButtonSystemImageName, "trash")
        XCTAssertEqual(presentation.configurationSectionTitle, "API Key Configuration")
        XCTAssertEqual(presentation.apiKeyFieldPlaceholder, "Enter your Cartesia API key")
    }

    func testProviderAPIKeyStateResolvesStoredRuntimeKeysAndNonUserProviders() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: " groq-key "],
            verifiedProviders: [.groq]
        )

        XCTAssertEqual(state.storedAPIKey(for: .groq), " groq-key ")
        XCTAssertEqual(state.runtimeAPIKey(for: .groq), "groq-key")
        XCTAssertEqual(state.runtimeAPIKey(for: .localWhisper), "local")
        XCTAssertNil(state.runtimeAPIKey(for: .voiceInk))
    }

    func testProviderAPIKeyStateLoadsStoredKeysForUserKeyProvidersOnly() {
        let state = VoiceInkProviderAPIKeyState.loadingStoredKeys(
            for: [.groq, .localWhisper, .voiceInk, .deepgram],
            verifiedProviders: [.groq, .localWhisper, .voiceInk],
            loadStoredAPIKey: { "\($0.rawValue)-stored" }
        )

        XCTAssertEqual(state.storedAPIKey(for: .groq), "groq-stored")
        XCTAssertEqual(state.storedAPIKey(for: .deepgram), "deepgram-stored")
        XCTAssertEqual(state.storedAPIKey(for: .localWhisper), "")
        XCTAssertEqual(state.storedAPIKey(for: .voiceInk), "")
        XCTAssertTrue(state.isReady(for: .groq, localWhisperModelAvailable: false))
        XCTAssertFalse(state.isReady(for: .deepgram, localWhisperModelAvailable: false))
        XCTAssertTrue(state.isReady(for: .localWhisper, localWhisperModelAvailable: true))
    }

    func testProviderAPIKeyStateReadinessUsesVerificationAndLocalModelState() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )

        XCTAssertTrue(state.isReady(for: .groq, localWhisperModelAvailable: false))
        XCTAssertFalse(state.isReady(for: .deepgram, localWhisperModelAvailable: false))
        XCTAssertTrue(state.isReady(for: .localWhisper, localWhisperModelAvailable: true))
        XCTAssertFalse(state.isReady(for: .localWhisper, localWhisperModelAvailable: false))
        XCTAssertTrue(state.isReady(for: .voiceInk, localWhisperModelAvailable: false))
    }

    func testProviderAPIKeyStateBuildsAvailableProvidersForModelUse() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [
                .groq: "groq-key",
                .deepgram: "deepgram-key",
                .mistral: "mistral-key",
                .elevenLabs: "elevenlabs-key",
                .soniox: "soniox-key",
                .speechmatics: "speechmatics-key",
                .assemblyAI: "assemblyai-key",
                .xai: "xai-key"
            ],
            verifiedProviders: [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai]
        )

        XCTAssertEqual(
            state.availableProviders(for: .transcription, localWhisperModelAvailable: true),
            [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper]
        )
        XCTAssertEqual(
            state.availableProviders(for: .transcription, localWhisperModelAvailable: false),
            [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai]
        )
        XCTAssertEqual(
            state.availableProviders(for: .postProcessing, localWhisperModelAvailable: true),
            [.groq]
        )
    }

    func testProviderAPIKeyStateBuildsListRowPresentation() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )

        XCTAssertEqual(
            state.listRowPresentation(for: .groq, localWhisperModelAvailable: false),
            VoiceInkProviderAPIKeyListRowPresentation(
                title: "Groq",
                statusSystemImageName: "checkmark.seal.fill",
                tone: .verified
            )
        )
        XCTAssertEqual(
            state.listRowPresentation(for: .deepgram, localWhisperModelAvailable: false),
            VoiceInkProviderAPIKeyListRowPresentation(
                title: "Deepgram",
                statusSystemImageName: "exclamationmark.triangle.fill",
                tone: .attention
            )
        )
    }

    func testProviderAPIKeyStateResetVerificationWhenStoredKeyChanges() {
        var state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "old-key"],
            verifiedProviders: [.groq]
        )

        XCTAssertFalse(state.setStoredAPIKey("old-key", for: .groq))
        XCTAssertTrue(state.isReady(for: .groq, localWhisperModelAvailable: false))

        XCTAssertTrue(state.setStoredAPIKey("new-key", for: .groq))
        XCTAssertEqual(state.storedAPIKey(for: .groq), "new-key")
        XCTAssertFalse(state.isReady(for: .groq, localWhisperModelAvailable: false))
    }

    func testProviderAPIKeyStateVerificationIgnoresNonUserKeyProviders() {
        var state = VoiceInkProviderAPIKeyState()

        XCTAssertFalse(state.setVerified(true, for: .localWhisper))
        XCTAssertFalse(state.setStoredAPIKey("ignored", for: .voiceInk))
        XCTAssertEqual(state.storedAPIKey(for: .voiceInk), "")
    }

    func testRuntimeAPIKeyIfAvailableFollowsProviderAccessPolicyAndBlankRules() {
        XCTAssertEqual(VoiceInkProviderKind.groq.runtimeAPIKeyIfAvailable(userAPIKey: "groq-key"), "groq-key")
        XCTAssertNil(VoiceInkProviderKind.groq.runtimeAPIKeyIfAvailable(userAPIKey: " \n "))
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.runtimeAPIKeyIfAvailable(userAPIKey: ""), "local")
        XCTAssertNil(VoiceInkProviderKind.voiceInk.runtimeAPIKeyIfAvailable(userAPIKey: "ignored"))
    }

    func testTranscriptionServiceKindGroupsProvidersByRequiredAdapter() {
        XCTAssertEqual(VoiceInkProviderKind.groq.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.openAI.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.deepgram.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.cerebras.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.gemini.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.mistral.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.elevenLabs.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.soniox.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.xai.transcriptionServiceKind, .remote)
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.transcriptionServiceKind, .localWhisper)
    }

    func testTranscriptionEmptyTextPolicyPreservesMacOSAndLocalPolicy() {
        XCTAssertEqual(VoiceInkProviderKind.groq.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertEqual(VoiceInkProviderKind.deepgram.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertEqual(VoiceInkProviderKind.gemini.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertTrue(VoiceInkProviderKind.groq.transcriptionEmptyTextPolicy.accepts(" \n\t "))
        XCTAssertFalse(VoiceInkProviderKind.groq.transcriptionEmptyTextPolicy.accepts(""))

        XCTAssertEqual(VoiceInkProviderKind.soniox.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertFalse(VoiceInkProviderKind.soniox.transcriptionEmptyTextPolicy.accepts(" \n\t "))

        XCTAssertEqual(VoiceInkProviderKind.mistral.transcriptionEmptyTextPolicy, .allow)
        XCTAssertTrue(VoiceInkProviderKind.mistral.transcriptionEmptyTextPolicy.accepts(""))
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.transcriptionEmptyTextPolicy, .allow)
        XCTAssertTrue(VoiceInkProviderKind.localWhisper.transcriptionEmptyTextPolicy.accepts(""))
    }

    func testRemoteTranscriptionProvidersUseSharedTransportAndEndpoints() {
        XCTAssertEqual(VoiceInkProviderKind.gemini.transcriptionTransport, .geminiGenerateContent)
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.transcriptionAPIBaseURL.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta"
        )
        XCTAssertEqual(VoiceInkProviderKind.mistral.transcriptionTransport, .mistral)
        XCTAssertEqual(VoiceInkProviderKind.mistral.transcriptionAPIBaseURL.absoluteString, "https://api.mistral.ai")
        XCTAssertEqual(VoiceInkProviderKind.elevenLabs.transcriptionTransport, .elevenLabs)
        XCTAssertEqual(VoiceInkProviderKind.elevenLabs.transcriptionAPIBaseURL.absoluteString, "https://api.elevenlabs.io")
        XCTAssertEqual(VoiceInkProviderKind.soniox.transcriptionTransport, .soniox)
        XCTAssertEqual(VoiceInkProviderKind.soniox.transcriptionAPIBaseURL.absoluteString, "https://api.soniox.com/v1")
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.transcriptionTransport, .speechmatics)
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.transcriptionAPIBaseURL.absoluteString, "https://asr.api.speechmatics.com/v2")
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.transcriptionTransport, .assemblyAI)
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.transcriptionAPIBaseURL.absoluteString, "https://api.assemblyai.com")
        XCTAssertEqual(VoiceInkProviderKind.xai.transcriptionTransport, .xai)
        XCTAssertEqual(VoiceInkProviderKind.xai.transcriptionAPIBaseURL.absoluteString, "https://api.x.ai")
    }

    func testGeminiUsesNativeTranscriptionEndpointButOpenAICompatiblePostProcessingEndpoint() {
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.postProcessingChatCompletionsURL?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/openai/v1/chat/completions"
        )
    }

    func testProviderReadinessFollowsProviderAccessPolicy() {
        XCTAssertTrue(VoiceInkProviderKind.groq.isReady(
            userAPIKey: "groq-key",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: false
        ))
        XCTAssertFalse(VoiceInkProviderKind.groq.isReady(
            userAPIKey: "",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(VoiceInkProviderKind.groq.isReady(
            userAPIKey: " \n ",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(VoiceInkProviderKind.groq.isReady(
            userAPIKey: "groq-key",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: true
        ))

        XCTAssertTrue(VoiceInkProviderKind.localWhisper.isReady(
            userAPIKey: "",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.isReady(
            userAPIKey: "",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: false
        ))

        XCTAssertTrue(VoiceInkProviderKind.voiceInk.isReady(
            userAPIKey: "",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: false
        ))
    }

    func testAvailableProvidersFiltersByModelUseAndReadiness() {
        let readyProviders: Set<VoiceInkProviderKind> = [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper, .voiceInk]

        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .transcription) { readyProviders.contains($0) },
            [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper]
        )

        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .postProcessing) { readyProviders.contains($0) },
            [.groq]
        )
    }

    func testBundledVoiceInkProviderIsNotSelectableUntilAnAdapterExists() {
        XCTAssertTrue(VoiceInkProviderKind.voiceInk.isReady(
            userAPIKey: "",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: false
        ))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.supportsModelUse(.transcription))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.supportsModelUse(.postProcessing))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .transcription))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .postProcessing))
        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .transcription) { $0 == .voiceInk },
            []
        )
        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .postProcessing) { $0 == .voiceInk },
            []
        )
    }

    func testProviderSelectabilityKeepsReadinessAndModelSupportSeparate() {
        XCTAssertTrue(VoiceInkProviderKind.groq.isSelectable(for: .transcription))
        XCTAssertTrue(VoiceInkProviderKind.groq.isSelectable(for: .postProcessing))
        XCTAssertTrue(VoiceInkProviderKind.localWhisper.isSelectable(for: .transcription))
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.isSelectable(for: .postProcessing))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .transcription))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .postProcessing))
    }

    func testAvailableProvidersReturnsEmptyWhenNoProviderIsReady() {
        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .transcription) { _ in false },
            []
        )
        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .postProcessing) { _ in false },
            []
        )
    }
}
