import Foundation
import RomaCore

final class RecordingFeedbackPreferenceTests: XCTestCase {
    func testBuiltInRecordingSoundsPreserveCatalogNamesAndExtensions() {
        XCTAssertEqual(
            RomaBuiltInRecordingSound.allCases.map(\.rawValue),
            ["sound1", "sound2", "sound3", "sound4", "sound5", "sound6", "sound7"]
        )
        XCTAssertEqual(RomaBuiltInRecordingSound.sound1.displayName, "Sound 1")
        XCTAssertEqual(RomaBuiltInRecordingSound.sound7.displayName, "Sound 7")
        XCTAssertEqual(RomaBuiltInRecordingSound.sound1.fileExtension, "wav")
        XCTAssertEqual(RomaBuiltInRecordingSound.sound4.fileExtension, "wav")
        XCTAssertEqual(RomaBuiltInRecordingSound.sound5.fileExtension, "mp3")
        XCTAssertEqual(RomaBuiltInRecordingSound.sound6.fileExtension, "mp3")
        XCTAssertEqual(RomaBuiltInRecordingSound.sound7.fileExtension, "wav")
    }

    func testCustomSoundTypePreservesExistingMacOSStorageKeys() {
        XCTAssertEqual(RomaCustomSoundType.start.displayName, "Start")
        XCTAssertEqual(RomaCustomSoundType.start.isUsingKey, "isUsingCustomStartSound")
        XCTAssertEqual(RomaCustomSoundType.start.filenameKey, "customStartSoundFilename")
        XCTAssertEqual(RomaCustomSoundType.start.builtInSoundKey, "selectedStartBuiltInSound")
        XCTAssertEqual(RomaCustomSoundType.start.standardName, "CustomStartSound")
        XCTAssertEqual(RomaCustomSoundType.start.defaultBuiltInSound, .sound1)
        XCTAssertEqual(RomaCustomSoundType.start.recordingSoundCue, .start)

        XCTAssertEqual(RomaCustomSoundType.stop.displayName, "Stop")
        XCTAssertEqual(RomaCustomSoundType.stop.isUsingKey, "isUsingCustomStopSound")
        XCTAssertEqual(RomaCustomSoundType.stop.filenameKey, "customStopSoundFilename")
        XCTAssertEqual(RomaCustomSoundType.stop.builtInSoundKey, "selectedStopBuiltInSound")
        XCTAssertEqual(RomaCustomSoundType.stop.standardName, "CustomStopSound")
        XCTAssertEqual(RomaCustomSoundType.stop.defaultBuiltInSound, .sound2)
        XCTAssertEqual(RomaCustomSoundType.stop.recordingSoundCue, .stop)
    }

    func testRecordingSoundPlaybackPolicyPreservesMacOSSlotsVolumesAndFallbacks() {
        XCTAssertEqual(
            RomaRecordingSoundPlaybackPolicy.setupSlots,
            [.defaultStart, .defaultStop, .defaultEsc, .customStart, .customStop]
        )

        XCTAssertEqual(RomaRecordingSoundPlayerSlot.defaultStart.volume, 0.4)
        XCTAssertEqual(RomaRecordingSoundPlayerSlot.defaultStop.volume, 0.4)
        XCTAssertEqual(RomaRecordingSoundPlayerSlot.customStart.volume, 0.4)
        XCTAssertEqual(RomaRecordingSoundPlayerSlot.customStop.volume, 0.4)
        XCTAssertEqual(RomaRecordingSoundPlayerSlot.defaultEsc.volume, 0.3)

        XCTAssertEqual(
            RomaRecordingSoundPlaybackPolicy.playbackSlots(for: .start),
            [.customStart, .defaultStart]
        )
        XCTAssertEqual(
            RomaRecordingSoundPlaybackPolicy.playbackSlots(for: .stop),
            [.customStop, .defaultStop]
        )
        XCTAssertEqual(
            RomaRecordingSoundPlaybackPolicy.playbackSlots(for: .esc),
            [.defaultEsc]
        )
    }

    func testCustomSoundPreferencePreservesDefaultsAndNotificationName() {
        XCTAssertEqual(RomaCustomSoundPreference.customSoundsRelativeDirectory, "RomaJustTalk/CustomSounds")
        XCTAssertEqual(RomaCustomSoundPreference.changedNotificationName, "CustomSoundsChanged")
        XCTAssertEqual(RomaCustomSoundPreference.maxDuration, 3.0)
        XCTAssertEqual(
            RomaCustomSoundPreference.registeredDefaults[RomaCustomSoundType.start.builtInSoundKey] as? String,
            Optional("sound1")
        )
        XCTAssertEqual(
            RomaCustomSoundPreference.registeredDefaults[RomaCustomSoundType.stop.builtInSoundKey] as? String,
            Optional("sound2")
        )
    }

