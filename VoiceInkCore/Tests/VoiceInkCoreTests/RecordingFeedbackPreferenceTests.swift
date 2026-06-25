import Foundation
@testable import VoiceInkCore

final class RecordingFeedbackPreferenceTests: XCTestCase {
    func testBuiltInRecordingSoundsPreserveCatalogNamesAndExtensions() {
        XCTAssertEqual(
            VoiceInkBuiltInRecordingSound.allCases.map(\.rawValue),
            ["sound1", "sound2", "sound3", "sound4", "sound5", "sound6", "sound7"]
        )
        XCTAssertEqual(VoiceInkBuiltInRecordingSound.sound1.displayName, "Sound 1")
        XCTAssertEqual(VoiceInkBuiltInRecordingSound.sound7.displayName, "Sound 7")
        XCTAssertEqual(VoiceInkBuiltInRecordingSound.sound1.fileExtension, "wav")
        XCTAssertEqual(VoiceInkBuiltInRecordingSound.sound4.fileExtension, "wav")
        XCTAssertEqual(VoiceInkBuiltInRecordingSound.sound5.fileExtension, "mp3")
        XCTAssertEqual(VoiceInkBuiltInRecordingSound.sound6.fileExtension, "mp3")
        XCTAssertEqual(VoiceInkBuiltInRecordingSound.sound7.fileExtension, "wav")
    }

    func testCustomSoundTypePreservesExistingMacOSStorageKeys() {
        XCTAssertEqual(VoiceInkCustomSoundType.start.displayName, "Start")
        XCTAssertEqual(VoiceInkCustomSoundType.start.isUsingKey, "isUsingCustomStartSound")
        XCTAssertEqual(VoiceInkCustomSoundType.start.filenameKey, "customStartSoundFilename")
        XCTAssertEqual(VoiceInkCustomSoundType.start.builtInSoundKey, "selectedStartBuiltInSound")
        XCTAssertEqual(VoiceInkCustomSoundType.start.standardName, "CustomStartSound")
        XCTAssertEqual(VoiceInkCustomSoundType.start.defaultBuiltInSound, .sound1)
        XCTAssertEqual(VoiceInkCustomSoundType.start.recordingSoundCue, .start)

        XCTAssertEqual(VoiceInkCustomSoundType.stop.displayName, "Stop")
        XCTAssertEqual(VoiceInkCustomSoundType.stop.isUsingKey, "isUsingCustomStopSound")
        XCTAssertEqual(VoiceInkCustomSoundType.stop.filenameKey, "customStopSoundFilename")
        XCTAssertEqual(VoiceInkCustomSoundType.stop.builtInSoundKey, "selectedStopBuiltInSound")
        XCTAssertEqual(VoiceInkCustomSoundType.stop.standardName, "CustomStopSound")
        XCTAssertEqual(VoiceInkCustomSoundType.stop.defaultBuiltInSound, .sound2)
        XCTAssertEqual(VoiceInkCustomSoundType.stop.recordingSoundCue, .stop)
    }

