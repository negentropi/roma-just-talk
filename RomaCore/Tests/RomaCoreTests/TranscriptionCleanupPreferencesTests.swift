import Foundation
import RomaCore

final class TranscriptionCleanupPreferencesTests: XCTestCase {

    func testMacOSCleanupSettingsPresentationFormatsDynamicMessages() {
        let presentation = RomaMacOSCleanupSettingsPresentation.macOS

        XCTAssertEqual(presentation.audioCleanupButtonTitle(isAnalyzing: false), "Run Cleanup Now")
        XCTAssertEqual(presentation.audioCleanupButtonTitle(isAnalyzing: true), "Analyzing...")
        XCTAssertEqual(presentation.deleteFilesButtonTitle(fileCount: 1), "Delete 1 Files")
        XCTAssertEqual(
            presentation.audioCleanupConfirmationMessage(fileCount: 2, totalSizeText: "12 MB"),
            "This will delete 2 audio files (12 MB)."
        )
        XCTAssertEqual(presentation.noAudioFilesMessage(retentionDays: 1), "No audio files found older than 1 day.")
        XCTAssertEqual(presentation.noAudioFilesMessage(retentionDays: 7), "No audio files found older than 7 days.")
        XCTAssertEqual(
            presentation.audioCleanupResultMessage(deletedCount: 3, errorCount: 0),
            "Deleted 3 audio files."
        )
        XCTAssertEqual(
            presentation.audioCleanupResultMessage(deletedCount: 3, errorCount: 1),
            "Deleted 3 files. Failed: 1."
        )
    }

    func testMacOSCleanupSettingsPresentationFormatsAudioFileSizes() {
        let presentation = RomaMacOSCleanupSettingsPresentation.macOS

        XCTAssertEqual(presentation.audioCleanupFileSizeText(512), "1 KB")
        XCTAssertEqual(presentation.audioCleanupFileSizeText(1_024), "1 KB")
        XCTAssertEqual(presentation.audioCleanupFileSizeText(1_048_576), "1 MB")
    }

    func testMacOSCleanupSettingsPolicyHidesAudioSectionWhenTranscriptCleanupIsEnabled() {
        XCTAssertFalse(
            RomaMacOSCleanupSettingsPolicy.shouldShowAudioCleanupSection(
                isTranscriptionCleanupEnabled: true
            )
        )
        XCTAssertTrue(
            RomaMacOSCleanupSettingsPolicy.shouldShowAudioCleanupSection(
                isTranscriptionCleanupEnabled: false
            )
        )
    }