    func testCustomSoundPreferenceReadsAndSavesSelectionState() {
        withTemporaryDefaults { defaults in
            XCTAssertFalse(RomaCustomSoundPreference.isUsingCustomSound(for: .start, from: defaults))
            XCTAssertNil(RomaCustomSoundPreference.customFilename(for: .start, from: defaults))
            XCTAssertEqual(RomaCustomSoundPreference.selectedBuiltInSound(for: .start, from: defaults), .sound1)

            RomaCustomSoundPreference.saveIsUsingCustomSound(true, for: .start, to: defaults)
            RomaCustomSoundPreference.saveCustomFilename("CustomStartSound.wav", for: .start, to: defaults)
            RomaCustomSoundPreference.saveSelectedBuiltInSound(.sound5, for: .start, to: defaults)

            XCTAssertTrue(RomaCustomSoundPreference.isUsingCustomSound(for: .start, from: defaults))
            XCTAssertEqual(
                RomaCustomSoundPreference.customFilename(for: .start, from: defaults),
                Optional("CustomStartSound.wav")
            )
            XCTAssertEqual(RomaCustomSoundPreference.selectedBuiltInSound(for: .start, from: defaults), .sound5)
            XCTAssertEqual(
                RomaCustomSoundPreference.selectionState(for: .start, from: defaults),
                RomaCustomSoundSelectionState(
                    type: .start,
                    isUsingCustomSound: true,
                    selectedBuiltInSound: .sound5,
                    customFilename: "CustomStartSound.wav"
                )
            )

            RomaCustomSoundPreference.saveCustomFilename(nil, for: .start, to: defaults)

            XCTAssertNil(RomaCustomSoundPreference.customFilename(for: .start, from: defaults))
        }
    }

