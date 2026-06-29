import Foundation
@testable import VoiceInkCore

final class AIProviderCatalogTests: XCTestCase {
    func testAIEnhancementProviderKeyChangeRequestPreservesMacOSNotificationName() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKeyChangeRequest.notificationName,
            Notification.Name("aiProviderKeyChanged")
        )
    }

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

    func testMacOSAIEnhancementCredentialStateResolutionPlanIsShared() {
        let groqPlan = VoiceInkAIEnhancementCredentialStateResolutionPlan.resolving(provider: .groq)
        let localCLIPlan = VoiceInkAIEnhancementCredentialStateResolutionPlan.resolving(provider: .localCLI)
        let ollamaPlan = VoiceInkAIEnhancementCredentialStateResolutionPlan.resolving(provider: .ollama)

        XCTAssertEqual(
            groqPlan,
            VoiceInkAIEnhancementCredentialStateResolutionPlan(
                provider: .groq,
                providerKeyStorageNameToLoad: VoiceInkAIEnhancementProviderKind.groq.rawValue
            )
        )
        XCTAssertEqual(
            groqPlan.credentialState(
                savedAPIKey: "saved-groq-key",
                isLocalCLIConfigured: false
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "saved-groq-key", isAPIKeyValid: true)
        )
        XCTAssertEqual(
            groqPlan.credentialState(
                savedAPIKey: nil,
                isLocalCLIConfigured: true
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        )
        XCTAssertEqual(
            localCLIPlan,
            VoiceInkAIEnhancementCredentialStateResolutionPlan(
                provider: .localCLI,
                providerKeyStorageNameToLoad: nil
            )
        )
        XCTAssertEqual(
            localCLIPlan.credentialState(
                savedAPIKey: "ignored-key",
                isLocalCLIConfigured: true
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: true)
        )
        XCTAssertEqual(
            ollamaPlan,
            VoiceInkAIEnhancementCredentialStateResolutionPlan(
                provider: .ollama,
                providerKeyStorageNameToLoad: nil
            )
        )
        XCTAssertEqual(
            ollamaPlan.credentialState(
                savedAPIKey: nil,
                isLocalCLIConfigured: false
            ),
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: true)
        )
    }

    func testMacOSAIEnhancementCredentialStateResolutionPlanAppliesRuntimeState() {
        var loadedProviders: [String] = []
        var credentialStates: [VoiceInkAIEnhancementCredentialState] = []

        VoiceInkAIEnhancementCredentialStateResolutionPlan.resolving(provider: .groq)
            .applyRuntimeState(
                loadSavedAPIKey: {
                    loadedProviders.append($0)
                    return "saved-groq-key"
                },
                isLocalCLIConfigured: false,
                setCredentialState: { credentialStates.append($0) }
            )

        XCTAssertEqual(loadedProviders, [VoiceInkAIEnhancementProviderKind.groq.rawValue])
        XCTAssertEqual(credentialStates, [
            VoiceInkAIEnhancementCredentialState(apiKey: "saved-groq-key", isAPIKeyValid: true)
        ])

        loadedProviders = []
        credentialStates = []

        VoiceInkAIEnhancementCredentialStateResolutionPlan.resolving(provider: .localCLI)
            .applyRuntimeState(
                loadSavedAPIKey: {
                    loadedProviders.append($0)
                    return "ignored-key"
                },
                isLocalCLIConfigured: true,
                setCredentialState: { credentialStates.append($0) }
            )

        XCTAssertTrue(loadedProviders.isEmpty)
        XCTAssertEqual(credentialStates, [
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: true)
        ])
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

    func testMacOSAIEnhancementAPIKeyVerificationRequestPlanIsShared() {
        let environmentDraft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " $GROQ_API_KEY "
        )
        let missingDraft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " $MISSING_GROQ_KEY "
        )
        let noKeyProviderDraft = VoiceInkAIEnhancementAPIKeyDraft(
            provider: .ollama,
            enteredKey: "ignored-key"
        )

        XCTAssertEqual(
            environmentDraft.verificationRequestPlan(environment: ["GROQ_API_KEY": "resolved-key"]),
            VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: "resolved-key",
                immediateResult: nil
            )
        )
        XCTAssertEqual(
            missingDraft.verificationRequestPlan(environment: [:]),
            VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: VoiceInkAIEnhancementProviderKind.missingVerificationCandidateMessage
                )
            )
        )
        XCTAssertEqual(
            noKeyProviderDraft.verificationRequestPlan(environment: [:]),
            VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationRequestPlanAppliesRuntimeState() {
        var completionResults: [VoiceInkAPIKeyVerificationResult] = []
        var resolvedKeys: [String] = []

        VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
            resolvedKeyToVerify: nil,
            immediateResult: VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "missing")
        )
        .applyRuntimeState(
            completeImmediateResult: { completionResults.append($0) },
            verifyResolvedKey: { resolvedKeys.append($0) }
        )

        XCTAssertEqual(completionResults, [
            VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "missing")
        ])
        XCTAssertTrue(resolvedKeys.isEmpty)

        completionResults = []
        resolvedKeys = []

        VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
            resolvedKeyToVerify: "resolved-key",
            immediateResult: nil
        )
        .applyRuntimeState(
            completeImmediateResult: { completionResults.append($0) },
            verifyResolvedKey: { resolvedKeys.append($0) }
        )

        XCTAssertTrue(completionResults.isEmpty)
        XCTAssertEqual(resolvedKeys, ["resolved-key"])
    }

    func testMacOSAIEnhancementAPIKeyVerificationDispatchPlanIsShared() async {
        let customRequestURL = URL(string: "https://api.example.com/v1/chat/completions")!

        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .localCLI,
                currentModel: "ignored",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: VoiceInkAIEnhancementProviderKind.localCLI.unsupportedAPIKeyVerificationMessage
            ),
            expectedCalls: []
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .custom,
                currentModel: "custom-model",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: VoiceInkAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage
            ),
            expectedCalls: []
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .custom,
                currentModel: "custom-model",
                requestURL: customRequestURL
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openai"),
            expectedCalls: [
                "openai:https://api.example.com/v1/chat/completions:resolved-key:custom-model"
            ]
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .gemini,
                currentModel: "gemini-2.5-pro",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"),
            expectedCalls: [
                "shared:resolved-key:gemini"
            ]
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .anthropic,
                currentModel: "claude-sonnet-4-20250514",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "anthropic"),
            expectedCalls: [
                "anthropic:resolved-key"
            ]
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .openRouter,
                currentModel: "openai/gpt-5.5",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openrouter"),
            expectedCalls: [
                "openrouter:resolved-key:openai/gpt-5.5"
            ]
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationDispatchPlanAppliesAdapters() async {
        let customRequestURL = URL(string: "https://api.example.com/v1/chat/completions")!

        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .custom,
                currentModel: "custom-model",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: VoiceInkAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage
            ),
            expectedCalls: []
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .gemini,
                currentModel: "gemini-2.5-pro",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"),
            expectedCalls: [
                "shared:resolved-key:gemini"
            ]
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .anthropic,
                currentModel: "claude-sonnet-4-20250514",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "anthropic"),
            expectedCalls: [
                "anthropic:resolved-key"
            ]
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .custom,
                currentModel: "custom-model",
                requestURL: customRequestURL
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openai"),
            expectedCalls: [
                "openai:https://api.example.com/v1/chat/completions:resolved-key:custom-model"
            ]
        )
        await assertVerificationDispatch(
            VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .openRouter,
                currentModel: "openai/gpt-5.5",
                requestURL: nil
            ),
            expectedResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openrouter"),
            expectedCalls: [
                "openrouter:resolved-key:openai/gpt-5.5"
            ]
        )
    }

    private func assertVerificationDispatch(
        _ plan: VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan,
        expectedResult: VoiceInkAPIKeyVerificationResult,
        expectedCalls: [String]
    ) async {
        var calls: [String] = []
        let result = await plan.verifyResolvedAPIKey(
            "resolved-key",
            verifySharedProvider: { key, provider in
                calls.append("shared:\(key):\(provider.rawValue)")
                return VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared")
            },
            verifyAnthropicMessages: { key in
                calls.append("anthropic:\(key)")
                return VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "anthropic")
            },
            verifyOpenAICompatibleModels: { requestURL, key, model in
                calls.append("openai:\(requestURL.absoluteString):\(key):\(model)")
                return VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openai")
            },
            verifyOpenRouterModels: { key, model in
                calls.append("openrouter:\(key):\(model)")
                return VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openrouter")
            }
        )

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(calls, expectedCalls)
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
                providerKeyStorageNameToSave: VoiceInkAIEnhancementProviderKind.groq.rawValue,
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
                providerKeyStorageNameToSave: nil,
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
                providerKeyStorageNameToSave: nil,
                errorMessage: nil
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanBuildsSuccessPersistencePlan() {
        let successPlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: false,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: "invalid"
        )

        XCTAssertEqual(
            successPlan.successPersistencePlan,
            VoiceInkAIEnhancementAPIKeyVerificationPersistencePlan(
                runtimeAPIKey: "resolved-key",
                keyToSave: "$GROQ_API_KEY",
                providerKeyStorageNameToSave: VoiceInkAIEnhancementProviderKind.groq.rawValue
            )
        )
        XCTAssertNil(failurePlan.successPersistencePlan)
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanBuildsServiceStateApplicationPlan() {
        let successPlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: false,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: "invalid"
        )
        let noKeyProviderPlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: nil
        )

        XCTAssertEqual(
            successPlan.serviceStateApplicationPlan,
            VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan(
                apiKeyToApply: "resolved-key",
                isAPIKeyValid: true,
                shouldPostProviderKeyChanged: true,
                completionResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        )
        XCTAssertEqual(
            failurePlan.serviceStateApplicationPlan,
            VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan(
                apiKeyToApply: nil,
                isAPIKeyValid: false,
                shouldPostProviderKeyChanged: false,
                completionResult: VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "invalid")
            )
        )
        XCTAssertEqual(
            noKeyProviderPlan.serviceStateApplicationPlan,
            VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan(
                apiKeyToApply: nil,
                isAPIKeyValid: true,
                shouldPostProviderKeyChanged: false,
                completionResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanAppliesSuccessPersistence() {
        let successPlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let storedKeySuccessPlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: nil,
            providerKeyStorageNameToSave: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: false,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: "invalid"
        )

        var savedKeys: [(key: String, provider: String)] = []

        successPlan.applySuccessPersistence { key, provider in
            savedKeys.append((key, provider))
        }
        XCTAssertEqual(savedKeys.map { $0.key }, ["$GROQ_API_KEY"])
        XCTAssertEqual(savedKeys.map { $0.provider }, [VoiceInkAIEnhancementProviderKind.groq.rawValue])

        savedKeys = []
        storedKeySuccessPlan.applySuccessPersistence { key, provider in
            savedKeys.append((key, provider))
        }
        XCTAssertTrue(savedKeys.isEmpty)

        failurePlan.applySuccessPersistence { key, provider in
            savedKeys.append((key, provider))
        }
        XCTAssertTrue(savedKeys.isEmpty)
    }

    func testMacOSAIEnhancementAPIKeyVerificationServiceStatePlanAppliesRuntimeState() {
        let successPlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: false,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: "invalid"
        )

        var appliedAPIKeys: [String] = []
        var appliedValidities: [Bool] = []
        var providerKeyChangedPostCount = 0
        var completionResults: [VoiceInkAPIKeyVerificationResult] = []

        successPlan.serviceStateApplicationPlan.apply(
            setAPIKey: { appliedAPIKeys.append($0) },
            setAPIKeyValidity: { appliedValidities.append($0) },
            postProviderKeyChanged: { providerKeyChangedPostCount += 1 },
            complete: { completionResults.append($0) }
        )

        XCTAssertEqual(appliedAPIKeys, ["resolved-key"])
        XCTAssertEqual(appliedValidities, [true])
        XCTAssertEqual(providerKeyChangedPostCount, 1)
        XCTAssertEqual(completionResults, [
            VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
        ])

        appliedAPIKeys = []
        appliedValidities = []
        providerKeyChangedPostCount = 0
        completionResults = []

        failurePlan.serviceStateApplicationPlan.apply(
            setAPIKey: { appliedAPIKeys.append($0) },
            setAPIKeyValidity: { appliedValidities.append($0) },
            postProviderKeyChanged: { providerKeyChangedPostCount += 1 },
            complete: { completionResults.append($0) }
        )

        XCTAssertTrue(appliedAPIKeys.isEmpty)
        XCTAssertEqual(appliedValidities, [false])
        XCTAssertEqual(providerKeyChangedPostCount, 0)
        XCTAssertEqual(completionResults, [
            VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: "invalid")
        ])
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanAppliesRuntimeState() {
        let successPlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: false,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: "invalid"
        )

        var events: [String] = []

        successPlan.applyRuntimeState(
            saveKey: { key, provider in events.append("save:\(key):\(provider)") },
            setAPIKey: { events.append("apiKey:\($0)") },
            setAPIKeyValidity: { events.append("valid:\($0)") },
            postProviderKeyChanged: { events.append("postProviderKeyChanged") },
            complete: { events.append("complete:\($0.isValid):\($0.errorMessage ?? "nil")") }
        )

        XCTAssertEqual(events, [
            "save:$GROQ_API_KEY:Groq",
            "apiKey:resolved-key",
            "valid:true",
            "postProviderKeyChanged",
            "complete:true:nil"
        ])

        events = []

        failurePlan.applyRuntimeState(
            saveKey: { key, provider in events.append("save:\(key):\(provider)") },
            setAPIKey: { events.append("apiKey:\($0)") },
            setAPIKeyValidity: { events.append("valid:\($0)") },
            postProviderKeyChanged: { events.append("postProviderKeyChanged") },
            complete: { events.append("complete:\($0.isValid):\($0.errorMessage ?? "nil")") }
        )

        XCTAssertEqual(events, [
            "valid:false",
            "complete:false:invalid"
        ])
    }

    func testMacOSAIEnhancementAPIKeyClearPlanIsShared() {
        XCTAssertEqual(
            VoiceInkAIEnhancementAPIKeyClearPlan.clearing(provider: .groq),
            VoiceInkAIEnhancementAPIKeyClearPlan(
                provider: .groq,
                providerKeyStorageNameToDelete: VoiceInkAIEnhancementProviderKind.groq.rawValue,
                credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                    apiKey: "",
                    isAPIKeyValid: false
                )
            )
        )

        XCTAssertEqual(
            VoiceInkAIEnhancementAPIKeyClearPlan.clearing(provider: .custom),
            VoiceInkAIEnhancementAPIKeyClearPlan(
                provider: .custom,
                providerKeyStorageNameToDelete: VoiceInkAIEnhancementProviderKind.custom.rawValue,
                credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                    apiKey: "",
                    isAPIKeyValid: false
                )
            )
        )

        XCTAssertNil(VoiceInkAIEnhancementAPIKeyClearPlan.clearing(provider: .ollama))
        XCTAssertNil(VoiceInkAIEnhancementAPIKeyClearPlan.clearing(provider: .localCLI))
    }

    func testMacOSAIEnhancementAPIKeyClearPlanBuildsPersistenceAndStatePlans() {
        let clearPlan = VoiceInkAIEnhancementAPIKeyClearPlan(
            provider: .groq,
            providerKeyStorageNameToDelete: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )

        XCTAssertEqual(
            clearPlan.persistencePlan,
            VoiceInkAIEnhancementAPIKeyClearPersistencePlan(
                providerKeyStorageNameToDelete: VoiceInkAIEnhancementProviderKind.groq.rawValue
            )
        )
        XCTAssertEqual(
            clearPlan.serviceStateApplicationPlan,
            VoiceInkAIEnhancementAPIKeyClearServiceStatePlan(
                credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                    apiKey: "",
                    isAPIKeyValid: false
                ),
                shouldPostProviderKeyChanged: true
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyClearPlanAppliesPersistence() {
        let clearPlan = VoiceInkAIEnhancementAPIKeyClearPlan(
            provider: .groq,
            providerKeyStorageNameToDelete: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )

        var deletedProviders: [String] = []

        clearPlan.applyClearPersistence { provider in
            deletedProviders.append(provider)
        }

        XCTAssertEqual(deletedProviders, [VoiceInkAIEnhancementProviderKind.groq.rawValue])
    }

    func testMacOSAIEnhancementAPIKeyClearServiceStatePlanAppliesRuntimeState() {
        let clearPlan = VoiceInkAIEnhancementAPIKeyClearPlan(
            provider: .groq,
            providerKeyStorageNameToDelete: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )

        var appliedCredentialStates: [VoiceInkAIEnhancementCredentialState] = []
        var providerKeyChangedPostCount = 0

        clearPlan.serviceStateApplicationPlan.apply(
            setCredentialState: { appliedCredentialStates.append($0) },
            postProviderKeyChanged: { providerKeyChangedPostCount += 1 }
        )

        XCTAssertEqual(appliedCredentialStates, [
            VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        ])
        XCTAssertEqual(providerKeyChangedPostCount, 1)
    }

    func testMacOSAIEnhancementAPIKeyClearPlanAppliesRuntimeState() {
        let clearPlan = VoiceInkAIEnhancementAPIKeyClearPlan(
            provider: .groq,
            providerKeyStorageNameToDelete: VoiceInkAIEnhancementProviderKind.groq.rawValue,
            credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )

        var events: [String] = []

        clearPlan.applyRuntimeState(
            deleteKey: { events.append("delete:\($0)") },
            setCredentialState: { events.append("state:\($0.apiKey):\($0.isAPIKeyValid)") },
            postProviderKeyChanged: { events.append("postProviderKeyChanged") }
        )

        XCTAssertEqual(events, [
            "delete:Groq",
            "state::false",
            "postProviderKeyChanged"
        ])
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
        let allProviderKeyNames = Set(VoiceInkAIEnhancementProviderKind.textEnhancementProviderKeyStorageNamesToCheck)

        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.textEnhancementProviderKeyStorageNamesToCheck,
            [
                VoiceInkAIEnhancementProviderKind.cerebras.rawValue,
                VoiceInkAIEnhancementProviderKind.groq.rawValue,
                VoiceInkAIEnhancementProviderKind.gemini.rawValue,
                VoiceInkAIEnhancementProviderKind.anthropic.rawValue,
                VoiceInkAIEnhancementProviderKind.openAI.rawValue,
                VoiceInkAIEnhancementProviderKind.openRouter.rawValue,
                VoiceInkAIEnhancementProviderKind.mistral.rawValue,
                VoiceInkAIEnhancementProviderKind.custom.rawValue
            ]
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.connectedTextEnhancementProviders(
                providerKeyStorageNamesWithKeys: allProviderKeyNames,
                isOllamaConnected: true,
                isLocalCLIConfigured: true
            ),
            VoiceInkAIEnhancementProviderKind.selectableTextEnhancementProviders
        )

        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.connectedTextEnhancementProviders(
                providerKeyStorageNamesWithKeys: Set([
                    VoiceInkAIEnhancementProviderKind.groq.rawValue,
                    VoiceInkAIEnhancementProviderKind.custom.rawValue
                ]),
                isOllamaConnected: false,
                isLocalCLIConfigured: false
            ),
            [.groq, .custom]
        )
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.connectedTextEnhancementProviders(
                providerKeyStorageNamesWithKeys: [],
                isOllamaConnected: true,
                isLocalCLIConfigured: false
            ),
            [.ollama]
        )
        XCTAssertTrue(
            VoiceInkAIEnhancementProviderKind.localCLI.isConnectedForTextEnhancement(
                providerKeyStorageNamesWithKeys: [],
                isOllamaConnected: false,
                isLocalCLIConfigured: true
            )
        )
        XCTAssertFalse(
            VoiceInkAIEnhancementProviderKind.assemblyAI.isConnectedForTextEnhancement(
                providerKeyStorageNamesWithKeys: allProviderKeyNames,
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
                provider: .groq,
                isAPIKeyValid: true,
                isCheckingOllama: false,
                hasOllamaModels: false
            ),
            .status(text: "Connected", tone: .connected)
        )
        XCTAssertNil(
            presentation.connectionStatus(
                provider: .groq,
                isAPIKeyValid: false,
                isCheckingOllama: false,
                hasOllamaModels: false
            )
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                provider: .ollama,
                isAPIKeyValid: false,
                isCheckingOllama: true,
                hasOllamaModels: false
            ),
            .checking
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                provider: .ollama,
                isAPIKeyValid: false,
                isCheckingOllama: false,
                hasOllamaModels: true
            ),
            .status(text: "Connected", tone: .connected)
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                provider: .ollama,
                isAPIKeyValid: false,
                isCheckingOllama: false,
                hasOllamaModels: false
            ),
            .status(text: "Disconnected", tone: .disconnected)
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                provider: .localCLI,
                isAPIKeyValid: true,
                isCheckingOllama: false,
                hasOllamaModels: false
            ),
            .status(text: "Connected", tone: .connected)
        )

        for provider in VoiceInkAIEnhancementProviderKind.allCases where provider != .ollama {
            XCTAssertEqual(
                presentation.connectionStatus(
                    provider: provider,
                    isAPIKeyValid: true,
                    isCheckingOllama: true,
                    hasOllamaModels: true
                ),
                .status(text: "Connected", tone: .connected),
                provider.rawValue
            )
            XCTAssertNil(
                presentation.connectionStatus(
                    provider: provider,
                    isAPIKeyValid: false,
                    isCheckingOllama: true,
                    hasOllamaModels: true
                ),
                provider.rawValue
            )
        }
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

    func testMacOSAIEnhancementAPIKeyControlPresentationUsesDraftAndCustomSubmitPolicy() {
        let presentation = VoiceInkAIEnhancementProviderSettingsPresentation.macOS

        XCTAssertEqual(
            presentation.apiKeyControlPresentation(
                formState: VoiceInkAIEnhancementAPIKeyFormState(enteredKey: "draft-key"),
                provider: .groq,
                customProviderBaseURL: "https://api.example.test/v1/chat/completions",
                customProviderModelName: "custom-model"
            ),
            VoiceInkAIEnhancementAPIKeyControlPresentation(
                isVerificationProgressVisible: false,
                isDefaultVerifyAndSaveButtonDisabled: false,
                isCustomVerifyAndSaveButtonDisabled: false
            )
        )
        XCTAssertEqual(
            presentation.apiKeyControlPresentation(
                formState: VoiceInkAIEnhancementAPIKeyFormState(
                    enteredKey: "draft-key",
                    verificationProgress: .verifying
                ),
                provider: .groq,
                customProviderBaseURL: "https://api.example.test/v1/chat/completions",
                customProviderModelName: "custom-model"
            ),
            VoiceInkAIEnhancementAPIKeyControlPresentation(
                isVerificationProgressVisible: true,
                isDefaultVerifyAndSaveButtonDisabled: false,
                isCustomVerifyAndSaveButtonDisabled: false
            )
        )
        XCTAssertEqual(
            presentation.apiKeyControlPresentation(
                formState: VoiceInkAIEnhancementAPIKeyFormState(enteredKey: ""),
                provider: .custom,
                customProviderBaseURL: "https://api.example.test/v1/chat/completions",
                customProviderModelName: "custom-model"
            ),
            VoiceInkAIEnhancementAPIKeyControlPresentation(
                isVerificationProgressVisible: false,
                isDefaultVerifyAndSaveButtonDisabled: true,
                isCustomVerifyAndSaveButtonDisabled: true
            )
        )
        XCTAssertTrue(
            presentation.apiKeyControlPresentation(
                formState: VoiceInkAIEnhancementAPIKeyFormState(enteredKey: "draft-key"),
                provider: .custom,
                customProviderBaseURL: "",
                customProviderModelName: "custom-model"
            ).isCustomVerifyAndSaveButtonDisabled
        )
    }

    func testMacOSAIEnhancementProviderSelectionPlanIsShared() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderSelectionPlan.selecting(.groq),
            VoiceInkAIEnhancementProviderSelectionPlan(
                selectedProviderToSave: .groq,
                shouldRefreshOllamaRuntimeModels: false
            )
        )

        XCTAssertEqual(
            VoiceInkAIEnhancementProviderSelectionPlan.selecting(.ollama),
            VoiceInkAIEnhancementProviderSelectionPlan(
                selectedProviderToSave: .ollama,
                shouldRefreshOllamaRuntimeModels: true
            )
        )

        XCTAssertEqual(
            VoiceInkAIEnhancementProviderSelectionPlan.selecting(.localCLI),
            VoiceInkAIEnhancementProviderSelectionPlan(
                selectedProviderToSave: .localCLI,
                shouldRefreshOllamaRuntimeModels: false
            )
        )
    }

    func testMacOSAIEnhancementProviderSelectionPlanAppliesRuntimeState() {
        let groqPlan = VoiceInkAIEnhancementProviderSelectionPlan.selecting(.groq)
        let ollamaPlan = VoiceInkAIEnhancementProviderSelectionPlan.selecting(.ollama)

        var events: [String] = []
        func apply(_ plan: VoiceInkAIEnhancementProviderSelectionPlan) {
            plan.applyRuntimeState(
                applyPersistence: { plan in
                    events.append("persist:\(plan.selectedProviderToSave.rawValue)")
                },
                applyCredentialState: {
                    events.append("credential")
                },
                refreshOllamaRuntimeModels: {
                    events.append("refreshOllama")
                },
                postSettingsChanged: {
                    events.append("settings")
                }
            )
        }

        apply(groqPlan)
        XCTAssertEqual(events, [
            "persist:Groq",
            "credential",
            "settings"
        ])

        events = []
        apply(ollamaPlan)
        XCTAssertEqual(events, [
            "persist:Ollama",
            "credential",
            "refreshOllama",
            "settings"
        ])
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

    func testMacOSAIEnhancementModelSelectionPlanIsShared() throws {
        let initialModels: [VoiceInkAIEnhancementProviderKind: String] = [
            .groq: "old-groq-model",
            .openAI: "gpt-5.4"
        ]

        let groqPlan = try XCTUnwrap(
            VoiceInkAIEnhancementModelSelectionPlan.selecting(
                "openai/gpt-oss-120b",
                provider: .groq,
                selectedModels: initialModels
            )
        )

        XCTAssertEqual(groqPlan.provider, .groq)
        XCTAssertEqual(groqPlan.selectedModelToSave, "openai/gpt-oss-120b")
        XCTAssertNil(groqPlan.ollamaModelToApply)
        XCTAssertEqual(groqPlan.selectedModels[.groq], "openai/gpt-oss-120b")
        XCTAssertEqual(groqPlan.selectedModels[.openAI], "gpt-5.4")

        let ollamaPlan = try XCTUnwrap(
            VoiceInkAIEnhancementModelSelectionPlan.selecting(
                "llama3",
                provider: .ollama,
                selectedModels: initialModels
            )
        )

        XCTAssertEqual(ollamaPlan.provider, .ollama)
        XCTAssertEqual(ollamaPlan.selectedModelToSave, "llama3")
        XCTAssertEqual(ollamaPlan.ollamaModelToApply, "llama3")
        XCTAssertEqual(ollamaPlan.selectedModels[.ollama], "llama3")

        XCTAssertNil(
            VoiceInkAIEnhancementModelSelectionPlan.selecting(
                "",
                provider: .groq,
                selectedModels: initialModels
            )
        )
    }

    func testMacOSAIEnhancementModelSelectionPlanAppliesRuntimeState() throws {
        let initialModels: [VoiceInkAIEnhancementProviderKind: String] = [
            .groq: "old-groq-model",
            .openAI: "gpt-5.4"
        ]
        let groqPlan = try XCTUnwrap(
            VoiceInkAIEnhancementModelSelectionPlan.selecting(
                "openai/gpt-oss-120b",
                provider: .groq,
                selectedModels: initialModels
            )
        )
        let ollamaPlan = try XCTUnwrap(
            VoiceInkAIEnhancementModelSelectionPlan.selecting(
                "llama3",
                provider: .ollama,
                selectedModels: initialModels
            )
        )

        var events: [String] = []
        func apply(_ plan: VoiceInkAIEnhancementModelSelectionPlan) {
            plan.applyRuntimeState(
                setSelectedModels: { models in
                    let selected = models[plan.provider] ?? ""
                    events.append("selected:\(plan.provider.rawValue):\(selected)")
                },
                applyPersistence: { plan in
                    events.append("persist:\(plan.provider.rawValue):\(plan.selectedModelToSave)")
                },
                setOllamaRuntimeModel: { model in
                    events.append("ollama:\(model)")
                },
                sendObjectWillChange: {
                    events.append("willChange")
                },
                postSettingsChanged: {
                    events.append("settings")
                }
            )
        }

        apply(groqPlan)
        XCTAssertEqual(events, [
            "selected:Groq:openai/gpt-oss-120b",
            "persist:Groq:openai/gpt-oss-120b",
            "willChange",
            "settings"
        ])

        events = []
        apply(ollamaPlan)
        XCTAssertEqual(events, [
            "selected:Ollama:llama3",
            "persist:Ollama:llama3",
            "ollama:llama3",
            "willChange",
            "settings"
        ])
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

    func testMacOSOllamaRequestTemperaturePolicyIsShared() {
        XCTAssertEqual(
            VoiceInkAIEnhancementProviderKind.ollamaTextEnhancementRequestTemperature,
            0.3
        )
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

    func testMacOSAIEnhancementAvailableModelsResolveFromRuntimeAndStaticProviders() {
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

    func testMacOSAIEnhancementModelPickerPresentationIsShared() {
        let presentation = VoiceInkAIEnhancementProviderSettingsPresentation.macOS
        let hidden = VoiceInkAIEnhancementModelPickerPresentation(
            isModelPickerVisible: false,
            isRefreshButtonVisible: false,
            emptyStateText: nil
        )
        let staticPicker = VoiceInkAIEnhancementModelPickerPresentation(
            isModelPickerVisible: true,
            isRefreshButtonVisible: false,
            emptyStateText: nil
        )
        let refreshablePicker = VoiceInkAIEnhancementModelPickerPresentation(
            isModelPickerVisible: true,
            isRefreshButtonVisible: true,
            emptyStateText: nil
        )
        let refreshableEmptyState = VoiceInkAIEnhancementModelPickerPresentation(
            isModelPickerVisible: false,
            isRefreshButtonVisible: true,
            emptyStateText: "No models loaded"
        )
        let expectedLoadedPresentations: [VoiceInkAIEnhancementProviderKind: VoiceInkAIEnhancementModelPickerPresentation] = [
            .anthropic: staticPicker,
            .assemblyAI: staticPicker,
            .cerebras: staticPicker,
            .custom: hidden,
            .deepgram: staticPicker,
            .elevenLabs: staticPicker,
            .gemini: staticPicker,
            .groq: staticPicker,
            .localCLI: hidden,
            .mistral: staticPicker,
            .ollama: hidden,
            .openAI: staticPicker,
            .openRouter: refreshablePicker,
            .soniox: staticPicker,
            .speechmatics: staticPicker
        ]

        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.allCases.count, expectedLoadedPresentations.count)

        for (provider, expectedPresentation) in expectedLoadedPresentations {
            XCTAssertEqual(
                presentation.modelPickerPresentation(provider: provider, availableModels: ["model"]),
                expectedPresentation,
                provider.rawValue
            )
            XCTAssertEqual(
                presentation.modelPickerPresentation(provider: provider, availableModels: []),
                provider == .openRouter ? refreshableEmptyState : hidden,
                provider.rawValue
            )
        }
    }

    func testMacOSAIEnhancementRequestURLSelectionIsShared() async {
        await withIsolatedDefaultsAsync { defaults in
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

            let invalidCustomPlan = VoiceInkAIEnhancementRequestExecutionPlan.planning(
                provider: .custom,
                modelName: "custom-model",
                defaults: defaults
            )

            do {
                _ = try await openAICompatibleRequestSummary(for: invalidCustomPlan)
                XCTFail("Expected invalid custom endpoint to throw")
            } catch {
                XCTAssertEqual(
                    error as? VoiceInkAIEnhancementError,
                    .customError(VoiceInkAIEnhancementProviderKind.custom.invalidTextEnhancementRequestURLMessage)
                )
            }

            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL(
                "https://api.example.com/v1/chat/completions",
                to: defaults
            )
            let customPlan = VoiceInkAIEnhancementRequestExecutionPlan.planning(
                provider: .custom,
                modelName: "custom-model",
                defaults: defaults
            )

            do {
                let customRequestSummary = try await openAICompatibleRequestSummary(for: customPlan)
                XCTAssertEqual(customRequestSummary?.requestURL.absoluteString, "https://api.example.com/v1/chat/completions")
                XCTAssertEqual(customRequestSummary?.temperature, 0.3)
                XCTAssertNil(customRequestSummary?.reasoningEffort)
                XCTAssertFalse(customRequestSummary?.hasExtraBodyParameters ?? true)
                XCTAssertNil(customRequestSummary?.includeReasoning)
            } catch {
                XCTFail("Expected valid custom endpoint to produce a request plan")
            }
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

    func testMacOSAIEnhancementModelRefreshPlanCachesAndRepairsSelection() {
        let openRouterModels = [
            "anthropic/claude-3.5-sonnet",
            "openai/gpt-4o"
        ]

        XCTAssertEqual(
            VoiceInkAIEnhancementModelRefreshPlan.refreshed(
                provider: .openRouter,
                currentModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter),
                refreshedModels: openRouterModels,
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter)
            ),
            VoiceInkAIEnhancementModelRefreshPlan(
                refreshedModelNames: openRouterModels,
                selectedModelToSave: "anthropic/claude-3.5-sonnet"
            )
        )

        XCTAssertEqual(
            VoiceInkAIEnhancementModelRefreshPlan.refreshed(
                provider: .openRouter,
                currentModel: "custom/openrouter-model",
                refreshedModels: openRouterModels,
                defaultModel: VoiceInkAIModelCatalog.defaultModel(for: .openRouter)
            ),
            VoiceInkAIEnhancementModelRefreshPlan(
                refreshedModelNames: openRouterModels,
                selectedModelToSave: nil
            )
        )

        XCTAssertEqual(
            VoiceInkAIEnhancementModelRefreshPlan.refreshed(
                provider: .ollama,
                currentModel: "missing-local-model",
                refreshedModels: ["llama3", "mistral"],
                defaultModel: VoiceInkAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
            ),
            VoiceInkAIEnhancementModelRefreshPlan(
                refreshedModelNames: ["llama3", "mistral"],
                selectedModelToSave: "llama3"
            )
        )

        XCTAssertEqual(
            VoiceInkAIEnhancementModelRefreshPlan.failed,
            VoiceInkAIEnhancementModelRefreshPlan(
                refreshedModelNames: [],
                selectedModelToSave: nil
            )
        )
    }

    func testMacOSAIEnhancementOpenRouterModelRefreshPlanAppliesRuntimeState() {
        let refreshedPlan = VoiceInkAIEnhancementModelRefreshPlan(
            refreshedModelNames: [
                "anthropic/claude-3.5-sonnet",
                "openai/gpt-4o"
            ],
            selectedModelToSave: "anthropic/claude-3.5-sonnet"
        )

        var events: [String] = []

        refreshedPlan.applyOpenRouterRuntimeState(
            setOpenRouterModels: { models in
                events.append("models:\(models.joined(separator: ","))")
            },
            applyPersistence: { plan in
                events.append("persist:\(plan.refreshedModelNames.joined(separator: ","))")
                return plan.selectedModelToSave
            },
            setSelectedOpenRouterModel: { model in
                events.append("select:\(model)")
            },
            postSettingsChanged: {
                events.append("settings")
            },
            sendObjectWillChange: {
                events.append("willChange")
            }
        )

        XCTAssertEqual(events, [
            "models:anthropic/claude-3.5-sonnet,openai/gpt-4o",
            "persist:anthropic/claude-3.5-sonnet,openai/gpt-4o",
            "select:anthropic/claude-3.5-sonnet",
            "settings",
            "willChange"
        ])

        events = []
        VoiceInkAIEnhancementModelRefreshPlan.failed.applyOpenRouterRuntimeState(
            setOpenRouterModels: { models in
                events.append("models:\(models.joined(separator: ","))")
            },
            applyPersistence: { plan in
                events.append("persist:\(plan.refreshedModelNames.joined(separator: ","))")
                return plan.selectedModelToSave
            },
            setSelectedOpenRouterModel: { model in
                events.append("select:\(model)")
            },
            postSettingsChanged: {
                events.append("settings")
            },
            sendObjectWillChange: {
                events.append("willChange")
            }
        )

        XCTAssertEqual(events, [
            "models:",
            "persist:",
            "willChange"
        ])
    }

    func testMacOSAIEnhancementProviderVerificationDispatchesAreShared() async {
        let customRequestURL = URL(string: "https://api.example.com/v1/chat/completions")!
        let expectedDispatches: [(VoiceInkAIEnhancementProviderKind, VoiceInkAPIKeyVerificationResult, [String])] = [
            (.anthropic, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "anthropic"), ["anthropic:resolved-key"]),
            (.assemblyAI, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:assemblyAI"]),
            (.cerebras, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openai"), ["openai:https://api.example.com/v1/chat/completions:resolved-key:shared-model"]),
            (.custom, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openai"), ["openai:https://api.example.com/v1/chat/completions:resolved-key:shared-model"]),
            (.deepgram, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:deepgram"]),
            (.elevenLabs, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:elevenLabs"]),
            (.gemini, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:gemini"]),
            (.groq, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openai"), ["openai:https://api.example.com/v1/chat/completions:resolved-key:shared-model"]),
            (.localCLI, VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: VoiceInkAIEnhancementProviderKind.localCLI.unsupportedAPIKeyVerificationMessage), []),
            (.mistral, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:mistral"]),
            (.ollama, VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: VoiceInkAIEnhancementProviderKind.ollama.unsupportedAPIKeyVerificationMessage), []),
            (.openAI, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openai"), ["openai:https://api.example.com/v1/chat/completions:resolved-key:shared-model"]),
            (.openRouter, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "openrouter"), ["openrouter:resolved-key:shared-model"]),
            (.soniox, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:soniox"]),
            (.speechmatics, VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:speechmatics"])
        ]

        XCTAssertEqual(VoiceInkAIEnhancementProviderKind.allCases.count, expectedDispatches.count)

        for (provider, expectedResult, expectedCalls) in expectedDispatches {
            await assertVerificationDispatch(
                VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                    provider: provider,
                    currentModel: "shared-model",
                    requestURL: customRequestURL
                ),
                expectedResult: expectedResult,
                expectedCalls: expectedCalls
            )
        }
    }

    func testMacOSAIEnhancementExecutionPlanAppliesAdapters() async throws {
        try await withIsolatedDefaultsAsyncThrows { defaults in
            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL(
                "https://api.example.com/v1/chat/completions",
                to: defaults
            )

            XCTAssertEqual(VoiceInkAIEnhancementProviderKind.selectableTextEnhancementProviders, [
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
            ])

            let localExpectations: [(VoiceInkAIEnhancementProviderKind, String, String)] = [
                (.ollama, "mistral", "ollama:mistral"),
                (.localCLI, "local-cli", "localCLI:local-cli"),
                (.anthropic, "claude-sonnet-4-5", "anthropicMessages:claude-sonnet-4-5")
            ]

            for (provider, model, expectedSummary) in localExpectations {
                let summary = try await executionSummary(
                    for: VoiceInkAIEnhancementRequestExecutionPlan.planning(
                        provider: provider,
                        modelName: model,
                        defaults: defaults
                    )
                )
                XCTAssertEqual(summary, expectedSummary)
            }

            let openAICompatibleExpectations: [(VoiceInkAIEnhancementProviderKind, String, OpenAICompatibleRequestSummary)] = [
                (
                    .cerebras,
                    "gpt-oss-120b",
                    OpenAICompatibleRequestSummary(
                        requestURL: VoiceInkAIModelProvider.cerebras.postProcessingRequestURL!,
                        temperature: 0.3,
                        reasoningEffort: "low",
                        hasExtraBodyParameters: true,
                        includeReasoning: nil
                    )
                ),
                (
                    .custom,
                    "custom-model",
                    OpenAICompatibleRequestSummary(
                        requestURL: URL(string: "https://api.example.com/v1/chat/completions")!,
                        temperature: 0.3,
                        reasoningEffort: nil,
                        hasExtraBodyParameters: false,
                        includeReasoning: nil
                    )
                ),
                (
                    .gemini,
                    "gemini-2.5-pro",
                    OpenAICompatibleRequestSummary(
                        requestURL: VoiceInkAIModelProvider.gemini.postProcessingRequestURL!,
                        temperature: 0.3,
                        reasoningEffort: "minimal",
                        hasExtraBodyParameters: false,
                        includeReasoning: nil
                    )
                ),
                (
                    .groq,
                    "openai/gpt-oss-120b",
                    OpenAICompatibleRequestSummary(
                        requestURL: VoiceInkAIModelProvider.groq.postProcessingRequestURL!,
                        temperature: 0.3,
                        reasoningEffort: "low",
                        hasExtraBodyParameters: true,
                        includeReasoning: false
                    )
                ),
                (
                    .mistral,
                    "mistral-large-latest",
                    OpenAICompatibleRequestSummary(
                        requestURL: VoiceInkAIModelProvider.mistral.postProcessingRequestURL!,
                        temperature: 0.3,
                        reasoningEffort: nil,
                        hasExtraBodyParameters: false,
                        includeReasoning: nil
                    )
                ),
                (
                    .openAI,
                    "gpt-5.5",
                    OpenAICompatibleRequestSummary(
                        requestURL: VoiceInkAIModelProvider.openAI.postProcessingRequestURL!,
                        temperature: 1.0,
                        reasoningEffort: "none",
                        hasExtraBodyParameters: false,
                        includeReasoning: nil
                    )
                ),
                (
                    .openRouter,
                    "openai/gpt-5.5",
                    OpenAICompatibleRequestSummary(
                        requestURL: VoiceInkAIModelProvider.openRouter.postProcessingRequestURL!,
                        temperature: 0.3,
                        reasoningEffort: nil,
                        hasExtraBodyParameters: false,
                        includeReasoning: nil
                    )
                )
            ]

            for (provider, model, expectedSummary) in openAICompatibleExpectations {
                let summary = try await openAICompatibleRequestSummary(
                    for: VoiceInkAIEnhancementRequestExecutionPlan.planning(
                        provider: provider,
                        modelName: model,
                        defaults: defaults
                    )
                )
                XCTAssertEqual(summary, expectedSummary)
            }
        }
    }

    private func executionSummary(for plan: VoiceInkAIEnhancementRequestExecutionPlan) async throws -> String {
        try await plan.applyRuntimeState(
            ollama: { modelName in "ollama:\(modelName)" },
            localCLI: { modelName in "localCLI:\(modelName)" },
            anthropicMessages: { modelName in "anthropicMessages:\(modelName)" },
            openAICompatibleChatCompletions: { modelName, requestURL, _ in
                "openAICompatibleChatCompletions:\(modelName):\(requestURL.absoluteString)"
            }
        )
    }

    private struct OpenAICompatibleRequestSummary: Equatable {
        let requestURL: URL
        let temperature: Double
        let reasoningEffort: String?
        let hasExtraBodyParameters: Bool
        let includeReasoning: Bool?
    }

    private func openAICompatibleRequestSummary(
        for plan: VoiceInkAIEnhancementRequestExecutionPlan
    ) async throws -> OpenAICompatibleRequestSummary? {
        try await plan.applyRuntimeState(
            ollama: { _ in nil },
            localCLI: { _ in nil },
            anthropicMessages: { _ in nil },
            openAICompatibleChatCompletions: { _, requestURL, requestParameters in
                OpenAICompatibleRequestSummary(
                    requestURL: requestURL,
                    temperature: requestParameters.temperature,
                    reasoningEffort: requestParameters.reasoningEffort,
                    hasExtraBodyParameters: requestParameters.extraBodyParameters != nil,
                    includeReasoning: requestParameters.extraBodyParameters?["include_reasoning"] as? Bool
                )
            }
        )
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

    private func withIsolatedDefaultsAsync(_ run: (UserDefaults) async -> Void) async {
        let suiteName = "VoiceInkCore.AIProviderCatalogTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        await run(defaults)
    }

    private func withIsolatedDefaultsAsyncThrows(_ run: (UserDefaults) async throws -> Void) async rethrows {
        let suiteName = "VoiceInkCore.AIProviderCatalogTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        try await run(defaults)
    }
}
