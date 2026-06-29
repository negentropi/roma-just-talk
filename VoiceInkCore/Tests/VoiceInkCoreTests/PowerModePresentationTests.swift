import VoiceInkCore

final class PowerModePresentationTests: XCTestCase {
    func testDisplayNameTrimsAndCombinesEmojiAndName() {
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: " Writing ", emoji: " W "), "W Writing")
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: nil, emoji: " W "), "W")
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: " Writing ", emoji: nil), "Writing")
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: " ", emoji: " "), "")
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: nil, emoji: nil), "")
    }

    func testSelectedLanguageDisplayTextPreservesPowerModeRowFallbacks() {
        XCTAssertEqual(
            VoiceInkPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: nil,
                languageOptions: ["es": "Spanish"]
            ),
            "Default"
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: "auto",
                languageOptions: ["auto": "Auto-detect"]
            ),
            "Auto"
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: "en",
                languageOptions: ["en": "English"]
            ),
            "English"
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: "es",
                languageOptions: ["es": "Spanish"]
            ),
            "Spanish"
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.selectedLanguageDisplayText(
                selectedLanguage: "zz",
                languageOptions: ["es": "Spanish"]
            ),
            "ZZ"
        )
    }

    func testTriggerCountTextPreservesPowerModeRowPluralization() {
        XCTAssertEqual(VoiceInkPowerModePresentation.appTriggerCountText(0), "")
        XCTAssertEqual(VoiceInkPowerModePresentation.appTriggerCountText(1), "1 App")
        XCTAssertEqual(VoiceInkPowerModePresentation.appTriggerCountText(2), "2 Apps")

        XCTAssertEqual(VoiceInkPowerModePresentation.websiteTriggerCountText(0), "")
        XCTAssertEqual(VoiceInkPowerModePresentation.websiteTriggerCountText(1), "1 Website")
        XCTAssertEqual(VoiceInkPowerModePresentation.websiteTriggerCountText(3), "3 Websites")
    }

    func testPanelAndSidebarChromePreservesMacOSCopy() {
        XCTAssertEqual(VoiceInkPowerModePresentation.panelTitle, "Power Modes")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.panelSubtitle,
            "Automate your workflows with context-aware configurations."
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.panelInfoTipText,
            "Automatically apply custom configurations based on the app/website you are using."
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.panelLearnMoreURLString,
            "https://tryvoiceink.com/docs/power-mode"
        )
        XCTAssertEqual(VoiceInkPowerModePresentation.settingsSectionTitle, "Power Mode")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.settingsToggleHelpText,
            "Apply custom settings based on active app or website."
        )
        XCTAssertEqual(VoiceInkPowerModePresentation.persistConfiguredPreferencesTitle, "Persist Configured Preferences")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.persistConfiguredPreferencesHelpText,
            "When enabled, Power Mode preferences stay active after you stop recording instead of reverting to your original preferences. They will only change when a different Power Mode activates."
        )
        XCTAssertEqual(VoiceInkPowerModePresentation.settingsDisableAlertTitle, "Power Mode Still Active")
        XCTAssertEqual(VoiceInkPowerModePresentation.settingsDisableAlertButtonTitle, "Got it")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.settingsDisableAlertMessage,
            "Disable or remove your Power Modes first."
        )
        XCTAssertEqual(VoiceInkPowerModePresentation.addButtonSystemImageName, "plus")
        XCTAssertEqual(VoiceInkPowerModePresentation.reorderButtonTitle, "Reorder")
        XCTAssertEqual(VoiceInkPowerModePresentation.reorderButtonSystemImageName, "arrow.up.arrow.down")
        XCTAssertEqual(VoiceInkPowerModePresentation.reorderPanelTitle, "Reorder Power Modes")
        XCTAssertEqual(VoiceInkPowerModePresentation.reorderPanelCloseHelpText, "Close")
        XCTAssertEqual(VoiceInkPowerModePresentation.reorderPanelCloseSystemImageName, "xmark")
        XCTAssertEqual(VoiceInkPowerModePresentation.reorderHandleSystemImageName, "line.3.horizontal")
        XCTAssertEqual(VoiceInkPowerModePresentation.defaultBadgeTitle, "Default")
        XCTAssertEqual(VoiceInkPowerModePresentation.disabledBadgeTitle, "Disabled")
        XCTAssertEqual(VoiceInkPowerModePresentation.emptyPanelTitle, "No Power Modes Yet")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.emptyPanelMessage,
            "Create first power mode to automate your VoiceInk workflow based on apps/website you are using"
        )
        XCTAssertEqual(VoiceInkPowerModePresentation.emptyPanelSystemImageName, "square.grid.2x2.fill")
        XCTAssertEqual(VoiceInkPowerModePresentation.sidebarEmptyTitle, "No Power Modes")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.sidebarEmptyMessage,
            "Add customized power modes for different contexts"
        )
        XCTAssertEqual(VoiceInkPowerModePresentation.sidebarEmptyButtonTitle, "Add New Power Mode")
        XCTAssertEqual(VoiceInkPowerModePresentation.sidebarEmptySystemImageName, "bolt.circle.fill")
        XCTAssertEqual(VoiceInkPowerModePresentation.addIconButtonSystemImageName, "plus.circle.fill")
    }

    func testPopoverAndRowActionChromePreservesMacOSCopy() {
        XCTAssertEqual(VoiceInkPowerModePresentation.popoverTitle, "Select Power Mode")
        XCTAssertEqual(VoiceInkPowerModePresentation.popoverEmptyTitle, "No Power Modes Available")
        XCTAssertEqual(VoiceInkPowerModePresentation.popoverEmptySystemImageName, "sparkles")
        XCTAssertEqual(VoiceInkPowerModePresentation.popoverSelectedSystemImageName, "checkmark")
        XCTAssertEqual(VoiceInkPowerModePresentation.recorderButtonFallbackIcon, "✨")
        XCTAssertEqual(VoiceInkPowerModePresentation.rowEditActionTitle, "Edit")
        XCTAssertEqual(VoiceInkPowerModePresentation.rowEditActionSystemImageName, "pencil")
        XCTAssertEqual(VoiceInkPowerModePresentation.rowDeleteActionTitle, "Delete")
        XCTAssertEqual(VoiceInkPowerModePresentation.rowDeleteActionSystemImageName, "trash")
    }

    func testRecorderButtonIconPreservesActiveEmojiFallbacks() {
        let activeConfig = PowerModeConfig(
            name: "Writing",
            emoji: "W",
            isAIEnhancementEnabled: false
        )

        XCTAssertEqual(
            VoiceInkPowerModePresentation.recorderButtonIcon(
                hasEnabledConfigurations: true,
                activeConfiguration: activeConfig
            ),
            "W"
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.recorderButtonIcon(
                hasEnabledConfigurations: true,
                activeConfiguration: nil
            ),
            "✨"
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.recorderButtonIcon(
                hasEnabledConfigurations: false,
                activeConfiguration: activeConfig
            ),
            "✨"
        )
    }

    func testConfigurationFormChromePreservesMacOSCopy() {
        XCTAssertEqual(VoiceInkPowerModePresentation.formCloseHelpText, "Close")
        XCTAssertEqual(VoiceInkPowerModePresentation.formCloseSystemImageName, "xmark")
        XCTAssertEqual(VoiceInkPowerModePresentation.generalSectionTitle, "General")
        XCTAssertEqual(VoiceInkPowerModePresentation.nameFieldPlaceholder, "Name")
        XCTAssertEqual(VoiceInkPowerModePresentation.triggerScenariosSectionTitle, "Trigger Scenarios")
        XCTAssertEqual(VoiceInkPowerModePresentation.applicationsSectionTitle, "Applications")
        XCTAssertEqual(VoiceInkPowerModePresentation.addApplicationHelpText, "Add application")
        XCTAssertEqual(VoiceInkPowerModePresentation.noApplicationsText, "No applications added")
        XCTAssertEqual(VoiceInkPowerModePresentation.appPickerSearchPlaceholder, "Search apps...")
        XCTAssertEqual(VoiceInkPowerModePresentation.appPickerSearchSystemImageName, "magnifyingglass")
        XCTAssertEqual(VoiceInkPowerModePresentation.appPickerClearSearchSystemImageName, "xmark.circle.fill")
        XCTAssertEqual(VoiceInkPowerModePresentation.appPickerSelectedSystemImageName, "checkmark")
        XCTAssertEqual(VoiceInkPowerModePresentation.websitesSectionTitle, "Websites")
        XCTAssertEqual(VoiceInkPowerModePresentation.websiteURLFieldPlaceholder, "Enter website URL")
        XCTAssertEqual(VoiceInkPowerModePresentation.addWebsiteHelpText, "Add website")
        XCTAssertEqual(VoiceInkPowerModePresentation.noWebsitesText, "No websites added")
        XCTAssertEqual(VoiceInkPowerModePresentation.transcriptionSectionTitle, "Transcription")
        XCTAssertEqual(VoiceInkPowerModePresentation.transcriptionModelPickerTitle, "Model")
        XCTAssertEqual(VoiceInkPowerModePresentation.transcriptionLanguageTitle, "Language")
        XCTAssertEqual(VoiceInkPowerModePresentation.autodetectedLanguageText, "Autodetected")
        XCTAssertEqual(VoiceInkPowerModePresentation.transcriptFormattingDisclosureSystemImageName, "chevron.right")
        XCTAssertEqual(VoiceInkPowerModePresentation.aiEnhancementSectionTitle, "AI Enhancement")
        XCTAssertEqual(VoiceInkPowerModePresentation.aiEnhancementToggleTitle, "AI Enhancement")
        XCTAssertEqual(VoiceInkPowerModePresentation.advancedSectionTitle, "Advanced")
        XCTAssertEqual(VoiceInkPowerModePresentation.formDeleteButtonTitle, "Delete")
        XCTAssertEqual(VoiceInkPowerModePresentation.formCancelButtonTitle, "Cancel")
        XCTAssertEqual(VoiceInkPowerModePresentation.formSaveButtonTitle, "Save Changes")
    }

    func testDeleteConfirmationPreservesPowerModeCopy() {
        let confirmation = VoiceInkPowerModePresentation.deleteConfirmation(configName: "Writing")

        XCTAssertEqual(confirmation.title, "Delete Power Mode?")
        XCTAssertEqual(
            confirmation.message,
            "Are you sure you want to delete the 'Writing' power mode? This action cannot be undone."
        )
        XCTAssertEqual(confirmation.primaryButtonTitle, "Delete")
        XCTAssertEqual(confirmation.cancelButtonTitle, "Cancel")
    }

    func testValidationAlertPreservesFirstPowerModeErrorCopy() {
        let alert = VoiceInkPowerModePresentation.validationAlert(errors: [.duplicateName("Writing")])

        XCTAssertEqual(alert.title, "Cannot Save Power Mode")
        XCTAssertEqual(alert.message, "A power mode with the name 'Writing' already exists.")
        XCTAssertEqual(alert.buttonTitle, "OK")
    }

    func testValidationAlertPreservesFallbackCopy() {
        let alert = VoiceInkPowerModePresentation.validationAlert(errors: [])

        XCTAssertEqual(alert.title, "Cannot Save Power Mode")
        XCTAssertEqual(alert.message, "Please fix the validation errors before saving.")
        XCTAssertEqual(alert.buttonTitle, "OK")
    }

    func testNoTranscriptionModelsAvailableTextPreservesMacOSFormCopy() {
        XCTAssertEqual(
            VoiceInkPowerModePresentation.noTranscriptionModelsAvailableText,
            "No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab."
        )
    }

    func testAIEnhancementEmptyStateTextPreservesMacOSFormCopy() {
        XCTAssertEqual(VoiceInkPowerModePresentation.noAIProvidersConnectedText, "No providers connected")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.noAIModelsAvailableText(for: .openRouter),
            "No models loaded"
        )
        XCTAssertEqual(
            VoiceInkPowerModePresentation.noAIModelsAvailableText(for: .gemini),
            "No models available"
        )
        for provider in VoiceInkAIEnhancementProviderKind.allCases {
            XCTAssertEqual(
                VoiceInkPowerModePresentation.shouldShowAIModelOptions(for: provider),
                provider != .custom,
                provider.rawValue
            )
        }
        for provider in VoiceInkAIEnhancementProviderKind.allCases {
            XCTAssertEqual(
                VoiceInkPowerModePresentation.shouldShowRefreshModelsButton(for: provider),
                provider == .openRouter,
                provider.rawValue
            )
        }
        XCTAssertEqual(VoiceInkPowerModePresentation.noEnhancementPromptsAvailableText, "No prompts available")
        XCTAssertEqual(VoiceInkPowerModePresentation.appTriggerSystemImageName, "app.fill")
        XCTAssertEqual(VoiceInkPowerModePresentation.websiteTriggerSystemImageName, "globe")
        XCTAssertEqual(VoiceInkPowerModePresentation.removeTriggerSystemImageName, "xmark.circle.fill")
    }

    func testAIEnhancementFormChromePreservesMacOSCopy() {
        XCTAssertEqual(VoiceInkPowerModePresentation.aiProviderFormTitle, "AI Provider")
        XCTAssertEqual(VoiceInkPowerModePresentation.aiModelFormTitle, "AI Model")
        XCTAssertEqual(VoiceInkPowerModePresentation.enhancementPromptFormTitle, "Enhancement Prompt")
        XCTAssertEqual(VoiceInkPowerModePresentation.contextAwarenessDisplayText, "Context Awareness")
        XCTAssertEqual(VoiceInkPowerModePresentation.refreshModelsButtonTitle, "Refresh Models")
        XCTAssertEqual(VoiceInkPowerModePresentation.refreshModelsButtonHelp, "Refresh models")
        XCTAssertEqual(VoiceInkPowerModePresentation.setAsDefaultToggleTitle, "Set as default")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.setAsDefaultHelpText,
            "Default power mode is used when no specific app or website matches are found."
        )
    }

    func testAdvancedFormChromePreservesMacOSCopy() {
        XCTAssertEqual(VoiceInkPowerModePresentation.autoSendFormTitle, "Auto Send")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.autoSendHelpText,
            "Automatically presses a key combination after pasting text. Useful for chat applications or forms that use different send shortcuts."
        )
        XCTAssertEqual(VoiceInkPowerModePresentation.keyboardShortcutFormTitle, "Keyboard Shortcut")
        XCTAssertEqual(
            VoiceInkPowerModePresentation.keyboardShortcutHelpText,
            "Assign a unique keyboard shortcut to instantly activate this Power Mode and start recording."
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

        let presentation = VoiceInkPowerModePresentation.rowDetailPresentation(
            config: config,
            transcriptionModelDisplayText: VoiceInkPowerModePresentation.defaultOverrideDisplayText,
            selectedLanguageDisplayText: VoiceInkPowerModePresentation.defaultOverrideDisplayText,
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

        let presentation = VoiceInkPowerModePresentation.rowDetailPresentation(
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
                VoiceInkAutoSendKey.commandEnter.displayName,
                VoiceInkPowerModePresentation.contextAwarenessDisplayText,
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

        let presentation = VoiceInkPowerModePresentation.rowDetailPresentation(
            config: config,
            transcriptionModelDisplayText: VoiceInkPowerModePresentation.defaultOverrideDisplayText,
            selectedLanguageDisplayText: VoiceInkPowerModePresentation.defaultOverrideDisplayText,
            selectedPromptTitle: nil
        )

        XCTAssertEqual(presentation.chips, [
            VoiceInkPowerModeRowDetailChipPresentation(
                kind: .prompt,
                text: VoiceInkPowerModePresentation.defaultPromptDisplayText
            )
        ])
    }
}