    func testCustomSoundSelectionStateOwnsMenuAndTransitionPolicy() {
        let directory = URL(fileURLWithPath: "/tmp/RomaJustTalk/CustomSounds", isDirectory: true)
        let state = RomaCustomSoundSelectionState(
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
            "/tmp/RomaJustTalk/CustomSounds/CustomStartSound.wav"
        )

        XCTAssertEqual(
            state.selectingBuiltInSound(.sound5),
            RomaCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: false,
                selectedBuiltInSound: .sound5,
                customFilename: "CustomStartSound.wav"
            )
        )
        XCTAssertEqual(
            state.usingExistingCustomSound(),
            RomaCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: true,
                selectedBuiltInSound: .sound3,
                customFilename: "CustomStartSound.wav"
            )
        )
        XCTAssertEqual(
            state.settingCustomFilename("CustomStartSound.aiff"),
            RomaCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: true,
                selectedBuiltInSound: .sound3,
                customFilename: "CustomStartSound.aiff"
            )
        )
        XCTAssertEqual(
            state.resettingToDefault(),
            RomaCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: false,
                selectedBuiltInSound: .sound1,
                customFilename: nil
            )
        )

        let missingCustomFile = RomaCustomSoundSelectionState(
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
            defaults.set("bad", forKey: RomaCustomSoundType.stop.builtInSoundKey)

            XCTAssertEqual(RomaCustomSoundPreference.selectedBuiltInSound(for: .stop, from: defaults), .sound2)
        }
    }

    func testCustomSoundPreferencePlansDefaultSelectionAndCopyFilename() {
        XCTAssertTrue(RomaCustomSoundPreference.isDefaultSelection(
            for: .start,
            isUsingCustomSound: false,
            selectedBuiltInSound: .sound1
        ))
        XCTAssertFalse(RomaCustomSoundPreference.isDefaultSelection(
            for: .start,
            isUsingCustomSound: true,
            selectedBuiltInSound: .sound1
        ))
        XCTAssertFalse(RomaCustomSoundPreference.isDefaultSelection(
            for: .start,
            isUsingCustomSound: false,
            selectedBuiltInSound: .sound3
        ))
        XCTAssertEqual(
            RomaCustomSoundPreference.copiedFilename(sourceExtension: "aiff", for: .stop),
            "CustomStopSound.aiff"
        )
    }

    func testCustomSoundPreferenceBuildsCustomSoundURLs() {
        let directory = URL(fileURLWithPath: "/tmp/RomaJustTalk/CustomSounds", isDirectory: true)

        XCTAssertEqual(
            RomaCustomSoundPreference.customSoundURL(
                isUsingCustomSound: true,
                filename: "CustomStartSound.wav",
                in: directory
            )?.path,
            "/tmp/RomaJustTalk/CustomSounds/CustomStartSound.wav"
        )
        XCTAssertNil(RomaCustomSoundPreference.customSoundURL(
            isUsingCustomSound: false,
            filename: "CustomStartSound.wav",
            in: directory
        ))
        XCTAssertNil(RomaCustomSoundPreference.storedCustomSoundURL(filename: nil, in: directory))
        XCTAssertNil(RomaCustomSoundPreference.storedCustomSoundURL(filename: "CustomStartSound.wav", in: nil))
    }

    func testCustomSoundPreferencePlansCopyActions() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.CustomSoundCopyPlanTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.deletingLastPathComponent().appendingPathComponent("start.aiff")

        var plan = RomaCustomSoundPreference.copyPlan(
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
        plan = RomaCustomSoundPreference.copyPlan(
            sourceURL: sourceURL,
            customSoundsDirectory: directory,
            for: .start
        )
        runtimeResult = customSoundCopyRuntimeResult(for: plan)
        XCTAssertEqual(runtimeResult.result, .success("CustomStartSound.aiff"))
        XCTAssertEqual(runtimeResult.events, ["remove:CustomStartSound.aiff", "copy:CustomStartSound.aiff"])

        let destinationURL = directory.appendingPathComponent("CustomStartSound.aiff")
        plan = RomaCustomSoundPreference.copyPlan(
            sourceURL: destinationURL,
            customSoundsDirectory: directory,
            for: .start
        )
        runtimeResult = customSoundCopyRuntimeResult(for: plan)
        XCTAssertEqual(runtimeResult.result, .success("CustomStartSound.aiff"))
        XCTAssertEqual(runtimeResult.events, [])

        plan = RomaCustomSoundPreference.copyPlan(
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
            RomaCustomSoundPreference.preflightValidationError(fileExists: false, duration: 1.0),
            Optional(.fileNotFound)
        )
        XCTAssertEqual(
            RomaCustomSoundPreference.preflightValidationError(fileExists: true, duration: 0.0),
            Optional(.invalidAudioFile)
        )
        XCTAssertEqual(
            RomaCustomSoundPreference.preflightValidationError(fileExists: true, duration: .infinity),
            Optional(.invalidAudioFile)
        )
        XCTAssertEqual(
            RomaCustomSoundPreference.preflightValidationError(fileExists: true, duration: 3.1),
            Optional(.durationTooLong(duration: 3.1, maxDuration: 3.0))
        )
        XCTAssertNil(
            RomaCustomSoundPreference.preflightValidationError(fileExists: true, duration: 3.0)
        )
    }

    func testSystemMuteModePreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(RomaSystemMuteMode.automatic.rawValue, "auto")
        XCTAssertEqual(RomaSystemMuteMode.always.rawValue, "always")
        XCTAssertEqual(RomaSystemMuteMode.never.rawValue, "never")
        XCTAssertEqual(RomaSystemMuteMode.automatic.displayName, "Auto")
        XCTAssertEqual(RomaSystemMuteMode.always.displayName, "On")
        XCTAssertEqual(RomaSystemMuteMode.never.displayName, "Off")
    }

    func testRegisteredDefaultsPreserveMacOSStorageKeys() {
        XCTAssertEqual(RomaRecordingFeedbackPreference.systemMuteModeKey, "systemMuteMode")
        XCTAssertEqual(RomaRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey, "isSystemMuteEnabled")
        XCTAssertEqual(RomaRecordingFeedbackPreference.audioResumptionDelayKey, "audioResumptionDelay")
        XCTAssertEqual(RomaRecordingFeedbackPreference.isPauseMediaEnabledKey, "isPauseMediaEnabled")
        XCTAssertEqual(RomaRecordingFeedbackPreference.isSoundFeedbackEnabledKey, "isSoundFeedbackEnabled")
        XCTAssertEqual(RomaRecordingFeedbackPreference.experimentalFeaturesEnabledKey, "isExperimentalFeaturesEnabled")
        XCTAssertEqual(RomaRecordingFeedbackPreference.defaultSystemMuteScheduleDelayNanoseconds, 250_000_000)
        XCTAssertEqual(RomaRecordingFeedbackPreference.defaultPauseMediaCommandDelayNanoseconds, 50_000_000)
        XCTAssertEqual(
            RomaRecordingFeedbackPreference.registeredDefaults[RomaRecordingFeedbackPreference.systemMuteModeKey] as? String,
            "auto"
        )
        XCTAssertEqual(
            RomaRecordingFeedbackPreference.registeredDefaults[RomaRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey] as? Bool,
            true
        )
        XCTAssertEqual(
            RomaRecordingFeedbackPreference.registeredDefaults[RomaRecordingFeedbackPreference.audioResumptionDelayKey] as? TimeInterval,
            0.0
        )
        XCTAssertEqual(
            RomaRecordingFeedbackPreference.registeredDefaults[RomaRecordingFeedbackPreference.isPauseMediaEnabledKey] as? Bool,
            false
        )
        XCTAssertEqual(
            RomaRecordingFeedbackPreference.registeredDefaults[RomaRecordingFeedbackPreference.isSoundFeedbackEnabledKey] as? Bool,
            false
        )
    }

    func testSystemMuteModeUsesModernValueBeforeLegacyFlag() {
        withTemporaryDefaults { defaults in
            defaults.set(RomaSystemMuteMode.never.rawValue, forKey: RomaRecordingFeedbackPreference.systemMuteModeKey)
            defaults.set(true, forKey: RomaRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey)

            XCTAssertEqual(RomaRecordingFeedbackPreference.systemMuteMode(from: defaults), .never)
            XCTAssertFalse(RomaRecordingFeedbackPreference.isSystemMuteEnabled(from: defaults))
        }
    }

    func testSystemMuteModeFallsBackToLegacyDisabledFlag() {
        withTemporaryDefaults { defaults in
            defaults.set(false, forKey: RomaRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey)

            XCTAssertEqual(RomaRecordingFeedbackPreference.systemMuteMode(from: defaults), .never)
            XCTAssertFalse(RomaRecordingFeedbackPreference.isSystemMuteEnabled(from: defaults))
        }
    }

    func testSystemMuteModeFallsBackToAutomaticForMissingInvalidAndLegacyEnabled() {
        withTemporaryDefaults { defaults in
            XCTAssertEqual(RomaRecordingFeedbackPreference.systemMuteMode(from: defaults), .automatic)

            defaults.set("bad", forKey: RomaRecordingFeedbackPreference.systemMuteModeKey)
            XCTAssertEqual(RomaRecordingFeedbackPreference.systemMuteMode(from: defaults), .automatic)

            defaults.set(true, forKey: RomaRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey)
            XCTAssertEqual(RomaRecordingFeedbackPreference.systemMuteMode(from: defaults), .automatic)
        }
    }

    func testSavingSystemMuteModeWritesModernAndLegacyCompatibilityKeys() {
        withTemporaryDefaults { defaults in
            RomaRecordingFeedbackPreference.saveSystemMuteMode(.always, to: defaults)

            XCTAssertEqual(defaults.string(forKey: RomaRecordingFeedbackPreference.systemMuteModeKey), "always")
            XCTAssertTrue(defaults.bool(forKey: RomaRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey))

            RomaRecordingFeedbackPreference.saveSystemMuteMode(.never, to: defaults)

            XCTAssertEqual(defaults.string(forKey: RomaRecordingFeedbackPreference.systemMuteModeKey), "never")
            XCTAssertFalse(defaults.bool(forKey: RomaRecordingFeedbackPreference.legacyIsSystemMuteEnabledKey))
        }
    }

    func testSavingLegacySystemMuteEnabledMapsToAlwaysAndNever() {
        withTemporaryDefaults { defaults in
            RomaRecordingFeedbackPreference.saveSystemMuteEnabled(true, to: defaults)

            XCTAssertEqual(RomaRecordingFeedbackPreference.systemMuteMode(from: defaults), .always)

            RomaRecordingFeedbackPreference.saveSystemMuteEnabled(false, to: defaults)

            XCTAssertEqual(RomaRecordingFeedbackPreference.systemMuteMode(from: defaults), .never)
        }
    }

    func testAudioResumptionDelayReadsAndSaves() {
        withTemporaryDefaults { defaults in
            XCTAssertEqual(RomaRecordingFeedbackPreference.audioResumptionDelay(from: defaults), 0.0)

            RomaRecordingFeedbackPreference.saveAudioResumptionDelay(3.0, to: defaults)

            XCTAssertEqual(RomaRecordingFeedbackPreference.audioResumptionDelay(from: defaults), 3.0)
        }
    }

    func testPauseMediaAndSoundFeedbackReadAndSave() {
        withTemporaryDefaults { defaults in
            XCTAssertFalse(RomaRecordingFeedbackPreference.isPauseMediaEnabled(from: defaults))
            XCTAssertFalse(RomaRecordingFeedbackPreference.isSoundFeedbackEnabled(from: defaults))

            RomaRecordingFeedbackPreference.savePauseMediaEnabled(true, to: defaults)
            RomaRecordingFeedbackPreference.saveSoundFeedbackEnabled(true, to: defaults)

            XCTAssertTrue(RomaRecordingFeedbackPreference.isPauseMediaEnabled(from: defaults))
            XCTAssertTrue(RomaRecordingFeedbackPreference.isSoundFeedbackEnabled(from: defaults))
        }
    }

    func testExperimentalFeaturesPreferenceReadsSavesAndPlansPauseMediaImport() {
        withTemporaryDefaults { defaults in
            XCTAssertFalse(RomaRecordingFeedbackPreference.isExperimentalFeaturesEnabled(from: defaults))

            RomaRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(true, to: defaults)
            XCTAssertTrue(RomaRecordingFeedbackPreference.isExperimentalFeaturesEnabled(from: defaults))

            RomaRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(false, to: defaults)
            XCTAssertFalse(RomaRecordingFeedbackPreference.isExperimentalFeaturesEnabled(from: defaults))
        }

        let disabledImportPlan = RomaRecordingFeedbackPreference.backupImportPlan(
            from: RomaRecordingFeedbackBackupPreferences(
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

        let enabledImportPlan = RomaRecordingFeedbackPreference.backupImportPlan(
            from: RomaRecordingFeedbackBackupPreferences(
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

        let missingImportPlan = RomaRecordingFeedbackPreference.backupImportPlan(
            from: RomaRecordingFeedbackBackupPreferences(
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
            RomaRecordingFeedbackPreference.backupPreferences(
                isSoundFeedbackEnabled: true,
                isSystemMuteEnabled: false,
                isPauseMediaEnabled: true,
                audioResumptionDelay: 3.0,
                isExperimentalFeaturesEnabled: true
            ),
            RomaRecordingFeedbackBackupPreferences(
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
            RomaRecordingFeedbackPreference.backupImportPlan(
                from: RomaRecordingFeedbackBackupPreferences(
                    isSoundFeedbackEnabled: true,
                    isSystemMuteEnabled: true,
                    isPauseMediaEnabled: false,
                    audioResumptionDelay: 2.0
                )
            ),
            RomaRecordingFeedbackBackupImportPlan(
                isSoundFeedbackEnabled: true,
                systemMuteMode: .always,
                isPauseMediaEnabled: false,
                audioResumptionDelay: 2.0
            )
        )

        XCTAssertEqual(
            RomaRecordingFeedbackPreference.backupImportPlan(
                from: RomaRecordingFeedbackBackupPreferences(
                    isSoundFeedbackEnabled: nil,
                    isSystemMuteEnabled: false,
                    isPauseMediaEnabled: nil,
                    audioResumptionDelay: nil
                )
            ),
            RomaRecordingFeedbackBackupImportPlan(
                isSoundFeedbackEnabled: nil,
                systemMuteMode: .never,
                isPauseMediaEnabled: nil,
                audioResumptionDelay: nil
            )
        )
    }

    func testBackupImportPlanLeavesMissingFieldsAsNoOps() {
        XCTAssertEqual(
            RomaRecordingFeedbackPreference.backupImportPlan(
                from: RomaRecordingFeedbackBackupPreferences(
                    isSoundFeedbackEnabled: nil,
                    isSystemMuteEnabled: nil,
                    isPauseMediaEnabled: nil,
                    audioResumptionDelay: nil
                )
            ),
            RomaRecordingFeedbackBackupImportPlan(
                isSoundFeedbackEnabled: nil,
                systemMuteMode: nil,
                isPauseMediaEnabled: nil,
                audioResumptionDelay: nil
            )
        )
    }

    private func customSoundCopyRuntimeResult(
        for plan: RomaCustomSoundCopyPlan,
        copyThrows: Bool = false
    ) -> (result: Result<String, RomaCustomSoundError>, events: [String]) {
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
        let suiteName = "RomaCore.RecordingFeedbackPreferenceTests.\(UUID().uuidString)"
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
