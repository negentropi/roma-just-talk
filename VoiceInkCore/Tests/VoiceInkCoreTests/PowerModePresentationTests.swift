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
