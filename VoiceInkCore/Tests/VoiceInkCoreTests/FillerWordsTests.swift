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

    func testInsertPlanNormalizesNewWords() {
        XCTAssertEqual(
            VoiceInkFillerWords.insertPlan("  LIKE  ", existingWords: ["um"]),
            VoiceInkFillerWordInsertPlan(wordToInsert: "like", errorMessage: nil)
        )
    }

    func testInsertPlanRejectsBlankDraftsWithoutAlert() {
        XCTAssertEqual(
            VoiceInkFillerWords.insertPlan("   ", existingWords: ["um"]),
            VoiceInkFillerWordInsertPlan(wordToInsert: nil, errorMessage: nil)
        )
    }

    func testInsertPlanRejectsCaseInsensitiveDuplicatesWithSharedMessage() {
        XCTAssertEqual(
            VoiceInkFillerWords.insertPlan("UM", existingWords: ["um"]),
            VoiceInkFillerWordInsertPlan(
                wordToInsert: nil,
                errorMessage: "This filler word is already in the list."
            )
        )
    }

    func testAddingRejectsBlankAndCaseInsensitiveDuplicateWords() {
        XCTAssertNil(VoiceInkFillerWords.adding("   ", to: ["um"]))
        XCTAssertNil(VoiceInkFillerWords.adding("UM", to: ["um"]))
    }

    func testAddMutatesWordsAndReturnsDuplicateMessage() {
        var words = ["um"]

        XCTAssertNil(VoiceInkFillerWords.add("  LIKE  ", to: &words))
        XCTAssertEqual(words, ["um", "like"])

        XCTAssertEqual(
            VoiceInkFillerWords.add("LIKE", to: &words),
            "This filler word is already in the list."
        )
        XCTAssertEqual(words, ["um", "like"])
    }

    func testDraftAvailabilityUsesSharedNormalization() {
        XCTAssertFalse(VoiceInkFillerWords.hasDraft(" \n\t "))
        XCTAssertTrue(VoiceInkFillerWords.hasDraft(" LIKE "))
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
