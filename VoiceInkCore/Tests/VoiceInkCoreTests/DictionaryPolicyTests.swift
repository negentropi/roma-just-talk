import Foundation
@testable import VoiceInkCore

final class DictionaryPolicyTests: XCTestCase {
    func testDictionaryAlertPresentationPreservesPlatformTitles() {
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.duplicateFillerWord(message: "This filler word is already in the list.").title,
            "Duplicate Word"
        )
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.vocabulary(message: "'Roma' is already in the vocabulary").title,
            "Vocabulary"
        )
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.wordReplacement(message: "'roma' already exists in word replacements").title,
            "Word Replacement"
        )
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.wordReplacement(message: "Nope").primaryButtonTitle,
            "OK"
        )
    }

    func testDictionaryPersistenceFailureMessagesPreservePlatformCopy() {
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.failedToAddVocabularyWord(
                "Roma",
                localizedDescription: "Disk full"
            ),
            "Failed to add 'Roma': Disk full"
        )
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.failedToAddWordReplacement(localizedDescription: "Disk full"),
            "Failed to add replacement: Disk full"
        )
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.failedToSaveWordReplacementChanges(localizedDescription: "Denied"),
            "Failed to save changes: Denied"
        )
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.failedToRemoveVocabularyWord(localizedDescription: "Missing"),
            "Failed to remove word: Missing"
        )
        XCTAssertEqual(
            VoiceInkDictionaryAlertPresentation.failedToRemoveWordReplacement(localizedDescription: "Missing"),
            "Failed to remove replacement: Missing"
        )
    }

    func testDictionarySettingsPresentationPreservesIOSCopy() {
        let presentation = VoiceInkDictionarySettingsPresentation.iOS

        XCTAssertEqual(presentation.sectionTitle, "Dictionary")
        XCTAssertNil(presentation.vocabularyHelpText)
        XCTAssertEqual(presentation.vocabularyPlaceholder, "Vocabulary term")
        XCTAssertNil(presentation.addVocabularyButtonHelp)
        XCTAssertNil(presentation.wordReplacementHelpText)
        XCTAssertEqual(presentation.wordReplacementsSection.title, "Word Replacements")
        XCTAssertEqual(presentation.wordReplacementsSection.description, "")
        XCTAssertEqual(presentation.wordReplacementsSection.systemImageName, "arrow.2.squarepath")
        XCTAssertEqual(presentation.vocabularySection.title, "Vocabulary")
        XCTAssertEqual(presentation.vocabularySection.description, "")
        XCTAssertEqual(presentation.vocabularySection.systemImageName, "character.book.closed.fill")
        XCTAssertEqual(presentation.originalTextPlaceholder, "Original text")
        XCTAssertEqual(presentation.replacementTextPlaceholder, "Replacement text")
        XCTAssertEqual(presentation.addReplacementButtonTitle, "Add Replacement")
        XCTAssertNil(presentation.addReplacementButtonHelp)
        XCTAssertNil(presentation.heroDescription)
        XCTAssertNil(presentation.sectionSelectorTitle)
        XCTAssertNil(presentation.settingsButtonHelp)
        XCTAssertNil(presentation.shortcutsSectionTitle)
        XCTAssertNil(presentation.quickAddShortcutTitle)
        XCTAssertNil(presentation.closeButtonHelp)
    }

    func testDictionarySettingsPresentationPreservesMacOSCopy() {
        let presentation = VoiceInkDictionarySettingsPresentation.macOS

        XCTAssertEqual(presentation.sectionTitle, "Dictionary Settings")
        XCTAssertEqual(
            presentation.heroDescription,
            "Enhance VoiceInk's transcription accuracy by teaching it your vocabulary"
        )
        XCTAssertEqual(presentation.sectionSelectorTitle, "Select Section")
        XCTAssertEqual(presentation.settingsButtonHelp, "Dictionary settings")
        XCTAssertEqual(presentation.wordReplacementsSection.title, "Word Replacements")
        XCTAssertEqual(
            presentation.wordReplacementsSection.description,
            "Automatically replace specific words/phrases with custom formatted text "
        )
        XCTAssertEqual(presentation.wordReplacementsSection.systemImageName, "arrow.2.squarepath")
        XCTAssertEqual(presentation.vocabularySection.title, "Vocabulary")
        XCTAssertEqual(
            presentation.vocabularySection.description,
            "Add words to help VoiceInk recognize them properly"
        )
        XCTAssertEqual(presentation.vocabularySection.systemImageName, "character.book.closed.fill")
        XCTAssertEqual(
            presentation.vocabularyHelpText,
            "Add words to help VoiceInk recognize them properly. (Requires AI enhancement)"
        )
        XCTAssertEqual(presentation.vocabularyPlaceholder, "Add word to vocabulary")
        XCTAssertEqual(presentation.addVocabularyButtonHelp, "Add word")
        XCTAssertEqual(
            presentation.wordReplacementHelpText,
            "Define word replacements to automatically replace specific words or phrases"
        )
        XCTAssertEqual(presentation.originalTextPlaceholder, "Original text (use commas for multiple)")
        XCTAssertEqual(presentation.replacementTextPlaceholder, "Replacement text")
        XCTAssertEqual(presentation.addReplacementButtonTitle, "Add Replacement")
        XCTAssertEqual(presentation.addReplacementButtonHelp, "Add word replacement")
        XCTAssertEqual(presentation.shortcutsSectionTitle, "Shortcuts")
        XCTAssertEqual(presentation.quickAddShortcutTitle, "Quick Add to Dictionary")
        XCTAssertEqual(presentation.closeButtonHelp, "Close")
    }

    func testDictionaryQuickAddPresentationPreservesMacOSCopy() {
        let presentation = VoiceInkDictionaryQuickAddPresentation.macOS

        XCTAssertEqual(presentation.vocabularyMode.title, "Vocabulary")
        XCTAssertEqual(presentation.vocabularyMode.systemImageName, "character.book.closed.fill")
        XCTAssertEqual(presentation.replacementMode.title, "Word Replacement")
        XCTAssertEqual(presentation.replacementMode.systemImageName, "arrow.2.squarepath")
        XCTAssertEqual(presentation.vocabularyPlaceholder, "e.g. Prakash, VoiceInk")
        XCTAssertEqual(presentation.originalLabel, "Replace")
        XCTAssertEqual(presentation.originalPlaceholder, "e.g. my email, my mail")
        XCTAssertEqual(presentation.replacementLabel, "With")
        XCTAssertEqual(presentation.replacementPlaceholder, "e.g. support@tryvoiceink.com")
        XCTAssertEqual(presentation.submitHintTitle, "Add")
        XCTAssertEqual(presentation.dismissHintTitle, "Dismiss")
    }

    func testWordReplacementInfoPresentationPreservesMacOSCopy() {
        let presentation = VoiceInkWordReplacementInfoPresentation.macOS

        XCTAssertEqual(presentation.title, "How to use Word Replacements")
        XCTAssertEqual(presentation.multipleOriginalsHelpText, "Separate multiple originals with commas:")
        XCTAssertEqual(presentation.multipleOriginalsExampleText, "Voicing, Voice ink, Voiceing")
        XCTAssertEqual(presentation.examplesTitle, "Examples")
        XCTAssertEqual(presentation.originalLabel, "Original:")
        XCTAssertEqual(presentation.replacementLabel, "Replacement:")
        XCTAssertEqual(
            presentation.examples,
            [
                VoiceInkWordReplacementExamplePresentation(
                    originalText: "my website link",
                    replacementText: "https://tryvoiceink.com"
                ),
                VoiceInkWordReplacementExamplePresentation(
                    originalText: "Voicing, Voice ink",
                    replacementText: "VoiceInk"
                )
            ]
        )
    }

    func testWordReplacementEditPresentationPreservesMacOSCopy() {
        let presentation = VoiceInkWordReplacementEditPresentation.macOS

        XCTAssertEqual(presentation.cancelButtonTitle, "Cancel")
        XCTAssertEqual(presentation.title, "Edit Word Replacement")
        XCTAssertEqual(presentation.saveButtonTitle, "Save")
        XCTAssertEqual(
            presentation.descriptionText,
            "Update the word or phrase that should be automatically replaced."
        )
        XCTAssertEqual(presentation.originalFieldTitle, "Original Text")
        XCTAssertEqual(presentation.requiredText, "Required")
        XCTAssertEqual(
            presentation.originalPlaceholder,
            "Enter word or phrase to replace (use commas for multiple)"
        )
        XCTAssertEqual(presentation.replacementFieldTitle, "Replacement Text")
    }

    func testVocabularyListPresentationPreservesMacOSCopy() {
        let presentation = VoiceInkVocabularyListPresentation.macOS

        XCTAssertEqual(presentation.wordsTitlePrefix, "Vocabulary Words")
        XCTAssertEqual(presentation.wordsTitle(count: 3), "Vocabulary Words (3)")
        XCTAssertEqual(presentation.sortHelpText, "Sort alphabetically")
        XCTAssertEqual(presentation.removeButtonHelp, "Remove word")
    }

    func testWordReplacementListPresentationPreservesMacOSCopy() {
        let presentation = VoiceInkWordReplacementListPresentation.macOS

        XCTAssertEqual(presentation.originalColumnTitle, "Original")
        XCTAssertEqual(presentation.replacementColumnTitle, "Replacement")
        XCTAssertEqual(presentation.sortOriginalHelpText, "Sort by original")
        XCTAssertEqual(presentation.sortReplacementHelpText, "Sort by replacement")
        XCTAssertEqual(presentation.editButtonHelp, "Edit replacement")
        XCTAssertEqual(presentation.removeButtonHelp, "Remove replacement")
    }

    func testVocabularyDraftUsesSharedTokenPolicy() {
        XCTAssertFalse(VoiceInkDictionaryPolicy.hasVocabularyDraft(" , \n "))
        XCTAssertTrue(VoiceInkDictionaryPolicy.hasVocabularyDraft("Voice Ink, "))
    }

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

    func testVocabularyBackupRecordsPreserveExistingJSONShape() throws {
        let records = VoiceInkDictionaryPolicy.vocabularyBackupRecords(from: ["Roma", "VoiceInk"])
        let data = try JSONEncoder().encode(records)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"word\":\"Roma\""))
        XCTAssertTrue(json.contains("\"word\":\"VoiceInk\""))
        XCTAssertEqual(
            try JSONDecoder().decode([VoiceInkVocabularyWordBackup].self, from: data),
            [
                VoiceInkVocabularyWordBackup(word: "Roma"),
                VoiceInkVocabularyWordBackup(word: "VoiceInk")
            ]
        )
    }

    func testVocabularyBackupImportUsesSharedTrimAndDuplicatePolicy() {
        let records = [
            VoiceInkVocabularyWordBackup(word: " Roma "),
            VoiceInkVocabularyWordBackup(word: "roma"),
            VoiceInkVocabularyWordBackup(word: " "),
            VoiceInkVocabularyWordBackup(word: "Cursor")
        ]

        XCTAssertEqual(
            VoiceInkDictionaryPolicy.vocabularyWordsToInsert(
                from: records,
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
                replacement: " \n ",
                existingOriginalTexts: []
            ).shouldInsert
        )
    }

    func testWordReplacementDraftSaveabilityUsesInsertPlan() {
        XCTAssertFalse(
            VoiceInkDictionaryPolicy.canSaveWordReplacementDraft(
                original: " , ",
                replacement: "roma"
            )
        )
        XCTAssertFalse(
            VoiceInkDictionaryPolicy.canSaveWordReplacementDraft(
                original: "voice ink",
                replacement: ""
            )
        )
        XCTAssertTrue(
            VoiceInkDictionaryPolicy.canSaveWordReplacementDraft(
                original: "voice ink",
                replacement: "roma"
            )
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

    func testWordReplacementPlanTrimsStoredOriginalAndReplacement() {
        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: " Flow, Voice Ink ",
            replacement: " roma ",
            existingOriginalTexts: ["quick release"]
        )

        XCTAssertTrue(plan.shouldInsert)
        XCTAssertEqual(plan.originalText, "Flow, Voice Ink")
        XCTAssertEqual(plan.replacementText, "roma")
        XCTAssertNil(plan.errorMessage)
    }

    func testWordReplacementBackupImportPlanPreservesMacOSImportSemantics() {
        let plan = VoiceInkDictionaryPolicy.wordReplacementBackupImportPlan(
            from: [
                " Flow, Voice Ink ": " roma ",
                "quick release": "duplicate",
                "blank replacement": " \n ",
                " , ": "ignored"
            ],
            existingOriginalTexts: ["quick release"]
        )

        XCTAssertEqual(
            plan.rulesToInsert,
            [VoiceInkWordReplacementRule(originalText: "Flow, Voice Ink", replacementText: "roma")]
        )
        XCTAssertEqual(plan.skippedInvalidReplacementCount, 2)
    }
}
