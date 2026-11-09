import Foundation
@testable import VoiceInkCore

final class LiveTypingTests: XCTestCase {
    func testOnlyWordsEveryRecentPassAgreesOnAreTyped() {
        let passes = [
            VoiceInkLiveTyping.words("The weather was warm and bright."),
            VoiceInkLiveTyping.words("The weather is warm and bright this."),
        ]

        XCTAssertEqual(VoiceInkLiveTyping.stableWords(acrossPasses: passes), ["The", "weather"])
    }

    func testPunctuationEachPassAddsAtItsEndDoesNotHoldWordsBack() {
        // Parakeet ends every pass with a period; it becomes a comma once the next word is heard.
        let passes = [
            VoiceInkLiveTyping.words("Testing one."),
            VoiceInkLiveTyping.words("Testing one, two."),
        ]

        XCTAssertEqual(VoiceInkLiveTyping.stableWords(acrossPasses: passes), ["Testing", "one"])
    }

    func testTheWordStillBeingSpokenWaits() {
        let pass = VoiceInkLiveTyping.words("Send it to fin")

        XCTAssertEqual(VoiceInkLiveTyping.stableWords(acrossPasses: [pass, pass]), ["Send", "it", "to"])
    }

    func testTypedWordsOnlyGainPunctuationAndNewWords() {
        let extended = VoiceInkLiveTyping.extend(["Testing", "one"], with: ["testing", "one,", "two"])

        XCTAssertEqual(extended, ["Testing", "one,", "two"])
    }

    func testARevisedTypedWordIsReportedAsARevision() {
        XCTAssertNil(VoiceInkLiveTyping.extend(["The", "weather", "was"], with: ["The", "weather", "is", "warm"]))
    }

    func testNewWordsAreAppendedWithoutTouchingTypedText() {
        let edit = VoiceInkLiveTyping.edit(from: "Hello there.", to: "Hello there. How are")

        XCTAssertEqual(edit.removedSuffix, "")
        XCTAssertEqual(edit.insertedText, " How are")
    }

    func testAReplacementSpanningTypedTextOnlyRewritesTheChangedTail() {
        let edit = VoiceInkLiveTyping.edit(from: "I moved to New", to: "I moved to NYC last year")

        XCTAssertEqual(edit.removedSuffix, "ew")
        XCTAssertEqual(edit.insertedText, "YC last year")
    }

    func testTypingWhileSpeakingIsOnUnlessTurnedOff() throws {
        let suiteName = "VoiceInkCore.LiveTypingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(VoiceInkLiveTypingPreference.isEnabled(from: defaults))
        defaults.set(false, forKey: VoiceInkLiveTypingPreference.userDefaultsKey)
        XCTAssertFalse(VoiceInkLiveTypingPreference.isEnabled(from: defaults))
    }
}
