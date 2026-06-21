import Foundation
@testable import VoiceInkCore

final class UserDefaultsPreferencesTests: XCTestCase {
    func testSharedPreferenceKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkUserDefaultsKey.hasCompletedOnboarding, "hasCompletedOnboarding")
        XCTAssertEqual(VoiceInkUserDefaultsKey.lowercaseTranscription, "LowercaseTranscription")
        XCTAssertEqual(VoiceInkUserDefaultsKey.removeFillerWords, "RemoveFillerWords")
        XCTAssertEqual(VoiceInkUserDefaultsKey.fillerWords, "FillerWords")
        XCTAssertEqual(VoiceInkUserDefaultsKey.wordReplacements, "voiceInkIOSWordReplacements")
        XCTAssertEqual(VoiceInkUserDefaultsKey.customVocabularyTerms, "voiceInkIOSCustomVocabularyTerms")
        XCTAssertEqual(VoiceInkUserDefaultsKey.modes, "modes")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedModeId, "selectedModeId")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage, "SelectedLanguage")
        XCTAssertEqual(VoiceInkUserDefaultsKey.currentTranscriptionModel, "CurrentTranscriptionModel")
        XCTAssertEqual(VoiceInkUserDefaultsKey.transcriptionPrompt, "TranscriptionPrompt")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isTextFormattingEnabled, "IsTextFormattingEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isVADEnabled, "IsVADEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled, "IsTranscriptionCleanupEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.transcriptionRetentionMinutes, "TranscriptionRetentionMinutes")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isAudioCleanupEnabled, "IsAudioCleanupEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.audioRetentionPeriodDays, "AudioRetentionPeriod")
        XCTAssertEqual(VoiceInkUserDefaultsKey.appendTrailingSpace, "AppendTrailingSpace")
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
        XCTAssertEqual(VoiceInkUserDefaultsKey.powerModeUIFlag, "powerModeUIFlag")
        XCTAssertEqual(VoiceInkUserDefaultsKey.powerModePersistConfig, "powerModePersistConfig")
        XCTAssertEqual(VoiceInkUserDefaultsKey.powerModeConfigurations, "powerModeConfigurationsV2")
        XCTAssertEqual(VoiceInkUserDefaultsKey.activePowerModeConfigurationId, "activeConfigurationId")
        XCTAssertEqual(VoiceInkUserDefaultsKey.activePowerModeSession, "powerModeActiveSession.v1")
        XCTAssertEqual(VoiceInkUserDefaultsKey.prewarmModelOnWake, "PrewarmModelOnWake")
        XCTAssertEqual(VoiceInkUserDefaultsKey.showLiveTextPreview, "showLiveTextPreview")
        XCTAssertEqual(VoiceInkUserDefaultsKey.primaryRecordingShortcut, "primaryRecordingShortcut")
        XCTAssertEqual(VoiceInkUserDefaultsKey.secondaryRecordingShortcut, "secondaryRecordingShortcut")
        XCTAssertEqual(VoiceInkUserDefaultsKey.primaryRecordingShortcutMode, "primaryRecordingShortcutMode")
        XCTAssertEqual(VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode, "secondaryRecordingShortcutMode")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled, "isMiddleClickToggleEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.middleClickActivationDelay, "middleClickActivationDelay")
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
        XCTAssertEqual(VoiceInkPreferenceDefault.audioRetentionDays, 7)
    }

    func testSharedPreferenceDefaultsPreserveMacOSTrailingSpacePolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.appendTrailingSpace, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingShortEnhancementPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.skipShortEnhancement, true)
        XCTAssertEqual(VoiceInkPreferenceDefault.shortEnhancementWordThreshold, 3)
    }

    func testSharedPreferenceDefaultsPreserveExistingEnhancementTimeoutPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.enhancementTimeoutSeconds, 7)
        XCTAssertEqual(VoiceInkPreferenceDefault.enhancementRetryOnTimeout, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingPowerModeFlags() {
        XCTAssertFalse(VoiceInkPreferenceDefault.powerModeUIEnabled)
        XCTAssertFalse(VoiceInkPreferenceDefault.powerModePersistConfiguredPreferences)
    }

    func testSharedPreferenceDefaultsPreserveExistingMacOSRuntimeFlags() {
        XCTAssertTrue(VoiceInkPreferenceDefault.prewarmModelOnWake)
        XCTAssertFalse(VoiceInkPreferenceDefault.showLiveTextPreview)
    }

    func testSharedPreferenceDefaultsPreserveExistingRecordingShortcutFlags() {
        XCTAssertFalse(VoiceInkPreferenceDefault.isMiddleClickToggleEnabled)
        XCTAssertEqual(VoiceInkPreferenceDefault.middleClickActivationDelay, 200)
    }

    func testSharedPreferenceDefaultsPreserveExistingOllamaBaseURL() {
        XCTAssertEqual(VoiceInkPreferenceDefault.ollamaBaseURL, "http://localhost:11434")
    }

    func testDefaultSettingsPreserveIOSResetState() {
        let defaults = VoiceInkDefaultSettings.iOS

        XCTAssertEqual(defaults.audioSessionTimeoutSeconds, VoiceInkPreferenceDefault.audioSessionTimeoutSeconds)
        XCTAssertEqual(defaults.punctuationCleanupMode, .keep)
        XCTAssertEqual(defaults.isTextFormattingEnabled, VoiceInkPreferenceDefault.isTextFormattingEnabled)
        XCTAssertEqual(defaults.isVADEnabled, VoiceInkPreferenceDefault.isVADEnabled)
        XCTAssertEqual(defaults.lowercaseTranscription, VoiceInkPreferenceDefault.lowercaseTranscription)
        XCTAssertEqual(defaults.removeFillerWords, VoiceInkPreferenceDefault.removeFillerWords)
        XCTAssertEqual(defaults.fillerWords, VoiceInkFillerWords.defaultWords)
        XCTAssertEqual(defaults.selectedTranscriptionLanguage, VoiceInkLanguageCatalog.autoDetectCode)
    }

    func testDefaultSettingsBuildSharedAppSettingsResetState() {
        let defaults = VoiceInkDefaultSettings(
            audioSessionTimeoutSeconds: 12,
            punctuationCleanupMode: .removeTrailingPeriod,
            isTextFormattingEnabled: false,
            lowercaseTranscription: true,
            removeFillerWords: false,
            fillerWords: ["um"],
            selectedTranscriptionLanguage: "de"
        )

        let resetState = defaults.appSettingsResetState

        XCTAssertTrue(resetState.modes.isEmpty)
        XCTAssertNil(resetState.selectedModeId)
        XCTAssertEqual(resetState.apiKeyState, VoiceInkProviderAPIKeyState())
        XCTAssertEqual(resetState.audioSessionTimeoutSeconds, 12)
        XCTAssertEqual(
            resetState.transcriptionCleanupSettings,
            VoiceInkTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )
        )
        XCTAssertEqual(resetState.fillerWords, ["um"])
        XCTAssertEqual(resetState.wordReplacements, [])
        XCTAssertEqual(resetState.customVocabularyTerms, [])
        XCTAssertEqual(resetState.selectedTranscriptionLanguage, "de")
    }

    func testDefaultSettingsPreserveMacOSSelectedLanguageDefault() {
        let defaults = VoiceInkDefaultSettings.macOS
        let registeredDefaults = defaults.registeredUserDefaults()

        XCTAssertEqual(
            defaults.selectedTranscriptionLanguage,
            VoiceInkPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
        XCTAssertEqual(defaults.selectedTranscriptionLanguage, "en")
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            VoiceInkPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
    }

    func testDefaultSettingsExposeTranscriptionCleanupSettings() {
        let defaults = VoiceInkDefaultSettings(
            punctuationCleanupMode: .removeTrailingPeriod,
            isTextFormattingEnabled: false,
            lowercaseTranscription: true,
            removeFillerWords: false
        )

        XCTAssertEqual(
            defaults.transcriptionCleanupSettings,
            VoiceInkTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )
        )
    }

    func testDefaultSettingsBuildRegisteredUserDefaultsForPlatformSelections() {
        let registeredDefaults = VoiceInkDefaultSettings.macOS.registeredUserDefaults(
            currentTranscriptionModel: "parakeet-tdt-0.6b-v2"
        )

        XCTAssertEqual(registeredDefaults[VoiceInkUserDefaultsKey.hasCompletedOnboarding] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.isTextFormattingEnabled] as? Bool,
            VoiceInkPreferenceDefault.isTextFormattingEnabled
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.isVADEnabled] as? Bool,
            VoiceInkPreferenceDefault.isVADEnabled
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.removeFillerWords] as? Bool,
            VoiceInkPreferenceDefault.removeFillerWords
        )
        XCTAssertEqual(registeredDefaults[PunctuationCleanupMode.legacyRemovePunctuationKey] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.lowercaseTranscription] as? Bool,
            VoiceInkPreferenceDefault.lowercaseTranscription
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            VoiceInkPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.currentTranscriptionModel] as? String,
            "parakeet-tdt-0.6b-v2"
        )
        XCTAssertEqual(registeredDefaults[VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.transcriptionRetentionMinutes] as? Int,
            VoiceInkPreferenceDefault.transcriptionRetentionMinutes
        )
        XCTAssertEqual(registeredDefaults[VoiceInkUserDefaultsKey.isAudioCleanupEnabled] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.audioRetentionPeriodDays] as? Int,
            VoiceInkPreferenceDefault.audioRetentionDays
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.skipShortEnhancement] as? Bool,
            VoiceInkPreferenceDefault.skipShortEnhancement
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.shortEnhancementWordThreshold] as? Int,
            VoiceInkPreferenceDefault.shortEnhancementWordThreshold
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.enhancementTimeoutSeconds] as? Int,
            VoiceInkPreferenceDefault.enhancementTimeoutSeconds
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.enhancementRetryOnTimeout] as? Bool,
            VoiceInkPreferenceDefault.enhancementRetryOnTimeout
        )

        let iOSRegisteredDefaults = VoiceInkDefaultSettings.iOS.registeredUserDefaults()
        XCTAssertNil(iOSRegisteredDefaults[VoiceInkUserDefaultsKey.currentTranscriptionModel])
        XCTAssertEqual(
            iOSRegisteredDefaults[VoiceInkUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            VoiceInkLanguageCatalog.autoDetectCode
        )

        let completedRemovePunctuationDefaults = VoiceInkDefaultSettings(
            punctuationCleanupMode: .removeAll
        ).registeredUserDefaults(
            hasCompletedOnboarding: true
        )
        XCTAssertEqual(
            completedRemovePunctuationDefaults[VoiceInkUserDefaultsKey.hasCompletedOnboarding] as? Bool,
            true
        )
        XCTAssertEqual(
            completedRemovePunctuationDefaults[PunctuationCleanupMode.legacyRemovePunctuationKey] as? Bool,
            true
        )
    }

    func testDefaultSettingsRegisterUserDefaultsForPlatformSelections() {
        let previousRegistrationDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        defer {
            UserDefaults.standard.setVolatileDomain(
                previousRegistrationDomain,
                forName: UserDefaults.registrationDomain
            )
        }

        withIsolatedDefaults { defaults in
            defaults.set("fr", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            VoiceInkDefaultSettings.macOS.registerUserDefaults(
                to: defaults,
                currentTranscriptionModel: "parakeet-tdt-0.6b-v2"
            )

            XCTAssertEqual(
                defaults.object(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding) as? Bool,
                false
            )
            XCTAssertEqual(
                defaults.string(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage),
                "fr"
            )
            XCTAssertEqual(
                defaults.string(forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel),
                "parakeet-tdt-0.6b-v2"
            )
            XCTAssertEqual(
                defaults.object(forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes) as? Int,
                VoiceInkPreferenceDefault.transcriptionRetentionMinutes
            )
        }
    }

    func testOnboardingPreferenceUsesFalseWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults))
            XCTAssertFalse(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))
        }
    }

    func testOnboardingPreferenceSavesAndClearsCompletionState() {
        withIsolatedDefaults { defaults in
            VoiceInkOnboardingPreference.saveHasCompletedOnboarding(true, to: defaults)
            XCTAssertTrue(VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults))
            XCTAssertTrue(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))

            VoiceInkOnboardingPreference.clear(from: defaults)
            XCTAssertFalse(VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults))
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

    func testAudioSessionTimeoutPreferenceOwnsIOSRuntimePolicy() {
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.minimumSeconds, 0)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.maximumSeconds, 300)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.stepSeconds, 15)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.countdownUpdateInterval, 1.0)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.displayText(for: 90), "90s")
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.deactivationPlan(for: 0), .immediate)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.deactivationPlan(for: -1), .immediate)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.deactivationPlan(for: 90), .delayed(90))
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.remainingTimeAfterCountdownTick(90), 89)
    }

    func testAudioSessionTimeoutPresentationPreservesIOSSettingsCopy() {
        let presentation = VoiceInkAudioSessionTimeoutPreference.settingsPresentation

        XCTAssertEqual(presentation.sectionTitle, "Audio Settings")
        XCTAssertEqual(presentation.timeoutTitle, "Session Timeout")
        XCTAssertEqual(
            presentation.detailText,
            "How long to keep the microphone session active after recording stops. Longer timeouts prevent 'session activation failed' errors when recording frequently, but may use more battery."
        )
    }

    func testVADPreferenceUsesSharedDefaultWhenMissing() {
        XCTAssertEqual(VoiceInkVADPreference.userDefaultsKey, "IsVADEnabled")
        XCTAssertTrue(VoiceInkVADPreference.defaultIsEnabled)

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

    func testTranscriptionPromptPreferenceSavesSelectedLanguagePrompt() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("ja", to: defaults)

            let prompt = VoiceInkTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage(
                from: defaults
            )

            XCTAssertEqual(prompt, VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "ja"))
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults),
                VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "ja")
            )
        }
    }

    func testTranscriptionPromptPreferenceSavesCustomPromptForSelectedLanguage() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("en", to: defaults)
            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompt(
                "Spell Roma Just Talk exactly.",
                for: "en",
                to: defaults
            )

            let prompt = VoiceInkTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage(
                from: defaults
            )

            XCTAssertEqual(prompt, "Spell Roma Just Talk exactly.")
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults),
                "Spell Roma Just Talk exactly."
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

    func testTranscriptionLanguagePreferenceUsesMacOSFallbackWhenRequested() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage(from: defaults),
                VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
            )

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage(from: defaults),
                "fr"
            )
        }
    }

    func testTranscriptionLanguagePreferenceSelectsCompatibleLanguageForSource() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "en-US"
            )

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "en-US"
            )

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr-FR", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "fr-FR"
            )
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

    func testCurrentTranscriptionModelPreferenceClearsLegacyModelName() {
        withIsolatedDefaults { defaults in
            defaults.set("legacy-base", forKey: VoiceInkCurrentTranscriptionModelPreference.legacyModelNameKey)

            VoiceInkCurrentTranscriptionModelPreference.clearModelName(from: defaults)

            XCTAssertNil(defaults.string(forKey: VoiceInkCurrentTranscriptionModelPreference.legacyModelNameKey))
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

    func testAIEnhancementProviderPreferenceBuildsDiagnosticDescriptions() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkAIEnhancementPreference.isEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkAIEnhancementPreference.statusDiagnosticDescription(from: defaults),
                "Disabled"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderDiagnosticDescription(from: defaults),
                "None selected"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "None selected"
            )

            VoiceInkAIEnhancementPreference.saveIsEnabled(true, to: defaults)
            VoiceInkAIEnhancementProviderPreference.saveSelectedProviderRawValue("GROQ", to: defaults)

            XCTAssertTrue(VoiceInkAIEnhancementPreference.isEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkAIEnhancementPreference.statusDiagnosticDescription(from: defaults),
                "Enabled"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderDiagnosticDescription(from: defaults),
                "GROQ"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "Default (GROQ)"
            )

            VoiceInkAIEnhancementProviderPreference.saveSelectedModel(
                "llama-3.3-70b-versatile",
                for: "GROQ",
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "llama-3.3-70b-versatile"
            )
        }
    }

    func testAIEnhancementContextPreferenceRoundTripsAndClearsToggles() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))

            VoiceInkAIEnhancementContextPreference.saveUseClipboardContext(true, to: defaults)
            VoiceInkAIEnhancementContextPreference.saveUseScreenCaptureContext(true, to: defaults)

            XCTAssertTrue(VoiceInkAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertTrue(VoiceInkAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))

            VoiceInkAIEnhancementContextPreference.clear(from: defaults)

            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))
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

    func testWordReplacementPreferenceRoundTripsSharedRules() {
        withIsolatedDefaults { defaults in
            let rules = [
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ]

            VoiceInkWordReplacementPreference.saveRules(rules, to: defaults)

            XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), rules)

            VoiceInkWordReplacementPreference.clearRules(from: defaults)
            XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), [])
        }
    }

    func testWordReplacementPreferenceIgnoresInvalidStoredData() {
        withIsolatedDefaults { defaults in
            defaults.set(Data([0]), forKey: VoiceInkUserDefaultsKey.wordReplacements)

            XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), [])
        }
    }

    func testCustomVocabularyPreferenceNormalizesTerms() {
        withIsolatedDefaults { defaults in
            VoiceInkCustomVocabularyPreference.saveTerms([" Roma ", "Felix", "roma", ""], to: defaults)

            XCTAssertEqual(VoiceInkCustomVocabularyPreference.terms(from: defaults), ["Roma", "Felix"])

            VoiceInkCustomVocabularyPreference.clearTerms(from: defaults)
            XCTAssertEqual(VoiceInkCustomVocabularyPreference.terms(from: defaults), [])
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

    func testTranscriptionAutoCleanupBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            VoiceInkTranscriptionAutoCleanupPreference.backupPreferences(
                from: VoiceInkTranscriptionAutoCleanupConfiguration(
                    isEnabled: true,
                    retentionMinutes: 15
                )
            ),
            VoiceInkTranscriptionAutoCleanupBackupPreferences(
                isEnabled: true,
                retentionMinutes: 15
            )
        )
    }

    func testTranscriptionAutoCleanupBackupImportPlanPreservesOptionalFields() {
        XCTAssertEqual(
            VoiceInkTranscriptionAutoCleanupPreference.backupImportPlan(
                from: VoiceInkTranscriptionAutoCleanupBackupPreferences(
                    isEnabled: false,
                    retentionMinutes: 0
                )
            ),
            VoiceInkTranscriptionAutoCleanupBackupImportPlan(
                isEnabled: false,
                retentionMinutes: 0
            )
        )

        XCTAssertEqual(
            VoiceInkTranscriptionAutoCleanupPreference.backupImportPlan(
                from: VoiceInkTranscriptionAutoCleanupBackupPreferences(
                    isEnabled: nil,
                    retentionMinutes: nil
                )
            ),
            VoiceInkTranscriptionAutoCleanupBackupImportPlan(
                isEnabled: nil,
                retentionMinutes: nil
            )
        )
    }

    func testAudioCleanupPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            let configuration = VoiceInkAudioCleanupPreference.current(from: defaults)

            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionDays, VoiceInkPreferenceDefault.audioRetentionDays)
            XCTAssertEqual(configuration.effectiveRetentionDays, VoiceInkPreferenceDefault.audioRetentionDays)
        }
    }

    func testAudioCleanupPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            VoiceInkAudioCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkAudioCleanupPreference.saveRetentionDays(14, to: defaults)

            let configuration = VoiceInkAudioCleanupPreference.current(from: defaults)

            XCTAssertTrue(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionDays, 14)
            XCTAssertEqual(configuration.effectiveRetentionDays, 14)
        }
    }

    func testAudioCleanupConfigurationBuildsDayCutoffDate() {
        let configuration = VoiceInkAudioCleanupConfiguration(isEnabled: true, retentionDays: 7)
        let referenceDate = Date(timeIntervalSince1970: 7 * 86_400)

        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), Date(timeIntervalSince1970: 0))
    }

    func testAudioCleanupConfigurationClampsNegativeRetentionForCutoff() {
        let configuration = VoiceInkAudioCleanupConfiguration(isEnabled: true, retentionDays: -1)
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(configuration.effectiveRetentionDays, 0)
        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), referenceDate)
    }

    func testAudioCleanupBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            VoiceInkAudioCleanupPreference.backupPreferences(
                from: VoiceInkAudioCleanupConfiguration(
                    isEnabled: true,
                    retentionDays: 14
                )
            ),
            VoiceInkAudioCleanupBackupPreferences(
                isEnabled: true,
                retentionDays: 14
            )
        )
    }

    func testAudioCleanupBackupImportPlanPreservesOptionalFields() {
        XCTAssertEqual(
            VoiceInkAudioCleanupPreference.backupImportPlan(
                from: VoiceInkAudioCleanupBackupPreferences(
                    isEnabled: false,
                    retentionDays: 0
                )
            ),
            VoiceInkAudioCleanupBackupImportPlan(
                isEnabled: false,
                retentionDays: 0
            )
        )

        XCTAssertEqual(
            VoiceInkAudioCleanupPreference.backupImportPlan(
                from: VoiceInkAudioCleanupBackupPreferences(
                    isEnabled: nil,
                    retentionDays: nil
                )
            ),
            VoiceInkAudioCleanupBackupImportPlan(
                isEnabled: nil,
                retentionDays: nil
            )
        )
    }

    func testModelRuntimePreferenceRegisteredDefaultsPreserveMacOSPolicy() {
        XCTAssertEqual(VoiceInkModelRuntimePreference.userDefaultsKey, "PrewarmModelOnWake")
        XCTAssertTrue(VoiceInkModelRuntimePreference.defaultShouldPrewarmModelOnWake)
        XCTAssertEqual(
            VoiceInkModelRuntimePreference.registeredDefaults[VoiceInkModelRuntimePreference.userDefaultsKey] as? Bool,
            true
        )
    }

    func testModelRuntimePreferenceReadsSavesAndClearsPrewarmFlag() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))

            VoiceInkModelRuntimePreference.saveShouldPrewarmModelOnWake(false, to: defaults)
            XCTAssertFalse(VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))

            VoiceInkModelRuntimePreference.clear(from: defaults)
            XCTAssertTrue(VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))
        }
    }

    func testRecorderPreviewPreferenceRegisteredDefaultsPreserveMacOSPolicy() {
        XCTAssertEqual(VoiceInkRecorderPreviewPreference.userDefaultsKey, "showLiveTextPreview")
        XCTAssertFalse(VoiceInkRecorderPreviewPreference.defaultIsLiveTextPreviewEnabled)
        XCTAssertEqual(
            VoiceInkRecorderPreviewPreference.registeredDefaults[VoiceInkRecorderPreviewPreference.userDefaultsKey] as? Bool,
            false
        )
    }

    func testMacOSAdvancedTranscriptionSettingsPresentationPreservesCopy() {
        let presentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS

        XCTAssertEqual(presentation.sectionTitle, "Advanced")
        XCTAssertEqual(presentation.vad, VoiceInkVADPreference.macOSSettingsPresentation)
        XCTAssertEqual(presentation.vad.title, "Voice Activity Detection (VAD)")
        XCTAssertEqual(
            presentation.vad.helpText,
            "Use VAD inside batch/final transcription when supported. Buffer preload has its own VAD model in Rolling Buffer settings."
        )
        XCTAssertEqual(presentation.modelPrewarm, VoiceInkModelRuntimePreference.macOSSettingsPresentation)
        XCTAssertEqual(presentation.modelPrewarm.title, "Prewarm model (Experimental)")
        XCTAssertEqual(
            presentation.modelPrewarm.helpText,
            "Turn this on if transcriptions with local models are taking longer than expected. Runs silent background transcription on app launch and wake to trigger optimization."
        )
        XCTAssertEqual(presentation.liveTextPreview, VoiceInkRecorderPreviewPreference.macOSSettingsPresentation)
        XCTAssertEqual(presentation.liveTextPreview.title, "Show Transcript Preview")
        XCTAssertEqual(
            presentation.liveTextPreview.helpText,
            "Displays in-progress transcript text when a model or buffer preload can provide it."
        )
    }

    func testRecorderPreviewPreferenceReadsSavesAndClearsPreviewFlag() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))

            VoiceInkRecorderPreviewPreference.saveIsLiveTextPreviewEnabled(true, to: defaults)
            XCTAssertTrue(VoiceInkRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))

            VoiceInkRecorderPreviewPreference.clear(from: defaults)
            XCTAssertFalse(VoiceInkRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))
        }
    }

    func testRecordingShortcutSelectionPreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(VoiceInkRecordingShortcutSelection.none.rawValue, "none")
        XCTAssertEqual(VoiceInkRecordingShortcutSelection.none.displayName, "None")
        XCTAssertEqual(VoiceInkRecordingShortcutSelection.custom.rawValue, "custom")
        XCTAssertEqual(VoiceInkRecordingShortcutSelection.custom.displayName, "Custom")
    }

    func testRecordingShortcutModePreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(VoiceInkRecordingShortcutMode.special.rawValue, "special")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.special.displayName, "Special")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.toggle.rawValue, "toggle")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.toggle.displayName, "Toggle")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.pushToTalk.displayName, "Push to Talk")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.hybrid.rawValue, "hybrid")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.hybrid.displayName, "Hybrid")
    }

    func testRecordingShortcutPreferencePreservesMacOSSettingsPresentation() {
        let presentation = VoiceInkRecordingShortcutPreference.macOSSettingsPresentation

        XCTAssertEqual(presentation.sectionTitle, "Shortcuts")
        XCTAssertEqual(presentation.primaryShortcutLabel, "Primary Shortcut")
        XCTAssertEqual(presentation.secondaryShortcutLabel, "Secondary Shortcut")
        XCTAssertEqual(presentation.addSecondaryShortcutButtonTitle, "Add Second Shortcut")
        XCTAssertEqual(presentation.emptyTapPasteLastTranscriptLabel, "Empty Tap Pastes Last")
        XCTAssertEqual(presentation.additionalSectionTitle, "Additional Shortcuts")
        XCTAssertEqual(presentation.pasteLastTranscriptionOriginalLabel, "Paste Last Transcription (Original)")
        XCTAssertEqual(presentation.pasteLastTranscriptionEnhancedLabel, "Paste Last Transcription (Enhanced)")
        XCTAssertEqual(presentation.retryLastTranscriptionLabel, "Retry Last Transcription")
        XCTAssertEqual(presentation.cancelRecordingLabel, "Cancel Recording")
        XCTAssertEqual(presentation.resetToDefaultHelp, "Reset to default")
        XCTAssertEqual(presentation.middleClickRecordingLabel, "Middle-Click Recording")
        XCTAssertEqual(presentation.activationDelayLabel, "Activation Delay")
        XCTAssertEqual(presentation.activationDelayUnitLabel, "ms")
    }

    func testRecordingShortcutPreferenceKeysDefaultsAndRegisteredDefaults() {
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.selectionKey(for: .primary),
            VoiceInkUserDefaultsKey.primaryRecordingShortcut
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.selectionKey(for: .secondary),
            VoiceInkUserDefaultsKey.secondaryRecordingShortcut
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.modeKey(for: .primary),
            VoiceInkUserDefaultsKey.primaryRecordingShortcutMode
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.modeKey(for: .secondary),
            VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode
        )
        XCTAssertEqual(
            VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap,
            "specialShortcutPasteLastTranscriptOnEmptyTap"
        )
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.defaultSelection(for: .primary), .custom)
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.defaultSelection(for: .secondary), .none)
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.defaultMode(for: .primary), .special)
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.defaultMode(for: .secondary), .hybrid)
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.registeredDefaults[VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled] as? Bool,
            VoiceInkPreferenceDefault.isMiddleClickToggleEnabled
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.registeredDefaults[VoiceInkUserDefaultsKey.middleClickActivationDelay] as? Int,
            VoiceInkPreferenceDefault.middleClickActivationDelay
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.registeredDefaults[VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap] as? Bool,
            VoiceInkPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
        )
    }

    func testRecordingShortcutPreferenceReadsSavesAndClearsSettings() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .secondary, from: defaults), .hybrid)
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                VoiceInkPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))

            VoiceInkRecordingShortcutPreference.saveSelection(.custom, for: .primary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveSelection(.none, for: .secondary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMode(.toggle, for: .primary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMode(.pushToTalk, for: .secondary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMiddleClickToggleEnabled(true, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMiddleClickActivationDelay(350, to: defaults)
            VoiceInkRecordingShortcutPreference.saveShouldPasteLastTranscriptOnEmptyTap(false, to: defaults)

            XCTAssertEqual(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults), .custom)
            XCTAssertEqual(
                VoiceInkRecordingShortcutPreference.selection(for: .secondary, from: defaults),
                VoiceInkRecordingShortcutSelection.none
            )
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .primary, from: defaults), .toggle)
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .secondary, from: defaults), .pushToTalk)
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults), 350)
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))

            VoiceInkRecordingShortcutPreference.clear(from: defaults)

            XCTAssertNil(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                VoiceInkPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))
        }
    }

    func testRecordingShortcutPreferenceBuildsBackupPreferences() throws {
        let backup = VoiceInkRecordingShortcutPreference.backupPreferences(
            primaryRecordingShortcut: .custom,
            secondaryRecordingShortcut: .none,
            primaryRecordingShortcutMode: .toggle,
            secondaryRecordingShortcutMode: .pushToTalk,
            specialShortcutPasteLastTranscriptOnEmptyTap: false,
            isMiddleClickToggleEnabled: true,
            middleClickActivationDelay: 350
        )

        XCTAssertEqual(backup.primaryRecordingShortcutRawValue, "custom")
        XCTAssertEqual(backup.secondaryRecordingShortcutRawValue, "none")
        XCTAssertEqual(backup.primaryRecordingShortcutModeRawValue, "toggle")
        XCTAssertEqual(backup.secondaryRecordingShortcutModeRawValue, "pushToTalk")
        XCTAssertEqual(backup.specialShortcutPasteLastTranscriptOnEmptyTap, false)
        XCTAssertEqual(backup.isMiddleClickToggleEnabled, true)
        XCTAssertEqual(backup.middleClickActivationDelay, 350)

        let data = try JSONEncoder().encode(backup)
        XCTAssertEqual(
            try JSONDecoder().decode(VoiceInkRecordingShortcutBackupPreferences.self, from: data),
            backup
        )
    }

    func testRecordingShortcutPreferenceBackupImportPlanSkipsInvalidRawValues() {
        let plan = VoiceInkRecordingShortcutPreference.backupImportPlan(
            from: VoiceInkRecordingShortcutBackupPreferences(
                primaryRecordingShortcutRawValue: "custom",
                secondaryRecordingShortcutRawValue: "invalid-selection",
                primaryRecordingShortcutModeRawValue: "toggle",
                secondaryRecordingShortcutModeRawValue: "invalid-mode",
                specialShortcutPasteLastTranscriptOnEmptyTap: false,
                isMiddleClickToggleEnabled: true,
                middleClickActivationDelay: 350
            )
        )

        XCTAssertEqual(plan.primaryRecordingShortcut, .custom)
        XCTAssertNil(plan.secondaryRecordingShortcut)
        XCTAssertEqual(plan.primaryRecordingShortcutMode, .toggle)
        XCTAssertNil(plan.secondaryRecordingShortcutMode)
        XCTAssertEqual(plan.specialShortcutPasteLastTranscriptOnEmptyTap, false)
        XCTAssertEqual(plan.isMiddleClickToggleEnabled, true)
        XCTAssertEqual(plan.middleClickActivationDelay, 350)
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
            VoiceInkWordReplacementPreference.saveRules([
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ], to: defaults)
            VoiceInkCustomVocabularyPreference.saveTerms(["Roma", "Felix"], to: defaults)
            VoiceInkDictionaryListSortPreference.saveVocabularySortMode(.wordDescending, to: defaults)
            VoiceInkDictionaryListSortPreference.saveWordReplacementSortMode(.replacementDescending, to: defaults)
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
            VoiceInkLocalCLIPreference.saveCommandTemplate("codex exec \"$VOICEINK_FULL_PROMPT\"", to: defaults)
            VoiceInkLocalCLIPreference.saveSelectedTemplate(.codex, to: defaults)
            VoiceInkLocalCLIPreference.saveTimeoutSeconds(90, to: defaults)
            defaults.set(15, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
            defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(15, to: defaults)
            VoiceInkAudioCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkAudioCleanupPreference.saveRetentionDays(30, to: defaults)
            let customPrompt = VoiceInkCustomPrompt(title: "Custom", promptText: "Clean this")
            VoiceInkCustomPromptStorage.savePrompts([customPrompt], to: defaults)
            VoiceInkCustomPromptStorage.saveSelectedPromptId(customPrompt.id, to: defaults)
            VoiceInkAIEnhancementContextPreference.saveUseClipboardContext(true, to: defaults)
            VoiceInkAIEnhancementContextPreference.saveUseScreenCaptureContext(true, to: defaults)
            VoiceInkPowerModePreference.saveIsUIEnabled(true, to: defaults)
            VoiceInkPowerModePreference.saveShouldPersistConfiguredPreferences(true, to: defaults)
            VoiceInkModelRuntimePreference.saveShouldPrewarmModelOnWake(false, to: defaults)
            VoiceInkRecorderPreviewPreference.saveIsLiveTextPreviewEnabled(true, to: defaults)
            VoiceInkAudioInputPreference.saveLastUsedMicrophoneDeviceID("123", to: defaults)
            VoiceInkRecordingShortcutPreference.saveSelection(.custom, for: .primary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveSelection(.none, for: .secondary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMode(.toggle, for: .primary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMode(.pushToTalk, for: .secondary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMiddleClickToggleEnabled(true, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMiddleClickActivationDelay(350, to: defaults)
            VoiceInkRecordingShortcutPreference.saveShouldPasteLastTranscriptOnEmptyTap(false, to: defaults)
            let powerModeConfig = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                isAIEnhancementEnabled: false
            )
            VoiceInkPowerModeConfigurationPreference.saveConfigurations([powerModeConfig], to: defaults)
            VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(powerModeConfig.id, to: defaults)
            try? VoiceInkPowerModeSessionPreference.saveActiveSession(
                VoiceInkPowerModeSession(
                    id: UUID(),
                    startTime: Date(timeIntervalSince1970: 1_700_000_000),
                    originalState: VoiceInkPowerModeApplicationState(
                        isEnhancementEnabled: true,
                        useScreenCaptureContext: false
                    )
                ),
                to: defaults
            )

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
            XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), [])
            XCTAssertEqual(VoiceInkCustomVocabularyPreference.terms(from: defaults), [])
            XCTAssertEqual(VoiceInkDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(
                VoiceInkDictionaryListSortPreference.wordReplacementSortMode(from: defaults),
                .originalAscending
            )
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
            XCTAssertEqual(VoiceInkLocalCLIPreference.commandTemplate(from: defaults), "")
            XCTAssertEqual(VoiceInkLocalCLIPreference.selectedTemplate(from: defaults), .pi)
            XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutSeconds(from: defaults), 45)
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
            XCTAssertEqual(
                VoiceInkAudioCleanupPreference.current(from: defaults),
                VoiceInkAudioCleanupConfiguration(
                    isEnabled: false,
                    retentionDays: VoiceInkPreferenceDefault.audioRetentionDays
                )
            )
            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkCustomPromptStorage.loadSelectedPromptId(from: defaults))
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))
            XCTAssertFalse(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertFalse(VoiceInkPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))
            XCTAssertTrue(VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
            XCTAssertNil(try? VoiceInkPowerModeSessionPreference.loadActiveSession(from: defaults))
            XCTAssertTrue(VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))
            XCTAssertFalse(VoiceInkRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))
            XCTAssertNil(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
            XCTAssertNil(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                VoiceInkPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))
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

    func testPowerModeConfigurationPreferenceRoundTripsConfigurationsAndActiveConfigurationId() {
        withIsolatedDefaults { defaults in
            let firstConfig = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                appConfigs: [
                    VoiceInkPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "Example")
                ],
                urlConfigs: [
                    VoiceInkPowerModeURLConfig(url: "example.com")
                ],
                isAIEnhancementEnabled: true,
                selectedPrompt: "prompt-id",
                selectedTranscriptionModelName: "ggml-base",
                selectedLanguage: "en",
                useScreenCapture: true,
                isTextFormattingEnabled: true,
                punctuationCleanupMode: .removeTrailingPeriod,
                lowercaseTranscription: true,
                selectedAIProvider: "openai",
                selectedAIModel: "gpt-4o",
                autoSendKey: .commandEnter,
                isDefault: true
            )
            let secondConfig = PowerModeConfig(
                name: "Notes",
                emoji: "N",
                isAIEnhancementEnabled: false
            )

            VoiceInkPowerModeConfigurationPreference.saveConfigurations([firstConfig, secondConfig], to: defaults)
            VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(secondConfig.id, to: defaults)

            let loadedConfigs = VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults)
            XCTAssertEqual(loadedConfigs.map(\.id), [firstConfig.id, secondConfig.id])
            XCTAssertEqual(loadedConfigs.map(\.name), ["Writing", "Notes"])
            XCTAssertEqual(loadedConfigs.first?.appConfigs?.first?.bundleIdentifier, "com.example.App")
            XCTAssertEqual(loadedConfigs.first?.urlConfigs?.first?.url, "example.com")
            XCTAssertEqual(loadedConfigs.first?.autoSendKey, .commandEnter)
            XCTAssertEqual(
                VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults),
                secondConfig.id
            )
            XCTAssertTrue(defaults.data(forKey: VoiceInkUserDefaultsKey.powerModeConfigurations) != nil)
            XCTAssertEqual(
                defaults.string(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId),
                secondConfig.id.uuidString
            )
        }
    }

    func testPowerModeConfigurationPreferenceFallsBackForMissingInvalidAndBlankActiveId() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))

            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.powerModeConfigurations)
            defaults.set("not-a-uuid", forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)

            XCTAssertTrue(VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))

            defaults.set("", forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
        }
    }

    func testPowerModeConfigurationPreferenceClearRemovesConfigurationsAndActiveConfigurationId() {
        withIsolatedDefaults { defaults in
            let config = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                isAIEnhancementEnabled: false
            )
            VoiceInkPowerModeConfigurationPreference.saveConfigurations([config], to: defaults)
            VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(config.id, to: defaults)

            VoiceInkPowerModeConfigurationPreference.clear(from: defaults)

            XCTAssertTrue(VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
            XCTAssertNil(defaults.object(forKey: VoiceInkUserDefaultsKey.powerModeConfigurations))
            XCTAssertNil(defaults.object(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId))
        }
    }

    func testPowerModePreferenceRegisteredDefaultsPreserveUIFlagInitializationPolicy() {
        XCTAssertNil(VoiceInkPowerModePreference.registeredDefaults[VoiceInkUserDefaultsKey.powerModeUIFlag])
        XCTAssertEqual(
            VoiceInkPowerModePreference.registeredDefaults[VoiceInkUserDefaultsKey.powerModePersistConfig] as? Bool,
            false
        )
    }

    func testPowerModePreferenceReadsAndSavesFlags() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertFalse(VoiceInkPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))

            VoiceInkPowerModePreference.saveIsUIEnabled(true, to: defaults)
            VoiceInkPowerModePreference.saveShouldPersistConfiguredPreferences(true, to: defaults)

            XCTAssertTrue(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertTrue(VoiceInkPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))
        }
    }

    func testPowerModePreferenceInitializesUIFlagFromEnabledConfigurationsWhenMissing() {
        withIsolatedDefaults { defaults in
            VoiceInkPowerModePreference.initializeUIFlagIfNeeded(
                hasEnabledConfigurations: true,
                in: defaults
            )

            XCTAssertTrue(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
        }
    }

    func testPowerModePreferenceInitializeUIFlagDoesNotOverwriteStoredValue() {
        withIsolatedDefaults { defaults in
            VoiceInkPowerModePreference.saveIsUIEnabled(false, to: defaults)

            VoiceInkPowerModePreference.initializeUIFlagIfNeeded(
                hasEnabledConfigurations: true,
                in: defaults
            )

            XCTAssertFalse(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
        }
    }

    func testPowerModePreferenceShortcutEligibilityRequiresUIAndEnabledConfigurations() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkPowerModePreference.canUseShortcuts(hasEnabledConfigurations: true, from: defaults))

            VoiceInkPowerModePreference.saveIsUIEnabled(true, to: defaults)

            XCTAssertFalse(VoiceInkPowerModePreference.canUseShortcuts(hasEnabledConfigurations: false, from: defaults))
            XCTAssertTrue(VoiceInkPowerModePreference.canUseShortcuts(hasEnabledConfigurations: true, from: defaults))
        }
    }

    func testPowerModeSessionPreferenceRoundTripsActiveSession() throws {
        let suiteName = "VoiceInkCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let originalState = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            selectedPromptId: "prompt-id",
            selectedAIProvider: "openai",
            selectedAIModel: "gpt-4o",
            selectedLanguage: "en",
            transcriptionModelName: "ggml-base",
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeAll,
            removePunctuation: true,
            lowercaseTranscription: false
        )
        let session = VoiceInkPowerModeSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            originalState: originalState
        )

        try VoiceInkPowerModeSessionPreference.saveActiveSession(session, to: defaults)

        let loadedSession = try VoiceInkPowerModeSessionPreference.loadActiveSession(from: defaults)
        XCTAssertEqual(loadedSession?.id, session.id)
        XCTAssertEqual(loadedSession?.startTime, session.startTime)
        XCTAssertEqual(loadedSession?.originalState, originalState)
        XCTAssertTrue(defaults.data(forKey: VoiceInkUserDefaultsKey.activePowerModeSession) != nil)
    }

    func testPowerModeSessionPreferenceThrowsForInvalidActiveSessionData() {
        withIsolatedDefaults { defaults in
            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.activePowerModeSession)

            var didThrow = false
            do {
                _ = try VoiceInkPowerModeSessionPreference.loadActiveSession(from: defaults)
            } catch {
                didThrow = true
            }

            XCTAssertTrue(didThrow)
        }
    }

    func testPowerModeSessionPreferenceClearRemovesActiveSession() {
        withIsolatedDefaults { defaults in
            let session = VoiceInkPowerModeSession(
                id: UUID(),
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                originalState: VoiceInkPowerModeApplicationState(
                    isEnhancementEnabled: false,
                    useScreenCaptureContext: true
                )
            )
            try? VoiceInkPowerModeSessionPreference.saveActiveSession(session, to: defaults)

            VoiceInkPowerModeSessionPreference.clear(from: defaults)

            XCTAssertNil(try? VoiceInkPowerModeSessionPreference.loadActiveSession(from: defaults))
            XCTAssertNil(defaults.object(forKey: VoiceInkUserDefaultsKey.activePowerModeSession))
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
