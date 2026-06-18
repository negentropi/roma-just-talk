import Foundation
@testable import VoiceInkCore

final class FillerWordsTests: XCTestCase {
    func testDefaultWordsMatchMacOSCleanupDefaults() {
        XCTAssertEqual(
            VoiceInkFillerWords.defaultWords,
            ["uh", "um", "uhm", "umm", "uhh", "uhhh", "hmm", "hm", "mmm", "mm", "mh", "ehh"]
        )
    }

    func testAddingNormalizesAndAppendsNewWord() {
        XCTAssertEqual(
            VoiceInkFillerWords.adding("  LIKE  ", to: ["um"]),
            ["um", "like"]
        )
    }

    func testAddingRejectsBlankAndCaseInsensitiveDuplicateWords() {
        XCTAssertNil(VoiceInkFillerWords.adding("   ", to: ["um"]))
        XCTAssertNil(VoiceInkFillerWords.adding("UM", to: ["um"]))
    }

    func testRemovingDropsWordsCaseInsensitively() {
        XCTAssertEqual(
            VoiceInkFillerWords.removing("UM", from: ["uh", "um", "like"]),
            ["uh", "like"]
        )
    }

    func testRemovingAtOffsetsMatchesIOSListDeletion() {
        XCTAssertEqual(
            VoiceInkFillerWords.removing(at: IndexSet([1, 3]), from: ["uh", "um", "like", "hmm"]),
            ["uh", "like"]
        )
    }
}