    func testMacOSCleanupSettingsPolicyStopsAudioCleanupWhenTranscriptCleanupStarts() {
        let enabledAudioPlan = RomaMacOSCleanupSettingsPolicy.transcriptCleanupChangePlan(
            isEnabled: true,
            isAudioCleanupEnabled: true
        )
        XCTAssertEqual(enabledAudioPlan.isExpanded, true)
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: enabledAudioPlan), ["stop"])

        let disabledAudioPlan = RomaMacOSCleanupSettingsPolicy.transcriptCleanupChangePlan(
            isEnabled: true,
            isAudioCleanupEnabled: false
        )
        XCTAssertEqual(disabledAudioPlan.isExpanded, true)
        XCTAssertEqual(
            macOSCleanupSettingsAudioEvents(for: disabledAudioPlan),
            ["stop"]
        )
    }

    func testMacOSCleanupSettingsPolicyRestartsAudioCleanupOnlyWhenStillEnabled() {
        let enabledAudioPlan = RomaMacOSCleanupSettingsPolicy.transcriptCleanupChangePlan(
            isEnabled: false,
            isAudioCleanupEnabled: true
        )
        XCTAssertEqual(enabledAudioPlan.isExpanded, false)
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: enabledAudioPlan), ["start"])

        let disabledAudioPlan = RomaMacOSCleanupSettingsPolicy.transcriptCleanupChangePlan(
            isEnabled: false,
            isAudioCleanupEnabled: false
        )
        XCTAssertEqual(
            disabledAudioPlan,
            RomaMacOSCleanupSettingsTogglePlan(isExpanded: false)
        )
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: disabledAudioPlan), [])
    }

    func testMacOSCleanupSettingsPolicyAudioToggleOnlyPlansExpansion() {
        let enabledPlan = RomaMacOSCleanupSettingsPolicy.audioCleanupChangePlan(isEnabled: true)
        XCTAssertEqual(enabledPlan, RomaMacOSCleanupSettingsTogglePlan(isExpanded: true))
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: enabledPlan), [])

        let disabledPlan = RomaMacOSCleanupSettingsPolicy.audioCleanupChangePlan(isEnabled: false)
        XCTAssertEqual(disabledPlan, RomaMacOSCleanupSettingsTogglePlan(isExpanded: false))
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: disabledPlan), [])
    }

    private func macOSCleanupSettingsAudioEvents(
        for plan: RomaMacOSCleanupSettingsTogglePlan
    ) -> [String] {
        var events: [String] = []
        plan.applyAutomaticAudioRuntimeState(
            start: {
                events.append("start")
            },
            stop: {
                events.append("stop")
            }
        )
        return events
    }

    func testCurrentFallsBackToLegacyRemovePunctuationFlag() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
        }
    }

    func testSelectionFromStoredRawValueUsesValidModeBeforeDefaults() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)

            XCTAssertEqual(
                PunctuationCleanupMode.selection(fromStoredRawValue: "removeTrailingPeriod", in: defaults),
                .removeTrailingPeriod
            )
        }
    }

    func testSelectionFromStoredRawValueFallsBackToLegacyDefaults() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)

            XCTAssertEqual(
                PunctuationCleanupMode.selection(fromStoredRawValue: "unknown", in: defaults),
                .removeAll
            )
        }
    }

    func testSetCurrentWritesNewModeAndLegacyCompatibilityFlag() {
        withIsolatedDefaults { defaults in
            PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
            XCTAssertEqual(defaults.string(forKey: PunctuationCleanupMode.userDefaultsKey), "removeTrailingPeriod")
            XCTAssertFalse(defaults.bool(forKey: PunctuationCleanupMode.legacyRemovePunctuationKey))

            PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
            XCTAssertEqual(defaults.string(forKey: PunctuationCleanupMode.userDefaultsKey), "removeAll")
            XCTAssertTrue(defaults.bool(forKey: PunctuationCleanupMode.legacyRemovePunctuationKey))
        }
    }

    func testClearCurrentRemovesModeAndDisablesLegacyFlag() {
        withIsolatedDefaults { defaults in
            PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
            PunctuationCleanupMode.clearCurrent(in: defaults)

            XCTAssertNil(defaults.string(forKey: PunctuationCleanupMode.userDefaultsKey))
            XCTAssertFalse(defaults.bool(forKey: PunctuationCleanupMode.legacyRemovePunctuationKey))
        }
    }

    func testCleanupConfigurationDefaultsToCurrentNoOpPolicy() {
        XCTAssertEqual(RomaTranscriptionCleanupConfiguration.disabled.punctuationMode, .keep)
        XCTAssertFalse(RomaTranscriptionCleanupConfiguration.disabled.shouldFormatParagraphs)
        XCTAssertFalse(RomaTranscriptionCleanupConfiguration.disabled.shouldLowercase)
        XCTAssertFalse(RomaTranscriptionCleanupConfiguration.disabled.shouldRemoveFillerWords)
        XCTAssertEqual(RomaTranscriptionCleanupConfiguration.disabled.fillerWords, RomaFillerWords.defaultWords)
    }

    func testCurrentCleanupConfigurationReadsSharedDefaults() {
        withIsolatedDefaults { defaults in
            PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
            defaults.set(true, forKey: RomaUserDefaultsKey.isTextFormattingEnabled)
            defaults.set(true, forKey: RomaUserDefaultsKey.lowercaseTranscription)
            defaults.set(true, forKey: RomaUserDefaultsKey.removeFillerWords)
            defaults.set(["um", "like"], forKey: RomaUserDefaultsKey.fillerWords)

            XCTAssertEqual(
                RomaTranscriptionCleanupConfiguration.current(in: defaults),
                RomaTranscriptionCleanupConfiguration(
                    punctuationMode: .removeTrailingPeriod,
                    shouldFormatParagraphs: true,
                    shouldLowercase: true,
                    shouldRemoveFillerWords: true,
                    fillerWords: ["um", "like"]
                )
            )
        }
    }

    func testCurrentCleanupConfigurationUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                RomaTranscriptionCleanupConfiguration.current(in: defaults),
                RomaTranscriptionCleanupConfiguration(
                    punctuationMode: .keep,
                    shouldFormatParagraphs: RomaPreferenceDefault.isTextFormattingEnabled,
                    shouldLowercase: RomaPreferenceDefault.lowercaseTranscription,
                    shouldRemoveFillerWords: RomaPreferenceDefault.removeFillerWords,
                    fillerWords: RomaFillerWords.defaultWords
                )
            )
        }
    }

    func testCleanupPreferenceStorageRoundTripsTextPreferences() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(RomaTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertFalse(RomaTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertTrue(RomaTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))

            RomaTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)

            XCTAssertFalse(RomaTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertTrue(RomaTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertFalse(RomaTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))
        }
    }

    func testCleanupPreferenceStorageClearRestoresSharedDefaults() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)

            RomaTranscriptionCleanupPreferenceStorage.clearTextPreferences(from: defaults)

            XCTAssertTrue(RomaTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertFalse(RomaTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertTrue(RomaTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))
        }
    }

    func testCleanupSettingsReadCurrentTextPreferences() {
        withIsolatedDefaults { defaults in
            PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)

            XCTAssertEqual(
                RomaTranscriptionCleanupSettings.current(in: defaults),
                RomaTranscriptionCleanupSettings(
                    punctuationMode: .removeTrailingPeriod,
                    isTextFormattingEnabled: false,
                    lowercaseTranscription: true,
                    removeFillerWords: false
                )
            )
        }
    }

    func testCleanupSettingsSaveWritesTextPreferencesAndLegacyPunctuationFlag() {
        withIsolatedDefaults { defaults in
            let settings = RomaTranscriptionCleanupSettings(
                punctuationMode: .removeAll,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )

            settings.save(to: defaults)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
            XCTAssertTrue(defaults.bool(forKey: PunctuationCleanupMode.legacyRemovePunctuationKey))
            XCTAssertFalse(RomaTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertTrue(RomaTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertFalse(RomaTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))
        }
    }

    func testCleanupSettingsUpdateHelperChangesOneFieldAndPreservesOthers() {
        let settings = RomaTranscriptionCleanupSettings(
            punctuationMode: .removeTrailingPeriod,
            isTextFormattingEnabled: true,
            lowercaseTranscription: false,
            removeFillerWords: true
        )

        let updatedSettings = settings.updating(\.lowercaseTranscription, to: true)

        XCTAssertEqual(settings.lowercaseTranscription, false)
        XCTAssertEqual(
            updatedSettings,
            RomaTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: true,
                lowercaseTranscription: true,
                removeFillerWords: true
            )
        )
    }

    func testCleanupSettingsChangedValueSaveWritesOnlyChangedPreferences() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            RomaTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)

            let previousSettings = RomaTranscriptionCleanupSettings(
                punctuationMode: .keep,
                isTextFormattingEnabled: true,
                lowercaseTranscription: false,
                removeFillerWords: true
            )
            let updatedSettings = previousSettings.updating(\.punctuationMode, to: .removeAll)

            updatedSettings.saveChangedValues(from: previousSettings, to: defaults)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
            XCTAssertTrue(defaults.bool(forKey: PunctuationCleanupMode.legacyRemovePunctuationKey))
            XCTAssertFalse(RomaTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertTrue(RomaTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertFalse(RomaTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))
        }
    }

    func testCleanupSettingsBuildRuntimeConfigurationWithSeparateFillerWords() {
        let settings = RomaTranscriptionCleanupSettings(
            punctuationMode: .removeTrailingPeriod,
            isTextFormattingEnabled: true,
            lowercaseTranscription: true,
            removeFillerWords: true
        )

        XCTAssertEqual(
            settings.runtimeConfiguration(fillerWords: ["um", "like"]),
            RomaTranscriptionCleanupConfiguration(
                punctuationMode: .removeTrailingPeriod,
                shouldFormatParagraphs: true,
                shouldLowercase: true,
                shouldRemoveFillerWords: true,
                fillerWords: ["um", "like"]
            )
        )
    }

    func testCleanupSettingsBackupPreferencesPreserveMacOSExportShape() {
        let settings = RomaTranscriptionCleanupSettings(
            punctuationMode: .removeAll,
            isTextFormattingEnabled: false,
            lowercaseTranscription: true,
            removeFillerWords: false
        )

        XCTAssertEqual(
            settings.backupPreferences,
            RomaTranscriptionCleanupBackupPreferences(
                isTextFormattingEnabled: false,
                punctuationCleanupMode: .removeAll,
                removePunctuation: true,
                lowercaseTranscription: true
            )
        )
    }

    func testCleanupSettingsBackupImportPlanPrefersModernPunctuationMode() {
        let preferences = RomaTranscriptionCleanupBackupPreferences(
            isTextFormattingEnabled: false,
            punctuationCleanupMode: .removeTrailingPeriod,
            removePunctuation: true,
            lowercaseTranscription: true
        )

        XCTAssertEqual(
            RomaTranscriptionCleanupSettings.backupImportPlan(from: preferences),
            RomaTranscriptionCleanupBackupImportPlan(
                isTextFormattingEnabled: false,
                punctuationCleanupMode: .removeTrailingPeriod,
                lowercaseTranscription: true
            )
        )
    }

    func testCleanupSettingsBackupImportPlanFallsBackToLegacyRemovePunctuation() {
        XCTAssertEqual(
            RomaTranscriptionCleanupSettings.backupImportPlan(
                from: RomaTranscriptionCleanupBackupPreferences(
                    isTextFormattingEnabled: true,
                    punctuationCleanupMode: nil,
                    removePunctuation: true,
                    lowercaseTranscription: false
                )
            ),
            RomaTranscriptionCleanupBackupImportPlan(
                isTextFormattingEnabled: true,
                punctuationCleanupMode: .removeAll,
                lowercaseTranscription: false
            )
        )

        XCTAssertEqual(
            RomaTranscriptionCleanupSettings.backupImportPlan(
                from: RomaTranscriptionCleanupBackupPreferences(
                    isTextFormattingEnabled: nil,
                    punctuationCleanupMode: nil,
                    removePunctuation: false,
                    lowercaseTranscription: nil
                )
            ),
            RomaTranscriptionCleanupBackupImportPlan(
                isTextFormattingEnabled: nil,
                punctuationCleanupMode: .keep,
                lowercaseTranscription: nil
            )
        )

        XCTAssertEqual(
            RomaTranscriptionCleanupSettings.backupImportPlan(
                from: RomaTranscriptionCleanupBackupPreferences(
                    isTextFormattingEnabled: nil,
                    punctuationCleanupMode: nil,
                    removePunctuation: nil,
                    lowercaseTranscription: nil
                )
            ),
            RomaTranscriptionCleanupBackupImportPlan(
                isTextFormattingEnabled: nil,
                punctuationCleanupMode: nil,
                lowercaseTranscription: nil
            )
        )
    }

    func testRemoveTrailingPeriodPreservesEllipsisAndTrailingWhitespace() {
        XCTAssertEqual(
            RomaTranscriptionCleanupPreferences.removeTrailingPeriod(from: "Ship it.  "),
            "Ship it  "
        )
        XCTAssertEqual(
            RomaTranscriptionCleanupPreferences.removeTrailingPeriod(from: "Wait..."),
            "Wait..."
        )
    }

    func testRemovePunctuationDropsApostrophesAndNormalizesInlineWhitespace() {
        XCTAssertEqual(
            RomaTranscriptionCleanupPreferences.removePunctuation(from: "Felix's note: ship, test, release."),
            "Felixs note ship test release"
        )
    }

    func testApplyRunsPunctuationCleanupBeforeLowercasing() {
        XCTAssertEqual(
            RomaTranscriptionCleanupPreferences.apply(
                "Ship, PLEASE.",
                punctuationMode: .removeAll,
                shouldLowercase: true
            ),
            "ship please"
        )
    }

    func testCleanupConfigurationFiltersRawOutputUsingActiveFillerWords() {
        let enabledConfiguration = RomaTranscriptionCleanupConfiguration(
            shouldRemoveFillerWords: true,
            fillerWords: ["um", "like"]
        )
        XCTAssertEqual(
            enabledConfiguration.filterRawOutput("Um, <noise>bad</noise> like ship [music] it."),
            "ship it."
        )

        let disabledConfiguration = RomaTranscriptionCleanupConfiguration(
            shouldRemoveFillerWords: false,
            fillerWords: ["um", "like"]
        )
        XCTAssertEqual(
            disabledConfiguration.filterRawOutput("Um, like ship it."),
            "Um, like ship it."
        )
    }

    func testDefaultFillerWordsMatchMacOSCleanupDefaults() {
        XCTAssertEqual(
            RomaTranscriptionOutputFilter.defaultFillerWords,
            RomaFillerWords.defaultWords
        )
    }

    func testFilterRemovesTagBlocksAndBracketedHallucinations() {
        XCTAssertEqual(
            RomaTranscriptionOutputFilter.filter("Hello [music] <noise>discard</noise> world"),
            "Hello world"
        )
    }

    func testFilterCanRemoveConfiguredFillerWordsCaseInsensitively() {
        XCTAssertEqual(
            RomaTranscriptionOutputFilter.filter("Um, this is LIKE ready.", fillerWords: ["um", "like"]),
            "this is ready."
        )
    }

    func testDefaultWhitespacePolicyCollapsesAllRunsForMacOSOutputFilterCompatibility() {
        XCTAssertEqual(
            RomaTranscriptionOutputFilter.filter("hello\n\nworld"),
            "hello world"
        )
    }

    func testPreserveParagraphsPolicyKeepsParagraphBreaksForRunProcessor() {
        XCTAssertEqual(
            RomaTranscriptionOutputFilter.filter(
                "hello\n\n\nworld",
                whitespacePolicy: .preserveParagraphs
            ),
            "hello\n\n\nworld"
        )
    }

    func testCleanupConfigurationAppliesTextPreferences() {
        let configuration = RomaTranscriptionCleanupConfiguration(
            punctuationMode: .removeTrailingPeriod,
            shouldLowercase: true
        )

        XCTAssertEqual(configuration.applyTextPreferences("SHIP IT."), "ship it")
    }

    func testCleanupConfigurationPreparesFilteredTextForWordReplacement() {
        let configuration = RomaTranscriptionCleanupConfiguration()

        XCTAssertEqual(
            configuration.prepareFilteredTextForWordReplacement(" \n Ship it. \t "),
            "Ship it."
        )
    }

    func testCleanupConfigurationPreparedTextAppliesWordReplacementBeforeTextPreferences() {
        let configuration = RomaTranscriptionCleanupConfiguration(
            punctuationMode: .removeAll,
            shouldLowercase: true
        )

        let preparedText = configuration.prepareFilteredText("Ship, Roma.") { text in
            text.replacingOccurrences(of: "Roma", with: "Just Talk")
        }

        XCTAssertEqual(preparedText.textForWordReplacement, "Ship, Roma.")
        XCTAssertEqual(preparedText.wordReplacedText, "Ship, Just Talk.")
        XCTAssertEqual(preparedText.cleanedText, "ship just talk")
    }

    func testCleanupConfigurationPreparedTextCanNormalizeParagraphSpacingBeforeFormatting() {
        let configuration = RomaTranscriptionCleanupConfiguration()

        let preparedText = configuration.prepareFilteredText(
            " hello\n\n\nworld ",
            normalizeParagraphSpacingBeforeFormatting: true
        )

        XCTAssertEqual(preparedText.textForWordReplacement, "hello\n\nworld")
        XCTAssertEqual(preparedText.wordReplacedText, "hello\n\nworld")
        XCTAssertEqual(preparedText.cleanedText, "hello\n\nworld")
    }

    func testCleanupConfigurationFormatsPreparedFilteredTextWhenEnabled() {
        let sentence = "This sentence has many ordinary English words that should count clearly in tokenizer."
        let input = Array(repeating: sentence, count: 5).joined(separator: " ")
        let firstParagraph = Array(repeating: sentence, count: 4).joined(separator: " ")
        let expected = "\(firstParagraph)\n\n\(sentence)"
        let configuration = RomaTranscriptionCleanupConfiguration(shouldFormatParagraphs: true)

        XCTAssertEqual(
            configuration.prepareFilteredTextForWordReplacement(input),
            expected
        )
    }

    func testTranscriptParagraphFormatterReturnsEmptyForWhitespaceOnlyInput() {
        XCTAssertEqual(RomaTranscriptParagraphFormatter.format(" \n\t "), "")
    }

    func testTranscriptParagraphFormatterTrimsAndKeepsShortTextInOneParagraph() {
        XCTAssertEqual(
            RomaTranscriptParagraphFormatter.format("  This is one sentence. This is another sentence.  "),
            "This is one sentence. This is another sentence."
        )
    }

    func testTranscriptParagraphFormatterSplitsAfterFourSignificantSentencesWhenChunkHitsWordTarget() {
        let sentence = "This sentence has many ordinary English words that should count clearly in tokenizer."
        let input = Array(repeating: sentence, count: 5).joined(separator: " ")
        let firstParagraph = Array(repeating: sentence, count: 4).joined(separator: " ")
        let expected = "\(firstParagraph)\n\n\(sentence)"

        XCTAssertEqual(RomaTranscriptParagraphFormatter.format(input), expected)
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "RomaCore.TranscriptionCleanupPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
