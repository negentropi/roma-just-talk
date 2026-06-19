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
}
