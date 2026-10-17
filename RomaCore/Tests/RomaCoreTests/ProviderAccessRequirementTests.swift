import Foundation
import Security
@testable import RomaCore

final class ProviderAccessRequirementTests: XCTestCase {
    func testBaseQueryPreservesSharedAppServiceAndAccount() {
        let query = RomaKeychainQuery.base(account: "groqAPIKey")

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, RomaAppIdentity.bundleIdentifier)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "groqAPIKey")
        XCTAssertEqual(booleanValue(query[kSecUseDataProtectionKeychain as String]), true)
        XCTAssertEqual(booleanValue(query[kSecAttrSynchronizable as String]), true)
    }

    func testBaseQueryCanDisableSyncableForMacOSCallers() {
        let query = RomaKeychainQuery.base(account: "provider", syncable: false)

        XCTAssertNil(query[kSecAttrSynchronizable as String])
    }

    func testAddQueryAddsValueData() {
        let data = Data("secret".utf8)
        let query = RomaKeychainQuery.add(data: data, account: "provider")

        XCTAssertEqual(query[kSecValueData as String] as? Data, data)
    }

    func testCopyDataQueryRequestsOneDataResult() {
        let query = RomaKeychainQuery.copyData(account: "provider")

        XCTAssertEqual(booleanValue(query[kSecReturnData as String]), true)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
    }

    func testDeleteQueryUsesBaseLookupShape() {
        let query = RomaKeychainQuery.delete(account: "provider", syncable: false)

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, RomaAppIdentity.bundleIdentifier)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "provider")
        XCTAssertEqual(booleanValue(query[kSecUseDataProtectionKeychain as String]), true)
        XCTAssertNil(query[kSecAttrSynchronizable as String])
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertNil(query[kSecReturnData as String])
        XCTAssertNil(query[kSecMatchLimit as String])
    }

    func testExistsQuerySuppressesDataReturn() {
        let query = RomaKeychainQuery.exists(account: "provider")

        XCTAssertEqual(booleanValue(query[kSecReturnData as String]), false)
    }

    func testLoadResultReportsSuccessStatus() {
        let data = Data("secret".utf8)

        XCTAssertTrue(RomaKeychainLoadResult(status: errSecSuccess, data: data).isSuccess)
        XCTAssertFalse(RomaKeychainLoadResult(status: errSecItemNotFound, data: nil).isSuccess)
    }

    func testStringLoadResultDecodesUTF8Values() {
        let data = Data("secret".utf8)
        let result = RomaKeychainStringLoadResult(status: errSecSuccess, data: data)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.value, "secret")
    }

    func testStringLoadResultRejectsInvalidUTF8DataButKeepsStatus() {
        let result = RomaKeychainStringLoadResult(status: errSecSuccess, data: Data([0xff]))

        XCTAssertTrue(result.isSuccess)
        XCTAssertNil(result.value)
    }

    func testValueStoreStringEncodingAndDeleteStatusPolicy() {
        XCTAssertEqual(
            RomaKeychainValueStore.data(forString: "secret"),
            Data("secret".utf8)
        )
        XCTAssertEqual(
            RomaKeychainValueStore.string(from: Data("secret".utf8)),
            "secret"
        )
        XCTAssertNil(RomaKeychainValueStore.string(from: nil))
        XCTAssertTrue(RomaKeychainValueStore.isSuccessfulDeleteStatus(errSecSuccess))
        XCTAssertTrue(RomaKeychainValueStore.isSuccessfulDeleteStatus(errSecItemNotFound))
        XCTAssertFalse(RomaKeychainValueStore.isSuccessfulDeleteStatus(errSecAuthFailed))
    }

    func testKeychainDiagnosticsPreserveMacOSAdapterLogCopy() {
        XCTAssertEqual(
            RomaKeychainDiagnostics.valueEncodingFailureMessage(key: "groqAPIKey"),
            "Failed to convert value to data for key: groqAPIKey"
        )
        XCTAssertEqual(
            RomaKeychainDiagnostics.itemLoadFailureMessage(key: "groqAPIKey", status: errSecAuthFailed),
            "Failed to retrieve keychain item for key: groqAPIKey, status: \(errSecAuthFailed)"
        )
        XCTAssertEqual(
            RomaKeychainDiagnostics.itemDeleteSuccessMessage(key: "groqAPIKey"),
            "Successfully deleted keychain item for key: groqAPIKey"
        )
        XCTAssertEqual(
            RomaKeychainDiagnostics.itemDeleteFailureMessage(key: "groqAPIKey", status: errSecAuthFailed),
            "Failed to delete keychain item for key: groqAPIKey, status: \(errSecAuthFailed)"
        )
        XCTAssertEqual(
            RomaKeychainDiagnostics.itemSaveSuccessMessage(key: "groqAPIKey"),
            "Successfully saved keychain item for key: groqAPIKey"
        )
        XCTAssertEqual(
            RomaKeychainDiagnostics.itemSaveFailureMessage(key: "groqAPIKey", status: errSecAuthFailed),
            "Failed to save keychain item for key: groqAPIKey, status: \(errSecAuthFailed)"
        )
    }

    func testAccountUsesSharedProviderAccessRequirement() {
        XCTAssertEqual(
            RomaProviderAPIKeyStorage.account(for: .groq),
            RomaProviderAPIKeyAccount.groq
        )
        XCTAssertEqual(
            RomaProviderAPIKeyStorage.account(for: .elevenLabs),
            RomaProviderAPIKeyAccount.elevenLabs
        )
        XCTAssertNil(RomaProviderAPIKeyStorage.account(for: .localWhisper))
    }

    func testStoredKeyLoadsThroughProviderAccountAndDefaultsToEmpty() {
        var requestedAccounts: [String] = []
        let storedKey = RomaProviderAPIKeyStorage.storedKey(for: .elevenLabs) { account in
            requestedAccounts.append(account)
            return "$ELEVENLABS_API_KEY"
        }

        XCTAssertEqual(storedKey, "$ELEVENLABS_API_KEY")
        XCTAssertEqual(requestedAccounts, [RomaProviderAPIKeyAccount.elevenLabs])

        let missingKey = RomaProviderAPIKeyStorage.storedKey(for: .groq) { _ in nil }
        XCTAssertEqual(missingKey, "")
    }

    func testStoredKeySkipsProvidersWithoutUserKeyAccounts() {
        var didLoad = false
        let storedKey = RomaProviderAPIKeyStorage.storedKey(for: .localWhisper) { _ in
            didLoad = true
            return "should-not-load"
        }

        XCTAssertEqual(storedKey, "")
        XCTAssertFalse(didLoad)
    }

    func testSaveStoredKeyTargetsProviderAccountAndReportsFailureStatus() {
        var savedValues: [(key: String, account: String)] = []
        let success = RomaProviderAPIKeyStorage.saveStoredKey("secret", for: .groq) { key, account in
            savedValues.append((key, account))
            return errSecSuccess
        }

        XCTAssertEqual(savedValues.count, 1)
        XCTAssertEqual(savedValues.first?.key, "secret")
        XCTAssertEqual(savedValues.first?.account, RomaProviderAPIKeyAccount.groq)
        XCTAssertEqual(success.account, RomaProviderAPIKeyAccount.groq)
        XCTAssertEqual(success.status, errSecSuccess)
        XCTAssertFalse(success.shouldReportFailure)

        let failure = RomaProviderAPIKeyStorage.saveStoredKey("secret", for: .groq) { _, _ in
            errSecAuthFailed
        }
        XCTAssertTrue(failure.shouldReportFailure)
    }

    func testSaveAndDeleteSkipProvidersWithoutUserKeyAccounts() {
        var didSave = false
        let saveResult = RomaProviderAPIKeyStorage.saveStoredKey("secret", for: .localWhisper) { _, _ in
            didSave = true
            return errSecSuccess
        }
        XCTAssertNil(saveResult.account)
        XCTAssertNil(saveResult.status)
        XCTAssertFalse(didSave)

        var didDelete = false
        let deleteResult = RomaProviderAPIKeyStorage.deleteStoredKey(for: .localWhisper) { _ in
            didDelete = true
            return errSecSuccess
        }
        XCTAssertNil(deleteResult.account)
        XCTAssertNil(deleteResult.status)
        XCTAssertFalse(didDelete)
    }

    func testDeleteStoredKeysTargetsProviderAccountsAndSkipsProvidersWithoutUserKeyAccounts() {
        var deletedAccounts: [String] = []
        let results = RomaProviderAPIKeyStorage.deleteStoredKeys(
            for: [.groq, .localWhisper, .elevenLabs]
        ) { account in
            deletedAccounts.append(account)
            return account == RomaProviderAPIKeyAccount.groq ? errSecSuccess : errSecAuthFailed
        }

        XCTAssertEqual(deletedAccounts, [
            RomaProviderAPIKeyAccount.groq,
            RomaProviderAPIKeyAccount.elevenLabs
        ])
        XCTAssertEqual(results.map(\.account), [
            RomaProviderAPIKeyAccount.groq,
            nil,
            RomaProviderAPIKeyAccount.elevenLabs
        ])
        XCTAssertEqual(results.map(\.status), [
            errSecSuccess,
            nil,
            errSecAuthFailed
        ])
    }

    func testProviderAPIKeyStorageDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            RomaProviderAPIKeyStorageDiagnostics.saveFailureMessage(status: errSecAuthFailed),
            "Error saving API key to keychain: \(errSecAuthFailed)"
        )
    }

    func testProviderAPIKeyStorageDiagnosticsPreserveMacOSSuccessLogCopy() {
        let modelId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        XCTAssertEqual(
            RomaProviderAPIKeyStorageDiagnostics.savedProviderAPIKeyMessage(
                providerName: "Groq",
                keyIdentifier: RomaProviderAPIKeyAccount.groq
            ),
            "Saved API key for provider: Groq with key: \(RomaProviderAPIKeyAccount.groq)"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyStorageDiagnostics.deletedProviderAPIKeyMessage(providerName: "Groq"),
            "Deleted API key for provider: Groq"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyStorageDiagnostics.savedCustomModelAPIKeyMessage(modelId: modelId),
            "Saved API key for custom model: 11111111-2222-3333-4444-555555555555"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyStorageDiagnostics.deletedCustomModelAPIKeyMessage(modelId: modelId),
            "Deleted API key for custom model: 11111111-2222-3333-4444-555555555555"
        )
    }

    func testUserAPIKeyProvidersExposeDerivedCredentialMetadata() {
        XCTAssertEqual(
            RomaProviderKind.userAPIKeyProviders,
            [.groq, .openAI, .deepgram, .cerebras, .gemini, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .nvidia, .anthropic, .openRouter, .customAI]
        )

        let expected: [RomaProviderKind: (account: String, verificationKey: String, transport: RomaAPIKeyVerificationTransport)] = [
            .groq: (RomaProviderAPIKeyAccount.groq, "groqKeyVerified", .openAICompatibleModels),
            .openAI: (RomaProviderAPIKeyAccount.openAI, "openAIKeyVerified", .openAICompatibleModels),
            .deepgram: (RomaProviderAPIKeyAccount.deepgram, "deepgramKeyVerified", .deepgramProjects),
            .cerebras: (RomaProviderAPIKeyAccount.cerebras, "cerebrasKeyVerified", .openAICompatibleModels),
            .gemini: (RomaProviderAPIKeyAccount.gemini, "geminiKeyVerified", .geminiModels),
            .mistral: (RomaProviderAPIKeyAccount.mistral, "mistralKeyVerified", .mistralModels),
            .elevenLabs: (RomaProviderAPIKeyAccount.elevenLabs, "elevenLabsKeyVerified", .elevenLabsUser),
            .soniox: (RomaProviderAPIKeyAccount.soniox, "sonioxKeyVerified", .sonioxFiles),
            .speechmatics: (RomaProviderAPIKeyAccount.speechmatics, "speechmaticsKeyVerified", .speechmaticsJobs),
            .assemblyAI: (RomaProviderAPIKeyAccount.assemblyAI, "assemblyAIKeyVerified", .assemblyAITranscripts),
            .xai: (RomaProviderAPIKeyAccount.xAI, "xaiKeyVerified", .xaiAPIKey),
            .cartesia: (RomaProviderAPIKeyAccount.cartesia, "cartesiaKeyVerified", .cartesiaVoices),
            .nvidia: (RomaProviderAPIKeyAccount.nvidia, "nvidiaKeyVerified", .nvidiaRivaConfig),
            .anthropic: (RomaProviderAPIKeyAccount.anthropic, "anthropicKeyVerified", .anthropicMessages),
            .openRouter: (RomaProviderAPIKeyAccount.openRouter, "openRouterKeyVerified", .openAICompatibleModels),
            .customAI: (RomaProviderAPIKeyAccount.customAI, "customAIKeyVerified", .customAIChat)
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
            RomaProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "ElevenLabs"),
            "ELEVENLABS_API_KEY"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "elevenlabs"),
            "ELEVENLABS_API_KEY"
        )
        XCTAssertNil(RomaProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: "Groq"))
    }

    func testResolvedValueReturnsTrimmedLiteralKeys() {
        XCTAssertEqual(
            RomaAPIKeyReference.resolvedValue(" literal-key "),
            "literal-key"
        )
    }

    func testResolvedValueResolvesDollarEnvironmentReference() {
        XCTAssertEqual(
            RomaAPIKeyReference.resolvedValue(
                "$ELEVENLABS_API_KEY",
                environment: ["ELEVENLABS_API_KEY": "test-key"]
            ),
            "test-key"
        )
    }

    func testResolvedValueResolvesBracedEnvironmentReference() {
        XCTAssertEqual(
            RomaAPIKeyReference.resolvedValue(
                "${ELEVENLABS_API_KEY}",
                environment: ["ELEVENLABS_API_KEY": "test-key"]
            ),
            "test-key"
        )
    }

    func testResolvedValueRejectsMissingBlankAndInvalidReferences() {
        let environment = [
            "EMPTY_KEY": "",
            "WHITESPACE_KEY": " \n\t ",
            "VALID_KEY": "test-key"
        ]

        XCTAssertNil(RomaAPIKeyReference.resolvedValue(" \n\t ", environment: environment))
        XCTAssertNil(RomaAPIKeyReference.resolvedValue("$MISSING", environment: environment))
        XCTAssertNil(RomaAPIKeyReference.resolvedValue("$EMPTY_KEY", environment: environment))
        XCTAssertNil(RomaAPIKeyReference.resolvedValue("$WHITESPACE_KEY", environment: environment))
        XCTAssertNil(RomaAPIKeyReference.resolvedValue("$1INVALID", environment: environment))
        XCTAssertNil(RomaAPIKeyReference.resolvedValue("${}", environment: environment))
    }

    func testProviderAPIKeyLookupUsesResolvedStoredKeyFirst() {
        let environment = [
            "ELEVENLABS_API_KEY": "fallback-key",
            "STORED_KEY": "stored-env-key"
        ]

        XCTAssertEqual(
            RomaProviderAPIKeyLookup.usableAPIKey(
                storedKey: " literal-key ",
                providerName: "ElevenLabs",
                environment: environment
            ),
            "literal-key"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyLookup.usableAPIKey(
                storedKey: "$STORED_KEY",
                providerName: "ElevenLabs",
                environment: environment
            ),
            "stored-env-key"
        )
    }

    func testProviderAPIKeyLookupUsesProviderEnvironmentFallbackWhenStoredKeyIsMissingOrInvalid() {
        let environment = [
            "ELEVENLABS_API_KEY": "fallback-key"
        ]

        XCTAssertEqual(
            RomaProviderAPIKeyLookup.usableAPIKey(
                storedKey: nil,
                providerName: "ElevenLabs",
                environment: environment
            ),
            "fallback-key"
        )
        XCTAssertEqual(
            RomaProviderAPIKeyLookup.usableAPIKey(
                storedKey: "$MISSING",
                providerName: "elevenlabs",
                environment: environment
            ),
            "fallback-key"
        )
    }

    func testProviderAPIKeyLookupAcceptsTypedProviderKind() {
        let environment = [
            "ELEVENLABS_API_KEY": "fallback-key"
        ]

        XCTAssertEqual(
            RomaProviderAPIKeyLookup.usableAPIKey(
                storedKey: nil,
                provider: .elevenLabs,
                environment: environment
            ),
            "fallback-key"
        )
        XCTAssertNil(
            RomaProviderAPIKeyLookup.usableAPIKey(
                storedKey: nil,
                provider: .groq,
                environment: environment
            )
        )
    }

    func testProviderAPIKeyLookupRejectsBlankAndProvidersWithoutEnvironmentFallback() {
        let environment = [
            "ELEVENLABS_API_KEY": "fallback-key"
        ]

        XCTAssertNil(
            RomaProviderAPIKeyLookup.usableAPIKey(
                storedKey: " \n\t ",
                providerName: "Groq",
                environment: environment
            )
        )
        XCTAssertNil(
            RomaProviderAPIKeyLookup.usableAPIKey(
                storedKey: nil,
                providerName: "Groq",
                environment: environment
            )
        )
    }

    func testCustomModelAccountIdentifierPreservesMacOSKeychainAccountShape() {
        let id = UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!

        XCTAssertEqual(
            RomaProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: id),
            "customModel_E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE_APIKey"
        )
    }

    func testNonUserKeyProvidersKeepTheirAccessPolicy() {
        guard case .localWhisperModel = RomaProviderKind.localWhisper.accessRequirement else {
            return XCTFail("Local Whisper should use local model availability")
        }
        XCTAssertFalse(RomaProviderKind.localWhisper.requiresUserAPIKey)
        XCTAssertNil(RomaProviderKind.localWhisper.apiKeyAccount)
        XCTAssertNil(RomaProviderKind.localWhisper.apiKeyVerificationStateKey)
        XCTAssertNil(RomaProviderKind.localWhisper.apiKeyVerificationTransport)
        XCTAssertFalse(RomaProviderKind.localWhisper.canVerifyAPIKey)
    }

    func testRuntimeAPIKeyFollowsProviderAccessPolicy() {
        XCTAssertEqual(RomaProviderKind.groq.runtimeAPIKey(userAPIKey: "groq-key"), "groq-key")
        XCTAssertEqual(RomaProviderKind.localWhisper.runtimeAPIKey(userAPIKey: ""), "local")
    }

    func testLegacyVoiceInkProviderValuesNoLongerDecodeAsProviderKind() {
        let decoder = JSONDecoder()

        XCTAssertNil(try? decoder.decode(RomaProviderKind.self, from: Data(#""RomaJustTalk""#.utf8)))
        XCTAssertNil(try? decoder.decode(RomaProviderKind.self, from: Data(#""romaJustTalk""#.utf8)))
    }

    func testProviderCredentialRejectsBlankKeysWithoutNormalizingUsableKeys() {
        XCTAssertNil(RomaProviderCredential.nonBlank(nil))
        XCTAssertNil(RomaProviderCredential.nonBlank(""))
        XCTAssertNil(RomaProviderCredential.nonBlank(" \n\t "))
        XCTAssertEqual(RomaProviderCredential.nonBlank(" key-with-space "), " key-with-space ")
    }

    func testSecretPresentationReturnsNilForEmptyOrWhitespaceOnlyKeys() {
        XCTAssertNil(RomaSecretPresentation.obfuscatedAPIKey(""))
        XCTAssertNil(RomaSecretPresentation.obfuscatedAPIKey("   \n"))
    }

    func testSecretPresentationMasksShortKeysCompletely() {
        XCTAssertEqual(RomaSecretPresentation.obfuscatedAPIKey("abc123"), "••••••")
    }

    func testSecretPresentationShowsPrefixAndSuffixForLongKeys() {
        XCTAssertEqual(
            RomaSecretPresentation.obfuscatedAPIKey("sk-1234567890"),
            "sk-1•••••7890"
        )
    }

    func testSecretPresentationTrimsWhitespaceBeforeMasking() {
        XCTAssertEqual(
            RomaSecretPresentation.obfuscatedAPIKey("  abc123  "),
            "••••••"
        )
    }

    func testSecretPresentationPreservesCurrentSevenCharacterEdgeCase() {
        XCTAssertEqual(
            RomaSecretPresentation.obfuscatedAPIKey("abcdefg"),
            "abcd••••efg"
        )
    }

    func testSecretPresentationOrPlaceholderPreservesMacOSFallback() {
        XCTAssertEqual(RomaSecretPresentation.obfuscatedAPIKeyOrPlaceholder(""), "••••••••")
        XCTAssertEqual(RomaSecretPresentation.obfuscatedAPIKeyOrPlaceholder("abc123"), "••••••")
    }

    func testProviderAPIKeyDraftUsesTrimmedEnteredKeyBeforeStoredRuntimeKey() {
        let draft = RomaProviderAPIKeyDraft(
            enteredKey: " entered-key \n",
            storedRuntimeKey: "stored-key"
        )

        XCTAssertTrue(draft.hasEnteredKey)
        XCTAssertTrue(draft.canVerify)
        XCTAssertEqual(draft.verificationCandidate, "entered-key")
        XCTAssertEqual(draft.keyToSaveAfterSuccessfulVerification, "entered-key")
    }

    func testProviderAPIKeyDraftFallsBackToStoredRuntimeKeyForBlankDraft() {
        let draft = RomaProviderAPIKeyDraft(
            enteredKey: " \n\t ",
            storedRuntimeKey: " stored-runtime-key "
        )

        XCTAssertFalse(draft.hasEnteredKey)
        XCTAssertTrue(draft.canVerify)
        XCTAssertEqual(draft.verificationCandidate, " stored-runtime-key ")
        XCTAssertNil(draft.keyToSaveAfterSuccessfulVerification)
    }

    func testProviderAPIKeyDraftRejectsBlankDraftAndBlankStoredRuntimeKey() {
        let draft = RomaProviderAPIKeyDraft(
            enteredKey: " \n\t ",
            storedRuntimeKey: "\n"
        )

        XCTAssertFalse(draft.hasEnteredKey)
        XCTAssertFalse(draft.canVerify)
        XCTAssertNil(draft.verificationCandidate)
        XCTAssertNil(draft.keyToSaveAfterSuccessfulVerification)
    }

    func testProviderAPIKeyVerificationApplicationPlanSavesEnteredKeyOnSuccess() {
        let draft = RomaProviderAPIKeyDraft(
            enteredKey: " entered-key \n",
            storedRuntimeKey: "stored-key"
        )

        let plan = draft.verificationApplicationPlan(for: RomaAPIKeyVerificationResult(
            isValid: true,
            errorMessage: nil
        ))

        XCTAssertEqual(plan.progress, .success)
        XCTAssertEqual(plan.keyToSave, "entered-key")
        XCTAssertTrue(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyVerificationApplicationPlanKeepsStoredKeyOnSuccess() {
        let draft = RomaProviderAPIKeyDraft(
            enteredKey: " \n\t ",
            storedRuntimeKey: "stored-key"
        )

        let plan = draft.verificationApplicationPlan(for: RomaAPIKeyVerificationResult(
            isValid: true,
            errorMessage: nil
        ))

        XCTAssertEqual(plan.progress, .success)
        XCTAssertNil(plan.keyToSave)
        XCTAssertTrue(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyVerificationApplicationPlanPreservesFailureMessage() {
        let draft = RomaProviderAPIKeyDraft(
            enteredKey: "bad-key",
            storedRuntimeKey: nil
        )

        let plan = draft.verificationApplicationPlan(for: RomaAPIKeyVerificationResult(
            isValid: false,
            errorMessage: "bad request"
        ))

        XCTAssertEqual(plan.progress, .failure(message: "bad request"))
        XCTAssertNil(plan.keyToSave)
        XCTAssertFalse(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyVerificationApplicationPlanBuildsSuccessPersistencePlan() {
        let successPlan = RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "entered-key",
            shouldMarkKeyVerified: true
        )
        let failurePlan = RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: "bad request"),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )

        XCTAssertEqual(
            successPlan.successPersistencePlan,
            RomaProviderAPIKeyVerificationPersistencePlan(
                keyToSave: "entered-key",
                verificationFlagToPersist: true
            )
        )
        XCTAssertNil(failurePlan.successPersistencePlan)
    }

    func testProviderAPIKeyVerificationApplicationPlanAppliesOrderedPersistenceRuntimeState() {
        let enteredKeySuccessPlan = RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "entered-key",
            shouldMarkKeyVerified: true
        )
        let storedKeySuccessPlan = RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: nil,
            shouldMarkKeyVerified: true
        )
        let failurePlan = RomaProviderAPIKeyVerificationApplicationPlan(
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
        let enteredKeySuccessPlan = RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "entered-key",
            shouldMarkKeyVerified: true
        )
        let storedKeySuccessPlan = RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: nil,
            shouldMarkKeyVerified: true
        )
        let failurePlan = RomaProviderAPIKeyVerificationApplicationPlan(
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
        let plan = RomaProviderAPIKeyDraft.missingVerificationCandidatePlan()

        XCTAssertEqual(plan.progress, .failure(message: nil))
        XCTAssertNil(plan.keyToSave)
        XCTAssertFalse(plan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyFormStateLoadsStoredKeyAndVerificationEditingPolicy() {
        let verifiedState = RomaProviderAPIKeyFormState.loaded(
            storedKey: "stored-key",
            isVerified: true
        )
        let unverifiedState = RomaProviderAPIKeyFormState.loaded(
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
        let enteredState = RomaProviderAPIKeyFormState(enteredKey: " entered-key \n")
        let storedFallbackState = RomaProviderAPIKeyFormState(enteredKey: " \n\t ")

        let enteredDraft = enteredState.draft(storedRuntimeKey: "stored-key")
        let storedFallbackDraft = storedFallbackState.draft(storedRuntimeKey: " stored-key ")

        XCTAssertEqual(enteredDraft.verificationCandidate, "entered-key")
        XCTAssertEqual(enteredDraft.keyToSaveAfterSuccessfulVerification, "entered-key")
        XCTAssertEqual(storedFallbackDraft.verificationCandidate, " stored-key ")
        XCTAssertNil(storedFallbackDraft.keyToSaveAfterSuccessfulVerification)
    }

    func testProviderAPIKeyFormStateEditingStoredKeyResetsProgressAndOpensEditing() {
        let state = RomaProviderAPIKeyFormState(
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
        let state = RomaProviderAPIKeyFormState(
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
        let state = RomaProviderAPIKeyFormState(
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
        let state = RomaProviderAPIKeyFormState(
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
        let state = RomaProviderAPIKeyFormState(
            enteredKey: " entered-key \n",
            verificationProgress: .failure(message: "bad request"),
            isEditing: true
        )

        let plan = state.verificationStartPlan(
            storedRuntimeKey: "stored-key",
            missingCandidatePolicy: .keepCurrentState
        )

        var formState: RomaProviderAPIKeyFormState?
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
        let state = RomaProviderAPIKeyFormState(
            enteredKey: " \n\t ",
            verificationProgress: .idle,
            isEditing: true
        )

        let plan = state.verificationStartPlan(
            storedRuntimeKey: nil,
            missingCandidatePolicy: .keepCurrentState
        )

        var didVerifyCandidate = false
        var formState: RomaProviderAPIKeyFormState?
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
        let state = RomaProviderAPIKeyFormState(
            enteredKey: " \n\t ",
            verificationProgress: .idle,
            isEditing: true
        )

        let plan = state.verificationStartPlan(
            storedRuntimeKey: nil,
            missingCandidatePolicy: .applyFailurePlan
        )

        var didVerifyCandidate = false
        var formState: RomaProviderAPIKeyFormState?
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
        let state = RomaProviderAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .verifying,
            isEditing: true
        )
        let successPlan = RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "entered-key",
            shouldMarkKeyVerified: true
        )
        let failurePlan = RomaProviderAPIKeyVerificationApplicationPlan(
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
        let startState = RomaProviderAPIKeyFormState(
            enteredKey: " verified-key ",
            verificationProgress: .idle,
            isEditing: true
        )
        let startPlan = startState.verificationStartPlan(
            storedRuntimeKey: "stored-key",
            missingCandidatePolicy: .keepCurrentState
        )
        let currentState = RomaProviderAPIKeyFormState(
            enteredKey: "edited-while-verifying",
            verificationProgress: .verifying,
            isEditing: true
        )
        let result = RomaAPIKeyVerificationResult(isValid: true, errorMessage: nil)

        let completionPlan = currentState.verificationCompletionPlan(
            startPlan: startPlan,
            result: result
        )

        XCTAssertEqual(completionPlan.formState.enteredKey, "edited-while-verifying")
        XCTAssertEqual(
            completionPlan.formState.verificationProgress,
            RomaProviderAPIKeyVerificationProgress.success
        )
        XCTAssertFalse(completionPlan.formState.isEditing)
        XCTAssertEqual(completionPlan.applicationPlan.keyToSave, "verified-key")
        XCTAssertTrue(completionPlan.applicationPlan.shouldMarkKeyVerified)
    }

    func testProviderAPIKeyVerificationCompletionPlanAppliesRuntimeStateInOrderAndReturnsResult() {
        let completionPlan = RomaProviderAPIKeyFormState(
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
            RomaProviderAPIKeyFormState(verificationProgress: .idle)
                .iOSVisibleResultFeedback(isProviderReady: false)
        )
        XCTAssertEqual(
            RomaProviderAPIKeyFormState(verificationProgress: .success)
                .iOSVisibleResultFeedback(isProviderReady: false),
            RomaProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback
        )
        XCTAssertEqual(
            RomaProviderAPIKeyFormState(verificationProgress: .failure(message: "Forbidden"))
                .iOSVisibleResultFeedback(isProviderReady: false),
            RomaProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                systemImageName: "xmark.seal",
                tone: .failure
            )
        )
        XCTAssertNil(
            RomaProviderAPIKeyFormState(verificationProgress: .success)
                .iOSVisibleResultFeedback(isProviderReady: true)
        )
    }

    func testProviderAPIKeyFormStateOwnsIOSStoredKeyPresentation() {
        XCTAssertEqual(
            RomaProviderAPIKeyFormState(isEditing: false)
                .iOSStoredKeyPresentation(storedKey: "abc123"),
            RomaProviderAPIKeyStoredKeyPresentation(
                feedback: RomaProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback,
                obfuscatedKey: "••••••"
            )
        )
        XCTAssertEqual(
            RomaProviderAPIKeyFormState(isEditing: false)
                .iOSStoredKeyPresentation(storedKey: " \n\t "),
            RomaProviderAPIKeyStoredKeyPresentation(
                feedback: RomaProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback,
                obfuscatedKey: nil
            )
        )
        XCTAssertNil(
            RomaProviderAPIKeyFormState(isEditing: true)
                .iOSStoredKeyPresentation(storedKey: "abc123")
        )
    }

    func testProviderAPIKeyFormStateOwnsIOSControlPresentation() {
        let enteredKey = RomaProviderAPIKeyFormState(enteredKey: " entered-key ")
            .iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertFalse(enteredKey.isSaveButtonDisabled)
        XCTAssertFalse(enteredKey.isVerificationProgressVisible)
        XCTAssertFalse(enteredKey.isVerifyButtonDisabled)

        let blankStoredKey = RomaProviderAPIKeyFormState(enteredKey: " \n\t ")
            .iOSControlPresentation(storedRuntimeKey: "stored-key")
        XCTAssertTrue(blankStoredKey.isSaveButtonDisabled)
        XCTAssertFalse(blankStoredKey.isVerificationProgressVisible)
        XCTAssertFalse(blankStoredKey.isVerifyButtonDisabled)

        let blankMissingStoredKey = RomaProviderAPIKeyFormState(enteredKey: " \n\t ")
            .iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertTrue(blankMissingStoredKey.isSaveButtonDisabled)
        XCTAssertFalse(blankMissingStoredKey.isVerificationProgressVisible)
        XCTAssertTrue(blankMissingStoredKey.isVerifyButtonDisabled)

        let verifying = RomaProviderAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .verifying
        ).iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertFalse(verifying.isSaveButtonDisabled)
        XCTAssertTrue(verifying.isVerificationProgressVisible)
        XCTAssertTrue(verifying.isVerifyButtonDisabled)
    }

    func testProviderAPIKeyFormStateOwnsMacOSCardControlPresentation() {
        XCTAssertEqual(
            RomaProviderAPIKeyFormState(enteredKey: " entered-key ")
                .macOSCardControlPresentation(storedRuntimeKey: nil),
            RomaProviderAPIKeyCardControlPresentation(
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
            RomaProviderAPIKeyFormState(enteredKey: " \n\t ")
                .macOSCardControlPresentation(storedRuntimeKey: nil)
                .isVerifyButtonDisabled,
            true
        )
        XCTAssertEqual(
            RomaProviderAPIKeyFormState(
                enteredKey: "entered-key",
                verificationProgress: .verifying
            ).macOSCardControlPresentation(storedRuntimeKey: nil),
            RomaProviderAPIKeyCardControlPresentation(
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
            RomaProviderAPIKeyFormState(
                enteredKey: "stored-key",
                verificationProgress: .success,
                isEditing: false
            ).macOSCardControlPresentation(storedRuntimeKey: nil),
            RomaProviderAPIKeyCardControlPresentation(
                isAPIKeyFieldDisabled: false,
                isVerifyProgressVisible: false,
                isVerifyButtonDisabled: false,
                verifyButtonTitle: "Verify",
                verifyButtonSystemImageName: "checkmark",
                isVerifyButtonSuccess: true,
                inlineFeedback: RomaProviderAPIKeyVerificationFeedback(
                    text: "API key verified successfully!",
                    tone: .success
                )
            )
        )
    }

    func testProviderAPIKeyFormControlPresentationOwnsIOSVerifyRuntimeActionMapping() {
        let enabledControl = RomaProviderAPIKeyFormState(enteredKey: "entered-key")
            .iOSControlPresentation(storedRuntimeKey: nil)
        var didVerify = false
        let enabledAction = enabledControl.verifyRuntimeAction {
            didVerify = true
        }

        XCTAssertTrue(enabledAction != nil)
        enabledAction?()
        XCTAssertTrue(didVerify)

        let disabledControl = RomaProviderAPIKeyFormState(enteredKey: "")
            .iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertFalse(disabledControl.isVerificationProgressVisible)
        XCTAssertTrue(disabledControl.isVerifyButtonDisabled)
        XCTAssertNil(disabledControl.verifyRuntimeAction {})

        let progressControl = RomaProviderAPIKeyFormState(
            enteredKey: "entered-key",
            verificationProgress: .verifying
        ).iOSControlPresentation(storedRuntimeKey: nil)
        XCTAssertTrue(progressControl.isVerificationProgressVisible)
        XCTAssertTrue(progressControl.isVerifyButtonDisabled)
        XCTAssertNil(progressControl.verifyRuntimeAction {})
    }

    func testProviderAPIKeyFormControlPresentationOwnsIOSSaveRuntimeActionMapping() {
        var didSave = false

        let saveAction = RomaProviderAPIKeyFormState(enteredKey: "entered-key")
            .iOSControlPresentation(storedRuntimeKey: nil)
            .saveRuntimeAction {
            didSave = true
        }

        XCTAssertTrue(saveAction != nil)
        saveAction?()
        XCTAssertTrue(didSave)
        XCTAssertNil(RomaProviderAPIKeyFormState(enteredKey: "")
            .iOSControlPresentation(storedRuntimeKey: nil)
            .saveRuntimeAction {})
    }

    func testProviderAPIKeyFormPresentationBuildsProviderCopy() {
        let presentation = RomaProviderKind.deepgram.apiKeyFormPresentation

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
        let presentation = RomaProviderAPIKeyCardPresentation(providerDisplayName: "Cartesia")

        XCTAssertEqual(presentation.configureButtonTitle, "Configure")
        XCTAssertEqual(presentation.configureButtonSystemImageName, "gear")
        XCTAssertEqual(presentation.removeAPIKeyButtonTitle, "Remove API Key")
        XCTAssertEqual(presentation.removeAPIKeyButtonSystemImageName, "trash")
        XCTAssertEqual(presentation.configurationSectionTitle, "API Key Configuration")
        XCTAssertEqual(presentation.apiKeyFieldPlaceholder, "Enter your Cartesia API key")
    }

    func testProviderAPIKeyStateResolvesStoredRuntimeKeysAndNonUserProviders() {
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: " groq-key "],
            verifiedProviders: [.groq]
        )

        XCTAssertEqual(state.storedAPIKey(for: .groq), " groq-key ")
        XCTAssertEqual(state.runtimeAPIKey(for: .groq), "groq-key")
        XCTAssertEqual(state.runtimeAPIKey(for: .localWhisper), "local")
    }

    func testProviderAPIKeyStateLoadsStoredKeysForUserKeyProvidersOnly() {
        let state = RomaProviderAPIKeyState.loadingStoredKeys(
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
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )

        XCTAssertTrue(state.isReady(for: .groq, localWhisperModelAvailable: false))
        XCTAssertFalse(state.isReady(for: .deepgram, localWhisperModelAvailable: false))
        XCTAssertTrue(state.isReady(for: .localWhisper, localWhisperModelAvailable: true))
        XCTAssertFalse(state.isReady(for: .localWhisper, localWhisperModelAvailable: false))
    }

    func testProviderAPIKeyStateBuildsAvailableProvidersForModelUse() {
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [
                .groq: "groq-key",
                .deepgram: "deepgram-key",
                .mistral: "mistral-key",
                .elevenLabs: "elevenlabs-key",
                .soniox: "soniox-key",
                .speechmatics: "speechmatics-key",
                .assemblyAI: "assemblyai-key",
                .xai: "xai-key",
                .anthropic: "anthropic-key",
                .openRouter: "openrouter-key"
            ],
            verifiedProviders: [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .anthropic, .openRouter]
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
            [.groq, .mistral, .anthropic, .openRouter]
        )
    }

    func testProviderAccessSnapshotUsesProviderReadyNaming() {
        let readyKeyState = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )
        let blankVerifiedKeyState = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: " \n\t "],
            verifiedProviders: [.groq]
        )

        XCTAssertTrue(
            RomaProviderAccessSnapshot(
                apiKeyState: readyKeyState,
                localWhisperModelAvailable: false
            ).isProviderReady(for: .groq)
        )
        XCTAssertFalse(
            RomaProviderAccessSnapshot(
                apiKeyState: blankVerifiedKeyState,
                localWhisperModelAvailable: false
            ).isProviderReady(for: .groq)
        )
        XCTAssertTrue(
            RomaProviderAccessSnapshot(
                apiKeyState: readyKeyState,
                localWhisperModelAvailable: true
            ).isProviderReady(for: .localWhisper)
        )
        XCTAssertFalse(
            RomaProviderAccessSnapshot(
                apiKeyState: readyKeyState,
                localWhisperModelAvailable: false
            ).isProviderReady(for: .localWhisper)
        )
    }

    func testProviderAccessSnapshotBuildsIOSAccessSurfacesFromLocalModelFact() {
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )
        let snapshotWithLocalModel = RomaProviderAccessSnapshot(
            apiKeyState: state,
            localWhisperModelAvailable: true
        )
        let snapshotWithoutLocalModel = RomaProviderAccessSnapshot(
            apiKeyState: state,
            localWhisperModelAvailable: false
        )

        XCTAssertTrue(snapshotWithLocalModel.isProviderReady(for: .groq))
        XCTAssertTrue(snapshotWithLocalModel.isProviderReady(for: .localWhisper))
        XCTAssertFalse(snapshotWithoutLocalModel.isProviderReady(for: .localWhisper))
        XCTAssertEqual(snapshotWithLocalModel.apiKeyListRows().map(\.provider), RomaProviderKind.userAPIKeyProviders)
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
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: " groq-key "],
            verifiedProviders: [.groq]
        )
        let accessSnapshot = RomaProviderAccessSnapshot(
            apiKeyState: state,
            localWhisperModelAvailable: false
        )
        let formState = RomaProviderAPIKeyFormState(
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
        let blankVerifiedState = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: " \n\t "],
            verifiedProviders: [.groq]
        )
        let formSnapshot = RomaProviderAccessSnapshot(
            apiKeyState: blankVerifiedState,
            localWhisperModelAvailable: false
        ).apiKeyFormSnapshot(
            for: .groq,
            formState: RomaProviderAPIKeyFormState()
        )

        XCTAssertFalse(formSnapshot.isProviderReady)
        XCTAssertEqual(
            formSnapshot.loadedFormState,
            .loaded(storedKey: " \n\t ", isVerified: false)
        )
        XCTAssertTrue(formSnapshot.loadedFormState.isEditing)
    }

    func testProviderAPIKeyFormSnapshotBuildsStoredKeyEditPlanFromStoredKey() {
        let formState = RomaProviderAPIKeyFormState(isEditing: false)
        let formSnapshot = RomaProviderAccessSnapshot(
            apiKeyState: RomaProviderAPIKeyState(
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
            RomaProviderAPIKeyEditPlan(
                formState: formState.editingStoredKey("stored-key"),
                verificationFlagToPersist: false
            )
        )
    }

    func testProviderAPIKeyFormSnapshotBuildsVerificationStartPlanFromRuntimeKey() {
        let storedKeySnapshot = RomaProviderAccessSnapshot(
            apiKeyState: RomaProviderAPIKeyState(storedKeysByProvider: [.groq: " stored-key "]),
            localWhisperModelAvailable: false
        ).apiKeyFormSnapshot(
            for: .groq,
            formState: RomaProviderAPIKeyFormState(enteredKey: " \n\t ")
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

        let missingKeySnapshot = RomaProviderAccessSnapshot(
            apiKeyState: RomaProviderAPIKeyState(),
            localWhisperModelAvailable: false
        ).apiKeyFormSnapshot(
            for: .groq,
            formState: RomaProviderAPIKeyFormState(enteredKey: " \n\t ")
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
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )

        XCTAssertEqual(
            state.listRowPresentation(for: .groq, localWhisperModelAvailable: false),
            RomaProviderAPIKeyListRowPresentation(
                title: "Groq",
                statusSystemImageName: "checkmark.seal.fill",
                tone: .verified
            )
        )
        XCTAssertEqual(
            state.listRowPresentation(for: .deepgram, localWhisperModelAvailable: false),
            RomaProviderAPIKeyListRowPresentation(
                title: "Deepgram",
                statusSystemImageName: "exclamationmark.triangle.fill",
                tone: .attention
            )
        )
    }

    func testProviderAPIKeyStateBuildsListRows() {
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )

        XCTAssertEqual(
            RomaProviderAPIKeyState().listRows(localWhisperModelAvailable: false).map(\.provider),
            RomaProviderKind.userAPIKeyProviders
        )

        XCTAssertEqual(
            state.listRows(
                for: [.groq, .localWhisper, .deepgram],
                localWhisperModelAvailable: false
            ),
            [
                RomaProviderAPIKeyListRow(
                    provider: .groq,
                    presentation: RomaProviderAPIKeyListRowPresentation(
                        title: "Groq",
                        statusSystemImageName: "checkmark.seal.fill",
                        tone: .verified
                    )
                ),
                RomaProviderAPIKeyListRow(
                    provider: .deepgram,
                    presentation: RomaProviderAPIKeyListRowPresentation(
                        title: "Deepgram",
                        statusSystemImageName: "exclamationmark.triangle.fill",
                        tone: .attention
                    )
                )
            ]
        )
    }

    func testProviderAPIKeyStateResetVerificationWhenStoredKeyChanges() {
        let state = RomaProviderAPIKeyState(
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
        let state = RomaProviderAPIKeyState(storedKeysByProvider: [.groq: "groq-key"])

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
        let state = RomaProviderAPIKeyState(
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
        let state = RomaProviderAPIKeyState(
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
        let plan = RomaProviderAPIKeyState()
            .applyingVerificationPlan(
                RomaProviderAPIKeyVerificationApplicationPlan(
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
        _ plan: RomaProviderAPIKeyStateUpdatePlan,
        provider: RomaProviderKind = .groq
    ) -> (appliedState: RomaProviderAPIKeyState?, events: [String]) {
        var appliedState: RomaProviderAPIKeyState?
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
        let state = RomaProviderAPIKeyState(storedKeysByProvider: [.groq: "groq-key"])

        let plan = state.applyingVerification(true, for: .groq)

        let application = applyProviderAPIKeyStateUpdatePlan(plan)
        XCTAssertTrue(application.appliedState?.isReady(for: .groq, localWhisperModelAvailable: false) ?? false)
        XCTAssertEqual(application.events, [
            "state:groq-key:true",
            "verified:true"
        ])
    }

    func testProviderAPIKeyStateBuildsStoredKeyEditUpdatePlan() {
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: "groq-key"],
            verifiedProviders: [.groq]
        )
        let editPlan = RomaProviderAPIKeyEditPlan(
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
        let state = RomaProviderAPIKeyState(
            storedKeysByProvider: [.groq: "old-key"],
            verifiedProviders: [.groq]
        )
        let successPlan = RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: "new-key",
            shouldMarkKeyVerified: true
        )
        let failurePlan = RomaProviderAPIKeyVerificationApplicationPlan(
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
        let state = RomaProviderAPIKeyState()

        let verificationPlan = state.applyingVerification(true, for: .localWhisper)
        let storagePlan = state.applyingStoredAPIKey("ignored", for: .localWhisper)

        XCTAssertEqual(applyProviderAPIKeyStateUpdatePlan(verificationPlan, provider: .localWhisper).events, [])
        XCTAssertEqual(applyProviderAPIKeyStateUpdatePlan(storagePlan, provider: .localWhisper).events, [])
    }

    func testRuntimeAPIKeyIfAvailableFollowsProviderAccessPolicyAndBlankRules() {
        XCTAssertEqual(RomaProviderKind.groq.runtimeAPIKeyIfAvailable(userAPIKey: "groq-key"), "groq-key")
        XCTAssertNil(RomaProviderKind.groq.runtimeAPIKeyIfAvailable(userAPIKey: " \n "))
        XCTAssertEqual(RomaProviderKind.localWhisper.runtimeAPIKeyIfAvailable(userAPIKey: ""), "local")
        XCTAssertEqual(RomaProviderKind.customCloud.runtimeAPIKeyIfAvailable(userAPIKey: ""), "custom-cloud")
    }

    func testTranscriptionServiceKindGroupsProvidersByRequiredAdapter() {
        XCTAssertEqual(RomaProviderKind.groq.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.openAI.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.deepgram.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.cerebras.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.gemini.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.mistral.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.elevenLabs.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.soniox.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.speechmatics.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.assemblyAI.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.xai.transcriptionServiceKind, .remote)
        XCTAssertEqual(RomaProviderKind.cartesia.transcriptionServiceKind, .streamingOnly)
        XCTAssertEqual(RomaProviderKind.customCloud.transcriptionServiceKind, .customCloud)
        XCTAssertEqual(RomaProviderKind.localWhisper.transcriptionServiceKind, .localWhisper)
    }

    func testTranscriptionEmptyTextPolicyPreservesMacOSAndLocalPolicy() {
        XCTAssertEqual(RomaProviderKind.groq.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertEqual(RomaProviderKind.deepgram.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertEqual(RomaProviderKind.gemini.transcriptionEmptyTextPolicy, .rejectEmpty)
        XCTAssertTrue(RomaProviderKind.groq.transcriptionEmptyTextPolicy.accepts(" \n\t "))
        XCTAssertFalse(RomaProviderKind.groq.transcriptionEmptyTextPolicy.accepts(""))

        XCTAssertEqual(RomaProviderKind.soniox.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertEqual(RomaProviderKind.speechmatics.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertEqual(RomaProviderKind.assemblyAI.transcriptionEmptyTextPolicy, .rejectWhitespace)
        XCTAssertFalse(RomaProviderKind.soniox.transcriptionEmptyTextPolicy.accepts(" \n\t "))

        XCTAssertEqual(RomaProviderKind.mistral.transcriptionEmptyTextPolicy, .allow)
        XCTAssertTrue(RomaProviderKind.mistral.transcriptionEmptyTextPolicy.accepts(""))
        XCTAssertEqual(RomaProviderKind.localWhisper.transcriptionEmptyTextPolicy, .allow)
        XCTAssertTrue(RomaProviderKind.localWhisper.transcriptionEmptyTextPolicy.accepts(""))
    }

    func testRemoteTranscriptionProvidersUseSharedTransportAndEndpoints() {
        XCTAssertEqual(RomaProviderKind.gemini.transcriptionTransport, .geminiGenerateContent)
        XCTAssertEqual(
            RomaProviderKind.gemini.transcriptionAPIBaseURL.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta"
        )
        XCTAssertEqual(RomaProviderKind.mistral.transcriptionTransport, .mistral)
        XCTAssertEqual(RomaProviderKind.mistral.transcriptionAPIBaseURL.absoluteString, "https://api.mistral.ai")
        XCTAssertEqual(RomaProviderKind.elevenLabs.transcriptionTransport, .elevenLabs)
        XCTAssertEqual(RomaProviderKind.elevenLabs.transcriptionAPIBaseURL.absoluteString, "https://api.elevenlabs.io")
        XCTAssertEqual(RomaProviderKind.soniox.transcriptionTransport, .soniox)
        XCTAssertEqual(RomaProviderKind.soniox.transcriptionAPIBaseURL.absoluteString, "https://api.soniox.com/v1")
        XCTAssertEqual(RomaProviderKind.speechmatics.transcriptionTransport, .speechmatics)
        XCTAssertEqual(RomaProviderKind.speechmatics.transcriptionAPIBaseURL.absoluteString, "https://asr.api.speechmatics.com/v2")
        XCTAssertEqual(RomaProviderKind.assemblyAI.transcriptionTransport, .assemblyAI)
        XCTAssertEqual(RomaProviderKind.assemblyAI.transcriptionAPIBaseURL.absoluteString, "https://api.assemblyai.com")
        XCTAssertEqual(RomaProviderKind.xai.transcriptionTransport, .xai)
        XCTAssertEqual(RomaProviderKind.xai.transcriptionAPIBaseURL.absoluteString, "https://api.x.ai")
        XCTAssertEqual(RomaProviderKind.cartesia.transcriptionAPIBaseURL.absoluteString, "https://api.cartesia.ai")
    }

    func testConsoleURLsMatchMacOSProviderSettings() {
        XCTAssertEqual(RomaProviderEndpoint.groq.consoleURL.absoluteString, "https://console.groq.com/keys")
        XCTAssertEqual(RomaProviderEndpoint.openAI.consoleURL.absoluteString, "https://platform.openai.com/api-keys")
        XCTAssertEqual(RomaProviderEndpoint.gemini.consoleURL.absoluteString, "https://makersuite.google.com/app/apikey")
        XCTAssertEqual(RomaProviderEndpoint.deepgram.consoleURL.absoluteString, "https://console.deepgram.com/api-keys")
        XCTAssertEqual(RomaProviderEndpoint.cerebras.consoleURL.absoluteString, "https://cloud.cerebras.ai/")
        XCTAssertEqual(RomaProviderKind.mistral.consoleURL.absoluteString, "https://console.mistral.ai/api-keys")
        XCTAssertEqual(RomaProviderKind.elevenLabs.consoleURL.absoluteString, "https://elevenlabs.io/speech-synthesis")
        XCTAssertEqual(RomaProviderKind.soniox.consoleURL.absoluteString, "https://console.soniox.com/")
        XCTAssertEqual(RomaProviderKind.speechmatics.consoleURL.absoluteString, "https://portal.speechmatics.com/manage-access/")
        XCTAssertEqual(RomaProviderKind.assemblyAI.consoleURL.absoluteString, "https://www.assemblyai.com/dashboard/api-keys")
        XCTAssertEqual(RomaProviderKind.xai.consoleURL.absoluteString, "https://console.x.ai/")
        XCTAssertEqual(RomaProviderKind.cartesia.consoleURL.absoluteString, "https://play.cartesia.ai/keys")
    }

    func testGeminiUsesNativeTranscriptionEndpointButOpenAICompatiblePostProcessingEndpoint() {
        XCTAssertEqual(
            RomaProviderKind.gemini.postProcessingChatCompletionsURL?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/openai/v1/chat/completions"
        )
    }

    func testPostProcessingChatCompletionsURLsOnlyExistForPostProcessingProviders() {
        XCTAssertEqual(
            RomaProviderKind.groq.postProcessingChatCompletionsURL?.absoluteString,
            "https://api.groq.com/openai/v1/chat/completions"
        )
        XCTAssertEqual(
            RomaProviderKind.openAI.postProcessingChatCompletionsURL?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            RomaProviderKind.cerebras.postProcessingChatCompletionsURL?.absoluteString,
            "https://api.cerebras.ai/v1/chat/completions"
        )
        XCTAssertEqual(
            RomaProviderKind.gemini.postProcessingChatCompletionsURL?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/openai/v1/chat/completions"
        )
        XCTAssertEqual(
            RomaProviderKind.mistral.postProcessingChatCompletionsURL?.absoluteString,
            "https://api.mistral.ai/v1/chat/completions"
        )
        XCTAssertEqual(
            RomaProviderKind.anthropic.postProcessingChatCompletionsURL?.absoluteString,
            "https://api.anthropic.com/v1/messages"
        )
        XCTAssertEqual(
            RomaProviderKind.openRouter.postProcessingChatCompletionsURL?.absoluteString,
            "https://openrouter.ai/api/v1/chat/completions"
        )
        XCTAssertNil(RomaProviderKind.deepgram.postProcessingChatCompletionsURL)
        XCTAssertNil(RomaProviderKind.elevenLabs.postProcessingChatCompletionsURL)
        XCTAssertNil(RomaProviderKind.soniox.postProcessingChatCompletionsURL)
        XCTAssertNil(RomaProviderKind.speechmatics.postProcessingChatCompletionsURL)
        XCTAssertNil(RomaProviderKind.assemblyAI.postProcessingChatCompletionsURL)
        XCTAssertNil(RomaProviderKind.xai.postProcessingChatCompletionsURL)
        XCTAssertNil(RomaProviderKind.cartesia.postProcessingChatCompletionsURL)
        XCTAssertNil(RomaProviderKind.localWhisper.postProcessingChatCompletionsURL)
    }

    func testProviderReadinessFollowsProviderAccessPolicy() {
        XCTAssertTrue(RomaProviderKind.groq.isReady(
            userAPIKey: "groq-key",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: false
        ))
        XCTAssertFalse(RomaProviderKind.groq.isReady(
            userAPIKey: "",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(RomaProviderKind.groq.isReady(
            userAPIKey: " \n ",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(RomaProviderKind.groq.isReady(
            userAPIKey: "groq-key",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: true
        ))

        XCTAssertTrue(RomaProviderKind.localWhisper.isReady(
            userAPIKey: "",
            userAPIKeyVerified: false,
            localWhisperModelAvailable: true
        ))
        XCTAssertFalse(RomaProviderKind.localWhisper.isReady(
            userAPIKey: "",
            userAPIKeyVerified: true,
            localWhisperModelAvailable: false
        ))

    }

    func testAvailableProvidersFiltersByModelUseAndReadiness() {
        let readyProviders: Set<RomaProviderKind> = [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .anthropic, .openRouter, .localWhisper]

        XCTAssertEqual(
            RomaProviderKind.availableProviders(for: .transcription) { readyProviders.contains($0) },
            [.groq, .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .localWhisper]
        )

        XCTAssertEqual(
            RomaProviderKind.availableProviders(for: .postProcessing) { readyProviders.contains($0) },
            [.groq, .mistral, .anthropic, .openRouter]
        )
    }

    func testProviderSelectabilityKeepsReadinessAndModelSupportSeparate() {
        XCTAssertTrue(RomaProviderKind.groq.isSelectable(for: .transcription))
        XCTAssertTrue(RomaProviderKind.groq.isSelectable(for: .postProcessing))
        XCTAssertTrue(RomaProviderKind.localWhisper.isSelectable(for: .transcription))
        XCTAssertFalse(RomaProviderKind.localWhisper.isSelectable(for: .postProcessing))
        XCTAssertTrue(RomaProviderKind.customCloud.isSelectable(for: .transcription))
        XCTAssertFalse(RomaProviderKind.customCloud.isSelectable(for: .postProcessing))
    }

    func testModelSelectionPresentationUsesTranscriptionModelList() {
        let presentation = RomaProviderKind.deepgram.modelSelectionPresentation(for: .transcription)

        XCTAssertNil(presentation.fixedModelName)
        XCTAssertEqual(presentation.selectableModels, RomaProviderKind.deepgram.models(for: .transcription))
    }

    func testModelSelectionPresentationUsesPostProcessingModelList() {
        let presentation = RomaProviderKind.groq.modelSelectionPresentation(for: .postProcessing)

        XCTAssertNil(presentation.fixedModelName)
        XCTAssertEqual(presentation.selectableModels, RomaAIModelCatalog.availableModels(for: .groq))
    }

    func testSelectedModelPreservesAvailableCurrentModel() {
        XCTAssertEqual(
            RomaProviderKind.deepgram.selectedModel("nova-3-medical", for: .transcription),
            "nova-3-medical"
        )
    }

    func testSelectedModelFallsBackToProviderDefaultWhenCurrentModelIsUnavailable() {
        XCTAssertEqual(
            RomaProviderKind.gemini.selectedModel("old-gemini-model", for: .postProcessing),
            RomaAIModelCatalog.defaultModel(for: .gemini)
        )
    }

    func testPostProcessingDefaultModelUsesCatalogDefaultForCoreAIProviders() {
        XCTAssertEqual(
            RomaProviderKind.groq.postProcessingDefaultModel,
            RomaAIModelCatalog.defaultModel(for: .groq)
        )
        XCTAssertEqual(
            RomaProviderKind.groq.defaultModel(for: .postProcessing),
            RomaAIModelCatalog.defaultModel(for: .groq)
        )
        XCTAssertEqual(
            RomaProviderKind.openAI.postProcessingDefaultModel,
            RomaAIModelCatalog.defaultModel(for: .openAI)
        )
        XCTAssertEqual(
            RomaProviderKind.cerebras.postProcessingDefaultModel,
            RomaAIModelCatalog.defaultModel(for: .cerebras)
        )
        XCTAssertEqual(
            RomaProviderKind.gemini.postProcessingDefaultModel,
            RomaAIModelCatalog.defaultModel(for: .gemini)
        )
    }

    func testPostProcessingModelListUsesCatalogModelsForCoreAIProviders() {
        XCTAssertEqual(
            RomaProviderKind.groq.postProcessingModels,
            RomaAIModelCatalog.availableModels(for: .groq)
        )
        XCTAssertEqual(
            RomaProviderKind.gemini.postProcessingModels,
            RomaAIModelCatalog.availableModels(for: .gemini)
        )
        XCTAssertEqual(
            RomaProviderKind.mistral.postProcessingModels,
            RomaAIModelCatalog.availableModels(for: .mistral)
        )
        XCTAssertEqual(
            RomaProviderKind.anthropic.postProcessingModels,
            RomaAIModelCatalog.availableModels(for: .anthropic)
        )
        XCTAssertEqual(
            RomaProviderKind.openRouter.postProcessingModels,
            [RomaAIModelCatalog.defaultModel(for: .openRouter)]
        )
    }

    func testPostProcessingModelsAreNilForNonPostProcessingProviders() {
        XCTAssertNil(RomaProviderKind.deepgram.postProcessingDefaultModel)
        XCTAssertNil(RomaProviderKind.deepgram.postProcessingModels)
        XCTAssertNil(RomaProviderKind.elevenLabs.postProcessingDefaultModel)
        XCTAssertNil(RomaProviderKind.elevenLabs.postProcessingModels)
        XCTAssertNil(RomaProviderKind.soniox.postProcessingDefaultModel)
        XCTAssertNil(RomaProviderKind.soniox.postProcessingModels)
        XCTAssertNil(RomaProviderKind.speechmatics.postProcessingDefaultModel)
        XCTAssertNil(RomaProviderKind.speechmatics.postProcessingModels)
        XCTAssertNil(RomaProviderKind.assemblyAI.postProcessingDefaultModel)
        XCTAssertNil(RomaProviderKind.assemblyAI.postProcessingModels)
        XCTAssertNil(RomaProviderKind.xai.postProcessingDefaultModel)
        XCTAssertNil(RomaProviderKind.xai.postProcessingModels)
        XCTAssertNil(RomaProviderKind.localWhisper.postProcessingDefaultModel)
        XCTAssertNil(RomaProviderKind.localWhisper.postProcessingModels)
    }

    func testSelectedModelReturnsEmptyStringWhenUseHasNoModels() {
        XCTAssertEqual(
            RomaProviderKind.cerebras.selectedModel("anything", for: .transcription),
            ""
        )
    }

    func testAvailableProvidersReturnsEmptyWhenNoProviderIsReady() {
        XCTAssertEqual(
            RomaProviderKind.availableProviders(for: .transcription) { _ in false },
            []
        )
        XCTAssertEqual(
            RomaProviderKind.availableProviders(for: .postProcessing) { _ in false },
            []
        )
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        value as? Bool
    }
}
