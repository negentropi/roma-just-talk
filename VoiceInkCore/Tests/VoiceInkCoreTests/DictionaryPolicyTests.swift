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
            VoiceInkDictionaryAlertPresentation.failedToAddVocabularyWords([
                "Failed to add 'Roma': Disk full",
                "Failed to add 'VoiceInk': Permission denied"
            ]),
            .vocabulary(message: "Failed to add 'Roma': Disk full; Failed to add 'VoiceInk': Permission denied")
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

    func testDictionarySettingsSectionsPreserveMacOSSelectorOrderAndPresentation() {
        let presentation = VoiceInkDictionarySettingsPresentation.macOS

        XCTAssertEqual(
            VoiceInkDictionarySettingsSection.allCases,
            [.wordReplacements, .vocabulary]
        )
        XCTAssertEqual(VoiceInkDictionarySettingsSection.defaultSelection, .wordReplacements)
        XCTAssertEqual(
            VoiceInkDictionarySettingsSection.wordReplacements.presentation(in: presentation),
            presentation.wordReplacementsSection
        )
        XCTAssertEqual(
            VoiceInkDictionarySettingsSection.vocabulary.presentation(in: presentation),
            presentation.vocabularySection
        )
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

    func testWordReplacementEngineApplyReturnsInputForNoRules() {
        XCTAssertEqual(
            VoiceInkWordReplacementEngine.apply([], to: "Keep this text"),
            "Keep this text"
        )
    }

    func testWordReplacementEngineApplySortsRulesByLongerOriginalText() {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "voice", replacementText: "v"),
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            VoiceInkWordReplacementEngine.apply(rules, to: "voice ink and voice"),
            "roma and v"
        )
    }

    func testWordReplacementEngineApplyUsesCaseInsensitiveWordBoundariesForSpacedText() {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            VoiceInkWordReplacementEngine.apply(rules, to: "Use Voice Ink, not voice inking."),
            "Use roma, not voice inking."
        )
    }

    func testWordReplacementEngineApplySortsCommaSeparatedVariantsByLength() {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "voice, voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            VoiceInkWordReplacementEngine.apply(rules, to: "voice ink and voice"),
            "roma and roma"
        )
    }

    func testWordReplacementEngineApplyUsesSubstringReplacementForNonSpacedScripts() {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "東京", replacementText: "Tokyo")
        ]

        XCTAssertEqual(
            VoiceInkWordReplacementEngine.apply(rules, to: "東京都 and 東京"),
            "Tokyo都 and Tokyo"
        )
    }

    func testWordReplacementRuleCodableRoundTripsIOSPreferenceShape() throws {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ]

        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: data)

        XCTAssertEqual(decoded, rules)
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

    func testDictionarySettingsSnapshotBuildsDisplayedRows() {
        let snapshot = VoiceInkDictionarySettingsSnapshot(
            fillerWords: ["uh"],
            customVocabularyTerms: ["zeta", "Alpha", "beta"],
            wordReplacements: [
                VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk"),
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
                VoiceInkWordReplacementRule(originalText: "alpha", replacementText: "Zed")
            ],
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .replacementDescending
        )

        XCTAssertEqual(snapshot.sortedCustomVocabularyTerms, ["Alpha", "beta", "zeta"])
        XCTAssertEqual(snapshot.sortedWordReplacements.map(\.replacementText), ["Zed", "VoiceInk", "Roma Just Talk"])
    }

    func testDictionarySettingsSnapshotReadsStoredSortPreferences() {
        withIsolatedDefaults { defaults in
            VoiceInkDictionaryListSortPreference.saveVocabularySortMode(.wordDescending, to: defaults)
            VoiceInkDictionaryListSortPreference.saveWordReplacementSortMode(.replacementAscending, to: defaults)

            let snapshot = VoiceInkDictionarySettingsSnapshot(
                fillerWords: ["uh"],
                customVocabularyTerms: ["zeta", "Alpha", "beta"],
                wordReplacements: [
                    VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk"),
                    VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
                    VoiceInkWordReplacementRule(originalText: "alpha", replacementText: "Zed")
                ],
                defaults: defaults
            )

            XCTAssertEqual(snapshot.vocabularySortMode, .wordDescending)
            XCTAssertEqual(snapshot.wordReplacementSortMode, .replacementAscending)
            XCTAssertEqual(snapshot.sortedCustomVocabularyTerms, ["zeta", "beta", "Alpha"])
            XCTAssertEqual(snapshot.sortedWordReplacements.map(\.replacementText), ["Roma Just Talk", "VoiceInk", "Zed"])
        }
    }

    func testDictionarySettingsSnapshotDeletesDisplayedRowsThroughOriginalStorageOrder() {
        let snapshot = VoiceInkDictionarySettingsSnapshot(
            fillerWords: ["uh", "um", "hmm"],
            customVocabularyTerms: ["zeta", "Alpha", "beta", "delta"],
            wordReplacements: [
                VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk"),
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
                VoiceInkWordReplacementRule(originalText: "alpha", replacementText: "Zed")
            ],
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .replacementDescending
        )

        XCTAssertEqual(snapshot.removingFillerWords(at: IndexSet([1])), ["uh", "hmm"])
        XCTAssertEqual(
            snapshot.removingCustomVocabularyTerms(atSortedOffsets: IndexSet([0, 2])),
            ["zeta", "beta"]
        )
        XCTAssertEqual(
            snapshot.removingWordReplacements(atSortedOffsets: IndexSet([0])),
            [
                VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk"),
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ]
        )
    }

    func testDictionarySettingsSnapshotSubmitsAndAppliesDrafts() {
        let snapshot = VoiceInkDictionarySettingsSnapshot(
            fillerWords: ["uh"],
            customVocabularyTerms: ["voice ink"],
            wordReplacements: [
                VoiceInkWordReplacementRule(originalText: "cursor", replacementText: "Cursor")
            ],
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .originalAscending
        )

        let fillerWordSubmission = snapshot.fillerWordSubmission(
            VoiceInkFillerWordDraftState(draft: " Ah ")
        )
        var fillerWords = snapshot.fillerWords
        snapshot.applyFillerWordSubmission(fillerWordSubmission.plan) { fillerWords = $0 }
        XCTAssertEqual(fillerWords, ["uh", "ah"])

        let vocabularySubmission = snapshot.customVocabularySubmission(
            VoiceInkVocabularyDraftState(draft: "Roma, voice ink")
        )
        var customVocabularyTerms = snapshot.customVocabularyTerms
        snapshot.applyCustomVocabularySubmission(vocabularySubmission.plan) { customVocabularyTerms = $0 }
        XCTAssertEqual(customVocabularyTerms, ["voice ink", "Roma"])

        let wordReplacementSubmission = snapshot.wordReplacementSubmission(
            VoiceInkWordReplacementDraftState(original: "Roma", replacement: "Roma Just Talk")
        )
        var wordReplacements = snapshot.wordReplacements
        snapshot.applyWordReplacementSubmission(wordReplacementSubmission.plan) { wordReplacements = $0 }
        XCTAssertEqual(
            wordReplacements,
            [
                VoiceInkWordReplacementRule(originalText: "cursor", replacementText: "Cursor"),
                VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
            ]
        )
    }

    func testDictionarySettingsSnapshotSkipsRuntimeSettersWhenDraftsDoNotChangeStorage() {
        let snapshot = VoiceInkDictionarySettingsSnapshot(
            fillerWords: ["uh"],
            customVocabularyTerms: ["voice ink"],
            wordReplacements: [
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ],
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .originalAscending
        )

        let duplicateFillerWord = snapshot.fillerWordSubmission(VoiceInkFillerWordDraftState(draft: "UH"))
        let duplicateVocabulary = snapshot.customVocabularySubmission(VoiceInkVocabularyDraftState(draft: "Voice Ink"))
        let duplicateReplacement = snapshot.wordReplacementSubmission(
            VoiceInkWordReplacementDraftState(original: "Roma", replacement: "RJT")
        )

        var appliedSetters = [String]()
        snapshot.applyFillerWordSubmission(duplicateFillerWord.plan) { _ in
            appliedSetters.append("fillerWords")
        }
        snapshot.applyCustomVocabularySubmission(duplicateVocabulary.plan) { _ in
            appliedSetters.append("customVocabularyTerms")
        }
        snapshot.applyWordReplacementSubmission(duplicateReplacement.plan) { _ in
            appliedSetters.append("wordReplacements")
        }

        XCTAssertEqual(appliedSetters, [])
    }

    func testDefaultWordsMatchMacOSCleanupDefaults() {
        XCTAssertEqual(
            VoiceInkFillerWords.defaultWords,
            ["uh", "um", "uhm", "umm", "uhh", "uhhh", "hmm", "hm", "mmm", "mm", "mh", "ehh"]
        )
    }

    func testSubmissionPlanInsertsWordAndClearsDraft() {
        XCTAssertEqual(
            VoiceInkFillerWords.submissionPlan("  LIKE  ", existingWords: ["um"]),
            VoiceInkFillerWordSubmissionPlan(
                updatedWords: ["um", "like"],
                draftAfterSubmit: "",
                alertPresentation: nil,
                didInsert: true
            )
        )
        XCTAssertTrue(VoiceInkFillerWords.submissionPlan("like", existingWords: ["um"]).didInsert)
        XCTAssertEqual(
            VoiceInkFillerWords.submissionPlan("like", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"]),
            ["um", "like"]
        )
    }

    func testSubmissionPlanAppliesAcceptedWordsToRuntimeState() {
        let plan = VoiceInkFillerWords.submissionPlan("LIKE", existingWords: ["um"])
        var words = ["um"]

        plan.applyRuntimeState(currentWords: words) { words = $0 }

        XCTAssertEqual(words, ["um", "like"])
    }

    func testSubmissionPlanKeepsBlankDraftWithoutAlert() {
        XCTAssertEqual(
            VoiceInkFillerWords.submissionPlan("   ", existingWords: ["um"]),
            VoiceInkFillerWordSubmissionPlan(
                updatedWords: ["um"],
                draftAfterSubmit: "   ",
                alertPresentation: nil
            )
        )
        XCTAssertFalse(VoiceInkFillerWords.submissionPlan("   ", existingWords: ["um"]).didInsert)
        XCTAssertFalse(VoiceInkFillerWords.submissionPlan("", existingWords: ["um"]).didInsert)
        XCTAssertNil(
            VoiceInkFillerWords.submissionPlan("   ", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"])
        )
    }

    func testSubmissionPlanKeepsDuplicateDraftAndBuildsSharedAlert() {
        XCTAssertEqual(
            VoiceInkFillerWords.submissionPlan("UM", existingWords: ["um"]),
            VoiceInkFillerWordSubmissionPlan(
                updatedWords: ["um"],
                draftAfterSubmit: "UM",
                alertPresentation: .duplicateFillerWord(message: "This filler word is already in the list.")
            )
        )
        XCTAssertFalse(VoiceInkFillerWords.submissionPlan("UM", existingWords: ["um"]).didInsert)
        XCTAssertNil(
            VoiceInkFillerWords.submissionPlan("UM", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"])
        )
    }

    func testDraftAvailabilityUsesSharedNormalization() {
        XCTAssertFalse(VoiceInkFillerWords.hasDraft(" \n\t "))
        XCTAssertTrue(VoiceInkFillerWords.hasDraft(" LIKE "))
    }

    func testDraftStateUsesSharedSubmitAvailability() {
        XCTAssertFalse(VoiceInkFillerWordDraftState(draft: " \n\t ").canSubmit)
        XCTAssertTrue(VoiceInkFillerWordDraftState(draft: " LIKE ").canSubmit)
    }

    func testEditorPresentationOwnsPlatformVisibilityPolicy() {
        XCTAssertEqual(
            VoiceInkFillerWords.editorPresentation(isEnabled: false, words: ["um"]),
            VoiceInkFillerWordEditorPresentation(
                shouldShowEditor: false,
                shouldShowWordList: false
            )
        )
        XCTAssertEqual(
            VoiceInkFillerWords.editorPresentation(isEnabled: true, words: []),
            VoiceInkFillerWordEditorPresentation(
                shouldShowEditor: true,
                shouldShowWordList: false
            )
        )
        XCTAssertEqual(
            VoiceInkFillerWords.editorPresentation(isEnabled: true, words: ["um"]),
            VoiceInkFillerWordEditorPresentation(
                shouldShowEditor: true,
                shouldShowWordList: true
            )
        )
    }

    func testDraftStateSubmitsAndClearsAcceptedWord() {
        let submission = VoiceInkFillerWordDraftState(draft: " LIKE ")
            .submitting(existingWords: ["um"])

        XCTAssertEqual(
            submission.plan,
            VoiceInkFillerWordSubmissionPlan(
                updatedWords: ["um", "like"],
                draftAfterSubmit: "",
                alertPresentation: nil,
                didInsert: true
            )
        )
        XCTAssertEqual(submission.draftStateAfterSubmit, VoiceInkFillerWordDraftState())
        XCTAssertNil(submission.alertPresentation)
    }

    func testDraftStateKeepsDuplicateDraftAndBuildsSharedAlert() {
        let submission = VoiceInkFillerWordDraftState(draft: "UM")
            .submitting(existingWords: ["um"])

        XCTAssertEqual(submission.plan.updatedWords, ["um"])
        XCTAssertEqual(submission.draftStateAfterSubmit, VoiceInkFillerWordDraftState(draft: "UM"))
        XCTAssertEqual(
            submission.alertPresentation,
            .duplicateFillerWord(message: "This filler word is already in the list.")
        )
    }

    func testDraftSubmissionAppliesRuntimeStateAfterStoragePlan() {
        let submission = VoiceInkFillerWordDraftState(draft: "LIKE")
            .submitting(existingWords: ["um"])
        var events = [String]()
        var appliedPlan: VoiceInkFillerWordSubmissionPlan?
        var draftState = VoiceInkFillerWordDraftState(draft: "LIKE")
        var alertPresentation: VoiceInkDictionaryAlertPresentation? = .vocabulary(message: "stale")

        let returnedSubmission = submission.applyRuntimeState(
            applyPlan: {
                events.append("plan")
                appliedPlan = $0
            },
            setDraftState: {
                events.append("draft")
                draftState = $0
            },
            setAlertPresentation: {
                events.append("alert")
                alertPresentation = $0
            }
        )

        XCTAssertEqual(returnedSubmission, submission)
        XCTAssertEqual(events, ["plan", "draft", "alert"])
        XCTAssertEqual(appliedPlan, submission.plan)
        XCTAssertEqual(draftState, VoiceInkFillerWordDraftState())
        XCTAssertNil(alertPresentation)
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

    func testCustomVocabularyTermsTrimDropBlankAndDeduplicateCaseInsensitively() {
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized([
                "  Roma  ",
                "",
                "roma",
                "VoiceInk",
                " voiceink ",
                "Cursor"
            ]),
            ["Roma", "VoiceInk", "Cursor"]
        )
    }

    func testCustomVocabularyTermsApplyOptionalLimitAfterFiltering() {
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(
                ["", " Roma ", "roma", "Cursor", "SwiftData"],
                limit: 2
            ),
            ["Roma", "Cursor"]
        )
    }

    func testCustomVocabularyTermsApplyDeepgramStreamingLimitFromSharedUsePolicy() {
        let terms = (1...55).map { "term-\($0)" }

        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .streamingTranscription(.deepgram)),
            Array(terms.prefix(50))
        )
    }

    func testCustomVocabularyTermsKeepTermsForSupportedUses() {
        let terms = (1...55).map { "term-\($0)" }

        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .batchTranscription(.soniox)),
            terms
        )
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .streamingTranscription(.soniox)),
            terms
        )
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .postProcessingContext),
            terms
        )
    }

    func testCustomVocabularyTermsDropTermsForUnsupportedTranscriptionUses() {
        let terms = ["Roma", "Felix"]

        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .batchTranscription(.groq)),
            []
        )
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .batchTranscription(.deepgram)),
            []
        )
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .streamingTranscription(.mistral)),
            []
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

    func testVocabularyDraftSubmissionAppliesRuntimeState() {
        let submission = VoiceInkVocabularyDraftState(draft: "Voice Ink")
            .submitting(existingWords: [])
        var draftState = VoiceInkVocabularyDraftState(draft: "Voice Ink")
        var alertPresentation: VoiceInkDictionaryAlertPresentation? = .vocabulary(message: "stale")

        let returnedSubmission = submission.applyRuntimeState(
            setDraftState: { draftState = $0 },
            setAlertPresentation: { alertPresentation = $0 }
        )

        XCTAssertEqual(returnedSubmission, submission)
        XCTAssertEqual(draftState, VoiceInkVocabularyDraftState())
        XCTAssertNil(alertPresentation)
    }

    func testVocabularySubmissionPlanAppliesAcceptedWordsToRuntimeState() {
        let plan = VoiceInkDictionaryPolicy.vocabularySubmissionPlan(
            input: "Roma, VoiceInk",
            existingWords: ["Cursor"]
        )
        var words = ["Cursor"]

        plan.applyRuntimeState(currentWords: words) { words = $0 }

        XCTAssertEqual(words, ["Cursor", "Roma", "VoiceInk"])
    }

    func testVocabularyDraftSubmissionAppliesPersistenceFailureInCore() {
        let submission = VoiceInkVocabularyDraftState(draft: "Roma, VoiceInk")
            .submitting(existingWords: [])
        var insertedWords = [String]()

        let returnedSubmission = submission.applyPersistenceRuntimeState { word in
            insertedWords.append(word)
            return word == "Roma" ? "Disk full" : nil
        }

        XCTAssertEqual(insertedWords, ["Roma", "VoiceInk"])
        XCTAssertEqual(returnedSubmission.submittedDraft, "Roma, VoiceInk")
        XCTAssertEqual(returnedSubmission.plan.wordsToInsert, ["Roma", "VoiceInk"])
        XCTAssertEqual(returnedSubmission.draftStateAfterSubmit, VoiceInkVocabularyDraftState(draft: "Roma, VoiceInk"))
        XCTAssertEqual(
            returnedSubmission.alertPresentation,
            .vocabulary(message: "Failed to add 'Roma': Disk full")
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
            dictionaryBackupExportRuntimeEvents(
                for: VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(
                    vocabularyWords: [],
                    wordReplacementRules: []
                )
            ),
            [
                "vocabulary:nil",
                "replacements:nil"
            ]
        )

        XCTAssertEqual(
            dictionaryBackupExportRuntimeEvents(
                for: VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(
                    vocabularyWords: ["Roma", "VoiceInk"],
                    wordReplacementRules: [
                        VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk")
                    ]
                )
            ),
            [
                "vocabulary:Roma,VoiceInk",
                "replacements:voice ink=VoiceInk"
            ]
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

        XCTAssertEqual(
            dictionaryBackupExportRuntimeEvents(for: plan),
            [
                "vocabulary:nil",
                "replacements:voice ink=roma just talk"
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

    func testWordReplacementDraftStateSubmitsAgainstExistingRules() {
        let existingRules = [
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ]

        let submission = VoiceInkWordReplacementDraftState(
            original: "Roma",
            replacement: "RJT"
        )
        .submitting(existingRules: existingRules)

        XCTAssertNil(submission.plan.ruleToInsert)
        XCTAssertEqual(
            submission.alertPresentation,
            .wordReplacement(message: "'Roma' already exists in word replacements")
        )
    }

    func testWordReplacementDraftSubmissionAppliesRuntimeState() {
        let submission = VoiceInkWordReplacementDraftState(
            original: "Roma",
            replacement: "Roma Just Talk"
        )
        .submitting(existingOriginalTexts: ["roma"])
        var draftState = VoiceInkWordReplacementDraftState()
        var alertPresentation: VoiceInkDictionaryAlertPresentation?

        let returnedSubmission = submission.applyRuntimeState(
            setDraftState: { draftState = $0 },
            setAlertPresentation: { alertPresentation = $0 }
        )

        XCTAssertEqual(returnedSubmission, submission)
        XCTAssertEqual(
            draftState,
            VoiceInkWordReplacementDraftState(original: "Roma", replacement: "Roma Just Talk")
        )
        XCTAssertEqual(
            alertPresentation,
            .wordReplacement(message: "'Roma' already exists in word replacements")
        )
    }

    func testWordReplacementSubmissionPlanAppliesAcceptedRuleToRuntimeState() {
        let plan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: "Roma",
            replacement: "Roma Just Talk",
            existingOriginalTexts: []
        )
        var rules = [VoiceInkWordReplacementRule]()

        plan.applyRuntimeState(currentRules: rules) { rules = $0 }

        XCTAssertEqual(
            rules,
            [VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")]
        )
    }

    func testWordReplacementDraftSubmissionAppliesPersistenceFailureInCore() {
        let submission = VoiceInkWordReplacementDraftState(
            original: "Roma",
            replacement: "Roma Just Talk"
        )
        .submitting(existingOriginalTexts: [])
        var insertedRules = [VoiceInkWordReplacementRule]()

        let returnedSubmission = submission.applyPersistenceRuntimeState { rule in
            insertedRules.append(rule)
            return "Disk full"
        }

        XCTAssertEqual(
            insertedRules,
            [VoiceInkWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")]
        )
        XCTAssertEqual(returnedSubmission.submittedOriginal, "Roma")
        XCTAssertEqual(returnedSubmission.submittedReplacement, "Roma Just Talk")
        XCTAssertEqual(
            returnedSubmission.draftStateAfterSubmit,
            VoiceInkWordReplacementDraftState(original: "Roma", replacement: "Roma Just Talk")
        )
        XCTAssertEqual(
            returnedSubmission.alertPresentation,
            .wordReplacement(message: "Failed to add replacement: Disk full")
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

    func testWordReplacementEditStateSubmitsAgainstExistingRules() {
        let existingRules = [
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "VoiceInk")
        ]

        let submission = VoiceInkWordReplacementEditState(
            original: "Voice Ink",
            replacement: "Roma"
        )
        .submitting(existingRules: existingRules)

        XCTAssertFalse(submission.shouldUpdate)
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

        XCTAssertEqual(
            dictionaryBackupImportRuntimeEvents(for: plan),
            [
                "vocabulary:Roma",
                "replacement:Flow, Voice Ink=roma",
                "save",
                "invalidateReplacements",
                "imported:1:1",
                "skippedInvalid:2"
            ]
        )
    }

    func testDictionaryBackupImportPlanPreservesNoDataNoSaveDecision() {
        let plan = VoiceInkDictionaryPolicy.dictionaryBackupImportPlan(
            vocabularyWords: nil,
            wordReplacements: nil,
            existingWords: ["voice ink"],
            existingOriginalTexts: ["quick release"]
        )

        XCTAssertEqual(
            dictionaryBackupImportRuntimeEvents(for: plan),
            [
                "noVocabulary",
                "noReplacements",
                "noImported"
            ]
        )
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

        XCTAssertEqual(
            dictionaryBackupImportRuntimeEvents(for: plan),
            [
                "noReplacements",
                "vocabulary:Roma",
                "save",
                "imported:1:0"
            ]
        )
    }

    private func dictionaryBackupExportRuntimeEvents(
        for plan: VoiceInkDictionaryBackupExportPlan
    ) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            setVocabularyBackupRecords: { records in
                events.append("vocabulary:\(records?.map(\.word).joined(separator: ",") ?? "nil")")
            },
            setWordReplacementBackupRecords: { records in
                let summary = records?
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ",") ?? "nil"
                events.append("replacements:\(summary)")
            }
        )

        return events
    }

    private func dictionaryBackupImportRuntimeEvents(
        for plan: VoiceInkDictionaryBackupImportPlan
    ) -> [String] {
        var events: [String] = []

        do {
            try plan.applyRuntimeState(
                reportNoVocabularyBackupRecords: {
                    events.append("noVocabulary")
                },
                reportNoWordReplacementBackupRecords: {
                    events.append("noReplacements")
                },
                insertVocabularyWord: { word in
                    events.append("vocabulary:\(word)")
                },
                insertWordReplacementRule: { rule in
                    events.append("replacement:\(rule.originalText)=\(rule.replacementText)")
                },
                reportNoDictionaryEntriesImported: {
                    events.append("noImported")
                },
                save: {
                    events.append("save")
                },
                invalidateWordReplacementCache: {
                    events.append("invalidateReplacements")
                },
                reportImportedEntryCounts: { vocabularyWordCount, wordReplacementCount in
                    events.append("imported:\(vocabularyWordCount):\(wordReplacementCount)")
                },
                reportSkippedInvalidReplacementCount: { count in
                    events.append("skippedInvalid:\(count)")
                }
            )
        } catch {
            XCTFail("Unexpected dictionary import runtime error: \(error)")
        }

        return events
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.DictionaryPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
