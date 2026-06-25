import Foundation
@testable import VoiceInkCore

final class TranscriptionCleanupPreferencesTests: XCTestCase {
    func testPunctuationModeDisplayNamesMatchMacOSSettingsLabels() {
        XCTAssertEqual(PunctuationCleanupMode.keep.displayName, "Keep")
        XCTAssertEqual(PunctuationCleanupMode.removeAll.displayName, "Remove all")
        XCTAssertEqual(PunctuationCleanupMode.removeTrailingPeriod.displayName, "Remove trailing period")
    }

    func testCleanupPresentationPreservesIOSSettingsCopy() {
        let presentation = VoiceInkTranscriptionCleanupPresentation.iOS

        XCTAssertEqual(presentation.sectionTitle, "Transcription Cleanup")
        XCTAssertEqual(presentation.paragraphBreaksToggleTitle, "Paragraph Breaks")
        XCTAssertNil(presentation.paragraphBreaksHelpText)
        XCTAssertEqual(presentation.punctuationPickerTitle, "Punctuation")
        XCTAssertNil(presentation.punctuationHelpText)
        XCTAssertEqual(presentation.lowercaseToggleTitle, "Lowercase Transcription")
        XCTAssertNil(presentation.lowercaseHelpText)
        XCTAssertEqual(presentation.removeFillerWordsToggleTitle, "Remove Filler Words")
        XCTAssertNil(presentation.removeFillerWordsHelpText)
        XCTAssertEqual(presentation.addFillerWordPlaceholder, "Add filler word")
    }

    func testCleanupPresentationPreservesMacOSSettingsCopy() {
        let presentation = VoiceInkTranscriptionCleanupPresentation.macOS

        XCTAssertEqual(presentation.sectionTitle, "Transcript Formatting")
        XCTAssertEqual(presentation.paragraphBreaksToggleTitle, "Paragraph breaks")
        XCTAssertEqual(
            presentation.paragraphBreaksHelpText,
            "Apply intelligent text formatting to break large block of text into paragraphs."
        )
        XCTAssertEqual(presentation.punctuationPickerTitle, "Punctuation")
        XCTAssertEqual(
            presentation.punctuationHelpText,
            "Keep preserves punctuation as transcribed. Remove all strips punctuation marks from the transcribed text. Remove trailing period only removes a final period from the transcribed text."
        )
        XCTAssertEqual(presentation.lowercaseToggleTitle, "Lowercase output")
        XCTAssertEqual(presentation.lowercaseHelpText, "Convert transcription output to lowercase.")
        XCTAssertEqual(presentation.removeFillerWordsToggleTitle, "Remove filler words")
        XCTAssertEqual(
            presentation.removeFillerWordsHelpText,
            "Automatically remove filler words like 'uh', 'um', 'hmm' from transcriptions."
        )
        XCTAssertEqual(presentation.addFillerWordPlaceholder, "Add filler word")
    }

    func testMacOSCleanupSettingsPresentationPreservesOptionsAndCopy() {
        let presentation = VoiceInkMacOSCleanupSettingsPresentation.macOS

        XCTAssertEqual(presentation.transcriptToggleTitle, "Auto-delete Transcripts")
        XCTAssertEqual(
            presentation.transcriptHelpText,
            "Automatically delete transcript history based on the retention period you set."
        )
        XCTAssertEqual(presentation.transcriptRetentionPickerTitle, "Delete After")
        XCTAssertEqual(
            presentation.transcriptRetentionOptions,
            [
                VoiceInkCleanupRetentionOption(title: "Immediately", value: 0),
                VoiceInkCleanupRetentionOption(title: "1 hour", value: 60),
                VoiceInkCleanupRetentionOption(title: "1 day", value: 24 * 60),
                VoiceInkCleanupRetentionOption(title: "3 days", value: 3 * 24 * 60),
                VoiceInkCleanupRetentionOption(title: "7 days", value: 7 * 24 * 60)
            ]
        )
        XCTAssertEqual(presentation.manualCleanupButtonTitle, "Run Cleanup Now")
        XCTAssertEqual(presentation.transcriptCleanupAlertTitle, "Transcript Cleanup")
        XCTAssertEqual(presentation.transcriptCleanupCompleteMessage, "Cleanup complete.")
        XCTAssertEqual(presentation.audioToggleTitle, "Auto-delete Audio Files")
        XCTAssertEqual(
            presentation.audioHelpText,
            "Automatically delete audio recordings while keeping text transcripts intact."
        )
        XCTAssertEqual(presentation.audioRetentionPickerTitle, "Keep Audio For")
        XCTAssertEqual(
            presentation.audioRetentionOptions,
            [
                VoiceInkCleanupRetentionOption(title: "1 day", value: 1),
                VoiceInkCleanupRetentionOption(title: "3 days", value: 3),
                VoiceInkCleanupRetentionOption(title: "7 days", value: 7),
                VoiceInkCleanupRetentionOption(title: "14 days", value: 14),
                VoiceInkCleanupRetentionOption(title: "30 days", value: 30)
            ]
        )
        XCTAssertEqual(presentation.audioCleanupAnalyzingButtonTitle, "Analyzing...")
        XCTAssertEqual(presentation.audioCleanupAlertTitle, "Audio Cleanup")
        XCTAssertEqual(presentation.cancelButtonTitle, "Cancel")
        XCTAssertEqual(presentation.deleteFilesButtonTitlePrefix, "Delete")
        XCTAssertEqual(presentation.deleteFilesButtonTitleSuffix, "Files")
        XCTAssertEqual(presentation.cleanupCompleteAlertTitle, "Cleanup Complete")
        XCTAssertEqual(presentation.okButtonTitle, "OK")
        XCTAssertEqual(presentation.disclosureSystemImageName, "chevron.right")
    }

