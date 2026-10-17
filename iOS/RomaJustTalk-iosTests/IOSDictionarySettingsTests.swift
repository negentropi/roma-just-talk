import XCTest
import RomaCore

final class IOSDictionarySettingsTests: XCTestCase {
    func testReplacementEditPreservesStorageOrderAndUsesNormalizedRule() {
        let original = RomaWordReplacementRule(
            originalText: "voice ink",
            replacementText: "RomaJustTalk"
        )
        let snapshot = makeSnapshot(replacements: [
            original,
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ])
        let submission = snapshot.wordReplacementEditSubmission(
            RomaWordReplacementEditState(
                original: "  voice ink app  ",
                replacement: "  RomaJustTalk App  "
            ),
            replacing: original
        )
        var updatedRules = snapshot.wordReplacements

        snapshot.applyWordReplacementEditSubmission(
            submission,
            replacing: original
        ) { updatedRules = $0 }

        XCTAssertTrue(submission.shouldComplete)
        XCTAssertEqual(updatedRules, [
            RomaWordReplacementRule(
                originalText: "voice ink app",
                replacementText: "RomaJustTalk App"
            ),
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ])
    }

    func testReplacementEditRejectsAnotherStoredOriginalWithoutPersisting() {
        let original = RomaWordReplacementRule(
            originalText: "voice ink",
            replacementText: "RomaJustTalk"
        )
        let snapshot = makeSnapshot(replacements: [
            original,
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ])
        let submission = snapshot.wordReplacementEditSubmission(
            RomaWordReplacementEditState(original: "ROMA", replacement: "RJT"),
            replacing: original
        )
        var didPersist = false

        snapshot.applyWordReplacementEditSubmission(
            submission,
            replacing: original
        ) { _ in didPersist = true }

        XCTAssertFalse(submission.shouldUpdate)
        XCTAssertNotNil(submission.alertPresentation)
        XCTAssertFalse(didPersist)
    }

    private func makeSnapshot(
        replacements: [RomaWordReplacementRule]
    ) -> RomaDictionarySettingsSnapshot {
        RomaDictionarySettingsSnapshot(
            fillerWords: [],
            customVocabularyTerms: [],
            wordReplacements: replacements,
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .originalAscending
        )
    }
}
