import Foundation
import RomaCore

final class DictionaryPolicyTests: XCTestCase {

    func testDictionarySettingsSectionsPreserveMacOSSelectorOrderAndPresentation() {
        let presentation = RomaDictionarySettingsPresentation.macOS

        XCTAssertEqual(
            RomaDictionarySettingsSection.allCases,
            [.wordReplacements, .vocabulary]
        )
        XCTAssertEqual(RomaDictionarySettingsSection.defaultSelection, .wordReplacements)
        XCTAssertEqual(
            RomaDictionarySettingsSection.wordReplacements.presentation(in: presentation),
            presentation.wordReplacementsSection
        )
        XCTAssertEqual(
            RomaDictionarySettingsSection.vocabulary.presentation(in: presentation),
            presentation.vocabularySection
        )
    }

    func testWordReplacementEngineApplyReturnsInputForNoRules() {
        XCTAssertEqual(
            RomaWordReplacementEngine.apply([], to: "Keep this text"),
            "Keep this text"
        )
    }

    func testWordReplacementEngineApplySortsRulesByLongerOriginalText() {
        let rules = [
            RomaWordReplacementRule(originalText: "voice", replacementText: "v"),
            RomaWordReplacementRule(originalText: "voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            RomaWordReplacementEngine.apply(rules, to: "voice ink and voice"),
            "roma and v"
        )
    }

    func testWordReplacementEngineApplyUsesCaseInsensitiveWordBoundariesForSpacedText() {
        let rules = [
            RomaWordReplacementRule(originalText: "voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            RomaWordReplacementEngine.apply(rules, to: "Use Voice Ink, not voice inking."),
            "Use roma, not voice inking."
        )
    }

    func testWordReplacementEngineApplySortsCommaSeparatedVariantsByLength() {
        let rules = [
            RomaWordReplacementRule(originalText: "voice, voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            RomaWordReplacementEngine.apply(rules, to: "voice ink and voice"),
            "roma and roma"
        )
    }

    func testWordReplacementEngineApplyUsesSubstringReplacementForNonSpacedScripts() {
        let rules = [
            RomaWordReplacementRule(originalText: "東京", replacementText: "Tokyo")
        ]

        XCTAssertEqual(
            RomaWordReplacementEngine.apply(rules, to: "東京都 and 東京"),
            "Tokyo都 and Tokyo"
        )
    }

    func testWordReplacementRuleCodableRoundTripsIOSPreferenceShape() throws {
        let rules = [
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ]

        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([RomaWordReplacementRule].self, from: data)

        XCTAssertEqual(decoded, rules)
    }

    func testDictionaryListSortModesPreserveStorageAndIndicatorValues() {
        XCTAssertEqual(RomaVocabularySortMode.wordAscending.rawValue, "wordAsc")
        XCTAssertEqual(RomaVocabularySortMode.wordDescending.rawValue, "wordDesc")
        XCTAssertEqual(RomaVocabularySortMode.defaultMode, .wordAscending)
        XCTAssertEqual(RomaVocabularySortMode.wordAscending.indicatorSystemImageName, "chevron.up")
        XCTAssertEqual(RomaVocabularySortMode.wordDescending.indicatorSystemImageName, "chevron.down")
        XCTAssertEqual(RomaVocabularySortMode.wordAscending.toggled(), .wordDescending)
        XCTAssertEqual(RomaVocabularySortMode.wordDescending.toggled(), .wordAscending)

        XCTAssertEqual(RomaWordReplacementSortMode.originalAscending.rawValue, "originalAsc")
        XCTAssertEqual(RomaWordReplacementSortMode.originalDescending.rawValue, "originalDesc")
        XCTAssertEqual(RomaWordReplacementSortMode.replacementAscending.rawValue, "replacementAsc")
        XCTAssertEqual(RomaWordReplacementSortMode.replacementDescending.rawValue, "replacementDesc")
        XCTAssertEqual(RomaWordReplacementSortMode.defaultMode, .originalAscending)
        XCTAssertEqual(RomaWordReplacementSortMode.originalAscending.activeColumn, .original)
        XCTAssertEqual(RomaWordReplacementSortMode.originalDescending.activeColumn, .original)
        XCTAssertEqual(RomaWordReplacementSortMode.replacementAscending.activeColumn, .replacement)
        XCTAssertEqual(RomaWordReplacementSortMode.replacementDescending.activeColumn, .replacement)
        XCTAssertEqual(RomaWordReplacementSortMode.originalAscending.indicatorSystemImageName, "chevron.up")
        XCTAssertEqual(RomaWordReplacementSortMode.originalDescending.indicatorSystemImageName, "chevron.down")
        XCTAssertEqual(RomaWordReplacementSortMode.originalAscending.toggled(for: .original), .originalDescending)
        XCTAssertEqual(RomaWordReplacementSortMode.originalDescending.toggled(for: .original), .originalAscending)
        XCTAssertEqual(RomaWordReplacementSortMode.originalDescending.toggled(for: .replacement), .replacementAscending)
        XCTAssertEqual(RomaWordReplacementSortMode.replacementAscending.toggled(for: .replacement), .replacementDescending)
    }

    func testDictionaryListSortPreferencesReadDefaultsAndSaveModes() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(RomaDictionaryListSortPreference.wordReplacementSortMode(from: defaults), .originalAscending)

            defaults.set("invalid", forKey: RomaDictionaryListSortPreference.vocabularySortModeKey)
            defaults.set("invalid", forKey: RomaDictionaryListSortPreference.wordReplacementSortModeKey)

            XCTAssertEqual(RomaDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(RomaDictionaryListSortPreference.wordReplacementSortMode(from: defaults), .originalAscending)

            RomaDictionaryListSortPreference.saveVocabularySortMode(.wordDescending, to: defaults)
            RomaDictionaryListSortPreference.saveWordReplacementSortMode(.replacementDescending, to: defaults)

            XCTAssertEqual(RomaDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordDescending)
            XCTAssertEqual(RomaDictionaryListSortPreference.wordReplacementSortMode(from: defaults), .replacementDescending)

            RomaDictionaryListSortPreference.clear(from: defaults)

            XCTAssertEqual(RomaDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(RomaDictionaryListSortPreference.wordReplacementSortMode(from: defaults), .originalAscending)
        }
    }

    func testDictionaryListSortPolicySortsVocabularyAndWordReplacements() {
        let vocabulary = ["zeta", "Alpha", "beta"]

        XCTAssertEqual(
            RomaDictionaryListSortPolicy.sortedVocabulary(vocabulary, mode: .wordAscending) { $0 },
            ["Alpha", "beta", "zeta"]
        )
        XCTAssertEqual(
            RomaDictionaryListSortPolicy.sortedVocabulary(vocabulary, mode: .wordDescending) { $0 },
            ["zeta", "beta", "Alpha"]
        )

        let replacements = [
            RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk"),
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
            RomaWordReplacementRule(originalText: "alpha", replacementText: "Zed")
        ]

        XCTAssertEqual(
            RomaDictionaryListSortPolicy.sortedWordReplacements(
                replacements,
                mode: .originalAscending,
                originalText: { $0.originalText },
                replacementText: { $0.replacementText }
            ).map(\.originalText),
            ["alpha", "roma", "voice ink"]
        )
        XCTAssertEqual(
            RomaDictionaryListSortPolicy.sortedWordReplacements(
                replacements,
                mode: .replacementDescending,
                originalText: { $0.originalText },
                replacementText: { $0.replacementText }
            ).map(\.replacementText),
            ["Zed", "RomaJustTalk", "Roma Just Talk"]
        )
    }

    func testDictionaryListSortPolicyRemovesDisplayedSortedVocabularyRows() {
        let vocabulary = ["zeta", "Alpha", "beta", "delta"]

        XCTAssertEqual(
            RomaDictionaryListSortPolicy.removingVocabulary(
                atSortedOffsets: IndexSet([0, 2]),
                from: vocabulary,
                mode: .wordAscending,
                word: { $0 }
            ),
            ["zeta", "beta"]
        )
        XCTAssertEqual(
            RomaDictionaryListSortPolicy.removingVocabulary(
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
            RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk"),
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
            RomaWordReplacementRule(originalText: "alpha", replacementText: "Zed")
        ]

        XCTAssertEqual(
            RomaDictionaryListSortPolicy.removingWordReplacements(
                atSortedOffsets: IndexSet([0]),
                from: replacements,
                mode: .replacementDescending,
                originalText: { $0.originalText },
                replacementText: { $0.replacementText }
            ),
            [
                RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk"),
                RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ]
        )
        XCTAssertEqual(
            RomaDictionaryListSortPolicy.removingWordReplacements(
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
        let snapshot = RomaDictionarySettingsSnapshot(
            fillerWords: ["uh"],
            customVocabularyTerms: ["zeta", "Alpha", "beta"],
            wordReplacements: [
                RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk"),
                RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
                RomaWordReplacementRule(originalText: "alpha", replacementText: "Zed")
            ],
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .replacementDescending
        )

        XCTAssertEqual(snapshot.sortedCustomVocabularyTerms, ["Alpha", "beta", "zeta"])
        XCTAssertEqual(snapshot.sortedWordReplacements.map(\.replacementText), ["Zed", "RomaJustTalk", "Roma Just Talk"])
    }

    func testDictionarySettingsSnapshotReadsStoredSortPreferences() {
        withIsolatedDefaults { defaults in
            RomaDictionaryListSortPreference.saveVocabularySortMode(.wordDescending, to: defaults)
            RomaDictionaryListSortPreference.saveWordReplacementSortMode(.replacementAscending, to: defaults)

            let snapshot = RomaDictionarySettingsSnapshot(
                fillerWords: ["uh"],
                customVocabularyTerms: ["zeta", "Alpha", "beta"],
                wordReplacements: [
                    RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk"),
                    RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
                    RomaWordReplacementRule(originalText: "alpha", replacementText: "Zed")
                ],
                defaults: defaults
            )

            XCTAssertEqual(snapshot.vocabularySortMode, .wordDescending)
            XCTAssertEqual(snapshot.wordReplacementSortMode, .replacementAscending)
            XCTAssertEqual(snapshot.sortedCustomVocabularyTerms, ["zeta", "beta", "Alpha"])
            XCTAssertEqual(snapshot.sortedWordReplacements.map(\.replacementText), ["Roma Just Talk", "RomaJustTalk", "Zed"])
        }
    }

    func testDictionarySettingsSnapshotDeletesDisplayedRowsThroughOriginalStorageOrder() {
        let snapshot = RomaDictionarySettingsSnapshot(
            fillerWords: ["uh", "um", "hmm"],
            customVocabularyTerms: ["zeta", "Alpha", "beta", "delta"],
            wordReplacements: [
                RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk"),
                RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk"),
                RomaWordReplacementRule(originalText: "alpha", replacementText: "Zed")
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
                RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk"),
                RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ]
        )
    }

    func testDictionarySettingsSnapshotSubmitsAndAppliesDrafts() {
        let snapshot = RomaDictionarySettingsSnapshot(
            fillerWords: ["uh"],
            customVocabularyTerms: ["voice ink"],
            wordReplacements: [
                RomaWordReplacementRule(originalText: "cursor", replacementText: "Cursor")
            ],
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .originalAscending
        )

        let fillerWordSubmission = snapshot.fillerWordSubmission(
            RomaFillerWordDraftState(draft: " Ah ")
        )
        var fillerWords = snapshot.fillerWords
        snapshot.applyFillerWordSubmission(fillerWordSubmission.plan) { fillerWords = $0 }
        XCTAssertEqual(fillerWords, ["uh", "ah"])

        let vocabularySubmission = snapshot.customVocabularySubmission(
            RomaVocabularyDraftState(draft: "Roma, voice ink")
        )
        var customVocabularyTerms = snapshot.customVocabularyTerms
        snapshot.applyCustomVocabularySubmission(vocabularySubmission.plan) { customVocabularyTerms = $0 }
        XCTAssertEqual(customVocabularyTerms, ["voice ink", "Roma"])

        let wordReplacementSubmission = snapshot.wordReplacementSubmission(
            RomaWordReplacementDraftState(original: "Roma", replacement: "Roma Just Talk")
        )
        var wordReplacements = snapshot.wordReplacements
        snapshot.applyWordReplacementSubmission(wordReplacementSubmission.plan) { wordReplacements = $0 }
        XCTAssertEqual(
            wordReplacements,
            [
                RomaWordReplacementRule(originalText: "cursor", replacementText: "Cursor"),
                RomaWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
            ]
        )
    }

    func testDictionarySettingsSnapshotSkipsRuntimeSettersWhenDraftsDoNotChangeStorage() {
        let snapshot = RomaDictionarySettingsSnapshot(
            fillerWords: ["uh"],
            customVocabularyTerms: ["voice ink"],
            wordReplacements: [
                RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ],
            vocabularySortMode: .wordAscending,
            wordReplacementSortMode: .originalAscending
        )

        let duplicateFillerWord = snapshot.fillerWordSubmission(RomaFillerWordDraftState(draft: "UH"))
        let duplicateVocabulary = snapshot.customVocabularySubmission(RomaVocabularyDraftState(draft: "Voice Ink"))
        let duplicateReplacement = snapshot.wordReplacementSubmission(
            RomaWordReplacementDraftState(original: "Roma", replacement: "RJT")
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
            RomaFillerWords.defaultWords,
            ["uh", "um", "uhm", "umm", "uhh", "uhhh", "hmm", "hm", "mmm", "mm", "mh", "ehh"]
        )
    }

    func testSubmissionPlanInsertsWordAndClearsDraft() {
        XCTAssertEqual(
            RomaFillerWords.submissionPlan("  LIKE  ", existingWords: ["um"]),
            RomaFillerWordSubmissionPlan(
                updatedWords: ["um", "like"],
                draftAfterSubmit: "",
                alertPresentation: nil,
                didInsert: true
            )
        )
        XCTAssertTrue(RomaFillerWords.submissionPlan("like", existingWords: ["um"]).didInsert)
        XCTAssertEqual(
            RomaFillerWords.submissionPlan("like", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"]),
            ["um", "like"]
        )
    }

    func testSubmissionPlanAppliesAcceptedWordsToRuntimeState() {
        let plan = RomaFillerWords.submissionPlan("LIKE", existingWords: ["um"])
        var words = ["um"]

        plan.applyRuntimeState(currentWords: words) { words = $0 }

        XCTAssertEqual(words, ["um", "like"])
    }

    func testSubmissionPlanKeepsBlankDraftWithoutAlert() {
        XCTAssertEqual(
            RomaFillerWords.submissionPlan("   ", existingWords: ["um"]),
            RomaFillerWordSubmissionPlan(
                updatedWords: ["um"],
                draftAfterSubmit: "   ",
                alertPresentation: nil
            )
        )
        XCTAssertFalse(RomaFillerWords.submissionPlan("   ", existingWords: ["um"]).didInsert)
        XCTAssertFalse(RomaFillerWords.submissionPlan("", existingWords: ["um"]).didInsert)
        XCTAssertNil(
            RomaFillerWords.submissionPlan("   ", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"])
        )
    }

    func testSubmissionPlanKeepsDuplicateDraftAndBuildsSharedAlert() {
        XCTAssertEqual(
            RomaFillerWords.submissionPlan("UM", existingWords: ["um"]),
            RomaFillerWordSubmissionPlan(
                updatedWords: ["um"],
                draftAfterSubmit: "UM",
                alertPresentation: .duplicateFillerWord(message: "This filler word is already in the list.")
            )
        )
        XCTAssertFalse(RomaFillerWords.submissionPlan("UM", existingWords: ["um"]).didInsert)
        XCTAssertNil(
            RomaFillerWords.submissionPlan("UM", existingWords: ["um"])
                .updatedWordsIfChanged(from: ["um"])
        )
    }

    func testDraftAvailabilityUsesSharedNormalization() {
        XCTAssertFalse(RomaFillerWords.hasDraft(" \n\t "))
        XCTAssertTrue(RomaFillerWords.hasDraft(" LIKE "))
    }

    func testDraftStateUsesSharedSubmitAvailability() {
        XCTAssertFalse(RomaFillerWordDraftState(draft: " \n\t ").canSubmit)
        XCTAssertTrue(RomaFillerWordDraftState(draft: " LIKE ").canSubmit)
    }

    func testEditorPresentationOwnsPlatformVisibilityPolicy() {
        XCTAssertEqual(
            RomaFillerWords.editorPresentation(isEnabled: false, words: ["um"]),
            RomaFillerWordEditorPresentation(
                shouldShowEditor: false,
                shouldShowWordList: false
            )
        )
        XCTAssertEqual(
            RomaFillerWords.editorPresentation(isEnabled: true, words: []),
            RomaFillerWordEditorPresentation(
                shouldShowEditor: true,
                shouldShowWordList: false
            )
        )
        XCTAssertEqual(
            RomaFillerWords.editorPresentation(isEnabled: true, words: ["um"]),
            RomaFillerWordEditorPresentation(
                shouldShowEditor: true,
                shouldShowWordList: true
            )
        )
    }

    func testDraftStateSubmitsAndClearsAcceptedWord() {
        let submission = RomaFillerWordDraftState(draft: " LIKE ")
            .submitting(existingWords: ["um"])

        XCTAssertEqual(
            submission.plan,
            RomaFillerWordSubmissionPlan(
                updatedWords: ["um", "like"],
                draftAfterSubmit: "",
                alertPresentation: nil,
                didInsert: true
            )
        )
        XCTAssertEqual(submission.draftStateAfterSubmit, RomaFillerWordDraftState())
        XCTAssertNil(submission.alertPresentation)
    }

    func testDraftStateKeepsDuplicateDraftAndBuildsSharedAlert() {
        let submission = RomaFillerWordDraftState(draft: "UM")
            .submitting(existingWords: ["um"])

        XCTAssertEqual(submission.plan.updatedWords, ["um"])
        XCTAssertEqual(submission.draftStateAfterSubmit, RomaFillerWordDraftState(draft: "UM"))
        XCTAssertEqual(
            submission.alertPresentation,
            .duplicateFillerWord(message: "This filler word is already in the list.")
        )
    }

    func testDraftSubmissionAppliesRuntimeStateAfterStoragePlan() {
        let submission = RomaFillerWordDraftState(draft: "LIKE")
            .submitting(existingWords: ["um"])
        var events = [String]()
        var appliedPlan: RomaFillerWordSubmissionPlan?
        var draftState = RomaFillerWordDraftState(draft: "LIKE")
        var alertPresentation: RomaDictionaryAlertPresentation? = .vocabulary(message: "stale")

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
        XCTAssertEqual(draftState, RomaFillerWordDraftState())
        XCTAssertNil(alertPresentation)
    }

    func testRemovingDropsWordsCaseInsensitively() {
        XCTAssertEqual(
            RomaFillerWords.removing("UM", from: ["uh", "um", "like"]),
            ["uh", "like"]
        )
    }

    func testRemovingAtOffsetsMatchesIOSListDeletion() {
        XCTAssertEqual(
            RomaFillerWords.removing(at: IndexSet([1, 3]), from: ["uh", "um", "like", "hmm"]),
            ["uh", "like"]
        )
    }

    func testCustomVocabularyTermsTrimDropBlankAndDeduplicateCaseInsensitively() {
        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized([
                "  Roma  ",
                "",
                "roma",
                "RomaJustTalk",
                " roma ",
                "Cursor"
            ]),
            ["Roma", "RomaJustTalk", "Cursor"]
        )
    }

    func testCustomVocabularyTermsApplyOptionalLimitAfterFiltering() {
        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized(
                ["", " Roma ", "roma", "Cursor", "SwiftData"],
                limit: 2
            ),
            ["Roma", "Cursor"]
        )
    }

    func testCustomVocabularyTermsApplyDeepgramStreamingLimitFromSharedUsePolicy() {
        let terms = (1...55).map { "term-\($0)" }

        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized(terms, for: .streamingTranscription(.deepgram)),
            Array(terms.prefix(50))
        )
    }

    func testCustomVocabularyTermsKeepTermsForSupportedUses() {
        let terms = (1...55).map { "term-\($0)" }

        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized(terms, for: .batchTranscription(.soniox)),
            terms
        )
        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized(terms, for: .streamingTranscription(.soniox)),
            terms
        )
        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized(terms, for: .postProcessingContext),
            terms
        )
    }

    func testCustomVocabularyTermsDropTermsForUnsupportedTranscriptionUses() {
        let terms = ["Roma", "Felix"]

        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized(terms, for: .batchTranscription(.groq)),
            []
        )
        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized(terms, for: .batchTranscription(.deepgram)),
            []
        )
        XCTAssertEqual(
            RomaCustomVocabularyTerms.normalized(terms, for: .streamingTranscription(.mistral)),
            []
        )
    }

