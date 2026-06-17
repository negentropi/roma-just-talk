import Foundation
@testable import VoiceInkCore

final class UserDefaultsPreferencesTests: XCTestCase {
    func testSharedPreferenceKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkUserDefaultsKey.hasCompletedOnboarding, "hasCompletedOnboarding")
        XCTAssertEqual(VoiceInkUserDefaultsKey.lowercaseTranscription, "LowercaseTranscription")
        XCTAssertEqual(VoiceInkUserDefaultsKey.removeFillerWords, "RemoveFillerWords")
        XCTAssertEqual(VoiceInkUserDefaultsKey.fillerWords, "FillerWords")
        XCTAssertEqual(VoiceInkUserDefaultsKey.modes, "modes")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedModeId, "selectedModeId")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage, "SelectedLanguage")
        XCTAssertEqual(VoiceInkUserDefaultsKey.currentTranscriptionModel, "CurrentTranscriptionModel")
        XCTAssertEqual(VoiceInkUserDefaultsKey.transcriptionPrompt, "TranscriptionPrompt")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isTextFormattingEnabled, "IsTextFormattingEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled, "IsTranscriptionCleanupEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.transcriptionRetentionMinutes, "TranscriptionRetentionMinutes")
        XCTAssertEqual(VoiceInkUserDefaultsKey.skipShortEnhancement, "SkipShortEnhancement")
        XCTAssertEqual(VoiceInkUserDefaultsKey.shortEnhancementWordThreshold, "ShortEnhancementWordThreshold")
        XCTAssertEqual(VoiceInkUserDefaultsKey.enhancementTimeoutSeconds, "EnhancementTimeoutSeconds")
        XCTAssertEqual(VoiceInkUserDefaultsKey.enhancementRetryOnTimeout, "EnhancementRetryOnTimeout")
        XCTAssertEqual(VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds, "audioSessionTimeoutSeconds")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isAIEnhancementEnabled, "isAIEnhancementEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.useClipboardContext, "useClipboardContext")
        XCTAssertEqual(VoiceInkUserDefaultsKey.useScreenCaptureContext, "useScreenCaptureContext")
        XCTAssertEqual(VoiceInkUserDefaultsKey.customPrompts, "customPrompts")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedPromptId, "selectedPromptId")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedAIProvider, "selectedAIProvider")
        XCTAssertEqual(VoiceInkUserDefaultsKey.openRouterModels, "openRouterModels")
        XCTAssertEqual(VoiceInkUserDefaultsKey.ollamaBaseURL, "ollamaBaseURL")
        XCTAssertEqual(VoiceInkUserDefaultsKey.ollamaSelectedModel, "ollamaSelectedModel")
        XCTAssertEqual(VoiceInkUserDefaultsKey.customProviderBaseURL, "customProviderBaseURL")
        XCTAssertEqual(VoiceInkUserDefaultsKey.customProviderModel, "customProviderModel")
    }

    func testAIProviderModelSelectionKeyPreservesExistingProviderRawValuePattern() {
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedAIProviderModel("Groq"), "GroqSelectedModel")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedAIProviderModel("Local CLI"), "Local CLISelectedModel")
    }

    func testSharedPreferenceDefaultsPreserveExistingIOSAudioSessionTimeout() {
        XCTAssertEqual(VoiceInkPreferenceDefault.audioSessionTimeoutSeconds, 90)
    }

    func testSharedPreferenceDefaultsPreserveExistingTextFormattingPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.isTextFormattingEnabled, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingTranscriptionCleanupPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.lowercaseTranscription, false)
        XCTAssertEqual(VoiceInkPreferenceDefault.removeFillerWords, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingCleanupRetention() {
        XCTAssertEqual(VoiceInkPreferenceDefault.transcriptionRetentionMinutes, 24 * 60)
    }

    func testSharedPreferenceDefaultsPreserveExistingShortEnhancementPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.skipShortEnhancement, true)
        XCTAssertEqual(VoiceInkPreferenceDefault.shortEnhancementWordThreshold, 3)
    }

    func testSharedPreferenceDefaultsPreserveExistingEnhancementTimeoutPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.enhancementTimeoutSeconds, 7)
        XCTAssertEqual(VoiceInkPreferenceDefault.enhancementRetryOnTimeout, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingOllamaBaseURL() {
        XCTAssertEqual(VoiceInkPreferenceDefault.ollamaBaseURL, "http://localhost:11434")
    }

    func testTranscriptionPromptPreferenceUsesFallbackOnlyWhenLocalWhisperPromptIsMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                "Language prompt"
            )

            defaults.set("", forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                ""
            )

            defaults.set(" spell Roma correctly ", forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                " spell Roma correctly "
            )
        }
    }

    func testTranscriptionPromptPreferenceDropsBlankRequestPrompts() {
        XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(nil))
        XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(""))
        XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(" \n\t "))
    }

    func testTranscriptionPromptPreferenceReadsRequestPromptFromSharedKey() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(from: defaults))

            defaults.set(" keep product names ", forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.requestPrompt(from: defaults),
                " keep product names "
            )

            defaults.set(" \n ", forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(from: defaults))
        }
    }

    func testTranscriptionLanguagePreferenceUsesAutoDetectFallbackWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                VoiceInkLanguageCatalog.autoDetectCode
            )
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(from: defaults))
        }
    }

    func testTranscriptionLanguagePreferencePreservesRawSelectedLanguage() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                "auto"
            )
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(from: defaults))

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(" fr ", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                " fr "
            )
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(from: defaults), "fr")
        }
    }

    func testTranscriptionLanguagePreferenceExposesStoredLanguageWhenPresent() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults))

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("de", to: defaults)

            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults), "de")
        }
    }

    func testTranscriptionLanguagePreferenceSavesCompatibleLanguage() {
        withIsolatedDefaults { defaults in
            let savedLanguage = VoiceInkTranscriptionLanguagePreference.saveCompatibleLanguage(
                "fr",
                languages: VoiceInkLanguageCatalog.englishOnly,
                to: defaults
            )

            XCTAssertEqual(savedLanguage, "en")
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults), "en")
        }
    }

    func testTranscriptionLanguagePreferenceClearsSelection() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            VoiceInkTranscriptionLanguagePreference.clearSelectedLanguage(from: defaults)

            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults))
        }
    }

    func testCurrentTranscriptionModelPreferenceRoundTripsModelName() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults))

            VoiceInkCurrentTranscriptionModelPreference.saveModelName("parakeet-tdt-0.6b-v2", to: defaults)

            XCTAssertEqual(
                VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults),
                "parakeet-tdt-0.6b-v2"
            )
        }
    }

    func testCurrentTranscriptionModelPreferenceClearsModelName() {
        withIsolatedDefaults { defaults in
            VoiceInkCurrentTranscriptionModelPreference.saveModelName("nova-3", to: defaults)
            VoiceInkCurrentTranscriptionModelPreference.clearModelName(from: defaults)

            XCTAssertNil(VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults))
        }
    }

    func testFillerWordPreferenceUsesDefaultWordsWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkFillerWordPreference.words(from: defaults),
                VoiceInkFillerWords.defaultWords
            )
        }
    }

    func testFillerWordPreferenceRoundTripsSavedWords() {
        withIsolatedDefaults { defaults in
            VoiceInkFillerWordPreference.saveWords(["um", "like"], to: defaults)

            XCTAssertEqual(
                VoiceInkFillerWordPreference.words(from: defaults),
                ["um", "like"]
            )
        }
    }

    func testAIEnhancementRequestPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults),
                VoiceInkPreferenceDefault.enhancementRetryOnTimeout
            )
        }
    }

    func testAIEnhancementRequestPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            defaults.set(15, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
            defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)

            XCTAssertEqual(VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults), 15)
            XCTAssertFalse(VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults))
        }
    }

    func testAIEnhancementRequestPreferenceFallsBackForNonPositiveTimeout() {
        withIsolatedDefaults { defaults in
            defaults.set(0, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)

            XCTAssertEqual(
                VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
            )
        }
    }

    func testModeStorageRoundTripsModesAndSelectedModeId() {
        withIsolatedDefaults { defaults in
            let localMode = Mode.defaultLocalWhisper(name: "Local")
            let cloudMode = Mode(
                name: "Cloud",
                transcriptionProvider: .deepgram,
                transcriptionModel: "nova-3-medical"
            )

            VoiceInkModeStorage.saveModes([localMode, cloudMode], to: defaults)
            VoiceInkModeStorage.saveSelectedModeId(cloudMode.id, to: defaults)

            let loadedModes = VoiceInkModeStorage.loadModes(from: defaults)
            XCTAssertEqual(loadedModes.map(\.name), ["Local", "Cloud"])
            XCTAssertEqual(loadedModes.map(\.id), [localMode.id, cloudMode.id])
            XCTAssertEqual(VoiceInkModeStorage.loadSelectedModeId(from: defaults), cloudMode.id)
        }
    }

    func testModeStorageFallsBackToEmptyModesForMissingOrInvalidData() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)

            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.modes)
            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)
        }
    }

    func testModeStorageClearRemovesModesAndSelectedModeId() {
        withIsolatedDefaults { defaults in
            let mode = Mode.defaultLocalWhisper()
            VoiceInkModeStorage.saveModes([mode], to: defaults)
            VoiceInkModeStorage.saveSelectedModeId(mode.id, to: defaults)

            VoiceInkModeStorage.clear(from: defaults)

            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkModeStorage.loadSelectedModeId(from: defaults))
        }
    }

    func testCustomPromptStorageRoundTripsPromptsAndSelectedPromptId() {
        withIsolatedDefaults { defaults in
            let customPrompt = VoiceInkCustomPrompt(
                title: "Custom",
                promptText: "Keep terms exact.",
                triggerWords: ["terms"]
            )
            let assistantPrompt = VoiceInkCustomPrompt(predefinedPrompt: VoiceInkPredefinedPrompts.all[1])

            VoiceInkCustomPromptStorage.savePrompts([customPrompt, assistantPrompt], to: defaults)
            VoiceInkCustomPromptStorage.saveSelectedPromptId(assistantPrompt.id, to: defaults)

            let loadedPrompts = VoiceInkCustomPromptStorage.loadPrompts(from: defaults)
            XCTAssertEqual(loadedPrompts.map(\.id), [customPrompt.id, assistantPrompt.id])
            XCTAssertEqual(loadedPrompts.map(\.title), ["Custom", "Assistant"])
            XCTAssertEqual(VoiceInkCustomPromptStorage.loadSelectedPromptId(from: defaults), assistantPrompt.id)
        }
    }

    func testCustomPromptStorageFallsBackToEmptyPromptsForMissingOrInvalidData() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)

            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.customPrompts)
            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
        }
    }

    func testCustomPromptStorageClearRemovesPromptsAndSelectedPromptId() {
        withIsolatedDefaults { defaults in
            let prompt = VoiceInkCustomPrompt(title: "Prompt", promptText: "Text")
            VoiceInkCustomPromptStorage.savePrompts([prompt], to: defaults)
            VoiceInkCustomPromptStorage.saveSelectedPromptId(prompt.id, to: defaults)

            VoiceInkCustomPromptStorage.clear(from: defaults)

            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkCustomPromptStorage.loadSelectedPromptId(from: defaults))
        }
    }

    func testProviderAPIKeyVerificationStateUsesProviderKeys() {
        withIsolatedDefaults { defaults in
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)

            XCTAssertTrue(VoiceInkProviderAPIKeyVerificationState.isVerified(.groq, in: defaults))
            XCTAssertEqual(defaults.object(forKey: "groqKeyVerified") as? Bool, true)
        }
    }

    func testProviderAPIKeyVerificationStatePersistsFalseFlag() {
        withIsolatedDefaults { defaults in
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .deepgram, in: defaults)
            VoiceInkProviderAPIKeyVerificationState.setVerified(false, for: .deepgram, in: defaults)

            XCTAssertFalse(VoiceInkProviderAPIKeyVerificationState.isVerified(.deepgram, in: defaults))
            XCTAssertEqual(defaults.object(forKey: "deepgramKeyVerified") as? Bool, false)
        }
    }

    func testProviderAPIKeyVerificationStateFiltersVerifiedUserKeyProviders() {
        withIsolatedDefaults { defaults in
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .voiceInk, in: defaults)

            XCTAssertEqual(
                VoiceInkProviderAPIKeyVerificationState.verifiedProviders(from: [.groq, .deepgram, .voiceInk], in: defaults),
                [.groq]
            )
            XCTAssertFalse(VoiceInkProviderAPIKeyVerificationState.isVerified(.voiceInk, in: defaults))
        }
    }

    func testProviderAPIKeyVerificationStateClearsSingleAndAllProviders() {
        withIsolatedDefaults { defaults in
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .deepgram, in: defaults)
            VoiceInkProviderAPIKeyVerificationState.clear(for: .groq, in: defaults)

            XCTAssertNil(defaults.object(forKey: "groqKeyVerified"))
            XCTAssertTrue(VoiceInkProviderAPIKeyVerificationState.isVerified(.deepgram, in: defaults))

            VoiceInkProviderAPIKeyVerificationState.clearAll(from: [.groq, .deepgram], in: defaults)

            XCTAssertNil(defaults.object(forKey: "deepgramKeyVerified"))
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
