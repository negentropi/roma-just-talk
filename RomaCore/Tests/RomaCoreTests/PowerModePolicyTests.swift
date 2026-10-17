import Foundation
import RomaCore

final class PowerModePolicyTests: XCTestCase {
    func testDisplayNameTrimsAndCombinesEmojiAndName() {
        XCTAssertEqual(RomaPowerModePresentation.displayName(name: " Writing ", emoji: " W "), "W Writing")
        XCTAssertEqual(RomaPowerModePresentation.displayName(name: nil, emoji: " W "), "W")
        XCTAssertEqual(RomaPowerModePresentation.displayName(name: " Writing ", emoji: nil), "Writing")
        XCTAssertEqual(RomaPowerModePresentation.displayName(name: " ", emoji: " "), "")
        XCTAssertEqual(RomaPowerModePresentation.displayName(name: nil, emoji: nil), "")
    }

    func testSelectedLanguageDisplayTextPreservesPowerModeRowFallbacks() {
        XCTAssertEqual(
            RomaPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: nil,
                languageOptions: ["es": "Spanish"]
            ),
            "Default"
        )
        XCTAssertEqual(
            RomaPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: "auto",
                languageOptions: ["auto": "Auto-detect"]
            ),
            "Auto"
        )
        XCTAssertEqual(
            RomaPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: "en",
                languageOptions: ["en": "English"]
            ),
            "English"
        )
        XCTAssertEqual(
            RomaPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: "es",
                languageOptions: ["es": "Spanish"]
            ),
            "Spanish"
        )
        XCTAssertEqual(
            RomaPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: "zz",
                languageOptions: ["es": "Spanish"]
            ),
            "ZZ"
        )
    }

    func testTriggerCountTextPreservesPowerModeRowPluralization() {
        XCTAssertEqual(RomaPowerModePresentation.appTriggerCountText(0), "")
        XCTAssertEqual(RomaPowerModePresentation.appTriggerCountText(1), "1 App")
        XCTAssertEqual(RomaPowerModePresentation.appTriggerCountText(2), "2 Apps")

        XCTAssertEqual(RomaPowerModePresentation.websiteTriggerCountText(0), "")
        XCTAssertEqual(RomaPowerModePresentation.websiteTriggerCountText(1), "1 Website")
        XCTAssertEqual(RomaPowerModePresentation.websiteTriggerCountText(3), "3 Websites")
    }

    func testAIEnhancementProviderControlsFollowProviderCapabilities() {
        for provider in RomaAIEnhancementProviderKind.allCases {
            XCTAssertEqual(
                RomaPowerModePresentation.shouldShowAIModelOptions(for: provider),
                provider != .custom,
                provider.rawValue
            )
            XCTAssertEqual(
                RomaPowerModePresentation.shouldShowRefreshModelsButton(for: provider),
                provider == .openRouter,
                provider.rawValue
            )
        }
    }

    func testRecorderButtonIconPreservesActiveEmojiFallbacks() {
        let activeConfig = PowerModeConfig(
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: false
        )

        XCTAssertEqual(
            RomaPowerModePresentation.recorderButtonIcon(
                hasEnabledConfigurations: true,
                activeConfiguration: activeConfig
            ),
            "W"
        )
        XCTAssertEqual(
            RomaPowerModePresentation.recorderButtonIcon(
                hasEnabledConfigurations: true,
                activeConfiguration: nil
            ),
            "✨"
        )
        XCTAssertEqual(
            RomaPowerModePresentation.recorderButtonIcon(
                hasEnabledConfigurations: false,
                activeConfiguration: activeConfig
            ),
            "✨"
        )
    }

    func testRowDetailPresentationPreservesDefaultBandWithoutVisibleChips() {
        let config = PowerModeConfig(
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: false,
            selectedTranscriptionModelName: "base",
            selectedLanguage: "en"
        )

        let presentation = RomaPowerModePresentation.rowDetailPresentation(
            config: config,
            transcriptionModelDisplayText: RomaPowerModePresentation.defaultOverrideDisplayText,
            selectedLanguageDisplayText: RomaPowerModePresentation.defaultOverrideDisplayText,
            selectedPromptTitle: nil
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.chips, [])
    }

    func testRowDetailPresentationPreservesMacOSChipOrderAndText() {
        let config = PowerModeConfig(
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: true,
            selectedTranscriptionModelName: "large",
            selectedLanguage: "es",
            useScreenCapture: true,
            selectedAIModel: "abcdefghijklmnopqrstu",
            autoSendKey: .commandEnter
        )

        let presentation = RomaPowerModePresentation.rowDetailPresentation(
            config: config,
            transcriptionModelDisplayText: "Large",
            selectedLanguageDisplayText: "Spanish",
            selectedPromptTitle: "Rewrite"
        )

        XCTAssertEqual(
            presentation.chips.map(\.kind),
            [.transcriptionModel, .selectedLanguage, .aiModel, .autoSend, .contextAwareness, .prompt]
        )
        XCTAssertEqual(
            presentation.chips.map(\.text),
            [
                "Large",
                "Spanish",
                "abcdefghijklmnopqr...",
                RomaAutoSendKey.commandEnter.displayName,
                RomaPowerModePresentation.contextAwarenessDisplayText,
                "Rewrite"
            ]
        )
        XCTAssertEqual(
            presentation.chips.map(\.systemImageName),
            ["waveform", "globe", "cpu", "keyboard", "camera.viewfinder", "sparkles"]
        )
        XCTAssertEqual(
            presentation.chips.map(\.usesAccentStyle),
            [false, false, false, false, false, true]
        )
    }

    func testRowDetailPresentationFallsBackToDefaultPromptAndSkipsBlankAIModel() {
        let config = PowerModeConfig(
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: true,
            selectedTranscriptionModelName: "base",
            selectedLanguage: "en",
            selectedAIModel: ""
        )

        let presentation = RomaPowerModePresentation.rowDetailPresentation(
            config: config,
            transcriptionModelDisplayText: RomaPowerModePresentation.defaultOverrideDisplayText,
            selectedLanguageDisplayText: RomaPowerModePresentation.defaultOverrideDisplayText,
            selectedPromptTitle: nil
        )

        XCTAssertEqual(presentation.chips, [
            RomaPowerModeRowDetailChipPresentation(
                kind: .prompt,
                text: RomaPowerModePresentation.defaultPromptDisplayText
            )
        ])
    }

    func testPowerModeBrowserCatalogPreservesMacOSMetadata() {
        XCTAssertEqual(RomaPowerModeBrowser.safari.scriptName, "safariURL")
        XCTAssertEqual(RomaPowerModeBrowser.arc.scriptName, "arcURL")
        XCTAssertEqual(RomaPowerModeBrowser.chrome.scriptName, "chromeURL")
        XCTAssertEqual(RomaPowerModeBrowser.edge.scriptName, "edgeURL")
        XCTAssertEqual(RomaPowerModeBrowser.firefox.scriptName, "firefoxURL")
        XCTAssertEqual(RomaPowerModeBrowser.brave.scriptName, "braveURL")
        XCTAssertEqual(RomaPowerModeBrowser.opera.scriptName, "operaURL")
        XCTAssertEqual(RomaPowerModeBrowser.vivaldi.scriptName, "vivaldiURL")
        XCTAssertEqual(RomaPowerModeBrowser.orion.scriptName, "orionURL")
        XCTAssertEqual(RomaPowerModeBrowser.zen.scriptName, "zenURL")
        XCTAssertEqual(RomaPowerModeBrowser.yandex.scriptName, "yandexURL")

        XCTAssertEqual(RomaPowerModeBrowser.safari.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(RomaPowerModeBrowser.arc.bundleIdentifier, "company.thebrowser.Browser")
        XCTAssertEqual(RomaPowerModeBrowser.chrome.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(RomaPowerModeBrowser.edge.bundleIdentifier, "com.microsoft.edgemac")
        XCTAssertEqual(RomaPowerModeBrowser.firefox.bundleIdentifier, "org.mozilla.firefox")
        XCTAssertEqual(RomaPowerModeBrowser.brave.bundleIdentifier, "com.brave.Browser")
        XCTAssertEqual(RomaPowerModeBrowser.opera.bundleIdentifier, "com.operasoftware.Opera")
        XCTAssertEqual(RomaPowerModeBrowser.vivaldi.bundleIdentifier, "com.vivaldi.Vivaldi")
        XCTAssertEqual(RomaPowerModeBrowser.orion.bundleIdentifier, "com.kagi.kagimacOS")
        XCTAssertEqual(RomaPowerModeBrowser.zen.bundleIdentifier, "app.zen-browser.zen")
        XCTAssertEqual(RomaPowerModeBrowser.yandex.bundleIdentifier, "ru.yandex.desktop.yandex-browser")

        XCTAssertEqual(RomaPowerModeBrowser.chrome.displayName, "Google Chrome")
        XCTAssertEqual(RomaPowerModeBrowser.edge.displayName, "Microsoft Edge")
        XCTAssertEqual(RomaPowerModeBrowser.zen.displayName, "Zen Browser")
        XCTAssertEqual(RomaPowerModeBrowser.yandex.displayName, "Yandex Browser")
    }

    func testPowerModeBrowserCatalogPreservesCurrentDetectionSet() {
        XCTAssertEqual(
            RomaPowerModeBrowser.allCases,
            [
                .safari,
                .arc,
                .chrome,
                .edge,
                .brave,
                .opera,
                .vivaldi,
                .orion,
                .yandex
            ]
        )
        XCTAssertFalse(RomaPowerModeBrowser.allCases.contains(.firefox))
        XCTAssertFalse(RomaPowerModeBrowser.allCases.contains(.zen))
    }

    func testPowerModeEmojiCatalogPreservesDefaultsStorageKeyAndCopy() {
        XCTAssertEqual(RomaPowerModeEmojiCatalog.customEmojisKey, "userAddedEmojis")
        XCTAssertEqual(RomaPowerModeEmojiCatalog.defaultEmojis.first, "🏢")
        XCTAssertEqual(RomaPowerModeEmojiCatalog.defaultEmojis.last, "🔧")
        XCTAssertTrue(RomaPowerModeEmojiCatalog.defaultEmojis.contains("✏️"))
        XCTAssertEqual(RomaPowerModeEmojiCatalog.defaultEmojis.count, 20)
        XCTAssertEqual(
            RomaPowerModeEmojiCatalog.allEmojis(customEmojis: ["🧪"]),
            RomaPowerModeEmojiCatalog.defaultEmojis + ["🧪"]
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.emptySubmitMessage,
            "Emoji cannot be empty."
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.customEmojiFieldPlaceholder,
            "➕"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.addButtonTitle,
            "Add"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.cancelButtonTitle,
            "Cancel"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.tipText,
            "Tip: Use ⌃⌘Space for emoji picker or paste an emoji."
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.addEmojiAccessibilityLabel,
            "Add Emoji"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.addEmojiSystemImageName,
            "plus.circle.fill"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.addCustomEmojiHelpText,
            "Add custom emoji"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.removeCustomEmojiSystemImageName,
            "xmark.circle.fill"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.invalidPreviewMessage,
            "Invalid emoji."
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.invalidSubmitMessage,
            "Invalid emoji character."
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.duplicateMessage,
            "Emoji already exists!"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.inUseAlertTitle,
            "Emoji in Use"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.inUseAlertButtonTitle,
            "OK"
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.inUseAlert(emoji: "🧪"),
            RomaPowerModeEmojiRemovalAlertPresentation(
                title: "Emoji in Use",
                message: "The emoji \"🧪\" is currently used by one or more Power Modes and cannot be removed.",
                buttonTitle: "OK"
            )
        )
        XCTAssertTrue(RomaPowerModeEmojiInputPresentation.isErrorMessage(RomaPowerModeEmojiInputPresentation.emptySubmitMessage))
        XCTAssertTrue(RomaPowerModeEmojiInputPresentation.isErrorMessage(RomaPowerModeEmojiInputPresentation.duplicateMessage))
        XCTAssertFalse(RomaPowerModeEmojiInputPresentation.isErrorMessage(""))
    }

    func testPowerModeEmojiCatalogValidatesAndAddsCustomEmojis() {
        XCTAssertTrue(RomaPowerModeEmojiCatalog.isValidEmoji("🧪"))
        XCTAssertTrue(RomaPowerModeEmojiCatalog.isValidEmoji("✏️"))
        XCTAssertFalse(RomaPowerModeEmojiCatalog.isValidEmoji(""))
        XCTAssertFalse(RomaPowerModeEmojiCatalog.isValidEmoji("A"))
        XCTAssertFalse(RomaPowerModeEmojiCatalog.isValidEmoji("🧪🧪"))
        XCTAssertEqual(RomaPowerModeEmojiCatalog.firstValidEmojiCharacter(in: "abc🧪"), "🧪")
        XCTAssertEqual(RomaPowerModeEmojiCatalog.firstValidEmojiCharacter(in: "abc"), "")

        XCTAssertEqual(
            RomaPowerModeEmojiCatalog.addCustomEmoji(" 🧪 ", customEmojis: []),
            .added(emoji: "🧪", customEmojis: ["🧪"])
        )
        XCTAssertEqual(
            RomaPowerModeEmojiCatalog.addCustomEmoji(" ", customEmojis: []),
            .empty
        )
        XCTAssertEqual(
            RomaPowerModeEmojiCatalog.addCustomEmoji("A", customEmojis: []),
            .invalid
        )
        XCTAssertEqual(
            RomaPowerModeEmojiCatalog.addCustomEmoji("🏢", customEmojis: []),
            .duplicate
        )
        XCTAssertEqual(
            RomaPowerModeEmojiCatalog.addCustomEmoji("🧪", customEmojis: ["🧪"]),
            .duplicate
        )
    }

    func testPowerModeEmojiInputDraftBuildsPreviewFeedback() {
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.inputDraft(for: "abc🧪", customEmojis: []),
            RomaPowerModeEmojiInputDraft(text: "🧪", feedbackMessage: "", canSubmit: true)
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.inputDraft(for: "abc", customEmojis: []),
            RomaPowerModeEmojiInputDraft(text: "", feedbackMessage: "", canSubmit: false)
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.inputDraft(for: "🏢", customEmojis: []),
            RomaPowerModeEmojiInputDraft(
                text: "🏢",
                feedbackMessage: RomaPowerModeEmojiInputPresentation.duplicateMessage,
                canSubmit: false
            )
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.inputDraft(for: "🧪", customEmojis: ["🧪"]),
            RomaPowerModeEmojiInputDraft(
                text: "🧪",
                feedbackMessage: RomaPowerModeEmojiInputPresentation.duplicateMessage,
                canSubmit: false
            )
        )
    }

    func testPowerModeEmojiAddResultPresentation() {
        let added = RomaPowerModeEmojiCatalog.addCustomEmoji("🧪", customEmojis: [])
        XCTAssertEqual(added.addedEmoji, "🧪")
        XCTAssertEqual(RomaPowerModeEmojiInputPresentation.submitFeedbackMessage(for: added), "")

        XCTAssertNil(RomaPowerModeCustomEmojiAddResult.empty.addedEmoji)
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.submitFeedbackMessage(for: .empty),
            RomaPowerModeEmojiInputPresentation.emptySubmitMessage
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.submitFeedbackMessage(for: .invalid),
            RomaPowerModeEmojiInputPresentation.invalidSubmitMessage
        )
        XCTAssertEqual(
            RomaPowerModeEmojiInputPresentation.submitFeedbackMessage(for: .duplicate),
            RomaPowerModeEmojiInputPresentation.duplicateMessage
        )
    }

    func testPowerModeEmojiCatalogReadsSavesAndRemovesCustomEmojis() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaPowerModeEmojiCatalog.customEmojis(from: defaults), [])

            RomaPowerModeEmojiCatalog.saveCustomEmojis(["🧪", "🚀"], to: defaults)

            XCTAssertEqual(RomaPowerModeEmojiCatalog.customEmojis(from: defaults), ["🧪", "🚀"])
            XCTAssertTrue(
                RomaPowerModeEmojiCatalog.isCustomEmoji(
                    "🧪",
                    customEmojis: RomaPowerModeEmojiCatalog.customEmojis(from: defaults)
                )
            )
            XCTAssertEqual(
                RomaPowerModeEmojiCatalog.removeCustomEmoji(
                    "🧪",
                    customEmojis: RomaPowerModeEmojiCatalog.customEmojis(from: defaults)
                ),
                ["🚀"]
            )
            XCTAssertNil(
                RomaPowerModeEmojiCatalog.removeCustomEmoji(
                    "missing",
                    customEmojis: RomaPowerModeEmojiCatalog.customEmojis(from: defaults)
                )
            )
        }
    }

    func testPowerModeTriggerConfigsPreserveStoredShapeAndIdEquality() throws {
        let id = UUID()
        let appConfig = RomaPowerModeAppConfig(
            id: id,
            bundleIdentifier: "com.example.App",
            appName: "Example"
        )
        let renamedAppConfig = RomaPowerModeAppConfig(
            id: id,
            bundleIdentifier: "com.example.Other",
            appName: "Other"
        )
        let urlConfig = RomaPowerModeURLConfig(id: id, url: "example.com")
        let renamedURLConfig = RomaPowerModeURLConfig(id: id, url: "other.example.com")

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

    func testTranscriptionMetadataUsesOnlyEnabledPowerModeConfig() {
        let enabledConfig = PowerModeConfig(
            name: " Writing ",
            emoji: " W ",
            isAIEnhancementEnabled: false,
            isEnabled: true
        )
        let disabledConfig = PowerModeConfig(
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: false,
            isEnabled: false
        )

        XCTAssertEqual(
            RomaPowerModeTranscriptionMetadata.active(from: enabledConfig),
            RomaPowerModeTranscriptionMetadata(name: " Writing ", emoji: " W ")
        )
        XCTAssertEqual(
            RomaPowerModeTranscriptionMetadata.active(from: disabledConfig),
            .inactive
        )
        XCTAssertEqual(
            RomaPowerModeTranscriptionMetadata.active(from: nil),
            .inactive
        )
    }

    func testPowerModeTriggerConfigsAdaptToPolicyRules() {
        XCTAssertEqual(
            RomaPowerModeAppConfig(
                bundleIdentifier: "com.example.App",
                appName: "Example"
            ).rule,
            RomaPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Example")
        )
        XCTAssertEqual(
            RomaPowerModeURLConfig(url: "example.com").rule,
            RomaPowerModeWebsiteRule(url: "example.com")
        )
    }

    func testPowerModeAppConfigSelectionTogglesByBundleIdentifier() {
        let existingID = UUID()
        var configs = [
            RomaPowerModeAppConfig(
                id: existingID,
                bundleIdentifier: "com.example.Existing",
                appName: "Existing"
            )
        ]

        XCTAssertTrue(configs.containsPowerModeAppConfig(bundleIdentifier: "com.example.Existing"))
        XCTAssertFalse(configs.containsPowerModeAppConfig(bundleIdentifier: "com.example.New"))

        configs.togglePowerModeAppConfig(bundleIdentifier: "com.example.New", appName: "New")
        XCTAssertEqual(configs.map(\.bundleIdentifier), ["com.example.Existing", "com.example.New"])
        XCTAssertEqual(configs.last?.appName, "New")

        configs.togglePowerModeAppConfig(bundleIdentifier: "com.example.Existing", appName: "Ignored")
        XCTAssertEqual(configs.map(\.bundleIdentifier), ["com.example.New"])
        XCTAssertFalse(configs.contains { $0.id == existingID })
    }

    func testPowerModeAppPickerSearchMatchesNameAndBundleIdentifier() {
        struct AppItem: Equatable {
            let name: String
            let bundleIdentifier: String
        }

        let apps = [
            AppItem(name: "Safari", bundleIdentifier: "com.apple.Safari"),
            AppItem(name: "Roma Notes", bundleIdentifier: "talk.roma.notes"),
            AppItem(name: "Mail", bundleIdentifier: "com.apple.mail")
        ]

        XCTAssertTrue(
            RomaPowerModeAppPickerPolicy.matchesSearch(
                appName: "Roma Notes",
                bundleIdentifier: "talk.roma.notes",
                searchText: "roma"
            )
        )
        XCTAssertTrue(
            RomaPowerModeAppPickerPolicy.matchesSearch(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                searchText: "APPLE"
            )
        )
        XCTAssertFalse(
            RomaPowerModeAppPickerPolicy.matchesSearch(
                appName: "Mail",
                bundleIdentifier: "com.apple.mail",
                searchText: "notes"
            )
        )

        XCTAssertEqual(
            RomaPowerModeAppPickerPolicy.filteredItems(
                apps,
                searchText: "",
                appName: { $0.name },
                bundleIdentifier: { $0.bundleIdentifier }
            ),
            apps
        )
        XCTAssertEqual(
            RomaPowerModeAppPickerPolicy.filteredItems(
                apps,
                searchText: "roma",
                appName: { $0.name },
                bundleIdentifier: { $0.bundleIdentifier }
            ),
            [apps[1]]
        )
        XCTAssertEqual(
            RomaPowerModeAppPickerPolicy.filteredItems(
                apps,
                searchText: "com.apple",
                appName: { $0.name },
                bundleIdentifier: { $0.bundleIdentifier }
            ),
            [apps[0], apps[2]]
        )
    }

    func testPowerModeConfigPreservesStoredShapeEqualityAndRuleAdapter() throws {
        let id = UUID()
        let config = PowerModeConfig(
            id: id,
            name: "Writing",
            emoji: "W",
            appConfigs: [
                RomaPowerModeAppConfig(
                    bundleIdentifier: "com.example.App",
                    appName: "Example"
                )
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
        XCTAssertEqual(object["autoSendKey"] as? String, RomaAutoSendKey.commandEnter.rawValue)

        let rule = config.powerModePolicyRule
        XCTAssertEqual(rule.id, id)
        XCTAssertEqual(rule.name, "Writing")
        XCTAssertEqual(
            rule.appRules,
            [RomaPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Example")]
        )
        XCTAssertEqual(rule.websiteRules, [RomaPowerModeWebsiteRule(url: "example.com")])
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
        let prompt = RomaCustomPrompt(id: promptID, title: "Rewrite", promptText: "Rewrite this")
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
        let appConfig = RomaPowerModeAppConfig(
            bundleIdentifier: "com.example.App",
            appName: "Example"
        )
        let urlConfig = RomaPowerModeURLConfig(url: "example.com")
        let draft = RomaPowerModeConfigurationDraft(
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

        let config = RomaPowerModePolicy.configuration(from: draft, mode: .add)

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
            appConfigs: [RomaPowerModeAppConfig(bundleIdentifier: "com.example.Old", appName: "Old")],
            urlConfigs: [RomaPowerModeURLConfig(url: "old.example.com")],
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
        let draft = RomaPowerModeConfigurationDraft(
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

        let config = RomaPowerModePolicy.configuration(from: draft, mode: .edit(existing))

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
        let formState = RomaPowerModeConfigurationMode.add.formState(
            existingConfigurations: [],
            newID: id,
            selectedAIProvider: "Groq"
        )

        XCTAssertEqual(formState.id, id)
        XCTAssertEqual(RomaPowerModeConfigurationFormState.addDefaultName, "")
        XCTAssertEqual(RomaPowerModeConfigurationFormState.addDefaultEmoji, "✏️")
        XCTAssertEqual(formState.name, RomaPowerModeConfigurationFormState.addDefaultName)
        XCTAssertEqual(formState.emoji, RomaPowerModeConfigurationFormState.addDefaultEmoji)
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
        let appConfig = RomaPowerModeAppConfig(
            bundleIdentifier: "com.example.App",
            appName: "Example"
        )
        let urlConfig = RomaPowerModeURLConfig(url: "example.com")
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

        let formState = RomaPowerModeConfigurationMode.edit(oldConfig).formState(
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

        let formState = RomaPowerModeConfigurationMode.edit(config).formState(existingConfigurations: [])

        XCTAssertEqual(formState.appConfigs, [])
        XCTAssertEqual(formState.urlConfigs, [])
        XCTAssertFalse(formState.isTranscriptFormattingExpanded)
    }

    func testPowerModeEnhancementSelectionFillsMissingProviderAndModel() {
        let nilSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil
        )
        let emptyModelSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "OpenAI",
            selectedAIModel: ""
        )
        let existingSelection = RomaPowerModeEnhancementSelection(
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
            RomaPowerModeEnhancementSelection(
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
        let prompt = RomaCustomPrompt(id: promptID, title: "Rewrite", promptText: "Rewrite this")

        XCTAssertEqual(
            RomaPowerModeEnhancementSelection(
                selectedPromptId: nil,
                selectedAIProvider: "Groq",
                selectedAIModel: "llama-3.3"
            )
            .selectingPromptAfterEnabling(prompts: [prompt])
            .selectedPromptId,
            promptID
        )
        XCTAssertEqual(
            RomaPowerModeEnhancementSelection(
                selectedPromptId: existingPromptID,
                selectedAIProvider: "Groq",
                selectedAIModel: "llama-3.3"
            )
            .selectingPromptAfterEnabling(prompts: [prompt])
            .selectedPromptId,
            existingPromptID
        )
        XCTAssertNil(
            RomaPowerModeEnhancementSelection(
                selectedPromptId: nil,
                selectedAIProvider: "Groq",
                selectedAIModel: "llama-3.3"
            )
            .selectingPromptAfterEnabling(prompts: [])
            .selectedPromptId
        )
    }

    func testPowerModeEnhancementSelectionRepairsPromptOnlyWhenEnhancementIsEnabled() {
        let promptID = UUID()
        let prompt = RomaCustomPrompt(id: promptID, title: "Rewrite", promptText: "Rewrite this")
        let missingSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "Groq",
            selectedAIModel: "llama-3.3"
        )

        XCTAssertEqual(
            missingSelection.selectingPromptForEnhancementState(
                isEnabled: true,
                prompts: [prompt]
            ).selectedPromptId,
            promptID
        )
        XCTAssertNil(
            missingSelection.selectingPromptForEnhancementState(
                isEnabled: false,
                prompts: [prompt]
            ).selectedPromptId
        )
    }

    func testPowerModeEnhancementTogglePlanAppliesMacOSToggleEnablementRules() {
        let promptID = UUID()
        let prompt = RomaCustomPrompt(id: promptID, title: "Rewrite", promptText: "Rewrite this")
        let missingSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil
        )
        let emptyModelSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "OpenAI",
            selectedAIModel: ""
        )
        let existingSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: UUID(),
            selectedAIProvider: "Groq",
            selectedAIModel: "llama-3.3"
        )

        let enabledPlan = missingSelection.togglePlan(
            isEnabled: true,
            currentProvider: .gemini,
            currentModel: "gemini-2.5-flash",
            prompts: [prompt]
        )
        XCTAssertEqual(
            enabledPlan.selectionToApply,
            RomaPowerModeEnhancementSelection(
                selectedPromptId: promptID,
                selectedAIProvider: "Gemini",
                selectedAIModel: "gemini-2.5-flash"
            )
        )

        XCTAssertEqual(
            emptyModelSelection.togglePlan(
                isEnabled: true,
                currentProvider: .groq,
                currentModel: "llama-3.3",
                prompts: [prompt]
            ).selectionToApply?.selectedAIModel,
            ""
        )
        XCTAssertEqual(
            existingSelection.togglePlan(
                isEnabled: true,
                currentProvider: .openAI,
                currentModel: "gpt-4o",
                prompts: [prompt]
            ).selectionToApply,
            existingSelection
        )
        XCTAssertNil(
            missingSelection.togglePlan(
                isEnabled: false,
                currentProvider: .openAI,
                currentModel: "gpt-4o",
                prompts: [prompt]
            ).selectionToApply
        )

        var events = [String]()
        enabledPlan.applyRuntimeState {
            events.append("\($0.selectedAIProvider ?? "nil"):\($0.selectedAIModel ?? "nil")")
        }
        missingSelection.togglePlan(
            isEnabled: false,
            currentProvider: .openAI,
            currentModel: "gpt-4o",
            prompts: [prompt]
        )
        .applyRuntimeState {
            events.append($0.selectedAIProvider ?? "nil")
        }

        XCTAssertEqual(events, ["Gemini:gemini-2.5-flash"])
    }

    func testPowerModeEnhancementProviderChangePlanAppliesDefaultModelOnlyForValidProvider() {
        let promptID = UUID()
        let selection = RomaPowerModeEnhancementSelection(
            selectedPromptId: promptID,
            selectedAIProvider: "Groq",
            selectedAIModel: nil
        )
        let existingModelSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: promptID,
            selectedAIProvider: "OpenAI",
            selectedAIModel: "old-model"
        )
        let invalidProviderSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: promptID,
            selectedAIProvider: "MissingProvider",
            selectedAIModel: "kept"
        )

        XCTAssertEqual(
            selection.providerChangePlan { "\($0.rawValue)-default" }.selectionToApply,
            RomaPowerModeEnhancementSelection(
                selectedPromptId: promptID,
                selectedAIProvider: "Groq",
                selectedAIModel: "Groq-default"
            )
        )
        XCTAssertEqual(
            existingModelSelection.providerChangePlan { "\($0.rawValue)-default" }.selectionToApply,
            RomaPowerModeEnhancementSelection(
                selectedPromptId: promptID,
                selectedAIProvider: "OpenAI",
                selectedAIModel: "OpenAI-default"
            )
        )
        XCTAssertNil(
            invalidProviderSelection.providerChangePlan { "\($0.rawValue)-default" }.selectionToApply
        )

        var events = [String]()
        selection.providerChangePlan { "\($0.rawValue)-default" }
            .applyRuntimeState {
                events.append("\($0.selectedAIProvider ?? "nil"):\($0.selectedAIModel ?? "nil")")
            }
        invalidProviderSelection.providerChangePlan { "\($0.rawValue)-default" }
            .applyRuntimeState {
                events.append($0.selectedAIProvider ?? "nil")
            }

        XCTAssertEqual(events, ["Groq:Groq-default"])
    }

    func testPowerModeEnhancementSelectionResolvesProviderPickerAndModelOptions() {
        let missingSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil
        )
        let legacySelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "GROQ",
            selectedAIModel: nil
        )
        let invalidSelection = RomaPowerModeEnhancementSelection(
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
        let selection = RomaPowerModeEnhancementSelection(
            selectedPromptId: UUID(),
            selectedAIProvider: "Groq",
            selectedAIModel: "llama-3.3"
        )
        let emptyModelSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "Groq",
            selectedAIModel: ""
        )
        let nilModelSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: "Groq",
            selectedAIModel: nil
        )
        let invalidProviderSelection = RomaPowerModeEnhancementSelection(
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

    func testPowerModeTranscriptionModelFactsResolveLanguagePresentationPolicy() {
        let autodetectFacts = transcriptionModelFacts(disablesLanguageSelection: true, isMultilingual: true)
        XCTAssertTrue(autodetectFacts.shouldShowAutodetectOnlyLanguage)
        XCTAssertFalse(autodetectFacts.shouldShowLanguagePicker)
        XCTAssertFalse(autodetectFacts.shouldApplyDefaultLanguageIfMissing)
        XCTAssertFalse(autodetectFacts.shouldRepairSelectedLanguageForPowerMode)

        let pickerFacts = transcriptionModelFacts(disablesLanguageSelection: false, isMultilingual: true)
        XCTAssertFalse(pickerFacts.shouldShowAutodetectOnlyLanguage)
        XCTAssertTrue(pickerFacts.shouldShowLanguagePicker)
        XCTAssertFalse(pickerFacts.shouldApplyDefaultLanguageIfMissing)
        XCTAssertTrue(pickerFacts.shouldRepairSelectedLanguageForPowerMode)

        let hiddenDefaultFacts = transcriptionModelFacts(disablesLanguageSelection: false, isMultilingual: false)
        XCTAssertFalse(hiddenDefaultFacts.shouldShowAutodetectOnlyLanguage)
        XCTAssertFalse(hiddenDefaultFacts.shouldShowLanguagePicker)
        XCTAssertTrue(hiddenDefaultFacts.shouldApplyDefaultLanguageIfMissing)
        XCTAssertTrue(hiddenDefaultFacts.shouldRepairSelectedLanguageForPowerMode)
    }

    func testPowerModeTranscriptionModelFactsDeriveProviderPoliciesFromLanguageSource() {
        let geminiFacts = RomaPowerModeTranscriptionModelFacts(
            name: "gemini",
            languageSource: .provider(.gemini),
            isMultilingual: true,
            languageOptions: RomaLanguageCatalog.all
        )
        let nativeAppleFacts = RomaPowerModeTranscriptionModelFacts(
            name: "native",
            languageSource: .nativeApple,
            isMultilingual: true,
            languageOptions: RomaLanguageCatalog.nativeApple
        )
        let whisperFacts = RomaPowerModeTranscriptionModelFacts(
            name: "base",
            languageSource: .whisper,
            isMultilingual: true,
            languageOptions: RomaLanguageCatalog.whisperLanguages()
        )

        XCTAssertTrue(geminiFacts.disablesLanguageSelection)
        XCTAssertTrue(geminiFacts.shouldShowAutodetectOnlyLanguage)
        XCTAssertFalse(geminiFacts.shouldRepairSelectedLanguageForPowerMode)
        XCTAssertFalse(geminiFacts.prefersNativeAppleEnglish)
        XCTAssertFalse(nativeAppleFacts.disablesLanguageSelection)
        XCTAssertTrue(nativeAppleFacts.shouldShowLanguagePicker)
        XCTAssertTrue(nativeAppleFacts.prefersNativeAppleEnglish)
        XCTAssertFalse(whisperFacts.disablesLanguageSelection)
        XCTAssertTrue(whisperFacts.shouldShowLanguagePicker)
        XCTAssertFalse(whisperFacts.prefersNativeAppleEnglish)
    }

    func testPowerModeTranscriptionModelResourceFactsDeriveLocalModelPolicyFromLanguageSource() {
        XCTAssertTrue(
            RomaPowerModeTranscriptionModelResourceFacts(
                name: "base",
                languageSource: .whisper
            ).loadsLocalWhisperModel
        )
        XCTAssertFalse(
            RomaPowerModeTranscriptionModelResourceFacts(
                name: "native",
                languageSource: .nativeApple
            ).loadsLocalWhisperModel
        )
        XCTAssertFalse(
            RomaPowerModeTranscriptionModelResourceFacts(
                name: "gemini",
                languageSource: .provider(.gemini)
            ).loadsLocalWhisperModel
        )
    }

    func testPowerModeTranscriptionSelectionRepairsModelAndLanguageState() {
        let selection = RomaPowerModeTranscriptionSelection(
            selectedModelName: nil,
            selectedLanguage: nil
        )
        let selectedLanguage = RomaPowerModeTranscriptionSelection(
            selectedModelName: "base",
            selectedLanguage: "fr"
        )

        XCTAssertEqual(selection.selectedModelNameForPicker(currentModelName: "current"), "current")
        XCTAssertEqual(selection.selectingModelName("large").selectedModelName, "large")
        XCTAssertEqual(selection.selectedLanguageForPicker(storedLanguage: "de"), "de")
        XCTAssertEqual(selection.selectingDefaultLanguageIfMissing("en").selectedLanguage, "en")
        XCTAssertEqual(selectedLanguage.selectingDefaultLanguageIfMissing("en").selectedLanguage, "fr")
        XCTAssertEqual(selectedLanguage.selectingAutodetectLanguage().selectedLanguage, RomaLanguageCatalog.autoDetectCode)
        XCTAssertEqual(
            selectedLanguage.selectingCompatibleLanguage(
                for: transcriptionModelFacts(disablesLanguageSelection: true),
                storedLanguage: "de"
            ).selectedLanguage,
            RomaLanguageCatalog.autoDetectCode
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
                    languageOptions: RomaLanguageCatalog.englishOnly
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

    func testPowerModeTranscriptionModelChangePlanAppliesCompatibleLanguageOnlyForSelectedModel() {
        let selection = RomaPowerModeTranscriptionSelection(
            selectedModelName: "base",
            selectedLanguage: nil
        )
        let disabledLanguageFacts = transcriptionModelFacts(disablesLanguageSelection: true)

        XCTAssertEqual(
            selection.modelChangePlan(
                selectedModelFacts: transcriptionModelFacts(languageOptions: ["en": "English", "fr": "French"]),
                storedLanguage: "fr"
            ).selectionToApply,
            RomaPowerModeTranscriptionSelection(
                selectedModelName: "base",
                selectedLanguage: "fr"
            )
        )
        XCTAssertEqual(
            selection.modelChangePlan(
                selectedModelFacts: disabledLanguageFacts,
                storedLanguage: "fr"
            ).selectionToApply?.selectedLanguage,
            RomaLanguageCatalog.autoDetectCode
        )
        XCTAssertNil(
            selection.modelChangePlan(
                selectedModelFacts: nil,
                storedLanguage: "fr"
            ).selectionToApply
        )

        var events = [String]()
        selection.modelChangePlan(
            selectedModelFacts: disabledLanguageFacts,
            storedLanguage: "fr"
        )
        .applyRuntimeState {
            events.append("\($0.selectedModelName ?? "nil"):\($0.selectedLanguage ?? "nil")")
        }
        selection.modelChangePlan(
            selectedModelFacts: nil,
            storedLanguage: "fr"
        )
        .applyRuntimeState {
            events.append($0.selectedModelName ?? "nil")
        }

        XCTAssertEqual(events, ["base:auto"])
    }

    func testPowerModeTranscriptionLanguageControlAppearPlanAppliesOnlyRenderedControlSideEffects() {
        let selection = RomaPowerModeTranscriptionSelection(
            selectedModelName: "base",
            selectedLanguage: nil
        )
        let selectedLanguage = RomaPowerModeTranscriptionSelection(
            selectedModelName: "base",
            selectedLanguage: "fr"
        )

        XCTAssertEqual(
            selection.languageControlAppearPlan(
                for: transcriptionModelFacts(disablesLanguageSelection: true),
                defaultLanguage: "en"
            ).selectionToApply?.selectedLanguage,
            RomaLanguageCatalog.autoDetectCode
        )
        XCTAssertNil(
            selection.languageControlAppearPlan(
                for: transcriptionModelFacts(isMultilingual: true),
                defaultLanguage: "en"
            ).selectionToApply
        )
        XCTAssertEqual(
            selection.languageControlAppearPlan(
                for: transcriptionModelFacts(
                    isMultilingual: false,
                    languageOptions: RomaLanguageCatalog.englishOnly
                ),
                defaultLanguage: "en"
            ).selectionToApply?.selectedLanguage,
            "en"
        )
        XCTAssertEqual(
            selectedLanguage.languageControlAppearPlan(
                for: transcriptionModelFacts(
                    isMultilingual: false,
                    languageOptions: RomaLanguageCatalog.englishOnly
                ),
                defaultLanguage: "en"
            ).selectionToApply?.selectedLanguage,
            "fr"
        )

        var events = [String]()
        selection.languageControlAppearPlan(
            for: transcriptionModelFacts(disablesLanguageSelection: true),
            defaultLanguage: "en"
        )
        .applyRuntimeState {
            events.append("\($0.selectedModelName ?? "nil"):\($0.selectedLanguage ?? "nil")")
        }
        selection.languageControlAppearPlan(
            for: transcriptionModelFacts(isMultilingual: true),
            defaultLanguage: "en"
        )
        .applyRuntimeState {
            events.append($0.selectedLanguage ?? "nil")
        }

        XCTAssertEqual(events, ["base:auto"])
    }

    func testPowerModeLanguageApplicationPlanSkipsMissingLanguage() {
        let plan = RomaPowerModeLanguageApplicationPlan.plan(selectedLanguage: nil)
        XCTAssertEqual(languageRuntimeEvents(for: plan), [])
    }

    func testPowerModeLanguageApplicationPlanPreservesExplicitChoices() {
        for language in ["auto", "en", "zh", "fr-FR"] {
            let plan = RomaPowerModeLanguageApplicationPlan.plan(selectedLanguage: language)
            XCTAssertEqual(languageRuntimeEvents(for: plan), ["save:\(language)", "post"])
        }
    }

    func testPowerModeTranscriptionModelResourcePlanSkipsMissingUnchangedSelection() async {
        let availableModels = [
            transcriptionModelResourceFacts(name: "base", loadsLocalWhisperModel: true)
        ]
        let missingSelection = RomaPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: nil,
            currentModelName: "current",
            availableModels: availableModels,
            availableLocalModelNames: []
        )
        let missingModel = RomaPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "missing",
            currentModelName: "current",
            availableModels: availableModels,
            availableLocalModelNames: ["missing"]
        )
        let unchangedModel = RomaPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "base",
            currentModelName: "base",
            availableModels: availableModels,
            availableLocalModelNames: ["base"]
        )

        let missingSelectionEvents = await runtimeEvents(for: missingSelection)
        let missingModelEvents = await runtimeEvents(for: missingModel)
        let unchangedModelEvents = await runtimeEvents(for: unchangedModel)
        XCTAssertEqual(missingSelectionEvents, [])
        XCTAssertEqual(missingModelEvents, [])
        XCTAssertEqual(unchangedModelEvents, [])
    }

    func testPowerModeTranscriptionModelResourcePlanCleansNonWhisperModels() async {
        let plan = RomaPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "nova-3",
            currentModelName: "base",
            availableModels: [
                transcriptionModelResourceFacts(name: "nova-3", loadsLocalWhisperModel: false)
            ],
            availableLocalModelNames: []
        )

        let events = await runtimeEvents(for: plan)
        XCTAssertEqual(events, ["select:nova-3", "cleanup"])
    }

    func testPowerModeTranscriptionModelResourcePlanLoadsDownloadedLocalWhisperModel() async {
        let plan = RomaPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "base",
            currentModelName: "nova-3",
            availableModels: [
                transcriptionModelResourceFacts(name: "base", loadsLocalWhisperModel: true)
            ],
            availableLocalModelNames: ["base"]
        )

        let events = await runtimeEvents(for: plan)
        XCTAssertEqual(events, ["select:base", "cleanup", "load:base"])
    }

    func testPowerModeTranscriptionModelResourcePlanCleansMissingLocalWhisperFile() async {
        let plan = RomaPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "base",
            currentModelName: "nova-3",
            availableModels: [
                transcriptionModelResourceFacts(name: "base", loadsLocalWhisperModel: true)
            ],
            availableLocalModelNames: []
        )

        let events = await runtimeEvents(for: plan)
        XCTAssertEqual(events, ["select:base", "cleanup"])
    }

    func testPowerModeTranscriptionModelResourcePlanReportsLocalModelLoadFailure() async {
        let plan = RomaPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: "base",
            currentModelName: "nova-3",
            availableModels: [
                transcriptionModelResourceFacts(name: "base", loadsLocalWhisperModel: true)
            ],
            availableLocalModelNames: ["base"]
        )

        let events = await runtimeEvents(for: plan, loadError: PowerModeResourcePlanFixtureError.loadFailed)
        XCTAssertEqual(events, ["select:base", "cleanup", "load:base", "loadFailed:base"])
    }

    func testPowerModeApplicationStatePreservesStoredShapeAndCleanupKeys() throws {
        let state = RomaPowerModeApplicationState(
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
            try JSONDecoder().decode(RomaPowerModeApplicationState.self, from: JSONEncoder().encode(state)),
            state
        )
    }

    func testPowerModeApplicationStateBuildsSnapshotFromPromptAndCleanupSettings() {
        let promptID = UUID()
        let cleanupSettings = RomaTranscriptionCleanupSettings(
            punctuationMode: .removeAll,
            isTextFormattingEnabled: true,
            lowercaseTranscription: true,
            removeFillerWords: false
        )

        let state = RomaPowerModeApplicationState(
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
        let validState = RomaPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            selectedPromptId: promptID.uuidString,
            selectedAIProvider: "GROQ"
        )
        let invalidState = RomaPowerModeApplicationState(
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
        let explicitModeState = RomaPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeTrailingPeriod,
            removePunctuation: true,
            lowercaseTranscription: false
        )
        let legacyRemoveAllState = RomaPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            removePunctuation: true
        )
        let legacyKeepState = RomaPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            removePunctuation: false
        )

        XCTAssertEqual(
            explicitModeState.cleanupRestore,
            RomaPowerModeCleanupRestore(
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

        let state = try JSONDecoder().decode(RomaPowerModeApplicationState.self, from: data)

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

        let runtime = preferenceApplicationRuntime(for: config.powerModePreferenceApplication)

        XCTAssertEqual(runtime.isEnhancementEnabled, true)
        XCTAssertEqual(runtime.useScreenCaptureContext, true)
        XCTAssertTrue(runtime.didApplyPrompt)
        XCTAssertEqual(runtime.selectedPromptId, promptID)
        XCTAssertEqual(runtime.selectedAIProvider, .groq)
        XCTAssertEqual(runtime.selectedAIModel, "llama-3.3")
        XCTAssertEqual(runtime.isTextFormattingEnabled, true)
        XCTAssertEqual(runtime.punctuationMode, .removeTrailingPeriod)
        XCTAssertEqual(runtime.lowercaseTranscription, true)
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

        let existingPromptID = UUID()
        let runtime = preferenceApplicationRuntime(
            for: config.powerModePreferenceApplication,
            startingAt: existingPromptID
        )

        XCTAssertEqual(runtime.isEnhancementEnabled, false)
        XCTAssertEqual(runtime.useScreenCaptureContext, true)
        XCTAssertFalse(runtime.didApplyPrompt)
        XCTAssertEqual(runtime.selectedPromptId, existingPromptID)
        XCTAssertNil(runtime.selectedAIProvider)
        XCTAssertNil(runtime.selectedAIModel)
        XCTAssertEqual(runtime.punctuationMode, .keep)
    }

    func testPowerModeApplicationStateBuildsPreferenceRestoreApplication() {
        let promptID = UUID()
        let state = RomaPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: true,
            selectedPromptId: promptID.uuidString,
            selectedAIProvider: "GROQ",
            selectedAIModel: "llama-3.3",
            isTextFormattingEnabled: false,
            punctuationCleanupMode: .removeAll,
            lowercaseTranscription: true
        )

        let runtime = preferenceApplicationRuntime(for: state.powerModePreferenceRestore)

        XCTAssertEqual(runtime.isEnhancementEnabled, true)
        XCTAssertEqual(runtime.useScreenCaptureContext, true)
        XCTAssertTrue(runtime.didApplyPrompt)
        XCTAssertEqual(runtime.selectedPromptId, promptID)
        XCTAssertEqual(runtime.selectedAIProvider, .groq)
        XCTAssertEqual(runtime.selectedAIModel, "llama-3.3")
        XCTAssertEqual(runtime.isTextFormattingEnabled, false)
        XCTAssertEqual(runtime.punctuationMode, .removeAll)
        XCTAssertEqual(runtime.lowercaseTranscription, true)
    }

    func testPowerModeApplicationStatePreferenceRestoreClearsInvalidPromptAndKeepsLegacyCleanup() {
        let state = RomaPowerModeApplicationState(
            isEnhancementEnabled: false,
            useScreenCaptureContext: false,
            selectedPromptId: "not-a-uuid",
            selectedAIProvider: "MissingProvider",
            removePunctuation: true
        )

        let runtime = preferenceApplicationRuntime(for: state.powerModePreferenceRestore, startingAt: UUID())

        XCTAssertEqual(runtime.isEnhancementEnabled, false)
        XCTAssertEqual(runtime.useScreenCaptureContext, false)
        XCTAssertTrue(runtime.didApplyPrompt)
        XCTAssertNil(runtime.selectedPromptId)
        XCTAssertNil(runtime.selectedAIProvider)
        XCTAssertNil(runtime.selectedAIModel)
        XCTAssertEqual(runtime.punctuationMode, .removeAll)
    }

    func testPowerModeSessionApplicationPlanBuildsConfigurationApplicationSequence() async {
        let promptID = UUID()
        let config = PowerModeConfig(
            name: "Coding",
            emoji: "C",
            isAIEnhancementEnabled: true,
            selectedPrompt: promptID.uuidString,
            selectedTranscriptionModelName: "base",
            selectedLanguage: "fr",
            useScreenCapture: true,
            selectedAIProvider: "GROQ",
            selectedAIModel: "llama-3.3"
        )

        let plan = RomaPowerModeSessionApplicationPlan.applying(
            config: config,
            facts: sessionApplicationFacts(
                currentModelName: "nova-3",
                availableLocalModelNames: ["base"]
            )
        )

        let runtime = await sessionApplicationRuntime(for: plan)
        guard let preferenceApplication = runtime.preferenceApplication,
              let modelResourcePlan = runtime.modelResourcePlan,
              let languageApplicationPlan = runtime.languageApplicationPlan else {
            XCTFail("Expected session application runtime plans")
            return
        }

        XCTAssertEqual(preferenceApplication.isEnhancementEnabled, true)
        XCTAssertEqual(preferenceApplication.useScreenCaptureContext, true)
        XCTAssertTrue(preferenceApplication.didApplyPrompt)
        XCTAssertEqual(preferenceApplication.selectedPromptId, promptID)
        XCTAssertEqual(preferenceApplication.selectedAIProvider, .groq)
        XCTAssertEqual(preferenceApplication.selectedAIModel, "llama-3.3")
        let modelResourceEvents = await runtimeEvents(for: modelResourcePlan)
        XCTAssertEqual(modelResourceEvents, ["select:base", "cleanup", "load:base"])
        XCTAssertEqual(languageRuntimeEvents(for: languageApplicationPlan), ["save:fr", "post"])
        XCTAssertTrue(runtime.didPostConfigurationApplied)
    }

    func testPowerModeSessionApplicationPlanBuildsRestoreSequenceWithoutConfigurationNotification() async {
        let promptID = UUID()
        let state = RomaPowerModeApplicationState(
            isEnhancementEnabled: false,
            useScreenCaptureContext: false,
            selectedPromptId: promptID.uuidString,
            selectedAIProvider: "GROQ",
            selectedAIModel: "llama-3.3",
            selectedLanguage: "auto",
            transcriptionModelName: "english-only",
            removePunctuation: true
        )

        let plan = RomaPowerModeSessionApplicationPlan.restoring(
            state: state,
            facts: sessionApplicationFacts(
                currentModelName: "base",
                availableLocalModelNames: ["base"]
            )
        )

        let runtime = await sessionApplicationRuntime(for: plan)
        guard let preferenceApplication = runtime.preferenceApplication,
              let modelResourcePlan = runtime.modelResourcePlan,
              let languageApplicationPlan = runtime.languageApplicationPlan else {
            XCTFail("Expected session application runtime plans")
            return
        }

        XCTAssertEqual(preferenceApplication.isEnhancementEnabled, false)
        XCTAssertEqual(preferenceApplication.useScreenCaptureContext, false)
        XCTAssertTrue(preferenceApplication.didApplyPrompt)
        XCTAssertEqual(preferenceApplication.selectedPromptId, promptID)
        XCTAssertEqual(preferenceApplication.selectedAIProvider, .groq)
        XCTAssertEqual(preferenceApplication.selectedAIModel, "llama-3.3")
        XCTAssertEqual(preferenceApplication.punctuationMode, .removeAll)
        let modelResourceEvents = await runtimeEvents(for: modelResourcePlan)
        XCTAssertEqual(modelResourceEvents, ["select:english-only", "cleanup"])
        XCTAssertEqual(languageRuntimeEvents(for: languageApplicationPlan), ["save:auto", "post"])
        XCTAssertFalse(runtime.didPostConfigurationApplied)
    }

    func testPowerModeSessionApplicationPlanKeepsModelAndLanguageNoOpWhenRestoreSelectionsAreMissing() async {
        let state = RomaPowerModeApplicationState(
            isEnhancementEnabled: false,
            useScreenCaptureContext: false,
            selectedLanguage: nil,
            transcriptionModelName: nil
        )

        let plan = RomaPowerModeSessionApplicationPlan.restoring(
            state: state,
            facts: sessionApplicationFacts(
                currentModelName: "base",
                availableLocalModelNames: ["base"]
            )
        )

        let runtime = await sessionApplicationRuntime(for: plan)
        guard let modelResourcePlan = runtime.modelResourcePlan,
              let languageApplicationPlan = runtime.languageApplicationPlan else {
            XCTFail("Expected session application runtime plans")
            return
        }

        XCTAssertEqual(languageRuntimeEvents(for: languageApplicationPlan), [])
        let modelResourceEvents = await runtimeEvents(for: modelResourcePlan)
        XCTAssertEqual(modelResourceEvents, [])
        XCTAssertFalse(runtime.didPostConfigurationApplied)
    }

    func testPowerModeSessionPreservesStoredShapeAndOriginalState() throws {
        let id = UUID()
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let originalState = RomaPowerModeApplicationState(
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
        let session = RomaPowerModeSession(
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

        let decoded = try JSONDecoder().decode(RomaPowerModeSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.startTime.timeIntervalSinceReferenceDate, startTime.timeIntervalSinceReferenceDate, accuracy: 0.001)
        XCTAssertEqual(decoded.originalState, originalState)
    }

    func testPowerModeSessionBeginPlanCreatesSessionWhenMissing() {
        let id = UUID()
        let startTime = Date(timeIntervalSince1970: 1_700_000_001)
        let originalState = powerModeApplicationState(selectedAIModel: "original")
        let plan = RomaPowerModeSessionBeginPlan.plan(activeSession: nil)

        XCTAssertEqual(
            powerModeSessionBeginEvents(
                for: plan,
                id: id,
                startTime: startTime,
                originalState: originalState
            ),
            [
                "save:\(id.uuidString):1700000001.0:original",
                "installObserver"
            ]
        )
    }

    func testPowerModeSessionBeginPlanKeepsExistingSession() {
        var stateBuildCount = 0
        func newOriginalState() -> RomaPowerModeApplicationState {
            stateBuildCount += 1
            return powerModeApplicationState(selectedAIModel: "new")
        }

        let existingSession = RomaPowerModeSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_700_000_002),
            originalState: powerModeApplicationState(selectedAIModel: "existing")
        )
        let plan = RomaPowerModeSessionBeginPlan.plan(activeSession: existingSession)

        XCTAssertEqual(
            powerModeSessionBeginEvents(
                for: plan,
                id: UUID(),
                startTime: Date(timeIntervalSince1970: 1_700_000_003),
                originalState: newOriginalState()
            ),
            []
        )
        XCTAssertEqual(stateBuildCount, 0)
    }

    func testPowerModeSessionSnapshotPlanSkipsApplyingOrMissingSession() {
        let activeSession = RomaPowerModeSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_700_000_004),
            originalState: powerModeApplicationState(selectedAIModel: "existing")
        )

        let applyingPlan = RomaPowerModeSessionSnapshotPlan.plan(
            isApplyingPowerModeConfiguration: true,
            activeSession: activeSession
        )
        let missingPlan = RomaPowerModeSessionSnapshotPlan.plan(
            isApplyingPowerModeConfiguration: false,
            activeSession: nil
        )

        XCTAssertEqual(
            powerModeSessionSnapshotEvents(
                for: applyingPlan,
                currentState: powerModeApplicationState(selectedAIModel: "ignored")
            ),
            []
        )
        XCTAssertEqual(
            powerModeSessionSnapshotEvents(
                for: missingPlan,
                currentState: powerModeApplicationState(selectedAIModel: "ignored")
            ),
            []
        )
    }

    func testPowerModeSessionSnapshotPlanUpdatesOriginalStateWhenIdle() {
        let id = UUID()
        let startTime = Date(timeIntervalSince1970: 1_700_000_005)
        let activeSession = RomaPowerModeSession(
            id: id,
            startTime: startTime,
            originalState: powerModeApplicationState(selectedAIModel: "old")
        )
        let currentState = powerModeApplicationState(selectedAIModel: "current")
        let plan = RomaPowerModeSessionSnapshotPlan.plan(
            isApplyingPowerModeConfiguration: false,
            activeSession: activeSession
        )

        XCTAssertEqual(
            powerModeSessionSnapshotEvents(for: plan, currentState: currentState),
            ["save:\(id.uuidString):1700000005.0:current"]
        )
    }

    private func powerModeSessionBeginEvents(
        for plan: RomaPowerModeSessionBeginPlan,
        id: UUID,
        startTime: Date,
        originalState: @autoclosure () -> RomaPowerModeApplicationState
    ) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            id: id,
            startTime: startTime,
            originalState: originalState(),
            saveSession: { session in
                events.append(powerModeSessionEvent(prefix: "save", session: session))
            },
            installSettingsObserver: { events.append("installObserver") }
        )

        return events
    }

    private func powerModeSessionSnapshotEvents(
        for plan: RomaPowerModeSessionSnapshotPlan,
        currentState: @autoclosure () -> RomaPowerModeApplicationState
    ) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            currentState: currentState(),
            saveSession: { session in
                events.append(powerModeSessionEvent(prefix: "save", session: session))
            }
        )

        return events
    }

    private func powerModeSessionEvent(
        prefix: String,
        session: RomaPowerModeSession
    ) -> String {
        "\(prefix):\(session.id.uuidString):\(session.startTime.timeIntervalSince1970):\(session.originalState.selectedAIModel ?? "nil")"
    }

    func testPowerModeSessionRecoveryPlanSkipsMissingSession() {
        let plan = RomaPowerModeSessionRecoveryPlan.plan(activeSession: nil)

        XCTAssertEqual(powerModeSessionRecoveryEvents(for: plan), [])
    }

    func testPowerModeSessionRecoveryPlanLogsBeforeSchedulingEndSession() {
        let session = RomaPowerModeSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_700_000_006),
            originalState: powerModeApplicationState(selectedAIModel: "existing")
        )
        let plan = RomaPowerModeSessionRecoveryPlan.plan(activeSession: session)

        XCTAssertEqual(powerModeSessionRecoveryEvents(for: plan), ["log", "scheduleEndSession"])
    }

    private func powerModeSessionRecoveryEvents(
        for plan: RomaPowerModeSessionRecoveryPlan
    ) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            logRecoveringAbandonedSession: { events.append("log") },
            scheduleEndSession: { events.append("scheduleEndSession") }
        )

        return events
    }

    func testAutoSendKeyPreservesStoredValuesPickerOrderAndLabels() {
        XCTAssertEqual(
            RomaAutoSendKey.allCases,
            [.none, .enter, .shiftEnter, .commandEnter]
        )
        XCTAssertEqual(RomaAutoSendKey.none.rawValue, "none")
        XCTAssertEqual(RomaAutoSendKey.enter.rawValue, "enter")
        XCTAssertEqual(RomaAutoSendKey.shiftEnter.rawValue, "shiftEnter")
        XCTAssertEqual(RomaAutoSendKey.commandEnter.rawValue, "commandEnter")
        XCTAssertEqual(RomaAutoSendKey.none.displayName, "None")
        XCTAssertEqual(RomaAutoSendKey.enter.displayName, "Return (⏎)")
        XCTAssertEqual(RomaAutoSendKey.shiftEnter.displayName, "Shift + Return (⇧⏎)")
        XCTAssertEqual(RomaAutoSendKey.commandEnter.displayName, "Command + Return (⌘⏎)")
    }

    func testAutoSendKeyEnablementAndCodableShape() throws {
        XCTAssertFalse(RomaAutoSendKey.none.isEnabled)
        XCTAssertTrue(RomaAutoSendKey.enter.isEnabled)
        XCTAssertTrue(RomaAutoSendKey.shiftEnter.isEnabled)
        XCTAssertTrue(RomaAutoSendKey.commandEnter.isEnabled)

        let data = try JSONEncoder().encode(RomaAutoSendKey.commandEnter)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"commandEnter\"")
        XCTAssertEqual(
            try JSONDecoder().decode(RomaAutoSendKey.self, from: data),
            .commandEnter
        )
    }

    func testAutoSendPolicySharesDelayAfterPasteEligibility() {
        XCTAssertEqual(RomaAutoSendPolicy.defaultDelayAfterPasteNanoseconds, 120_000_000)
        XCTAssertNil(RomaAutoSendPolicy.delayAfterPasteNanoseconds(for: .none))
        XCTAssertEqual(RomaAutoSendPolicy.delayAfterPasteNanoseconds(for: .enter), 120_000_000)
        XCTAssertEqual(RomaAutoSendPolicy.delayAfterPasteNanoseconds(for: .shiftEnter), 120_000_000)
        XCTAssertEqual(RomaAutoSendPolicy.delayAfterPasteNanoseconds(for: .commandEnter), 120_000_000)
    }

    func testNormalizedWebsiteURLPreservesExistingMacOSCleanURLPolicy() {
        XCTAssertEqual(
            RomaPowerModePolicy.normalizedWebsiteURL(" HTTP://WWW.Example.COM/path "),
            "example.com/path"
        )
        XCTAssertEqual(
            RomaPowerModePolicy.normalizedWebsiteURL("https://docs.example.com"),
            "docs.example.com"
        )
    }

    func testWebsiteConfigForFormInputReturnsNilForRawEmptyInput() {
        XCTAssertNil(RomaPowerModePolicy.websiteConfigForFormInput(""))
    }

    func testWebsiteConfigForFormInputNormalizesNonEmptyInput() throws {
        let config = try XCTUnwrap(
            RomaPowerModePolicy.websiteConfigForFormInput(" HTTPS://WWW.Example.COM/docs ")
        )

        XCTAssertEqual(config.url, "example.com/docs")
    }

    func testWebsiteConfigForFormInputPreservesWhitespaceOnlyMacOSBehavior() throws {
        let config = try XCTUnwrap(
            RomaPowerModePolicy.websiteConfigForFormInput("   ")
        )

        XCTAssertEqual(config.url, "")
    }

    func testAddingWebsiteConfigAppendsSharedFormConfigAndPreservesNilInput() throws {
        let existingConfig = RomaPowerModeURLConfig(id: UUID(), url: "existing.example.com")

        let configs = try XCTUnwrap(
            RomaPowerModePolicy.addingWebsiteConfig(
                forFormInput: " HTTPS://WWW.Example.COM/docs ",
                to: [existingConfig]
            )
        )

        XCTAssertEqual(configs.map(\.url), ["existing.example.com", "example.com/docs"])
        XCTAssertNil(RomaPowerModePolicy.addingWebsiteConfig(forFormInput: "", to: [existingConfig]))
    }

    func testRemovingPowerModeFormTriggerConfigsUsesSharedIdPolicy() {
        let firstApp = RomaPowerModeAppConfig(id: UUID(), bundleIdentifier: "com.example.First", appName: "First")
        let secondApp = RomaPowerModeAppConfig(id: UUID(), bundleIdentifier: "com.example.Second", appName: "Second")
        let firstWebsite = RomaPowerModeURLConfig(id: UUID(), url: "first.example.com")
        let secondWebsite = RomaPowerModeURLConfig(id: UUID(), url: "second.example.com")

        XCTAssertEqual(
            RomaPowerModePolicy.removingAppConfig(id: firstApp.id, from: [firstApp, secondApp]).map(\.id),
            [secondApp.id]
        )
        XCTAssertEqual(
            RomaPowerModePolicy.removingWebsiteConfig(id: secondWebsite.id, from: [firstWebsite, secondWebsite]).map(\.id),
            [firstWebsite.id]
        )
    }

    func testConfigurationNameSaveabilityPreservesRawEmptyMacOSRule() {
        XCTAssertFalse(RomaPowerModePolicy.canSaveConfigurationName(""))
        XCTAssertTrue(RomaPowerModePolicy.canSaveConfigurationName("   "))
        XCTAssertTrue(RomaPowerModePolicy.canSaveConfigurationName("Writing"))
    }

    func testMatchingWebsiteRuleUsesEnabledOrderAndSubstringPolicy() {
        let disabled = rule(
            name: "Disabled",
            websiteRules: [RomaPowerModeWebsiteRule(url: "docs.example.com")],
            isEnabled: false
        )
        let firstEnabled = rule(
            name: "Docs",
            websiteRules: [RomaPowerModeWebsiteRule(url: "example.com/docs")]
        )
        let secondEnabled = rule(
            name: "Example",
            websiteRules: [RomaPowerModeWebsiteRule(url: "example.com")]
        )

        let match = RomaPowerModePolicy.matchingRule(
            forWebsiteURL: "https://www.example.com/docs/new",
            in: [disabled, firstEnabled, secondEnabled]
        )

        XCTAssertEqual(match?.id, firstEnabled.id)
    }

    func testMatchingWebsiteRulePreservesEmptyRuleURLRejection() {
        let emptyWebsiteRule = rule(
            name: "Empty",
            websiteRules: [RomaPowerModeWebsiteRule(url: "")]
        )

        XCTAssertNil(
            RomaPowerModePolicy.matchingRule(
                forWebsiteURL: "https://example.com",
                in: [emptyWebsiteRule]
            )
        )
    }

    func testMatchingAppRuleUsesExactEnabledBundleIdentifier() {
        let disabled = rule(
            name: "Disabled",
            appRules: [RomaPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")],
            isEnabled: false
        )
        let enabled = rule(
            name: "Enabled",
            appRules: [RomaPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")]
        )

        XCTAssertEqual(
            RomaPowerModePolicy.matchingRule(
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
            websiteRules: [RomaPowerModeWebsiteRule(url: "example.com")]
        )
        let app = rule(
            name: "App",
            appRules: [RomaPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")]
        )
        let enabledDefault = rule(name: "Default", isDefault: true)

        XCTAssertTrue(RomaPowerModePolicy.hasEnabledAutomaticRules(in: [disabledDefault, app]))
        XCTAssertFalse(RomaPowerModePolicy.hasEnabledAutomaticRules(in: [disabledDefault]))
        XCTAssertTrue(RomaPowerModePolicy.hasEnabledWebsiteRules(in: [disabledDefault, website]))
        XCTAssertFalse(RomaPowerModePolicy.hasEnabledWebsiteRules(in: [disabledDefault, app]))
        XCTAssertEqual(RomaPowerModePolicy.defaultRule(in: [disabledDefault, enabledDefault])?.id, enabledDefault.id)
    }

    func testPowerModeConfigurationListQueriesUseSharedRulePolicy() {
        let disabledDefault = config(name: "Disabled", emoji: "D", isEnabled: false, isDefault: true)
        let websiteConfig = config(
            name: "Website",
            emoji: "W",
            urlConfigs: [RomaPowerModeURLConfig(url: "example.com/docs")]
        )
        let appConfig = config(
            name: "App",
            emoji: "A",
            appConfigs: [RomaPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "App")]
        )
        let configs = [disabledDefault, websiteConfig, appConfig]

        XCTAssertEqual(configs.powerModeConfiguration(with: appConfig.id)?.id, appConfig.id)
        XCTAssertEqual(configs.enabledPowerModeConfigurations.map(\.id), [websiteConfig.id, appConfig.id])
        XCTAssertTrue(configs.hasEnabledPowerModeConfigurations)
        XCTAssertFalse([disabledDefault].hasEnabledPowerModeConfigurations)
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

    func testPowerModeConfigurationListSelectsMiniRecorderShortcutByEnabledIndex() {
        let disabled = config(name: "Disabled", emoji: "D", isEnabled: false)
        let firstEnabled = config(name: "First", emoji: "F")
        let secondEnabled = config(name: "Second", emoji: "S")
        let configs = [disabled, firstEnabled, secondEnabled]

        XCTAssertEqual(
            configs.powerModeConfigurationForMiniRecorderShortcut(index: 0)?.id,
            firstEnabled.id
        )
        XCTAssertEqual(
            configs.powerModeConfigurationForMiniRecorderShortcut(index: 1)?.id,
            secondEnabled.id
        )
    }

    func testPowerModeConfigurationListRejectsMiniRecorderShortcutOutsideEnabledRange() {
        let configs = [config(name: "Only", emoji: "O")]

        XCTAssertNil(configs.powerModeConfigurationForMiniRecorderShortcut(index: -1))
        XCTAssertNil(configs.powerModeConfigurationForMiniRecorderShortcut(index: 1))
        XCTAssertNil([PowerModeConfig]().powerModeConfigurationForMiniRecorderShortcut(index: 0))
        XCTAssertNil(
            [config(name: "Disabled", emoji: "D", isEnabled: false)]
                .powerModeConfigurationForMiniRecorderShortcut(index: 0)
        )
    }

    func testPowerModeShortcutEntriesIncludeOnlyEnabledConfigurationsWithShortcuts() {
        let disabled = config(name: "Disabled", emoji: "D", isEnabled: false)
        let firstEnabled = config(name: "First", emoji: "F")
        let secondEnabled = config(name: "Second", emoji: "S")
        let configs = [disabled, firstEnabled, secondEnabled]

        let entries = configs.powerModeShortcutEntries { id -> String? in
            switch id {
            case disabled.id:
                return "disabled"
            case firstEnabled.id:
                return "first"
            default:
                return nil
            }
        }

        XCTAssertEqual(entries.map(\.configuration.id), [firstEnabled.id])
        XCTAssertEqual(entries.map(\.shortcut), ["first"])
    }

    func testPowerModeShortcutConfigurationIdRequiresEnabledConfigAndStoredShortcut() {
        let disabled = config(name: "Disabled", emoji: "D", isEnabled: false)
        let firstEnabled = config(name: "First", emoji: "F")
        let secondEnabled = config(name: "Second", emoji: "S")
        let missing = UUID(uuidString: "00000000-0000-0000-0000-000000000304")!
        let configs = [disabled, firstEnabled, secondEnabled]

        XCTAssertEqual(
            configs.powerModeShortcutConfigurationId(
                for: firstEnabled.id,
                shortcutExists: { $0 == firstEnabled.id }
            ),
            firstEnabled.id
        )
        XCTAssertNil(
            configs.powerModeShortcutConfigurationId(
                for: disabled.id,
                shortcutExists: { _ in true }
            )
        )
        XCTAssertNil(
            configs.powerModeShortcutConfigurationId(
                for: secondEnabled.id,
                shortcutExists: { _ in false }
            )
        )
        XCTAssertNil(
            configs.powerModeShortcutConfigurationId(
                for: missing,
                shortcutExists: { _ in true }
            )
        )
    }

    func testPowerModeShortcutImportPlanKeepsOnlyImportedConfigurationKeys() {
        let importedId = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let secondImportedId = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let unimportedId = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let importedBackupKey = importedId.uuidString.lowercased()

        let imports = RomaPowerModePolicy.powerModeShortcutImports(
            backupKeys: [
                importedBackupKey,
                "not-a-uuid",
                unimportedId.uuidString,
                secondImportedId.uuidString
            ],
            importedConfigurations: [
                config(id: importedId, name: "Imported", emoji: "I"),
                config(id: secondImportedId, name: "Second", emoji: "S")
            ]
        )

        XCTAssertEqual(
            imports,
            [
                RomaPowerModeShortcutImport(backupKey: importedBackupKey, id: importedId),
                RomaPowerModeShortcutImport(backupKey: secondImportedId.uuidString, id: secondImportedId)
            ]
        )
    }

    func testPowerModeBackupExportPlanAppliesMacOSExportRuntimeState() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
        let secondId = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
        let configurations = [
            config(id: firstId, name: "First", emoji: "F"),
            config(id: secondId, name: "Second", emoji: "S")
        ]

        let plan = RomaPowerModePolicy.powerModeBackupExportPlan(
            configurations: configurations,
            customEmojis: ["F", "S"]
        )

        XCTAssertEqual(
            backupExportRuntimeEvents(
                for: plan,
                shortcutBackups: [
                    firstId: "First Shortcut"
                ]
            ),
            [
                "configs:\(firstId.uuidString),\(secondId.uuidString)",
                "shortcuts:\(firstId.uuidString)=First Shortcut",
                "emojis:F,S"
            ]
        )
    }

    func testPowerModeBackupExportPlanOmitsShortcutBackupsWhenNoShortcutsExist() {
        let firstId = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
        let secondId = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
        let plan = RomaPowerModePolicy.powerModeBackupExportPlan(
            configurations: [
                config(id: firstId, name: "First", emoji: "F"),
                config(id: secondId, name: "Second", emoji: "S")
            ],
            customEmojis: []
        )

        XCTAssertEqual(
            backupExportRuntimeEvents(for: plan),
            [
                "configs:\(firstId.uuidString),\(secondId.uuidString)",
                "shortcuts:nil",
                "emojis:"
            ]
        )
    }

    func testPowerModeBackupImportPlanPreservesMacOSImportSequencingInputs() {
        let existingId = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let secondExistingId = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let importedId = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
        let secondImportedId = UUID(uuidString: "00000000-0000-0000-0000-000000000404")!
        let unimportedId = UUID(uuidString: "00000000-0000-0000-0000-000000000405")!
        let importedConfigurations = [
            config(id: importedId, name: "Imported", emoji: "I"),
            config(id: secondImportedId, name: "Second", emoji: "S")
        ]

        let plan = RomaPowerModePolicy.powerModeBackupImportPlan(
            existingConfigurations: [
                config(id: existingId, name: "Existing", emoji: "E"),
                config(id: secondExistingId, name: "Second Existing", emoji: "X")
            ],
            importedConfigurations: importedConfigurations,
            backupShortcutKeys: [
                importedId.uuidString.lowercased(),
                "not-a-uuid",
                unimportedId.uuidString,
                secondImportedId.uuidString
            ],
            customEmojis: ["I", "S"]
        )

        let events = backupImportRuntimeEvents(
            for: plan,
            shortcutBackups: [
                importedId.uuidString.lowercased(): "Imported Shortcut",
                secondImportedId.uuidString: "Second Shortcut"
            ]
        )

        XCTAssertEqual(
            events,
            [
                "clear:\(existingId.uuidString)",
                "clear:\(secondExistingId.uuidString)",
                "set:\(importedId.uuidString),\(secondImportedId.uuidString)",
                "shortcut:Imported Shortcut:\(importedId.uuidString)",
                "shortcut:Second Shortcut:\(secondImportedId.uuidString)",
                "save",
                "emoji:I",
                "emoji:S",
                "count:2"
            ]
        )
    }

    func testPowerModeBackupImportPlanTreatsMissingCustomEmojiRecordsAsNoOps() {
        let plan = RomaPowerModePolicy.powerModeBackupImportPlan(
            existingConfigurations: [],
            importedConfigurations: [],
            backupShortcutKeys: [],
            customEmojis: nil
        )

        XCTAssertEqual(
            backupImportRuntimeEvents(for: plan),
            [
                "set:",
                "save",
                "count:0"
            ]
        )
    }

    func testResolvedPowerModeConfigurationPreservesAutomaticResolutionOrder() {
        let explicitDisabled = config(name: "Explicit", emoji: "E", isEnabled: false)
        let appConfig = config(
            name: "App",
            emoji: "A",
            appConfigs: [RomaPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "App")]
        )
        let defaultConfig = config(name: "Default", emoji: "D", isDefault: true)
        let websiteConfig = config(
            name: "Website",
            emoji: "W",
            urlConfigs: [RomaPowerModeURLConfig(url: "example.com/docs")]
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

    func testPowerModeAutomaticResolutionPlanAvoidsUnneededRuntimeLookup() async {
        let explicitConfig = config(name: "Explicit", emoji: "E", isEnabled: false)
        var lookupCount = 0

        let explicitResult = await RomaPowerModeAutomaticResolutionPlan.resolving(
            configurations: [explicitConfig],
            explicitID: explicitConfig.id
        ).applyRuntimeState(
            frontmostApplicationBundleIdentifier: {
                lookupCount += 1
                return "com.example.App"
            },
            readCurrentWebsiteURL: { _ in
                lookupCount += 1
                return "https://example.com"
            },
            logBrowserURLFailure: { _ in lookupCount += 1 }
        )

        XCTAssertEqual(explicitResult?.id, explicitConfig.id)
        XCTAssertEqual(lookupCount, 0)

        let disabledResult = await RomaPowerModeAutomaticResolutionPlan.resolving(
            configurations: [config(name: "Disabled", emoji: "D", isEnabled: false)]
        ).applyRuntimeState(
            frontmostApplicationBundleIdentifier: {
                lookupCount += 1
                return "com.example.App"
            },
            readCurrentWebsiteURL: { _ in
                lookupCount += 1
                return "https://example.com"
            },
            logBrowserURLFailure: { _ in lookupCount += 1 }
        )

        XCTAssertNil(disabledResult)
        XCTAssertEqual(lookupCount, 0)
    }

    func testPowerModeAutomaticResolutionPlanReadsBrowserURLBeforeAppFallback() async {
        let websiteConfig = config(
            name: "Website",
            emoji: "W",
            urlConfigs: [RomaPowerModeURLConfig(url: "example.com/docs")]
        )
        let appConfig = config(
            name: "App",
            emoji: "A",
            appConfigs: [RomaPowerModeAppConfig(bundleIdentifier: "com.google.Chrome", appName: "Chrome")]
        )
        let defaultConfig = config(name: "Default", emoji: "D", isDefault: true)
        let configs = [websiteConfig, appConfig, defaultConfig]
        var events = [String]()

        let websiteResult = await RomaPowerModeAutomaticResolutionPlan.resolving(
            configurations: configs
        ).applyRuntimeState(
            frontmostApplicationBundleIdentifier: {
                events.append("frontmost")
                return "com.google.Chrome"
            },
            readCurrentWebsiteURL: { browser in
                events.append("browser:\(browser.displayName)")
                return "https://www.example.com/docs/today"
            },
            logBrowserURLFailure: { events.append("log:\($0)") }
        )

        XCTAssertEqual(websiteResult?.id, websiteConfig.id)
        XCTAssertEqual(events, ["frontmost", "browser:Google Chrome"])

        events.removeAll()
        let appResult = await RomaPowerModeAutomaticResolutionPlan.resolving(
            configurations: configs
        ).applyRuntimeState(
            frontmostApplicationBundleIdentifier: {
                events.append("frontmost")
                return "com.google.Chrome"
            },
            readCurrentWebsiteURL: { browser in
                events.append("browser:\(browser.displayName)")
                throw PowerModeResolutionTestError()
            },
            logBrowserURLFailure: { events.append("log:\($0)") }
        )

        XCTAssertEqual(appResult?.id, appConfig.id)
        XCTAssertEqual(
            events,
            [
                "frontmost",
                "browser:Google Chrome",
                "log:\(RomaPowerModeBrowserDetectionDiagnostics.urlLookupFailedMessage(browserDisplayName: "Google Chrome", localizedDescription: "offline"))"
            ]
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

        let appConfig = RomaPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "App")
        let urlConfig = RomaPowerModeURLConfig(url: "example.com")
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

    func testPowerModeConfigurationListSaveAppliesDefaultAndMutationMode() throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        var configs = [
            config(id: firstID, name: "First", emoji: "F", isDefault: true),
            config(id: secondID, name: "Second", emoji: "S")
        ]

        XCTAssertTrue(
            configs.savePowerModeConfiguration(
                config(id: thirdID, name: "Third", emoji: "T", isDefault: true),
                mode: .add
            )
        )
        XCTAssertFalse(try XCTUnwrap(configs.powerModeConfiguration(with: firstID)).isDefault)
        XCTAssertFalse(try XCTUnwrap(configs.powerModeConfiguration(with: secondID)).isDefault)
        XCTAssertTrue(try XCTUnwrap(configs.powerModeConfiguration(with: thirdID)).isDefault)

        XCTAssertTrue(
            configs.savePowerModeConfiguration(
                config(id: secondID, name: "Second Updated", emoji: "U", isDefault: true),
                mode: .edit(secondID)
            )
        )
        XCTAssertFalse(try XCTUnwrap(configs.powerModeConfiguration(with: thirdID)).isDefault)
        XCTAssertEqual(configs.powerModeConfiguration(with: secondID)?.name, "Second Updated")
        XCTAssertTrue(try XCTUnwrap(configs.powerModeConfiguration(with: secondID)).isDefault)

        XCTAssertFalse(
            configs.savePowerModeConfiguration(
                config(id: firstID, name: "Duplicate", emoji: "D"),
                mode: .add
            )
        )
        XCTAssertFalse(
            configs.savePowerModeConfiguration(
                config(id: UUID(), name: "Missing", emoji: "M"),
                mode: .edit(UUID())
            )
        )
    }

    func testPowerModeConfigurationMutationPlanAppliesManagerRuntimeOrdering() throws {
        let firstID = UUID()
        let secondID = UUID()
        let missingID = UUID()
        var runtimeConfigs = [
            config(id: firstID, name: "First", emoji: "F", isEnabled: true)
        ]

        func apply(_ plan: RomaPowerModeConfigurationMutationPlan) -> [String] {
            var events = [String]()
            plan.applyRuntimeState(
                setConfigurations: {
                    runtimeConfigs = $0
                    events.append("set:\($0.map(\.id).count)")
                },
                removeShortcutStorageForConfiguration: { events.append("remove:\($0 == missingID)") },
                saveConfigurations: { events.append("save") },
                postShortcutAvailabilityDidChange: { events.append("shortcut") }
            )
            return events
        }

        let addPlan = RomaPowerModeConfigurationMutationPlan.saving(
            config(id: secondID, name: "Second", emoji: "S", isEnabled: true),
            mode: .add,
            in: runtimeConfigs
        )
        XCTAssertTrue(addPlan.didMutate)
        XCTAssertEqual(apply(addPlan), ["set:2", "save", "shortcut"])
        XCTAssertEqual(runtimeConfigs.map(\.id), [firstID, secondID])

        var disabledFirst = try XCTUnwrap(runtimeConfigs.powerModeConfiguration(with: firstID))
        disabledFirst.isEnabled = false
        let updatePlan = RomaPowerModeConfigurationMutationPlan.updating(
            disabledFirst,
            in: runtimeConfigs
        )
        XCTAssertTrue(updatePlan.didMutate)
        XCTAssertEqual(apply(updatePlan), ["set:2", "save", "shortcut"])
        XCTAssertFalse(try XCTUnwrap(runtimeConfigs.powerModeConfiguration(with: firstID)).isEnabled)

        let appConfig = RomaPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "App")
        let appPlan = RomaPowerModeConfigurationMutationPlan.addingAppConfig(
            appConfig,
            toConfigurationID: firstID,
            in: runtimeConfigs
        )
        XCTAssertTrue(appPlan.didMutate)
        XCTAssertEqual(apply(appPlan), ["set:2", "save"])
        XCTAssertEqual(runtimeConfigs.powerModeConfiguration(with: firstID)?.appConfigs?.map(\.id), [appConfig.id])

        let missingRemovePlan = RomaPowerModeConfigurationMutationPlan.removing(
            id: missingID,
            from: runtimeConfigs
        )
        XCTAssertFalse(missingRemovePlan.didMutate)
        XCTAssertEqual(apply(missingRemovePlan), ["remove:true", "save"])

        let invalidMovePlan = RomaPowerModeConfigurationMutationPlan.moving(
            fromOffsets: IndexSet([99]),
            toOffset: 0,
            in: runtimeConfigs
        )
        XCTAssertFalse(invalidMovePlan.didMutate)
        XCTAssertEqual(apply(invalidMovePlan), ["save"])
    }

    func testPowerModeActivationPlanAppliesActiveSelectionBeforeSessionStart() async {
        let configID = UUID()
        let selectedConfig = config(id: configID, name: "Meeting", emoji: "M")
        var events = [String]()

        await RomaPowerModeActivationPlan.activating(selectedConfig).applyRuntimeState(
            setActiveConfiguration: { config in
                events.append("active:\(config.id == configID)")
            },
            beginSession: { config in
                events.append("session:\(config.id == configID)")
            }
        )

        XCTAssertEqual(events, ["active:true", "session:true"])

        events.removeAll()
        await RomaPowerModeActivationPlan.activating(nil).applyRuntimeState(
            setActiveConfiguration: { _ in events.append("active") },
            beginSession: { _ in events.append("session") }
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testPowerModeActiveConfigurationRestorePlanClearsMissingAndStaleSelection() {
        let configID = UUID()
        let existingConfig = config(id: configID, name: "Meeting", emoji: "M")

        XCTAssertEqual(
            powerModeActiveConfigurationRestoreEvents(
                configurations: [existingConfig],
                activeConfigurationID: nil
            ),
            ["active:nil"]
        )
        XCTAssertEqual(
            powerModeActiveConfigurationRestoreEvents(
                configurations: [existingConfig],
                activeConfigurationID: UUID()
            ),
            ["active:nil"]
        )
    }

    func testPowerModeActiveConfigurationRestorePlanRestoresMatchingConfiguration() {
        let configID = UUID()
        let existingConfig = config(id: configID, name: "Meeting", emoji: "M")

        XCTAssertEqual(
            powerModeActiveConfigurationRestoreEvents(
                configurations: [existingConfig],
                activeConfigurationID: configID
            ),
            ["active:Meeting"]
        )
    }

    func testPowerModeRecordingFinishPlanSkipsWhenPreferencesPersist() async {
        var events = [String]()

        await RomaPowerModeRecordingFinishPlan.finishingRecording(
            shouldPersistConfiguredPreferences: true
        ).applyRuntimeState(
            endSession: { events.append("endSession") },
            clearActiveConfiguration: { events.append("clearActiveConfiguration") }
        )

        XCTAssertEqual(events, [])
    }

    func testPowerModeRecordingFinishPlanEndsSessionBeforeClearingActiveConfig() async {
        var events = [String]()

        await RomaPowerModeRecordingFinishPlan.finishingRecording(
            shouldPersistConfiguredPreferences: false
        ).applyRuntimeState(
            endSession: { events.append("endSession") },
            clearActiveConfiguration: { events.append("clearActiveConfiguration") }
        )

        XCTAssertEqual(events, ["endSession", "clearActiveConfiguration"])
    }

    func testValidationRejectsBlankAndDuplicateNameWithoutNormalizingName() {
        let existing = rule(name: "Writing")
        let blankCandidate = rule(name: " ")
        let duplicateCandidate = rule(name: "Writing")
        let spacedCandidate = rule(name: " Writing ")

        XCTAssertEqual(
            RomaPowerModePolicy.validateForSave(
                candidate: blankCandidate,
                mode: .add,
                existing: [existing]
            ),
            [.emptyName]
        )
        XCTAssertEqual(
            RomaPowerModePolicy.validateForSave(
                candidate: duplicateCandidate,
                mode: .add,
                existing: [existing]
            ),
            [.duplicateName("Writing")]
        )
        XCTAssertEqual(
            RomaPowerModePolicy.validateForSave(
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
            appRules: [RomaPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Old Name")],
            websiteRules: [RomaPowerModeWebsiteRule(url: "example.com")]
        )
        let candidate = rule(
            id: editedID,
            name: "Candidate",
            appRules: [RomaPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "New Name")],
            websiteRules: [RomaPowerModeWebsiteRule(url: "example.com")]
        )

        XCTAssertEqual(
            RomaPowerModePolicy.validateForSave(
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
            websiteRules: [RomaPowerModeWebsiteRule(url: "example.com")]
        )
        let normalizedSameCandidate = rule(
            name: "Candidate",
            websiteRules: [RomaPowerModeWebsiteRule(url: "https://www.example.com")]
        )

        XCTAssertEqual(
            RomaPowerModePolicy.validateForSave(
                candidate: normalizedSameCandidate,
                mode: .add,
                existing: [existing]
            ),
            []
        )
    }

    func testConfigurationFormSavePlanValidatesBeforeApplyingRuntimeSave() {
        let invalidDraft = RomaPowerModeConfigurationDraft(
            id: UUID(),
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: false
        )
        let validDraft = RomaPowerModeConfigurationDraft(
            id: UUID(),
            name: "Coding",
            emoji: "C",
            isAIEnhancementEnabled: false
        )
        let existing = rule(name: "Writing")
        let invalidPlan = RomaPowerModePolicy.formSavePlan(
            draft: invalidDraft,
            mode: .add,
            existing: [existing]
        )
        let validPlan = RomaPowerModePolicy.formSavePlan(
            draft: validDraft,
            mode: .add,
            existing: [existing]
        )

        XCTAssertEqual(
            invalidPlan.validationErrors,
            [RomaPowerModeValidationError.duplicateName("Writing")]
        )
        XCTAssertTrue(validPlan.validationErrors.isEmpty)

        var invalidEvents = [String]()
        invalidPlan.applyRuntimeState(
            setValidationErrors: { invalidEvents.append("errors:\($0.count)") },
            showValidationAlert: { invalidEvents.append("alert") },
            saveConfiguration: { config, _ in invalidEvents.append("save:\(config.name)") },
            markSaved: { invalidEvents.append("saved") },
            dismiss: { invalidEvents.append("dismiss") }
        )

        var validEvents = [String]()
        validPlan.applyRuntimeState(
            setValidationErrors: { validEvents.append("errors:\($0.count)") },
            showValidationAlert: { validEvents.append("alert") },
            saveConfiguration: { config, saveMode in
                validEvents.append("save:\(config.name):\(saveMode == .add)")
            },
            markSaved: { validEvents.append("saved") },
            dismiss: { validEvents.append("dismiss") }
        )

        XCTAssertEqual(invalidEvents, ["errors:1", "alert"])
        XCTAssertEqual(validEvents, ["errors:0", "save:Coding:true", "saved", "dismiss"])
    }

    func testConfigurationModePreservesFormTitlesAndSaveModes() {
        let id = UUID()
        let editMode = RomaPowerModeConfigurationMode.edit(
            config(id: id, name: "Writing", emoji: "W")
        )

        XCTAssertTrue(RomaPowerModeConfigurationMode.add.isAdding)
        XCTAssertFalse(editMode.isAdding)
        XCTAssertEqual(RomaPowerModeConfigurationMode.add.title, "Add Power Mode")
        XCTAssertEqual(editMode.title, "Edit Power Mode")
        XCTAssertEqual(RomaPowerModeConfigurationMode.add.saveMode, .add)
        XCTAssertEqual(editMode.saveMode, .edit(id))
    }

    func testConfigurationModePlansUnsavedAddShortcutCleanupOnDismiss() {
        let id = UUID()
        let editMode = RomaPowerModeConfigurationMode.edit(
            config(id: id, name: "Writing", emoji: "W")
        )

        XCTAssertEqual(
            RomaPowerModeConfigurationMode.add.dismissalPlan(didSaveConfiguration: false),
            RomaPowerModeConfigurationFormDismissalPlan(shouldRemoveUnsavedShortcut: true)
        )
        XCTAssertEqual(
            RomaPowerModeConfigurationMode.add.dismissalPlan(didSaveConfiguration: true),
            RomaPowerModeConfigurationFormDismissalPlan(shouldRemoveUnsavedShortcut: false)
        )
        XCTAssertEqual(
            editMode.dismissalPlan(didSaveConfiguration: false),
            RomaPowerModeConfigurationFormDismissalPlan(shouldRemoveUnsavedShortcut: false)
        )

        var events = [String]()
        RomaPowerModeConfigurationMode.add
            .dismissalPlan(didSaveConfiguration: false)
            .applyRuntimeState {
                events.append("remove")
            }
        RomaPowerModeConfigurationMode.add
            .dismissalPlan(didSaveConfiguration: true)
            .applyRuntimeState {
                events.append("remove")
            }

        XCTAssertEqual(events, ["remove"])
    }

    func testConfigurationModeAppearPlanRepairsAddSelections() {
        let promptID = UUID()
        let prompt = RomaCustomPrompt(id: promptID, title: "Rewrite", promptText: "Rewrite this")
        let enhancementSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: ""
        )
        let transcriptionSelection = RomaPowerModeTranscriptionSelection(
            selectedModelName: "base",
            selectedLanguage: nil
        )

        let plan = RomaPowerModeConfigurationMode.add.appearPlan(
            enhancementSelection: enhancementSelection,
            isAIEnhancementEnabled: true,
            prompts: [prompt],
            currentAIProvider: .groq,
            currentAIModel: "llama-3.3",
            transcriptionSelection: transcriptionSelection,
            selectedTranscriptionModelFacts: transcriptionModelFacts(
                name: "base",
                languageOptions: ["en": "English", "fr": "French"]
            ),
            storedLanguage: "fr"
        )

        XCTAssertEqual(
            plan.enhancementSelection,
            RomaPowerModeEnhancementSelection(
                selectedPromptId: promptID,
                selectedAIProvider: "Groq",
                selectedAIModel: "llama-3.3"
            )
        )
        XCTAssertEqual(
            plan.transcriptionSelection,
            RomaPowerModeTranscriptionSelection(
                selectedModelName: "base",
                selectedLanguage: "fr"
            )
        )

        var events = [String]()
        plan.applyRuntimeState(
            applyEnhancementSelection: { events.append("enhancement:\($0.selectedAIProvider ?? "nil")") },
            applyTranscriptionSelection: { events.append("language:\($0.selectedLanguage ?? "nil")") }
        )
        XCTAssertEqual(events, ["enhancement:Groq", "language:fr"])
    }

    func testConfigurationModeAppearPlanKeepsEditProviderAndSkipsUnsupportedLanguageRepair() {
        let id = UUID()
        let editMode = RomaPowerModeConfigurationMode.edit(
            config(id: id, name: "Writing", emoji: "W")
        )
        let enhancementSelection = RomaPowerModeEnhancementSelection(
            selectedPromptId: nil,
            selectedAIProvider: nil,
            selectedAIModel: nil
        )

        let plan = editMode.appearPlan(
            enhancementSelection: enhancementSelection,
            isAIEnhancementEnabled: false,
            prompts: [RomaCustomPrompt(id: UUID(), title: "Rewrite", promptText: "Rewrite this")],
            currentAIProvider: .openAI,
            currentAIModel: "gpt-4o",
            transcriptionSelection: RomaPowerModeTranscriptionSelection(
                selectedModelName: "gemini",
                selectedLanguage: "fr"
            ),
            selectedTranscriptionModelFacts: transcriptionModelFacts(
                name: "gemini",
                disablesLanguageSelection: true
            ),
            storedLanguage: "en"
        )

        XCTAssertEqual(plan.enhancementSelection, enhancementSelection)
        XCTAssertNil(plan.transcriptionSelection)
    }

    func testConfigurationModePreservesEditIdentityByConfigId() {
        let id = UUID()
        let first = RomaPowerModeConfigurationMode.edit(
            config(id: id, name: "Writing", emoji: "W")
        )
        let renamed = RomaPowerModeConfigurationMode.edit(
            config(id: id, name: "Renamed", emoji: "R")
        )
        let other = RomaPowerModeConfigurationMode.edit(
            config(id: UUID(), name: "Writing", emoji: "W")
        )

        XCTAssertEqual(first, renamed)
        XCTAssertFalse(first == other)
    }

    private func powerModeActiveConfigurationRestoreEvents(
        configurations: [PowerModeConfig],
        activeConfigurationID: UUID?
    ) -> [String] {
        var events = [String]()
        RomaPowerModeActiveConfigurationRestorePlan.restoring(
            configurations: configurations,
            activeConfigurationID: activeConfigurationID
        ).applyRuntimeState { config in
            events.append("active:\(config?.name ?? "nil")")
        }
        return events
    }

    private func config(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        appConfigs: [RomaPowerModeAppConfig]? = nil,
        urlConfigs: [RomaPowerModeURLConfig]? = nil,
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

    private struct PowerModeResolutionTestError: LocalizedError {
        var errorDescription: String? {
            "offline"
        }
    }

    private func rule(
        id: UUID = UUID(),
        name: String,
        appRules: [RomaPowerModeAppRule] = [],
        websiteRules: [RomaPowerModeWebsiteRule] = [],
        isEnabled: Bool = true,
        isDefault: Bool = false
    ) -> RomaPowerModeRule {
        RomaPowerModeRule(
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
        languageOptions: [String: String] = RomaLanguageCatalog.all,
        prefersNativeAppleEnglish: Bool = false
    ) -> RomaPowerModeTranscriptionModelFacts {
        RomaPowerModeTranscriptionModelFacts(
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
    ) -> RomaPowerModeTranscriptionModelResourceFacts {
        RomaPowerModeTranscriptionModelResourceFacts(
            name: name,
            loadsLocalWhisperModel: loadsLocalWhisperModel
        )
    }

    private func powerModeApplicationState(
        selectedAIModel: String
    ) -> RomaPowerModeApplicationState {
        RomaPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            selectedAIProvider: "openai",
            selectedAIModel: selectedAIModel
        )
    }

    private func sessionApplicationFacts(
        currentModelName: String?,
        availableLocalModelNames: Set<String>
    ) -> RomaPowerModeSessionApplicationFacts {
        RomaPowerModeSessionApplicationFacts(
            currentModelName: currentModelName,
            availableModelResourceFacts: [
                transcriptionModelResourceFacts(name: "base", loadsLocalWhisperModel: true),
                transcriptionModelResourceFacts(name: "nova-3", loadsLocalWhisperModel: false),
                transcriptionModelResourceFacts(name: "english-only", loadsLocalWhisperModel: false)
            ],
            availableLocalModelNames: availableLocalModelNames
        )
    }

    private func backupExportRuntimeEvents(
        for plan: RomaPowerModeBackupExportPlan,
        shortcutBackups: [UUID: String] = [:]
    ) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            backupForConfiguration: { id in
                shortcutBackups[id]
            },
            setConfigurations: { configurations in
                let ids = configurations.map(\.id.uuidString).joined(separator: ",")
                events.append("configs:\(ids)")
            },
            setShortcutBackups: { backups in
                let summary = backups?
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ",") ?? "nil"
                events.append("shortcuts:\(summary)")
            },
            setCustomEmojis: { customEmojis in
                events.append("emojis:\(customEmojis.joined(separator: ","))")
            }
        )

        return events
    }

    private func backupImportRuntimeEvents(
        for plan: RomaPowerModeBackupImportPlan,
        shortcutBackups: [String: String] = [:]
    ) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            removeShortcutStorageForConfiguration: { id in
                events.append("clear:\(id.uuidString)")
            },
            setImportedConfigurations: { configurations in
                let ids = configurations.map(\.id.uuidString).joined(separator: ",")
                events.append("set:\(ids)")
            },
            shortcutBackup: { key in
                shortcutBackups[key]
            },
            importShortcut: { backup, id in
                events.append("shortcut:\(backup):\(id.uuidString)")
            },
            saveConfigurations: {
                events.append("save")
            },
            addCustomEmoji: { emoji in
                events.append("emoji:\(emoji)")
            },
            reportImportedConfigurationCount: { count in
                events.append("count:\(count)")
            }
        )

        return events
    }

    private struct PreferenceApplicationRuntime {
        var isEnhancementEnabled: Bool?
        var useScreenCaptureContext: Bool?
        var selectedPromptId: UUID?
        var didApplyPrompt = false
        var selectedAIProvider: RomaAIEnhancementProviderKind?
        var selectedAIModel: String?
        var isTextFormattingEnabled: Bool?
        var punctuationMode: PunctuationCleanupMode?
        var lowercaseTranscription: Bool?
    }

    private func preferenceApplicationRuntime(
        for application: RomaPowerModePreferenceApplication,
        startingAt initialPromptId: UUID? = nil
    ) -> PreferenceApplicationRuntime {
        var runtime = PreferenceApplicationRuntime(selectedPromptId: initialPromptId)

        application.applyRuntimeState(
            setEnhancementEnabled: { runtime.isEnhancementEnabled = $0 },
            setUseScreenCaptureContext: { runtime.useScreenCaptureContext = $0 },
            setSelectedPromptId: { selectedPromptId in
                runtime.didApplyPrompt = true
                runtime.selectedPromptId = selectedPromptId
            },
            setSelectedAIProvider: { runtime.selectedAIProvider = $0 },
            selectAIModel: { runtime.selectedAIModel = $0 },
            saveTextFormattingEnabled: { runtime.isTextFormattingEnabled = $0 },
            setPunctuationCleanupMode: { runtime.punctuationMode = $0 },
            saveLowercaseTranscription: { runtime.lowercaseTranscription = $0 }
        )

        return runtime
    }

    private func languageRuntimeEvents(
        for plan: RomaPowerModeLanguageApplicationPlan
    ) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            saveSelectedLanguage: { language in
                events.append("save:\(language)")
            },
            postLanguageDidChange: {
                events.append("post")
            }
        )

        return events
    }

    private struct SessionApplicationRuntime {
        var preferenceApplication: PreferenceApplicationRuntime?
        var modelResourcePlan: RomaPowerModeTranscriptionModelResourcePlan?
        var languageApplicationPlan: RomaPowerModeLanguageApplicationPlan?
        var didPostConfigurationApplied = false
    }

    private func sessionApplicationRuntime(
        for plan: RomaPowerModeSessionApplicationPlan
    ) async -> SessionApplicationRuntime {
        var runtime = SessionApplicationRuntime()

        await plan.applyRuntimeState(
            applyPreferenceApplication: { application in
                runtime.preferenceApplication = preferenceApplicationRuntime(for: application)
            },
            applyModelResourcePlan: { modelResourcePlan in
                runtime.modelResourcePlan = modelResourcePlan
            },
            applyLanguageApplicationPlan: { languageApplicationPlan in
                runtime.languageApplicationPlan = languageApplicationPlan
            },
            postConfigurationApplied: {
                runtime.didPostConfigurationApplied = true
            }
        )

        return runtime
    }

    private func runtimeEvents(
        for plan: RomaPowerModeTranscriptionModelResourcePlan,
        selectionSucceeds: Bool = true,
        loadError: Error? = nil
    ) async -> [String] {
        let events = PowerModeResourcePlanEvents()

        await plan.applyRuntimeState(
            setDefaultTranscriptionModelNamed: { modelName in
                await events.append("select:\(modelName)")
                return selectionSucceeds
            },
            cleanupModelResources: {
                await events.append("cleanup")
            },
            loadDownloadedLocalModelNamed: { modelName in
                await events.append("load:\(modelName)")
                if let loadError {
                    throw loadError
                }
            },
            handleLocalModelLoadFailure: { modelName, _ in
                await events.append("loadFailed:\(modelName)")
            }
        )

        return await events.values
    }

    private func jsonObject<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "RomaCore.PowerModePolicyTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        run(defaults)
    }
}

private enum PowerModeResourcePlanFixtureError: Error {
    case loadFailed
}

private actor PowerModeResourcePlanEvents {
    private var recordedEvents: [String] = []

    var values: [String] {
        recordedEvents
    }

    func append(_ event: String) {
        recordedEvents.append(event)
    }
}
