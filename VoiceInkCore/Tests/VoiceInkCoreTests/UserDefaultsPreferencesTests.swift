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
        XCTAssertEqual(VoiceInkUserDefaultsKey.isVADEnabled, "IsVADEnabled")
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

    func testSharedPreferenceDefaultsPreserveExistingVADPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.isVADEnabled, true)
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

    func testOnboardingPreferenceUsesFalseWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))
        }
    }

    func testOnboardingPreferenceSavesAndClearsCompletionState() {
        withIsolatedDefaults { defaults in
            VoiceInkOnboardingPreference.saveHasCompletedOnboarding(true, to: defaults)
            XCTAssertTrue(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))

            VoiceInkOnboardingPreference.clear(from: defaults)
            XCTAssertFalse(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))
        }
    }

    func testAudioSessionTimeoutPreferenceUsesExistingDefaultWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
            )
        }
    }

    func testAudioSessionTimeoutPreferenceSavesAndClearsTimeout() {
        withIsolatedDefaults { defaults in
            VoiceInkAudioSessionTimeoutPreference.saveTimeoutSeconds(120, to: defaults)
            XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults), 120)

            VoiceInkAudioSessionTimeoutPreference.clear(from: defaults)
            XCTAssertEqual(
                VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
            )
        }
    }

    func testVADPreferenceUsesSharedDefaultWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkVADPreference.isEnabled(from: defaults),
                VoiceInkPreferenceDefault.isVADEnabled
            )
        }
    }

    func testVADPreferenceSavesAndClearsEnabledState() {
        withIsolatedDefaults { defaults in
            VoiceInkVADPreference.saveIsEnabled(false, to: defaults)
            XCTAssertFalse(VoiceInkVADPreference.isEnabled(from: defaults))

            VoiceInkVADPreference.clear(from: defaults)
            XCTAssertEqual(
                VoiceInkVADPreference.isEnabled(from: defaults),
                VoiceInkPreferenceDefault.isVADEnabled
            )
        }
    }

    func testTranscriptionPromptPreferenceUsesFallbackOnlyWhenLocalWhisperPromptIsMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                "Language prompt"
            )

            VoiceInkTranscriptionPromptPreference.savePrompt("", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                ""
            )

            VoiceInkTranscriptionPromptPreference.savePrompt(" spell Roma correctly ", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                " spell Roma correctly "
            )
        }
    }

    func testTranscriptionPromptPreferenceUsesSelectedLanguagePromptFallback() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("ja", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(from: defaults),
                VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "ja")
            )

            VoiceInkTranscriptionPromptPreference.savePrompt(" custom prompt ", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(from: defaults),
                " custom prompt "
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

            VoiceInkTranscriptionPromptPreference.savePrompt(" keep product names ", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.requestPrompt(from: defaults),
                " keep product names "
            )

            VoiceInkTranscriptionPromptPreference.savePrompt(" \n ", to: defaults)
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(from: defaults))
        }
    }

    func testTranscriptionPromptPreferenceRoundTripsStoredPrompt() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults))

            VoiceInkTranscriptionPromptPreference.savePrompt("keep Roma spelling", to: defaults)

            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults),
                "keep Roma spelling"
            )
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

    func testAIEnhancementProviderPreferenceUsesDefaultWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults))
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProvider(default: .gemini, from: defaults),
                .gemini
            )
        }
    }

    func testAIEnhancementProviderPreferenceRepairsLegacyStoredProvider() {
        withIsolatedDefaults { defaults in
            defaults.set("GROQ", forKey: VoiceInkUserDefaultsKey.selectedAIProvider)

            XCTAssertEqual(VoiceInkAIEnhancementProviderPreference.selectedProvider(from: defaults), .groq)
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                VoiceInkAIEnhancementProviderKind.groq.rawValue
            )
        }
    }

    func testAIEnhancementProviderPreferenceRoundTripsRawProvider() {
        withIsolatedDefaults { defaults in
            VoiceInkAIEnhancementProviderPreference.saveSelectedProviderRawValue("OpenRouter", to: defaults)

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                "OpenRouter"
            )
            XCTAssertEqual(VoiceInkAIEnhancementProviderPreference.selectedProvider(from: defaults), .openRouter)
        }
    }

    func testAIEnhancementProviderPreferenceRoundTripsSelectedModel() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "Groq", from: defaults)
            )

            VoiceInkAIEnhancementProviderPreference.saveSelectedModel(
                "llama-3.3-70b-versatile",
                for: "Groq",
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "Groq", from: defaults),
                "llama-3.3-70b-versatile"
            )
        }
    }

    func testDynamicAIProviderPreferenceReadsOllamaFallbacksAndSavedValues() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                VoiceInkPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )

            VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL("http://example.local:11434", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel("mistral", to: defaults)

            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                "http://example.local:11434"
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "mistral"
            )
        }
    }

    func testDynamicAIProviderPreferencePreservesCallerSpecificOllamaModelFallbacks() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "mistral"),
                "mistral"
            )
        }
    }

    func testDynamicAIProviderPreferenceRoundTripsCustomProviderSettings() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderBaseURL(from: defaults), "")
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderModel(from: defaults), "")

            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL("https://api.example.com/v1", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderModel("custom-model", to: defaults)

            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.customProviderBaseURL(from: defaults),
                "https://api.example.com/v1"
            )
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderModel(from: defaults), "custom-model")
        }
    }

    func testDynamicAIProviderPreferenceRoundTripsOpenRouterModels() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.openRouterModels(from: defaults), [])

            VoiceInkDynamicAIProviderPreference.saveOpenRouterModels(["openai/gpt-oss-120b", "z-ai/glm-4.5"], to: defaults)

            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.openRouterModels(from: defaults),
                ["openai/gpt-oss-120b", "z-ai/glm-4.5"]
            )
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

    func testFillerWordPreferenceClearsSavedWords() {
        withIsolatedDefaults { defaults in
            VoiceInkFillerWordPreference.saveWords(["um", "like"], to: defaults)
            VoiceInkFillerWordPreference.clearWords(from: defaults)

            XCTAssertEqual(
                VoiceInkFillerWordPreference.words(from: defaults),
                VoiceInkFillerWords.defaultWords
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

    func testTranscriptionAutoCleanupPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            let configuration = VoiceInkTranscriptionAutoCleanupPreference.current(from: defaults)

            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionMinutes, VoiceInkPreferenceDefault.transcriptionRetentionMinutes)
            XCTAssertEqual(configuration.effectiveRetentionMinutes, VoiceInkPreferenceDefault.transcriptionRetentionMinutes)
            XCTAssertFalse(configuration.shouldDeleteCompletedTranscriptionImmediately)
        }
    }

    func testTranscriptionAutoCleanupPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(15, to: defaults)

            let configuration = VoiceInkTranscriptionAutoCleanupPreference.current(from: defaults)

            XCTAssertTrue(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionMinutes, 15)
            XCTAssertEqual(configuration.effectiveRetentionMinutes, 15)
        }
    }

    func testTranscriptionAutoCleanupConfigurationClampsNegativeRetentionForCutoff() {
        let configuration = VoiceInkTranscriptionAutoCleanupConfiguration(
            isEnabled: true,
            retentionMinutes: -5
        )
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(configuration.effectiveRetentionMinutes, 0)
        XCTAssertTrue(configuration.shouldDeleteCompletedTranscriptionImmediately)
        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), referenceDate)
    }

    func testTranscriptionAutoCleanupConfigurationBuildsCutoffDate() {
        let configuration = VoiceInkTranscriptionAutoCleanupConfiguration(
            isEnabled: true,
            retentionMinutes: 30
        )
        let referenceDate = Date(timeIntervalSince1970: 3_600)

        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), Date(timeIntervalSince1970: 1_800))
    }

    func testSharedPreferenceResetClearsCoreUserSettings() {
        withIsolatedDefaults { defaults in
            let mode = Mode.defaultLocalWhisper()
            VoiceInkModeStorage.saveModes([mode], to: defaults)
            VoiceInkModeStorage.saveSelectedModeId(mode.id, to: defaults)
            VoiceInkOnboardingPreference.saveHasCompletedOnboarding(to: defaults)
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            VoiceInkAudioSessionTimeoutPreference.saveTimeoutSeconds(120, to: defaults)
            VoiceInkVADPreference.saveIsEnabled(false, to: defaults)
            PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)
            VoiceInkFillerWordPreference.saveWords(["um", "like"], to: defaults)
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            VoiceInkTranscriptionPromptPreference.savePrompt("custom prompt", to: defaults)
            VoiceInkCurrentTranscriptionModelPreference.saveModelName("nova-3", to: defaults)
            VoiceInkAIEnhancementProviderPreference.saveSelectedProviderRawValue("OpenRouter", to: defaults)
            VoiceInkAIEnhancementProviderPreference.saveSelectedModel("openai/gpt-oss-120b", for: "OpenRouter", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL("http://example.local:11434", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel("mistral", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL("https://api.example.com/v1", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderModel("custom-model", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveOpenRouterModels(["openai/gpt-oss-120b"], to: defaults)
            defaults.set(15, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
            defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(15, to: defaults)
            let customPrompt = VoiceInkCustomPrompt(title: "Custom", promptText: "Clean this")
            VoiceInkCustomPromptStorage.savePrompts([customPrompt], to: defaults)
            VoiceInkCustomPromptStorage.saveSelectedPromptId(customPrompt.id, to: defaults)

            VoiceInkSharedPreferenceReset.clearCoreUserSettings(from: defaults, providers: [.groq])

            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkModeStorage.loadSelectedModeId(from: defaults))
            XCTAssertFalse(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))
            XCTAssertFalse(VoiceInkProviderAPIKeyVerificationState.isVerified(.groq, in: defaults))
            XCTAssertEqual(
                VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
            )
            XCTAssertEqual(
                VoiceInkVADPreference.isEnabled(from: defaults),
                VoiceInkPreferenceDefault.isVADEnabled
            )
            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .keep)
            XCTAssertEqual(
                VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults),
                VoiceInkPreferenceDefault.isTextFormattingEnabled
            )
            XCTAssertEqual(
                VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults),
                VoiceInkPreferenceDefault.lowercaseTranscription
            )
            XCTAssertEqual(
                VoiceInkTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults),
                VoiceInkPreferenceDefault.removeFillerWords
            )
            XCTAssertEqual(VoiceInkFillerWordPreference.words(from: defaults), VoiceInkFillerWords.defaultWords)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                VoiceInkLanguageCatalog.autoDetectCode
            )
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults))
            XCTAssertNil(VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults))
            XCTAssertNil(VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults))
            XCTAssertNil(VoiceInkAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults))
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                VoiceInkPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderBaseURL(from: defaults), "")
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderModel(from: defaults), "")
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.openRouterModels(from: defaults), [])
            XCTAssertEqual(
                VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
            )
            XCTAssertTrue(VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults))
            XCTAssertEqual(
                VoiceInkTranscriptionAutoCleanupPreference.current(from: defaults),
                VoiceInkTranscriptionAutoCleanupConfiguration(
                    isEnabled: false,
                    retentionMinutes: VoiceInkPreferenceDefault.transcriptionRetentionMinutes
                )
            )
            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkCustomPromptStorage.loadSelectedPromptId(from: defaults))
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

    func testModeStorageRepairsStaleModelSelectionsOnLoad() {
        withIsolatedDefaults { defaults in
            let staleMode = Mode(
                name: "Cloud",
                transcriptionProvider: .deepgram,
                transcriptionModel: "stale-transcription-model",
                isPostProcessingEnabled: true,
                postProcessingProvider: .gemini,
                postProcessingModel: "stale-post-processing-model"
            )

            VoiceInkModeStorage.saveModes([staleMode], to: defaults)

            let loadedMode = VoiceInkModeStorage.loadModes(from: defaults).first

            XCTAssertEqual(loadedMode?.id, staleMode.id)
            XCTAssertEqual(loadedMode?.transcriptionModel, VoiceInkProviderKind.deepgram.defaultModel(for: .transcription))
            XCTAssertEqual(loadedMode?.postProcessingModel, VoiceInkProviderKind.gemini.defaultModel(for: .postProcessing))
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
