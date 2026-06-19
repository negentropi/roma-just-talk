import Foundation
import VoiceInkCore

final class PowerModePolicyTests: XCTestCase {
    func testPowerModeTriggerConfigsPreserveStoredShapeAndIdEquality() throws {
        let id = UUID()
        let appConfig = VoiceInkPowerModeAppConfig(
            id: id,
            bundleIdentifier: "com.example.App",
            appName: "Example"
        )
        let renamedAppConfig = VoiceInkPowerModeAppConfig(
            id: id,
            bundleIdentifier: "com.example.Other",
            appName: "Other"
        )
        let urlConfig = VoiceInkPowerModeURLConfig(id: id, url: "example.com")
        let renamedURLConfig = VoiceInkPowerModeURLConfig(id: id, url: "other.example.com")

        XCTAssertEqual(appConfig, renamedAppConfig)
        XCTAssertEqual(urlConfig, renamedURLConfig)

        let appObject = try jsonObject(from: appConfig)
        XCTAssertEqual(appObject["id"] as? String, id.uuidString)
        XCTAssertEqual(appObject["bundleIdentifier"] as? String, "com.example.App")
        XCTAssertEqual(appObject["appName"] as? String, "Example")

        let urlObject = try jsonObject(from: urlConfig)
        XCTAssertEqual(urlObject["id"] as? String, id.uuidString)
        XCTAssertEqual(urlObject["url"] as? String, "example.com")
    }

    func testPowerModeTriggerConfigsAdaptToPolicyRules() {
        XCTAssertEqual(
            VoiceInkPowerModeAppConfig(
                bundleIdentifier: "com.example.App",
                appName: "Example"
            ).rule,
            VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Example")
        )
        XCTAssertEqual(
            VoiceInkPowerModeURLConfig(url: "example.com").rule,
            VoiceInkPowerModeWebsiteRule(url: "example.com")
        )
    }

    func testPowerModeConfigPreservesStoredShapeEqualityAndRuleAdapter() throws {
        let id = UUID()
        let config = PowerModeConfig(
            id: id,
            name: "Writing",
            emoji: "W",
            appConfigs: [
                VoiceInkPowerModeAppConfig(
                    bundleIdentifier: "com.example.App",
                    appName: "Example"
                )
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
            punctuationCleanupMode: .removeAll,
            lowercaseTranscription: true,
            selectedAIProvider: "openai",
            selectedAIModel: "gpt-4o",
            autoSendKey: .commandEnter,
            isEnabled: true,
            isDefault: true
        )
        let sameIDConfig = PowerModeConfig(
            id: id,
            name: "Other",
            emoji: "O",
            isAIEnhancementEnabled: false
        )

        XCTAssertEqual(config, sameIDConfig)

        let object = try jsonObject(from: config)
        XCTAssertEqual(object["id"] as? String, id.uuidString)
        XCTAssertEqual(object["name"] as? String, "Writing")
        XCTAssertEqual(object["emoji"] as? String, "W")
        XCTAssertEqual(object["selectedPrompt"] as? String, "prompt-id")
        XCTAssertEqual(object["selectedTranscriptionModelName"] as? String, "ggml-base")
        XCTAssertEqual(object["selectedLanguage"] as? String, "en")
        XCTAssertEqual(object["punctuationCleanupMode"] as? String, PunctuationCleanupMode.removeAll.rawValue)
        XCTAssertEqual(object["removePunctuation"] as? Bool, true)
        XCTAssertEqual(object["autoSendKey"] as? String, VoiceInkAutoSendKey.commandEnter.rawValue)

        let rule = config.powerModePolicyRule
        XCTAssertEqual(rule.id, id)
        XCTAssertEqual(rule.name, "Writing")
        XCTAssertEqual(
            rule.appRules,
            [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Example")]
        )
        XCTAssertEqual(rule.websiteRules, [VoiceInkPowerModeWebsiteRule(url: "example.com")])
        XCTAssertTrue(rule.isEnabled)
        XCTAssertTrue(rule.isDefault)
    }

    func testPowerModeConfigExposesParsedPromptAndProviderForApplication() {
        let promptID = UUID()
        let validConfig = PowerModeConfig(
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: true,
            selectedPrompt: promptID.uuidString,
            selectedAIProvider: "GROQ"
        )
        let invalidConfig = PowerModeConfig(
            name: "Broken",
            emoji: "B",
            isAIEnhancementEnabled: true,
            selectedPrompt: "not-a-uuid",
            selectedAIProvider: "MissingProvider"
        )

        XCTAssertEqual(validConfig.selectedPromptUUID, promptID)
        XCTAssertEqual(validConfig.selectedAIProviderKind, .groq)
        XCTAssertNil(invalidConfig.selectedPromptUUID)
        XCTAssertNil(invalidConfig.selectedAIProviderKind)
    }

    func testPowerModeConfigResolvesSelectedPromptTitle() {
        let promptID = UUID()
        let prompt = VoiceInkCustomPrompt(id: promptID, title: "Rewrite", promptText: "Rewrite this")
        let matchingConfig = PowerModeConfig(
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: true,
            selectedPrompt: promptID.uuidString
        )
        let staleConfig = PowerModeConfig(
            name: "Stale",
            emoji: "S",
            isAIEnhancementEnabled: true,
            selectedPrompt: UUID().uuidString
        )
        let invalidConfig = PowerModeConfig(
            name: "Invalid",
            emoji: "I",
            isAIEnhancementEnabled: true,
            selectedPrompt: "not-a-uuid"
        )

        XCTAssertEqual(matchingConfig.selectedPromptTitle(in: [prompt]), "Rewrite")
        XCTAssertNil(staleConfig.selectedPromptTitle(in: [prompt]))
        XCTAssertNil(invalidConfig.selectedPromptTitle(in: [prompt]))
    }

    func testPowerModeConfigDecodesLegacyStoredKeys() throws {
        let id = UUID()
        let data = Data("""
        {
          "id": "\(id.uuidString)",
          "name": "Legacy",
          "emoji": "L",
          "appConfigs": [],
          "urlConfigs": [],
          "isAIEnhancementEnabled": false,
          "useScreenCapture": false,
          "isTextFormattingEnabled": true,
          "removePunctuation": true,
          "lowercaseTranscription": true,
          "isAutoSendEnabled": true,
          "selectedWhisperModel": "ggml-base.en"
        }
        """.utf8)

        let config = try JSONDecoder().decode(PowerModeConfig.self, from: data)

        XCTAssertEqual(config.id, id)
        XCTAssertEqual(config.name, "Legacy")
        XCTAssertEqual(config.emoji, "L")
        XCTAssertEqual(config.appConfigs, [])
        XCTAssertEqual(config.urlConfigs, [])
        XCTAssertEqual(config.punctuationCleanupMode, .removeAll)
        XCTAssertTrue(config.isTextFormattingEnabled)
        XCTAssertTrue(config.lowercaseTranscription)
        XCTAssertEqual(config.autoSendKey, .enter)
        XCTAssertEqual(config.selectedTranscriptionModelName, "ggml-base.en")
        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.isDefault)
    }

    func testConfigurationDraftBuildsAddConfigurationWithStoredFormSemantics() {
        let id = UUID()
        let promptID = UUID()
        let appConfig = VoiceInkPowerModeAppConfig(
            bundleIdentifier: "com.example.App",
            appName: "Example"
        )
        let urlConfig = VoiceInkPowerModeURLConfig(url: "example.com")
        let draft = VoiceInkPowerModeConfigurationDraft(
            id: id,
            name: "Writing",
            emoji: "W",
            appConfigs: [appConfig],
            urlConfigs: [urlConfig],
            isAIEnhancementEnabled: true,
            selectedPromptId: promptID,
            selectedTranscriptionModelName: "ggml-base",
            selectedLanguage: "fr",
            useScreenCapture: true,
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeAll,
            lowercaseTranscription: true,
            selectedAIProvider: "openai",
            selectedAIModel: "gpt-4o",
            autoSendKey: .commandEnter,
            isDefault: true
        )

        let config = VoiceInkPowerModePolicy.configuration(from: draft, mode: .add)

        XCTAssertEqual(config.id, id)
        XCTAssertEqual(config.name, "Writing")
        XCTAssertEqual(config.emoji, "W")
        XCTAssertEqual(config.appConfigs, [appConfig])
        XCTAssertEqual(config.urlConfigs, [urlConfig])
        XCTAssertTrue(config.isAIEnhancementEnabled)
        XCTAssertEqual(config.selectedPrompt, promptID.uuidString)
        XCTAssertEqual(config.selectedTranscriptionModelName, "ggml-base")
        XCTAssertEqual(config.selectedLanguage, "fr")
        XCTAssertTrue(config.useScreenCapture)
        XCTAssertTrue(config.isTextFormattingEnabled)
        XCTAssertEqual(config.punctuationCleanupMode, .removeAll)
        XCTAssertTrue(config.lowercaseTranscription)
        XCTAssertEqual(config.selectedAIProvider, "openai")
        XCTAssertEqual(config.selectedAIModel, "gpt-4o")
        XCTAssertEqual(config.autoSendKey, .commandEnter)
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.isDefault)
    }

