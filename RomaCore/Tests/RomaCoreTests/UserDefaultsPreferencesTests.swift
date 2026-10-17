import Foundation
@testable import RomaCore

final class UserDefaultsPreferencesTests: XCTestCase {

    func testMacOSEnhancementSettingsPresentationPreservesOptions() {
        let presentation = RomaEnhancementSettingsPresentation.macOS

        XCTAssertEqual(
            presentation.shortEnhancementWordOptions,
            (1...15).map {
                RomaEnhancementIntegerOption(title: "\($0) \($0 == 1 ? "word" : "words")", value: $0)
            }
        )
        XCTAssertEqual(
            presentation.timeoutOptions,
            [3, 5, 7, 10, 15, 20, 30, 40, 50, 60].map {
                RomaEnhancementIntegerOption(title: "\($0) seconds", value: $0)
            }
        )
        XCTAssertEqual(
            presentation.timeoutRetryOptions,
            [
                RomaEnhancementRetryOption(title: "Fail immediately", value: false),
                RomaEnhancementRetryOption(title: "Retry", value: true)
            ]
        )
    }

    func testSharedPreferenceKeysPreserveExistingStorageNames() {
        XCTAssertEqual(RomaUserDefaultsKey.hasCompletedOnboarding, "hasCompletedOnboarding")
        XCTAssertEqual(RomaUserDefaultsKey.lowercaseTranscription, "LowercaseTranscription")
        XCTAssertEqual(RomaUserDefaultsKey.removeFillerWords, "RemoveFillerWords")
        XCTAssertEqual(RomaUserDefaultsKey.fillerWords, "FillerWords")
        XCTAssertEqual(RomaUserDefaultsKey.wordReplacements, "romaIOSWordReplacements")
        XCTAssertEqual(RomaUserDefaultsKey.customVocabularyTerms, "romaIOSCustomVocabularyTerms")
        XCTAssertEqual(RomaUserDefaultsKey.modes, "modes")
        XCTAssertEqual(RomaUserDefaultsKey.selectedModeId, "selectedModeId")
        XCTAssertEqual(RomaUserDefaultsKey.selectedTranscriptionLanguage, "SelectedLanguage")
        XCTAssertEqual(RomaUserDefaultsKey.currentTranscriptionModel, "CurrentTranscriptionModel")
        XCTAssertEqual(RomaUserDefaultsKey.transcriptionPrompt, "TranscriptionPrompt")
        XCTAssertEqual(RomaUserDefaultsKey.isTextFormattingEnabled, "IsTextFormattingEnabled")
        XCTAssertEqual(RomaUserDefaultsKey.isVADEnabled, "IsVADEnabled")
        XCTAssertEqual(RomaUserDefaultsKey.isTranscriptionCleanupEnabled, "IsTranscriptionCleanupEnabled")
        XCTAssertEqual(RomaUserDefaultsKey.transcriptionRetentionMinutes, "TranscriptionRetentionMinutes")
        XCTAssertEqual(RomaUserDefaultsKey.isAudioCleanupEnabled, "IsAudioCleanupEnabled")
        XCTAssertEqual(RomaUserDefaultsKey.audioRetentionPeriodDays, "AudioRetentionPeriod")
        XCTAssertEqual(RomaUserDefaultsKey.appendTrailingSpace, "AppendTrailingSpace")
        XCTAssertEqual(RomaUserDefaultsKey.skipShortEnhancement, "SkipShortEnhancement")
        XCTAssertEqual(RomaUserDefaultsKey.shortEnhancementWordThreshold, "ShortEnhancementWordThreshold")
        XCTAssertEqual(RomaUserDefaultsKey.enhancementTimeoutSeconds, "EnhancementTimeoutSeconds")
        XCTAssertEqual(RomaUserDefaultsKey.enhancementRetryOnTimeout, "EnhancementRetryOnTimeout")
        XCTAssertEqual(RomaUserDefaultsKey.audioSessionTimeoutSeconds, "audioSessionTimeoutSeconds")
        XCTAssertEqual(RomaUserDefaultsKey.isAIEnhancementEnabled, "isAIEnhancementEnabled")
        XCTAssertEqual(RomaUserDefaultsKey.useClipboardContext, "useClipboardContext")
        XCTAssertEqual(RomaUserDefaultsKey.useScreenCaptureContext, "useScreenCaptureContext")
        XCTAssertEqual(RomaUserDefaultsKey.customPrompts, "customPrompts")
        XCTAssertEqual(RomaUserDefaultsKey.selectedPromptId, "selectedPromptId")
        XCTAssertEqual(RomaUserDefaultsKey.powerModeUIFlag, "powerModeUIFlag")
        XCTAssertEqual(RomaUserDefaultsKey.powerModePersistConfig, "powerModePersistConfig")
        XCTAssertEqual(RomaUserDefaultsKey.powerModeConfigurations, "powerModeConfigurationsV2")
        XCTAssertEqual(RomaUserDefaultsKey.activePowerModeConfigurationId, "activeConfigurationId")
        XCTAssertEqual(RomaUserDefaultsKey.activePowerModeSession, "powerModeActiveSession.v1")
        XCTAssertEqual(RomaUserDefaultsKey.prewarmModelOnWake, "PrewarmModelOnWake")
        XCTAssertEqual(RomaUserDefaultsKey.showLiveTextPreview, "showLiveTextPreview")
        XCTAssertEqual(RomaUserDefaultsKey.primaryRecordingShortcut, "primaryRecordingShortcut")
        XCTAssertEqual(RomaUserDefaultsKey.secondaryRecordingShortcut, "secondaryRecordingShortcut")
        XCTAssertEqual(RomaUserDefaultsKey.primaryRecordingShortcutMode, "primaryRecordingShortcutMode")
        XCTAssertEqual(RomaUserDefaultsKey.secondaryRecordingShortcutMode, "secondaryRecordingShortcutMode")
        XCTAssertEqual(RomaUserDefaultsKey.isMiddleClickToggleEnabled, "isMiddleClickToggleEnabled")
        XCTAssertEqual(RomaUserDefaultsKey.middleClickActivationDelay, "middleClickActivationDelay")
        XCTAssertEqual(RomaUserDefaultsKey.selectedAIProvider, "selectedAIProvider")
        XCTAssertEqual(RomaUserDefaultsKey.openRouterModels, "openRouterModels")
        XCTAssertEqual(RomaUserDefaultsKey.ollamaBaseURL, "ollamaBaseURL")
        XCTAssertEqual(RomaUserDefaultsKey.ollamaSelectedModel, "ollamaSelectedModel")
        XCTAssertEqual(RomaUserDefaultsKey.customProviderBaseURL, "customProviderBaseURL")
        XCTAssertEqual(RomaUserDefaultsKey.customProviderModel, "customProviderModel")
        XCTAssertEqual(RomaUserDefaultsKey.showMenuBarIcon, "ShowMenuBarIcon")
        XCTAssertEqual(RomaUserDefaultsKey.legacyIsMenuBarOnly, "IsMenuBarOnly")
        XCTAssertEqual(RomaUserDefaultsKey.didApplyLaunchAtLoginDefault, "DidApplyLaunchAtLoginDefault")
    }

    func testPreferenceListRemovingAtOffsetsPreservesRemainingOrder() {
        XCTAssertEqual(
            RomaPreferenceList.removing(at: IndexSet([1, 3]), from: ["zero", "one", "two", "three"]),
            ["zero", "two"]
        )
    }

    func testPreferenceListRemovingAtOffsetsIgnoresOutOfRangeIndexes() {
        XCTAssertEqual(
            RomaPreferenceList.removing(at: IndexSet([1, 9]), from: ["zero", "one", "two"]),
            ["zero", "two"]
        )
    }

    func testAIProviderModelSelectionKeyPreservesExistingProviderRawValuePattern() {
        XCTAssertEqual(RomaUserDefaultsKey.selectedAIProviderModel("Groq"), "GroqSelectedModel")
        XCTAssertEqual(RomaUserDefaultsKey.selectedAIProviderModel("Local CLI"), "Local CLISelectedModel")
    }

    func testSharedPreferenceDefaultsPreserveExistingIOSAudioSessionTimeout() {
        XCTAssertEqual(RomaPreferenceDefault.audioSessionTimeoutSeconds, 90)
    }

