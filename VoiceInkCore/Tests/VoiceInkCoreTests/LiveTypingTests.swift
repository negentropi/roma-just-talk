import Foundation
@testable import VoiceInkCore

final class LiveTypingTests: XCTestCase {
    func testRemainderIsOnlyTheTextSpokenAfterTheTypedSegments() {
        let typed = VoiceInkStreamingTranscriptAssembly.committedText(["Hello there", "how are you"])
        let final = VoiceInkStreamingTranscriptAssembly.committedText(["Hello there", "how are you", "doing today?"])

        XCTAssertEqual(
            VoiceInkLiveTyping.untypedRemainder(finalRawText: final, typedRawText: typed),
            "doing today?"
        )
    }

    func testRemainderIsEmptyWhenEverythingWasTypedDuringTheHold() {
        let typed = VoiceInkStreamingTranscriptAssembly.committedText(["Hello there"])

        XCTAssertEqual(VoiceInkLiveTyping.untypedRemainder(finalRawText: typed, typedRawText: typed), "")
    }

    func testRemainderSurvivesARepunctuatedFallbackTranscript() {
        XCTAssertEqual(
            VoiceInkLiveTyping.untypedRemainder(
                finalRawText: "Hello, there. How are you doing today?",
                typedRawText: "Hello there how are you"
            ),
            "doing today?"
        )
    }

    func testRemainderRefusesATranscriptWithDifferentWords() {
        XCTAssertNil(
            VoiceInkLiveTyping.untypedRemainder(
                finalRawText: "Yellow there, how are you doing today?",
                typedRawText: "Hello there"
            )
        )
        XCTAssertNil(VoiceInkLiveTyping.untypedRemainder(finalRawText: "Hello", typedRawText: "Hello there"))
    }

    func testOnlyWordsEveryRecentPassAgreesOnAreTyped() {
        let passes = [
            VoiceInkLiveTyping.words("The weather was warm and"),
            VoiceInkLiveTyping.words("The weather was warm and bright"),
            VoiceInkLiveTyping.words("The weather is warm and bright this"),
        ]

        XCTAssertEqual(VoiceInkLiveTyping.stableWords(acrossPasses: passes), ["The"])
    }

    func testTheLastAgreedWordWaitsForItsPunctuation() {
        let pass = VoiceInkLiveTyping.words("Send it to finance")

        XCTAssertEqual(VoiceInkLiveTyping.stableWords(acrossPasses: [pass, pass, pass]), ["Send", "it", "to"])
    }

    func testReconcileKeepsMatchingChunksAndReplacesTheRest() {
        let result = VoiceInkLiveTyping.reconcile(
            typedChunks: [["Hello", "there."], ["My", "sister", "plan"]],
            finalWords: VoiceInkLiveTyping.words("Hello there. My sister planted tomatoes.")
        )

        XCTAssertEqual(result.keptChunkCount, 1)
        XCTAssertEqual(result.remainingWords, ["My", "sister", "planted", "tomatoes."])
    }

    func testReconcileKeepsEveryChunkWhenTheFinalTranscriptContinuesThem() {
        let result = VoiceInkLiveTyping.reconcile(
            typedChunks: [["Hello", "there."]],
            finalWords: VoiceInkLiveTyping.words("Hello there. How are you?")
        )

        XCTAssertEqual(result.keptChunkCount, 1)
        XCTAssertEqual(result.remainingWords, ["How", "are", "you?"])
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