    func testConfigurationDraftBuildsEditConfigurationWithoutReplacingIdentityOrEnablement() {
        let existingID = UUID()
        let existing = PowerModeConfig(
            id: existingID,
            name: "Old",
            emoji: "O",
            appConfigs: [VoiceInkPowerModeAppConfig(bundleIdentifier: "com.example.Old", appName: "Old")],
            urlConfigs: [VoiceInkPowerModeURLConfig(url: "old.example.com")],
            isAIEnhancementEnabled: true,
            selectedPrompt: "old-prompt",
            selectedTranscriptionModelName: "old-model",
            selectedLanguage: "en",
            useScreenCapture: true,
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeAll,
            lowercaseTranscription: true,
            selectedAIProvider: "old-provider",
            selectedAIModel: "old-model",
            autoSendKey: .enter,
            isEnabled: false,
            isDefault: false
        )
        let draft = VoiceInkPowerModeConfigurationDraft(
            id: UUID(),
            name: "New",
            emoji: "N",
            isAIEnhancementEnabled: false,
            selectedPromptId: nil,
            selectedTranscriptionModelName: nil,
            selectedLanguage: nil,
            useScreenCapture: false,
            isTextFormattingEnabled: false,
            punctuationCleanupMode: .keep,
            lowercaseTranscription: false,
            selectedAIProvider: nil,
            selectedAIModel: nil,
            autoSendKey: .none,
            isDefault: true
        )

        let config = VoiceInkPowerModePolicy.configuration(from: draft, mode: .edit(existing))

        XCTAssertEqual(config.id, existingID)
        XCTAssertEqual(config.name, "New")
        XCTAssertEqual(config.emoji, "N")
        XCTAssertNil(config.appConfigs)
        XCTAssertNil(config.urlConfigs)
        XCTAssertFalse(config.isAIEnhancementEnabled)
        XCTAssertNil(config.selectedPrompt)
        XCTAssertNil(config.selectedTranscriptionModelName)
        XCTAssertNil(config.selectedLanguage)
        XCTAssertFalse(config.useScreenCapture)
        XCTAssertFalse(config.isTextFormattingEnabled)
        XCTAssertEqual(config.punctuationCleanupMode, .keep)
        XCTAssertFalse(config.lowercaseTranscription)
        XCTAssertNil(config.selectedAIProvider)
        XCTAssertNil(config.selectedAIModel)
        XCTAssertEqual(config.autoSendKey, .none)
        XCTAssertFalse(config.isEnabled)
        XCTAssertTrue(config.isDefault)
    }

    func testPowerModeConfigurationFormStateBuildsAddDefaults() {
        let id = UUID()
        let formState = VoiceInkPowerModeConfigurationMode.add.formState(
            existingConfigurations: [],
            newID: id,
            selectedAIProvider: "Groq"
        )

        XCTAssertEqual(formState.id, id)
        XCTAssertEqual(formState.name, "")
        XCTAssertEqual(formState.emoji, "✏️")
        XCTAssertEqual(formState.appConfigs, [])
        XCTAssertEqual(formState.urlConfigs, [])
        XCTAssertFalse(formState.isAIEnhancementEnabled)
        XCTAssertNil(formState.selectedPromptId)
        XCTAssertNil(formState.selectedTranscriptionModelName)
        XCTAssertNil(formState.selectedLanguage)
        XCTAssertFalse(formState.useScreenCapture)
        XCTAssertFalse(formState.isTextFormattingEnabled)
        XCTAssertEqual(formState.punctuationCleanupMode, .keep)
        XCTAssertFalse(formState.lowercaseTranscription)
        XCTAssertEqual(formState.selectedAIProvider, "Groq")
        XCTAssertNil(formState.selectedAIModel)
        XCTAssertEqual(formState.autoSendKey, .none)
        XCTAssertFalse(formState.isDefault)
        XCTAssertFalse(formState.isTranscriptFormattingExpanded)
    }

    func testPowerModeConfigurationFormStateBuildsEditStateFromLatestConfig() {
        let id = UUID()
        let promptID = UUID()
        let oldConfig = PowerModeConfig(
            id: id,
            name: "Old",
            emoji: "O",
            isAIEnhancementEnabled: false
        )
        let appConfig = VoiceInkPowerModeAppConfig(
            bundleIdentifier: "com.example.App",
            appName: "Example"
        )
        let urlConfig = VoiceInkPowerModeURLConfig(url: "example.com")
        let latestConfig = PowerModeConfig(
            id: id,
            name: "Latest",
            emoji: "L",
            appConfigs: [appConfig],
            urlConfigs: [urlConfig],
            isAIEnhancementEnabled: true,
            selectedPrompt: promptID.uuidString,
            selectedTranscriptionModelName: "ggml-base",
            selectedLanguage: "fr",
            useScreenCapture: true,
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeTrailingPeriod,
            lowercaseTranscription: true,
            selectedAIProvider: "OpenAI",
            selectedAIModel: "gpt-4o",
            autoSendKey: .shiftEnter,
            isDefault: true
        )

        let formState = VoiceInkPowerModeConfigurationMode.edit(oldConfig).formState(
            existingConfigurations: [latestConfig],
            selectedAIProvider: "Ignored"
        )

        XCTAssertEqual(formState.id, id)
        XCTAssertEqual(formState.name, "Latest")
        XCTAssertEqual(formState.emoji, "L")
        XCTAssertEqual(formState.appConfigs, [appConfig])
        XCTAssertEqual(formState.urlConfigs, [urlConfig])
        XCTAssertTrue(formState.isAIEnhancementEnabled)
        XCTAssertEqual(formState.selectedPromptId, promptID)
        XCTAssertEqual(formState.selectedTranscriptionModelName, "ggml-base")
        XCTAssertEqual(formState.selectedLanguage, "fr")
        XCTAssertTrue(formState.useScreenCapture)
        XCTAssertTrue(formState.isTextFormattingEnabled)
        XCTAssertEqual(formState.punctuationCleanupMode, .removeTrailingPeriod)
        XCTAssertTrue(formState.lowercaseTranscription)
        XCTAssertEqual(formState.selectedAIProvider, "OpenAI")
        XCTAssertEqual(formState.selectedAIModel, "gpt-4o")
        XCTAssertEqual(formState.autoSendKey, .shiftEnter)
        XCTAssertTrue(formState.isDefault)
        XCTAssertTrue(formState.isTranscriptFormattingExpanded)
    }