    func testSharedPreferenceDefaultsPreserveExistingTextFormattingPolicy() {
        XCTAssertEqual(RomaPreferenceDefault.isTextFormattingEnabled, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingVADPolicy() {
        XCTAssertEqual(RomaPreferenceDefault.isVADEnabled, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingTranscriptionCleanupPolicy() {
        XCTAssertEqual(RomaPreferenceDefault.lowercaseTranscription, false)
        XCTAssertEqual(RomaPreferenceDefault.removeFillerWords, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingCleanupRetention() {
        XCTAssertEqual(RomaPreferenceDefault.transcriptionRetentionMinutes, 24 * 60)
        XCTAssertEqual(RomaPreferenceDefault.audioRetentionDays, 7)
    }

    func testSharedPreferenceDefaultsPreserveMacOSTrailingSpacePolicy() {
        XCTAssertEqual(RomaPreferenceDefault.appendTrailingSpace, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingShortEnhancementPolicy() {
        XCTAssertEqual(RomaPreferenceDefault.skipShortEnhancement, true)
        XCTAssertEqual(RomaPreferenceDefault.shortEnhancementWordThreshold, 3)
    }

    func testSharedPreferenceDefaultsPreserveExistingEnhancementTimeoutPolicy() {
        XCTAssertEqual(RomaPreferenceDefault.enhancementTimeoutSeconds, 7)
        XCTAssertEqual(RomaPreferenceDefault.enhancementRetryOnTimeout, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingPowerModeFlags() {
        XCTAssertFalse(RomaPreferenceDefault.powerModeUIEnabled)
        XCTAssertFalse(RomaPreferenceDefault.powerModePersistConfiguredPreferences)
    }

    func testSharedPreferenceDefaultsPreserveExistingMacOSRuntimeFlags() {
        XCTAssertTrue(RomaPreferenceDefault.prewarmModelOnWake)
        XCTAssertFalse(RomaPreferenceDefault.showLiveTextPreview)
    }

    func testSharedPreferenceDefaultsPreserveExistingMacOSMenuBarPolicy() {
        XCTAssertFalse(RomaPreferenceDefault.showMenuBarIcon)
        XCTAssertFalse(RomaPreferenceDefault.showDockIcon)
        XCTAssertFalse(RomaPreferenceDefault.didApplyLaunchAtLoginDefault)
    }

    func testSharedPreferenceDefaultsPreserveExistingRecordingShortcutFlags() {
        XCTAssertFalse(RomaPreferenceDefault.isMiddleClickToggleEnabled)
        XCTAssertEqual(RomaPreferenceDefault.middleClickActivationDelay, 200)
    }

    func testSharedPreferenceDefaultsPreserveExistingOllamaBaseURL() {
        XCTAssertEqual(RomaPreferenceDefault.ollamaBaseURL, "http://localhost:11434")
    }

    func testDefaultSettingsPreserveIOSResetState() {
        let defaults = RomaDefaultSettings.iOS

        XCTAssertEqual(defaults.audioSessionTimeoutSeconds, RomaPreferenceDefault.audioSessionTimeoutSeconds)
        XCTAssertEqual(defaults.punctuationCleanupMode, .keep)
        XCTAssertEqual(defaults.isTextFormattingEnabled, RomaPreferenceDefault.isTextFormattingEnabled)
        XCTAssertEqual(defaults.isVADEnabled, RomaPreferenceDefault.isVADEnabled)
        XCTAssertEqual(defaults.lowercaseTranscription, RomaPreferenceDefault.lowercaseTranscription)
        XCTAssertEqual(defaults.removeFillerWords, RomaPreferenceDefault.removeFillerWords)
        XCTAssertEqual(defaults.fillerWords, RomaFillerWords.defaultWords)
        XCTAssertEqual(defaults.selectedTranscriptionLanguage, RomaLanguageCatalog.autoDetectCode)
    }

    func testDefaultSettingsBuildSharedAppSettingsResetState() {
        let defaults = RomaDefaultSettings(
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
        XCTAssertEqual(resetState.apiKeyState, RomaProviderAPIKeyState())
        XCTAssertEqual(resetState.audioSessionTimeoutSeconds, 12)
        XCTAssertEqual(
            resetState.transcriptionCleanupSettings,
            RomaTranscriptionCleanupSettings(
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
        XCTAssertEqual(resetState.apiKeyProvidersToDelete, RomaProviderKind.userAPIKeyProviders)
    }

    func testAppSettingsResetStateAppliesDefaultRuntimeStateInOrder() {
        let resetState = RomaDefaultSettings.iOS.appSettingsResetState

        XCTAssertEqual(appSettingsResetActionEvents(for: resetState), [
            "applyResetState",
            "clearCoreUserSettings",
            "deleteProviderAPIKeys:\(RomaProviderKind.userAPIKeyProviders.map(\.rawValue).joined(separator: ","))"
        ])
    }

    func testAppSettingsResetStateAppliesRuntimeStateInOrder() {
        let mode = Mode(name: "Focus")
        let resetState = RomaAppSettingsResetState(
            modes: [mode],
            selectedModeId: mode.id,
            apiKeyState: RomaProviderAPIKeyState(storedKeysByProvider: [.groq: "groq-key"]),
            audioSessionTimeoutSeconds: 90,
            transcriptionCleanupSettings: RomaTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            ),
            fillerWords: ["uh"],
            wordReplacements: [
                RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ],
            customVocabularyTerms: ["Whisper"],
            selectedTranscriptionLanguage: "fr",
            apiKeyProvidersToDelete: [.groq, .openAI]
        )
        var events: [String] = []

        resetState.applyRuntimeState(
            setModes: { modes in events.append("modes:\(modes.count)") },
            setSelectedModeId: { selectedModeId in events.append("selectedMode:\(selectedModeId == mode.id)") },
            setAPIKeyState: { state in events.append("apiKey:\(state.storedAPIKey(for: .groq))") },
            setAudioSessionTimeoutSeconds: { timeout in events.append("timeout:\(timeout)") },
            setTranscriptionCleanupSettings: { settings in events.append("cleanup:\(settings.punctuationMode.rawValue)") },
            setFillerWords: { words in events.append("filler:\(words.joined(separator: ","))") },
            setWordReplacements: { rules in events.append("rules:\(rules.count)") },
            setCustomVocabularyTerms: { terms in events.append("vocabulary:\(terms.joined(separator: ","))") },
            setSelectedTranscriptionLanguage: { language in events.append("language:\(language)") },
            clearCoreUserSettings: { events.append("clear") },
            deleteProviderAPIKeys: { providers in events.append("delete:\(providers.map(\.rawValue).joined(separator: ","))") }
        )

        XCTAssertEqual(events, [
            "modes:1",
            "selectedMode:true",
            "apiKey:groq-key",
            "timeout:90",
            "cleanup:removeTrailingPeriod",
            "filler:uh",
            "rules:1",
            "vocabulary:Whisper",
            "language:fr",
            "clear",
            "delete:groq,openAI"
        ])
    }

    func testAppSettingsResetStateSkipsProviderDeletionRuntimeActionWhenNoProviders() {
        let resetState = RomaAppSettingsResetState(
            modes: [],
            selectedModeId: nil,
            apiKeyState: RomaProviderAPIKeyState(),
            audioSessionTimeoutSeconds: 30,
            transcriptionCleanupSettings: RomaDefaultSettings.iOS.transcriptionCleanupSettings,
            fillerWords: [],
            wordReplacements: [],
            customVocabularyTerms: [],
            selectedTranscriptionLanguage: RomaLanguageCatalog.autoDetectCode,
            apiKeyProvidersToDelete: []
        )

        XCTAssertEqual(appSettingsResetActionEvents(for: resetState), [
            "applyResetState",
            "clearCoreUserSettings"
        ])
    }

    private func appSettingsResetActionEvents(
        for resetState: RomaAppSettingsResetState
    ) -> [String] {
        var events: [String] = []
        resetState.applyRuntimeState(
            setModes: { _ in events.append("applyResetState") },
            setSelectedModeId: { _ in },
            setAPIKeyState: { _ in },
            setAudioSessionTimeoutSeconds: { _ in },
            setTranscriptionCleanupSettings: { _ in },
            setFillerWords: { _ in },
            setWordReplacements: { _ in },
            setCustomVocabularyTerms: { _ in },
            setSelectedTranscriptionLanguage: { _ in },
            clearCoreUserSettings: {
                events.append("clearCoreUserSettings")
            },
            deleteProviderAPIKeys: { providers in
                events.append("deleteProviderAPIKeys:\(providers.map(\.rawValue).joined(separator: ","))")
            }
        )
        return events
    }

    func testIOSAppSettingsStartupPolicyLoadsPersistedStateThroughAdapters() {
        let suiteName = "RomaCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mode = Mode(
            name: "Meeting",
            transcriptionProvider: .groq,
            transcriptionModel: "whisper-large-v3",
            isPostProcessingEnabled: true,
            postProcessingProvider: .openAI,
            postProcessingModel: "gpt-4o-mini"
        )
        RomaModeStorage.saveModes([mode], to: defaults)
        RomaModeStorage.saveSelectedModeId(mode.id, to: defaults)
        RomaAudioSessionTimeoutPreference.saveTimeoutSeconds(120, to: defaults)
        PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
        RomaTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
        RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
        RomaTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)
        RomaFillerWordPreference.saveWords(["um", "like"], to: defaults)
        RomaWordReplacementPreference.saveRules([
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ], to: defaults)
        RomaCustomVocabularyPreference.saveTerms([" Felix ", "roma", " "], to: defaults)
        RomaTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
        RomaProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)

        let startupState = RomaIOSAppSettingsStartupPolicy.state(
            from: defaults,
            verifiedProviders: RomaProviderAPIKeyVerificationState.verifiedProviders(in: defaults),
            loadStoredAPIKey: { provider in
                provider == .groq ? "groq-key" : ""
            }
        )

        XCTAssertEqual(startupState.modes.count, 1)
        XCTAssertEqual(startupState.modes.first?.id, mode.id)
        XCTAssertEqual(startupState.modes.first?.transcriptionProvider, .groq)
        XCTAssertEqual(startupState.selectedModeId, mode.id)
        XCTAssertEqual(startupState.apiKeyState.storedAPIKey(for: .groq), "groq-key")
        XCTAssertEqual(startupState.audioSessionTimeoutSeconds, 120)
        XCTAssertEqual(
            startupState.transcriptionCleanupSettings,
            RomaTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )
        )
        XCTAssertEqual(startupState.fillerWords, ["um", "like"])
        XCTAssertEqual(
            startupState.wordReplacements,
            [RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")]
        )
        XCTAssertEqual(startupState.customVocabularyTerms, ["Felix", "roma"])
        XCTAssertEqual(startupState.selectedTranscriptionLanguage, "fr")
    }

    func testIOSFirstTimeSetupPolicySeedsDefaultModeAndCompletionIntent() {
        let plan = RomaIOSFirstTimeSetupPolicy.plan(
            modes: [],
            selectedModeId: nil,
            selectedTranscriptionLanguage: "not-a-language"
        )
        var didSaveHasCompletedOnboarding = false
        var appliedModeSettingsRepairPlan: RomaModeSettingsRepairPlan?

        plan.applyRuntimeState(
            applyModeSettingsRepair: { repairPlan in
                appliedModeSettingsRepairPlan = repairPlan
            },
            saveHasCompletedOnboarding: {
                didSaveHasCompletedOnboarding = true
            }
        )

        XCTAssertTrue(didSaveHasCompletedOnboarding)
        guard let modeSettingsRepairPlan = appliedModeSettingsRepairPlan else {
            return XCTFail("Expected first-time setup to apply mode repair")
        }
        XCTAssertTrue(modeSettingsRepairPlan.shouldReplaceModes)
        XCTAssertEqual(modeSettingsRepairPlan.modes.count, 1)
        XCTAssertEqual(modeSettingsRepairPlan.modes.first?.id, modeSettingsRepairPlan.selectedModeId)
        XCTAssertEqual(modeSettingsRepairPlan.modes.first?.transcriptionProvider, .localWhisper)
        XCTAssertEqual(
            modeSettingsRepairPlan.selectedTranscriptionLanguage,
            RomaLanguageCatalog.autoDetectCode
        )
    }

    func testIOSFirstTimeSetupPlanSkipsOnboardingRuntimeActionWhenDisabled() {
        let plan = RomaIOSFirstTimeSetupPlan(
            modeSettingsRepairPlan: RomaModeSettingsPolicy.defaultModeRepairPlan(
                modes: [],
                selectedModeId: nil,
                selectedTranscriptionLanguage: "not-a-language"
            ),
            shouldSaveHasCompletedOnboarding: false
        )

        XCTAssertEqual(iOSFirstTimeSetupEvents(for: plan), ["repair:1"])
    }

    func testIOSFirstTimeSetupPlanAppliesRuntimeStateInOrder() {
        let plan = RomaIOSFirstTimeSetupPolicy.plan(
            modes: [],
            selectedModeId: nil,
            selectedTranscriptionLanguage: "not-a-language"
        )
        XCTAssertEqual(iOSFirstTimeSetupEvents(for: plan), [
            "repair:1",
            "saveOnboarding"
        ])
    }

    private func iOSFirstTimeSetupEvents(
        for plan: RomaIOSFirstTimeSetupPlan
    ) -> [String] {
        var events: [String] = []
        plan.applyRuntimeState(
            applyModeSettingsRepair: { repairPlan in
                events.append("repair:\(repairPlan.modes.count)")
            },
            saveHasCompletedOnboarding: {
                events.append("saveOnboarding")
            }
        )
        return events
    }

    func testDefaultSettingsPreserveMacOSSelectedLanguageDefault() {
        let defaults = RomaDefaultSettings.macOS
        let registeredDefaults = defaults.registeredUserDefaults()

        XCTAssertEqual(
            defaults.selectedTranscriptionLanguage,
            RomaPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
        XCTAssertEqual(defaults.selectedTranscriptionLanguage, "en")
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            RomaPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
    }

    func testDefaultSettingsExposeTranscriptionCleanupSettings() {
        let defaults = RomaDefaultSettings(
            punctuationCleanupMode: .removeTrailingPeriod,
            isTextFormattingEnabled: false,
            lowercaseTranscription: true,
            removeFillerWords: false
        )

        XCTAssertEqual(
            defaults.transcriptionCleanupSettings,
            RomaTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )
        )
    }

    func testDefaultSettingsBuildRegisteredUserDefaultsForPlatformSelections() {
        let registeredDefaults = RomaDefaultSettings.macOS.registeredUserDefaults(
            currentTranscriptionModel: RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )

        XCTAssertEqual(registeredDefaults[RomaUserDefaultsKey.hasCompletedOnboarding] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.isTextFormattingEnabled] as? Bool,
            RomaPreferenceDefault.isTextFormattingEnabled
        )
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.isVADEnabled] as? Bool,
            RomaPreferenceDefault.isVADEnabled
        )
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.removeFillerWords] as? Bool,
            RomaPreferenceDefault.removeFillerWords
        )
        XCTAssertEqual(registeredDefaults[PunctuationCleanupMode.legacyRemovePunctuationKey] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.lowercaseTranscription] as? Bool,
            RomaPreferenceDefault.lowercaseTranscription
        )
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            RomaPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.currentTranscriptionModel] as? String,
            RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )
        XCTAssertEqual(registeredDefaults[RomaUserDefaultsKey.isTranscriptionCleanupEnabled] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.transcriptionRetentionMinutes] as? Int,
            RomaPreferenceDefault.transcriptionRetentionMinutes
        )
        XCTAssertEqual(registeredDefaults[RomaUserDefaultsKey.isAudioCleanupEnabled] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.audioRetentionPeriodDays] as? Int,
            RomaPreferenceDefault.audioRetentionDays
        )
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.skipShortEnhancement] as? Bool,
            RomaPreferenceDefault.skipShortEnhancement
        )
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.shortEnhancementWordThreshold] as? Int,
            RomaPreferenceDefault.shortEnhancementWordThreshold
        )
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.enhancementTimeoutSeconds] as? Int,
            RomaPreferenceDefault.enhancementTimeoutSeconds
        )
        XCTAssertEqual(
            registeredDefaults[RomaUserDefaultsKey.enhancementRetryOnTimeout] as? Bool,
            RomaPreferenceDefault.enhancementRetryOnTimeout
        )

        let iOSRegisteredDefaults = RomaDefaultSettings.iOS.registeredUserDefaults()
        XCTAssertNil(iOSRegisteredDefaults[RomaUserDefaultsKey.currentTranscriptionModel])
        XCTAssertEqual(
            iOSRegisteredDefaults[RomaUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            RomaLanguageCatalog.autoDetectCode
        )

        let completedRemovePunctuationDefaults = RomaDefaultSettings(
            punctuationCleanupMode: .removeAll
        ).registeredUserDefaults(
            hasCompletedOnboarding: true
        )
        XCTAssertEqual(
            completedRemovePunctuationDefaults[RomaUserDefaultsKey.hasCompletedOnboarding] as? Bool,
            true
        )
        XCTAssertEqual(
            completedRemovePunctuationDefaults[PunctuationCleanupMode.legacyRemovePunctuationKey] as? Bool,
            true
        )
    }

    func testMenuBarPreferencePreservesRegisteredDefaultsAndStorage() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaMacOSSettingsPresentation.macOS.menuBarTitle, "Menu Bar")
            XCTAssertEqual(RomaMacOSSettingsPresentation.macOS.dockIconTitle, "Dock Icon")
            XCTAssertEqual(
                RomaMenuBarPreference.showMenuBarIconKey,
                RomaUserDefaultsKey.showMenuBarIcon
            )
            XCTAssertEqual(
                RomaMenuBarPreference.legacyIsMenuBarOnlyKey,
                RomaUserDefaultsKey.legacyIsMenuBarOnly
            )
            XCTAssertEqual(
                RomaMenuBarPreference.registeredDefaults[RomaUserDefaultsKey.showMenuBarIcon] as? Bool,
                RomaPreferenceDefault.showMenuBarIcon
            )
            XCTAssertEqual(
                RomaMenuBarPreference.registeredDefaults[RomaUserDefaultsKey.legacyIsMenuBarOnly] as? Bool,
                !RomaPreferenceDefault.showDockIcon
            )

            XCTAssertFalse(RomaMenuBarPreference.shouldShowMenuBarIcon(from: defaults))
            XCTAssertFalse(RomaMenuBarPreference.shouldShowDockIcon(from: defaults))

            defaults.register(defaults: RomaMenuBarPreference.registeredDefaults)

            XCTAssertFalse(RomaMenuBarPreference.shouldShowMenuBarIcon(from: defaults))
            XCTAssertFalse(RomaMenuBarPreference.shouldShowDockIcon(from: defaults))

            RomaMenuBarPreference.saveShowMenuBarIcon(true, to: defaults)
            RomaMenuBarPreference.saveShowDockIcon(true, to: defaults)

            XCTAssertTrue(RomaMenuBarPreference.shouldShowMenuBarIcon(from: defaults))
            XCTAssertTrue(RomaMenuBarPreference.shouldShowDockIcon(from: defaults))
            XCTAssertFalse(defaults.bool(forKey: RomaMenuBarPreference.legacyIsMenuBarOnlyKey))
            XCTAssertEqual(
                RomaMacOSMenuBarPresentation.dockIconTitle(showDockIcon: true),
                "Hide Dock Icon"
            )
            XCTAssertEqual(
                RomaMacOSMenuBarPresentation.dockIconTitle(showDockIcon: false),
                "Show Dock Icon"
            )
        }
    }

    func testMacOSLaunchAtLoginDefaultPolicyPreservesExistingStorageAndRegisteredDefault() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaMacOSLaunchAtLoginDefaultPolicy.didApplyDefaultKey,
                RomaUserDefaultsKey.didApplyLaunchAtLoginDefault
            )
            XCTAssertEqual(
                RomaMacOSLaunchAtLoginDefaultPolicy.registeredDefaults[
                    RomaMacOSLaunchAtLoginDefaultPolicy.didApplyDefaultKey
                ] as? Bool,
                false
            )
            XCTAssertTrue(RomaMacOSLaunchAtLoginDefaultPolicy.shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults))

            RomaMacOSLaunchAtLoginDefaultPolicy.markDefaultApplied(to: defaults)

            XCTAssertFalse(RomaMacOSLaunchAtLoginDefaultPolicy.shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults))
            XCTAssertEqual(
                defaults.bool(forKey: RomaMacOSLaunchAtLoginDefaultPolicy.didApplyDefaultKey),
                true
            )
        }
    }

    func testMacOSLaunchAtLoginDefaultPolicySkipsExistingOnboardingOrRegisteredState() {
        withIsolatedDefaults { defaults in
            RomaOnboardingPreference.saveHasCompletedOnboarding(false, to: defaults)

            XCTAssertFalse(RomaMacOSLaunchAtLoginDefaultPolicy.shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults))
        }

        withIsolatedDefaults { defaults in
            defaults.register(defaults: RomaMacOSLaunchAtLoginDefaultPolicy.registeredDefaults)

            XCTAssertFalse(RomaMacOSLaunchAtLoginDefaultPolicy.shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults))
        }
    }

    func testMacOSShellBackupPreferencesPreserveExportShape() {
        XCTAssertEqual(
            RomaMacOSShellBackupPreference.backupPreferences(
                launchAtLoginEnabled: true,
                showDockIcon: true,
                recorderType: "mini"
            ),
            RomaMacOSShellBackupPreferences(
                launchAtLoginEnabled: true,
                showDockIcon: true,
                recorderType: "mini"
            )
        )
    }

    func testMacOSShellBackupImportPlanPreservesOptionalFields() {
        XCTAssertEqual(
            RomaMacOSShellBackupPreference.backupImportPlan(
                from: RomaMacOSShellBackupPreferences(
                    launchAtLoginEnabled: nil,
                    showDockIcon: false,
                    recorderType: nil
                )
            ),
            RomaMacOSShellBackupImportPlan(
                launchAtLoginEnabled: nil,
                showDockIcon: false,
                recorderType: nil
            )
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
            defaults.set("fr", forKey: RomaUserDefaultsKey.selectedTranscriptionLanguage)
            RomaDefaultSettings.macOS.registerUserDefaults(
                to: defaults,
                currentTranscriptionModel: RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
            )

            XCTAssertEqual(
                defaults.object(forKey: RomaUserDefaultsKey.hasCompletedOnboarding) as? Bool,
                false
            )
            XCTAssertEqual(
                defaults.string(forKey: RomaUserDefaultsKey.selectedTranscriptionLanguage),
                "fr"
            )
            XCTAssertEqual(
                defaults.string(forKey: RomaUserDefaultsKey.currentTranscriptionModel),
                RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
            )
            XCTAssertEqual(
                defaults.object(forKey: RomaUserDefaultsKey.transcriptionRetentionMinutes) as? Int,
                RomaPreferenceDefault.transcriptionRetentionMinutes
            )
        }
    }

    func testStartupPreferenceMigrationUsesIOSMigrationSet() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)
            defaults.set(true, forKey: RomaPasteMethod.legacyAppleScriptPasteKey)

            RomaStartupPreferenceMigration.migrateLegacyPreferences(for: .iOS, in: defaults)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
            XCTAssertNil(defaults.string(forKey: RomaPasteMethod.userDefaultsKey))
        }
    }

    func testStartupPreferenceMigrationUsesMacOSMigrationSet() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)
            defaults.set(true, forKey: RomaPasteMethod.legacyAppleScriptPasteKey)

            RomaStartupPreferenceMigration.migrateLegacyPreferences(for: .macOS, in: defaults)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
            XCTAssertEqual(RomaPasteMethod.current(in: defaults), .appleScript)
            XCTAssertEqual(defaults.string(forKey: RomaPasteMethod.userDefaultsKey), "appleScript")
        }
    }

    func testOnboardingPreferenceUsesFalseWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(RomaOnboardingPreference.hasStoredCompletionState(from: defaults))
            XCTAssertFalse(RomaOnboardingPreference.hasCompletedOnboarding(from: defaults))
        }
    }

    func testOnboardingPreferenceSavesAndClearsCompletionState() {
        withIsolatedDefaults { defaults in
            RomaOnboardingPreference.saveHasCompletedOnboarding(true, to: defaults)
            XCTAssertTrue(RomaOnboardingPreference.hasStoredCompletionState(from: defaults))
            XCTAssertTrue(RomaOnboardingPreference.hasCompletedOnboarding(from: defaults))

            RomaOnboardingPreference.clear(from: defaults)
            XCTAssertFalse(RomaOnboardingPreference.hasStoredCompletionState(from: defaults))
            XCTAssertFalse(RomaOnboardingPreference.hasCompletedOnboarding(from: defaults))
        }
    }

    func testAudioSessionTimeoutPreferenceUsesExistingDefaultWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                RomaPreferenceDefault.audioSessionTimeoutSeconds
            )
        }
    }

    func testAudioSessionTimeoutPreferenceSavesAndClearsTimeout() {
        withIsolatedDefaults { defaults in
            RomaAudioSessionTimeoutPreference.saveTimeoutSeconds(120, to: defaults)
            XCTAssertEqual(RomaAudioSessionTimeoutPreference.timeoutSeconds(from: defaults), 120)

            RomaAudioSessionTimeoutPreference.clear(from: defaults)
            XCTAssertEqual(
                RomaAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                RomaPreferenceDefault.audioSessionTimeoutSeconds
            )
        }
    }

    func testAudioSessionTimeoutPreferenceOwnsIOSRuntimePolicy() {
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.minimumSeconds, 0)
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.maximumSeconds, 300)
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.stepSeconds, 15)
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.countdownUpdateInterval, 1.0)
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.displayText(for: 90), "90s")
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.deactivationPlan(for: 0), .immediate)
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.deactivationPlan(for: -1), .immediate)
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.deactivationPlan(for: 90), .delayed(90))
        XCTAssertEqual(RomaAudioSessionTimeoutPreference.remainingTimeAfterCountdownTick(90), 89)
    }

    func testAudioSessionDeactivationPlanOwnsShellExecutionIntent() {
        assertAudioSessionDeactivationExecution(
            RomaAudioSessionDeactivationPlan.immediate.executionPlan,
            expectedEvents: ["deactivate"]
        )
        assertAudioSessionDeactivationExecution(
            RomaAudioSessionDeactivationPlan.delayed(90).executionPlan,
            expectedEvents: ["timer", "scheduled"]
        )
    }

    func testAudioSessionDeactivationExecutionPlanAppliesRuntimeState() {
        assertAudioSessionDeactivationExecution(
            RomaAudioSessionDeactivationPlan.immediate.executionPlan,
            expectedEvents: ["deactivate"]
        )
        assertAudioSessionDeactivationExecution(
            RomaAudioSessionDeactivationPlan.delayed(90).executionPlan,
            expectedEvents: ["timer", "scheduled"]
        )
    }

    private func assertAudioSessionDeactivationExecution(
        _ plan: RomaAudioSessionDeactivationExecutionPlan,
        expectedEvents: [String]
    ) {
        var events: [String] = []

        plan.applyRuntimeState(
            deactivateSession: { events.append("deactivate") },
            runCountdownTimer: { events.append("timer") },
            countdownTimerDidStart: { events.append("scheduled") }
        )

        XCTAssertEqual(events, expectedEvents)
    }

    func testVADPreferenceUsesSharedDefaultWhenMissing() {
        XCTAssertEqual(RomaVADPreference.userDefaultsKey, "IsVADEnabled")
        XCTAssertTrue(RomaVADPreference.defaultIsEnabled)

        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaVADPreference.isEnabled(from: defaults),
                RomaPreferenceDefault.isVADEnabled
            )
        }
    }

    func testVADPreferenceSavesAndClearsEnabledState() {
        withIsolatedDefaults { defaults in
            RomaVADPreference.saveIsEnabled(false, to: defaults)
            XCTAssertFalse(RomaVADPreference.isEnabled(from: defaults))

            RomaVADPreference.clear(from: defaults)
            XCTAssertEqual(
                RomaVADPreference.isEnabled(from: defaults),
                RomaPreferenceDefault.isVADEnabled
            )
        }
    }

    func testCustomLanguagePromptsKeyPreservesExistingMacOSStorageName() {
        XCTAssertEqual(RomaLocalWhisperPromptCatalog.customLanguagePromptsKey, "CustomLanguagePrompts")
    }

    func testPromptDraftStateOwnsMacOSEditSaveAndLanguageRefresh() {
        let draftState = RomaLocalWhisperPromptDraftState()

        XCTAssertEqual(draftState, RomaLocalWhisperPromptDraftState(text: "", isEditing: false))

        let editingState = draftState.editing(prompt: "Use sentence case.")
        XCTAssertEqual(
            editingState,
            RomaLocalWhisperPromptDraftState(text: "Use sentence case.", isEditing: true)
        )

        XCTAssertEqual(
            editingState.refreshingForSelectedLanguage(prompt: "Use French punctuation."),
            RomaLocalWhisperPromptDraftState(text: "Use French punctuation.", isEditing: true)
        )

        let savedState = editingState.saved()
        XCTAssertEqual(
            savedState,
            RomaLocalWhisperPromptDraftState(text: "Use sentence case.", isEditing: false)
        )

        XCTAssertEqual(
            savedState.refreshingForSelectedLanguage(prompt: "Use German punctuation."),
            savedState
        )
    }

    func testDefaultPromptsPreserveExistingMacOSLanguageSeeds() {
        XCTAssertEqual(
            RomaLocalWhisperPromptCatalog.defaultPrompt(for: "en"),
            "Hello, how are you doing? Nice to meet you."
        )
        XCTAssertEqual(
            RomaLocalWhisperPromptCatalog.defaultPrompt(for: "ja"),
            "こんにちは、お元気ですか？お会いできて嬉しいです。"
        )
        XCTAssertEqual(
            RomaLocalWhisperPromptCatalog.defaultPrompt(for: "he"),
            ",שלום, מה שלומך? נעים להכיר"
        )
    }

    func testPromptUsesCustomPromptWhenAvailable() {
        XCTAssertEqual(
            RomaLocalWhisperPromptCatalog.prompt(
                for: "en",
                customPrompts: ["en": "Spell Roma Just Talk exactly."]
            ),
            "Spell Roma Just Talk exactly."
        )
    }

    func testPromptFallsBackToDefaultWhenCustomPromptIsEmptyOrLanguageIsMissing() {
        XCTAssertEqual(
            RomaLocalWhisperPromptCatalog.prompt(for: "en", customPrompts: ["en": ""]),
            "Hello, how are you doing? Nice to meet you."
        )
        XCTAssertEqual(RomaLocalWhisperPromptCatalog.prompt(for: "xx"), "")
    }

    func testPromptForSelectedLanguageUsesSharedLanguageKeyAndFallbackLanguage() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Hello, how are you doing? Nice to meet you."
            )

            defaults.set("fr", forKey: RomaUserDefaultsKey.selectedTranscriptionLanguage)
            XCTAssertEqual(
                RomaLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Bonjour, comment allez-vous? Ravi de vous rencontrer."
            )
        }
    }

    func testStoredCustomPromptsRoundTrip() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults), [:])

            RomaLocalWhisperPromptCatalog.saveCustomPrompts(
                ["en": "Spell Roma Just Talk exactly."],
                to: defaults
            )

            XCTAssertEqual(
                RomaLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults),
                ["en": "Spell Roma Just Talk exactly."]
            )
        }
    }

    func testSaveCustomPromptUpdatesOneLanguageAndPreservesOthers() {
        withIsolatedDefaults { defaults in
            RomaLocalWhisperPromptCatalog.saveCustomPrompts(
                ["fr": "Use French punctuation."],
                to: defaults
            )

            RomaLocalWhisperPromptCatalog.saveCustomPrompt(
                "Spell Roma Just Talk exactly.",
                for: "en",
                to: defaults
            )

            XCTAssertEqual(
                RomaLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults),
                [
                    "en": "Spell Roma Just Talk exactly.",
                    "fr": "Use French punctuation."
                ]
            )
        }
    }

    func testPromptForSelectedLanguageUsesStoredCustomPromptsByDefault() {
        withIsolatedDefaults { defaults in
            defaults.set("en", forKey: RomaUserDefaultsKey.selectedTranscriptionLanguage)
            RomaLocalWhisperPromptCatalog.saveCustomPrompts(
                ["en": "Spell Roma Just Talk exactly."],
                to: defaults
            )

            XCTAssertEqual(
                RomaLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Spell Roma Just Talk exactly."
            )

            XCTAssertEqual(
                RomaLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults, customPrompts: [:]),
                "Hello, how are you doing? Nice to meet you."
            )
        }
    }

    func testTranscriptionPromptPreferenceUsesFallbackOnlyWhenLocalWhisperPromptIsMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                "Language prompt"
            )

            RomaTranscriptionPromptPreference.savePrompt("", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                ""
            )

            RomaTranscriptionPromptPreference.savePrompt(" spell Roma correctly ", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                " spell Roma correctly "
            )
        }
    }

    func testTranscriptionPromptPreferenceUsesSelectedLanguagePromptFallback() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("ja", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(from: defaults),
                RomaLocalWhisperPromptCatalog.defaultPrompt(for: "ja")
            )

            RomaTranscriptionPromptPreference.savePrompt(" custom prompt ", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(from: defaults),
                " custom prompt "
            )
        }
    }

    func testTranscriptionPromptPreferenceSavesSelectedLanguagePrompt() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("ja", to: defaults)

            let prompt = RomaTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage(
                from: defaults
            )

            XCTAssertEqual(prompt, RomaLocalWhisperPromptCatalog.defaultPrompt(for: "ja"))
            XCTAssertEqual(
                RomaTranscriptionPromptPreference.storedPrompt(from: defaults),
                RomaLocalWhisperPromptCatalog.defaultPrompt(for: "ja")
            )
        }
    }

    func testTranscriptionPromptPreferenceSavesCustomPromptForSelectedLanguage() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("en", to: defaults)
            RomaLocalWhisperPromptCatalog.saveCustomPrompt(
                "Spell Roma Just Talk exactly.",
                for: "en",
                to: defaults
            )

            let prompt = RomaTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage(
                from: defaults
            )

            XCTAssertEqual(prompt, "Spell Roma Just Talk exactly.")
            XCTAssertEqual(
                RomaTranscriptionPromptPreference.storedPrompt(from: defaults),
                "Spell Roma Just Talk exactly."
            )
        }
    }

    func testTranscriptionPromptPreferenceDropsBlankRequestPrompts() {
        XCTAssertNil(RomaTranscriptionPromptPreference.requestPrompt(nil))
        XCTAssertNil(RomaTranscriptionPromptPreference.requestPrompt(""))
        XCTAssertNil(RomaTranscriptionPromptPreference.requestPrompt(" \n\t "))
    }

    func testTranscriptionPromptPreferenceReadsRequestPromptFromSharedKey() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(RomaTranscriptionPromptPreference.requestPrompt(from: defaults))

            RomaTranscriptionPromptPreference.savePrompt(" keep product names ", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionPromptPreference.requestPrompt(from: defaults),
                " keep product names "
            )

            RomaTranscriptionPromptPreference.savePrompt(" \n ", to: defaults)
            XCTAssertNil(RomaTranscriptionPromptPreference.requestPrompt(from: defaults))
        }
    }

    func testTranscriptionPromptPreferenceRoundTripsStoredPrompt() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(RomaTranscriptionPromptPreference.storedPrompt(from: defaults))

            RomaTranscriptionPromptPreference.savePrompt("keep Roma spelling", to: defaults)

            XCTAssertEqual(
                RomaTranscriptionPromptPreference.storedPrompt(from: defaults),
                "keep Roma spelling"
            )
        }
    }

    func testTranscriptionLanguagePreferenceUsesAutoDetectFallbackWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                RomaLanguageCatalog.autoDetectCode
            )
            XCTAssertNil(RomaTranscriptionLanguagePreference.requestLanguage(from: defaults))
        }
    }

    func testTranscriptionLanguagePreferenceUsesMacOSFallbackWhenRequested() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedMacOSLanguage(from: defaults),
                RomaDefaultSettings.macOS.selectedTranscriptionLanguage
            )

            RomaTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedMacOSLanguage(from: defaults),
                "fr"
            )
        }
    }

    func testTranscriptionLanguagePreferenceSelectsCompatibleLanguageForSource() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "en-US"
            )

            RomaTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "en-US"
            )

            RomaTranscriptionLanguagePreference.saveSelectedLanguage("fr-FR", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "fr-FR"
            )
        }
    }

    func testTranscriptionLanguagePreferencePreservesRawSelectedLanguage() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                "auto"
            )
            XCTAssertNil(RomaTranscriptionLanguagePreference.requestLanguage(from: defaults))

            RomaTranscriptionLanguagePreference.saveSelectedLanguage(" fr ", to: defaults)
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                " fr "
            )
            XCTAssertEqual(RomaTranscriptionLanguagePreference.requestLanguage(from: defaults), "fr")
        }
    }

    func testTranscriptionLanguagePreferenceExposesStoredLanguageWhenPresent() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults))

            RomaTranscriptionLanguagePreference.saveSelectedLanguage("de", to: defaults)

            XCTAssertEqual(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults), "de")
        }
    }

    func testTranscriptionLanguagePreferenceClearsSelection() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            RomaTranscriptionLanguagePreference.clearSelectedLanguage(from: defaults)

            XCTAssertNil(RomaTranscriptionLanguagePreference.storedLanguage(from: defaults))
        }
    }

    func testCurrentTranscriptionModelPreferenceRoundTripsModelName() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(RomaCurrentTranscriptionModelPreference.modelName(from: defaults))

            RomaCurrentTranscriptionModelPreference.saveModelName(
                RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName,
                to: defaults
            )

            XCTAssertEqual(
                RomaCurrentTranscriptionModelPreference.modelName(from: defaults),
                RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
            )
        }
    }

    func testCurrentTranscriptionModelPreferenceClearsModelName() {
        withIsolatedDefaults { defaults in
            RomaCurrentTranscriptionModelPreference.saveModelName("nova-3", to: defaults)
            RomaCurrentTranscriptionModelPreference.clearModelName(from: defaults)

            XCTAssertNil(RomaCurrentTranscriptionModelPreference.modelName(from: defaults))
        }
    }

    func testCurrentTranscriptionModelPreferenceClearsLegacyModelName() {
        withIsolatedDefaults { defaults in
            defaults.set("legacy-base", forKey: RomaCurrentTranscriptionModelPreference.legacyModelNameKey)

            RomaCurrentTranscriptionModelPreference.clearModelName(from: defaults)

            XCTAssertNil(defaults.string(forKey: RomaCurrentTranscriptionModelPreference.legacyModelNameKey))
        }
    }

    func testCurrentTranscriptionModelLoadPlanNoOpsWhenNoModelIsSaved() {
        let plan = RomaCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: nil,
            candidateModelExists: false,
            isCandidateAvailableOnCurrentOS: false
        )
        var events: [String] = []

        plan.applyRuntimeState(
            clearStoredModelName: {
                events.append("clear")
            },
            restoreSavedModel: {
                events.append("restore")
            }
        )

        XCTAssertEqual(events, [])
    }

    func testCurrentTranscriptionModelLoadPlanNoOpsWhenSavedModelIsMissingFromRegistry() {
        let plan = RomaCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: "missing-model",
            candidateModelExists: false,
            isCandidateAvailableOnCurrentOS: false
        )
        var events: [String] = []

        plan.applyRuntimeState(
            clearStoredModelName: {
                events.append("clear")
            },
            restoreSavedModel: {
                events.append("restore")
            }
        )

        XCTAssertEqual(events, [])
    }

    func testCurrentTranscriptionModelLoadPlanRestoresAvailableSavedModel() {
        let plan = RomaCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: "nova-3",
            candidateModelExists: true,
            isCandidateAvailableOnCurrentOS: true
        )
        var events: [String] = []

        plan.applyRuntimeState(
            clearStoredModelName: {
                events.append("clear")
            },
            restoreSavedModel: {
                events.append("restore")
            }
        )

        XCTAssertEqual(events, ["restore"])
    }

    func testCurrentTranscriptionModelLoadPlanClearsUnavailableSavedModel() {
        let plan = RomaCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: "apple-speech",
            candidateModelExists: true,
            isCandidateAvailableOnCurrentOS: false
        )
        var events: [String] = []

        plan.applyRuntimeState(
            clearStoredModelName: {
                events.append("clear")
            },
            restoreSavedModel: {
                events.append("restore")
            }
        )

        XCTAssertEqual(events, ["clear"])
    }

    func testAIEnhancementProviderPreferenceUsesDefaultWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(RomaAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults))
            XCTAssertEqual(RomaAIEnhancementProviderPreference.defaultSelectedProvider, .gemini)
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedProvider(from: defaults),
                .gemini
            )
        }
    }

    func testAIEnhancementProviderPreferenceRepairsLegacyStoredProvider() {
        withIsolatedDefaults { defaults in
            defaults.set("GROQ", forKey: RomaUserDefaultsKey.selectedAIProvider)

            XCTAssertEqual(RomaAIEnhancementProviderPreference.selectedProvider(from: defaults), .groq)
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                RomaAIEnhancementProviderKind.groq.rawValue
            )
        }
    }

    func testAIEnhancementProviderPreferenceRoundTripsRawProvider() {
        withIsolatedDefaults { defaults in
            RomaAIEnhancementProviderPreference.saveSelectedProviderRawValue("OpenRouter", to: defaults)

            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                "OpenRouter"
            )
            XCTAssertEqual(RomaAIEnhancementProviderPreference.selectedProvider(from: defaults), .openRouter)
        }
    }

    func testAIEnhancementProviderPreferenceSavesEnumProvider() {
        withIsolatedDefaults { defaults in
            RomaAIEnhancementProviderPreference.saveSelectedProvider(.openRouter, to: defaults)

            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                RomaAIEnhancementProviderKind.openRouter.rawValue
            )
            XCTAssertEqual(RomaAIEnhancementProviderPreference.selectedProvider(from: defaults), .openRouter)
        }
    }

    func testAIEnhancementProviderPreferenceAppliesProviderSelectionPlan() {
        withIsolatedDefaults { defaults in
            let appliedProvider = RomaAIEnhancementProviderPreference.applyProviderSelectionPlan(
                RomaAIEnhancementProviderSelectionPlan.selecting(.openRouter),
                to: defaults
            )

            XCTAssertEqual(appliedProvider, .openRouter)
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                RomaAIEnhancementProviderKind.openRouter.rawValue
            )
            XCTAssertEqual(RomaAIEnhancementProviderPreference.selectedProvider(from: defaults), .openRouter)
        }
    }

    func testAIEnhancementProviderPreferenceRoundTripsSelectedModel() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(
                RomaAIEnhancementProviderPreference.selectedModel(for: "Groq", from: defaults)
            )

            RomaAIEnhancementProviderPreference.saveSelectedModel(
                "llama-3.3-70b-versatile",
                for: "Groq",
                to: defaults
            )

            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModel(for: "Groq", from: defaults),
                "llama-3.3-70b-versatile"
            )
        }
    }

    func testAIEnhancementProviderPreferenceAppliesModelSelectionPlan() throws {
        let plan = try XCTUnwrap(
            RomaAIEnhancementModelSelectionPlan.selecting(
                "openai/gpt-oss-120b",
                provider: .groq,
                selectedModels: [:]
            )
        )

        withIsolatedDefaults { defaults in
            let appliedModel = RomaAIEnhancementProviderPreference.applyModelSelectionPlan(
                plan,
                to: defaults
            )

            XCTAssertEqual(appliedModel, "openai/gpt-oss-120b")
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModel(for: "Groq", from: defaults),
                "openai/gpt-oss-120b"
            )
        }
    }

    func testAIEnhancementProviderPreferenceAppliesModelRefreshPlan() {
        withIsolatedDefaults { defaults in
            let appliedModel = RomaAIEnhancementProviderPreference.applyModelRefreshPlan(
                RomaAIEnhancementModelRefreshPlan(
                    refreshedModelNames: ["anthropic/claude-3.5-sonnet"],
                    selectedModelToSave: "anthropic/claude-3.5-sonnet"
                ),
                for: .openRouter,
                to: defaults
            )

            XCTAssertEqual(appliedModel, "anthropic/claude-3.5-sonnet")
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults),
                "anthropic/claude-3.5-sonnet"
            )

            let ignoredModel = RomaAIEnhancementProviderPreference.applyModelRefreshPlan(
                RomaAIEnhancementModelRefreshPlan(
                    refreshedModelNames: [],
                    selectedModelToSave: nil
                ),
                for: .openRouter,
                to: defaults
            )

            XCTAssertNil(ignoredModel)
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults),
                "anthropic/claude-3.5-sonnet"
            )
        }
    }

    func testAIEnhancementProviderPreferenceLoadsSelectedModelsByProvider() {
        withIsolatedDefaults { defaults in
            RomaAIEnhancementProviderPreference.saveSelectedModel(
                "llama-3.3-70b-versatile",
                for: .groq,
                to: defaults
            )
            RomaAIEnhancementProviderPreference.saveSelectedModel(
                "openai/gpt-4o",
                for: .openAI,
                to: defaults
            )
            defaults.set("", forKey: RomaUserDefaultsKey.selectedAIProviderModel("OpenRouter"))

            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModels(
                    for: [.groq, .openRouter, .openAI],
                    from: defaults
                ),
                [
                    .groq: "llama-3.3-70b-versatile",
                    .openAI: "openai/gpt-4o"
                ]
            )
        }
    }

    func testAIEnhancementProviderPreferenceBuildsDiagnosticDescriptions() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(RomaAIEnhancementPreference.isEnabled(from: defaults))
            XCTAssertEqual(
                RomaAIEnhancementPreference.statusDiagnosticDescription(from: defaults),
                "Disabled"
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedProviderDiagnosticDescription(from: defaults),
                "None selected"
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "None selected"
            )

            RomaAIEnhancementPreference.saveIsEnabled(true, to: defaults)
            RomaAIEnhancementProviderPreference.saveSelectedProviderRawValue("GROQ", to: defaults)

            XCTAssertTrue(RomaAIEnhancementPreference.isEnabled(from: defaults))
            XCTAssertEqual(
                RomaAIEnhancementPreference.statusDiagnosticDescription(from: defaults),
                "Enabled"
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedProviderDiagnosticDescription(from: defaults),
                "GROQ"
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "Default (GROQ)"
            )

            RomaAIEnhancementProviderPreference.saveSelectedModel(
                "llama-3.3-70b-versatile",
                for: "GROQ",
                to: defaults
            )

            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "llama-3.3-70b-versatile"
            )
        }
    }

    func testAIEnhancementContextPreferenceRoundTripsAndClearsToggles() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(RomaAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(RomaAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))

            RomaAIEnhancementContextPreference.saveUseClipboardContext(true, to: defaults)
            RomaAIEnhancementContextPreference.saveUseScreenCaptureContext(true, to: defaults)

            XCTAssertTrue(RomaAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertTrue(RomaAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))

            RomaAIEnhancementContextPreference.clear(from: defaults)

            XCTAssertFalse(RomaAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(RomaAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))
        }
    }

    func testDynamicAIProviderPreferenceReadsOllamaFallbacksAndSavedValues() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.defaultOllamaBaseURL,
                RomaPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.defaultOllamaRuntimeSelectedModel,
                RomaAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback
            )
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                RomaPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaRuntimeSelectedModel(from: defaults),
                RomaAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback
            )
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )

            RomaDynamicAIProviderPreference.saveOllamaBaseURL("http://example.local:11434", to: defaults)
            RomaDynamicAIProviderPreference.saveOllamaSelectedModel("mistral", to: defaults)

            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                "http://example.local:11434"
            )
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "mistral"
            )
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaRuntimeSelectedModel(from: defaults),
                "mistral"
            )
        }
    }

    func testDynamicAIProviderPreferencePreservesCallerSpecificOllamaModelFallbacks() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "mistral"),
                "mistral"
            )
        }
    }

    func testDynamicAIProviderPreferenceAppliesOllamaModelRefreshPlan() {
        withIsolatedDefaults { defaults in
            let appliedModel = RomaDynamicAIProviderPreference.applyOllamaModelRefreshPlan(
                RomaAIEnhancementModelRefreshPlan(
                    refreshedModelNames: ["llama3", "mistral"],
                    selectedModelToSave: "llama3"
                ),
                to: defaults
            )

            XCTAssertEqual(appliedModel, "llama3")
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "mistral"),
                "llama3"
            )

            let ignoredModel = RomaDynamicAIProviderPreference.applyOllamaModelRefreshPlan(
                RomaAIEnhancementModelRefreshPlan(
                    refreshedModelNames: ["mistral"],
                    selectedModelToSave: nil
                ),
                to: defaults
            )

            XCTAssertNil(ignoredModel)
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "mistral"),
                "llama3"
            )
        }
    }

    func testDynamicAIProviderPreferenceRoundTripsCustomProviderSettings() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaDynamicAIProviderPreference.customProviderBaseURL(from: defaults), "")
            XCTAssertEqual(RomaDynamicAIProviderPreference.customProviderModel(from: defaults), "")

            RomaDynamicAIProviderPreference.saveCustomProviderBaseURL("https://api.example.com/v1", to: defaults)
            RomaDynamicAIProviderPreference.saveCustomProviderModel("custom-model", to: defaults)

            XCTAssertEqual(
                RomaDynamicAIProviderPreference.customProviderBaseURL(from: defaults),
                "https://api.example.com/v1"
            )
            XCTAssertEqual(RomaDynamicAIProviderPreference.customProviderModel(from: defaults), "custom-model")
        }
    }

    func testDynamicAIProviderPreferenceRoundTripsOpenRouterModels() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaDynamicAIProviderPreference.openRouterModels(from: defaults), [])

            RomaDynamicAIProviderPreference.saveOpenRouterModels(["openai/gpt-oss-120b", "z-ai/glm-4.5"], to: defaults)

            XCTAssertEqual(
                RomaDynamicAIProviderPreference.openRouterModels(from: defaults),
                ["openai/gpt-oss-120b", "z-ai/glm-4.5"]
            )
        }
    }

    func testDynamicAIProviderPreferenceAppliesOpenRouterModelRefreshPlan() {
        withIsolatedDefaults { defaults in
            let appliedModel = RomaDynamicAIProviderPreference.applyOpenRouterModelRefreshPlan(
                RomaAIEnhancementModelRefreshPlan(
                    refreshedModelNames: ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"],
                    selectedModelToSave: "anthropic/claude-3.5-sonnet"
                ),
                to: defaults
            )

            XCTAssertEqual(appliedModel, "anthropic/claude-3.5-sonnet")
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.openRouterModels(from: defaults),
                ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"]
            )
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults),
                "anthropic/claude-3.5-sonnet"
            )

            let ignoredModel = RomaDynamicAIProviderPreference.applyOpenRouterModelRefreshPlan(
                .failed,
                to: defaults
            )

            XCTAssertNil(ignoredModel)
            XCTAssertEqual(RomaDynamicAIProviderPreference.openRouterModels(from: defaults), [])
            XCTAssertEqual(
                RomaAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults),
                "anthropic/claude-3.5-sonnet"
            )
        }
    }

    func testFillerWordPreferenceUsesDefaultWordsWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaFillerWordPreference.words(from: defaults),
                RomaFillerWords.defaultWords
            )
        }
    }

    func testFillerWordPreferenceRoundTripsSavedWords() {
        withIsolatedDefaults { defaults in
            RomaFillerWordPreference.saveWords(["um", "like"], to: defaults)

            XCTAssertEqual(
                RomaFillerWordPreference.words(from: defaults),
                ["um", "like"]
            )
        }
    }

    func testFillerWordPreferenceClearsSavedWords() {
        withIsolatedDefaults { defaults in
            RomaFillerWordPreference.saveWords(["um", "like"], to: defaults)
            RomaFillerWordPreference.clearWords(from: defaults)

            XCTAssertEqual(
                RomaFillerWordPreference.words(from: defaults),
                RomaFillerWords.defaultWords
            )
        }
    }

    func testWordReplacementPreferenceRoundTripsSharedRules() {
        withIsolatedDefaults { defaults in
            let rules = [
                RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ]

            RomaWordReplacementPreference.saveRules(rules, to: defaults)

            XCTAssertEqual(RomaWordReplacementPreference.rules(from: defaults), rules)

            RomaWordReplacementPreference.clearRules(from: defaults)
            XCTAssertEqual(RomaWordReplacementPreference.rules(from: defaults), [])
        }
    }

    func testWordReplacementPreferenceIgnoresInvalidStoredData() {
        withIsolatedDefaults { defaults in
            defaults.set(Data([0]), forKey: RomaUserDefaultsKey.wordReplacements)

            XCTAssertEqual(RomaWordReplacementPreference.rules(from: defaults), [])
        }
    }

    func testCustomVocabularyPreferenceNormalizesTerms() {
        withIsolatedDefaults { defaults in
            RomaCustomVocabularyPreference.saveTerms([" Roma ", "Felix", "roma", ""], to: defaults)

            XCTAssertEqual(RomaCustomVocabularyPreference.terms(from: defaults), ["Roma", "Felix"])

            RomaCustomVocabularyPreference.clearTerms(from: defaults)
            XCTAssertEqual(RomaCustomVocabularyPreference.terms(from: defaults), [])
        }
    }

    func testAIEnhancementRequestPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(RomaPreferenceDefault.enhancementTimeoutSeconds)
            )
            XCTAssertEqual(
                RomaAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults),
                RomaPreferenceDefault.enhancementRetryOnTimeout
            )
        }
    }

    func testAIEnhancementRequestPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            defaults.set(15, forKey: RomaUserDefaultsKey.enhancementTimeoutSeconds)
            defaults.set(false, forKey: RomaUserDefaultsKey.enhancementRetryOnTimeout)

            XCTAssertEqual(RomaAIEnhancementRequestPreference.timeoutSeconds(from: defaults), 15)
            XCTAssertFalse(RomaAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults))
        }
    }

    func testAIEnhancementRequestPreferenceFallsBackForNonPositiveTimeout() {
        withIsolatedDefaults { defaults in
            defaults.set(0, forKey: RomaUserDefaultsKey.enhancementTimeoutSeconds)

            XCTAssertEqual(
                RomaAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(RomaPreferenceDefault.enhancementTimeoutSeconds)
            )
        }
    }

    func testTranscriptionAutoCleanupPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            let configuration = RomaTranscriptionAutoCleanupPreference.current(from: defaults)

            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionMinutes, RomaPreferenceDefault.transcriptionRetentionMinutes)
            XCTAssertEqual(configuration.effectiveRetentionMinutes, RomaPreferenceDefault.transcriptionRetentionMinutes)
            XCTAssertFalse(configuration.shouldDeleteCompletedTranscriptionImmediately)
        }
    }

    func testTranscriptionAutoCleanupPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionAutoCleanupPreference.saveIsEnabled(true, to: defaults)
            RomaTranscriptionAutoCleanupPreference.saveRetentionMinutes(15, to: defaults)

            let configuration = RomaTranscriptionAutoCleanupPreference.current(from: defaults)

            XCTAssertTrue(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionMinutes, 15)
            XCTAssertEqual(configuration.effectiveRetentionMinutes, 15)
        }
    }

    func testTranscriptionAutoCleanupConfigurationClampsNegativeRetentionForCutoff() {
        let configuration = RomaTranscriptionAutoCleanupConfiguration(
            isEnabled: true,
            retentionMinutes: -5
        )
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(configuration.effectiveRetentionMinutes, 0)
        XCTAssertTrue(configuration.shouldDeleteCompletedTranscriptionImmediately)
        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), referenceDate)
    }

    func testTranscriptionAutoCleanupConfigurationBuildsCutoffDate() {
        let configuration = RomaTranscriptionAutoCleanupConfiguration(
            isEnabled: true,
            retentionMinutes: 30
        )
        let referenceDate = Date(timeIntervalSince1970: 3_600)

        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), Date(timeIntervalSince1970: 1_800))
    }

    func testTranscriptionAutoCleanupConfigurationAppliesCompletedTranscriptionRuntimeState() {
        XCTAssertEqual(
            transcriptionAutoCleanupCompletionEvents(
                isEnabled: false,
                retentionMinutes: 0
            ),
            ["ignore"]
        )
        XCTAssertEqual(
            transcriptionAutoCleanupCompletionEvents(
                isEnabled: true,
                retentionMinutes: 30
            ),
            ["sweep"]
        )
        XCTAssertEqual(
            transcriptionAutoCleanupCompletionEvents(
                isEnabled: true,
                retentionMinutes: 0
            ),
            ["delete"]
        )
    }

    private func transcriptionAutoCleanupCompletionEvents(
        isEnabled: Bool,
        retentionMinutes: Int
    ) -> [String] {
        var events: [String] = []
        RomaTranscriptionAutoCleanupConfiguration(
            isEnabled: isEnabled,
            retentionMinutes: retentionMinutes
        ).applyCompletionRuntimeState(
            ignore: {
                events.append("ignore")
            },
            sweepOldTranscriptions: {
                events.append("sweep")
            },
            deleteCompletedTranscription: {
                events.append("delete")
            }
        )
        return events
    }

    func testTranscriptionAutoCleanupBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            RomaTranscriptionAutoCleanupPreference.backupPreferences(
                from: RomaTranscriptionAutoCleanupConfiguration(
                    isEnabled: true,
                    retentionMinutes: 15
                )
            ),
            RomaTranscriptionAutoCleanupBackupPreferences(
                isEnabled: true,
                retentionMinutes: 15
            )
        )
    }

    func testTranscriptionAutoCleanupBackupImportPlanPreservesOptionalFields() {
        XCTAssertEqual(
            RomaTranscriptionAutoCleanupPreference.backupImportPlan(
                from: RomaTranscriptionAutoCleanupBackupPreferences(
                    isEnabled: false,
                    retentionMinutes: 0
                )
            ),
            RomaTranscriptionAutoCleanupBackupImportPlan(
                isEnabled: false,
                retentionMinutes: 0
            )
        )

        XCTAssertEqual(
            RomaTranscriptionAutoCleanupPreference.backupImportPlan(
                from: RomaTranscriptionAutoCleanupBackupPreferences(
                    isEnabled: nil,
                    retentionMinutes: nil
                )
            ),
            RomaTranscriptionAutoCleanupBackupImportPlan(
                isEnabled: nil,
                retentionMinutes: nil
            )
        )
    }

    func testAudioCleanupPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            let configuration = RomaAudioCleanupPreference.current(from: defaults)

            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionDays, RomaPreferenceDefault.audioRetentionDays)
            XCTAssertEqual(configuration.effectiveRetentionDays, RomaPreferenceDefault.audioRetentionDays)
        }
    }

    func testAudioCleanupPreferencePreservesDailyCleanupCheckInterval() {
        XCTAssertEqual(RomaAudioCleanupPreference.cleanupCheckInterval, 86_400)
    }

    func testAudioCleanupPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            RomaAudioCleanupPreference.saveIsEnabled(true, to: defaults)
            RomaAudioCleanupPreference.saveRetentionDays(14, to: defaults)

            let configuration = RomaAudioCleanupPreference.current(from: defaults)

            XCTAssertTrue(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionDays, 14)
            XCTAssertEqual(configuration.effectiveRetentionDays, 14)
        }
    }

    func testAudioCleanupConfigurationBuildsDayCutoffDate() {
        let configuration = RomaAudioCleanupConfiguration(isEnabled: true, retentionDays: 7)
        let referenceDate = Date(timeIntervalSince1970: 7 * 86_400)

        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), Date(timeIntervalSince1970: 0))
    }

    func testAudioCleanupConfigurationClampsNegativeRetentionForCutoff() {
        let configuration = RomaAudioCleanupConfiguration(isEnabled: true, retentionDays: -1)
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(configuration.effectiveRetentionDays, 0)
        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), referenceDate)
    }

    func testAudioCleanupBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            RomaAudioCleanupPreference.backupPreferences(
                from: RomaAudioCleanupConfiguration(
                    isEnabled: true,
                    retentionDays: 14
                )
            ),
            RomaAudioCleanupBackupPreferences(
                isEnabled: true,
                retentionDays: 14
            )
        )
    }

    func testAudioCleanupBackupImportPlanPreservesOptionalFields() {
        XCTAssertEqual(
            RomaAudioCleanupPreference.backupImportPlan(
                from: RomaAudioCleanupBackupPreferences(
                    isEnabled: false,
                    retentionDays: 0
                )
            ),
            RomaAudioCleanupBackupImportPlan(
                isEnabled: false,
                retentionDays: 0
            )
        )

        XCTAssertEqual(
            RomaAudioCleanupPreference.backupImportPlan(
                from: RomaAudioCleanupBackupPreferences(
                    isEnabled: nil,
                    retentionDays: nil
                )
            ),
            RomaAudioCleanupBackupImportPlan(
                isEnabled: nil,
                retentionDays: nil
            )
        )
    }

    func testModelRuntimePreferenceRegisteredDefaultsPreserveMacOSPolicy() {
        XCTAssertEqual(RomaModelRuntimePreference.userDefaultsKey, "PrewarmModelOnWake")
        XCTAssertTrue(RomaModelRuntimePreference.defaultShouldPrewarmModelOnWake)
        XCTAssertEqual(RomaModelRuntimePreference.prewarmScheduleDelay, .seconds(3))
        XCTAssertEqual(
            RomaModelRuntimePreference.registeredDefaults[RomaModelRuntimePreference.userDefaultsKey] as? Bool,
            true
        )
    }

    func testModelRuntimePreferenceReadsSavesAndClearsPrewarmFlag() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(RomaModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))

            RomaModelRuntimePreference.saveShouldPrewarmModelOnWake(false, to: defaults)
            XCTAssertFalse(RomaModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))

            RomaModelRuntimePreference.clear(from: defaults)
            XCTAssertTrue(RomaModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))
        }
    }

    func testRecorderPreviewPreferenceRegisteredDefaultsPreserveMacOSPolicy() {
        XCTAssertEqual(RomaRecorderPreviewPreference.userDefaultsKey, "showLiveTextPreview")
        XCTAssertFalse(RomaRecorderPreviewPreference.defaultIsLiveTextPreviewEnabled)
        XCTAssertEqual(
            RomaRecorderPreviewPreference.registeredDefaults[RomaRecorderPreviewPreference.userDefaultsKey] as? Bool,
            false
        )
    }

    func testRecorderPreviewPreferenceReadsSavesAndClearsPreviewFlag() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(RomaRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))

            RomaRecorderPreviewPreference.saveIsLiveTextPreviewEnabled(true, to: defaults)
            XCTAssertTrue(RomaRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))

            RomaRecorderPreviewPreference.clear(from: defaults)
            XCTAssertFalse(RomaRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))
        }
    }

    func testRecordingShortcutSelectionPreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(RomaRecordingShortcutSelection.none.rawValue, "none")
        XCTAssertEqual(RomaRecordingShortcutSelection.none.displayName, "None")
        XCTAssertEqual(RomaRecordingShortcutSelection.custom.rawValue, "custom")
        XCTAssertEqual(RomaRecordingShortcutSelection.custom.displayName, "Custom")
    }

    func testRecordingShortcutModePreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(RomaRecordingShortcutMode.special.rawValue, "special")
        XCTAssertEqual(RomaRecordingShortcutMode.special.displayName, "Special")
        XCTAssertEqual(RomaRecordingShortcutMode.toggle.rawValue, "toggle")
        XCTAssertEqual(RomaRecordingShortcutMode.toggle.displayName, "Toggle")
        XCTAssertEqual(RomaRecordingShortcutMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(RomaRecordingShortcutMode.pushToTalk.displayName, "Push to Talk")
        XCTAssertEqual(RomaRecordingShortcutMode.hybrid.rawValue, "hybrid")
        XCTAssertEqual(RomaRecordingShortcutMode.hybrid.displayName, "Hybrid")
    }

    func testRecordingShortcutModePreservesMonitorPolicy() {
        XCTAssertTrue(RomaRecordingShortcutMode.special.tracksKeyUpEvidence)
        XCTAssertFalse(RomaRecordingShortcutMode.special.allowsShortcutInterruption)

        for mode in [
            RomaRecordingShortcutMode.toggle,
            .pushToTalk,
            .hybrid
        ] {
            XCTAssertFalse(mode.tracksKeyUpEvidence)
            XCTAssertTrue(mode.allowsShortcutInterruption)
        }
    }

    func testReliablePressContextAllowsSpecialShortcutCommit() {
        XCTAssertFalse(
            RomaSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: RomaShortcutPressContext()
            )
        )
    }

    func testTypingEvidenceDiscardsSpecialShortcut() {
        XCTAssertTrue(
            RomaSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: RomaShortcutPressContext(didPressOtherKeyDuringPress: true)
            )
        )
        XCTAssertTrue(
            RomaSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: RomaShortcutPressContext(didReleaseOtherKeyDuringPress: true)
            )
        )
    }

    func testUnreliableKeyEvidenceFailsClosed() {
        XCTAssertTrue(
            RomaSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: RomaShortcutPressContext(hasReliableKeyEvidence: false)
            )
        )
    }

    func testShortcutInterruptionPolicyPreservesMacOSWindow() {
        XCTAssertEqual(RomaShortcutInterruptionPolicy.interruptionWindow, 1.0)
        XCTAssertTrue(RomaShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 10.5))
        XCTAssertTrue(RomaShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 11.0))
        XCTAssertFalse(RomaShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 11.1))
    }

    func testRecordingShortcutTimingPolicyPreservesMacOSThresholds() {
        XCTAssertEqual(RomaRecordingShortcutTimingPolicy.pressCooldown, 0.08)
        XCTAssertEqual(RomaRecordingShortcutTimingPolicy.hybridPushToTalkThreshold, 0.5)
    }

    func testRecordingShortcutTimingPolicyDetectsPressCooldown() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertFalse(
            RomaRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: nil,
                now: now
            )
        )
        XCTAssertTrue(
            RomaRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: now.addingTimeInterval(-0.079),
                now: now
            )
        )
        XCTAssertFalse(
            RomaRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: now.addingTimeInterval(-0.08),
                now: now
            )
        )
    }

    func testRecordingShortcutTimingPolicyHybridStopRequiresThresholdAndRecordingState() {
        XCTAssertFalse(
            RomaRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.499,
                recordingState: .recording
            )
        )
        XCTAssertTrue(
            RomaRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.5,
                recordingState: .recording
            )
        )
        XCTAssertFalse(
            RomaRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.5,
                recordingState: .idle
            )
        )
    }

    func testRecordingShortcutTimingPolicyConvertsSleepDelaySafely() {
        XCTAssertEqual(
            RomaRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: 0.25),
            250_000_000
        )
        XCTAssertEqual(
            RomaRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: -1),
            0
        )
        XCTAssertEqual(
            RomaRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: .infinity),
            0
        )
        XCTAssertEqual(
            RomaRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: .greatestFiniteMagnitude),
            UInt64.max
        )
    }

    func testShortPressSchedulesEmptyTapFallbackOnlyBelowThreshold() {
        XCTAssertTrue(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.319)
        )
        XCTAssertFalse(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.32)
        )
        XCTAssertFalse(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.5)
        )
    }

    func testConsumeFallbackRequiresFreshCompletedEmptyTranscription() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = createdAt.addingTimeInterval(29.9)

        XCTAssertTrue(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: now,
                transcriptionStatus: .completed,
                rawText: " \n ",
                enhancedText: nil
            )
        )
        XCTAssertTrue(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: now,
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: "  "
            )
        )
    }

    func testConsumeFallbackRejectsStalePendingOrNonEmptyTranscriptions() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertFalse(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt.addingTimeInterval(30.1),
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .pending,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: nil,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .completed,
                rawText: "hello",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            RomaSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: "hello"
            )
        )
    }

    func testRecordingShortcutPreferencePreservesMacOSSettingsPresentation() {
        let presentation = RomaRecordingShortcutPreference.macOSSettingsPresentation

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

    func testRecordingShortcutPreferenceBuildsMiddleClickActivationDelayFormatter() {
        let formatter = RomaRecordingShortcutPreference.middleClickActivationDelayFormatter()

        XCTAssertEqual(formatter.minimum, NSNumber(value: RomaRecordingShortcutPreference.minimumMiddleClickActivationDelay))
        XCTAssertNil(formatter.maximum)
    }

    func testRecordingShortcutPreferencePreservesMacOSRecorderPresentation() {
        let presentation = RomaRecordingShortcutPreference.macOSRecorderPresentation

        XCTAssertEqual(presentation.recordingPlaceholderText, "Press shortcut")
        XCTAssertEqual(presentation.idleAccessibilityLabel, "Record shortcut")
        XCTAssertEqual(presentation.idleButtonText, "Record")
    }

    func testRecordingShortcutPreferencePreservesMacOSNotificationNames() {
        XCTAssertEqual(
            RomaRecordingShortcutPreference.shortcutDidChangeNotificationName.rawValue,
            "ShortcutStoreShortcutDidChange"
        )
        XCTAssertEqual(
            RomaRecordingShortcutPreference.shortcutRecordingDidStartNotificationName.rawValue,
            "ShortcutRecorderRecordingDidStart"
        )
    }

    func testRecordingShortcutPreferenceKeysDefaultsAndRegisteredDefaults() {
        XCTAssertEqual(
            RomaRecordingShortcutPreference.selectionKey(for: .primary),
            RomaUserDefaultsKey.primaryRecordingShortcut
        )
        XCTAssertEqual(
            RomaRecordingShortcutPreference.selectionKey(for: .secondary),
            RomaUserDefaultsKey.secondaryRecordingShortcut
        )
        XCTAssertEqual(
            RomaRecordingShortcutPreference.modeKey(for: .primary),
            RomaUserDefaultsKey.primaryRecordingShortcutMode
        )
        XCTAssertEqual(
            RomaRecordingShortcutPreference.modeKey(for: .secondary),
            RomaUserDefaultsKey.secondaryRecordingShortcutMode
        )
        XCTAssertEqual(
            RomaUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap,
            "specialShortcutPasteLastTranscriptOnEmptyTap"
        )
        XCTAssertEqual(RomaRecordingShortcutPreference.defaultSelection(for: .primary), .custom)
        XCTAssertEqual(RomaRecordingShortcutPreference.defaultSelection(for: .secondary), .none)
        XCTAssertEqual(RomaRecordingShortcutPreference.defaultMode(for: .primary), .special)
        XCTAssertEqual(RomaRecordingShortcutPreference.defaultMode(for: .secondary), .hybrid)
        XCTAssertEqual(RomaRecordingShortcutPreference.minimumMiddleClickActivationDelay, 0)
        XCTAssertEqual(
            RomaRecordingShortcutPreference.registeredDefaults[RomaUserDefaultsKey.isMiddleClickToggleEnabled] as? Bool,
            RomaPreferenceDefault.isMiddleClickToggleEnabled
        )
        XCTAssertEqual(
            RomaRecordingShortcutPreference.registeredDefaults[RomaUserDefaultsKey.middleClickActivationDelay] as? Int,
            RomaPreferenceDefault.middleClickActivationDelay
        )
        XCTAssertEqual(
            RomaRecordingShortcutPreference.registeredDefaults[RomaUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap] as? Bool,
            RomaPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
        )
    }

    func testShortcutActionIdentifierPreservesStorageAndLegacyKeys() {
        let powerModeId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.storageName, "primaryRecording")
        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.shortcutStorageKey, "Shortcut_primaryRecording")
        XCTAssertTrue(RomaShortcutActionIdentifier.primaryRecording.isStoredShortcut)
        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.recordingShortcutSlot, .primary)
        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.selectionKey, RomaUserDefaultsKey.primaryRecordingShortcut)
        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.legacySelectionKey, "selectedHotkey1")
        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.modeKey, RomaUserDefaultsKey.primaryRecordingShortcutMode)
        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.legacyModeKey, "hotkeyMode1")
        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.legacyCustomRecordingShortcutKey, "CustomRecordingShortcut_primary")
        XCTAssertEqual(RomaShortcutActionIdentifier.primaryRecording.legacyKeyboardShortcutStorageKey, "KeyboardShortcuts_toggleMiniRecorder")

        XCTAssertEqual(RomaShortcutActionIdentifier.secondaryRecording.legacySelectionKey, "selectedHotkey2")
        XCTAssertEqual(RomaShortcutActionIdentifier.secondaryRecording.legacyModeKey, "hotkeyMode2")
        XCTAssertEqual(RomaShortcutActionIdentifier.secondaryRecording.legacyCustomRecordingShortcutKey, "CustomRecordingShortcut_secondary")
        XCTAssertEqual(RomaShortcutActionIdentifier.secondaryRecording.legacyKeyboardShortcutStorageKey, "KeyboardShortcuts_toggleMiniRecorder2")

        let powerMode = RomaShortcutActionIdentifier.powerMode(powerModeId)
        XCTAssertEqual(powerMode.storageName, "powerMode_11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(powerMode.shortcutStorageKey, "Shortcut_powerMode_11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(powerMode.legacyKeyboardShortcutStorageKey, "KeyboardShortcuts_powerMode_11111111-2222-3333-4444-555555555555")

        XCTAssertFalse(RomaShortcutActionIdentifier.miniRecorderPrompt(2).isStoredShortcut)
        XCTAssertNil(RomaShortcutActionIdentifier.miniRecorderPrompt(2).legacyKeyboardShortcutStorageKey)
        XCTAssertEqual(
            RomaShortcutActionIdentifier.legacyKeyboardShortcutActions,
            [
                .primaryRecording,
                .secondaryRecording,
                .pasteLastTranscription,
                .pasteLastEnhancement,
                .retryLastTranscription,
                .cancelRecorder,
                .openHistoryWindow,
                .quickAddToDictionary,
                .toggleEnhancement
            ]
        )
        XCTAssertEqual(RomaShortcutActionIdentifier.legacyCustomRecordingShortcutActions, [.primaryRecording, .secondaryRecording])
    }

    func testShortcutActionPresentationPreservesMacOSDisplayNames() {
        let powerModeId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .primaryRecording),
            "Primary Shortcut"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .secondaryRecording),
            "Secondary Shortcut"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .pasteLastTranscription),
            "Paste Last Transcription"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .pasteLastEnhancement),
            "Paste Last Enhanced Transcription"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .retryLastTranscription),
            "Retry Last Transcription"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .cancelRecorder),
            "Cancel Recording"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .openHistoryWindow),
            "Open History Window"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .quickAddToDictionary),
            "Quick Add to Dictionary"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .toggleEnhancement),
            "Toggle Enhancement"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .powerMode(powerModeId)),
            "Power Mode"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .powerMode(powerModeId), powerModeName: "Writing"),
            "Writing Power Mode"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .miniRecorderEscape),
            "Mini Recorder Cancel"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .miniRecorderPrompt(0)),
            "Select Prompt 1"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .miniRecorderPrompt(9)),
            "Select Prompt 10"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .miniRecorderPowerMode(0)),
            "Select Power Mode 1"
        )
        XCTAssertEqual(
            RomaShortcutActionPresentation.displayName(for: .miniRecorderPowerMode(9)),
            "Select Power Mode 10"
        )
    }

    func testMacOSShortcutNotificationPresentationPreservesShellCopy() {
        XCTAssertEqual(
            RomaMacOSShortcutNotificationPresentation.inputMonitoringPermissionRequired,
            RomaMacOSShortcutNotificationPresentation(
                title: "Enable Input Monitoring for shortcuts",
                duration: 6,
                actionButtonLabel: "Open Settings"
            )
        )
        XCTAssertEqual(
            RomaMacOSShortcutNotificationPresentation.accessibilityPermissionRequired,
            RomaMacOSShortcutNotificationPresentation(
                title: "Enable Accessibility for shortcuts",
                duration: 6,
                actionButtonLabel: "Open Settings"
            )
        )
        XCTAssertEqual(
            RomaMacOSShortcutNotificationPresentation.monitorStartFailed,
            RomaMacOSShortcutNotificationPresentation(
                title: "Keyboard shortcut monitor could not start",
                duration: 6
            )
        )
        XCTAssertEqual(
            RomaMacOSShortcutNotificationPresentation.miniRecorderEscapeConfirmation(duration: 1.5),
            RomaMacOSShortcutNotificationPresentation(
                title: "Press ESC again to cancel recording",
                duration: 1.5
            )
        )
    }

    func testMiniRecorderEscapeShortcutPolicyPreservesMacOSTiming() {
        XCTAssertEqual(RomaMiniRecorderEscapeShortcutPolicy.doublePressThreshold, 1.5)
        XCTAssertEqual(
            RomaMiniRecorderEscapeShortcutPolicy.confirmationPresentation,
            RomaMacOSShortcutNotificationPresentation(
                title: "Press ESC again to cancel recording",
                duration: 1.5
            )
        )
        XCTAssertEqual(RomaMiniRecorderEscapeShortcutPolicy.timeoutNanoseconds(), 1_500_000_000)
        XCTAssertEqual(
            RomaMiniRecorderEscapeShortcutPolicy.timeoutNanoseconds(threshold: -1),
            0
        )
        XCTAssertEqual(
            RomaMiniRecorderEscapeShortcutPolicy.timeoutNanoseconds(threshold: .infinity),
            0
        )
        XCTAssertEqual(
            RomaMiniRecorderEscapeShortcutPolicy.timeoutNanoseconds(threshold: .greatestFiniteMagnitude),
            UInt64.max
        )

        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            RomaMiniRecorderEscapeShortcutPolicy.isSecondPress(
                firstPressTime: nil,
                now: now
            )
        )
        XCTAssertTrue(
            RomaMiniRecorderEscapeShortcutPolicy.isSecondPress(
                firstPressTime: now.addingTimeInterval(-1.5),
                now: now
            )
        )
        XCTAssertFalse(
            RomaMiniRecorderEscapeShortcutPolicy.isSecondPress(
                firstPressTime: now.addingTimeInterval(-1.51),
                now: now
            )
        )
    }

    func testRecordingShortcutSelectionMigrationPlanMigratesCurrentPresetAndRemovesLegacyKey() {
        withIsolatedDefaults { defaults in
            defaults.set("rightOption", forKey: RomaUserDefaultsKey.primaryRecordingShortcut)
            defaults.set("leftShift", forKey: "selectedHotkey1")

            let plan = RomaRecordingShortcutPreference.shortcutSelectionMigrationPlan(
                for: .primaryRecording,
                allowsNone: false,
                from: defaults
            )

            XCTAssertEqual(plan.selection, .custom)
            XCTAssertEqual(plan.destinationKey, RomaUserDefaultsKey.primaryRecordingShortcut)
            XCTAssertEqual(plan.legacyKeyToRemove, "selectedHotkey1")
            XCTAssertEqual(plan.presetToStore, .rightOption)
            XCTAssertNil(plan.defaultPresetToStore)

            RomaRecordingShortcutPreference.applyShortcutSelectionMigrationPlan(plan, to: defaults)

            XCTAssertEqual(defaults.string(forKey: RomaUserDefaultsKey.primaryRecordingShortcut), "custom")
            XCTAssertNil(defaults.object(forKey: "selectedHotkey1"))
        }
    }

    func testRecordingShortcutSelectionMigrationPlanHandlesLegacyNoneAndAbsentDefaults() {
        withIsolatedDefaults { defaults in
            defaults.set("none", forKey: "selectedHotkey2")

            let secondaryPlan = RomaRecordingShortcutPreference.shortcutSelectionMigrationPlan(
                for: .secondaryRecording,
                allowsNone: true,
                from: defaults
            )

            XCTAssertEqual(secondaryPlan.selection, .none)
            XCTAssertEqual(secondaryPlan.destinationKey, RomaUserDefaultsKey.secondaryRecordingShortcut)
            XCTAssertEqual(secondaryPlan.legacyKeyToRemove, "selectedHotkey2")
            XCTAssertNil(secondaryPlan.presetToStore)
            XCTAssertNil(secondaryPlan.defaultPresetToStore)

            RomaRecordingShortcutPreference.applyShortcutSelectionMigrationPlan(secondaryPlan, to: defaults)

            XCTAssertEqual(defaults.string(forKey: RomaUserDefaultsKey.secondaryRecordingShortcut), "none")
            XCTAssertNil(defaults.object(forKey: "selectedHotkey2"))
        }

        withIsolatedDefaults { defaults in
            let primaryPlan = RomaRecordingShortcutPreference.shortcutSelectionMigrationPlan(
                for: .primaryRecording,
                allowsNone: false,
                from: defaults
            )

            XCTAssertEqual(primaryPlan.selection, .custom)
            XCTAssertEqual(primaryPlan.destinationKey, RomaUserDefaultsKey.primaryRecordingShortcut)
            XCTAssertNil(primaryPlan.legacyKeyToRemove)
            XCTAssertNil(primaryPlan.presetToStore)
            XCTAssertEqual(primaryPlan.defaultPresetToStore, .leftShift)

            let absentSecondaryPlan = RomaRecordingShortcutPreference.shortcutSelectionMigrationPlan(
                for: .secondaryRecording,
                allowsNone: true,
                from: defaults
            )

            XCTAssertEqual(absentSecondaryPlan.selection, .none)
            XCTAssertNil(absentSecondaryPlan.destinationKey)
            XCTAssertNil(absentSecondaryPlan.legacyKeyToRemove)
            XCTAssertNil(absentSecondaryPlan.presetToStore)
            XCTAssertNil(absentSecondaryPlan.defaultPresetToStore)
        }
    }

    func testRecordingShortcutModeMigrationMovesLegacyValuesAndMarksCompletion() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(RomaRecordingShortcutPreference.isLegacyKeyboardShortcutsMigrationComplete(in: defaults))
            XCTAssertFalse(RomaRecordingShortcutPreference.isLegacyCustomRecordingShortcutsMigrationComplete(in: defaults))

            RomaRecordingShortcutPreference.markLegacyKeyboardShortcutsMigrationComplete(in: defaults)
            RomaRecordingShortcutPreference.markLegacyCustomRecordingShortcutsMigrationComplete(in: defaults)

            XCTAssertTrue(RomaRecordingShortcutPreference.isLegacyKeyboardShortcutsMigrationComplete(in: defaults))
            XCTAssertTrue(RomaRecordingShortcutPreference.isLegacyCustomRecordingShortcutsMigrationComplete(in: defaults))

            defaults.set("pushToTalk", forKey: "hotkeyMode2")

            let mode = RomaRecordingShortcutPreference.migrateShortcutMode(
                for: .secondaryRecording,
                in: defaults
            )

            XCTAssertEqual(mode, .pushToTalk)
            XCTAssertEqual(defaults.string(forKey: RomaUserDefaultsKey.secondaryRecordingShortcutMode), "pushToTalk")
            XCTAssertNil(defaults.object(forKey: "hotkeyMode2"))
        }

        withIsolatedDefaults { defaults in
            defaults.set("toggle", forKey: RomaUserDefaultsKey.primaryRecordingShortcutMode)
            defaults.set("hybrid", forKey: "hotkeyMode1")

            let mode = RomaRecordingShortcutPreference.migrateShortcutMode(
                for: .primaryRecording,
                in: defaults
            )

            XCTAssertEqual(mode, .toggle)
            XCTAssertNil(defaults.object(forKey: "hotkeyMode1"))
        }
    }

    func testRecordingShortcutPreferenceReadsSavesAndClearsSettings() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(RomaRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(RomaRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertEqual(RomaRecordingShortcutPreference.mode(for: .secondary, from: defaults), .hybrid)
            XCTAssertFalse(RomaRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                RomaRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                RomaPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(RomaRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))

            RomaRecordingShortcutPreference.saveSelection(.custom, for: .primary, to: defaults)
            RomaRecordingShortcutPreference.saveSelection(.none, for: .secondary, to: defaults)
            RomaRecordingShortcutPreference.saveMode(.toggle, for: .primary, to: defaults)
            RomaRecordingShortcutPreference.saveMode(.pushToTalk, for: .secondary, to: defaults)
            RomaRecordingShortcutPreference.saveMiddleClickToggleEnabled(true, to: defaults)
            RomaRecordingShortcutPreference.saveMiddleClickActivationDelay(350, to: defaults)
            RomaRecordingShortcutPreference.saveShouldPasteLastTranscriptOnEmptyTap(false, to: defaults)

            XCTAssertEqual(RomaRecordingShortcutPreference.selection(for: .primary, from: defaults), .custom)
            XCTAssertEqual(
                RomaRecordingShortcutPreference.selection(for: .secondary, from: defaults),
                RomaRecordingShortcutSelection.none
            )
            XCTAssertEqual(RomaRecordingShortcutPreference.mode(for: .primary, from: defaults), .toggle)
            XCTAssertEqual(RomaRecordingShortcutPreference.mode(for: .secondary, from: defaults), .pushToTalk)
            XCTAssertTrue(RomaRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(RomaRecordingShortcutPreference.middleClickActivationDelay(from: defaults), 350)
            XCTAssertFalse(RomaRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))

            RomaRecordingShortcutPreference.saveMiddleClickActivationDelay(-1, to: defaults)
            XCTAssertEqual(RomaRecordingShortcutPreference.middleClickActivationDelay(from: defaults), 0)
            defaults.set(-50, forKey: RomaUserDefaultsKey.middleClickActivationDelay)
            XCTAssertEqual(RomaRecordingShortcutPreference.middleClickActivationDelay(from: defaults), 0)

            RomaRecordingShortcutPreference.clear(from: defaults)

            XCTAssertNil(RomaRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(RomaRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertFalse(RomaRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                RomaRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                RomaPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(RomaRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))
        }
    }

    func testShortcutStoragePreferenceStoresDataAndClearedState() {
        withIsolatedDefaults { defaults in
            let shortcutKey = "Shortcut_primaryRecording"
            let clearedKey = RomaShortcutStoragePreference.clearedKey(for: shortcutKey)
            let shortcutData = Data([1, 2, 3])

            XCTAssertEqual(clearedKey, "Shortcut_primaryRecording_cleared")
            XCTAssertNil(RomaShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults))
            XCTAssertFalse(RomaShortcutStoragePreference.isShortcutCleared(for: shortcutKey, from: defaults))

            RomaShortcutStoragePreference.markShortcutCleared(for: shortcutKey, to: defaults)

            XCTAssertNil(RomaShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults))
            XCTAssertTrue(RomaShortcutStoragePreference.isShortcutCleared(for: shortcutKey, from: defaults))

            RomaShortcutStoragePreference.saveShortcutData(shortcutData, for: shortcutKey, to: defaults)

            XCTAssertEqual(RomaShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults), shortcutData)
            XCTAssertNil(defaults.object(forKey: clearedKey))

            RomaShortcutStoragePreference.removeShortcutStorage(for: shortcutKey, from: defaults)

            XCTAssertNil(RomaShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults))
            XCTAssertNil(defaults.object(forKey: clearedKey))
        }
    }

    func testShortcutStoragePreferenceCapturesAndRestoresStoredState() {
        withIsolatedDefaults { defaults in
            let shortcutKey = "Shortcut_secondaryRecording"
            let originalData = Data([9, 8, 7])
            let replacementData = Data([1, 2, 3])

            RomaShortcutStoragePreference.saveShortcutData(originalData, for: shortcutKey, to: defaults)
            let dataState = RomaShortcutStoragePreference.storedState(for: shortcutKey, from: defaults)

            XCTAssertEqual(dataState, RomaShortcutStorageState(shortcutData: originalData, clearedValue: nil))

            RomaShortcutStoragePreference.markShortcutCleared(for: shortcutKey, to: defaults)
            let clearedState = RomaShortcutStoragePreference.storedState(for: shortcutKey, from: defaults)

            XCTAssertEqual(clearedState, RomaShortcutStorageState(shortcutData: nil, clearedValue: true))

            RomaShortcutStoragePreference.saveShortcutData(replacementData, for: shortcutKey, to: defaults)
            RomaShortcutStoragePreference.restoreStoredState(clearedState, for: shortcutKey, to: defaults)

            XCTAssertNil(RomaShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults))
            XCTAssertTrue(RomaShortcutStoragePreference.isShortcutCleared(for: shortcutKey, from: defaults))

            RomaShortcutStoragePreference.restoreStoredState(dataState, for: shortcutKey, to: defaults)

            XCTAssertEqual(RomaShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults), originalData)
            XCTAssertNil(defaults.object(forKey: RomaShortcutStoragePreference.clearedKey(for: shortcutKey)))
        }
    }

    func testRecordingShortcutPreferenceBuildsBackupPreferences() throws {
        let backup = RomaRecordingShortcutPreference.backupPreferences(
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
            try JSONDecoder().decode(RomaRecordingShortcutBackupPreferences.self, from: data),
            backup
        )
    }

    func testRecordingShortcutPreferenceBackupImportPlanSkipsInvalidRawValues() {
        let plan = RomaRecordingShortcutPreference.backupImportPlan(
            from: RomaRecordingShortcutBackupPreferences(
                primaryRecordingShortcutRawValue: "custom",
                secondaryRecordingShortcutRawValue: "invalid-selection",
                primaryRecordingShortcutModeRawValue: "toggle",
                secondaryRecordingShortcutModeRawValue: "invalid-mode",
                specialShortcutPasteLastTranscriptOnEmptyTap: false,
                isMiddleClickToggleEnabled: true,
                middleClickActivationDelay: 350
            )
        )

        var appliedEvents = [String]()
        plan.applyRuntimeState(
            setPrimaryRecordingShortcut: { appliedEvents.append("primary:\($0.rawValue)") },
            setSecondaryRecordingShortcut: { appliedEvents.append("secondary:\($0.rawValue)") },
            setPrimaryRecordingShortcutMode: { appliedEvents.append("primaryMode:\($0.rawValue)") },
            setSecondaryRecordingShortcutMode: { appliedEvents.append("secondaryMode:\($0.rawValue)") },
            setSpecialShortcutPasteLastTranscriptOnEmptyTap: { appliedEvents.append("paste:\($0)") },
            setMiddleClickToggleEnabled: { appliedEvents.append("middleClick:\($0)") },
            setMiddleClickActivationDelay: { appliedEvents.append("middleClickDelay:\($0)") }
        )

        XCTAssertEqual(
            appliedEvents,
            [
                "primary:custom",
                "primaryMode:toggle",
                "paste:false",
                "middleClick:true",
                "middleClickDelay:350"
            ]
        )

        let negativeDelayPlan = RomaRecordingShortcutPreference.backupImportPlan(
            from: RomaRecordingShortcutBackupPreferences(
                primaryRecordingShortcutRawValue: nil,
                secondaryRecordingShortcutRawValue: nil,
                primaryRecordingShortcutModeRawValue: nil,
                secondaryRecordingShortcutModeRawValue: nil,
                specialShortcutPasteLastTranscriptOnEmptyTap: nil,
                isMiddleClickToggleEnabled: nil,
                middleClickActivationDelay: -1
            )
        )

        var negativeDelayEvents = [String]()
        negativeDelayPlan.applyRuntimeState(
            setPrimaryRecordingShortcut: { negativeDelayEvents.append("primary:\($0.rawValue)") },
            setSecondaryRecordingShortcut: { negativeDelayEvents.append("secondary:\($0.rawValue)") },
            setPrimaryRecordingShortcutMode: { negativeDelayEvents.append("primaryMode:\($0.rawValue)") },
            setSecondaryRecordingShortcutMode: { negativeDelayEvents.append("secondaryMode:\($0.rawValue)") },
            setSpecialShortcutPasteLastTranscriptOnEmptyTap: { negativeDelayEvents.append("paste:\($0)") },
            setMiddleClickToggleEnabled: { negativeDelayEvents.append("middleClick:\($0)") },
            setMiddleClickActivationDelay: { negativeDelayEvents.append("middleClickDelay:\($0)") }
        )

        XCTAssertEqual(negativeDelayEvents, ["middleClickDelay:0"])
    }

    func testShortcutBackupPolicyExportsGeneralShortcutsInStableOrder() {
        XCTAssertEqual(
            RomaShortcutBackupPolicy.generalBackupShortcutExportPlan(
                availableActionIdentifiers: [
                    .toggleEnhancement,
                    .miniRecorderEscape,
                    .primaryRecording,
                    .retryLastTranscription,
                    .quickAddToDictionary
                ]
            ),
            [
                .primaryRecording,
                .retryLastTranscription,
                .quickAddToDictionary,
                .toggleEnhancement
            ]
        )
    }

    func testShortcutBackupPolicyBuildsGeneralShortcutRecordsThroughAdapter() {
        var requestedActionIdentifiers = [RomaShortcutActionIdentifier]()
        let records = RomaShortcutBackupPolicy.generalBackupShortcutRecords { actionIdentifier in
            requestedActionIdentifiers.append(actionIdentifier)
            switch actionIdentifier {
            case .primaryRecording:
                return "primary"
            case .retryLastTranscription:
                return "retry"
            case .toggleEnhancement:
                return "toggle"
            default:
                return nil
            }
        }

        XCTAssertEqual(
            requestedActionIdentifiers,
            RomaShortcutBackupPolicy.generalBackupShortcutActionIdentifiers
        )
        XCTAssertEqual(
            records,
            [
                .primaryRecording: "primary",
                .retryLastTranscription: "retry",
                .toggleEnhancement: "toggle"
            ]
        )
    }

    func testShortcutBackupPolicyImportsGeneralShortcutsWithRecordingSelections() {
        XCTAssertEqual(
            RomaShortcutBackupPolicy.generalBackupShortcutImportPlan(
                importedActionIdentifiers: [
                    .secondaryRecording,
                    .miniRecorderEscape,
                    .pasteLastTranscription,
                    .primaryRecording
                ]
            ),
            [
                RomaShortcutBackupImport(
                    actionIdentifier: .primaryRecording,
                    recordingShortcutSlot: .primary,
                    recordingShortcutSelection: .custom
                ),
                RomaShortcutBackupImport(
                    actionIdentifier: .secondaryRecording,
                    recordingShortcutSlot: .secondary,
                    recordingShortcutSelection: .custom
                ),
                RomaShortcutBackupImport(
                    actionIdentifier: .pasteLastTranscription,
                    recordingShortcutSlot: nil,
                    recordingShortcutSelection: nil
                )
            ]
        )
    }

    func testSharedPreferenceResetClearsCoreUserSettings() {
        withIsolatedDefaults { defaults in
            let mode = Mode.defaultLocalWhisper()
            RomaModeStorage.saveModes([mode], to: defaults)
            RomaModeStorage.saveSelectedModeId(mode.id, to: defaults)
            RomaOnboardingPreference.saveHasCompletedOnboarding(to: defaults)
            RomaProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            RomaAudioSessionTimeoutPreference.saveTimeoutSeconds(120, to: defaults)
            RomaVADPreference.saveIsEnabled(false, to: defaults)
            PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)
            RomaFillerWordPreference.saveWords(["um", "like"], to: defaults)
            RomaWordReplacementPreference.saveRules([
                RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ], to: defaults)
            RomaCustomVocabularyPreference.saveTerms(["Roma", "Felix"], to: defaults)
            RomaDictionaryListSortPreference.saveVocabularySortMode(.wordDescending, to: defaults)
            RomaDictionaryListSortPreference.saveWordReplacementSortMode(.replacementDescending, to: defaults)
            RomaTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            RomaTranscriptionPromptPreference.savePrompt("custom prompt", to: defaults)
            RomaCurrentTranscriptionModelPreference.saveModelName("nova-3", to: defaults)
            RomaAIEnhancementProviderPreference.saveSelectedProviderRawValue("OpenRouter", to: defaults)
            RomaAIEnhancementProviderPreference.saveSelectedModel("openai/gpt-oss-120b", for: "OpenRouter", to: defaults)
            RomaDynamicAIProviderPreference.saveOllamaBaseURL("http://example.local:11434", to: defaults)
            RomaDynamicAIProviderPreference.saveOllamaSelectedModel("mistral", to: defaults)
            RomaDynamicAIProviderPreference.saveCustomProviderBaseURL("https://api.example.com/v1", to: defaults)
            RomaDynamicAIProviderPreference.saveCustomProviderModel("custom-model", to: defaults)
            RomaDynamicAIProviderPreference.saveOpenRouterModels(["openai/gpt-oss-120b"], to: defaults)
            RomaLocalCLIPreference.saveCommandTemplate("codex exec \"$ROMA_FULL_PROMPT\"", to: defaults)
            RomaLocalCLIPreference.saveSelectedTemplate(.codex, to: defaults)
            RomaLocalCLIPreference.saveTimeoutSeconds(90, to: defaults)
            defaults.set(15, forKey: RomaUserDefaultsKey.enhancementTimeoutSeconds)
            defaults.set(false, forKey: RomaUserDefaultsKey.enhancementRetryOnTimeout)
            RomaTranscriptionAutoCleanupPreference.saveIsEnabled(true, to: defaults)
            RomaTranscriptionAutoCleanupPreference.saveRetentionMinutes(15, to: defaults)
            RomaAudioCleanupPreference.saveIsEnabled(true, to: defaults)
            RomaAudioCleanupPreference.saveRetentionDays(30, to: defaults)
            let customPrompt = RomaCustomPrompt(title: "Custom", promptText: "Clean this")
            RomaCustomPromptStorage.savePrompts([customPrompt], to: defaults)
            RomaCustomPromptStorage.saveSelectedPromptId(customPrompt.id, to: defaults)
            RomaAIEnhancementContextPreference.saveUseClipboardContext(true, to: defaults)
            RomaAIEnhancementContextPreference.saveUseScreenCaptureContext(true, to: defaults)
            RomaPowerModePreference.saveIsUIEnabled(true, to: defaults)
            RomaPowerModePreference.saveShouldPersistConfiguredPreferences(true, to: defaults)
            RomaModelRuntimePreference.saveShouldPrewarmModelOnWake(false, to: defaults)
            RomaRecorderPreviewPreference.saveIsLiveTextPreviewEnabled(true, to: defaults)
            RomaAudioInputPreference.saveLastUsedMicrophoneDeviceID("123", to: defaults)
            RomaRecordingShortcutPreference.saveSelection(.custom, for: .primary, to: defaults)
            RomaRecordingShortcutPreference.saveSelection(.none, for: .secondary, to: defaults)
            RomaRecordingShortcutPreference.saveMode(.toggle, for: .primary, to: defaults)
            RomaRecordingShortcutPreference.saveMode(.pushToTalk, for: .secondary, to: defaults)
            RomaRecordingShortcutPreference.saveMiddleClickToggleEnabled(true, to: defaults)
            RomaRecordingShortcutPreference.saveMiddleClickActivationDelay(350, to: defaults)
            RomaRecordingShortcutPreference.saveShouldPasteLastTranscriptOnEmptyTap(false, to: defaults)
            let powerModeConfig = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                isAIEnhancementEnabled: false
            )
            RomaPowerModeConfigurationPreference.saveConfigurations([powerModeConfig], to: defaults)
            RomaPowerModeConfigurationPreference.saveActiveConfigurationId(powerModeConfig.id, to: defaults)
            try? RomaPowerModeSessionPreference.saveActiveSession(
                RomaPowerModeSession(
                    id: UUID(),
                    startTime: Date(timeIntervalSince1970: 1_700_000_000),
                    originalState: RomaPowerModeApplicationState(
                        isEnhancementEnabled: true,
                        useScreenCaptureContext: false
                    )
                ),
                to: defaults
            )

            RomaSharedPreferenceReset.clearCoreUserSettings(from: defaults, providers: [.groq])

            XCTAssertTrue(RomaModeStorage.loadModes(from: defaults).isEmpty)
            XCTAssertNil(RomaModeStorage.loadSelectedModeId(from: defaults))
            XCTAssertFalse(RomaOnboardingPreference.hasCompletedOnboarding(from: defaults))
            XCTAssertFalse(RomaProviderAPIKeyVerificationState.isVerified(.groq, in: defaults))
            XCTAssertEqual(
                RomaAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                RomaPreferenceDefault.audioSessionTimeoutSeconds
            )
            XCTAssertEqual(
                RomaVADPreference.isEnabled(from: defaults),
                RomaPreferenceDefault.isVADEnabled
            )
            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .keep)
            XCTAssertEqual(
                RomaTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults),
                RomaPreferenceDefault.isTextFormattingEnabled
            )
            XCTAssertEqual(
                RomaTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults),
                RomaPreferenceDefault.lowercaseTranscription
            )
            XCTAssertEqual(
                RomaTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults),
                RomaPreferenceDefault.removeFillerWords
            )
            XCTAssertEqual(RomaFillerWordPreference.words(from: defaults), RomaFillerWords.defaultWords)
            XCTAssertEqual(RomaWordReplacementPreference.rules(from: defaults), [])
            XCTAssertEqual(RomaCustomVocabularyPreference.terms(from: defaults), [])
            XCTAssertEqual(RomaDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(
                RomaDictionaryListSortPreference.wordReplacementSortMode(from: defaults),
                .originalAscending
            )
            XCTAssertEqual(
                RomaTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                RomaLanguageCatalog.autoDetectCode
            )
            XCTAssertNil(RomaTranscriptionPromptPreference.storedPrompt(from: defaults))
            XCTAssertNil(RomaCurrentTranscriptionModelPreference.modelName(from: defaults))
            XCTAssertNil(RomaAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults))
            XCTAssertNil(RomaAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults))
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                RomaPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                RomaDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )
            XCTAssertEqual(RomaDynamicAIProviderPreference.customProviderBaseURL(from: defaults), "")
            XCTAssertEqual(RomaDynamicAIProviderPreference.customProviderModel(from: defaults), "")
            XCTAssertEqual(RomaDynamicAIProviderPreference.openRouterModels(from: defaults), [])
            XCTAssertEqual(RomaLocalCLIPreference.commandTemplate(from: defaults), "")
            XCTAssertEqual(RomaLocalCLIPreference.selectedTemplate(from: defaults), .pi)
            XCTAssertEqual(RomaLocalCLIPreference.timeoutSeconds(from: defaults), 45)
            XCTAssertEqual(
                RomaAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(RomaPreferenceDefault.enhancementTimeoutSeconds)
            )
            XCTAssertTrue(RomaAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults))
            XCTAssertEqual(
                RomaTranscriptionAutoCleanupPreference.current(from: defaults),
                RomaTranscriptionAutoCleanupConfiguration(
                    isEnabled: false,
                    retentionMinutes: RomaPreferenceDefault.transcriptionRetentionMinutes
                )
            )
            XCTAssertEqual(
                RomaAudioCleanupPreference.current(from: defaults),
                RomaAudioCleanupConfiguration(
                    isEnabled: false,
                    retentionDays: RomaPreferenceDefault.audioRetentionDays
                )
            )
            XCTAssertTrue(RomaCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
            XCTAssertNil(RomaCustomPromptStorage.loadSelectedPromptId(from: defaults))
            XCTAssertFalse(RomaAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(RomaAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))
            XCTAssertFalse(RomaPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertFalse(RomaPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))
            XCTAssertTrue(RomaPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(RomaPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
            XCTAssertNil(try? RomaPowerModeSessionPreference.loadActiveSession(from: defaults))
            XCTAssertTrue(RomaModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))
            XCTAssertFalse(RomaRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))
            XCTAssertNil(RomaAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
            XCTAssertNil(RomaRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(RomaRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertFalse(RomaRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                RomaRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                RomaPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(RomaRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))
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

            RomaModeStorage.saveModes([localMode, cloudMode], to: defaults)
            RomaModeStorage.saveSelectedModeId(cloudMode.id, to: defaults)

            let loadedModes = RomaModeStorage.loadModes(from: defaults)
            XCTAssertEqual(loadedModes.map(\.name), ["Local", "Cloud"])
            XCTAssertEqual(loadedModes.map(\.id), [localMode.id, cloudMode.id])
            XCTAssertEqual(RomaModeStorage.loadSelectedModeId(from: defaults), cloudMode.id)
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

            RomaModeStorage.saveModes([staleMode], to: defaults)

            let loadedMode = RomaModeStorage.loadModes(from: defaults).first

            XCTAssertEqual(loadedMode?.id, staleMode.id)
            XCTAssertEqual(loadedMode?.transcriptionModel, RomaProviderKind.deepgram.defaultModel(for: .transcription))
            XCTAssertEqual(loadedMode?.postProcessingModel, RomaProviderKind.gemini.defaultModel(for: .postProcessing))
        }
    }

    func testModeStorageMigratesLegacyVoiceInkProvidersWithoutDroppingModeList() {
        withIsolatedDefaults { defaults in
            let legacyModeId = UUID(uuidString: "E9A2F4E2-6B2F-4E9D-A631-0D4640D74F3A")!
            let cloudModeId = UUID(uuidString: "C3E1F5D0-539B-4D1B-9F7F-48989AF59056")!
            let groqDefaultModel = RomaAIModelCatalog.defaultModel(for: .groq)
            let json = """
            [
              {
                "id": "\(legacyModeId.uuidString)",
                "name": "Legacy RomaJustTalk",
                "transcriptionProvider": "RomaJustTalk",
                "transcriptionModel": "whisper-large-v3",
                "isPostProcessingEnabled": true,
                "postProcessingProvider": "romaJustTalk",
                "postProcessingModel": "llama-3.1-8b-instant",
                "promptTemplate": {
                  "type": "Summary",
                  "customPrompt": ""
                }
              },
              {
                "id": "\(cloudModeId.uuidString)",
                "name": "Cloud",
                "transcriptionProvider": "Deepgram",
                "transcriptionModel": "nova-3",
                "isPostProcessingEnabled": false,
                "postProcessingProvider": "Groq",
                "postProcessingModel": "\(groqDefaultModel)",
                "promptTemplate": {
                  "type": "Summary",
                  "customPrompt": ""
                }
              }
            ]
            """

            defaults.set(Data(json.utf8), forKey: RomaUserDefaultsKey.modes)

            let modes = RomaModeStorage.loadModes(from: defaults)

            XCTAssertEqual(modes.map(\.id), [legacyModeId, cloudModeId])
            XCTAssertEqual(modes.first?.name, "Legacy RomaJustTalk")
            XCTAssertEqual(modes.first?.transcriptionProvider, .localWhisper)
            XCTAssertEqual(modes.first?.transcriptionModel, RomaTranscriptionModelCatalog.localBaseModel)
            XCTAssertEqual(modes.first?.isPostProcessingEnabled, false)
            XCTAssertEqual(modes.first?.postProcessingProvider, .groq)
            XCTAssertEqual(modes.first?.postProcessingModel, groqDefaultModel)
            XCTAssertEqual(modes.last?.transcriptionProvider, .deepgram)
            XCTAssertEqual(modes.last?.postProcessingProvider, .groq)
        }
    }

    func testModeStorageFallsBackToEmptyModesForMissingOrInvalidData() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(RomaModeStorage.loadModes(from: defaults).isEmpty)

            defaults.set(Data("bad".utf8), forKey: RomaUserDefaultsKey.modes)
            XCTAssertTrue(RomaModeStorage.loadModes(from: defaults).isEmpty)
        }
    }

    func testModeStorageClearRemovesModesAndSelectedModeId() {
        withIsolatedDefaults { defaults in
            let mode = Mode.defaultLocalWhisper()
            RomaModeStorage.saveModes([mode], to: defaults)
            RomaModeStorage.saveSelectedModeId(mode.id, to: defaults)

            RomaModeStorage.clear(from: defaults)

            XCTAssertTrue(RomaModeStorage.loadModes(from: defaults).isEmpty)
            XCTAssertNil(RomaModeStorage.loadSelectedModeId(from: defaults))
        }
    }

    func testPowerModeConfigurationPreferenceRoundTripsConfigurationsAndActiveConfigurationId() {
        withIsolatedDefaults { defaults in
            let firstConfig = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                appConfigs: [
                    RomaPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "Example")
                ],
                urlConfigs: [
                    RomaPowerModeURLConfig(url: "example.com")
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

            RomaPowerModeConfigurationPreference.saveConfigurations([firstConfig, secondConfig], to: defaults)
            RomaPowerModeConfigurationPreference.saveActiveConfigurationId(secondConfig.id, to: defaults)

            let loadedConfigs = RomaPowerModeConfigurationPreference.loadConfigurations(from: defaults)
            XCTAssertEqual(loadedConfigs.map(\.id), [firstConfig.id, secondConfig.id])
            XCTAssertEqual(loadedConfigs.map(\.name), ["Writing", "Notes"])
            XCTAssertEqual(loadedConfigs.first?.appConfigs?.first?.bundleIdentifier, "com.example.App")
            XCTAssertEqual(loadedConfigs.first?.urlConfigs?.first?.url, "example.com")
            XCTAssertEqual(loadedConfigs.first?.autoSendKey, .commandEnter)
            XCTAssertEqual(
                RomaPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults),
                secondConfig.id
            )
            XCTAssertTrue(defaults.data(forKey: RomaUserDefaultsKey.powerModeConfigurations) != nil)
            XCTAssertEqual(
                defaults.string(forKey: RomaUserDefaultsKey.activePowerModeConfigurationId),
                secondConfig.id.uuidString
            )
        }
    }

    func testPowerModeConfigurationPreferenceFallsBackForMissingInvalidAndBlankActiveId() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(RomaPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(RomaPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))

            defaults.set(Data("bad".utf8), forKey: RomaUserDefaultsKey.powerModeConfigurations)
            defaults.set("not-a-uuid", forKey: RomaUserDefaultsKey.activePowerModeConfigurationId)

            XCTAssertTrue(RomaPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(RomaPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))

            defaults.set("", forKey: RomaUserDefaultsKey.activePowerModeConfigurationId)
            XCTAssertNil(RomaPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
        }
    }

    func testPowerModeConfigurationPreferenceClearRemovesConfigurationsAndActiveConfigurationId() {
        withIsolatedDefaults { defaults in
            let config = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                isAIEnhancementEnabled: false
            )
            RomaPowerModeConfigurationPreference.saveConfigurations([config], to: defaults)
            RomaPowerModeConfigurationPreference.saveActiveConfigurationId(config.id, to: defaults)

            RomaPowerModeConfigurationPreference.clear(from: defaults)

            XCTAssertTrue(RomaPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(RomaPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
            XCTAssertNil(defaults.object(forKey: RomaUserDefaultsKey.powerModeConfigurations))
            XCTAssertNil(defaults.object(forKey: RomaUserDefaultsKey.activePowerModeConfigurationId))
        }
    }

    func testPowerModePreferenceRegisteredDefaultsPreserveUIFlagInitializationPolicy() {
        XCTAssertNil(RomaPowerModePreference.registeredDefaults[RomaUserDefaultsKey.powerModeUIFlag])
        XCTAssertEqual(
            RomaPowerModePreference.registeredDefaults[RomaUserDefaultsKey.powerModePersistConfig] as? Bool,
            false
        )
    }

    func testPowerModePreferenceReadsAndSavesFlags() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(RomaPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertFalse(RomaPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))

            RomaPowerModePreference.saveIsUIEnabled(true, to: defaults)
            RomaPowerModePreference.saveShouldPersistConfiguredPreferences(true, to: defaults)

            XCTAssertTrue(RomaPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertTrue(RomaPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))
        }
    }

    func testPowerModePreferenceInitializesUIFlagFromEnabledConfigurationsWhenMissing() {
        withIsolatedDefaults { defaults in
            RomaPowerModePreference.initializeUIFlagIfNeeded(
                hasEnabledConfigurations: true,
                in: defaults
            )

            XCTAssertTrue(RomaPowerModePreference.isUIEnabled(from: defaults))
        }
    }

    func testPowerModePreferenceInitializeUIFlagDoesNotOverwriteStoredValue() {
        withIsolatedDefaults { defaults in
            RomaPowerModePreference.saveIsUIEnabled(false, to: defaults)

            RomaPowerModePreference.initializeUIFlagIfNeeded(
                hasEnabledConfigurations: true,
                in: defaults
            )

            XCTAssertFalse(RomaPowerModePreference.isUIEnabled(from: defaults))
        }
    }

    func testPowerModePreferenceShortcutEligibilityRequiresUIAndEnabledConfigurations() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(RomaPowerModePreference.canUseShortcuts(hasEnabledConfigurations: true, from: defaults))

            RomaPowerModePreference.saveIsUIEnabled(true, to: defaults)

            XCTAssertFalse(RomaPowerModePreference.canUseShortcuts(hasEnabledConfigurations: false, from: defaults))
            XCTAssertTrue(RomaPowerModePreference.canUseShortcuts(hasEnabledConfigurations: true, from: defaults))
        }
    }

    func testPowerModeSessionPreferenceRoundTripsActiveSession() throws {
        let suiteName = "RomaCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let originalState = RomaPowerModeApplicationState(
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
        let session = RomaPowerModeSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            originalState: originalState
        )

        try RomaPowerModeSessionPreference.saveActiveSession(session, to: defaults)

        let loadedSession = try RomaPowerModeSessionPreference.loadActiveSession(from: defaults)
        XCTAssertEqual(loadedSession?.id, session.id)
        XCTAssertEqual(loadedSession?.startTime, session.startTime)
        XCTAssertEqual(loadedSession?.originalState, originalState)
        XCTAssertTrue(defaults.data(forKey: RomaUserDefaultsKey.activePowerModeSession) != nil)
    }

    func testPowerModeSessionPreferenceThrowsForInvalidActiveSessionData() {
        withIsolatedDefaults { defaults in
            defaults.set(Data("bad".utf8), forKey: RomaUserDefaultsKey.activePowerModeSession)

            var didThrow = false
            do {
                _ = try RomaPowerModeSessionPreference.loadActiveSession(from: defaults)
            } catch {
                didThrow = true
            }

            XCTAssertTrue(didThrow)
        }
    }

    func testPowerModeSessionPreferenceClearRemovesActiveSession() {
        withIsolatedDefaults { defaults in
            let session = RomaPowerModeSession(
                id: UUID(),
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                originalState: RomaPowerModeApplicationState(
                    isEnhancementEnabled: false,
                    useScreenCaptureContext: true
                )
            )
            try? RomaPowerModeSessionPreference.saveActiveSession(session, to: defaults)

            RomaPowerModeSessionPreference.clear(from: defaults)

            XCTAssertNil(try? RomaPowerModeSessionPreference.loadActiveSession(from: defaults))
            XCTAssertNil(defaults.object(forKey: RomaUserDefaultsKey.activePowerModeSession))
        }
    }

    func testCustomPromptStorageRoundTripsPromptsAndSelectedPromptId() {
        withIsolatedDefaults { defaults in
            let customPrompt = RomaCustomPrompt(
                title: "Custom",
                promptText: "Keep terms exact.",
                triggerWords: ["terms"]
            )
            let assistantPrompt = RomaCustomPrompt(predefinedPrompt: RomaPredefinedPrompts.all[1])

            RomaCustomPromptStorage.savePrompts([customPrompt, assistantPrompt], to: defaults)
            RomaCustomPromptStorage.saveSelectedPromptId(assistantPrompt.id, to: defaults)

            let loadedPrompts = RomaCustomPromptStorage.loadPrompts(from: defaults)
            XCTAssertEqual(loadedPrompts.map(\.id), [customPrompt.id, assistantPrompt.id])
            XCTAssertEqual(loadedPrompts.map(\.title), ["Custom", "Assistant"])
            XCTAssertEqual(RomaCustomPromptStorage.loadSelectedPromptId(from: defaults), assistantPrompt.id)
        }
    }

    func testCustomPromptStorageFallsBackToEmptyPromptsForMissingOrInvalidData() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(RomaCustomPromptStorage.loadPrompts(from: defaults).isEmpty)

            defaults.set(Data("bad".utf8), forKey: RomaUserDefaultsKey.customPrompts)
            XCTAssertTrue(RomaCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
        }
    }

    func testCustomPromptStorageClearRemovesPromptsAndSelectedPromptId() {
        withIsolatedDefaults { defaults in
            let prompt = RomaCustomPrompt(title: "Prompt", promptText: "Text")
            RomaCustomPromptStorage.savePrompts([prompt], to: defaults)
            RomaCustomPromptStorage.saveSelectedPromptId(prompt.id, to: defaults)

            RomaCustomPromptStorage.clear(from: defaults)

            XCTAssertTrue(RomaCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
            XCTAssertNil(RomaCustomPromptStorage.loadSelectedPromptId(from: defaults))
        }
    }

    func testProviderAPIKeyVerificationStateUsesProviderKeys() {
        withIsolatedDefaults { defaults in
            RomaProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)

            XCTAssertTrue(RomaProviderAPIKeyVerificationState.isVerified(.groq, in: defaults))
            XCTAssertEqual(defaults.object(forKey: "groqKeyVerified") as? Bool, true)
        }
    }

    func testProviderAPIKeyVerificationStatePersistsFalseFlag() {
        withIsolatedDefaults { defaults in
            RomaProviderAPIKeyVerificationState.setVerified(true, for: .deepgram, in: defaults)
            RomaProviderAPIKeyVerificationState.setVerified(false, for: .deepgram, in: defaults)

            XCTAssertFalse(RomaProviderAPIKeyVerificationState.isVerified(.deepgram, in: defaults))
            XCTAssertEqual(defaults.object(forKey: "deepgramKeyVerified") as? Bool, false)
        }
    }

    func testProviderAPIKeyVerificationStateFiltersVerifiedUserKeyProviders() {
        withIsolatedDefaults { defaults in
            RomaProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            RomaProviderAPIKeyVerificationState.setVerified(true, for: .localWhisper, in: defaults)

            XCTAssertEqual(
                RomaProviderAPIKeyVerificationState.verifiedProviders(from: [.groq, .deepgram, .localWhisper], in: defaults),
                [.groq]
            )
            XCTAssertFalse(RomaProviderAPIKeyVerificationState.isVerified(.localWhisper, in: defaults))
        }
    }

    func testProviderAPIKeyVerificationStateClearsSingleAndAllProviders() {
        withIsolatedDefaults { defaults in
            RomaProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            RomaProviderAPIKeyVerificationState.setVerified(true, for: .deepgram, in: defaults)
            RomaProviderAPIKeyVerificationState.clear(for: .groq, in: defaults)

            XCTAssertNil(defaults.object(forKey: "groqKeyVerified"))
            XCTAssertTrue(RomaProviderAPIKeyVerificationState.isVerified(.deepgram, in: defaults))

            RomaProviderAPIKeyVerificationState.clearAll(from: [.groq, .deepgram], in: defaults)

            XCTAssertNil(defaults.object(forKey: "deepgramKeyVerified"))
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "RomaCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