    func testMacOSCleanupSettingsPresentationFormatsDynamicMessages() {
        let presentation = VoiceInkMacOSCleanupSettingsPresentation.macOS

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
        let presentation = VoiceInkMacOSCleanupSettingsPresentation.macOS

        XCTAssertEqual(presentation.audioCleanupFileSizeText(512), "1 KB")
        XCTAssertEqual(presentation.audioCleanupFileSizeText(1_024), "1 KB")
        XCTAssertEqual(presentation.audioCleanupFileSizeText(1_048_576), "1 MB")
    }

    func testMacOSCleanupSettingsPolicyHidesAudioSectionWhenTranscriptCleanupIsEnabled() {
        XCTAssertFalse(
            VoiceInkMacOSCleanupSettingsPolicy.shouldShowAudioCleanupSection(
                isTranscriptionCleanupEnabled: true
            )
        )
        XCTAssertTrue(
            VoiceInkMacOSCleanupSettingsPolicy.shouldShowAudioCleanupSection(
                isTranscriptionCleanupEnabled: false
            )
        )
    }

    func testMacOSCleanupSettingsPolicyStopsAudioCleanupWhenTranscriptCleanupStarts() {
        let enabledAudioPlan = VoiceInkMacOSCleanupSettingsPolicy.transcriptCleanupChangePlan(
            isEnabled: true,
            isAudioCleanupEnabled: true
        )
        XCTAssertEqual(enabledAudioPlan.isExpanded, true)
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: enabledAudioPlan), ["stop"])

        let disabledAudioPlan = VoiceInkMacOSCleanupSettingsPolicy.transcriptCleanupChangePlan(
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
        let enabledAudioPlan = VoiceInkMacOSCleanupSettingsPolicy.transcriptCleanupChangePlan(
            isEnabled: false,
            isAudioCleanupEnabled: true
        )
        XCTAssertEqual(enabledAudioPlan.isExpanded, false)
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: enabledAudioPlan), ["start"])

        let disabledAudioPlan = VoiceInkMacOSCleanupSettingsPolicy.transcriptCleanupChangePlan(
            isEnabled: false,
            isAudioCleanupEnabled: false
        )
        XCTAssertEqual(
            disabledAudioPlan,
            VoiceInkMacOSCleanupSettingsTogglePlan(isExpanded: false)
        )
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: disabledAudioPlan), [])
    }

    func testMacOSCleanupSettingsPolicyAudioToggleOnlyPlansExpansion() {
        let enabledPlan = VoiceInkMacOSCleanupSettingsPolicy.audioCleanupChangePlan(isEnabled: true)
        XCTAssertEqual(enabledPlan, VoiceInkMacOSCleanupSettingsTogglePlan(isExpanded: true))
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: enabledPlan), [])

        let disabledPlan = VoiceInkMacOSCleanupSettingsPolicy.audioCleanupChangePlan(isEnabled: false)
        XCTAssertEqual(disabledPlan, VoiceInkMacOSCleanupSettingsTogglePlan(isExpanded: false))
        XCTAssertEqual(macOSCleanupSettingsAudioEvents(for: disabledPlan), [])
    }

    private func macOSCleanupSettingsAudioEvents(
        for plan: VoiceInkMacOSCleanupSettingsTogglePlan
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
        XCTAssertEqual(VoiceInkTranscriptionCleanupConfiguration.disabled.punctuationMode, .keep)
        XCTAssertFalse(VoiceInkTranscriptionCleanupConfiguration.disabled.shouldFormatParagraphs)
        XCTAssertFalse(VoiceInkTranscriptionCleanupConfiguration.disabled.shouldLowercase)
        XCTAssertFalse(VoiceInkTranscriptionCleanupConfiguration.disabled.shouldRemoveFillerWords)
        XCTAssertEqual(VoiceInkTranscriptionCleanupConfiguration.disabled.fillerWords, VoiceInkFillerWords.defaultWords)
    }

    func testCurrentCleanupConfigurationReadsSharedDefaults() {
        withIsolatedDefaults { defaults in
            PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
            defaults.set(true, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
            defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
            defaults.set(true, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
            defaults.set(["um", "like"], forKey: VoiceInkUserDefaultsKey.fillerWords)

            XCTAssertEqual(
                VoiceInkTranscriptionCleanupConfiguration.current(in: defaults),
                VoiceInkTranscriptionCleanupConfiguration(
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
                VoiceInkTranscriptionCleanupConfiguration.current(in: defaults),
                VoiceInkTranscriptionCleanupConfiguration(
                    punctuationMode: .keep,
                    shouldFormatParagraphs: VoiceInkPreferenceDefault.isTextFormattingEnabled,
                    shouldLowercase: VoiceInkPreferenceDefault.lowercaseTranscription,
                    shouldRemoveFillerWords: VoiceInkPreferenceDefault.removeFillerWords,
                    fillerWords: VoiceInkFillerWords.defaultWords
                )
            )
        }
    }

    func testCleanupPreferenceStorageRoundTripsTextPreferences() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertFalse(VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertTrue(VoiceInkTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))

            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)

            XCTAssertFalse(VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertTrue(VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertFalse(VoiceInkTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))
        }
    }

    func testCleanupPreferenceStorageClearRestoresSharedDefaults() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)

            VoiceInkTranscriptionCleanupPreferenceStorage.clearTextPreferences(from: defaults)

            XCTAssertTrue(VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertFalse(VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertTrue(VoiceInkTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))
        }
    }

    func testCleanupSettingsReadCurrentTextPreferences() {
        withIsolatedDefaults { defaults in
            PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)

            XCTAssertEqual(
                VoiceInkTranscriptionCleanupSettings.current(in: defaults),
                VoiceInkTranscriptionCleanupSettings(
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
            let settings = VoiceInkTranscriptionCleanupSettings(
                punctuationMode: .removeAll,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )

            settings.save(to: defaults)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
            XCTAssertTrue(defaults.bool(forKey: PunctuationCleanupMode.legacyRemovePunctuationKey))
            XCTAssertFalse(VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults))
            XCTAssertTrue(VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults))
            XCTAssertFalse(VoiceInkTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults))
        }
    }

    func testCleanupSettingsBuildRuntimeConfigurationWithSeparateFillerWords() {
        let settings = VoiceInkTranscriptionCleanupSettings(
            punctuationMode: .removeTrailingPeriod,
            isTextFormattingEnabled: true,
            lowercaseTranscription: true,
            removeFillerWords: true
        )

        XCTAssertEqual(
            settings.runtimeConfiguration(fillerWords: ["um", "like"]),
            VoiceInkTranscriptionCleanupConfiguration(
                punctuationMode: .removeTrailingPeriod,
                shouldFormatParagraphs: true,
                shouldLowercase: true,
                shouldRemoveFillerWords: true,
                fillerWords: ["um", "like"]
            )
        )
    }

    func testCleanupSettingsBackupPreferencesPreserveMacOSExportShape() {
        let settings = VoiceInkTranscriptionCleanupSettings(
            punctuationMode: .removeAll,
            isTextFormattingEnabled: false,
            lowercaseTranscription: true,
            removeFillerWords: false
        )

        XCTAssertEqual(
            settings.backupPreferences,
            VoiceInkTranscriptionCleanupBackupPreferences(
                isTextFormattingEnabled: false,
                punctuationCleanupMode: .removeAll,
                removePunctuation: true,
                lowercaseTranscription: true
            )
        )
    }

    func testCleanupSettingsBackupImportPlanPrefersModernPunctuationMode() {
        let preferences = VoiceInkTranscriptionCleanupBackupPreferences(
            isTextFormattingEnabled: false,
            punctuationCleanupMode: .removeTrailingPeriod,
            removePunctuation: true,
            lowercaseTranscription: true
        )

        XCTAssertEqual(
            VoiceInkTranscriptionCleanupSettings.backupImportPlan(from: preferences),
            VoiceInkTranscriptionCleanupBackupImportPlan(
                isTextFormattingEnabled: false,
                punctuationCleanupMode: .removeTrailingPeriod,
                lowercaseTranscription: true
            )
        )
    }

    func testCleanupSettingsBackupImportPlanFallsBackToLegacyRemovePunctuation() {
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupSettings.backupImportPlan(
                from: VoiceInkTranscriptionCleanupBackupPreferences(
                    isTextFormattingEnabled: true,
                    punctuationCleanupMode: nil,
                    removePunctuation: true,
                    lowercaseTranscription: false
                )
            ),
            VoiceInkTranscriptionCleanupBackupImportPlan(
                isTextFormattingEnabled: true,
                punctuationCleanupMode: .removeAll,
                lowercaseTranscription: false
            )
        )

        XCTAssertEqual(
            VoiceInkTranscriptionCleanupSettings.backupImportPlan(
                from: VoiceInkTranscriptionCleanupBackupPreferences(
                    isTextFormattingEnabled: nil,
                    punctuationCleanupMode: nil,
                    removePunctuation: false,
                    lowercaseTranscription: nil
                )
            ),
            VoiceInkTranscriptionCleanupBackupImportPlan(
                isTextFormattingEnabled: nil,
                punctuationCleanupMode: .keep,
                lowercaseTranscription: nil
            )
        )

        XCTAssertEqual(
            VoiceInkTranscriptionCleanupSettings.backupImportPlan(
                from: VoiceInkTranscriptionCleanupBackupPreferences(
                    isTextFormattingEnabled: nil,
                    punctuationCleanupMode: nil,
                    removePunctuation: nil,
                    lowercaseTranscription: nil
                )
            ),
            VoiceInkTranscriptionCleanupBackupImportPlan(
                isTextFormattingEnabled: nil,
                punctuationCleanupMode: nil,
                lowercaseTranscription: nil
            )
        )
    }

    func testRemoveTrailingPeriodPreservesEllipsisAndTrailingWhitespace() {
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupPreferences.removeTrailingPeriod(from: "Ship it.  "),
            "Ship it  "
        )
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupPreferences.removeTrailingPeriod(from: "Wait..."),
            "Wait..."
        )
    }

    func testRemovePunctuationDropsApostrophesAndNormalizesInlineWhitespace() {
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupPreferences.removePunctuation(from: "Felix's note: ship, test, release."),
            "Felixs note ship test release"
        )
    }

    func testApplyRunsPunctuationCleanupBeforeLowercasing() {
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupPreferences.apply(
                "Ship, PLEASE.",
                punctuationMode: .removeAll,
                shouldLowercase: true
            ),
            "ship please"
        )
    }

    func testCleanupConfigurationFiltersRawOutputUsingActiveFillerWords() {
        let enabledConfiguration = VoiceInkTranscriptionCleanupConfiguration(
            shouldRemoveFillerWords: true,
            fillerWords: ["um", "like"]
        )
        XCTAssertEqual(
            enabledConfiguration.filterRawOutput("Um, <noise>bad</noise> like ship [music] it."),
            "ship it."
        )

        let disabledConfiguration = VoiceInkTranscriptionCleanupConfiguration(
            shouldRemoveFillerWords: false,
            fillerWords: ["um", "like"]
        )
        XCTAssertEqual(
            disabledConfiguration.filterRawOutput("Um, like ship it."),
            "Um, like ship it."
        )
    }

    func testCleanupConfigurationAppliesTextPreferences() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: .removeTrailingPeriod,
            shouldLowercase: true
        )

        XCTAssertEqual(configuration.applyTextPreferences("SHIP IT."), "ship it")
    }

    func testCleanupConfigurationPreparesFilteredTextForWordReplacement() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration()

        XCTAssertEqual(
            configuration.prepareFilteredTextForWordReplacement(" \n Ship it. \t "),
            "Ship it."
        )
    }

    func testCleanupConfigurationPreparedTextAppliesWordReplacementBeforeTextPreferences() {
        let configuration = VoiceInkTranscriptionCleanupConfiguration(
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
        let configuration = VoiceInkTranscriptionCleanupConfiguration()

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
        let configuration = VoiceInkTranscriptionCleanupConfiguration(shouldFormatParagraphs: true)

        XCTAssertEqual(
            configuration.prepareFilteredTextForWordReplacement(input),
            expected
        )
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.TranscriptionCleanupPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
