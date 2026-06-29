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
    }

    func testRuntimeAPIKeyFollowsProviderAccessPolicy() {
        XCTAssertEqual(VoiceInkProviderKind.groq.runtimeAPIKey(userAPIKey: "groq-key"), "groq-key")
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.runtimeAPIKey(userAPIKey: ""), "local")
    }

    func testLegacyVoiceInkProviderValuesDecodeToLegacyProvider() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(VoiceInkProviderKind.self, from: Data(#""VoiceInk""#.utf8)),
            .voiceInk
        )
        XCTAssertEqual(
            try decoder.decode(VoiceInkProviderKind.self, from: Data(#""voiceInk""#.utf8)),
            .voiceInk
        )
    }

    func testBundledVoiceInkProviderIsNotSelectableUntilAnAdapterExists() {
        guard case .bundledService = VoiceInkProviderKind.voiceInk.accessRequirement else {
            return XCTFail("Legacy VoiceInk provider should keep bundled-service compatibility")
        }

        XCTAssertFalse(VoiceInkProviderKind.voiceInk.requiresUserAPIKey)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyAccount)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyVerificationStateKey)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.apiKeyVerificationTransport)
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.canVerifyAPIKey)
        XCTAssertEqual(VoiceInkProviderKind.voiceInk.runtimeAPIKey(userAPIKey: ""), "")
        XCTAssertNil(VoiceInkProviderKind.voiceInk.runtimeAPIKeyIfAvailable(userAPIKey: ""))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isReady(
            userAPIKey: "",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .transcription))
        XCTAssertFalse(VoiceInkProviderKind.voiceInk.isSelectable(for: .postProcessing))
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

    func testProviderAPIKeyVerificationApplicationPlanBuildsSuccessPersistencePlan() {
        let successPlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "entered-key",
            shouldMarkKeyVerified: true
        )
        let failurePlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: "bad request"),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )

        XCTAssertEqual(
            successPlan.successPersistencePlan,
            VoiceInkProviderAPIKeyVerificationPersistencePlan(
                keyToSave: "entered-key",
                verificationFlagToPersist: true
            )
        )
        XCTAssertNil(failurePlan.successPersistencePlan)
    }

    func testProviderAPIKeyVerificationApplicationPlanAppliesOrderedPersistenceRuntimeState() {
        let enteredKeySuccessPlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "entered-key",
            shouldMarkKeyVerified: true
        )
        let storedKeySuccessPlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: nil,
            shouldMarkKeyVerified: true
        )
        let failurePlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: "bad request"),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )

        var events: [String] = []
        enteredKeySuccessPlan.successPersistenceApplicationPlan?.applyRuntimeState(
            saveKey: { events.append("key:\($0)") },
            persistVerificationFlag: { events.append("verified:\($0)") }
        )
        XCTAssertEqual(events, ["key:entered-key", "verified:true"])

        events = []
        storedKeySuccessPlan.successPersistenceApplicationPlan?.applyRuntimeState(
            saveKey: { events.append("key:\($0)") },
            persistVerificationFlag: { events.append("verified:\($0)") }
        )
        XCTAssertEqual(events, ["verified:true"])

        XCTAssertNil(failurePlan.successPersistenceApplicationPlan)
    }

    func testProviderAPIKeyVerificationApplicationPlanAppliesSuccessPersistence() {
        let enteredKeySuccessPlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "entered-key",
            shouldMarkKeyVerified: true
        )
        let storedKeySuccessPlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: nil,
            shouldMarkKeyVerified: true
        )
        let failurePlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: "bad request"),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )

        var savedKeys: [String] = []

        XCTAssertTrue(enteredKeySuccessPlan.applySuccessPersistence { savedKeys.append($0) })
        XCTAssertEqual(savedKeys, ["entered-key"])

        savedKeys = []
        XCTAssertTrue(storedKeySuccessPlan.applySuccessPersistence { savedKeys.append($0) })
        XCTAssertEqual(savedKeys, [])

        XCTAssertFalse(failurePlan.applySuccessPersistence { savedKeys.append($0) })
        XCTAssertEqual(savedKeys, [])
    }

    func testProviderAPIKeyMissingVerificationCandidatePlanFailsWithoutStorageSideEffects() {
        let plan = VoiceInkProviderAPIKeyDraft.missingVerificationCandidatePlan()

        XCTAssertEqual(plan.progress, .failure(message: nil))
        XCTAssertNil(plan.keyToSave)
        XCTAssertFalse(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyFormStateLoadsStoredKeyAndVerificationEditingPolicy() {
        let verifiedState = VoiceInkProviderAPIKeyFormState.loaded(
            storedKey: "stored-key",
            isVerified: true
        )
        let unverifiedState = VoiceInkProviderAPIKeyFormState.loaded(
            storedKey: "stored-key",
            isVerified: false
        )

        XCTAssertEqual(verifiedState.enteredKey, "stored-key")
        XCTAssertEqual(verifiedState.verificationProgress, .idle)
        XCTAssertFalse(verifiedState.isEditing)
        XCTAssertEqual(unverifiedState.enteredKey, "stored-key")
        XCTAssertEqual(unverifiedState.verificationProgress, .idle)
        XCTAssertTrue(unverifiedState.isEditing)
    }

    func testProviderAPIKeyFormStateBuildsDraftFromCurrentEntryAndStoredRuntimeKey() {
        let enteredState = VoiceInkProviderAPIKeyFormState(enteredKey: " entered-key \n")
        let storedFallbackState = VoiceInkProviderAPIKeyFormState(enteredKey: " \n\t ")

        let enteredDraft = enteredState.draft(storedRuntimeKey: "stored-key")
        let storedFallbackDraft = storedFallbackState.draft(storedRuntimeKey: " stored-key ")

        XCTAssertEqual(enteredDraft.verificationCandidate, "entered-key")
        XCTAssertEqual(enteredDraft.keyToSaveAfterSuccessfulVerification, "entered-key")
        XCTAssertEqual(storedFallbackDraft.verificationCandidate, " stored-key ")
        XCTAssertNil(storedFallbackDraft.keyToSaveAfterSuccessfulVerification)
    }

    func testProviderAPIKeyFormStateEditingStoredKeyResetsProgressAndOpensEditing() {
        let state = VoiceInkProviderAPIKeyFormState(
            enteredKey: "old-key",
            verificationProgress: .failure(message: "bad request"),
            isEditing: false
        )

        let editingState = state.editingStoredKey("stored-key")

        XCTAssertEqual(editingState.enteredKey, "stored-key")
        XCTAssertEqual(editingState.verificationProgress, .idle)
        XCTAssertTrue(editingState.isEditing)
    }

    func testProviderAPIKeyFormStateEditPlanOwnsIOSVerificationReset() {
        let state = VoiceInkProviderAPIKeyFormState(
            enteredKey: "old-key",
            verificationProgress: .success,
            isEditing: false
        )

        let plan = state.iOSStoredKeyEditPlan(storedKey: "stored-key")

        XCTAssertEqual(plan.formState.enteredKey, "stored-key")
        XCTAssertEqual(plan.formState.verificationProgress, .idle)
        XCTAssertTrue(plan.formState.isEditing)
        XCTAssertEqual(plan.verificationFlagToPersist, false)
    }

    func testProviderAPIKeyFormStateEditingKeyResetsProgressWithoutChangingMode() {
        let state = VoiceInkProviderAPIKeyFormState(
            enteredKey: "edited-key",
            verificationProgress: .failure(message: "bad request"),
            isEditing: true
        )

        let editedState = state.keyEdited()

        XCTAssertEqual(editedState.enteredKey, "edited-key")
        XCTAssertEqual(editedState.verificationProgress, .idle)
        XCTAssertTrue(editedState.isEditing)
    }

    func testProviderAPIKeyFormStateMarksVerificationInProgress() {
        let state = VoiceInkProviderAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .failure(message: "bad request"),
            isEditing: true
        )

        let verifyingState = state.verifying()

        XCTAssertEqual(verifyingState.enteredKey, "entered-key")
        XCTAssertEqual(verifyingState.verificationProgress, .verifying)
        XCTAssertTrue(verifyingState.isEditing)
    }

    func testProviderAPIKeyVerificationStartPlanBeginsWhenCandidateExists() {
        let state = VoiceInkProviderAPIKeyFormState(
            enteredKey: " entered-key \n",
            verificationProgress: .failure(message: "bad request"),
            isEditing: true
        )

        let plan = state.verificationStartPlan(
            storedRuntimeKey: "stored-key",
            missingCandidatePolicy: .keepCurrentState
        )

        var formState: VoiceInkProviderAPIKeyFormState?
        let verificationResult = plan.applyRuntimeState(
            setFormState: { formState = $0 },
            verifyCandidate: { "candidate:\($0)" }
        )

        XCTAssertEqual(verificationResult, "candidate:entered-key")
        XCTAssertEqual(formState?.enteredKey, " entered-key \n")
        XCTAssertEqual(formState?.verificationProgress, .verifying)
        XCTAssertEqual(formState?.isEditing, true)
    }

    func testProviderAPIKeyVerificationStartPlanCanKeepStateForMissingCandidate() {
        let state = VoiceInkProviderAPIKeyFormState(
            enteredKey: " \n\t ",
            verificationProgress: .idle,
            isEditing: true
        )

        let plan = state.verificationStartPlan(
            storedRuntimeKey: nil,
            missingCandidatePolicy: .keepCurrentState
        )

        var didVerifyCandidate = false
        var formState: VoiceInkProviderAPIKeyFormState?
        let verificationResult: Bool? = plan.applyRuntimeState(
            setFormState: { formState = $0 },
            verifyCandidate: { _ in
                didVerifyCandidate = true
                return true
            }
        )

        XCTAssertNil(verificationResult)
        XCTAssertFalse(didVerifyCandidate)
        XCTAssertEqual(formState, state)
    }

    func testProviderAPIKeyVerificationStartPlanCanApplyFailureForMissingCandidate() {
        let state = VoiceInkProviderAPIKeyFormState(
            enteredKey: " \n\t ",
            verificationProgress: .idle,
            isEditing: true
        )

        let plan = state.verificationStartPlan(
            storedRuntimeKey: nil,
            missingCandidatePolicy: .applyFailurePlan
        )

        var didVerifyCandidate = false
        var formState: VoiceInkProviderAPIKeyFormState?
        let verificationResult: Bool? = plan.applyRuntimeState(
            setFormState: { formState = $0 },
            verifyCandidate: { _ in
                didVerifyCandidate = true
                return true
            }
        )

        XCTAssertNil(verificationResult)
        XCTAssertFalse(didVerifyCandidate)
        XCTAssertEqual(formState?.enteredKey, " \n\t ")
        XCTAssertEqual(formState?.verificationProgress, .failure(message: nil))
        XCTAssertEqual(formState?.isEditing, true)
    }

    func testProviderAPIKeyFormStateAppliesVerificationPlanAndClosesEditingOnSuccess() {
        let state = VoiceInkProviderAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .verifying,
            isEditing: true
        )
        let successPlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "entered-key",
            shouldMarkKeyVerified: true
        )
        let failurePlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: "bad request"),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )

        let successState = state.applyingVerificationPlan(successPlan)
        let failureState = state.applyingVerificationPlan(failurePlan)

        XCTAssertEqual(successState.enteredKey, "entered-key")
        XCTAssertEqual(successState.verificationProgress, .success)
        XCTAssertFalse(successState.isEditing)
        XCTAssertEqual(failureState.enteredKey, "entered-key")
        XCTAssertEqual(failureState.verificationProgress, .failure(message: "bad request"))
        XCTAssertTrue(failureState.isEditing)
    }

    func testProviderAPIKeyVerificationCompletionPlanUsesStartDraftAndCurrentFormState() {
        let startState = VoiceInkProviderAPIKeyFormState(
            enteredKey: " verified-key ",
            verificationProgress: .idle,
            isEditing: true
        )
        let startPlan = startState.verificationStartPlan(
            storedRuntimeKey: "stored-key",
            missingCandidatePolicy: .keepCurrentState
        )
        let currentState = VoiceInkProviderAPIKeyFormState(
            enteredKey: "edited-while-verifying",
            verificationProgress: .verifying,
            isEditing: true
        )
        let result = VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)

        let completionPlan = currentState.verificationCompletionPlan(
            startPlan: startPlan,
            result: result
        )

        XCTAssertEqual(completionPlan.formState.enteredKey, "edited-while-verifying")
        XCTAssertEqual(
            completionPlan.formState.verificationProgress,
            VoiceInkProviderAPIKeyVerificationProgress.success
        )
        XCTAssertFalse(completionPlan.formState.isEditing)
        XCTAssertEqual(completionPlan.applicationPlan.keyToSave, "verified-key")
        XCTAssertTrue(completionPlan.applicationPlan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyVerificationCompletionPlanAppliesRuntimeStateInOrderAndReturnsResult() {
        let completionPlan = VoiceInkProviderAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .verifying,
            isEditing: true
        ).verificationCompletionPlan(
            applicationPlan: .unsupportedProvider
        )
        var events: [String] = []

        let didPersist = completionPlan.applyRuntimeState(
            setFormState: { state in
                XCTAssertEqual(state, completionPlan.formState)
                events.append("state")
            },
            applyVerificationPlan: { plan in
                XCTAssertEqual(plan, completionPlan.applicationPlan)
                events.append("plan")
                return plan.shouldMarkKeyVerified
            }
        )

        XCTAssertFalse(didPersist)
        XCTAssertEqual(completionPlan.formState.verificationProgress, .unsupportedProviderFailure)
        XCTAssertEqual(events, ["state", "plan"])
    }

    func testProviderAPIKeyFormStateOwnsIOSResultFeedbackVisibility() {
        XCTAssertNil(
            VoiceInkProviderAPIKeyFormState(verificationProgress: .idle)
                .iOSVisibleResultFeedback(isProviderReady: false)
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyFormState(verificationProgress: .success)
                .iOSVisibleResultFeedback(isProviderReady: false),
            VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyFormState(verificationProgress: .failure(message: "Forbidden"))
                .iOSVisibleResultFeedback(isProviderReady: false),
            VoiceInkProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                systemImageName: "xmark.seal",
                tone: .failure
            )
        )
        XCTAssertNil(
            VoiceInkProviderAPIKeyFormState(verificationProgress: .success)
                .iOSVisibleResultFeedback(isProviderReady: true)
        )
    }

    func testProviderAPIKeyFormStateOwnsIOSStoredKeyPresentation() {
        XCTAssertEqual(
            VoiceInkProviderAPIKeyFormState(isEditing: false)
                .iOSStoredKeyPresentation(storedKey: "abc123"),
            VoiceInkProviderAPIKeyStoredKeyPresentation(
                feedback: VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback,
                obfuscatedKey: "••••••"
            )
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyFormState(isEditing: false)
                .iOSStoredKeyPresentation(storedKey: " \n\t "),
            VoiceInkProviderAPIKeyStoredKeyPresentation(
                feedback: VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback,
                obfuscatedKey: nil
            )
        )
        XCTAssertNil(
            VoiceInkProviderAPIKeyFormState(isEditing: true)
                .iOSStoredKeyPresentation(storedKey: "abc123")
        )
    }

    func testProviderAPIKeyFormStateOwnsIOSControlPresentation() {
        let enteredKey = VoiceInkProviderAPIKeyFormState(enteredKey: " entered-key ")
            .iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertFalse(enteredKey.isSaveButtonDisabled)
        XCTAssertFalse(enteredKey.isVerificationProgressVisible)
        XCTAssertFalse(enteredKey.isVerifyButtonDisabled)

        let blankStoredKey = VoiceInkProviderAPIKeyFormState(enteredKey: " \n\t ")
            .iOSControlPresentation(storedRuntimeKey: "stored-key")
        XCTAssertTrue(blankStoredKey.isSaveButtonDisabled)
        XCTAssertFalse(blankStoredKey.isVerificationProgressVisible)
        XCTAssertFalse(blankStoredKey.isVerifyButtonDisabled)

        let blankMissingStoredKey = VoiceInkProviderAPIKeyFormState(enteredKey: " \n\t ")
            .iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertTrue(blankMissingStoredKey.isSaveButtonDisabled)
        XCTAssertFalse(blankMissingStoredKey.isVerificationProgressVisible)
        XCTAssertTrue(blankMissingStoredKey.isVerifyButtonDisabled)

        let verifying = VoiceInkProviderAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .verifying
        ).iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertFalse(verifying.isSaveButtonDisabled)
        XCTAssertTrue(verifying.isVerificationProgressVisible)
        XCTAssertTrue(verifying.isVerifyButtonDisabled)
    }

    func testProviderAPIKeyFormStateOwnsMacOSCardControlPresentation() {
        XCTAssertEqual(
            VoiceInkProviderAPIKeyFormState(enteredKey: " entered-key ")
                .macOSCardControlPresentation(storedRuntimeKey: nil),
            VoiceInkProviderAPIKeyCardControlPresentation(
                isAPIKeyFieldDisabled: false,
                isVerifyProgressVisible: false,
                isVerifyButtonDisabled: false,
                verifyButtonTitle: "Verify",
                verifyButtonSystemImageName: "checkmark.shield",
                isVerifyButtonSuccess: false,
                inlineFeedback: nil
            )
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyFormState(enteredKey: " \n\t ")
                .macOSCardControlPresentation(storedRuntimeKey: nil)
                .isVerifyButtonDisabled,
            true
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyFormState(
                enteredKey: "entered-key",
                verificationProgress: .verifying
            ).macOSCardControlPresentation(storedRuntimeKey: nil),
            VoiceInkProviderAPIKeyCardControlPresentation(
                isAPIKeyFieldDisabled: true,
                isVerifyProgressVisible: true,
                isVerifyButtonDisabled: true,
                verifyButtonTitle: "Verifying...",
                verifyButtonSystemImageName: "checkmark.shield",
                isVerifyButtonSuccess: false,
                inlineFeedback: nil
            )
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyFormState(
                enteredKey: "stored-key",
                verificationProgress: .success,
                isEditing: false
            ).macOSCardControlPresentation(storedRuntimeKey: nil),
            VoiceInkProviderAPIKeyCardControlPresentation(
                isAPIKeyFieldDisabled: false,
                isVerifyProgressVisible: false,
                isVerifyButtonDisabled: false,
                verifyButtonTitle: "Verify",
                verifyButtonSystemImageName: "checkmark",
                isVerifyButtonSuccess: true,
                inlineFeedback: VoiceInkProviderAPIKeyVerificationFeedback(
                    text: "API key verified successfully!",
                    tone: .success
                )
            )
        )
    }

    func testProviderAPIKeyFormControlPresentationOwnsIOSVerifyRuntimeActionMapping() {
        let enabledControl = VoiceInkProviderAPIKeyFormState(enteredKey: "entered-key")
            .iOSControlPresentation(storedRuntimeKey: nil)
        var didVerify = false
        let enabledAction = enabledControl.verifyRuntimeAction {
            didVerify = true
        }

        XCTAssertTrue(enabledAction != nil)
        enabledAction?()
        XCTAssertTrue(didVerify)

        let disabledControl = VoiceInkProviderAPIKeyFormState(enteredKey: "")
            .iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertFalse(disabledControl.isVerificationProgressVisible)
        XCTAssertTrue(disabledControl.isVerifyButtonDisabled)
        XCTAssertNil(disabledControl.verifyRuntimeAction {})

        let progressControl = VoiceInkProviderAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .verifying
        ).iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertTrue(progressControl.isVerificationProgressVisible)
        XCTAssertTrue(progressControl.isVerifyButtonDisabled)
        XCTAssertNil(progressControl.verifyRuntimeAction {})
    }

    func testProviderAPIKeyFormControlPresentationOwnsIOSSaveRuntimeActionMapping() {
        var didSave = false

        let saveAction = VoiceInkProviderAPIKeyFormState(enteredKey: "entered-key")
            .iOSControlPresentation(storedRuntimeKey: nil)
            .saveRuntimeAction {
            didSave = true
        }

        XCTAssertTrue(saveAction != nil)
        saveAction?()
        XCTAssertTrue(didSave)
        XCTAssertNil(VoiceInkProviderAPIKeyFormState(enteredKey: "")
            .iOSControlPresentation(storedRuntimeKey: nil)
            .saveRuntimeAction {})
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
    }

    func testProviderAPIKeyStateLoadsStoredKeysForUserKeyProvidersOnly() {
        let state = VoiceInkProviderAPIKeyState.loadingStoredKeys(
            for: [.groq, .localWhisper, .deepgram],
            verifiedProviders: [.groq, .localWhisper],
            loadStoredAPIKey: { "\($0.rawValue)-stored" }
        )

        XCTAssertEqual(state.storedAPIKey(for: .groq), "groq-stored")
        XCTAssertEqual(state.storedAPIKey(for: .deepgram), "deepgram-stored")
        XCTAssertEqual(state.storedAPIKey(for: .localWhisper), "")
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

    func testProviderAccessSnapshotUsesProviderReadyNaming() {
        let readyKeyState = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )
        let blankVerifiedKeyState = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: " \n\t "],
            verifiedProviders: [.groq]
        )

        XCTAssertTrue(
            VoiceInkProviderAccessSnapshot(
                apiKeyState: readyKeyState,
                localWhisperModelAvailable: false
            ).isProviderReady(for: .groq)
        )
        XCTAssertFalse(
            VoiceInkProviderAccessSnapshot(
                apiKeyState: blankVerifiedKeyState,
                localWhisperModelAvailable: false
            ).isProviderReady(for: .groq)
        )
        XCTAssertTrue(
            VoiceInkProviderAccessSnapshot(
                apiKeyState: readyKeyState,
                localWhisperModelAvailable: true
            ).isProviderReady(for: .localWhisper)
        )
        XCTAssertFalse(
            VoiceInkProviderAccessSnapshot(
                apiKeyState: readyKeyState,
                localWhisperModelAvailable: false
            ).isProviderReady(for: .localWhisper)
        )
    }

    func testProviderAccessSnapshotBuildsIOSAccessSurfacesFromLocalModelFact() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )
        let snapshotWithLocalModel = VoiceInkProviderAccessSnapshot(
            apiKeyState: state,
            localWhisperModelAvailable: true
        )
        let snapshotWithoutLocalModel = VoiceInkProviderAccessSnapshot(
            apiKeyState: state,
            localWhisperModelAvailable: false
        )

        XCTAssertTrue(snapshotWithLocalModel.isProviderReady(for: .groq))
        XCTAssertTrue(snapshotWithLocalModel.isProviderReady(for: .localWhisper))
        XCTAssertFalse(snapshotWithoutLocalModel.isProviderReady(for: .localWhisper))
        XCTAssertEqual(snapshotWithLocalModel.apiKeyListRows().map(\.provider), VoiceInkProviderKind.userAPIKeyProviders)
        XCTAssertEqual(
            snapshotWithLocalModel.availableProviders(for: .transcription),
            [.groq, .localWhisper]
        )
        XCTAssertEqual(
            snapshotWithoutLocalModel.availableProviders(for: .transcription),
            [.groq]
        )
        XCTAssertEqual(
            snapshotWithLocalModel.modeFormProviderAvailability.transcriptionProviders,
            [.groq, .localWhisper]
        )
        XCTAssertEqual(
            snapshotWithLocalModel.modeFormProviderAvailability.postProcessingProviders,
            [.groq]
        )
    }

    func testProviderAccessSnapshotBuildsProviderAPIKeyFormSnapshot() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: " groq-key "],
            verifiedProviders: [.groq]
        )
        let accessSnapshot = VoiceInkProviderAccessSnapshot(
            apiKeyState: state,
            localWhisperModelAvailable: false
        )
        let formState = VoiceInkProviderAPIKeyFormState(
            enteredKey: " draft-key ",
            verificationProgress: .success,
            isEditing: true
        )
        let formSnapshot = accessSnapshot.apiKeyFormSnapshot(
            for: .groq,
            formState: formState
        )

        XCTAssertEqual(formSnapshot.provider, .groq)
        XCTAssertEqual(formSnapshot.presentation, .make(for: .groq))
        XCTAssertTrue(formSnapshot.isProviderReady)
        XCTAssertTrue(formSnapshot.isEditing)
        XCTAssertEqual(formSnapshot.enteredKey, " draft-key ")
        XCTAssertFalse(formSnapshot.controlPresentation.isSaveButtonDisabled)
        XCTAssertFalse(formSnapshot.controlPresentation.isVerifyButtonDisabled)
        XCTAssertNil(formSnapshot.storedKeyPresentation)
        XCTAssertNil(formSnapshot.visibleResultFeedback)
    }

    func testProviderAPIKeyFormSnapshotBuildsLoadedFormStateFromProviderReadiness() {
        let blankVerifiedState = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: " \n\t "],
            verifiedProviders: [.groq]
        )
        let formSnapshot = VoiceInkProviderAccessSnapshot(
            apiKeyState: blankVerifiedState,
            localWhisperModelAvailable: false
        ).apiKeyFormSnapshot(
            for: .groq,
            formState: VoiceInkProviderAPIKeyFormState()
        )

        XCTAssertFalse(formSnapshot.isProviderReady)
        XCTAssertEqual(
            formSnapshot.loadedFormState,
            .loaded(storedKey: " \n\t ", isVerified: false)
        )
        XCTAssertTrue(formSnapshot.loadedFormState.isEditing)
    }

    func testProviderAPIKeyFormSnapshotBuildsStoredKeyEditPlanFromStoredKey() {
        let formState = VoiceInkProviderAPIKeyFormState(isEditing: false)
        let formSnapshot = VoiceInkProviderAccessSnapshot(
            apiKeyState: VoiceInkProviderAPIKeyState(
                storedKeysByProvider: [.groq: "stored-key"],
                verifiedProviders: [.groq]
            ),
            localWhisperModelAvailable: false
        ).apiKeyFormSnapshot(
            for: .groq,
            formState: formState
        )

        XCTAssertEqual(
            formSnapshot.storedKeyEditPlan,
            VoiceInkProviderAPIKeyEditPlan(
                formState: formState.editingStoredKey("stored-key"),
                verificationFlagToPersist: false
            )
        )
    }

    func testProviderAPIKeyFormSnapshotBuildsVerificationStartPlanFromRuntimeKey() {
        let storedKeySnapshot = VoiceInkProviderAccessSnapshot(
            apiKeyState: VoiceInkProviderAPIKeyState(storedKeysByProvider: [.groq: " stored-key "]),
            localWhisperModelAvailable: false
        ).apiKeyFormSnapshot(
            for: .groq,
            formState: VoiceInkProviderAPIKeyFormState(enteredKey: " \n\t ")
        )
        var verifiedCandidate: String?
        let storedKeyResult = storedKeySnapshot
            .verificationStartPlan(missingCandidatePolicy: .applyFailurePlan)
            .applyRuntimeState(
                setFormState: { state in
                    XCTAssertEqual(state.verificationProgress, .verifying)
                },
                verifyCandidate: { candidate in
                    verifiedCandidate = candidate
                    return "verified"
                }
            )

        XCTAssertEqual(storedKeyResult, "verified")
        XCTAssertEqual(verifiedCandidate, "stored-key")

        let missingKeySnapshot = VoiceInkProviderAccessSnapshot(
            apiKeyState: VoiceInkProviderAPIKeyState(),
            localWhisperModelAvailable: false
        ).apiKeyFormSnapshot(
            for: .groq,
            formState: VoiceInkProviderAPIKeyFormState(enteredKey: " \n\t ")
        )
        let missingKeyResult = missingKeySnapshot
            .verificationStartPlan(missingCandidatePolicy: .applyFailurePlan)
            .applyRuntimeState(
                setFormState: { state in
                    XCTAssertEqual(state.verificationProgress, .failure(message: nil))
                },
                verifyCandidate: { _ in "unexpected" }
            )

        XCTAssertNil(missingKeyResult)
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

    func testProviderAPIKeyStateBuildsListRows() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )

        XCTAssertEqual(
            VoiceInkProviderAPIKeyState().listRows(localWhisperModelAvailable: false).map(\.provider),
            VoiceInkProviderKind.userAPIKeyProviders
        )

        XCTAssertEqual(
            state.listRows(
                for: [.groq, .localWhisper, .deepgram],
                localWhisperModelAvailable: false
            ),
            [
                VoiceInkProviderAPIKeyListRow(
                    provider: .groq,
                    presentation: VoiceInkProviderAPIKeyListRowPresentation(
                        title: "Groq",
                        statusSystemImageName: "checkmark.seal.fill",
                        tone: .verified
                    )
                ),
                VoiceInkProviderAPIKeyListRow(
                    provider: .deepgram,
                    presentation: VoiceInkProviderAPIKeyListRowPresentation(
                        title: "Deepgram",
                        statusSystemImageName: "exclamationmark.triangle.fill",
                        tone: .attention
                    )
                )
            ]
        )
    }

    func testProviderAPIKeyStateResetVerificationWhenStoredKeyChanges() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "old-key"],
            verifiedProviders: [.groq]
        )

        let unchangedApplication = applyProviderAPIKeyStateUpdatePlan(
            state.applyingStoredAPIKey("old-key", for: .groq)
        )
        XCTAssertTrue(unchangedApplication.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? false)
        XCTAssertEqual(unchangedApplication.events, [
            "state:old-key:true",
            "key:old-key"
        ])

        let changedApplication = applyProviderAPIKeyStateUpdatePlan(
            state.applyingStoredAPIKey("new-key", for: .groq)
        )
        XCTAssertEqual(changedApplication.appliedState?.storedAPIKey(for: .groq), "new-key")
        XCTAssertFalse(changedApplication.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? true)
        XCTAssertEqual(changedApplication.events, [
            "state:new-key:false",
            "key:new-key",
            "verified:false"
        ])
    }

    func testProviderAPIKeyStateVerificationUpdatePlanOwnsPersistenceDecision() {
        let state = VoiceInkProviderAPIKeyState(storedKeysByProvider: [.groq: "groq-key"])

        let verifiedApplication = applyProviderAPIKeyStateUpdatePlan(
            state.applyingVerification(true, for: .groq)
        )
        XCTAssertTrue(verifiedApplication.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? false)
        XCTAssertEqual(verifiedApplication.events, [
            "state:groq-key:true",
            "verified:true"
        ])

        let unverifiedApplication = applyProviderAPIKeyStateUpdatePlan(
            state.applyingVerification(false, for: .groq)
        )
        XCTAssertFalse(unverifiedApplication.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? true)
        XCTAssertEqual(unverifiedApplication.events, [
            "state:groq-key:false",
            "verified:false"
        ])
    }

    func testProviderAPIKeyStateBuildsStoredKeyUpdatePlan() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "old-key"],
            verifiedProviders: [.groq]
        )

        let plan = state.applyingStoredAPIKey("new-key", for: .groq)

        let application = applyProviderAPIKeyStateUpdatePlan(plan)
        XCTAssertEqual(application.appliedState?.storedAPIKey(for: .groq), "new-key")
        XCTAssertFalse(application.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? true)
        XCTAssertEqual(application.events, [
            "state:new-key:false",
            "key:new-key",
            "verified:false"
        ])
    }

    func testProviderAPIKeyStateUpdatePlanAppliesRuntimeStateInOrder() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "old-key"],
            verifiedProviders: [.groq]
        )

        let application = applyProviderAPIKeyStateUpdatePlan(
            state.applyingStoredAPIKey("new-key", for: .groq)
        )

        XCTAssertEqual(application.events, [
            "state:new-key:false",
            "key:new-key",
            "verified:false"
        ])
    }

    func testProviderAPIKeyStateUpdatePlanSkipsRuntimeApplicationWhenNoPersistenceActions() {
        let plan = VoiceInkProviderAPIKeyState()
            .applyingVerificationPlan(
                VoiceInkProviderAPIKeyVerificationApplicationPlan(
                    progress: .failure(message: "bad request"),
                    keyToSave: nil,
                    shouldMarkKeyVerified: false
                ),
                for: .groq
            )
        let application = applyProviderAPIKeyStateUpdatePlan(plan)

        XCTAssertEqual(application.events, [])
        XCTAssertNil(application.appliedState)
    }

    private func applyProviderAPIKeyStateUpdatePlan(
        _ plan: VoiceInkProviderAPIKeyStateUpdatePlan,
        provider: VoiceInkProviderKind = .groq
    ) -> (appliedState: VoiceInkProviderAPIKeyState?, events: [String]) {
        var appliedState: VoiceInkProviderAPIKeyState?
        var events: [String] = []

        plan.applyRuntimeState(
            setAPIKeyState: { state in
                appliedState = state
                events.append(
                    "state:\(state.storedAPIKey(for: provider)):\(state.isReady(for: provider, localWhisperModelAvailable: false))"
                )
            },
            persistStoredKey: { key in
                events.append("key:\(key)")
            },
            persistVerificationFlag: { flag in
                events.append("verified:\(flag)")
            }
        )

        return (appliedState, events)
    }

    func testProviderAPIKeyStateBuildsVerificationUpdatePlan() {
        let state = VoiceInkProviderAPIKeyState(storedKeysByProvider: [.groq: "groq-key"])

        let plan = state.applyingVerification(true, for: .groq)

        let application = applyProviderAPIKeyStateUpdatePlan(plan)
        XCTAssertTrue(application.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? false)
        XCTAssertEqual(application.events, [
            "state:groq-key:true",
            "verified:true"
        ])
    }

    func testProviderAPIKeyStateBuildsStoredKeyEditUpdatePlan() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )
        let editPlan = VoiceInkProviderAPIKeyEditPlan(
            formState: .loaded(storedKey: "groq-key", isVerified: true),
            verificationFlagToPersist: false
        )

        let plan = state.applyingEditPlan(editPlan, for: .groq)

        let application = applyProviderAPIKeyStateUpdatePlan(plan)
        XCTAssertFalse(application.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? true)
        XCTAssertEqual(application.events, [
            "state:groq-key:false",
            "verified:false"
        ])
    }

    func testProviderAPIKeyStateBuildsVerificationApplicationUpdatePlan() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.groq: "old-key"],
            verifiedProviders: [.groq]
        )
        let successPlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "new-key",
            shouldMarkKeyVerified: true
        )
        let failurePlan = VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: "bad request"),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )

        let plan = state.applyingVerificationPlan(successPlan, for: .groq)
        let ignoredPlan = state.applyingVerificationPlan(failurePlan, for: .groq)

        let application = applyProviderAPIKeyStateUpdatePlan(plan)
        XCTAssertEqual(application.appliedState?.storedAPIKey(for: .groq), "new-key")
        XCTAssertTrue(application.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? false)
        XCTAssertEqual(application.events, [
            "state:new-key:true",
            "key:new-key",
            "verified:false",
            "verified:true"
        ])
        XCTAssertNil(applyProviderAPIKeyStateUpdatePlan(ignoredPlan).appliedState)
    }

    func testProviderAPIKeyStateUpdatePlanIgnoresNonUserKeyProviders() {
        let state = VoiceInkProviderAPIKeyState()

        let verificationPlan = state.applyingVerification(true, for: .localWhisper)
        let storagePlan = state.applyingStoredAPIKey("ignored", for: .localWhisper)

        XCTAssertEqual(applyProviderAPIKeyStateUpdatePlan(verificationPlan, provider: .localWhisper).events, [])
        XCTAssertEqual(applyProviderAPIKeyStateUpdatePlan(storagePlan, provider: .localWhisper).events, [])
    }

    func testRuntimeAPIKeyIfAvailableFollowsProviderAccessPolicyAndBlankRules() {
        XCTAssertEqual(VoiceInkProviderKind.groq.runtimeAPIKeyIfAvailable(userAPIKey: "groq-key"), "groq-key")
        XCTAssertNil(VoiceInkProviderKind.groq.runtimeAPIKeyIfAvailable(userAPIKey: " \n "))
        XCTAssertEqual(VoiceInkProviderKind.localWhisper.runtimeAPIKeyIfAvailable(userAPIKey: ""), "local")
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

    }

    func testAvailableProvidersFiltersByModelUseAndReadiness() {
        let readyProviders: Set<VoiceInkProviderKind> = [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper]

        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .transcription) { readyProviders.contains($0) },
            [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper]
        )

        XCTAssertEqual(
            VoiceInkProviderKind.availableProviders(for: .postProcessing) { readyProviders.contains($0) },
            [.groq]
        )
    }

    func testProviderSelectabilityKeepsReadinessAndModelSupportSeparate() {
        XCTAssertTrue(VoiceInkProviderKind.groq.isSelectable(for: .transcription))
        XCTAssertTrue(VoiceInkProviderKind.groq.isSelectable(for: .postProcessing))
        XCTAssertTrue(VoiceInkProviderKind.localWhisper.isSelectable(for: .transcription))
        XCTAssertFalse(VoiceInkProviderKind.localWhisper.isSelectable(for: .postProcessing))
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
