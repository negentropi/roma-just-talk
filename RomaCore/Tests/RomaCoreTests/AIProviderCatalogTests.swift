import Foundation
@testable import RomaCore

final class AIProviderCatalogTests: XCTestCase {
    func testAIEnhancementProviderKeyChangeRequestPreservesMacOSNotificationName() {
        XCTAssertEqual(
            RomaAIEnhancementProviderKeyChangeRequest.notificationName,
            Notification.Name("aiProviderKeyChanged")
        )
    }

    func testMacOSAIEnhancementProviderMapsToSharedModelProvider() {
        XCTAssertEqual(RomaAIEnhancementProviderKind.anthropic.aiModelProvider, .anthropic)
        XCTAssertEqual(RomaAIEnhancementProviderKind.cerebras.aiModelProvider, .cerebras)
        XCTAssertEqual(RomaAIEnhancementProviderKind.deepgram.aiModelProvider, .deepgram)
        XCTAssertEqual(RomaAIEnhancementProviderKind.openRouter.aiModelProvider, .openRouter)
        XCTAssertNil(RomaAIEnhancementProviderKind.ollama.aiModelProvider)
        XCTAssertNil(RomaAIEnhancementProviderKind.localCLI.aiModelProvider)
        XCTAssertNil(RomaAIEnhancementProviderKind.custom.aiModelProvider)
    }

