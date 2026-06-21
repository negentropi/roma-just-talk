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
        XCTAssertEqual(presentation.wordReplacementArrowSystemImageName, "arrow.right")
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
        XCTAssertEqual(presentation.wordReplacementArrowSystemImageName, "arrow.right")
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

    func testDictionaryListSortModesPreserveStorageAndIndicatorValues() {
        XCTAssertEqual(VoiceInkVocabularySortMode.wordAscending.rawValue, "wordAsc")
        XCTAssertEqual(VoiceInkVocabularySortMode.wordDescending.rawValue, "wordDesc")
        XCTAssertEqual(VoiceInkVocabularySortMode.defaultMode, .wordAscending)
        XCTAssertEqual(VoiceInkVocabularySortMode.wordAscending.indicatorSystemImageName, "chevron.up")
        XCTAssertEqual(VoiceInkVocabularySortMode.wordDescending.indicatorSystemImageName, "chevron.down")
        XCTAssertEqual(VoiceInkVocabularySortMode.wordAscending.toggled(), .wordDescending)
        XCTAssertEqual(VoiceInkVocabularySortMode.wordDescending.toggled(), .wordAscending)

        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalAscending.rawValue, "originalAsc")
        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalDescending.rawValue, "originalDesc")
        XCTAssertEqual(VoiceInkWordReplacementSortMode.replacementAscending.rawValue, "replacementAsc")
        XCTAssertEqual(VoiceInkWordReplacementSortMode.replacementDescending.rawValue, "replacementDesc")
        XCTAssertEqual(VoiceInkWordReplacementSortMode.defaultMode, .originalAscending)
        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalAscending.activeColumn, .original)
        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalDescending.activeColumn, .original)
        XCTAssertEqual(VoiceInkWordReplacementSortMode.replacementAscending.activeColumn, .replacement)
        XCTAssertEqual(VoiceInkWordReplacementSortMode.replacementDescending.activeColumn, .replacement)
        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalAscending.indicatorSystemImageName, "chevron.up")
        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalDescending.indicatorSystemImageName, "chevron.down")
        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalAscending.toggled(for: .original), .originalDescending)
        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalDescending.toggled(for: .original), .originalAscending)
        XCTAssertEqual(VoiceInkWordReplacementSortMode.originalDescending.toggled(for: .replacement), .replacementAscending)
        XCTAssertEqual(VoiceInkWordReplacementSortMode.replacementAscending.toggled(for: .replacement), .replacementDescending)
    }

    func testDictionaryListSortPreferencesReadDefaultsAndSaveModes() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(VoiceInkDictionaryListSortPreference.wordReplacementSortMode(from: defaults), .originalAscending)

            defaults.set("invalid", forKey: VoiceInkDictionaryListSortPreference.vocabularySortModeKey)
            defaults.set("invalid", forKey: VoiceInkDictionaryListSortPreference.wordReplacementSortModeKey)

            XCTAssertEqual(VoiceInkDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(VoiceInkDictionaryListSortPreference.wordReplacementSortMode(from: defaults), .originalAscending)

            VoiceInkDictionaryListSortPreference.saveVocabularySortMode(.wordDescending, to: defaults)
            VoiceInkDictionaryListSortPreference.saveWordReplacementSortMode(.replacementDescending, to: defaults)

            XCTAssertEqual(VoiceInkDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordDescending)
            XCTAssertEqual(VoiceInkDictionaryListSortPreference.wordReplacementSortMode(from: defaults), .replacementDescending)

            VoiceInkDictionaryListSortPreference.clear(from: defaults)

            XCTAssertEqual(VoiceInkDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(VoiceInkDictionaryListSortPreference.wordReplacementSortMode(from: defaults), .originalAscending)
        }
    }

    func testDictionaryListSortPolicySortsVocabularyAndWordReplacements() {
        let vocabulary = ["zeta", "Alpha", "beta"]

        XCTAssertEqual(
            VoiceInkDictionaryListSortPolicy.sortedVocabulary(vocabulary, mode: .wordAscending) { $0 },
            ["Alpha", "beta", "zeta"]
        )
        XCTAssertEqual(
            VoiceInkDictionaryListSortPolicy.sortedVocabulary(vocabulary, mode: .wordDescending) { $0 },
            ["zeta", "beta", "Alpha"]
        )

        let replacements = [
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk"),
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
            VoiceInkWordReplacementRule(originalText: "alpha", replacementText: "Zed")
        ]

        XCTAssertEqual(
            VoiceInkDictionaryListSortPolicy.sortedWordReplacements(
                replacements,
                mode: .originalAscending,
                originalText: { $0.originalText },
                replacementText: { $0.replacementText }
            ).map(\.originalText),
            ["alpha", "roma", "voice ink"]
        )
        XCTAssertEqual(
            VoiceInkDictionaryListSortPolicy.sortedWordReplacements(
                replacements,
                mode: .replacementDescending,
                originalText: { $0.originalText },
                replacementText: { $0.replacementText }
            ).map(\.replacementText),
            ["Zed", "VoiceInk", "Roma Just Talk"]
        )
    }

    func testDictionaryListSortPolicyRemovesDisplayedSortedVocabularyRows() {
        let vocabulary = ["zeta", "Alpha", "beta", "delta"]

        XCTAssertEqual(
            VoiceInkDictionaryListSortPolicy.removingVocabulary(
                atSortedOffsets: IndexSet([0, 2]),
                from: vocabulary,
                mode: .wordAscending,
                word: { $0 }
            ),
            ["zeta", "beta"]
        )
        XCTAssertEqual(
            VoiceInkDictionaryListSortPolicy.removingVocabulary(
                atSortedOffsets: IndexSet([10]),
                from: vocabulary,
                mode: .wordAscending,
                word: { $0 }
            ),
            vocabulary
        )
    }

    func testDictionaryListSortPolicyRemovesDisplayedSortedWordReplacementRows() {
        let replacements = [
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk"),
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
            VoiceInkWordReplacementRule(originalText: "alpha", replacementText: "Zed")
        ]

        XCTAssertEqual(
            VoiceInkDictionaryListSortPolicy.removingWordReplacements(
                atSortedOffsets: IndexSet([0]),
                from: replacements,
                mode: .replacementDescending,
                originalText: { $0.originalText },
                replacementText: { $0.replacementText }
            ),
            [
                VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk"),
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ]
        )
        XCTAssertEqual(
            VoiceInkDictionaryListSortPolicy.removingWordReplacements(
                atSortedOffsets: IndexSet([8]),
                from: replacements,
                mode: .replacementDescending,
                originalText: { $0.originalText },
                replacementText: { $0.replacementText }
            ),
            replacements
        )
    }

    func testVocabularyDraftUsesSharedTokenPolicy() {
        XCTAssertFalse(VoiceInkDictionaryPolicy.hasVocabularyDraft(" , \n "))
        XCTAssertTrue(VoiceInkDictionaryPolicy.hasVocabularyDraft("Voice Ink, "))
    }

    func testVocabularyDraftStateUsesSharedTokenPolicy() {
        XCTAssertFalse(VoiceInkVocabularyDraftState(draft: " , \n ").canSubmit)
        XCTAssertTrue(VoiceInkVocabularyDraftState(draft: "Voice Ink, ").canSubmit)
    }

    func testVocabularyDraftStateSubmitsAndClearsAcceptedWords() {
        let submission = VoiceInkVocabularyDraftState(draft: "Voice Ink, Roma, roma, Cursor")
            .submitting(existingWords: ["voice ink"])

        XCTAssertEqual(submission.submittedDraft, "Voice Ink, Roma, roma, Cursor")
        XCTAssertEqual(submission.plan.wordsToInsert, ["Roma", "Cursor"])
        XCTAssertEqual(submission.draftStateAfterSubmit, VoiceInkVocabularyDraftState())
        XCTAssertNil(submission.alertPresentation)
    }

    func testVocabularyDraftStateKeepsDuplicateDraftAndBuildsSharedAlert() {
        let submission = VoiceInkVocabularyDraftState(draft: "Voice Ink")
            .submitting(existingWords: ["voice ink"])

        XCTAssertEqual(submission.submittedDraft, "Voice Ink")
        XCTAssertEqual(submission.plan.wordsToInsert, [])
        XCTAssertEqual(submission.draftStateAfterSubmit, VoiceInkVocabularyDraftState(draft: "Voice Ink"))
        XCTAssertEqual(
            submission.alertPresentation,
            .vocabulary(message: "'Voice Ink' is already in the vocabulary")
        )
    }

    func testVocabularySubmissionPlanKeepsBlankDraftWithoutAlert() {
        let plan = VoiceInkDictionaryPolicy.vocabularySubmissionPlan(
            input: " , \n ",
            existingWords: []
        )

        XCTAssertFalse(plan.shouldInsert)
        XCTAssertFalse(plan.shouldComplete)
        XCTAssertEqual(plan.draftAfterSubmit, " , \n ")
        XCTAssertNil(plan.alertPresentation)
    }

    func testVocabularySubmissionPlanRejectsSingleDuplicateWithSharedAlert() {
        let plan = VoiceInkDictionaryPolicy.vocabularySubmissionPlan(
            input: "Voice Ink",
            existingWords: ["voice ink"]
        )

        XCTAssertEqual(plan.wordsToInsert, [])
        XCTAssertFalse(plan.shouldComplete)
        XCTAssertEqual(plan.draftAfterSubmit, "Voice Ink")
        XCTAssertEqual(
            plan.alertPresentation,
            .vocabulary(message: "'Voice Ink' is already in the vocabulary")
        )
    }

    func testVocabularySubmissionPlanSkipsDuplicatesAndClearsSubmittedDraft() {
        let plan = VoiceInkDictionaryPolicy.vocabularySubmissionPlan(
            input: "Voice Ink, Roma, roma, Cursor",
            existingWords: ["voice ink"]
        )

        XCTAssertEqual(plan.wordsToInsert, ["Roma", "Cursor"])
        XCTAssertTrue(plan.shouldInsert)
        XCTAssertTrue(plan.shouldComplete)
        XCTAssertEqual(plan.draftAfterSubmit, "")
        XCTAssertNil(plan.alertPresentation)
    }

    func testVocabularySubmissionPlanClearsAllDuplicateMultiAddAsCompletedNoOp() {
        let plan = VoiceInkDictionaryPolicy.vocabularySubmissionPlan(
            input: "Voice Ink, voice ink",
            existingWords: ["voice ink"]
        )

        XCTAssertEqual(plan.wordsToInsert, [])
        XCTAssertFalse(plan.shouldInsert)
        XCTAssertTrue(plan.shouldComplete)
        XCTAssertEqual(plan.draftAfterSubmit, "")
        XCTAssertNil(plan.alertPresentation)
    }

    func testVocabularySubmissionPlanAppliesInsertedWordsToStoredList() {
        let existingWords = ["Voice Ink"]
        let plan = VoiceInkDictionaryPolicy.vocabularySubmissionPlan(
            input: "Roma, voice ink, Cursor",
            existingWords: existingWords
        )

        XCTAssertEqual(plan.applying(to: existingWords), ["Voice Ink", "Roma", "Cursor"])
        XCTAssertEqual(plan.updatedWordsIfChanged(from: existingWords), ["Voice Ink", "Roma", "Cursor"])
    }

    func testVocabularySubmissionPlanLeavesStoredListUnchangedWhenNothingIsInserted() {
        let existingWords = ["Voice Ink"]
        let plan = VoiceInkDictionaryPolicy.vocabularySubmissionPlan(
            input: "voice ink",
            existingWords: existingWords
        )

        XCTAssertEqual(plan.applying(to: existingWords), existingWords)
        XCTAssertNil(plan.updatedWordsIfChanged(from: existingWords))
    }

    func testVocabularySubmissionPlanLeavesStoredListUnchangedWhenAlertIsPresent() {
        let existingWords = ["Voice Ink"]
        let plan = VoiceInkVocabularySubmissionPlan(
            wordsToInsert: ["Roma"],
            draftAfterSubmit: "Roma",
            alertPresentation: .vocabulary(message: "Failed to add 'Roma': Disk full")
        )

        XCTAssertEqual(plan.applying(to: existingWords), existingWords)
        XCTAssertNil(plan.updatedWordsIfChanged(from: existingWords))
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

    func testDictionaryBackupExportPlanPreservesMacOSNilAndRecordShape() {
        XCTAssertEqual(
            VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(
                vocabularyWords: [],
                wordReplacementRules: []
            ),
            VoiceInkDictionaryBackupExportPlan(
                vocabularyBackupRecords: nil,
                wordReplacementBackupRecords: nil
            )
        )

        XCTAssertEqual(
            VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(
                vocabularyWords: ["Roma", "VoiceInk"],
                wordReplacementRules: [
                    VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk")
                ]
            ),
            VoiceInkDictionaryBackupExportPlan(
                vocabularyBackupRecords: [
                    VoiceInkVocabularyWordBackup(word: "Roma"),
                    VoiceInkVocabularyWordBackup(word: "VoiceInk")
                ],
                wordReplacementBackupRecords: ["voice ink": "VoiceInk"]
            )
        )
    }

    func testDictionaryBackupExportPlanKeepsLastDuplicateReplacement() {
        let plan = VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(
            vocabularyWords: [],
            wordReplacementRules: [
                VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk"),
                VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "roma just talk")
            ]
        )

        XCTAssertEqual(plan.vocabularyBackupRecords, nil)
        XCTAssertEqual(plan.wordReplacementBackupRecords, ["voice ink": "roma just talk"])
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

    func testWordReplacementDraftStateUsesSharedVisibilityAndSaveability() {
        XCTAssertFalse(VoiceInkWordReplacementDraftState().hasDraft)
        XCTAssertTrue(VoiceInkWordReplacementDraftState(original: "voice ink").hasDraft)
        XCTAssertTrue(VoiceInkWordReplacementDraftState(replacement: "Roma").hasDraft)
        XCTAssertFalse(VoiceInkWordReplacementDraftState(original: " , ", replacement: "roma").canSubmit)
        XCTAssertTrue(VoiceInkWordReplacementDraftState(original: "voice ink", replacement: "roma").canSubmit)
    }

    func testWordReplacementDraftStateSubmitsAndClearsAcceptedRule() {
        let submission = VoiceInkWordReplacementDraftState(
            original: " Roma ",
            replacement: " Roma Just Talk "
        )
        .submitting(existingOriginalTexts: [])

        XCTAssertEqual(submission.submittedOriginal, " Roma ")
        XCTAssertEqual(submission.submittedReplacement, " Roma Just Talk ")
        XCTAssertEqual(
            submission.plan.ruleToInsert,
            VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
        )
        XCTAssertEqual(submission.draftStateAfterSubmit, VoiceInkWordReplacementDraftState())
        XCTAssertNil(submission.alertPresentation)
    }

    func testWordReplacementDraftStateKeepsDuplicateDraftAndBuildsSharedAlert() {
        let submission = VoiceInkWordReplacementDraftState(
            original: "Roma",
            replacement: "Roma Just Talk"
        )
        .submitting(existingOriginalTexts: ["roma"])

        XCTAssertNil(submission.plan.ruleToInsert)
        XCTAssertEqual(submission.draftStateAfterSubmit, VoiceInkWordReplacementDraftState(
            original: "Roma",
            replacement: "Roma Just Talk"
        ))
        XCTAssertEqual(
            submission.alertPresentation,
            .wordReplacement(message: "'Roma' already exists in word replacements")
        )
    }

    func testWordReplacementEditStateUsesSharedSaveability() {
        XCTAssertFalse(VoiceInkWordReplacementEditState(original: " , ", replacement: "Roma").canSave)
        XCTAssertFalse(VoiceInkWordReplacementEditState(original: "voice ink", replacement: "").canSave)
        XCTAssertTrue(VoiceInkWordReplacementEditState(original: "voice ink", replacement: "VoiceInk").canSave)
    }

    func testWordReplacementEditStateSubmitsTrimmedAcceptedRule() {
        let submission = VoiceInkWordReplacementEditState(
            original: " Voice Ink ",
            replacement: " VoiceInk "
        )
        .submitting(existingOriginalTexts: ["Roma"])

        XCTAssertEqual(submission.submittedOriginal, " Voice Ink ")
        XCTAssertEqual(submission.submittedReplacement, " VoiceInk ")
        XCTAssertTrue(submission.shouldUpdate)
        XCTAssertTrue(submission.shouldComplete)
        XCTAssertEqual(submission.plan.originalText, "Voice Ink")
        XCTAssertEqual(submission.plan.replacementText, "VoiceInk")
        XCTAssertNil(submission.alertPresentation)
    }

    func testWordReplacementEditStateRejectsDuplicateWithSharedAlert() {
        let submission = VoiceInkWordReplacementEditState(
            original: "Voice Ink",
            replacement: "VoiceInk"
        )
        .submitting(existingOriginalTexts: ["voice ink"])

        XCTAssertFalse(submission.shouldUpdate)
        XCTAssertFalse(submission.shouldComplete)
        XCTAssertEqual(
            submission.alertPresentation,
            .wordReplacement(message: "'Voice Ink' already exists in word replacements")
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

    func testWordReplacementSubmissionPlanKeepsInvalidDraftWithoutAlert() {
        let plan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: " , ",
            replacement: "roma",
            existingOriginalTexts: []
        )

        XCTAssertNil(plan.ruleToInsert)
        XCTAssertEqual(plan.originalDraftAfterSubmit, " , ")
        XCTAssertEqual(plan.replacementDraftAfterSubmit, "roma")
        XCTAssertNil(plan.alertPresentation)
        XCTAssertFalse(plan.shouldInsert)
        XCTAssertFalse(plan.shouldComplete)

        let emptyPlan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: "",
            replacement: "",
            existingOriginalTexts: []
        )

        XCTAssertNil(emptyPlan.ruleToInsert)
        XCTAssertEqual(emptyPlan.originalDraftAfterSubmit, "")
        XCTAssertEqual(emptyPlan.replacementDraftAfterSubmit, "")
        XCTAssertNil(emptyPlan.alertPresentation)
        XCTAssertFalse(emptyPlan.shouldInsert)
        XCTAssertFalse(emptyPlan.shouldComplete)
    }

    func testWordReplacementSubmissionPlanRejectsDuplicateWithSharedAlert() {
        let plan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: "Roma",
            replacement: "Roma Just Talk",
            existingOriginalTexts: ["roma"]
        )

        XCTAssertNil(plan.ruleToInsert)
        XCTAssertEqual(plan.originalDraftAfterSubmit, "Roma")
        XCTAssertEqual(plan.replacementDraftAfterSubmit, "Roma Just Talk")
        XCTAssertEqual(
            plan.alertPresentation,
            .wordReplacement(message: "'Roma' already exists in word replacements")
        )
        XCTAssertFalse(plan.shouldInsert)
        XCTAssertFalse(plan.shouldComplete)
    }

    func testWordReplacementSubmissionPlanBuildsRuleAndClearsDraft() {
        let plan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: " Roma ",
            replacement: " Roma Just Talk ",
            existingOriginalTexts: []
        )

        XCTAssertEqual(
            plan.ruleToInsert,
            VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
        )
        XCTAssertEqual(plan.originalDraftAfterSubmit, "")
        XCTAssertEqual(plan.replacementDraftAfterSubmit, "")
        XCTAssertNil(plan.alertPresentation)
        XCTAssertTrue(plan.shouldInsert)
        XCTAssertTrue(plan.shouldComplete)
    }

    func testWordReplacementSubmissionPlanAppliesInsertedRuleToStoredList() {
        let existingRules = [
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk")
        ]
        let plan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: " Roma ",
            replacement: " Roma Just Talk ",
            existingOriginalTexts: existingRules.map(\.originalText)
        )

        XCTAssertEqual(
            plan.applying(to: existingRules),
            existingRules + [
                VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
            ]
        )
        XCTAssertEqual(
            plan.updatedRulesIfChanged(from: existingRules),
            existingRules + [
                VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
            ]
        )
    }

    func testWordReplacementSubmissionPlanLeavesStoredListUnchangedWhenNothingIsInserted() {
        let existingRules = [
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ]
        let duplicatePlan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: "Roma",
            replacement: "RJT",
            existingOriginalTexts: existingRules.map(\.originalText)
        )
        let blankPlan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: "",
            replacement: "",
            existingOriginalTexts: existingRules.map(\.originalText)
        )

        XCTAssertEqual(duplicatePlan.applying(to: existingRules), existingRules)
        XCTAssertEqual(blankPlan.applying(to: existingRules), existingRules)
        XCTAssertNil(duplicatePlan.updatedRulesIfChanged(from: existingRules))
        XCTAssertNil(blankPlan.updatedRulesIfChanged(from: existingRules))
    }

    func testWordReplacementSubmissionPlanLeavesStoredListUnchangedWhenAlertIsPresent() {
        let existingRules = [
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk")
        ]
        let plan = VoiceInkWordReplacementSubmissionPlan(
            ruleToInsert: VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk"),
            originalDraftAfterSubmit: "Roma",
            replacementDraftAfterSubmit: "Roma Just Talk",
            alertPresentation: .wordReplacement(message: "Failed to add replacement: Disk full")
        )

        XCTAssertEqual(plan.applying(to: existingRules), existingRules)
        XCTAssertNil(plan.updatedRulesIfChanged(from: existingRules))
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

    func testDictionaryBackupImportPlanCombinesVocabularyAndReplacementsForMacOSImport() {
        let plan = VoiceInkDictionaryPolicy.dictionaryBackupImportPlan(
            vocabularyWords: [
                VoiceInkVocabularyWordBackup(word: " Roma "),
                VoiceInkVocabularyWordBackup(word: "voice ink"),
                VoiceInkVocabularyWordBackup(word: "roma")
            ],
            wordReplacements: [
                " Flow, Voice Ink ": " roma ",
                "quick release": "duplicate",
                "blank replacement": " \n ",
                " , ": "ignored"
            ],
            existingWords: ["voice ink"],
            existingOriginalTexts: ["quick release"]
        )

        XCTAssertTrue(plan.hasVocabularyBackupRecords)
        XCTAssertTrue(plan.hasWordReplacementBackupRecords)
        XCTAssertEqual(plan.vocabularyWordsToInsert, ["Roma"])
        XCTAssertEqual(
            plan.wordReplacementRulesToInsert,
            [VoiceInkWordReplacementRule(originalText: "Flow, Voice Ink", replacementText: "roma")]
        )
        XCTAssertEqual(plan.skippedInvalidReplacementCount, 2)
        XCTAssertEqual(plan.insertedVocabularyWordCount, 1)
        XCTAssertEqual(plan.insertedWordReplacementCount, 1)
        XCTAssertTrue(plan.shouldSave)
        XCTAssertTrue(plan.shouldInvalidateWordReplacementCache)
    }

    func testDictionaryBackupImportPlanPreservesNoDataNoSaveDecision() {
        let plan = VoiceInkDictionaryPolicy.dictionaryBackupImportPlan(
            vocabularyWords: nil,
            wordReplacements: nil,
            existingWords: ["voice ink"],
            existingOriginalTexts: ["quick release"]
        )

        XCTAssertFalse(plan.hasVocabularyBackupRecords)
        XCTAssertFalse(plan.hasWordReplacementBackupRecords)
        XCTAssertEqual(plan.vocabularyWordsToInsert, [])
        XCTAssertEqual(plan.wordReplacementRulesToInsert, [])
        XCTAssertEqual(plan.skippedInvalidReplacementCount, 0)
        XCTAssertFalse(plan.shouldSave)
        XCTAssertFalse(plan.shouldInvalidateWordReplacementCache)
    }

    func testDictionaryBackupImportPlanDoesNotInvalidateReplacementCacheForVocabularyOnlyImport() {
        let plan = VoiceInkDictionaryPolicy.dictionaryBackupImportPlan(
            vocabularyWords: [
                VoiceInkVocabularyWordBackup(word: "Roma")
            ],
            wordReplacements: nil,
            existingWords: [],
            existingOriginalTexts: []
        )

        XCTAssertEqual(plan.vocabularyWordsToInsert, ["Roma"])
        XCTAssertEqual(plan.wordReplacementRulesToInsert, [])
        XCTAssertTrue(plan.shouldSave)
        XCTAssertFalse(plan.shouldInvalidateWordReplacementCache)
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.DictionaryPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
