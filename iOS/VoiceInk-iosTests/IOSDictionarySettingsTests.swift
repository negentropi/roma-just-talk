import XCTest
import VoiceInkCore

final class IOSDictionarySettingsTests: XCTestCase {
    func testReplacementEditPreservesStorageOrderAndUsesNormalizedRule() {
        let original = VoiceInkWordReplacementRule(
            originalText: "voice ink",
            replacementText: "VoiceInk"
        )
        let snapshot = makeSnapshot(replacements: [
            original,
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ])
        let submission = snapshot.wordReplacementEditSubmission(
            VoiceInkWordReplacementEditState(
                original: "  voice ink app  ",
                replacement: "  VoiceInk App  "
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
            VoiceInkWordReplacementRule(
                originalText: "voice ink app",
                replacementText: "VoiceInk App"
            ),
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ])
    }

    func testReplacementEditRejectsAnotherStoredOriginalWithoutPersisting() {
        let original = VoiceInkWordReplacementRule(
            originalText: "voice ink",
            replacementText: "VoiceInk"
        )
        let snapshot = makeSnapshot(replacements: [
            original,
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ])
        let submission = snapshot.wordReplacementEditSubmission(
            VoiceInkWordReplacementEditState(original: "ROMA", replacement: "RJT"),
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
        replacements: [VoiceInkWordReplacementRule]
    ) -> VoiceInkDictionarySettingsSnapshot {
        VoiceInkDictionarySettingsSnapshot(
            fillerWords: [],
            customVocabularyTerms: [],
            wordReplacements: replacements,
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .originalAscending
        )
    }
}