    func testMacOSAIEnhancementCredentialStateResolutionPlanAppliesRuntimeState() {
        var loadedProviders: [String] = []
        var credentialStates: [RomaAIEnhancementCredentialState] = []

        RomaAIEnhancementCredentialStateResolutionPlan.resolving(provider: .groq)
            .applyRuntimeState(
                loadSavedAPIKey: {
                    loadedProviders.append($0)
                    return "saved-groq-key"
                },
                isLocalCLIConfigured: false,
                setCredentialState: { credentialStates.append($0) }
            )

        XCTAssertEqual(loadedProviders, [RomaAIEnhancementProviderKind.groq.rawValue])
        XCTAssertEqual(credentialStates, [
            RomaAIEnhancementCredentialState(apiKey: "saved-groq-key", isAPIKeyValid: true)
        ])

        loadedProviders = []
        credentialStates = []

        RomaAIEnhancementCredentialStateResolutionPlan.resolving(provider: .localCLI)
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
            RomaAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: true)
        ])
    }

    func testMacOSAIEnhancementCredentialStateHandlesMissingAndNoKeyProviders() {
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.groq.textEnhancementCredentialState(
                savedAPIKey: nil,
                isLocalCLIConfigured: false
            ),
            RomaAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.localCLI.textEnhancementCredentialState(
                savedAPIKey: nil,
                isLocalCLIConfigured: false
            ),
            RomaAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.ollama.textEnhancementCredentialState(
                savedAPIKey: nil,
                isLocalCLIConfigured: false
            ),
            RomaAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: true)
        )
    }

    func testLocalCLITemplatesPreserveRawValuesDisplayNamesAndCommands() {
        XCTAssertEqual(RomaLocalCLITemplate.allCases, [.pi, .claude, .codex, .copilot])
        XCTAssertEqual(RomaLocalCLITemplate.pi.rawValue, "pi")
        XCTAssertEqual(RomaLocalCLITemplate.claude.rawValue, "claude")
        XCTAssertEqual(RomaLocalCLITemplate.codex.rawValue, "codex")
        XCTAssertEqual(RomaLocalCLITemplate.copilot.rawValue, "copilot")

        XCTAssertEqual(RomaLocalCLITemplate.pi.displayName, "Pi")
        XCTAssertEqual(RomaLocalCLITemplate.claude.displayName, "Claude")
        XCTAssertEqual(RomaLocalCLITemplate.codex.displayName, "Codex")
        XCTAssertEqual(RomaLocalCLITemplate.copilot.displayName, "Copilot")

        XCTAssertEqual(
            RomaLocalCLITemplate.pi.commandTemplate,
            "pi -ne -ns -p --no-tools --system-prompt \"$ROMA_SYSTEM_PROMPT\" \"$ROMA_USER_PROMPT\""
        )
        XCTAssertEqual(RomaLocalCLITemplate.claude.commandTemplate, "claude -p \"$ROMA_FULL_PROMPT\"")
        XCTAssertEqual(
            RomaLocalCLITemplate.codex.commandTemplate,
            "TMPFILE=$(mktemp) && codex exec --skip-git-repo-check --output-last-message \"$TMPFILE\" \"$ROMA_FULL_PROMPT\" > /dev/null 2>&1 && cat \"$TMPFILE\" && rm \"$TMPFILE\""
        )
        XCTAssertEqual(
            RomaLocalCLITemplate.copilot.commandTemplate,
            "copilot -p \"$ROMA_FULL_PROMPT\" -s --no-ask-user --available-tools=__none__ 2>/dev/null"
        )
    }

    func testLocalCLIPreferencePreservesKeysDefaultsAndRoundTrips() {
        XCTAssertEqual(RomaLocalCLIPreference.commandTemplateKey, "localCLICommandTemplate")
        XCTAssertEqual(RomaLocalCLIPreference.selectedTemplateKey, "localCLISelectedTemplate")
        XCTAssertEqual(RomaLocalCLIPreference.timeoutSecondsKey, "localCLITimeoutSeconds")
        XCTAssertEqual(RomaLocalCLIPreference.defaultTimeoutSeconds, 45)
        XCTAssertEqual(RomaLocalCLIPreference.minimumTimeoutSeconds, 5)
        XCTAssertEqual(RomaLocalCLIPreference.timeoutOptions, [15, 30, 45, 60, 90, 120, 180, 300])

        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaLocalCLIPreference.commandTemplate(from: defaults), "")
            XCTAssertEqual(RomaLocalCLIPreference.selectedTemplate(from: defaults), .pi)
            XCTAssertEqual(RomaLocalCLIPreference.timeoutSeconds(from: defaults), 45)

            defaults.set(3, forKey: RomaLocalCLIPreference.timeoutSecondsKey)
            XCTAssertEqual(RomaLocalCLIPreference.timeoutSeconds(from: defaults), 3)

            RomaLocalCLIPreference.saveCommandTemplate("codex exec \"$ROMA_FULL_PROMPT\"", to: defaults)
            RomaLocalCLIPreference.saveSelectedTemplate(.codex, to: defaults)
            RomaLocalCLIPreference.saveTimeoutSeconds(3, to: defaults)

            XCTAssertEqual(
                RomaLocalCLIPreference.commandTemplate(from: defaults),
                "codex exec \"$ROMA_FULL_PROMPT\""
            )
            XCTAssertEqual(RomaLocalCLIPreference.selectedTemplate(from: defaults), .codex)
            XCTAssertEqual(RomaLocalCLIPreference.timeoutSeconds(from: defaults), 5)

            RomaLocalCLIPreference.saveTimeoutSeconds(90, to: defaults)
            XCTAssertEqual(RomaLocalCLIPreference.timeoutSeconds(from: defaults), 90)

            RomaLocalCLIPreference.clear(from: defaults)
            XCTAssertEqual(RomaLocalCLIPreference.commandTemplate(from: defaults), "")
            XCTAssertEqual(RomaLocalCLIPreference.selectedTemplate(from: defaults), .pi)
            XCTAssertEqual(RomaLocalCLIPreference.timeoutSeconds(from: defaults), 45)
        }
    }

    func testLocalCLICommandConfigurationAndPromptPolicy() {
        XCTAssertFalse(RomaLocalCLIPreference.isCommandConfigured(""))
        XCTAssertFalse(RomaLocalCLIPreference.isCommandConfigured(" \n\t "))
        XCTAssertTrue(RomaLocalCLIPreference.isCommandConfigured("pi \"$ROMA_FULL_PROMPT\""))
        XCTAssertEqual(RomaLocalCLIPreference.boundedTimeoutSeconds(1), 5)
        XCTAssertEqual(RomaLocalCLIPreference.boundedTimeoutSeconds(30), 30)
        XCTAssertEqual(RomaLocalCLIPreference.timeoutLabel(for: 120), "120s")
        XCTAssertEqual(RomaLocalCLIPreference.cleanedOutput(" \n result \t"), "result")

        XCTAssertEqual(
            RomaLocalCLIPreference.fullPrompt(systemPrompt: "System", userPrompt: "User"),
            """
            <SYSTEM_PROMPT>
            System
            </SYSTEM_PROMPT>

            <USER_PROMPT>
            User
            </USER_PROMPT>
            """
        )
    }

    func testLocalCLICommandFailureClassificationTrimsStderrAndDetectsMissingCommands() {
        XCTAssertEqual(
            RomaLocalCLIPreference.commandFailureError(
                terminationStatus: 127,
                stderr: "",
                commandTemplate: "missing-cli"
            ),
            .commandNotFound("missing-cli")
        )
        XCTAssertEqual(
            RomaLocalCLIPreference.commandFailureError(
                terminationStatus: 1,
                stderr: " zsh: command not found: missing-cli\n",
                commandTemplate: "missing-cli"
            ),
            .commandNotFound("zsh: command not found: missing-cli")
        )
        XCTAssertEqual(
            RomaLocalCLIPreference.commandFailureError(
                terminationStatus: 3,
                stderr: " bad input\n",
                commandTemplate: "cli"
            ),
            .nonZeroExit(status: 3, stderr: "bad input")
        )
    }

    func testProviderAPIKeyVerificationProgressPresentsSharedFeedback() {
        XCTAssertTrue(RomaProviderAPIKeyVerificationProgress.verifying.isVerifying)
        XCTAssertFalse(RomaProviderAPIKeyVerificationProgress.idle.isVerifying)
        XCTAssertTrue(RomaProviderAPIKeyVerificationProgress.success.isSuccess)

        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.verifying.macOSVerifyButtonTitle,
            "Verifying..."
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.success.macOSVerifyButtonTitle,
            "Verify"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.success.macOSVerifyButtonSystemImageName,
            "checkmark"
        )

        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.success.macOSInlineFeedback,
            RomaProviderAPIKeyVerificationFeedback(
                text: "API key verified successfully!",
                tone: .success
            )
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.failure(message: nil).macOSInlineFeedback,
            RomaProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                tone: .failure
            )
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.unsupportedProviderFailure.macOSInlineFeedback?.text,
            "Unsupported provider"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback,
            RomaProviderAPIKeyVerificationFeedback(
                text: "Key verified",
                systemImageName: "checkmark.seal.fill",
                tone: .success
            )
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback.effectiveSystemImageName,
            "checkmark.seal.fill"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationFeedback(text: "FYI", tone: .success).effectiveSystemImageName,
            "info.circle"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.success.iOSResultFeedback,
            RomaProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback
        )
        XCTAssertEqual(
            RomaProviderAPIKeyVerificationProgress.failure(message: "bad").iOSResultFeedback,
            RomaProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                systemImageName: "xmark.seal",
                tone: .failure
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyDraftUsesSharedBlankPolicy() {
        let draft = RomaAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " \n\t "
        )

        XCTAssertFalse(draft.hasEnteredKey)
        XCTAssertFalse(draft.canVerify)
        XCTAssertNil(draft.keyToSaveAfterSuccessfulVerification)
        XCTAssertNil(draft.resolvedVerificationCandidate(environment: [:]))
    }

    func testMacOSAIEnhancementAPIKeyDraftResolvesEnvironmentReferences() {
        let draft = RomaAIEnhancementAPIKeyDraft(
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
        let draft = RomaAIEnhancementAPIKeyDraft(
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
        let draft = RomaAIEnhancementAPIKeyDraft(
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
        let environmentDraft = RomaAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " $GROQ_API_KEY "
        )
        let missingDraft = RomaAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " $MISSING_GROQ_KEY "
        )
        let noKeyProviderDraft = RomaAIEnhancementAPIKeyDraft(
            provider: .ollama,
            enteredKey: "ignored-key"
        )

        XCTAssertEqual(
            environmentDraft.verificationRequestPlan(environment: ["GROQ_API_KEY": "resolved-key"]),
            RomaAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: "resolved-key",
                immediateResult: nil
            )
        )
        XCTAssertEqual(
            missingDraft.verificationRequestPlan(environment: [:]),
            RomaAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: RomaAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: RomaAIEnhancementProviderKind.missingVerificationCandidateMessage
                )
            )
        )
        XCTAssertEqual(
            noKeyProviderDraft.verificationRequestPlan(environment: [:]),
            RomaAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationRequestPlanAppliesRuntimeState() {
        var completionResults: [RomaAPIKeyVerificationResult] = []
        var resolvedKeys: [String] = []

        RomaAIEnhancementAPIKeyVerificationRequestPlan(
            resolvedKeyToVerify: nil,
            immediateResult: RomaAPIKeyVerificationResult(isValid: false, errorMessage: "missing")
        )
        .applyRuntimeState(
            completeImmediateResult: { completionResults.append($0) },
            verifyResolvedKey: { resolvedKeys.append($0) }
        )

        XCTAssertEqual(completionResults, [
            RomaAPIKeyVerificationResult(isValid: false, errorMessage: "missing")
        ])
        XCTAssertTrue(resolvedKeys.isEmpty)

        completionResults = []
        resolvedKeys = []

        RomaAIEnhancementAPIKeyVerificationRequestPlan(
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

    func testMacOSAIEnhancementAPIKeyVerificationDispatchPlanAppliesAdapters() async {
        let customRequestURL = URL(string: "https://api.example.com/v1/chat/completions")!

        await assertVerificationDispatch(
            RomaAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .custom,
                currentModel: "custom-model",
                requestURL: nil
            ),
            expectedResult: RomaAPIKeyVerificationResult(
                isValid: false,
                errorMessage: RomaAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage
            ),
            expectedCalls: []
        )
        await assertVerificationDispatch(
            RomaAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .gemini,
                currentModel: "gemini-2.5-pro",
                requestURL: nil
            ),
            expectedResult: RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared"),
            expectedCalls: [
                "shared:resolved-key:gemini"
            ]
        )
        await assertVerificationDispatch(
            RomaAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .anthropic,
                currentModel: "claude-sonnet-4-20250514",
                requestURL: nil
            ),
            expectedResult: RomaAPIKeyVerificationResult(isValid: true, errorMessage: "anthropic"),
            expectedCalls: [
                "anthropic:resolved-key"
            ]
        )
        await assertVerificationDispatch(
            RomaAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .custom,
                currentModel: "custom-model",
                requestURL: customRequestURL
            ),
            expectedResult: RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openai"),
            expectedCalls: [
                "openai:https://api.example.com/v1/chat/completions:resolved-key:custom-model"
            ]
        )
        await assertVerificationDispatch(
            RomaAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: .openRouter,
                currentModel: "openai/gpt-5.5",
                requestURL: nil
            ),
            expectedResult: RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openrouter"),
            expectedCalls: [
                "openrouter:resolved-key:openai/gpt-5.5"
            ]
        )
    }

    private func assertVerificationDispatch(
        _ plan: RomaAIEnhancementAPIKeyVerificationDispatchPlan,
        expectedResult: RomaAPIKeyVerificationResult,
        expectedCalls: [String]
    ) async {
        var calls: [String] = []
        let result = await plan.verifyResolvedAPIKey(
            "resolved-key",
            verifySharedProvider: { key, provider in
                calls.append("shared:\(key):\(provider.rawValue)")
                return RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared")
            },
            verifyAnthropicMessages: { key in
                calls.append("anthropic:\(key)")
                return RomaAPIKeyVerificationResult(isValid: true, errorMessage: "anthropic")
            },
            verifyOpenAICompatibleModels: { requestURL, key, model in
                calls.append("openai:\(requestURL.absoluteString):\(key):\(model)")
                return RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openai")
            },
            verifyOpenRouterModels: { key, model in
                calls.append("openrouter:\(key):\(model)")
                return RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openrouter")
            }
        )

        XCTAssertEqual(result, expectedResult)
        XCTAssertEqual(calls, expectedCalls)
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanSavesEnteredReferenceAndAppliesResolvedRuntimeKey() {
        let draft = RomaAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: " $GROQ_API_KEY "
        )

        XCTAssertEqual(
            draft.verificationApplicationPlan(
                for: RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil),
                resolvedRuntimeKey: "resolved-key"
            ),
            RomaAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: true,
                runtimeAPIKey: "resolved-key",
                keyToSave: "$GROQ_API_KEY",
                providerKeyStorageNameToSave: RomaAIEnhancementProviderKind.groq.rawValue,
                errorMessage: nil
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanPropagatesFailureWithoutSaving() {
        let draft = RomaAIEnhancementAPIKeyDraft(
            provider: .groq,
            enteredKey: "bad-key"
        )

        XCTAssertEqual(
            draft.verificationApplicationPlan(
                for: RomaAPIKeyVerificationResult(isValid: false, errorMessage: "invalid"),
                resolvedRuntimeKey: "bad-key"
            ),
            RomaAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: false,
                runtimeAPIKey: nil,
                keyToSave: nil,
                providerKeyStorageNameToSave: nil,
                errorMessage: "invalid"
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanNoOpsForNoKeyProviders() {
        let draft = RomaAIEnhancementAPIKeyDraft(
            provider: .ollama,
            enteredKey: "ignored-key"
        )

        XCTAssertEqual(
            draft.verificationApplicationPlan(
                for: RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil),
                resolvedRuntimeKey: "ignored-key"
            ),
            RomaAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: true,
                runtimeAPIKey: nil,
                keyToSave: nil,
                providerKeyStorageNameToSave: nil,
                errorMessage: nil
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanBuildsSuccessPersistencePlan() {
        let successPlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: RomaAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: false,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: "invalid"
        )

        XCTAssertEqual(
            successPlan.successPersistencePlan,
            RomaAIEnhancementAPIKeyVerificationPersistencePlan(
                runtimeAPIKey: "resolved-key",
                keyToSave: "$GROQ_API_KEY",
                providerKeyStorageNameToSave: RomaAIEnhancementProviderKind.groq.rawValue
            )
        )
        XCTAssertNil(failurePlan.successPersistencePlan)
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanBuildsServiceStateApplicationPlan() {
        let successPlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: RomaAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: false,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: "invalid"
        )
        let noKeyProviderPlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: nil
        )

        XCTAssertEqual(
            successPlan.serviceStateApplicationPlan,
            RomaAIEnhancementAPIKeyVerificationServiceStatePlan(
                apiKeyToApply: "resolved-key",
                isAPIKeyValid: true,
                shouldPostProviderKeyChanged: true,
                completionResult: RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        )
        XCTAssertEqual(
            failurePlan.serviceStateApplicationPlan,
            RomaAIEnhancementAPIKeyVerificationServiceStatePlan(
                apiKeyToApply: nil,
                isAPIKeyValid: false,
                shouldPostProviderKeyChanged: false,
                completionResult: RomaAPIKeyVerificationResult(isValid: false, errorMessage: "invalid")
            )
        )
        XCTAssertEqual(
            noKeyProviderPlan.serviceStateApplicationPlan,
            RomaAIEnhancementAPIKeyVerificationServiceStatePlan(
                apiKeyToApply: nil,
                isAPIKeyValid: true,
                shouldPostProviderKeyChanged: false,
                completionResult: RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanAppliesSuccessPersistence() {
        let successPlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: RomaAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let storedKeySuccessPlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: nil,
            providerKeyStorageNameToSave: RomaAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
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
        XCTAssertEqual(savedKeys.map { $0.provider }, [RomaAIEnhancementProviderKind.groq.rawValue])

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
        let successPlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: RomaAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: false,
            runtimeAPIKey: nil,
            keyToSave: nil,
            providerKeyStorageNameToSave: nil,
            errorMessage: "invalid"
        )

        var appliedAPIKeys: [String] = []
        var appliedValidities: [Bool] = []
        var providerKeyChangedPostCount = 0
        var completionResults: [RomaAPIKeyVerificationResult] = []

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
            RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil)
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
            RomaAPIKeyVerificationResult(isValid: false, errorMessage: "invalid")
        ])
    }

    func testMacOSAIEnhancementAPIKeyVerificationPlanAppliesRuntimeState() {
        let successPlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: "resolved-key",
            keyToSave: "$GROQ_API_KEY",
            providerKeyStorageNameToSave: RomaAIEnhancementProviderKind.groq.rawValue,
            errorMessage: nil
        )
        let failurePlan = RomaAIEnhancementAPIKeyVerificationApplicationPlan(
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
            RomaAIEnhancementAPIKeyClearPlan.clearing(provider: .groq),
            RomaAIEnhancementAPIKeyClearPlan(
                provider: .groq,
                providerKeyStorageNameToDelete: RomaAIEnhancementProviderKind.groq.rawValue,
                credentialStateAfterClear: RomaAIEnhancementCredentialState(
                    apiKey: "",
                    isAPIKeyValid: false
                )
            )
        )
        XCTAssertEqual(
            RomaAIEnhancementAPIKeyClearPlan.clearing(provider: .custom),
            RomaAIEnhancementAPIKeyClearPlan(
                provider: .custom,
                providerKeyStorageNameToDelete: RomaAIEnhancementProviderKind.custom.rawValue,
                credentialStateAfterClear: RomaAIEnhancementCredentialState(
                    apiKey: "",
                    isAPIKeyValid: false
                )
            )
        )

        XCTAssertNil(RomaAIEnhancementAPIKeyClearPlan.clearing(provider: .ollama))
        XCTAssertNil(RomaAIEnhancementAPIKeyClearPlan.clearing(provider: .localCLI))
    }

    func testMacOSAIEnhancementAPIKeyClearPlanBuildsPersistenceAndStatePlans() {
        let clearPlan = RomaAIEnhancementAPIKeyClearPlan(
            provider: .groq,
            providerKeyStorageNameToDelete: RomaAIEnhancementProviderKind.groq.rawValue,
            credentialStateAfterClear: RomaAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )

        XCTAssertEqual(
            clearPlan.persistencePlan,
            RomaAIEnhancementAPIKeyClearPersistencePlan(
                providerKeyStorageNameToDelete: RomaAIEnhancementProviderKind.groq.rawValue
            )
        )
        XCTAssertEqual(
            clearPlan.serviceStateApplicationPlan,
            RomaAIEnhancementAPIKeyClearServiceStatePlan(
                credentialStateAfterClear: RomaAIEnhancementCredentialState(
                    apiKey: "",
                    isAPIKeyValid: false
                ),
                shouldPostProviderKeyChanged: true
            )
        )
    }

    func testMacOSAIEnhancementAPIKeyClearPlanAppliesPersistence() {
        let clearPlan = RomaAIEnhancementAPIKeyClearPlan(
            provider: .groq,
            providerKeyStorageNameToDelete: RomaAIEnhancementProviderKind.groq.rawValue,
            credentialStateAfterClear: RomaAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )

        var deletedProviders: [String] = []

        clearPlan.applyClearPersistence { provider in
            deletedProviders.append(provider)
        }

        XCTAssertEqual(deletedProviders, [RomaAIEnhancementProviderKind.groq.rawValue])
    }

    func testMacOSAIEnhancementAPIKeyClearServiceStatePlanAppliesRuntimeState() {
        let clearPlan = RomaAIEnhancementAPIKeyClearPlan(
            provider: .groq,
            providerKeyStorageNameToDelete: RomaAIEnhancementProviderKind.groq.rawValue,
            credentialStateAfterClear: RomaAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )

        var appliedCredentialStates: [RomaAIEnhancementCredentialState] = []
        var providerKeyChangedPostCount = 0

        clearPlan.serviceStateApplicationPlan.apply(
            setCredentialState: { appliedCredentialStates.append($0) },
            postProviderKeyChanged: { providerKeyChangedPostCount += 1 }
        )

        XCTAssertEqual(appliedCredentialStates, [
            RomaAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        ])
        XCTAssertEqual(providerKeyChangedPostCount, 1)
    }

    func testMacOSAIEnhancementAPIKeyClearPlanAppliesRuntimeState() {
        let clearPlan = RomaAIEnhancementAPIKeyClearPlan(
            provider: .groq,
            providerKeyStorageNameToDelete: RomaAIEnhancementProviderKind.groq.rawValue,
            credentialStateAfterClear: RomaAIEnhancementCredentialState(
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
        let state = RomaAIEnhancementAPIKeyFormState(enteredKey: " $GROQ_API_KEY ")
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
        let state = RomaAIEnhancementAPIKeyFormState(
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
        let state = RomaAIEnhancementAPIKeyFormState(enteredKey: "bad-key")

        XCTAssertEqual(
            state.verificationFailureAlertMessage(
                for: RomaAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: "invalid key"
                )
            ),
            "invalid key"
        )
        XCTAssertEqual(
            state.verificationFailureAlertMessage(
                for: RomaAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: nil
                )
            ),
            "Verification failed"
        )
    }

    func testMacOSAIEnhancementAPIKeyFailureMessagesAreShared() {
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.missingVerificationCandidateMessage,
            "Environment variable is missing or empty"
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage,
            "Invalid or missing base URL configuration"
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.localCLI.unsupportedAPIKeyVerificationMessage,
            "Local CLI does not support API key verification."
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.custom.invalidTextEnhancementRequestURLMessage,
            "Custom has an invalid API endpoint URL. Please update it in AI settings."
        )
    }

    func testMacOSAIEnhancementSelectableTextProvidersAreShared() {
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.selectableTextEnhancementProviders,
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
        XCTAssertFalse(RomaAIEnhancementProviderKind.assemblyAI.isSelectableForTextEnhancement)
        XCTAssertFalse(RomaAIEnhancementProviderKind.deepgram.isSelectableForTextEnhancement)
        XCTAssertFalse(RomaAIEnhancementProviderKind.elevenLabs.isSelectableForTextEnhancement)
        XCTAssertFalse(RomaAIEnhancementProviderKind.soniox.isSelectableForTextEnhancement)
        XCTAssertFalse(RomaAIEnhancementProviderKind.speechmatics.isSelectableForTextEnhancement)
    }

    func testMacOSAIEnhancementConnectedProvidersUseSharedPolicy() {
        let allProviderKeyNames = Set(RomaAIEnhancementProviderKind.textEnhancementProviderKeyStorageNamesToCheck)

        XCTAssertEqual(
            RomaAIEnhancementProviderKind.textEnhancementProviderKeyStorageNamesToCheck,
            [
                RomaAIEnhancementProviderKind.cerebras.rawValue,
                RomaAIEnhancementProviderKind.groq.rawValue,
                RomaAIEnhancementProviderKind.gemini.rawValue,
                RomaAIEnhancementProviderKind.anthropic.rawValue,
                RomaAIEnhancementProviderKind.openAI.rawValue,
                RomaAIEnhancementProviderKind.openRouter.rawValue,
                RomaAIEnhancementProviderKind.mistral.rawValue,
                RomaAIEnhancementProviderKind.custom.rawValue
            ]
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.connectedTextEnhancementProviders(
                providerKeyStorageNamesWithKeys: allProviderKeyNames,
                isOllamaConnected: true,
                isLocalCLIConfigured: true
            ),
            RomaAIEnhancementProviderKind.selectableTextEnhancementProviders
        )

        XCTAssertEqual(
            RomaAIEnhancementProviderKind.connectedTextEnhancementProviders(
                providerKeyStorageNamesWithKeys: Set([
                    RomaAIEnhancementProviderKind.groq.rawValue,
                    RomaAIEnhancementProviderKind.custom.rawValue
                ]),
                isOllamaConnected: false,
                isLocalCLIConfigured: false
            ),
            [.groq, .custom]
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.connectedTextEnhancementProviders(
                providerKeyStorageNamesWithKeys: [],
                isOllamaConnected: true,
                isLocalCLIConfigured: false
            ),
            [.ollama]
        )
        XCTAssertTrue(
            RomaAIEnhancementProviderKind.localCLI.isConnectedForTextEnhancement(
                providerKeyStorageNamesWithKeys: [],
                isOllamaConnected: false,
                isLocalCLIConfigured: true
            )
        )
        XCTAssertFalse(
            RomaAIEnhancementProviderKind.assemblyAI.isConnectedForTextEnhancement(
                providerKeyStorageNamesWithKeys: allProviderKeyNames,
                isOllamaConnected: true,
                isLocalCLIConfigured: true
            )
        )
    }

    func testMacOSAIEnhancementConnectionStatusUsesProviderState() {
        let presentation = RomaAIEnhancementProviderSettingsPresentation.macOS

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
            .status(text: presentation.connectedText, tone: .connected)
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                provider: .ollama,
                isAPIKeyValid: false,
                isCheckingOllama: false,
                hasOllamaModels: false
            ),
            .status(text: presentation.disconnectedText, tone: .disconnected)
        )
        XCTAssertEqual(
            presentation.connectionStatus(
                provider: .groq,
                isAPIKeyValid: true,
                isCheckingOllama: false,
                hasOllamaModels: false
            ),
            .status(text: presentation.connectedText, tone: .connected)
        )
        XCTAssertNil(
            presentation.connectionStatus(
                provider: .groq,
                isAPIKeyValid: false,
                isCheckingOllama: false,
                hasOllamaModels: false
            )
        )
    }

    func testMacOSAIEnhancementModelPickerFollowsProviderCapabilities() {
        let presentation = RomaAIEnhancementProviderSettingsPresentation.macOS

        XCTAssertEqual(
            presentation.modelPickerPresentation(provider: .openRouter, availableModels: []),
            RomaAIEnhancementModelPickerPresentation(
                isModelPickerVisible: false,
                isRefreshButtonVisible: true,
                emptyStateText: presentation.noModelsLoadedText
            )
        )
        XCTAssertEqual(
            presentation.modelPickerPresentation(provider: .openRouter, availableModels: ["model"]),
            RomaAIEnhancementModelPickerPresentation(
                isModelPickerVisible: true,
                isRefreshButtonVisible: true,
                emptyStateText: nil
            )
        )
        XCTAssertEqual(
            presentation.modelPickerPresentation(provider: .groq, availableModels: ["model"]),
            RomaAIEnhancementModelPickerPresentation(
                isModelPickerVisible: true,
                isRefreshButtonVisible: false,
                emptyStateText: nil
            )
        )
        XCTAssertEqual(
            presentation.modelPickerPresentation(provider: .custom, availableModels: ["model"]),
            RomaAIEnhancementModelPickerPresentation(
                isModelPickerVisible: false,
                isRefreshButtonVisible: false,
                emptyStateText: nil
            )
        )
    }

    func testMacOSCustomProviderSettingsPresentationAndSubmitPolicyAreShared() {
        let presentation = RomaAIEnhancementProviderSettingsPresentation.macOS

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
        let presentation = RomaAIEnhancementProviderSettingsPresentation.macOS

        XCTAssertEqual(
            presentation.apiKeyControlPresentation(
                formState: RomaAIEnhancementAPIKeyFormState(enteredKey: "draft-key"),
                provider: .groq,
                customProviderBaseURL: "https://api.example.test/v1/chat/completions",
                customProviderModelName: "custom-model"
            ),
            RomaAIEnhancementAPIKeyControlPresentation(
                isVerificationProgressVisible: false,
                isDefaultVerifyAndSaveButtonDisabled: false,
                isCustomVerifyAndSaveButtonDisabled: false
            )
        )
        XCTAssertEqual(
            presentation.apiKeyControlPresentation(
                formState: RomaAIEnhancementAPIKeyFormState(
                    enteredKey: "draft-key",
                    verificationProgress: .verifying
                ),
                provider: .groq,
                customProviderBaseURL: "https://api.example.test/v1/chat/completions",
                customProviderModelName: "custom-model"
            ),
            RomaAIEnhancementAPIKeyControlPresentation(
                isVerificationProgressVisible: true,
                isDefaultVerifyAndSaveButtonDisabled: false,
                isCustomVerifyAndSaveButtonDisabled: false
            )
        )
        XCTAssertEqual(
            presentation.apiKeyControlPresentation(
                formState: RomaAIEnhancementAPIKeyFormState(enteredKey: ""),
                provider: .custom,
                customProviderBaseURL: "https://api.example.test/v1/chat/completions",
                customProviderModelName: "custom-model"
            ),
            RomaAIEnhancementAPIKeyControlPresentation(
                isVerificationProgressVisible: false,
                isDefaultVerifyAndSaveButtonDisabled: true,
                isCustomVerifyAndSaveButtonDisabled: true
            )
        )
        XCTAssertTrue(
            presentation.apiKeyControlPresentation(
                formState: RomaAIEnhancementAPIKeyFormState(enteredKey: "draft-key"),
                provider: .custom,
                customProviderBaseURL: "",
                customProviderModelName: "custom-model"
            ).isCustomVerifyAndSaveButtonDisabled
        )
    }

    func testMacOSAIEnhancementProviderSelectionPlanAppliesRuntimeState() {
        let groqPlan = RomaAIEnhancementProviderSelectionPlan.selecting(.groq)
        let ollamaPlan = RomaAIEnhancementProviderSelectionPlan.selecting(.ollama)

        var events: [String] = []
        func apply(_ plan: RomaAIEnhancementProviderSelectionPlan) {
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
            RomaAIEnhancementProviderKind.groq.selectedTextEnhancementModel(
                "llama-3.3-70b-versatile",
                availableModels: RomaAIModelCatalog.availableModels(for: .groq),
                defaultModel: RomaAIModelCatalog.defaultModel(for: .groq)
            ),
            "llama-3.3-70b-versatile"
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.openRouter.selectedTextEnhancementModel(
                "anthropic/claude-sonnet",
                availableModels: ["anthropic/claude-sonnet"],
                defaultModel: RomaAIModelCatalog.defaultModel(for: .openRouter)
            ),
            "anthropic/claude-sonnet"
        )
    }

    func testMacOSAIEnhancementModelSelectionFallsBackForBlankAndUnavailableSelections() {
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.groq.selectedTextEnhancementModel(
                "",
                availableModels: RomaAIModelCatalog.availableModels(for: .groq),
                defaultModel: RomaAIModelCatalog.defaultModel(for: .groq)
            ),
            RomaAIModelCatalog.defaultModel(for: .groq)
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.groq.selectedTextEnhancementModel(
                "stale-model",
                availableModels: RomaAIModelCatalog.availableModels(for: .groq),
                defaultModel: RomaAIModelCatalog.defaultModel(for: .groq)
            ),
            RomaAIModelCatalog.defaultModel(for: .groq)
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.localCLI.selectedTextEnhancementModel(
                "custom-cli-model",
                availableModels: [],
                defaultModel: "local-cli"
            ),
            "local-cli"
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.custom.selectedTextEnhancementModel(
                "saved-custom-selection",
                availableModels: [],
                defaultModel: "custom-model"
            ),
            "custom-model"
        )
    }

    func testMacOSAIEnhancementModelSelectionKeepsUnavailableOllamaModel() {
        XCTAssertTrue(RomaAIEnhancementProviderKind.ollama.preservesUnavailableSelectedTextEnhancementModel)
        XCTAssertFalse(RomaAIEnhancementProviderKind.groq.preservesUnavailableSelectedTextEnhancementModel)
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.ollama.selectedTextEnhancementModel(
                "local-llama",
                availableModels: [],
                defaultModel: "mistral"
            ),
            "local-llama"
        )
    }

    func testMacOSAIEnhancementModelSelectionPlanAppliesRuntimeState() throws {
        let initialModels: [RomaAIEnhancementProviderKind: String] = [
            .groq: "old-groq-model",
            .openAI: "gpt-5.4"
        ]
        let groqPlan = try XCTUnwrap(
            RomaAIEnhancementModelSelectionPlan.selecting(
                "openai/gpt-oss-120b",
                provider: .groq,
                selectedModels: initialModels
            )
        )
        let ollamaPlan = try XCTUnwrap(
            RomaAIEnhancementModelSelectionPlan.selecting(
                "llama3",
                provider: .ollama,
                selectedModels: initialModels
            )
        )

        var events: [String] = []
        func apply(_ plan: RomaAIEnhancementModelSelectionPlan) {
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

    func testMacOSAIEnhancementProviderDefaultsAreShared() {
        let expectedDefaults: [RomaAIModelProvider: String] = [
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

        XCTAssertEqual(RomaAIModelProvider.allCases.count, expectedDefaults.count)

        for (provider, expectedDefault) in expectedDefaults {
            XCTAssertEqual(RomaAIModelCatalog.defaultModel(for: provider), expectedDefault)
        }
    }

    func testMacOSAIEnhancementProviderModelListsAreShared() {
        XCTAssertEqual(
            RomaAIModelCatalog.availableModels(for: .anthropic),
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
            RomaAIModelCatalog.availableModels(for: .mistral),
            [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest"
            ]
        )
        XCTAssertEqual(RomaAIModelCatalog.availableModels(for: .elevenLabs), ["scribe_v1", "scribe_v2"])
        XCTAssertEqual(RomaAIModelCatalog.availableModels(for: .deepgram), ["whisper-1"])
        XCTAssertEqual(RomaAIModelCatalog.availableModels(for: .soniox), ["stt-async-v4"])
        XCTAssertEqual(RomaAIModelCatalog.availableModels(for: .speechmatics), ["speechmatics-enhanced"])
        XCTAssertEqual(RomaAIModelCatalog.availableModels(for: .assemblyAI), ["universal-3-pro"])
    }

    func testOpenRouterKeepsDynamicModelListWithSharedDefault() {
        XCTAssertEqual(RomaAIModelCatalog.defaultModel(for: .openRouter), "openai/gpt-oss-120b")
        XCTAssertEqual(RomaAIModelCatalog.availableModels(for: .openRouter), [])
    }

    func testMacOSAIEnhancementDefaultTextEnhancementModelsAreShared() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.groq.defaultTextEnhancementModel(from: defaults),
                RomaAIModelCatalog.defaultModel(for: .groq)
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.openRouter.defaultTextEnhancementModel(from: defaults),
                RomaAIModelCatalog.defaultModel(for: .openRouter)
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.ollama.defaultTextEnhancementModel(from: defaults),
                RomaAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback,
                "llama2"
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.localCLI.defaultTextEnhancementModel(from: defaults),
                RomaAIEnhancementProviderKind.localCLITextEnhancementModel
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.custom.defaultTextEnhancementModel(from: defaults),
                ""
            )

            RomaDynamicAIProviderPreference.saveOllamaSelectedModel("llama3", to: defaults)
            RomaDynamicAIProviderPreference.saveCustomProviderModel("custom-model", to: defaults)

            XCTAssertEqual(
                RomaAIEnhancementProviderKind.ollama.defaultTextEnhancementModel(from: defaults),
                "llama3"
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.custom.defaultTextEnhancementModel(from: defaults),
                "custom-model"
            )
        }
    }

    func testMacOSAIEnhancementStaticTextEnhancementModelsAreShared() {
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.groq.staticTextEnhancementModels,
            RomaAIModelCatalog.availableModels(for: .groq)
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.openRouter.staticTextEnhancementModels,
            RomaAIModelCatalog.availableModels(for: .openRouter)
        )
        XCTAssertEqual(RomaAIEnhancementProviderKind.ollama.staticTextEnhancementModels, [])
        XCTAssertEqual(RomaAIEnhancementProviderKind.localCLI.staticTextEnhancementModels, [])
        XCTAssertEqual(RomaAIEnhancementProviderKind.custom.staticTextEnhancementModels, [])
    }

    func testMacOSAIEnhancementAvailableModelsResolveFromRuntimeAndStaticProviders() {
        let ollamaModels = ["llama3", "mistral"]
        let openRouterModels = ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"]

        XCTAssertEqual(
            RomaAIEnhancementProviderKind.ollama.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            ollamaModels
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.openRouter.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            openRouterModels
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.groq.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            RomaAIModelCatalog.availableModels(for: .groq)
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.localCLI.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            []
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.custom.textEnhancementAvailableModels(
                ollamaModels: ollamaModels,
                openRouterModels: openRouterModels
            ),
            []
        )
    }

    func testMacOSAIEnhancementModelRefreshPlanCachesAndRepairsSelection() {
        let openRouterModels = [
            "anthropic/claude-3.5-sonnet",
            "openai/gpt-4o"
        ]

        XCTAssertEqual(
            RomaAIEnhancementModelRefreshPlan.refreshed(
                provider: .openRouter,
                currentModel: RomaAIModelCatalog.defaultModel(for: .openRouter),
                refreshedModels: openRouterModels,
                defaultModel: RomaAIModelCatalog.defaultModel(for: .openRouter)
            ),
            RomaAIEnhancementModelRefreshPlan(
                refreshedModelNames: openRouterModels,
                selectedModelToSave: "anthropic/claude-3.5-sonnet"
            )
        )

        XCTAssertEqual(
            RomaAIEnhancementModelRefreshPlan.refreshed(
                provider: .openRouter,
                currentModel: "custom/openrouter-model",
                refreshedModels: openRouterModels,
                defaultModel: RomaAIModelCatalog.defaultModel(for: .openRouter)
            ),
            RomaAIEnhancementModelRefreshPlan(
                refreshedModelNames: openRouterModels,
                selectedModelToSave: nil
            )
        )

        XCTAssertEqual(
            RomaAIEnhancementModelRefreshPlan.refreshed(
                provider: .ollama,
                currentModel: "missing-local-model",
                refreshedModels: ["llama3", "mistral"],
                defaultModel: RomaAIEnhancementProviderKind.defaultOllamaTextEnhancementModel
            ),
            RomaAIEnhancementModelRefreshPlan(
                refreshedModelNames: ["llama3", "mistral"],
                selectedModelToSave: "llama3"
            )
        )

        XCTAssertEqual(
            RomaAIEnhancementModelRefreshPlan.failed,
            RomaAIEnhancementModelRefreshPlan(
                refreshedModelNames: [],
                selectedModelToSave: nil
            )
        )
    }

    func testMacOSAIEnhancementOpenRouterModelRefreshPlanAppliesRuntimeState() {
        let refreshedPlan = RomaAIEnhancementModelRefreshPlan(
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
        RomaAIEnhancementModelRefreshPlan.failed.applyOpenRouterRuntimeState(
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
        let expectedDispatches: [(RomaAIEnhancementProviderKind, RomaAPIKeyVerificationResult, [String])] = [
            (.anthropic, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "anthropic"), ["anthropic:resolved-key"]),
            (.assemblyAI, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:assemblyAI"]),
            (.cerebras, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openai"), ["openai:https://api.example.com/v1/chat/completions:resolved-key:shared-model"]),
            (.custom, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openai"), ["openai:https://api.example.com/v1/chat/completions:resolved-key:shared-model"]),
            (.deepgram, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:deepgram"]),
            (.elevenLabs, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:elevenLabs"]),
            (.gemini, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:gemini"]),
            (.groq, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openai"), ["openai:https://api.example.com/v1/chat/completions:resolved-key:shared-model"]),
            (.localCLI, RomaAPIKeyVerificationResult(isValid: false, errorMessage: RomaAIEnhancementProviderKind.localCLI.unsupportedAPIKeyVerificationMessage), []),
            (.mistral, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:mistral"]),
            (.ollama, RomaAPIKeyVerificationResult(isValid: false, errorMessage: RomaAIEnhancementProviderKind.ollama.unsupportedAPIKeyVerificationMessage), []),
            (.openAI, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openai"), ["openai:https://api.example.com/v1/chat/completions:resolved-key:shared-model"]),
            (.openRouter, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "openrouter"), ["openrouter:resolved-key:shared-model"]),
            (.soniox, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:soniox"]),
            (.speechmatics, RomaAPIKeyVerificationResult(isValid: true, errorMessage: "shared"), ["shared:resolved-key:speechmatics"])
        ]

        XCTAssertEqual(RomaAIEnhancementProviderKind.allCases.count, expectedDispatches.count)

        for (provider, expectedResult, expectedCalls) in expectedDispatches {
            await assertVerificationDispatch(
                RomaAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                    provider: provider,
                    currentModel: "shared-model",
                    requestURL: customRequestURL
                ),
                expectedResult: expectedResult,
                expectedCalls: expectedCalls
            )
        }
    }

    func testTemperatureUsesRequiredGPT5Temperature() {
        XCTAssertEqual(RomaAIReasoningConfig.temperature(forModelName: "gpt-5.4"), 1)
        XCTAssertEqual(
            RomaAIReasoningConfig.temperature(forModelName: "llama-3.3-70b-versatile", defaultTemperature: 0.2),
            0.2
        )
    }

    func testReasoningEffortMatchesProviderModelPolicy() {
        XCTAssertEqual(RomaAIReasoningConfig.reasoningEffort(for: .gemini, modelName: "gemini-2.5-flash"), "none")
        XCTAssertEqual(RomaAIReasoningConfig.reasoningEffort(for: .gemini, modelName: "gemini-3.1-pro-preview"), "low")
        XCTAssertEqual(RomaAIReasoningConfig.reasoningEffort(for: .openAI, modelName: "gpt-5.4"), "none")
        XCTAssertEqual(RomaAIReasoningConfig.reasoningEffort(for: .cerebras, modelName: "gpt-oss-120b"), "low")
        XCTAssertEqual(RomaAIReasoningConfig.reasoningEffort(for: .groq, modelName: "qwen/qwen3-32b"), "none")
        XCTAssertNil(RomaAIReasoningConfig.reasoningEffort(for: .groq, modelName: "llama-3.3-70b-versatile"))
    }

    func testExtraBodyParametersMatchProviderModelPolicy() {
        XCTAssertEqual(
            RomaAIReasoningConfig.extraBodyParameters(for: .cerebras, modelName: "gpt-oss-120b")?["reasoning_format"] as? String,
            "hidden"
        )
        XCTAssertEqual(
            RomaAIReasoningConfig.extraBodyParameters(for: .groq, modelName: "openai/gpt-oss-120b")?["include_reasoning"] as? Bool,
            false
        )
        XCTAssertNil(RomaAIReasoningConfig.extraBodyParameters(for: .openAI, modelName: "gpt-5.4"))
    }

    func testChatRequestParametersCombineTemperatureAndReasoningPolicy() {
        let openAIParameters = RomaAIReasoningConfig.chatRequestParameters(
            for: .openAI,
            modelName: "gpt-5.4",
            defaultTemperature: 0.2
        )
        XCTAssertEqual(openAIParameters.temperature, 1)
        XCTAssertEqual(openAIParameters.reasoningEffort, "none")
        XCTAssertNil(openAIParameters.extraBodyParameters)

        let groqParameters = RomaAIReasoningConfig.chatRequestParameters(
            for: .groq,
            modelName: "openai/gpt-oss-120b",
            defaultTemperature: 0.2
        )
        XCTAssertEqual(groqParameters.temperature, 0.2)
        XCTAssertEqual(groqParameters.reasoningEffort, "low")
        XCTAssertEqual(groqParameters.extraBodyParameters?["include_reasoning"] as? Bool, false)

        let customParameters = RomaAIReasoningConfig.chatRequestParameters(
            for: nil,
            modelName: "custom-model",
            defaultTemperature: 0.2
        )
        XCTAssertEqual(customParameters.temperature, 0.2)
        XCTAssertNil(customParameters.reasoningEffort)
        XCTAssertNil(customParameters.extraBodyParameters)
    }

    func testMacOSExtraAIProvidersUseNoSharedReasoningOverrides() {
        let providersWithoutOverrides: [RomaAIModelProvider] = [
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
            let model = RomaAIModelCatalog.defaultModel(for: provider)
            XCTAssertNil(RomaAIReasoningConfig.reasoningEffort(for: provider, modelName: model))
            XCTAssertNil(RomaAIReasoningConfig.extraBodyParameters(for: provider, modelName: model))
        }
    }

    func testMacOSAIEnhancementExecutionPlanAppliesAdapters() async throws {
        try await withIsolatedDefaultsAsyncThrows { defaults in
            RomaDynamicAIProviderPreference.saveCustomProviderBaseURL(
                "https://api.example.com/v1/chat/completions",
                to: defaults
            )

            XCTAssertEqual(RomaAIEnhancementProviderKind.selectableTextEnhancementProviders, [
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

            let localExpectations: [(RomaAIEnhancementProviderKind, String, String)] = [
                (.ollama, "mistral", "ollama:mistral"),
                (.localCLI, "local-cli", "localCLI:local-cli"),
                (.anthropic, "claude-sonnet-4-5", "anthropicMessages:claude-sonnet-4-5")
            ]

            for (provider, model, expectedSummary) in localExpectations {
                let summary = try await executionSummary(
                    for: RomaAIEnhancementRequestExecutionPlan.planning(
                        provider: provider,
                        modelName: model,
                        defaults: defaults
                    )
                )
                XCTAssertEqual(summary, expectedSummary)
            }

            let openAICompatibleExpectations: [(RomaAIEnhancementProviderKind, String, OpenAICompatibleRequestSummary)] = [
                (
                    .cerebras,
                    "gpt-oss-120b",
                    OpenAICompatibleRequestSummary(
                        requestURL: RomaAIModelProvider.cerebras.postProcessingRequestURL!,
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
                        requestURL: RomaAIModelProvider.gemini.postProcessingRequestURL!,
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
                        requestURL: RomaAIModelProvider.groq.postProcessingRequestURL!,
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
                        requestURL: RomaAIModelProvider.mistral.postProcessingRequestURL!,
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
                        requestURL: RomaAIModelProvider.openAI.postProcessingRequestURL!,
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
                        requestURL: RomaAIModelProvider.openRouter.postProcessingRequestURL!,
                        temperature: 0.3,
                        reasoningEffort: nil,
                        hasExtraBodyParameters: false,
                        includeReasoning: nil
                    )
                )
            ]

            for (provider, model, expectedSummary) in openAICompatibleExpectations {
                let summary = try await openAICompatibleRequestSummary(
                    for: RomaAIEnhancementRequestExecutionPlan.planning(
                        provider: provider,
                        modelName: model,
                        defaults: defaults
                    )
                )
                XCTAssertEqual(summary, expectedSummary)
            }
        }
    }

    private func executionSummary(for plan: RomaAIEnhancementRequestExecutionPlan) async throws -> String {
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
        for plan: RomaAIEnhancementRequestExecutionPlan
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
        let expectedURLs: [RomaAIModelProvider: String?] = [
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

        XCTAssertEqual(RomaAIModelProvider.allCases.count, expectedURLs.count)

        for (provider, expectedURL) in expectedURLs {
            XCTAssertEqual(provider.postProcessingRequestURL?.absoluteString, expectedURL)
        }
    }

    func testMacOSAIEnhancementConsoleURLsAreShared() {
        let expectedURLs: [RomaAIModelProvider: String] = [
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

        XCTAssertEqual(RomaAIModelProvider.allCases.count, expectedURLs.count)

        for (provider, expectedURL) in expectedURLs {
            XCTAssertEqual(provider.apiKeyConsoleURL.absoluteString, expectedURL)
        }
    }

    func testAIEnhancementProvidersExposeOptionalConsoleURLs() {
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.groq.apiKeyConsoleURL?.absoluteString,
            "https://console.groq.com/keys"
        )
        XCTAssertEqual(
            RomaAIEnhancementProviderKind.openRouter.apiKeyConsoleURL?.absoluteString,
            "https://openrouter.ai/keys"
        )
        XCTAssertNil(RomaAIEnhancementProviderKind.custom.apiKeyConsoleURL)
        XCTAssertNil(RomaAIEnhancementProviderKind.ollama.apiKeyConsoleURL)
        XCTAssertNil(RomaAIEnhancementProviderKind.localCLI.apiKeyConsoleURL)
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "RomaCore.AIProviderCatalogTests.\(UUID().uuidString)"
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
        let suiteName = "RomaCore.AIProviderCatalogTests.\(UUID().uuidString)"
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
        let suiteName = "RomaCore.AIProviderCatalogTests.\(UUID().uuidString)"
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

extension AIProviderCatalogTests {
    func testEnhancementPromptBuilderAppendsContextSectionsInMacOSOrder() {
        let systemMessage = RomaAIEnhancementPromptBuilder.systemMessage(
            basePrompt: "Clean this transcript.",
            context: RomaAIEnhancementPromptContext(
                surroundingTextBeforeCursor: "before cursor",
                selectedText: "selected text",
                clipboardText: "clipboard text",
                currentWindowText: "window text",
                customVocabulary: "Roma\nFelix"
            )
        )

        XCTAssertEqual(
            systemMessage,
            """
            Clean this transcript.

            <SURROUNDING_TEXT_BEFORE_CURSOR>
            before cursor
            </SURROUNDING_TEXT_BEFORE_CURSOR>

            <CURRENTLY_SELECTED_TEXT>
            selected text
            </CURRENTLY_SELECTED_TEXT>

            <CLIPBOARD_CONTEXT>
            clipboard text
            </CLIPBOARD_CONTEXT>

            <CURRENT_WINDOW_CONTEXT>
            window text
            </CURRENT_WINDOW_CONTEXT>

            The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
            <CUSTOM_VOCABULARY>
            Roma
            Felix
            </CUSTOM_VOCABULARY>
            """
        )
    }

    func testEnhancementPromptBuilderSkipsMissingAndEmptyContextSections() {
        XCTAssertEqual(
            RomaAIEnhancementPromptBuilder.systemMessage(
                basePrompt: "Clean this transcript.",
                context: RomaAIEnhancementPromptContext(
                    selectedText: "",
                    clipboardText: nil,
                    currentWindowText: "",
                    customVocabulary: ""
                )
            ),
            "Clean this transcript."
        )
    }

    func testEnhancementVocabularyContextFormatsTermsInOrder() {
        XCTAssertEqual(
            RomaAIEnhancementVocabularyContext.formatted(from: ["Roma", "Felix", "SwiftData"]),
            "Important Vocabulary: Roma, Felix, SwiftData"
        )
    }

    func testEnhancementVocabularyContextNormalizesRawTermsForPostProcessing() {
        XCTAssertEqual(
            RomaAIEnhancementVocabularyContext.formatted(from: [" Roma ", "", "roma", "Felix"]),
            "Important Vocabulary: Roma, Felix"
        )
    }

    func testEnhancementVocabularyContextReturnsEmptyForNoTerms() {
        XCTAssertEqual(
            RomaAIEnhancementVocabularyContext.formatted(from: []),
            ""
        )
    }

    func testScreenContextPrefersFrontmostVisibleNonSelfWindow() {
        let windows = [
            aiPromptScreenWindow(processID: 7, title: "Background"),
            aiPromptScreenWindow(processID: 42, title: "Self"),
            aiPromptScreenWindow(processID: 9, title: "Frontmost")
        ]

        XCTAssertEqual(
            RomaAIEnhancementScreenContext.preferredWindowIndex(
                in: windows,
                currentProcessID: 42,
                frontmostProcessID: 9
            ),
            2
        )
    }

    func testScreenContextFallsBackToFirstVisibleNonSelfWindow() {
        let windows = [
            aiPromptScreenWindow(processID: 42, title: "Self"),
            aiPromptScreenWindow(processID: 7, layer: 1, title: "Menu"),
            aiPromptScreenWindow(processID: 8, isOnScreen: false, title: "Hidden"),
            aiPromptScreenWindow(processID: 10, title: "Fallback")
        ]

        XCTAssertEqual(
            RomaAIEnhancementScreenContext.preferredWindowIndex(
                in: windows,
                currentProcessID: 42,
                frontmostProcessID: 99
            ),
            3
        )
    }

    func testScreenContextTextUsesExistingFallbacks() {
        XCTAssertEqual(
            RomaAIEnhancementScreenContext.contextText(
                window: aiPromptScreenWindow(processID: nil, title: nil, applicationName: nil),
                extractedText: ""
            ),
            """
            Active Window: Unknown
            Application: Unknown

            Window Content:
            No text detected via OCR
            """
        )
    }

    func testScreenContextExtractedTextPreservesMacOSOCRAssembly() {
        XCTAssertEqual(
            RomaAIEnhancementScreenContext.extractedText(
                fromRecognizedCandidates: ["Roadmap", "Architecture"]
            ),
            "Roadmap\nArchitecture"
        )
        XCTAssertNil(
            RomaAIEnhancementScreenContext.extractedText(
                fromRecognizedCandidates: []
            )
        )
    }

    func testEnhancementRequestPayloadReturnsNilForEmptyTranscript() {
        XCTAssertNil(RomaAIEnhancementRequestPayload(transcript: ""))
    }

    func testEnhancementRequestPayloadPreservesMacOSWhitespaceOnlyTranscriptPolicy() throws {
        let payload = try XCTUnwrap(RomaAIEnhancementRequestPayload(transcript: "   "))

        XCTAssertEqual(
            payload.userMessage,
            "\n<TRANSCRIPT>\n   \n</TRANSCRIPT>"
        )
    }

    func testEnhancementRequestPayloadBuildsTaggedUserMessageAndFiltersProviderOutput() throws {
        let payload = try XCTUnwrap(RomaAIEnhancementRequestPayload(transcript: "raw text"))

        XCTAssertEqual(
            payload.userMessage,
            "\n<TRANSCRIPT>\nraw text\n</TRANSCRIPT>"
        )
        XCTAssertEqual(
            RomaAIEnhancementRequestPayload.enhancedText(
                from: "<thinking>draft</thinking>\nClean text"
            ),
            "Clean text"
        )
    }

    func testEnhancementRequestPreparationPreservesMacOSPreflightPolicy() throws {
        do {
            _ = try RomaAIEnhancementRequestPreparation.preparing(
                transcript: "raw text",
                isConfigured: false
            )
            XCTFail("Expected notConfigured error")
        } catch let error as RomaAIEnhancementError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            try RomaAIEnhancementRequestPreparation.preparing(
                transcript: "",
                isConfigured: true
            ),
            .skipEmptyTranscript
        )
        XCTAssertEqual(
            try RomaAIEnhancementRequestPreparation.preparing(
                transcript: "raw text",
                isConfigured: true
            ),
            .execute(try XCTUnwrap(RomaAIEnhancementRequestPayload(transcript: "raw text")))
        )
    }
}

private func aiPromptScreenWindow(
    processID: Int?,
    layer: Int = 0,
    isOnScreen: Bool = true,
    title: String? = nil,
    applicationName: String? = "App"
) -> RomaScreenCaptureWindowFacts {
    RomaScreenCaptureWindowFacts(
        processID: processID,
        layer: layer,
        isOnScreen: isOnScreen,
        title: title,
        applicationName: applicationName
    )
}

extension AIProviderCatalogTests {

    func testHTTPErrorMappingPreservesMacOSRetryCategories() {
        XCTAssertEqual(
            RomaAIEnhancementError.httpError(statusCode: 429, message: "too many requests"),
            .rateLimitExceeded
        )
        XCTAssertEqual(
            RomaAIEnhancementError.httpError(statusCode: 500, message: "bad gateway"),
            .serverError
        )
        XCTAssertEqual(
            RomaAIEnhancementError.httpError(statusCode: 599, message: "edge timeout"),
            .serverError
        )
        XCTAssertEqual(
            RomaAIEnhancementError.httpError(statusCode: 400, message: "bad request"),
            .customError("HTTP 400: bad request")
        )
    }

    func testTransportFailureMappingPreservesMacOSLLMKitCategories() {
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.missingAPIKey),
            .notConfigured
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.httpStatus(statusCode: 429, message: "slow down")),
            .rateLimitExceeded
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.httpStatus(statusCode: 500, message: "server down")),
            .serverError
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.httpStatus(statusCode: 400, message: "bad input")),
            .customError("HTTP 400: bad input")
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.noResultReturned),
            .enhancementFailed
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.network),
            .networkError
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.timeout),
            .timeout
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.invalidRequest(description: "bad response")),
            .customError("bad response")
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.invalidRequest(description: "")),
            .customError("An unknown error occurred.")
        )
        XCTAssertEqual(
            RomaAIEnhancementError.transportFailure(.invalidRequest(description: nil)),
            .customError("An unknown error occurred.")
        )
    }

    func testTransportNetworkErrorMapsRetryableFoundationErrors() {
        let retryableCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost
        ]

        for code in retryableCodes {
            let error = NSError(domain: NSURLErrorDomain, code: code)
            XCTAssertEqual(
                RomaAIEnhancementError.transportNetworkError(for: error),
                .networkError
            )
        }
    }

    func testTransportNetworkErrorRejectsNonRetryableFoundationErrors() {
        XCTAssertNil(RomaAIEnhancementError.transportNetworkError(
            for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        ))
        XCTAssertNil(RomaAIEnhancementError.transportNetworkError(
            for: NSError(domain: "RomaJustTalk", code: NSURLErrorTimedOut)
        ))
    }

    func testLocalCLIExecutionFailureMapsCoreErrorsAndGenericFallbacks() {
        XCTAssertEqual(
            RomaAIEnhancementError.localCLIExecutionFailure(
                RomaLocalCLIExecutionError.timeout(seconds: 45.9)
            ),
            .customError("Local CLI command timed out after 45 seconds.")
        )
        XCTAssertEqual(
            RomaAIEnhancementError.localCLIExecutionFailure(
                NSError(
                    domain: "RomaLocalCLI",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "sandbox denied"]
                )
            ),
            .customError("sandbox denied")
        )
    }

    func testOllamaEnhancementFailurePolicyPreservesMacOSMessagesAndRetryShape() {
        let expectedMessages: [(RomaOllamaEnhancementFailure, String)] = [
            (.invalidURL, "Invalid Ollama server URL"),
            (.serviceUnavailable, "Ollama service is not available"),
            (.invalidResponse, "Invalid response from Ollama server"),
            (.modelNotFound, "Selected model not found"),
            (.serverError, "Ollama server error"),
            (.invalidRequest, "System prompt is required"),
            (.timeout, "Ollama request timed out")
        ]

        for (failure, message) in expectedMessages {
            XCTAssertEqual(failure.message, message)
            XCTAssertEqual(failure.errorDescription, message)
        }

        XCTAssertEqual(RomaOllamaEnhancementFailure.httpFailure(statusCode: 404), .modelNotFound)
        XCTAssertEqual(RomaOllamaEnhancementFailure.httpFailure(statusCode: 500), .serverError)
        XCTAssertEqual(RomaOllamaEnhancementFailure.httpFailure(statusCode: 599), .invalidResponse)
        XCTAssertEqual(RomaOllamaEnhancementFailure.timeout.enhancementError, .timeout)
        XCTAssertEqual(
            RomaOllamaEnhancementFailure.serverError.enhancementError,
            .customError("Ollama server error")
        )
    }

    func testOllamaTransportFailuresMapToSharedFailurePolicy() {
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.invalidURL), .invalidURL)
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.httpStatus(404)), .modelNotFound)
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.httpStatus(500)), .serverError)
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.httpStatus(400)), .invalidResponse)
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.network), .serviceUnavailable)
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.invalidResponse), .invalidResponse)
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.invalidRequest), .invalidRequest)
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.missingCredential), .invalidResponse)
        XCTAssertEqual(RomaOllamaEnhancementFailure.transportFailure(.timeout), .timeout)
    }

    func testDefaultRetryStatePreservesMacOSAttemptAndDelayDefaults() {
        var state = RomaAIEnhancementRetryState()

        XCTAssertEqual(state.maxAttempts, 3)
        XCTAssertTrue(state.retryOnTimeout)
        XCTAssertEqual(state.failedAttempts, 0)
        XCTAssertEqual(state.nextDelay, 1)
        XCTAssertEqual(state.recordFailure(.networkError), .retryAfterDelay(1))
        XCTAssertEqual(state.recordFailure(.serverError), .retryAfterDelay(2))
        XCTAssertEqual(state.recordFailure(.rateLimitExceeded), .fail(.rateLimitExceeded))
    }

    func testBackoffFailuresRetryUntilAttemptLimit() {
        var state = RomaAIEnhancementRetryState(
            maxAttempts: 3,
            initialDelay: 1,
            retryOnTimeout: true
        )

        XCTAssertEqual(state.recordFailure(.networkError), .retryAfterDelay(1))
        XCTAssertEqual(state.failedAttempts, 1)
        XCTAssertEqual(state.nextDelay, 2)

        XCTAssertEqual(state.recordFailure(.serverError), .retryAfterDelay(2))
        XCTAssertEqual(state.failedAttempts, 2)
        XCTAssertEqual(state.nextDelay, 4)

        XCTAssertEqual(state.recordFailure(.rateLimitExceeded), .fail(.rateLimitExceeded))
        XCTAssertEqual(state.failedAttempts, 3)
    }

    func testTimeoutRetriesImmediatelyWhenEnabled() {
        var state = RomaAIEnhancementRetryState(
            maxAttempts: 3,
            initialDelay: 1,
            retryOnTimeout: true
        )

        XCTAssertEqual(state.recordFailure(.timeout), .retryImmediately)
        XCTAssertEqual(state.failedAttempts, 1)
        XCTAssertEqual(state.nextDelay, 1)

        XCTAssertEqual(state.recordFailure(.timeout), .retryImmediately)
        XCTAssertEqual(state.failedAttempts, 2)

        XCTAssertEqual(state.recordFailure(.timeout), .fail(.timeout))
        XCTAssertEqual(state.failedAttempts, 3)
    }

    func testTimeoutFailsImmediatelyWhenDisabled() {
        var state = RomaAIEnhancementRetryState(
            maxAttempts: 3,
            initialDelay: 1,
            retryOnTimeout: false
        )

        XCTAssertEqual(state.recordFailure(.timeout), .fail(.timeout))
        XCTAssertEqual(state.failedAttempts, 0)
    }

    func testNonRetryableEnhancementErrorsFailWithoutCountingAttempt() {
        var state = RomaAIEnhancementRetryState()

        XCTAssertEqual(state.recordFailure(.notConfigured), .fail(.notConfigured))
        XCTAssertEqual(state.recordFailure(.enhancementFailed), .fail(.enhancementFailed))
        XCTAssertEqual(state.recordFailure(.customError("bad request")), .fail(.customError("bad request")))
        XCTAssertEqual(state.failedAttempts, 0)
    }

    func testTransportNetworkFailureMapsToSharedNetworkError() {
        var state = RomaAIEnhancementRetryState(
            maxAttempts: 2,
            initialDelay: 1,
            retryOnTimeout: true
        )

        XCTAssertEqual(state.recordTransportNetworkFailure(), .retryAfterDelay(1))
        XCTAssertEqual(state.recordTransportNetworkFailure(), .fail(.networkError))
    }

    func testNonEnhancementErrorRetryPlanHandlesOnlyRetryableTransportFailures() {
        var state = RomaAIEnhancementRetryState(
            maxAttempts: 2,
            initialDelay: 1,
            retryOnTimeout: true
        )

        XCTAssertEqual(
            state.recordNonEnhancementError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
            ),
            RomaAIEnhancementNonEnhancementErrorRetryPlan(
                decision: .retryAfterDelay(1),
                isTransportNetworkFailure: true
            )
        )
        XCTAssertEqual(state.failedAttempts, 1)
        XCTAssertEqual(
            state.recordNonEnhancementError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
            ),
            RomaAIEnhancementNonEnhancementErrorRetryPlan(
                decision: .fail(.networkError),
                isTransportNetworkFailure: true
            )
        )
        XCTAssertEqual(state.failedAttempts, 2)

        var nonRetryableState = RomaAIEnhancementRetryState()
        XCTAssertNil(nonRetryableState.recordNonEnhancementError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        ))
        XCTAssertEqual(nonRetryableState.failedAttempts, 0)
    }

    func testNonEnhancementErrorRetryPlanAppliesRuntimeState() async throws {
        let plan = RomaAIEnhancementNonEnhancementErrorRetryPlan(
            decision: .retryAfterDelay(1),
            isTransportNetworkFailure: true
        )

        var decisions: [RomaAIEnhancementRetryDecision] = []
        var transportNetworkFailures: [Bool] = []
        try await plan.applyRuntimeState { decision, transportNetworkFailure in
            decisions.append(decision)
            transportNetworkFailures.append(transportNetworkFailure)
        }

        XCTAssertEqual(decisions, [.retryAfterDelay(1)])
        XCTAssertEqual(transportNetworkFailures, [true])
    }

    func testRateLimitPolicySkipsDelayWithoutLastRequest() {
        let policy = RomaAIEnhancementRateLimitPolicy(minimumInterval: 1)

        XCTAssertNil(policy.delaySinceLastRequest(
            lastRequest: nil,
            now: Date(timeIntervalSince1970: 100)
        ))
    }

    func testRateLimitPolicyReturnsRemainingDelay() {
        let policy = RomaAIEnhancementRateLimitPolicy(minimumInterval: 1)
        let lastRequest = Date(timeIntervalSince1970: 100)
        let now = Date(timeIntervalSince1970: 100.25)

        XCTAssertEqual(
            policy.delaySinceLastRequest(lastRequest: lastRequest, now: now) ?? -1,
            0.75,
            accuracy: 0.0001
        )
    }

    func testRateLimitPolicySkipsDelayAfterIntervalExpires() {
        let policy = RomaAIEnhancementRateLimitPolicy(minimumInterval: 1)
        let lastRequest = Date(timeIntervalSince1970: 100)

        XCTAssertNil(policy.delaySinceLastRequest(
            lastRequest: lastRequest,
            now: Date(timeIntervalSince1970: 101)
        ))
        XCTAssertNil(RomaAIEnhancementRateLimitPolicy(minimumInterval: -1).delaySinceLastRequest(
            lastRequest: lastRequest,
            now: Date(timeIntervalSince1970: 100)
        ))
    }
    func testMacOSAIEnhancementRequestURLSelectionIsShared() async {
        await withIsolatedDefaultsAsync { defaults in
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.groq.textEnhancementRequestURLString(from: defaults),
                RomaAIModelProvider.groq.postProcessingRequestURL?.absoluteString
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.openRouter.textEnhancementRequestURLString(from: defaults),
                RomaAIModelProvider.openRouter.postProcessingRequestURL?.absoluteString
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.ollama.textEnhancementRequestURLString(from: defaults),
                RomaPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.localCLI.textEnhancementRequestURLString(from: defaults),
                ""
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.custom.textEnhancementRequestURLString(from: defaults),
                ""
            )

            RomaDynamicAIProviderPreference.saveOllamaBaseURL("http://example.local:11434", to: defaults)
            RomaDynamicAIProviderPreference.saveCustomProviderBaseURL("https://api.example.com", to: defaults)

            XCTAssertEqual(
                RomaAIEnhancementProviderKind.ollama.textEnhancementRequestURLString(from: defaults),
                "http://example.local:11434"
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.custom.textEnhancementRequestURLString(from: defaults),
                "https://api.example.com"
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderKind.custom.textEnhancementRequestURL(from: defaults)?.absoluteString,
                "https://api.example.com"
            )

            RomaDynamicAIProviderPreference.saveCustomProviderBaseURL("http://[::1", to: defaults)

            XCTAssertNil(RomaAIEnhancementProviderKind.custom.textEnhancementRequestURL(from: defaults))
            XCTAssertNil(RomaAIEnhancementProviderKind.localCLI.textEnhancementRequestURL(from: defaults))

            let invalidCustomPlan = RomaAIEnhancementRequestExecutionPlan.planning(
                provider: .custom,
                modelName: "custom-model",
                defaults: defaults
            )

            do {
                _ = try await openAICompatibleRequestSummary(for: invalidCustomPlan)
                XCTFail("Expected invalid custom endpoint to throw")
            } catch {
                XCTAssertEqual(
                    error as? RomaAIEnhancementError,
                    .customError(RomaAIEnhancementProviderKind.custom.invalidTextEnhancementRequestURLMessage)
                )
            }

            RomaDynamicAIProviderPreference.saveCustomProviderBaseURL(
                "https://api.example.com/v1/chat/completions",
                to: defaults
            )
            let customPlan = RomaAIEnhancementRequestExecutionPlan.planning(
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

}