    func testPowerModeConfigurationFormStateNormalizesMissingEditCollectionsAndCollapsedFormatting() {
        let id = UUID()
        let config = PowerModeConfig(
            id: id,
            name: "Plain",
            emoji: "P",
            appConfigs: nil,
            urlConfigs: nil,
            isAIEnhancementEnabled: false,
            isTextFormattingEnabled: false,
            punctuationCleanupMode: .keep,
            lowercaseTranscription: false
        )

        let formState = VoiceInkPowerModeConfigurationMode.edit(config).formState(existingConfigurations: [])

        XCTAssertEqual(formState.appConfigs, [])
        XCTAssertEqual(formState.urlConfigs, [])
        XCTAssertFalse(formState.isTranscriptFormattingExpanded)
    }

    func testPowerModeEnhancementSelectionFillsMissingProviderAndModel() {
        let nilSelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil
        )
        let emptyModelSelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "OpenAI",
            selectedAIModel: ""
        )
        let existingSelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "OpenAI",
            selectedAIModel: "gpt-4o"
        )

        XCTAssertEqual(
            nilSelection.fillingMissingProviderAndModel(
                currentProvider: .groq,
                currentModel: "llama-3.3",
                treatsEmptyModelAsMissing: false
            ),
            VoiceInkPowerModeEnhancementSelection(
                selectedPromptId: nil,
                selectedAIProvider: "Groq",
                selectedAIModel: "llama-3.3"
            )
        )
        XCTAssertEqual(
            emptyModelSelection.fillingMissingProviderAndModel(
                currentProvider: .groq,
                currentModel: "llama-3.3",
                treatsEmptyModelAsMissing: false
            ).selectedAIModel,
            ""
        )
        XCTAssertEqual(
            emptyModelSelection.fillingMissingProviderAndModel(
                currentProvider: .groq,
                currentModel: "llama-3.3",
                treatsEmptyModelAsMissing: true
            ).selectedAIModel,
            "llama-3.3"
        )
        XCTAssertEqual(
            existingSelection.fillingMissingProviderAndModel(
                currentProvider: .groq,
                currentModel: "llama-3.3",
                treatsEmptyModelAsMissing: true
            ),
            existingSelection
        )
    }

    func testPowerModeEnhancementSelectionSelectsPromptOnlyWhenMissing() {
        let promptID = UUID()
        let existingPromptID = UUID()
        let prompt = VoiceInkCustomPrompt(id: promptID, title: "Rewrite", promptText: "Rewrite this")

        XCTAssertEqual(
            VoiceInkPowerModeEnhancementSelection(
                selectedPromptId: nil,
                selectedAIProvider: "Groq",
                selectedAIModel: "llama-3.3"
            )
            .selectingPromptAfterEnabling(prompts: [prompt])
            .selectedPromptId,
            promptID
        )
        XCTAssertEqual(
            VoiceInkPowerModeEnhancementSelection(
                selectedPromptId: existingPromptID,
                selectedAIProvider: "Groq",
                selectedAIModel: "llama-3.3"
            )
            .selectingPromptAfterEnabling(prompts: [prompt])
            .selectedPromptId,
            existingPromptID
        )
        XCTAssertNil(
            VoiceInkPowerModeEnhancementSelection(
                selectedPromptId: nil,
                selectedAIProvider: "Groq",
                selectedAIModel: "llama-3.3"
            )
            .selectingPromptAfterEnabling(prompts: [])
            .selectedPromptId
        )
    }

    func testPowerModeEnhancementSelectionResolvesProviderPickerAndModelOptions() {
        let missingSelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil
        )
        let legacySelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "GROQ",
            selectedAIModel: nil
        )
        let invalidSelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "MissingProvider",
            selectedAIModel: nil
        )

        XCTAssertEqual(missingSelection.resolvedProviderForPicker(currentProvider: .gemini), .gemini)
        XCTAssertEqual(missingSelection.selectedProviderForModelOptions(currentProvider: .gemini), .gemini)
        XCTAssertEqual(legacySelection.resolvedProviderForPicker(currentProvider: .gemini), .groq)
        XCTAssertEqual(legacySelection.selectedProviderForModelOptions(currentProvider: .gemini), .groq)
        XCTAssertEqual(invalidSelection.resolvedProviderForPicker(currentProvider: .gemini), .gemini)
        XCTAssertNil(invalidSelection.selectedProviderForModelOptions(currentProvider: .gemini))
    }

    func testPowerModeEnhancementSelectionUpdatesProviderAndModelSelection() {
        let selection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: UUID(),
            selectedAIProvider: "Groq",
            selectedAIModel: "llama-3.3"
        )
        let emptyModelSelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "Groq",
            selectedAIModel: ""
        )
        let nilModelSelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "Groq",
            selectedAIModel: nil
        )
        let invalidProviderSelection = VoiceInkPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "MissingProvider",
            selectedAIModel: "kept"
        )

        XCTAssertEqual(selection.selectingProvider(.openAI).selectedAIProvider, "OpenAI")
        XCTAssertNil(selection.selectingProvider(.openAI).selectedAIModel)
        XCTAssertEqual(
            selection.selectingProvider(.openAI)
                .selectingDefaultModelForSelectedProvider { provider in "\(provider.rawValue)-default" }
                .selectedAIModel,
            "OpenAI-default"
        )
        XCTAssertEqual(
            invalidProviderSelection.selectingDefaultModelForSelectedProvider { provider in "\(provider.rawValue)-default" },
            invalidProviderSelection
        )
        XCTAssertEqual(selection.selectedModelForPicker(currentModel: "current"), "llama-3.3")
        XCTAssertEqual(emptyModelSelection.selectedModelForPicker(currentModel: "current"), "current")
        XCTAssertEqual(nilModelSelection.selectedModelForPicker(currentModel: "current"), "current")
        XCTAssertEqual(selection.selectingModel("gpt-4.1").selectedAIModel, "gpt-4.1")
    }

    func testPowerModeTranscriptionModelFactsResolveLanguageControl() {
        XCTAssertEqual(
            transcriptionModelFacts(disablesLanguageSelection: true, isMultilingual: true).languageControl,
            .disabledAutodetect
        )
        XCTAssertEqual(
            transcriptionModelFacts(disablesLanguageSelection: false, isMultilingual: true).languageControl,
            .picker
        )
        XCTAssertEqual(
            transcriptionModelFacts(disablesLanguageSelection: false, isMultilingual: false).languageControl,
            .hiddenDefault
        )
    }

    func testPowerModeTranscriptionSelectionRepairsModelAndLanguageState() {
        let selection = VoiceInkPowerModeTranscriptionSelection(
            selectedModelName: nil,
            selectedLanguage: nil
        )
        let selectedLanguage = VoiceInkPowerModeTranscriptionSelection(
            selectedModelName: "base",
            selectedLanguage: "fr"
        )

        XCTAssertEqual(selection.selectedModelNameForPicker(currentModelName: "current"), "current")
        XCTAssertEqual(selection.selectingModelName("large").selectedModelName, "large")
        XCTAssertEqual(selection.selectedLanguageForPicker(storedLanguage: "de"), "de")
        XCTAssertEqual(selection.selectingDefaultLanguageIfMissing("en").selectedLanguage, "en")
        XCTAssertEqual(selectedLanguage.selectingDefaultLanguageIfMissing("en").selectedLanguage, "fr")
        XCTAssertEqual(selectedLanguage.selectingAutodetectLanguage().selectedLanguage, VoiceInkLanguageCatalog.autoDetectCode)
        XCTAssertEqual(
            selectedLanguage.selectingCompatibleLanguage(
                for: transcriptionModelFacts(disablesLanguageSelection: true),
                storedLanguage: "de"
            ).selectedLanguage,
            VoiceInkLanguageCatalog.autoDetectCode
        )
        XCTAssertEqual(
            selection.selectingCompatibleLanguage(
                for: transcriptionModelFacts(
                    languageOptions: ["en": "English", "fr": "French"]
                ),
                storedLanguage: "fr"
            ).selectedLanguage,
            "fr"
        )
        XCTAssertEqual(
            selectedLanguage.selectingCompatibleLanguage(
                for: transcriptionModelFacts(
                    isMultilingual: false,
                    languageOptions: VoiceInkLanguageCatalog.englishOnly
                ),
                storedLanguage: "de"
            ).selectedLanguage,
            "en"
        )
        XCTAssertEqual(
            selection.selectingCompatibleLanguage(
                for: transcriptionModelFacts(
                    languageOptions: ["en-US": "English (United States)"],
                    prefersNativeAppleEnglish: true
                ),
                storedLanguage: "de"
            ).selectedLanguage,
            "en-US"
        )
    }

    func testPowerModeLanguageApplicationPlanSkipsMissingLanguage() {
        let plan = VoiceInkPowerModeLanguageApplicationPlan.plan(
            selectedLanguage: nil,
            preferredModelName: "base",
            currentModelName: "current",
            availableModels: [
                transcriptionModelFacts(name: "base")
            ]
        )

        XCTAssertNil(plan.languageToSave)
        XCTAssertFalse(plan.shouldPostLanguageDidChange)
    }

    func testPowerModeLanguageApplicationPlanSavesRawLanguageWithoutModel() {
        let plan = VoiceInkPowerModeLanguageApplicationPlan.plan(
            selectedLanguage: "fr",
            preferredModelName: nil,
            currentModelName: nil,
            availableModels: []
        )

        XCTAssertEqual(plan.languageToSave, "fr")
        XCTAssertTrue(plan.shouldPostLanguageDidChange)
    }

    func testPowerModeLanguageApplicationPlanUsesPreferredModelBeforeCurrentModel() {
        let plan = VoiceInkPowerModeLanguageApplicationPlan.plan(
            selectedLanguage: "fr",
            preferredModelName: "english-only",
            currentModelName: "multilingual",
            availableModels: [
                transcriptionModelFacts(
                    name: "multilingual",
                    languageOptions: ["en": "English", "fr": "French"]
                ),
                transcriptionModelFacts(
                    name: "english-only",
                    isMultilingual: false,
                    languageOptions: VoiceInkLanguageCatalog.englishOnly
                )
            ]
        )

        XCTAssertEqual(plan.languageToSave, "en")
        XCTAssertTrue(plan.shouldPostLanguageDidChange)
    }

    func testPowerModeLanguageApplicationPlanFallsBackToCurrentModelWhenPreferredIsMissing() {
        let plan = VoiceInkPowerModeLanguageApplicationPlan.plan(
            selectedLanguage: "de",
            preferredModelName: "missing",
            currentModelName: "native",
            availableModels: [
                transcriptionModelFacts(
                    name: "native",
                    languageOptions: ["en-US": "English (United States)"],
                    prefersNativeAppleEnglish: true
                )
            ]
        )

        XCTAssertEqual(plan.languageToSave, "en-US")
        XCTAssertTrue(plan.shouldPostLanguageDidChange)
    }

    func testPowerModeTranscriptionModelResourcePlanSkipsMissingUnchangedSelection() {
        let availableModels = [
            transcriptionModelResourceFacts(name: "base", loadsLocalWhisperModel: true)
        ]
        let expectedNoChange = VoiceInkPowerModeTranscriptionModelResourcePlan(
            selectedModelName: nil,
            action: .none
        )

        XCTAssertEqual(
            VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
                selectedModelName: nil,
                currentModelName: "current",
                availableModels: availableModels,
                availableLocalModelNames: []
            ),
            expectedNoChange
        )
        XCTAssertEqual(
            VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
                selectedModelName: "missing",
                currentModelName: "current",
                availableModels: availableModels,
                availableLocalModelNames: ["missing"]
            ),
            expectedNoChange
        )
        XCTAssertEqual(
            VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
                selectedModelName: "base",
                currentModelName: "base",
                availableModels: availableModels,
                availableLocalModelNames: ["base"]
            ),
            expectedNoChange
        )
        XCTAssertFalse(expectedNoChange.shouldChangeModel)
    }

    func testPowerModeTranscriptionModelResourcePlanCleansNonWhisperModels() {
        let plan = VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "nova-3",
            currentModelName: "base",
            availableModels: [
                transcriptionModelResourceFacts(name: "nova-3", loadsLocalWhisperModel: false)
            ],
            availableLocalModelNames: []
        )

        XCTAssertTrue(plan.shouldChangeModel)
        XCTAssertEqual(plan.selectedModelName, "nova-3")
        XCTAssertEqual(plan.action, .cleanupOnly)
    }

    func testPowerModeTranscriptionModelResourcePlanLoadsDownloadedLocalWhisperModel() {
        let plan = VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "base",
            currentModelName: "nova-3",
            availableModels: [
                transcriptionModelResourceFacts(name: "base", loadsLocalWhisperModel: true)
            ],
            availableLocalModelNames: ["base"]
        )

        XCTAssertTrue(plan.shouldChangeModel)
        XCTAssertEqual(plan.selectedModelName, "base")
        XCTAssertEqual(plan.action, .cleanupAndLoadLocalModel("base"))
    }

    func testPowerModeTranscriptionModelResourcePlanCleansMissingLocalWhisperFile() {
        let plan = VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "base",
            currentModelName: "nova-3",
            availableModels: [
                transcriptionModelResourceFacts(name: "base", loadsLocalWhisperModel: true)
            ],
            availableLocalModelNames: []
        )

        XCTAssertTrue(plan.shouldChangeModel)
        XCTAssertEqual(plan.selectedModelName, "base")
        XCTAssertEqual(plan.action, .cleanupOnly)
    }

    func testPowerModeApplicationStatePreservesStoredShapeAndCleanupKeys() throws {
        let state = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: true,
            selectedPromptId: "prompt-id",
            selectedAIProvider: "openai",
            selectedAIModel: "gpt-4o",
            selectedLanguage: "en",
            transcriptionModelName: "ggml-base",
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeTrailingPeriod,
            removePunctuation: false,
            lowercaseTranscription: true
        )

        let object = try jsonObject(from: state)

        XCTAssertEqual(object["isEnhancementEnabled"] as? Bool, true)
        XCTAssertEqual(object["useScreenCaptureContext"] as? Bool, true)
        XCTAssertEqual(object["selectedPromptId"] as? String, "prompt-id")
        XCTAssertEqual(object["selectedAIProvider"] as? String, "openai")
        XCTAssertEqual(object["selectedAIModel"] as? String, "gpt-4o")
        XCTAssertEqual(object["selectedLanguage"] as? String, "en")
        XCTAssertEqual(object["transcriptionModelName"] as? String, "ggml-base")
        XCTAssertEqual(object["isTextFormattingEnabled"] as? Bool, true)
        XCTAssertEqual(object["punctuationCleanupMode"] as? String, PunctuationCleanupMode.removeTrailingPeriod.rawValue)
        XCTAssertEqual(object["removePunctuation"] as? Bool, false)
        XCTAssertEqual(object["lowercaseTranscription"] as? Bool, true)
        XCTAssertEqual(
            try JSONDecoder().decode(VoiceInkPowerModeApplicationState.self, from: JSONEncoder().encode(state)),
            state
        )
    }

    func testPowerModeApplicationStateBuildsSnapshotFromPromptAndCleanupSettings() {
        let promptID = UUID()
        let cleanupSettings = VoiceInkTranscriptionCleanupSettings(
            punctuationMode: .removeAll,
            isTextFormattingEnabled: true,
            lowercaseTranscription: true,
            removeFillerWords: false
        )

        let state = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            selectedPromptId: promptID,
            selectedAIProvider: "openai",
            selectedAIModel: "gpt-4o",
            selectedLanguage: "en",
            transcriptionModelName: "ggml-base",
            cleanupSettings: cleanupSettings
        )

        XCTAssertTrue(state.isEnhancementEnabled)
        XCTAssertFalse(state.useScreenCaptureContext)
        XCTAssertEqual(state.selectedPromptId, promptID.uuidString)
        XCTAssertEqual(state.selectedAIProvider, "openai")
        XCTAssertEqual(state.selectedAIModel, "gpt-4o")
        XCTAssertEqual(state.selectedLanguage, "en")
        XCTAssertEqual(state.transcriptionModelName, "ggml-base")
        XCTAssertEqual(state.isTextFormattingEnabled, true)
        XCTAssertEqual(state.punctuationCleanupMode, .removeAll)
        XCTAssertEqual(state.removePunctuation, true)
        XCTAssertEqual(state.lowercaseTranscription, true)
    }

    func testPowerModeApplicationStateExposesRestoreReadyPromptUUID() {
        let promptID = UUID()
        let validState = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            selectedPromptId: promptID.uuidString,
            selectedAIProvider: "GROQ"
        )
        let invalidState = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            selectedPromptId: "not-a-uuid",
            selectedAIProvider: "MissingProvider"
        )

        XCTAssertEqual(validState.selectedPromptUUID, promptID)
        XCTAssertEqual(validState.selectedAIProviderKind, .groq)
        XCTAssertNil(invalidState.selectedPromptUUID)
        XCTAssertNil(invalidState.selectedAIProviderKind)
    }

    func testPowerModeApplicationStateCleanupRestorePreservesLegacyPunctuationFallback() {
        let explicitModeState = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeTrailingPeriod,
            removePunctuation: true,
            lowercaseTranscription: false
        )
        let legacyRemoveAllState = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            removePunctuation: true
        )
        let legacyKeepState = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            removePunctuation: false
        )

        XCTAssertEqual(
            explicitModeState.cleanupRestore,
            VoiceInkPowerModeCleanupRestore(
                isTextFormattingEnabled: true,
                punctuationMode: .removeTrailingPeriod,
                lowercaseTranscription: false
            )
        )
        XCTAssertEqual(legacyRemoveAllState.cleanupRestore.punctuationMode, .removeAll)
        XCTAssertEqual(legacyKeepState.cleanupRestore.punctuationMode, .keep)
    }

    func testPowerModeApplicationStateDecodesLegacyRemovePunctuation() throws {
        let data = Data("""
        {
          "isEnhancementEnabled": false,
          "useScreenCaptureContext": true,
          "removePunctuation": true
        }
        """.utf8)

        let state = try JSONDecoder().decode(VoiceInkPowerModeApplicationState.self, from: data)

        XCTAssertFalse(state.isEnhancementEnabled)
        XCTAssertTrue(state.useScreenCaptureContext)
        XCTAssertNil(state.selectedPromptId)
        XCTAssertNil(state.selectedAIProvider)
        XCTAssertNil(state.selectedAIModel)
        XCTAssertNil(state.selectedLanguage)
        XCTAssertNil(state.transcriptionModelName)
        XCTAssertNil(state.isTextFormattingEnabled)
        XCTAssertEqual(state.punctuationCleanupMode, .removeAll)
        XCTAssertEqual(state.removePunctuation, true)
        XCTAssertNil(state.lowercaseTranscription)
    }

    func testPowerModeConfigBuildsPreferenceApplicationWhenEnhancementIsEnabled() {
        let promptID = UUID()
        let config = PowerModeConfig(
            name: "Enhanced",
            emoji: "E",
            isAIEnhancementEnabled: true,
            selectedPrompt: promptID.uuidString,
            useScreenCapture: true,
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeTrailingPeriod,
            lowercaseTranscription: true,
            selectedAIProvider: "GROQ",
            selectedAIModel: "llama-3.3"
        )

        let application = config.powerModePreferenceApplication

        XCTAssertTrue(application.isEnhancementEnabled)
        XCTAssertTrue(application.useScreenCaptureContext)
        XCTAssertEqual(application.promptSelection, .set(promptID))
        XCTAssertEqual(application.selectedAIProvider, .groq)
        XCTAssertEqual(application.selectedAIModel, "llama-3.3")
        XCTAssertEqual(
            application.cleanupRestore,
            VoiceInkPowerModeCleanupRestore(
                isTextFormattingEnabled: true,
                punctuationMode: .removeTrailingPeriod,
                lowercaseTranscription: true
            )
        )
    }

    func testPowerModeConfigPreferenceApplicationLeavesEnhancementDetailsWhenDisabled() {
        let promptID = UUID()
        let config = PowerModeConfig(
            name: "Disabled",
            emoji: "D",
            isAIEnhancementEnabled: false,
            selectedPrompt: promptID.uuidString,
            useScreenCapture: true,
            selectedAIProvider: "GROQ",
            selectedAIModel: "llama-3.3"
        )

        let application = config.powerModePreferenceApplication

        XCTAssertFalse(application.isEnhancementEnabled)
        XCTAssertTrue(application.useScreenCaptureContext)
        XCTAssertEqual(application.promptSelection, .leaveUnchanged)
        XCTAssertNil(application.selectedAIProvider)
        XCTAssertNil(application.selectedAIModel)
        XCTAssertEqual(application.cleanupRestore.punctuationMode, .keep)
    }

    func testPowerModeApplicationStateBuildsPreferenceRestoreApplication() {
        let promptID = UUID()
        let state = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: true,
            selectedPromptId: promptID.uuidString,
            selectedAIProvider: "GROQ",
            selectedAIModel: "llama-3.3",
            isTextFormattingEnabled: false,
            punctuationCleanupMode: .removeAll,
            lowercaseTranscription: true
        )

        let application = state.powerModePreferenceRestore

        XCTAssertTrue(application.isEnhancementEnabled)
        XCTAssertTrue(application.useScreenCaptureContext)
        XCTAssertEqual(application.promptSelection, .set(promptID))
        XCTAssertEqual(application.selectedAIProvider, .groq)
        XCTAssertEqual(application.selectedAIModel, "llama-3.3")
        XCTAssertEqual(
            application.cleanupRestore,
            VoiceInkPowerModeCleanupRestore(
                isTextFormattingEnabled: false,
                punctuationMode: .removeAll,
                lowercaseTranscription: true
            )
        )
    }

    func testPowerModeApplicationStatePreferenceRestoreClearsInvalidPromptAndKeepsLegacyCleanup() {
        let state = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: false,
            useScreenCaptureContext: false,
            selectedPromptId: "not-a-uuid",
            selectedAIProvider: "MissingProvider",
            removePunctuation: true
        )

        let application = state.powerModePreferenceRestore

        XCTAssertFalse(application.isEnhancementEnabled)
        XCTAssertFalse(application.useScreenCaptureContext)
        XCTAssertEqual(application.promptSelection, .set(nil))
        XCTAssertNil(application.selectedAIProvider)
        XCTAssertNil(application.selectedAIModel)
        XCTAssertEqual(application.cleanupRestore.punctuationMode, .removeAll)
    }

    func testPowerModeSessionPreservesStoredShapeAndOriginalState() throws {
        let id = UUID()
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let originalState = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            selectedPromptId: "prompt-id",
            selectedAIProvider: "anthropic",
            selectedAIModel: "claude",
            selectedLanguage: "auto",
            transcriptionModelName: "ggml-small",
            isTextFormattingEnabled: false,
            punctuationCleanupMode: .keep,
            removePunctuation: false,
            lowercaseTranscription: false
        )
        let session = VoiceInkPowerModeSession(
            id: id,
            startTime: startTime,
            originalState: originalState
        )

        let object = try jsonObject(from: session)
        let originalStateObject = try XCTUnwrap(object["originalState"] as? [String: Any])
        let encodedStartTime = try XCTUnwrap(object["startTime"] as? Double)

        XCTAssertEqual(object["id"] as? String, id.uuidString)
        XCTAssertEqual(encodedStartTime, startTime.timeIntervalSinceReferenceDate, accuracy: 0.001)
        XCTAssertEqual(originalStateObject["selectedPromptId"] as? String, "prompt-id")
        XCTAssertEqual(originalStateObject["punctuationCleanupMode"] as? String, PunctuationCleanupMode.keep.rawValue)

        let decoded = try JSONDecoder().decode(VoiceInkPowerModeSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.startTime.timeIntervalSinceReferenceDate, startTime.timeIntervalSinceReferenceDate, accuracy: 0.001)
        XCTAssertEqual(decoded.originalState, originalState)
    }

    func testAutoSendKeyPreservesStoredValuesPickerOrderAndLabels() {
        XCTAssertEqual(
            VoiceInkAutoSendKey.allCases,
            [.none, .enter, .shiftEnter, .commandEnter]
        )
        XCTAssertEqual(VoiceInkAutoSendKey.none.rawValue, "none")
        XCTAssertEqual(VoiceInkAutoSendKey.enter.rawValue, "enter")
        XCTAssertEqual(VoiceInkAutoSendKey.shiftEnter.rawValue, "shiftEnter")
        XCTAssertEqual(VoiceInkAutoSendKey.commandEnter.rawValue, "commandEnter")
        XCTAssertEqual(VoiceInkAutoSendKey.none.displayName, "None")
        XCTAssertEqual(VoiceInkAutoSendKey.enter.displayName, "Return (⏎)")
        XCTAssertEqual(VoiceInkAutoSendKey.shiftEnter.displayName, "Shift + Return (⇧⏎)")
        XCTAssertEqual(VoiceInkAutoSendKey.commandEnter.displayName, "Command + Return (⌘⏎)")
    }

    func testAutoSendKeyEnablementAndCodableShape() throws {
        XCTAssertFalse(VoiceInkAutoSendKey.none.isEnabled)
        XCTAssertTrue(VoiceInkAutoSendKey.enter.isEnabled)
        XCTAssertTrue(VoiceInkAutoSendKey.shiftEnter.isEnabled)
        XCTAssertTrue(VoiceInkAutoSendKey.commandEnter.isEnabled)

        let data = try JSONEncoder().encode(VoiceInkAutoSendKey.commandEnter)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"commandEnter\"")
        XCTAssertEqual(
            try JSONDecoder().decode(VoiceInkAutoSendKey.self, from: data),
            .commandEnter
        )
    }

    func testNormalizedWebsiteURLPreservesExistingMacOSCleanURLPolicy() {
        XCTAssertEqual(
            VoiceInkPowerModePolicy.normalizedWebsiteURL(" HTTP://WWW.Example.COM/path "),
            "example.com/path"
        )
        XCTAssertEqual(
            VoiceInkPowerModePolicy.normalizedWebsiteURL("https://docs.example.com"),
            "docs.example.com"
        )
    }

    func testWebsiteConfigForFormInputReturnsNilForRawEmptyInput() {
        XCTAssertNil(VoiceInkPowerModePolicy.websiteConfigForFormInput(""))
    }

    func testWebsiteConfigForFormInputNormalizesNonEmptyInput() throws {
        let config = try XCTUnwrap(
            VoiceInkPowerModePolicy.websiteConfigForFormInput(" HTTPS://WWW.Example.COM/docs ")
        )

        XCTAssertEqual(config.url, "example.com/docs")
    }

    func testWebsiteConfigForFormInputPreservesWhitespaceOnlyMacOSBehavior() throws {
        let config = try XCTUnwrap(
            VoiceInkPowerModePolicy.websiteConfigForFormInput("   ")
        )

        XCTAssertEqual(config.url, "")
    }

    func testConfigurationNameSaveabilityPreservesRawEmptyMacOSRule() {
        XCTAssertFalse(VoiceInkPowerModePolicy.canSaveConfigurationName(""))
        XCTAssertTrue(VoiceInkPowerModePolicy.canSaveConfigurationName("   "))
        XCTAssertTrue(VoiceInkPowerModePolicy.canSaveConfigurationName("Writing"))
    }

    func testMatchingWebsiteRuleUsesEnabledOrderAndSubstringPolicy() {
        let disabled = rule(
            name: "Disabled",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "docs.example.com")],
            isEnabled: false
        )
        let firstEnabled = rule(
            name: "Docs",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com/docs")]
        )
        let secondEnabled = rule(
            name: "Example",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )

        let match = VoiceInkPowerModePolicy.matchingRule(
            forWebsiteURL: "https://www.example.com/docs/new",
            in: [disabled, firstEnabled, secondEnabled]
        )

        XCTAssertEqual(match?.id, firstEnabled.id)
    }

    func testMatchingWebsiteRulePreservesEmptyRuleURLRejection() {
        let emptyWebsiteRule = rule(
            name: "Empty",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "")]
        )

        XCTAssertNil(
            VoiceInkPowerModePolicy.matchingRule(
                forWebsiteURL: "https://example.com",
                in: [emptyWebsiteRule]
            )
        )
    }

    func testMatchingAppRuleUsesExactEnabledBundleIdentifier() {
        let disabled = rule(
            name: "Disabled",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")],
            isEnabled: false
        )
        let enabled = rule(
            name: "Enabled",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")]
        )

        XCTAssertEqual(
            VoiceInkPowerModePolicy.matchingRule(
                forAppBundleIdentifier: "com.example.App",
                in: [disabled, enabled]
            )?.id,
            enabled.id
        )
    }

    func testDefaultAndRulePresenceRequireEnabledRules() {
        let disabledDefault = rule(name: "Disabled", isEnabled: false, isDefault: true)
        let website = rule(
            name: "Website",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )
        let app = rule(
            name: "App",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")]
        )
        let enabledDefault = rule(name: "Default", isDefault: true)

        XCTAssertTrue(VoiceInkPowerModePolicy.hasEnabledAutomaticRules(in: [disabledDefault, app]))
        XCTAssertFalse(VoiceInkPowerModePolicy.hasEnabledAutomaticRules(in: [disabledDefault]))
        XCTAssertTrue(VoiceInkPowerModePolicy.hasEnabledWebsiteRules(in: [disabledDefault, website]))
        XCTAssertFalse(VoiceInkPowerModePolicy.hasEnabledWebsiteRules(in: [disabledDefault, app]))
        XCTAssertEqual(VoiceInkPowerModePolicy.defaultRule(in: [disabledDefault, enabledDefault])?.id, enabledDefault.id)
    }

    func testPowerModeConfigurationListQueriesUseSharedRulePolicy() {
        let disabledDefault = config(name: "Disabled", emoji: "D", isEnabled: false, isDefault: true)
        let websiteConfig = config(
            name: "Website",
            emoji: "W",
            urlConfigs: [VoiceInkPowerModeURLConfig(url: "example.com/docs")]
        )
        let appConfig = config(
            name: "App",
            emoji: "A",
            appConfigs: [VoiceInkPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "App")]
        )
        let configs = [disabledDefault, websiteConfig, appConfig]

        XCTAssertEqual(configs.powerModeConfiguration(with: appConfig.id)?.id, appConfig.id)
        XCTAssertEqual(configs.enabledPowerModeConfigurations.map(\.id), [websiteConfig.id, appConfig.id])
        XCTAssertEqual(configs.enabledPowerModeConfigurationIds, Set([websiteConfig.id, appConfig.id]))
        XCTAssertTrue(configs.hasPowerModeDefaultConfiguration)
        XCTAssertNil(configs.defaultPowerModeConfiguration)
        XCTAssertTrue(configs.containsPowerModeEmoji("D"))
        XCTAssertFalse(configs.containsPowerModeEmoji("Z"))
        XCTAssertEqual(
            configs.powerModeConfiguration(forWebsiteURL: "https://www.example.com/docs/new")?.id,
            websiteConfig.id
        )
        XCTAssertEqual(
            configs.powerModeConfiguration(forAppBundleIdentifier: "com.example.App")?.id,
            appConfig.id
        )
    }

    func testResolvedPowerModeConfigurationPreservesAutomaticResolutionOrder() {
        let explicitDisabled = config(name: "Explicit", emoji: "E", isEnabled: false)
        let appConfig = config(
            name: "App",
            emoji: "A",
            appConfigs: [VoiceInkPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "App")]
        )
        let defaultConfig = config(name: "Default", emoji: "D", isDefault: true)
        let websiteConfig = config(
            name: "Website",
            emoji: "W",
            urlConfigs: [VoiceInkPowerModeURLConfig(url: "example.com/docs")]
        )
        let configs = [explicitDisabled, appConfig, defaultConfig, websiteConfig]

        XCTAssertEqual(
            configs.resolvedPowerModeConfiguration(explicitID: explicitDisabled.id)?.id,
            explicitDisabled.id
        )
        XCTAssertNil(configs.resolvedPowerModeConfiguration(explicitID: UUID()))
        XCTAssertEqual(
            configs.resolvedPowerModeConfiguration(
                explicitID: UUID(),
                appBundleIdentifier: "com.example.App"
            )?.id,
            appConfig.id
        )
        XCTAssertEqual(
            configs.resolvedPowerModeConfiguration(
                websiteURL: "https://www.example.com/docs/new",
                appBundleIdentifier: "com.example.App"
            )?.id,
            websiteConfig.id
        )
        XCTAssertEqual(
            configs.resolvedPowerModeConfiguration(appBundleIdentifier: "com.example.App")?.id,
            appConfig.id
        )
        XCTAssertEqual(
            configs.resolvedPowerModeConfiguration(appBundleIdentifier: "com.example.Other")?.id,
            defaultConfig.id
        )
        XCTAssertNil(
            [config(name: "Disabled", emoji: "X", isEnabled: false)]
                .resolvedPowerModeConfiguration(appBundleIdentifier: "com.example.App")
        )
    }

    func testPowerModeConfigurationListMutationsPreserveManagerSemantics() throws {
        let firstID = UUID()
        let secondID = UUID()
        var configs = [config(id: firstID, name: "First", emoji: "F")]

        XCTAssertFalse(configs.appendPowerModeConfigurationIfMissing(config(id: firstID, name: "Duplicate", emoji: "D")))
        XCTAssertEqual(configs.map(\.id), [firstID])
        XCTAssertTrue(configs.appendPowerModeConfigurationIfMissing(config(id: secondID, name: "Second", emoji: "S")))
        XCTAssertEqual(configs.map(\.id), [firstID, secondID])

        var updatedSecond = config(id: secondID, name: "Updated", emoji: "U")
        updatedSecond.isEnabled = false
        XCTAssertTrue(configs.updatePowerModeConfiguration(updatedSecond))
        XCTAssertEqual(configs.powerModeConfiguration(with: secondID)?.name, "Updated")
        XCTAssertEqual(configs.enabledPowerModeConfigurationIds, Set([firstID]))
        XCTAssertFalse(configs.updatePowerModeConfiguration(config(name: "Missing", emoji: "M")))

        configs.setPowerModeDefaultConfiguration(id: secondID)
        XCTAssertFalse(try XCTUnwrap(configs.powerModeConfiguration(with: firstID)).isDefault)
        XCTAssertTrue(try XCTUnwrap(configs.powerModeConfiguration(with: secondID)).isDefault)
        configs.setPowerModeDefaultConfiguration(id: UUID())
        XCTAssertFalse(configs.contains { $0.isDefault })

        XCTAssertTrue(configs.setPowerModeConfiguration(id: secondID, isEnabled: true))
        XCTAssertEqual(configs.enabledPowerModeConfigurationIds, Set([firstID, secondID]))
        XCTAssertFalse(configs.setPowerModeConfiguration(id: UUID(), isEnabled: false))

        let appConfig = VoiceInkPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "App")
        let urlConfig = VoiceInkPowerModeURLConfig(url: "example.com")
        XCTAssertTrue(configs.addPowerModeAppConfig(appConfig, toConfigurationID: firstID))
        XCTAssertEqual(configs.powerModeConfiguration(with: firstID)?.appConfigs?.map(\.id), [appConfig.id])
        XCTAssertTrue(configs.removePowerModeAppConfig(id: appConfig.id, fromConfigurationID: firstID))
        XCTAssertEqual(configs.powerModeConfiguration(with: firstID)?.appConfigs?.map(\.id) ?? [], [])
        XCTAssertTrue(configs.addPowerModeURLConfig(urlConfig, toConfigurationID: firstID))
        XCTAssertEqual(configs.powerModeConfiguration(with: firstID)?.urlConfigs?.map(\.id), [urlConfig.id])
        XCTAssertTrue(configs.removePowerModeURLConfig(id: urlConfig.id, fromConfigurationID: firstID))
        XCTAssertEqual(configs.powerModeConfiguration(with: firstID)?.urlConfigs?.map(\.id) ?? [], [])
        XCTAssertFalse(configs.addPowerModeAppConfig(appConfig, toConfigurationID: UUID()))
        XCTAssertFalse(configs.addPowerModeURLConfig(urlConfig, toConfigurationID: UUID()))

        configs.movePowerModeConfigurations(fromOffsets: IndexSet([0]), toOffset: 2)
        XCTAssertEqual(configs.map(\.id), [secondID, firstID])
        configs.movePowerModeConfigurations(fromOffsets: IndexSet([1, 99]), toOffset: 0)
        XCTAssertEqual(configs.map(\.id), [firstID, secondID])

        XCTAssertTrue(configs.removePowerModeConfiguration(with: secondID))
        XCTAssertNil(configs.powerModeConfiguration(with: secondID))
        XCTAssertFalse(configs.removePowerModeConfiguration(with: secondID))
    }

    func testValidationRejectsBlankAndDuplicateNameWithoutNormalizingName() {
        let existing = rule(name: "Writing")
        let blankCandidate = rule(name: " ")
        let duplicateCandidate = rule(name: "Writing")
        let spacedCandidate = rule(name: " Writing ")

        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: blankCandidate,
                mode: .add,
                existing: [existing]
            ),
            [.emptyName]
        )
        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: duplicateCandidate,
                mode: .add,
                existing: [existing]
            ),
            [.duplicateName("Writing")]
        )
        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: spacedCandidate,
                mode: .add,
                existing: [existing]
            ),
            []
        )
    }

    func testValidationSkipsEditedRuleAndReportsDuplicateTriggers() {
        let editedID = UUID()
        let edited = rule(id: editedID, name: "Edited")
        let existing = rule(
            name: "Existing",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Old Name")],
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )
        let candidate = rule(
            id: editedID,
            name: "Candidate",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "New Name")],
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )

        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: candidate,
                mode: .edit(editedID),
                existing: [edited, existing]
            ),
            [
                .duplicateAppTrigger("New Name", "Existing"),
                .duplicateWebsiteTrigger("example.com", "Existing")
            ]
        )
    }

    func testValidationComparesWebsiteDuplicatesByRawStoredURL() {
        let existing = rule(
            name: "Existing",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )
        let normalizedSameCandidate = rule(
            name: "Candidate",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "https://www.example.com")]
        )

        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: normalizedSameCandidate,
                mode: .add,
                existing: [existing]
            ),
            []
        )
    }

    func testConfigurationModePreservesFormTitlesAndSaveModes() {
        let id = UUID()
        let editMode = VoiceInkPowerModeConfigurationMode.edit(
            config(id: id, name: "Writing", emoji: "W")
        )

        XCTAssertTrue(VoiceInkPowerModeConfigurationMode.add.isAdding)
        XCTAssertFalse(editMode.isAdding)
        XCTAssertEqual(VoiceInkPowerModeConfigurationMode.add.title, "Add Power Mode")
        XCTAssertEqual(editMode.title, "Edit Power Mode")
        XCTAssertEqual(VoiceInkPowerModeConfigurationMode.add.saveMode, .add)
        XCTAssertEqual(editMode.saveMode, .edit(id))
    }

    func testConfigurationModePreservesEditIdentityByConfigId() {
        let id = UUID()
        let first = VoiceInkPowerModeConfigurationMode.edit(
            config(id: id, name: "Writing", emoji: "W")
        )
        let renamed = VoiceInkPowerModeConfigurationMode.edit(
            config(id: id, name: "Renamed", emoji: "R")
        )
        let other = VoiceInkPowerModeConfigurationMode.edit(
            config(id: UUID(), name: "Writing", emoji: "W")
        )

        XCTAssertEqual(first, renamed)
        XCTAssertFalse(first == other)
    }

    func testValidationErrorDescriptionsPreserveMacOSAlertText() {
        XCTAssertEqual(
            VoiceInkPowerModeValidationError.emptyName.localizedDescription,
            "Power mode name cannot be empty."
        )
        XCTAssertEqual(
            VoiceInkPowerModeValidationError.duplicateName("Writing").localizedDescription,
            "A power mode with the name 'Writing' already exists."
        )
        XCTAssertEqual(
            VoiceInkPowerModeValidationError.duplicateAppTrigger("Notes", "Writing").localizedDescription,
            "The app 'Notes' is already configured in the 'Writing' power mode."
        )
        XCTAssertEqual(
            VoiceInkPowerModeValidationError.duplicateWebsiteTrigger("example.com", "Writing").localizedDescription,
            "The website 'example.com' is already configured in the 'Writing' power mode."
        )
    }

    private func config(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        appConfigs: [VoiceInkPowerModeAppConfig]? = nil,
        urlConfigs: [VoiceInkPowerModeURLConfig]? = nil,
        isEnabled: Bool = true,
        isDefault: Bool = false
    ) -> PowerModeConfig {
        PowerModeConfig(
            id: id,
            name: name,
            emoji: emoji,
            appConfigs: appConfigs,
            urlConfigs: urlConfigs,
            isAIEnhancementEnabled: false,
            isEnabled: isEnabled,
            isDefault: isDefault
        )
    }

    private func rule(
        id: UUID = UUID(),
        name: String,
        appRules: [VoiceInkPowerModeAppRule] = [],
        websiteRules: [VoiceInkPowerModeWebsiteRule] = [],
        isEnabled: Bool = true,
        isDefault: Bool = false
    ) -> VoiceInkPowerModeRule {
        VoiceInkPowerModeRule(
            id: id,
            name: name,
            appRules: appRules,
            websiteRules: websiteRules,
            isEnabled: isEnabled,
            isDefault: isDefault
        )
    }

    private func transcriptionModelFacts(
        name: String = "model",
        disablesLanguageSelection: Bool = false,
        isMultilingual: Bool = true,
        languageOptions: [String: String] = VoiceInkLanguageCatalog.all,
        prefersNativeAppleEnglish: Bool = false
    ) -> VoiceInkPowerModeTranscriptionModelFacts {
        VoiceInkPowerModeTranscriptionModelFacts(
            name: name,
            disablesLanguageSelection: disablesLanguageSelection,
            isMultilingual: isMultilingual,
            languageOptions: languageOptions,
            prefersNativeAppleEnglish: prefersNativeAppleEnglish
        )
    }

    private func transcriptionModelResourceFacts(
        name: String,
        loadsLocalWhisperModel: Bool
    ) -> VoiceInkPowerModeTranscriptionModelResourceFacts {
        VoiceInkPowerModeTranscriptionModelResourceFacts(
            name: name,
            loadsLocalWhisperModel: loadsLocalWhisperModel
        )
    }

    private func jsonObject<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