    func testVocabularyDraftUsesSharedTokenPolicy() {
        XCTAssertFalse(RomaDictionaryPolicy.hasVocabularyDraft(" , \n "))
        XCTAssertTrue(RomaDictionaryPolicy.hasVocabularyDraft("Voice Ink, "))
    }

    func testVocabularyDraftStateUsesSharedTokenPolicy() {
        XCTAssertFalse(RomaVocabularyDraftState(draft: " , \n ").canSubmit)
        XCTAssertTrue(RomaVocabularyDraftState(draft: "Voice Ink, ").canSubmit)
    }

    func testVocabularyDraftStateSubmitsAndClearsAcceptedWords() {
        let submission = RomaVocabularyDraftState(draft: "Voice Ink, Roma, roma, Cursor")
            .submitting(existingWords: ["voice ink"])

        XCTAssertEqual(submission.submittedDraft, "Voice Ink, Roma, roma, Cursor")
        XCTAssertEqual(submission.plan.wordsToInsert, ["Roma", "Cursor"])
        XCTAssertEqual(submission.draftStateAfterSubmit, RomaVocabularyDraftState())
        XCTAssertNil(submission.alertPresentation)
    }

    func testVocabularyDraftStateKeepsDuplicateDraftAndBuildsSharedAlert() {
        let submission = RomaVocabularyDraftState(draft: "Voice Ink")
            .submitting(existingWords: ["voice ink"])

        XCTAssertEqual(submission.submittedDraft, "Voice Ink")
        XCTAssertEqual(submission.plan.wordsToInsert, [])
        XCTAssertEqual(submission.draftStateAfterSubmit, RomaVocabularyDraftState(draft: "Voice Ink"))
        XCTAssertEqual(
            submission.alertPresentation,
            .vocabulary(message: "'Voice Ink' is already in the vocabulary")
        )
    }