    func testCustomSoundSettingsPresentationPreservesMacOSCopyAndActions() {
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.label(for: .start), "Start Sound")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.label(for: .stop), "Stop Sound")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.pickerTitle, "Sound")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.customFallbackTitle, "Custom")
        XCTAssertEqual(
            VoiceInkCustomSoundSettingsPresentation.customMenuTitle(filename: "CustomStartSound.wav"),
            "Custom: CustomStartSound.wav"
        )
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.customMenuTitle(filename: nil), "Custom: Custom")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.selectSoundHelpText, "Select sound")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.testButtonHelpText, "Test")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.chooseButtonHelpText, "Choose")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.resetButtonHelpText, "Reset")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.testButtonSystemImageName, "play.fill")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.chooseButtonSystemImageName, "folder")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.resetButtonSystemImageName, "arrow.uturn.backward")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.openPanelTitle(for: .start), "Choose Start Sound")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.openPanelTitle(for: .stop), "Choose Stop Sound")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.openPanelMessage, "Select an audio file")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.invalidAudioAlertTitle, "Invalid Audio File")
        XCTAssertEqual(VoiceInkCustomSoundSettingsPresentation.alertDismissButtonTitle, "OK")

        XCTAssertEqual(VoiceInkCustomSoundMenuSelection.builtIn(.sound1), .builtIn(.sound1))
        XCTAssertFalse(
            VoiceInkCustomSoundMenuSelection.builtIn(.sound1) == VoiceInkCustomSoundMenuSelection.custom
        )
    }

    func testRecordingSoundPlaybackPolicyPreservesMacOSSlotsVolumesAndFallbacks() {
        XCTAssertEqual(
            VoiceInkRecordingSoundPlaybackPolicy.setupSlots,
            [.defaultStart, .defaultStop, .defaultEsc, .customStart, .customStop]
        )

        XCTAssertEqual(VoiceInkRecordingSoundPlayerSlot.defaultStart.volume, 0.4)
        XCTAssertEqual(VoiceInkRecordingSoundPlayerSlot.defaultStop.volume, 0.4)
        XCTAssertEqual(VoiceInkRecordingSoundPlayerSlot.customStart.volume, 0.4)
        XCTAssertEqual(VoiceInkRecordingSoundPlayerSlot.customStop.volume, 0.4)
        XCTAssertEqual(VoiceInkRecordingSoundPlayerSlot.defaultEsc.volume, 0.3)

        XCTAssertEqual(
            VoiceInkRecordingSoundPlaybackPolicy.playbackSlots(for: .start),
            [.customStart, .defaultStart]
        )
        XCTAssertEqual(
            VoiceInkRecordingSoundPlaybackPolicy.playbackSlots(for: .stop),
            [.customStop, .defaultStop]
        )
        XCTAssertEqual(
            VoiceInkRecordingSoundPlaybackPolicy.playbackSlots(for: .esc),
            [.defaultEsc]
        )
    }

    func testCustomSoundPreferencePreservesDefaultsAndNotificationName() {
        XCTAssertEqual(VoiceInkCustomSoundPreference.customSoundsRelativeDirectory, "VoiceInk/CustomSounds")
        XCTAssertEqual(VoiceInkCustomSoundPreference.changedNotificationName, "CustomSoundsChanged")
        XCTAssertEqual(VoiceInkCustomSoundPreference.maxDuration, 3.0)
        XCTAssertEqual(
            VoiceInkCustomSoundPreference.registeredDefaults[VoiceInkCustomSoundType.start.builtInSoundKey] as? String,
            Optional("sound1")
        )
        XCTAssertEqual(
            VoiceInkCustomSoundPreference.registeredDefaults[VoiceInkCustomSoundType.stop.builtInSoundKey] as? String,
            Optional("sound2")
        )
    }

    func testCustomSoundPreferenceReadsAndSavesSelectionState() {
        withTemporaryDefaults { defaults in
            XCTAssertFalse(VoiceInkCustomSoundPreference.isUsingCustomSound(for: .start, from: defaults))
            XCTAssertNil(VoiceInkCustomSoundPreference.customFilename(for: .start, from: defaults))
            XCTAssertEqual(VoiceInkCustomSoundPreference.selectedBuiltInSound(for: .start, from: defaults), .sound1)

            VoiceInkCustomSoundPreference.saveIsUsingCustomSound(true, for: .start, to: defaults)
            VoiceInkCustomSoundPreference.saveCustomFilename("CustomStartSound.wav", for: .start, to: defaults)
            VoiceInkCustomSoundPreference.saveSelectedBuiltInSound(.sound5, for: .start, to: defaults)

            XCTAssertTrue(VoiceInkCustomSoundPreference.isUsingCustomSound(for: .start, from: defaults))
            XCTAssertEqual(
                VoiceInkCustomSoundPreference.customFilename(for: .start, from: defaults),
                Optional("CustomStartSound.wav")
            )
            XCTAssertEqual(VoiceInkCustomSoundPreference.selectedBuiltInSound(for: .start, from: defaults), .sound5)
            XCTAssertEqual(
                VoiceInkCustomSoundPreference.selectionState(for: .start, from: defaults),
                VoiceInkCustomSoundSelectionState(
                    type: .start,
                    isUsingCustomSound: true,
                    selectedBuiltInSound: .sound5,
                    customFilename: "CustomStartSound.wav"
                )
            )

            VoiceInkCustomSoundPreference.saveCustomFilename(nil, for: .start, to: defaults)

            XCTAssertNil(VoiceInkCustomSoundPreference.customFilename(for: .start, from: defaults))
        }
    }

    func testCustomSoundSelectionStateOwnsMenuAndTransitionPolicy() {
        let directory = URL(fileURLWithPath: "/tmp/VoiceInk/CustomSounds", isDirectory: true)
        let state = VoiceInkCustomSoundSelectionState(
            type: .start,
            isUsingCustomSound: false,
            selectedBuiltInSound: .sound3,
            customFilename: "CustomStartSound.wav"
        )

        XCTAssertEqual(state.menuSelection, .builtIn(.sound3))
        XCTAssertFalse(state.isDefaultSelection)
        XCTAssertNil(state.customSoundURL(in: directory))
        XCTAssertEqual(
            state.storedCustomSoundURL(in: directory)?.path,
            "/tmp/VoiceInk/CustomSounds/CustomStartSound.wav"
        )

        XCTAssertEqual(
            state.selectingBuiltInSound(.sound5),
            VoiceInkCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: false,
                selectedBuiltInSound: .sound5,
                customFilename: "CustomStartSound.wav"
            )
        )
        XCTAssertEqual(
            state.usingExistingCustomSound(),
            VoiceInkCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: true,
                selectedBuiltInSound: .sound3,
                customFilename: "CustomStartSound.wav"
            )
        )
        XCTAssertEqual(
            state.settingCustomFilename("CustomStartSound.aiff"),
            VoiceInkCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: true,
                selectedBuiltInSound: .sound3,
                customFilename: "CustomStartSound.aiff"
            )
        )
        XCTAssertEqual(
            state.resettingToDefault(),
            VoiceInkCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: false,
                selectedBuiltInSound: .sound1,
                customFilename: nil
            )
        )

        let missingCustomFile = VoiceInkCustomSoundSelectionState(
            type: .stop,
            isUsingCustomSound: false,
            selectedBuiltInSound: .sound2,
            customFilename: nil
        )
        XCTAssertTrue(missingCustomFile.isDefaultSelection)
        XCTAssertNil(missingCustomFile.usingExistingCustomSound())
    }

    func testCustomSoundPreferenceRepairsInvalidBuiltInSelectionToDefault() {
        withTemporaryDefaults { defaults in
            defaults.set("bad", forKey: VoiceInkCustomSoundType.stop.builtInSoundKey)

            XCTAssertEqual(VoiceInkCustomSoundPreference.selectedBuiltInSound(for: .stop, from: defaults), .sound2)
        }
    }

    func testCustomSoundPreferencePlansDefaultSelectionAndCopyFilename() {
        XCTAssertTrue(VoiceInkCustomSoundPreference.isDefaultSelection(
            for: .start,
            isUsingCustomSound: false,
            selectedBuiltInSound: .sound1
        ))
        XCTAssertFalse(VoiceInkCustomSoundPreference.isDefaultSelection(
            for: .start,
            isUsingCustomSound: true,
            selectedBuiltInSound: .sound1
        ))
        XCTAssertFalse(VoiceInkCustomSoundPreference.isDefaultSelection(
            for: .start,
            isUsingCustomSound: false,
            selectedBuiltInSound: .sound3
        ))
        XCTAssertEqual(
            VoiceInkCustomSoundPreference.copiedFilename(sourceExtension: "aiff", for: .stop),
            "CustomStopSound.aiff"
        )
    }

    func testCustomSoundPreferenceBuildsCustomSoundURLs() {
        let directory = URL(fileURLWithPath: "/tmp/VoiceInk/CustomSounds", isDirectory: true)

        XCTAssertEqual(
            VoiceInkCustomSoundPreference.customSoundURL(
                isUsingCustomSound: true,
                filename: "CustomStartSound.wav",
                in: directory
            )?.path,
            "/tmp/VoiceInk/CustomSounds/CustomStartSound.wav"
        )
        XCTAssertNil(VoiceInkCustomSoundPreference.customSoundURL(
            isUsingCustomSound: false,
            filename: "CustomStartSound.wav",
            in: directory
        ))
        XCTAssertNil(VoiceInkCustomSoundPreference.storedCustomSoundURL(filename: nil, in: directory))
        XCTAssertNil(VoiceInkCustomSoundPreference.storedCustomSoundURL(filename: "CustomStartSound.wav", in: nil))
    }

    func testCustomSoundPreferencePlansCopyActions() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.CustomSoundCopyPlanTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.deletingLastPathComponent().appendingPathComponent("start.aiff")

        var plan = VoiceInkCustomSoundPreference.copyPlan(
            sourceURL: sourceURL,
            customSoundsDirectory: directory,
            for: .start
        )
        XCTAssertEqual(plan.filename, "CustomStartSound.aiff")
        XCTAssertEqual(plan.destinationURL, directory.appendingPathComponent("CustomStartSound.aiff"))
        var runtimeResult = customSoundCopyRuntimeResult(for: plan)
        XCTAssertEqual(runtimeResult.result, .success("CustomStartSound.aiff"))
        XCTAssertEqual(runtimeResult.events, ["copy:CustomStartSound.aiff"])

        try? Data("existing".utf8).write(to: plan.destinationURL)
        plan = VoiceInkCustomSoundPreference.copyPlan(
            sourceURL: sourceURL,
            customSoundsDirectory: directory,
            for: .start
        )
        runtimeResult = customSoundCopyRuntimeResult(for: plan)
        XCTAssertEqual(runtimeResult.result, .success("CustomStartSound.aiff"))
        XCTAssertEqual(runtimeResult.events, ["remove:CustomStartSound.aiff", "copy:CustomStartSound.aiff"])

        let destinationURL = directory.appendingPathComponent("CustomStartSound.aiff")
        plan = VoiceInkCustomSoundPreference.copyPlan(
            sourceURL: destinationURL,
            customSoundsDirectory: directory,
            for: .start
        )
        runtimeResult = customSoundCopyRuntimeResult(for: plan)
        XCTAssertEqual(runtimeResult.result, .success("CustomStartSound.aiff"))
        XCTAssertEqual(runtimeResult.events, [])

        plan = VoiceInkCustomSoundPreference.copyPlan(
            sourceURL: sourceURL,
            customSoundsDirectory: directory,
            for: .stop
        )
        runtimeResult = customSoundCopyRuntimeResult(for: plan, copyThrows: true)
        XCTAssertEqual(runtimeResult.result, .failure(.fileCopyFailed))
        XCTAssertEqual(runtimeResult.events, ["copy:CustomStopSound.aiff"])
    }

    func testCustomSoundValidationPreservesMacOSErrorPolicy() {
        XCTAssertEqual(
            VoiceInkCustomSoundPreference.preflightValidationError(fileExists: false, duration: 1.0),
            Optional(.fileNotFound)
        )
        XCTAssertEqual(
            VoiceInkCustomSoundPreference.preflightValidationError(fileExists: true, duration: 0.0),
            Optional(.invalidAudioFile)
        )
        XCTAssertEqual(
            VoiceInkCustomSoundPreference.preflightValidationError(fileExists: true, duration: .infinity),
            Optional(.invalidAudioFile)
        )
        XCTAssertEqual(
            VoiceInkCustomSoundPreference.preflightValidationError(fileExists: true, duration: 3.1),
            Optional(.durationTooLong(duration: 3.1, maxDuration: 3.0))
        )
        XCTAssertNil(
            VoiceInkCustomSoundPreference.preflightValidationError(fileExists: true, duration: 3.0)
        )
    }

    func testCustomSoundErrorMessagesPreserveExistingCopy() {
        XCTAssertEqual(VoiceInkCustomSoundError.fileNotFound.errorDescription, Optional("Audio file not found"))
        XCTAssertEqual(VoiceInkCustomSoundError.invalidAudioFile.errorDescription, Optional("Invalid audio file format"))
        XCTAssertEqual(
            VoiceInkCustomSoundError.durationTooLong(duration: 3.4, maxDuration: 3.0).errorDescription,
            Optional("Audio file is 3.4 seconds long. Please use an audio file that is 3 seconds or shorter for start and stop sounds.")
        )
        XCTAssertEqual(
            VoiceInkCustomSoundError.directoryCreationFailed.errorDescription,
            Optional("Failed to create custom sounds directory")
        )
        XCTAssertEqual(VoiceInkCustomSoundError.fileCopyFailed.errorDescription, Optional("Failed to copy audio file"))
    }

    func testSystemMuteModePreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(VoiceInkSystemMuteMode.automatic.rawValue, "auto")
        XCTAssertEqual(VoiceInkSystemMuteMode.always.rawValue, "always")
        XCTAssertEqual(VoiceInkSystemMuteMode.never.rawValue, "never")
        XCTAssertEqual(VoiceInkSystemMuteMode.automatic.displayName, "Auto")
        XCTAssertEqual(VoiceInkSystemMuteMode.always.displayName, "On")
        XCTAssertEqual(VoiceInkSystemMuteMode.never.displayName, "Off")
    }

    func testRegisteredDefaultsPreserveMacOSStorageKeys() {
        XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteModeKey, "systemMuteMode")
        XCTAssertEqual(VoiceInkRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey, "isSystemMuteEnabled")
        XCTAssertEqual(VoiceInkRecordingFeedbackPreference.audioResumptionDelayKey, "audioResumptionDelay")
        XCTAssertEqual(VoiceInkRecordingFeedbackPreference.isPauseMediaEnabledKey, "isPauseMediaEnabled")
        XCTAssertEqual(VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey, "isSoundFeedbackEnabled")
        XCTAssertEqual(VoiceInkRecordingFeedbackPreference.experimentalFeaturesEnabledKey, "isExperimentalFeaturesEnabled")
        XCTAssertEqual(VoiceInkRecordingFeedbackPreference.defaultSystemMuteScheduleDelayNanoseconds, 250_000_000)
        XCTAssertEqual(VoiceInkRecordingFeedbackPreference.defaultPauseMediaCommandDelayNanoseconds, 50_000_000)
        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.registeredDefaults[VoiceInkRecordingFeedbackPreference.systemMuteModeKey] as? String,
            "auto"
        )
        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.registeredDefaults[VoiceInkRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey] as? Bool,
            true
        )
        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.registeredDefaults[VoiceInkRecordingFeedbackPreference.audioResumptionDelayKey] as? TimeInterval,
            0.0
        )
        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.registeredDefaults[VoiceInkRecordingFeedbackPreference.isPauseMediaEnabledKey] as? Bool,
            false
        )
        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.registeredDefaults[VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey] as? Bool,
            false
        )
    }

    func testMacOSRecordingFeedbackSettingsPresentationPreservesCopyAndDelayOptions() {
        let presentation = VoiceInkRecordingFeedbackPreference.macOSSettingsPresentation

        XCTAssertEqual(presentation.sectionTitle, "Recording Feedback")
        XCTAssertEqual(presentation.soundFeedbackLabel, "Sound Feedback")
        XCTAssertEqual(presentation.systemMuteModeLabel, "Mute Audio While Recording")
        XCTAssertEqual(presentation.audioResumptionDelayLabel, "Audio Resume Delay")
        XCTAssertEqual(presentation.experimentalSectionTitle, "Experimental")
        XCTAssertEqual(presentation.pauseMediaLabel, "Pause Media While Recording")
        XCTAssertEqual(
            presentation.pauseMediaInfoMessage,
            "Pauses playing media when recording starts and resumes when done."
        )
        XCTAssertEqual(presentation.pauseMediaResumeDelayLabel, "Resume Delay")
        XCTAssertEqual(
            presentation.audioResumptionDelayOptions,
            [
                VoiceInkRecordingFeedbackDelayOption(label: "0s", value: 0.0),
                VoiceInkRecordingFeedbackDelayOption(label: "1s", value: 1.0),
                VoiceInkRecordingFeedbackDelayOption(label: "2s", value: 2.0),
                VoiceInkRecordingFeedbackDelayOption(label: "3s", value: 3.0),
                VoiceInkRecordingFeedbackDelayOption(label: "4s", value: 4.0),
                VoiceInkRecordingFeedbackDelayOption(label: "5s", value: 5.0)
            ]
        )
    }

    func testSystemMuteModeUsesModernValueBeforeLegacyFlag() {
        withTemporaryDefaults { defaults in
            defaults.set(VoiceInkSystemMuteMode.never.rawValue, forKey: VoiceInkRecordingFeedbackPreference.systemMuteModeKey)
            defaults.set(true, forKey: VoiceInkRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey)

            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteMode(from: defaults), .never)
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isSystemMuteEnabled(from: defaults))
        }
    }

    func testSystemMuteModeFallsBackToLegacyDisabledFlag() {
        withTemporaryDefaults { defaults in
            defaults.set(false, forKey: VoiceInkRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey)

            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteMode(from: defaults), .never)
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isSystemMuteEnabled(from: defaults))
        }
    }

    func testSystemMuteModeFallsBackToAutomaticForMissingInvalidAndLegacyEnabled() {
        withTemporaryDefaults { defaults in
            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteMode(from: defaults), .automatic)

            defaults.set("bad", forKey: VoiceInkRecordingFeedbackPreference.systemMuteModeKey)
            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteMode(from: defaults), .automatic)

            defaults.set(true, forKey: VoiceInkRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey)
            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteMode(from: defaults), .automatic)
        }
    }

    func testSavingSystemMuteModeWritesModernAndLegacyCompatibilityKeys() {
        withTemporaryDefaults { defaults in
            VoiceInkRecordingFeedbackPreference.saveSystemMuteMode(.always, to: defaults)

            XCTAssertEqual(defaults.string(forKey: VoiceInkRecordingFeedbackPreference.systemMuteModeKey), "always")
            XCTAssertTrue(defaults.bool(forKey: VoiceInkRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey))

            VoiceInkRecordingFeedbackPreference.saveSystemMuteMode(.never, to: defaults)

            XCTAssertEqual(defaults.string(forKey: VoiceInkRecordingFeedbackPreference.systemMuteModeKey), "never")
            XCTAssertFalse(defaults.bool(forKey: VoiceInkRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey))
        }
    }

    func testSavingLegacySystemMuteEnabledMapsToAlwaysAndNever() {
        withTemporaryDefaults { defaults in
            VoiceInkRecordingFeedbackPreference.saveSystemMuteEnabled(true, to: defaults)

            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteMode(from: defaults), .always)

            VoiceInkRecordingFeedbackPreference.saveSystemMuteEnabled(false, to: defaults)

            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.systemMuteMode(from: defaults), .never)
        }
    }

    func testAudioResumptionDelayReadsAndSaves() {
        withTemporaryDefaults { defaults in
            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.audioResumptionDelay(from: defaults), 0.0)

            VoiceInkRecordingFeedbackPreference.saveAudioResumptionDelay(3.0, to: defaults)

            XCTAssertEqual(VoiceInkRecordingFeedbackPreference.audioResumptionDelay(from: defaults), 3.0)
        }
    }

    func testPauseMediaAndSoundFeedbackReadAndSave() {
        withTemporaryDefaults { defaults in
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isPauseMediaEnabled(from: defaults))
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabled(from: defaults))

            VoiceInkRecordingFeedbackPreference.savePauseMediaEnabled(true, to: defaults)
            VoiceInkRecordingFeedbackPreference.saveSoundFeedbackEnabled(true, to: defaults)

            XCTAssertTrue(VoiceInkRecordingFeedbackPreference.isPauseMediaEnabled(from: defaults))
            XCTAssertTrue(VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabled(from: defaults))
        }
    }

    func testExperimentalFeaturesPreferenceReadsSavesAndPlansPauseMediaImport() {
        withTemporaryDefaults { defaults in
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isExperimentalFeaturesEnabled(from: defaults))

            VoiceInkRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(true, to: defaults)
            XCTAssertTrue(VoiceInkRecordingFeedbackPreference.isExperimentalFeaturesEnabled(from: defaults))

            VoiceInkRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(false, to: defaults)
            XCTAssertFalse(VoiceInkRecordingFeedbackPreference.isExperimentalFeaturesEnabled(from: defaults))
        }

        let disabledImportPlan = VoiceInkRecordingFeedbackPreference.backupImportPlan(
            from: VoiceInkRecordingFeedbackBackupPreferences(
                isSoundFeedbackEnabled: nil,
                isSystemMuteEnabled: nil,
                isPauseMediaEnabled: true,
                audioResumptionDelay: nil,
                isExperimentalFeaturesEnabled: false
            )
        )

        var disabledExperimentalImports = [Bool]()
        disabledImportPlan.applyCorePreferenceState {
            disabledExperimentalImports.append($0)
        }
        XCTAssertEqual(disabledExperimentalImports, [false])
        XCTAssertTrue(disabledImportPlan.shouldDisablePauseMediaForExperimentalImport)

        let enabledImportPlan = VoiceInkRecordingFeedbackPreference.backupImportPlan(
            from: VoiceInkRecordingFeedbackBackupPreferences(
                isSoundFeedbackEnabled: nil,
                isSystemMuteEnabled: nil,
                isPauseMediaEnabled: true,
                audioResumptionDelay: nil,
                isExperimentalFeaturesEnabled: true
            )
        )

        var enabledExperimentalImports = [Bool]()
        enabledImportPlan.applyCorePreferenceState {
            enabledExperimentalImports.append($0)
        }
        XCTAssertEqual(enabledExperimentalImports, [true])
        XCTAssertFalse(enabledImportPlan.shouldDisablePauseMediaForExperimentalImport)

        let missingImportPlan = VoiceInkRecordingFeedbackPreference.backupImportPlan(
            from: VoiceInkRecordingFeedbackBackupPreferences(
                isSoundFeedbackEnabled: nil,
                isSystemMuteEnabled: nil,
                isPauseMediaEnabled: true,
                audioResumptionDelay: nil
            )
        )

        var missingExperimentalImports = [Bool]()
        missingImportPlan.applyCorePreferenceState {
            missingExperimentalImports.append($0)
        }
        XCTAssertTrue(missingExperimentalImports.isEmpty)
        XCTAssertFalse(missingImportPlan.shouldDisablePauseMediaForExperimentalImport)
    }

    func testBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.backupPreferences(
                isSoundFeedbackEnabled: true,
                isSystemMuteEnabled: false,
                isPauseMediaEnabled: true,
                audioResumptionDelay: 3.0,
                isExperimentalFeaturesEnabled: true
            ),
            VoiceInkRecordingFeedbackBackupPreferences(
                isSoundFeedbackEnabled: true,
                isSystemMuteEnabled: false,
                isPauseMediaEnabled: true,
                audioResumptionDelay: 3.0,
                isExperimentalFeaturesEnabled: true
            )
        )
    }

    func testBackupImportPlanMapsLegacyMuteBooleanToCurrentMode() {
        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.backupImportPlan(
                from: VoiceInkRecordingFeedbackBackupPreferences(
                    isSoundFeedbackEnabled: true,
                    isSystemMuteEnabled: true,
                    isPauseMediaEnabled: false,
                    audioResumptionDelay: 2.0
                )
            ),
            VoiceInkRecordingFeedbackBackupImportPlan(
                isSoundFeedbackEnabled: true,
                systemMuteMode: .always,
                isPauseMediaEnabled: false,
                audioResumptionDelay: 2.0
            )
        )

        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.backupImportPlan(
                from: VoiceInkRecordingFeedbackBackupPreferences(
                    isSoundFeedbackEnabled: nil,
                    isSystemMuteEnabled: false,
                    isPauseMediaEnabled: nil,
                    audioResumptionDelay: nil
                )
            ),
            VoiceInkRecordingFeedbackBackupImportPlan(
                isSoundFeedbackEnabled: nil,
                systemMuteMode: .never,
                isPauseMediaEnabled: nil,
                audioResumptionDelay: nil
            )
        )
    }

    func testBackupImportPlanLeavesMissingFieldsAsNoOps() {
        XCTAssertEqual(
            VoiceInkRecordingFeedbackPreference.backupImportPlan(
                from: VoiceInkRecordingFeedbackBackupPreferences(
                    isSoundFeedbackEnabled: nil,
                    isSystemMuteEnabled: nil,
                    isPauseMediaEnabled: nil,
                    audioResumptionDelay: nil
                )
            ),
            VoiceInkRecordingFeedbackBackupImportPlan(
                isSoundFeedbackEnabled: nil,
                systemMuteMode: nil,
                isPauseMediaEnabled: nil,
                audioResumptionDelay: nil
            )
        )
    }

    private func customSoundCopyRuntimeResult(
        for plan: VoiceInkCustomSoundCopyPlan,
        copyThrows: Bool = false
    ) -> (result: Result<String, VoiceInkCustomSoundError>, events: [String]) {
        var events: [String] = []
        let result = plan.applyRuntimeState(
            removeExistingDestination: { url in
                events.append("remove:\(url.lastPathComponent)")
            },
            copyToDestination: { url in
                events.append("copy:\(url.lastPathComponent)")
                if copyThrows {
                    throw CustomSoundCopyFixtureError.copyFailed
                }
            }
        )

        return (result, events)
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.RecordingFeedbackPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
    }
}

private enum CustomSoundCopyFixtureError: Error {
    case copyFailed
}
