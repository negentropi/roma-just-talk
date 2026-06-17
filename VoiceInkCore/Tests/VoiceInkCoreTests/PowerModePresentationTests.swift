import VoiceInkCore

final class PowerModePresentationTests: XCTestCase {
    func testDisplayNameTrimsAndCombinesEmojiAndName() {
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: " Writing ", emoji: " W "), "W Writing")
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: nil, emoji: " W "), "W")
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: " Writing ", emoji: nil), "Writing")
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: " ", emoji: " "), "")
        XCTAssertEqual(VoiceInkPowerModePresentation.displayName(name: nil, emoji: nil), "")
    }
}