    func testVocabularyDraftSubmissionAppliesRuntimeState() {
        let submission = RomaVocabularyDraftState(draft: "Voice Ink")
            .submitting(existingWords: [])
        var draftState = RomaVocabularyDraftState(draft: "Voice Ink")
        var alertPresentation: RomaDictionaryAlertPresentation? = .vocabulary(message: "stale")

        let returnedSubmission = submission.applyRuntimeState(
            setDraftState: { draftState = $0 },
            setAlertPresentation: { alertPresentation = $0 }
        )

        XCTAssertEqual(returnedSubmission, submission)
        XCTAssertEqual(draftState, RomaVocabularyDraftState())
        XCTAssertNil(alertPresentation)
    }

    func testVocabularySubmissionPlanAppliesAcceptedWordsToRuntimeState() {
        let plan = RomaDictionaryPolicy.vocabularySubmissionPlan(
            input: "Roma, RomaJustTalk",
            existingWords: ["Cursor"]
        )
        var words = ["Cursor"]

        plan.applyRuntimeState(currentWords: words) { words = $0 }

        XCTAssertEqual(words, ["Cursor", "Roma", "RomaJustTalk"])
    }

    func testVocabularyDraftSubmissionAppliesPersistenceFailureInCore() {
        let submission = RomaVocabularyDraftState(draft: "Roma, RomaJustTalk")
            .submitting(existingWords: [])
        var insertedWords = [String]()

        let returnedSubmission = submission.applyPersistenceRuntimeState { word in
            insertedWords.append(word)
            return word == "Roma" ? "Disk full" : nil
        }

        XCTAssertEqual(insertedWords, ["Roma", "RomaJustTalk"])
        XCTAssertEqual(returnedSubmission.submittedDraft, "Roma, RomaJustTalk")
        XCTAssertEqual(returnedSubmission.plan.wordsToInsert, ["Roma", "RomaJustTalk"])
        XCTAssertEqual(returnedSubmission.draftStateAfterSubmit, RomaVocabularyDraftState(draft: "Roma, RomaJustTalk"))
        XCTAssertEqual(
            returnedSubmission.alertPresentation,
            .vocabulary(message: "Failed to add 'Roma': Disk full")
        )
    }

