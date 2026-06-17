import Foundation
@testable import VoiceInkCore

final class DictionaryPolicyTests: XCTestCase {
    func testVocabularyPlanReturnsNoOpForBlankInput() {
        let plan = VoiceInkDictionaryPolicy.vocabularyInsertPlan(
            input: " , \n ",
            existingWords: []
        )

        XCTAssertFalse(plan.shouldInsert)
        XCTAssertNil(plan.errorMessage)
    }

    func testVocabularyPlanRejectsSingleDuplicateWithExistingMessage() {
        let plan = VoiceInkDictionaryPolicy.vocabularyInsertPlan(
            input: "Voice Ink",
            existingWords: ["voice ink"]
        )

        XCTAssertEqual(plan.wordsToInsert, [])
        XCTAssertEqual(plan.errorMessage, "'Voice Ink' is already in the vocabulary")
    }

    func testVocabularyPlanSkipsDuplicatesForMultiAdd() {
        let plan = VoiceInkDictionaryPolicy.vocabularyInsertPlan(
            input: "Voice Ink, Roma, roma, Cursor",
            existingWords: ["voice ink"]
        )

        XCTAssertEqual(plan.wordsToInsert, ["Roma", "Cursor"])
        XCTAssertNil(plan.errorMessage)
    }

    func testVocabularyWordsToInsertTrimsAndSkipsExistingAndBatchDuplicates() {
        XCTAssertEqual(
            VoiceInkDictionaryPolicy.vocabularyWordsToInsert(
                [" Voice Ink ", "Roma", "roma", " ", "Cursor"],
                existingWords: ["voice ink"]
            ),
            ["Roma", "Cursor"]
        )
    }

    func testWordReplacementPlanReturnsNoOpForBlankOriginalOrReplacement() {
        XCTAssertFalse(
            VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
                original: " , ",
                replacement: "roma",
                existingOriginalTexts: []
            ).shouldInsert
        )

        XCTAssertFalse(
            VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
                original: "voice ink",
                replacement: "",
                existingOriginalTexts: []
            ).shouldInsert
        )
    }

    func testWordReplacementPlanRejectsDuplicateTokenAcrossCommaGroups() {
        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: "Flow, Voice Ink",
            replacement: "roma",
            existingOriginalTexts: ["quick release, voice ink"]
        )

        XCTAssertFalse(plan.shouldInsert)
        XCTAssertEqual(plan.errorMessage, "'Voice Ink' already exists in word replacements")
    }

    func testWordReplacementPlanAllowsNewTokensAndPreservesOriginalInput() {
        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: " Flow, Voice Ink ",
            replacement: "roma",
            existingOriginalTexts: ["quick release"]
        )

        XCTAssertTrue(plan.shouldInsert)
        XCTAssertEqual(plan.originalText, " Flow, Voice Ink ")
        XCTAssertEqual(plan.replacementText, "roma")
        XCTAssertNil(plan.errorMessage)
    }
}
