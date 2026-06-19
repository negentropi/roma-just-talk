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
}