    func testVocabularySubmissionPlanKeepsBlankDraftWithoutAlert() {
        let plan = RomaDictionaryPolicy.vocabularySubmissionPlan(
            input: " , \n ",
            existingWords: []
        )

        XCTAssertFalse(plan.shouldInsert)
        XCTAssertFalse(plan.shouldComplete)
        XCTAssertEqual(plan.draftAfterSubmit, " , \n ")
        XCTAssertNil(plan.alertPresentation)
    }

    func testVocabularySubmissionPlanRejectsSingleDuplicateWithSharedAlert() {
        let plan = RomaDictionaryPolicy.vocabularySubmissionPlan(
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
        let plan = RomaDictionaryPolicy.vocabularySubmissionPlan(
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
        let plan = RomaDictionaryPolicy.vocabularySubmissionPlan(
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
        let plan = RomaDictionaryPolicy.vocabularySubmissionPlan(
            input: "Roma, voice ink, Cursor",
            existingWords: existingWords
        )

        XCTAssertEqual(plan.applying(to: existingWords), ["Voice Ink", "Roma", "Cursor"])
        XCTAssertEqual(plan.updatedWordsIfChanged(from: existingWords), ["Voice Ink", "Roma", "Cursor"])
    }

    func testVocabularySubmissionPlanLeavesStoredListUnchangedWhenNothingIsInserted() {
        let existingWords = ["Voice Ink"]
        let plan = RomaDictionaryPolicy.vocabularySubmissionPlan(
            input: "voice ink",
            existingWords: existingWords
        )

        XCTAssertEqual(plan.applying(to: existingWords), existingWords)
        XCTAssertNil(plan.updatedWordsIfChanged(from: existingWords))
    }

    func testVocabularySubmissionPlanLeavesStoredListUnchangedWhenAlertIsPresent() {
        let existingWords = ["Voice Ink"]
        let plan = RomaVocabularySubmissionPlan(
            wordsToInsert: ["Roma"],
            draftAfterSubmit: "Roma",
            alertPresentation: .vocabulary(message: "Failed to add 'Roma': Disk full")
        )

        XCTAssertEqual(plan.applying(to: existingWords), existingWords)
        XCTAssertNil(plan.updatedWordsIfChanged(from: existingWords))
    }

    func testVocabularyWordsToInsertTrimsAndSkipsExistingAndBatchDuplicates() {
        XCTAssertEqual(
            RomaDictionaryPolicy.vocabularyWordsToInsert(
                [" Voice Ink ", "Roma", "roma", " ", "Cursor"],
                existingWords: ["voice ink"]
            ),
            ["Roma", "Cursor"]
        )
    }

    func testVocabularyBackupRecordsPreserveExistingJSONShape() throws {
        let records = RomaDictionaryPolicy.vocabularyBackupRecords(from: ["Roma", "RomaJustTalk"])
        let data = try JSONEncoder().encode(records)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"word\":\"Roma\""))
        XCTAssertTrue(json.contains("\"word\":\"RomaJustTalk\""))
        XCTAssertEqual(
            try JSONDecoder().decode([RomaVocabularyWordBackup].self, from: data),
            [
                RomaVocabularyWordBackup(word: "Roma"),
                RomaVocabularyWordBackup(word: "RomaJustTalk")
            ]
        )
    }

    func testDictionaryBackupExportPlanPreservesMacOSNilAndRecordShape() {
        XCTAssertEqual(
            dictionaryBackupExportRuntimeEvents(
                for: RomaDictionaryPolicy.dictionaryBackupExportPlan(
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
                for: RomaDictionaryPolicy.dictionaryBackupExportPlan(
                    vocabularyWords: ["Roma", "RomaJustTalk"],
                    wordReplacementRules: [
                        RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk")
                    ]
                )
            ),
            [
                "vocabulary:Roma,RomaJustTalk",
                "replacements:voice ink=RomaJustTalk"
            ]
        )
    }

    func testDictionaryBackupExportPlanKeepsLastDuplicateReplacement() {
        let plan = RomaDictionaryPolicy.dictionaryBackupExportPlan(
            vocabularyWords: [],
            wordReplacementRules: [
                RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk"),
                RomaWordReplacementRule(originalText: "voice ink", replacementText: "roma just talk")
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
            RomaVocabularyWordBackup(word: " Roma "),
            RomaVocabularyWordBackup(word: "roma"),
            RomaVocabularyWordBackup(word: " "),
            RomaVocabularyWordBackup(word: "Cursor")
        ]

        XCTAssertEqual(
            RomaDictionaryPolicy.vocabularyWordsToInsert(
                from: records,
                existingWords: ["voice ink"]
            ),
            ["Roma", "Cursor"]
        )
    }

    func testWordReplacementPlanReturnsNoOpForBlankOriginalOrReplacement() {
        XCTAssertFalse(
            RomaDictionaryPolicy.wordReplacementInsertPlan(
                original: " , ",
                replacement: "roma",
                existingOriginalTexts: []
            ).shouldInsert
        )

        XCTAssertFalse(
            RomaDictionaryPolicy.wordReplacementInsertPlan(
                original: "voice ink",
                replacement: " \n ",
                existingOriginalTexts: []
            ).shouldInsert
        )
    }

    func testWordReplacementDraftSaveabilityUsesInsertPlan() {
        XCTAssertFalse(
            RomaDictionaryPolicy.canSaveWordReplacementDraft(
                original: " , ",
                replacement: "roma"
            )
        )
        XCTAssertFalse(
            RomaDictionaryPolicy.canSaveWordReplacementDraft(
                original: "voice ink",
                replacement: ""
            )
        )
        XCTAssertTrue(
            RomaDictionaryPolicy.canSaveWordReplacementDraft(
                original: "voice ink",
                replacement: "roma"
            )
        )
    }

    func testWordReplacementDraftStateUsesSharedVisibilityAndSaveability() {
        XCTAssertFalse(RomaWordReplacementDraftState().hasDraft)
        XCTAssertTrue(RomaWordReplacementDraftState(original: "voice ink").hasDraft)
        XCTAssertTrue(RomaWordReplacementDraftState(replacement: "Roma").hasDraft)
        XCTAssertFalse(RomaWordReplacementDraftState(original: " , ", replacement: "roma").canSubmit)
        XCTAssertTrue(RomaWordReplacementDraftState(original: "voice ink", replacement: "roma").canSubmit)
    }

    func testWordReplacementDraftStateSubmitsAndClearsAcceptedRule() {
        let submission = RomaWordReplacementDraftState(
            original: " Roma ",
            replacement: " Roma Just Talk "
        )
        .submitting(existingOriginalTexts: [])

        XCTAssertEqual(submission.submittedOriginal, " Roma ")
        XCTAssertEqual(submission.submittedReplacement, " Roma Just Talk ")
        XCTAssertEqual(
            submission.plan.ruleToInsert,
            RomaWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
        )
        XCTAssertEqual(submission.draftStateAfterSubmit, RomaWordReplacementDraftState())
        XCTAssertNil(submission.alertPresentation)
    }

    func testWordReplacementDraftStateKeepsDuplicateDraftAndBuildsSharedAlert() {
        let submission = RomaWordReplacementDraftState(
            original: "Roma",
            replacement: "Roma Just Talk"
        )
        .submitting(existingOriginalTexts: ["roma"])

        XCTAssertNil(submission.plan.ruleToInsert)
        XCTAssertEqual(submission.draftStateAfterSubmit, RomaWordReplacementDraftState(
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
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ]

        let submission = RomaWordReplacementDraftState(
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
        let submission = RomaWordReplacementDraftState(
            original: "Roma",
            replacement: "Roma Just Talk"
        )
        .submitting(existingOriginalTexts: ["roma"])
        var draftState = RomaWordReplacementDraftState()
        var alertPresentation: RomaDictionaryAlertPresentation?

        let returnedSubmission = submission.applyRuntimeState(
            setDraftState: { draftState = $0 },
            setAlertPresentation: { alertPresentation = $0 }
        )

        XCTAssertEqual(returnedSubmission, submission)
        XCTAssertEqual(
            draftState,
            RomaWordReplacementDraftState(original: "Roma", replacement: "Roma Just Talk")
        )
        XCTAssertEqual(
            alertPresentation,
            .wordReplacement(message: "'Roma' already exists in word replacements")
        )
    }

    func testWordReplacementSubmissionPlanAppliesAcceptedRuleToRuntimeState() {
        let plan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
            original: "Roma",
            replacement: "Roma Just Talk",
            existingOriginalTexts: []
        )
        var rules = [RomaWordReplacementRule]()

        plan.applyRuntimeState(currentRules: rules) { rules = $0 }

        XCTAssertEqual(
            rules,
            [RomaWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")]
        )
    }

    func testWordReplacementDraftSubmissionAppliesPersistenceFailureInCore() {
        let submission = RomaWordReplacementDraftState(
            original: "Roma",
            replacement: "Roma Just Talk"
        )
        .submitting(existingOriginalTexts: [])
        var insertedRules = [RomaWordReplacementRule]()

        let returnedSubmission = submission.applyPersistenceRuntimeState { rule in
            insertedRules.append(rule)
            return "Disk full"
        }

        XCTAssertEqual(
            insertedRules,
            [RomaWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")]
        )
        XCTAssertEqual(returnedSubmission.submittedOriginal, "Roma")
        XCTAssertEqual(returnedSubmission.submittedReplacement, "Roma Just Talk")
        XCTAssertEqual(
            returnedSubmission.draftStateAfterSubmit,
            RomaWordReplacementDraftState(original: "Roma", replacement: "Roma Just Talk")
        )
        XCTAssertEqual(
            returnedSubmission.alertPresentation,
            .wordReplacement(message: "Failed to add replacement: Disk full")
        )
    }

    func testWordReplacementEditStateUsesSharedSaveability() {
        XCTAssertFalse(RomaWordReplacementEditState(original: " , ", replacement: "Roma").canSave)
        XCTAssertFalse(RomaWordReplacementEditState(original: "voice ink", replacement: "").canSave)
        XCTAssertTrue(RomaWordReplacementEditState(original: "voice ink", replacement: "RomaJustTalk").canSave)
    }

    func testWordReplacementEditStateSubmitsTrimmedAcceptedRule() {
        let submission = RomaWordReplacementEditState(
            original: " Voice Ink ",
            replacement: " RomaJustTalk "
        )
        .submitting(existingOriginalTexts: ["Roma"])

        XCTAssertEqual(submission.submittedOriginal, " Voice Ink ")
        XCTAssertEqual(submission.submittedReplacement, " RomaJustTalk ")
        XCTAssertTrue(submission.shouldUpdate)
        XCTAssertTrue(submission.shouldComplete)
        XCTAssertEqual(submission.plan.originalText, "Voice Ink")
        XCTAssertEqual(submission.plan.replacementText, "RomaJustTalk")
        XCTAssertNil(submission.alertPresentation)
    }

    func testWordReplacementEditStateRejectsDuplicateWithSharedAlert() {
        let submission = RomaWordReplacementEditState(
            original: "Voice Ink",
            replacement: "RomaJustTalk"
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
            RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk")
        ]

        let submission = RomaWordReplacementEditState(
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
        let plan = RomaDictionaryPolicy.wordReplacementInsertPlan(
            original: "Flow, Voice Ink",
            replacement: "roma",
            existingOriginalTexts: ["quick release, voice ink"]
        )

        XCTAssertFalse(plan.shouldInsert)
        XCTAssertEqual(plan.errorMessage, "'Voice Ink' already exists in word replacements")
    }

    func testWordReplacementPlanTrimsStoredOriginalAndReplacement() {
        let plan = RomaDictionaryPolicy.wordReplacementInsertPlan(
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
        let plan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
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

        let emptyPlan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
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
        let plan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
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
        let plan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
            original: " Roma ",
            replacement: " Roma Just Talk ",
            existingOriginalTexts: []
        )

        XCTAssertEqual(
            plan.ruleToInsert,
            RomaWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
        )
        XCTAssertEqual(plan.originalDraftAfterSubmit, "")
        XCTAssertEqual(plan.replacementDraftAfterSubmit, "")
        XCTAssertNil(plan.alertPresentation)
        XCTAssertTrue(plan.shouldInsert)
        XCTAssertTrue(plan.shouldComplete)
    }

    func testWordReplacementSubmissionPlanAppliesInsertedRuleToStoredList() {
        let existingRules = [
            RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk")
        ]
        let plan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
            original: " Roma ",
            replacement: " Roma Just Talk ",
            existingOriginalTexts: existingRules.map(\.originalText)
        )

        XCTAssertEqual(
            plan.applying(to: existingRules),
            existingRules + [
                RomaWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
            ]
        )
        XCTAssertEqual(
            plan.updatedRulesIfChanged(from: existingRules),
            existingRules + [
                RomaWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk")
            ]
        )
    }

    func testWordReplacementSubmissionPlanLeavesStoredListUnchangedWhenNothingIsInserted() {
        let existingRules = [
            RomaWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ]
        let duplicatePlan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
            original: "Roma",
            replacement: "RJT",
            existingOriginalTexts: existingRules.map(\.originalText)
        )
        let blankPlan = RomaDictionaryPolicy.wordReplacementSubmissionPlan(
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
            RomaWordReplacementRule(originalText: "voice ink", replacementText: "RomaJustTalk")
        ]
        let plan = RomaWordReplacementSubmissionPlan(
            ruleToInsert: RomaWordReplacementRule(originalText: "Roma", replacementText: "Roma Just Talk"),
            originalDraftAfterSubmit: "Roma",
            replacementDraftAfterSubmit: "Roma Just Talk",
            alertPresentation: .wordReplacement(message: "Failed to add replacement: Disk full")
        )

        XCTAssertEqual(plan.applying(to: existingRules), existingRules)
        XCTAssertNil(plan.updatedRulesIfChanged(from: existingRules))
    }

    func testWordReplacementBackupImportPlanPreservesMacOSImportSemantics() {
        let plan = RomaDictionaryPolicy.wordReplacementBackupImportPlan(
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
            [RomaWordReplacementRule(originalText: "Flow, Voice Ink", replacementText: "roma")]
        )
        XCTAssertEqual(plan.skippedInvalidReplacementCount, 2)
    }

    func testDictionaryBackupImportPlanCombinesVocabularyAndReplacementsForMacOSImport() {
        let plan = RomaDictionaryPolicy.dictionaryBackupImportPlan(
            vocabularyWords: [
                RomaVocabularyWordBackup(word: " Roma "),
                RomaVocabularyWordBackup(word: "voice ink"),
                RomaVocabularyWordBackup(word: "roma")
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
        let plan = RomaDictionaryPolicy.dictionaryBackupImportPlan(
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
        let plan = RomaDictionaryPolicy.dictionaryBackupImportPlan(
            vocabularyWords: [
                RomaVocabularyWordBackup(word: "Roma")
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
        for plan: RomaDictionaryBackupExportPlan
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
        for plan: RomaDictionaryBackupImportPlan
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
        let suiteName = "RomaCore.DictionaryPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
