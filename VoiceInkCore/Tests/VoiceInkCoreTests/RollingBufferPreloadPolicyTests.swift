import Foundation
@testable import VoiceInkCore

final class RollingBufferPreloadPolicyTests: XCTestCase {
    func testSettingsPreserveExistingStorageKeysAndDefaults() {
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.modeKey, "RollingBufferPreloadMode")
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.autoDisableCloudModelsKey, "RollingBufferPreloadAutoDisableCloudModels")
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey, "RollingBufferPreloadAutoDisableLowBatteryLocalModels")
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.lowBatteryThresholdPercentKey, "RollingBufferPreloadLowBatteryThresholdPercent")
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.bufferDurationSecondsKey, "RollingBufferDurationSeconds")
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.preRunFinalizationKey, "RollingBufferPreloadFinalization")
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.perModelEnabledKeyPrefix, "rolling-buffer-preload-enabled-")

        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.defaultMode, .auto)
        XCTAssertFalse(VoiceInkRollingBufferPreloadSettings.defaultAutoDisablesCloudModels)
        XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.defaultAutoDisablesLowBatteryLocalModels)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.defaultLowBatteryThresholdPercent, 40)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.defaultBufferDurationSeconds, 3.0)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.minimumBufferDurationSeconds, 0.25)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.maximumBufferDurationSeconds, 30.0)
        XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.defaultPreRunFinalization)
        XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.defaultPerModelPreloadEnabled)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.defaultStartingPreloadClaimWaitNanoseconds, 150_000_000)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.defaultUnclaimedPreloadSilenceSeconds, 1.0)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.defaultUnclaimedPreloadGraceSeconds, 2.0)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.defaultPlanRefreshInterval, 30)
    }

    func testSettingsNormalizeDurationAndBatteryThresholdRanges() {
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.normalizedLowBatteryThresholdPercent(-1), 1)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.normalizedLowBatteryThresholdPercent(55), 55)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.normalizedLowBatteryThresholdPercent(500), 100)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.normalizedBufferDurationSeconds(0), 0.25)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.normalizedBufferDurationSeconds(4.5), 4.5)
        XCTAssertEqual(VoiceInkRollingBufferPreloadSettings.normalizedBufferDurationSeconds(99), 30.0)
    }

    func testPartialTranscriptRequestPreservesNotificationContract() {
        XCTAssertEqual(
            VoiceInkRollingBufferPreloadPartialTranscriptRequest.notificationName.rawValue,
            "rollingBufferPreloadPartialTranscript"
        )
        XCTAssertEqual(VoiceInkRollingBufferPreloadPartialTranscriptRequest.textUserInfoKey, "text")

        let userInfo = VoiceInkRollingBufferPreloadPartialTranscriptRequest.userInfo(text: "hello")
        XCTAssertEqual(userInfo[VoiceInkRollingBufferPreloadPartialTranscriptRequest.textUserInfoKey] as? String, "hello")

        let notification = Notification(
            name: VoiceInkRollingBufferPreloadPartialTranscriptRequest.notificationName,
            userInfo: userInfo
        )
        XCTAssertEqual(VoiceInkRollingBufferPreloadPartialTranscriptRequest.text(from: notification), "hello")
        XCTAssertNil(
            VoiceInkRollingBufferPreloadPartialTranscriptRequest.text(
                from: Notification(name: VoiceInkRollingBufferPreloadPartialTranscriptRequest.notificationName)
            )
        )
    }

    func testSettingsPresentationPreservesMacOSCopy() {
        let presentation = VoiceInkRollingBufferPreloadSettings.macOSSettingsPresentation

        XCTAssertEqual(presentation.sectionTitle, "Rolling Buffer")
        XCTAssertEqual(presentation.modePickerTitle, "Buffer Preload")
        XCTAssertEqual(
            presentation.modePickerHelp,
            "Runs local VAD on the rolling buffer and pre-runs supported STT models before capture is finalized."
        )
        XCTAssertEqual(presentation.durationLabel, "Rolling Duration")
        XCTAssertEqual(presentation.durationUnitLabel, "s")
        XCTAssertEqual(presentation.preRunFinalizationTitle, "Pre-run Finalization")
        XCTAssertEqual(
            presentation.preRunFinalizationHelp,
            "When available, use the already-running preload session to finalize text instead of starting transcription from the saved WAV."
        )
        XCTAssertEqual(presentation.vadModelPickerTitle, "Buffer VAD Model")
        XCTAssertEqual(
            presentation.vadModelPickerHelp,
            "Silero runs locally on CPU and watches rolling-buffer audio for speech before STT preload starts."
        )
        XCTAssertEqual(presentation.autoDisableCloudModelsTitle, "Auto: Disable Cloud Models")
        XCTAssertEqual(
            presentation.autoDisableCloudModelsHelp,
            "When enabled, Auto keeps rolling-buffer preload local and avoids cloud streaming before capture."
        )
        XCTAssertEqual(presentation.autoDisableLowBatteryLocalModelsTitle, "Auto: Disable Local Models on Low Battery")
        XCTAssertEqual(
            presentation.autoDisableLowBatteryLocalModelsHelp,
            "When enabled, Auto stops local pre-run STT while running on battery below the cutoff."
        )
        XCTAssertEqual(presentation.batteryCutoffLabel(percent: 40), "Battery cutoff: 40%")
    }

    func testVADModelSettingsPreserveExistingStorageAndSileroIdentity() {
        XCTAssertEqual(VoiceInkRollingBufferVADSettings.modelKey, "RollingBufferVADModel")
        XCTAssertEqual(VoiceInkRollingBufferVADSettings.defaultModel, .silero)
        XCTAssertEqual(VoiceInkRollingBufferVADSettings.sileroModelName, "silero")
        XCTAssertEqual(VoiceInkRollingBufferVADModel.allCases, [.silero])
        XCTAssertEqual(VoiceInkRollingBufferVADModel.silero.rawValue, "silero")
        XCTAssertEqual(VoiceInkRollingBufferVADModel.silero.displayName, "Silero")
    }

    func testVADModelSettingsReadSaveAndImportRawValues() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkRollingBufferVADSettings.selectedModel(in: defaults), "silero")
            XCTAssertTrue(VoiceInkRollingBufferVADSettings.usesSilero(in: defaults))

            defaults.set("future-vad", forKey: VoiceInkRollingBufferVADSettings.modelKey)
            XCTAssertEqual(VoiceInkRollingBufferVADSettings.selectedModel(in: defaults), "future-vad")
            XCTAssertFalse(VoiceInkRollingBufferVADSettings.usesSilero(in: defaults))

            VoiceInkRollingBufferVADSettings.saveSelectedModel(.silero, to: defaults)
            XCTAssertEqual(VoiceInkRollingBufferVADSettings.selectedModel(in: defaults), "silero")
            XCTAssertTrue(VoiceInkRollingBufferVADSettings.usesSilero(in: defaults))

            defaults.set("future-vad", forKey: VoiceInkRollingBufferVADSettings.modelKey)
            XCTAssertFalse(VoiceInkRollingBufferVADSettings.saveImportedModel(rawValue: "bad", to: defaults))
            XCTAssertEqual(VoiceInkRollingBufferVADSettings.selectedModel(in: defaults), "future-vad")
            XCTAssertTrue(VoiceInkRollingBufferVADSettings.saveImportedModel(rawValue: "silero", to: defaults))
            XCTAssertEqual(VoiceInkRollingBufferVADSettings.selectedModel(in: defaults), "silero")
        }
    }

    func testConfigurationReadsAndClampsStoredValues() {
        withIsolatedDefaults { defaults in
            defaults.set("on", forKey: VoiceInkRollingBufferPreloadSettings.modeKey)
            defaults.set(true, forKey: VoiceInkRollingBufferPreloadSettings.autoDisableCloudModelsKey)
            defaults.set(false, forKey: VoiceInkRollingBufferPreloadSettings.autoDisableLowBatteryLocalModelsKey)
            defaults.set(500, forKey: VoiceInkRollingBufferPreloadSettings.lowBatteryThresholdPercentKey)
            defaults.set(99.0, forKey: VoiceInkRollingBufferPreloadSettings.bufferDurationSecondsKey)
            defaults.set(false, forKey: VoiceInkRollingBufferPreloadSettings.preRunFinalizationKey)

            let configuration = VoiceInkRollingBufferPreloadSettings.configuration(in: defaults)

            XCTAssertEqual(configuration.mode, .on)
            XCTAssertTrue(configuration.autoDisablesCloudModels)
            XCTAssertFalse(configuration.autoDisablesLowBatteryLocalModels)
            XCTAssertEqual(configuration.lowBatteryThresholdPercent, 100)
            XCTAssertEqual(configuration.bufferDurationSeconds, 30.0)
            XCTAssertFalse(configuration.preRunFinalization)
        }
    }

    func testPerModelPreloadDefaultsEnabledAndReadsStoredOverride() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(
                forModelName: "parakeet",
                in: defaults
            ))

            VoiceInkRollingBufferPreloadSettings.savePerModelPreloadEnabled(
                false,
                forModelName: "parakeet",
                in: defaults
            )

            XCTAssertFalse(VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(
                forModelName: "parakeet",
                in: defaults
            ))

            VoiceInkRollingBufferPreloadSettings.savePerModelPreloadEnabled(
                true,
                forModelName: "parakeet",
                in: defaults
            )

            XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(
                forModelName: "parakeet",
                in: defaults
            ))
        }
    }

    func testExportedPerModelPreloadEnabledReadsOnlyStoredBooleanOverrides() {
        withIsolatedDefaults { defaults in
            VoiceInkRollingBufferPreloadSettings.savePerModelPreloadEnabled(
                false,
                forModelName: "parakeet",
                in: defaults
            )
            VoiceInkRollingBufferPreloadSettings.savePerModelPreloadEnabled(
                true,
                forModelName: "fluid",
                in: defaults
            )
            defaults.set("no", forKey: VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabledKey(forModelName: "bad"))
            defaults.set(true, forKey: VoiceInkRollingBufferPreloadSettings.perModelEnabledKeyPrefix)
            defaults.set(false, forKey: "other-prefix-parakeet")

            XCTAssertEqual(
                VoiceInkRollingBufferPreloadSettings.exportedPerModelPreloadEnabled(from: defaults),
                [
                    "parakeet": false,
                    "fluid": true
                ]
            )
        }
    }

    func testBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            VoiceInkRollingBufferPreloadSettings.backupPreferences(
                from: VoiceInkRollingBufferPreloadConfiguration(
                    mode: .on,
                    autoDisablesCloudModels: true,
                    autoDisablesLowBatteryLocalModels: false,
                    lowBatteryThresholdPercent: 55,
                    bufferDurationSeconds: 4.5,
                    preRunFinalization: false
                ),
                selectedVADModelRawValue: "silero",
                perModelPreloadEnabled: ["parakeet": false]
            ),
            VoiceInkRollingBufferBackupPreferences(
                preloadModeRawValue: "on",
                autoDisablesCloudModels: true,
                autoDisablesLowBatteryLocalModels: false,
                lowBatteryThresholdPercent: 55,
                bufferDurationSeconds: 4.5,
                preRunFinalization: false,
                vadModelRawValue: "silero",
                perModelPreloadEnabled: ["parakeet": false]
            )
        )

        XCTAssertNil(
            VoiceInkRollingBufferPreloadSettings.backupPreferences(
                from: configuration(mode: .auto),
                selectedVADModelRawValue: "future-vad",
                perModelPreloadEnabled: [:]
            ).perModelPreloadEnabled
        )
    }

    func testBackupImportPlanValidatesAndClampsRawValues() {
        XCTAssertEqual(
            VoiceInkRollingBufferPreloadSettings.backupImportPlan(
                from: VoiceInkRollingBufferBackupPreferences(
                    preloadModeRawValue: "on",
                    autoDisablesCloudModels: true,
                    autoDisablesLowBatteryLocalModels: false,
                    lowBatteryThresholdPercent: 500,
                    bufferDurationSeconds: 99,
                    preRunFinalization: false,
                    vadModelRawValue: "silero",
                    perModelPreloadEnabled: [
                        "parakeet": false,
                        "": true
                    ]
                )
            ),
            VoiceInkRollingBufferBackupImportPlan(
                mode: .on,
                autoDisablesCloudModels: true,
                autoDisablesLowBatteryLocalModels: false,
                lowBatteryThresholdPercent: 100,
                bufferDurationSeconds: 30,
                preRunFinalization: false,
                vadModel: .silero,
                perModelPreloadEnabled: [
                    "parakeet": false,
                    "": true
                ]
            )
        )

        XCTAssertEqual(
            VoiceInkRollingBufferPreloadSettings.backupImportPlan(
                from: VoiceInkRollingBufferBackupPreferences(
                    preloadModeRawValue: "bad",
                    autoDisablesCloudModels: nil,
                    autoDisablesLowBatteryLocalModels: nil,
                    lowBatteryThresholdPercent: -1,
                    bufferDurationSeconds: 0,
                    preRunFinalization: nil,
                    vadModelRawValue: "future-vad",
                    perModelPreloadEnabled: nil
                )
            ),
            VoiceInkRollingBufferBackupImportPlan(
                mode: nil,
                autoDisablesCloudModels: nil,
                autoDisablesLowBatteryLocalModels: nil,
                lowBatteryThresholdPercent: 1,
                bufferDurationSeconds: 0.25,
                preRunFinalization: nil,
                vadModel: nil,
                perModelPreloadEnabled: nil
            )
        )
    }

    func testImportedSettingsSavePresentValuesAndClampRanges() {
        withIsolatedDefaults { defaults in
            let didSave = VoiceInkRollingBufferPreloadSettings.saveImportedSettings(
                modeRawValue: "on",
                autoDisablesCloudModels: true,
                autoDisablesLowBatteryLocalModels: false,
                lowBatteryThresholdPercent: 500,
                bufferDurationSeconds: 99,
                preRunFinalization: false,
                perModelPreloadEnabled: [
                    "parakeet": false,
                    "": true
                ],
                to: defaults
            )

            XCTAssertTrue(didSave)
            let configuration = VoiceInkRollingBufferPreloadSettings.configuration(in: defaults)
            XCTAssertEqual(configuration.mode, .on)
            XCTAssertTrue(configuration.autoDisablesCloudModels)
            XCTAssertFalse(configuration.autoDisablesLowBatteryLocalModels)
            XCTAssertEqual(configuration.lowBatteryThresholdPercent, 100)
            XCTAssertEqual(configuration.bufferDurationSeconds, 30)
            XCTAssertFalse(configuration.preRunFinalization)
            XCTAssertFalse(VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(
                forModelName: "parakeet",
                in: defaults
            ))
            XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(
                forModelName: "",
                in: defaults
            ))
        }
    }

    func testImportedSettingsIgnoreInvalidAndMissingValues() {
        withIsolatedDefaults { defaults in
            defaults.set("off", forKey: VoiceInkRollingBufferPreloadSettings.modeKey)

            let didSave = VoiceInkRollingBufferPreloadSettings.saveImportedSettings(
                modeRawValue: "bad",
                autoDisablesCloudModels: nil,
                autoDisablesLowBatteryLocalModels: nil,
                lowBatteryThresholdPercent: nil,
                bufferDurationSeconds: nil,
                preRunFinalization: nil,
                perModelPreloadEnabled: nil,
                to: defaults
            )

            XCTAssertFalse(didSave)
            XCTAssertEqual(
                VoiceInkRollingBufferPreloadSettings.configuration(in: defaults).mode,
                .off
            )
        }
    }

    func testImportedBackupPlanSavesPreloadAndVADSettings() {
        withIsolatedDefaults { defaults in
            let importPlan = VoiceInkRollingBufferPreloadSettings.backupImportPlan(
                from: VoiceInkRollingBufferBackupPreferences(
                    preloadModeRawValue: "on",
                    autoDisablesCloudModels: true,
                    autoDisablesLowBatteryLocalModels: false,
                    lowBatteryThresholdPercent: 500,
                    bufferDurationSeconds: 99,
                    preRunFinalization: false,
                    vadModelRawValue: "silero",
                    perModelPreloadEnabled: ["parakeet": false]
                )
            )

            XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.saveImportedSettings(from: importPlan, to: defaults))
            XCTAssertTrue(VoiceInkRollingBufferVADSettings.saveImportedModel(from: importPlan, to: defaults))

            let configuration = VoiceInkRollingBufferPreloadSettings.configuration(in: defaults)
            XCTAssertEqual(configuration.mode, .on)
            XCTAssertTrue(configuration.autoDisablesCloudModels)
            XCTAssertFalse(configuration.autoDisablesLowBatteryLocalModels)
            XCTAssertEqual(configuration.lowBatteryThresholdPercent, 100)
            XCTAssertEqual(configuration.bufferDurationSeconds, 30)
            XCTAssertFalse(configuration.preRunFinalization)
            XCTAssertFalse(VoiceInkRollingBufferPreloadSettings.perModelPreloadEnabled(
                forModelName: "parakeet",
                in: defaults
            ))
            XCTAssertEqual(VoiceInkRollingBufferVADSettings.selectedModel(in: defaults), "silero")
        }
    }

    func testPolicyRejectsNonStreamingAndPerModelDisabled() {
        let policy = VoiceInkRollingBufferPreloadPolicy(
            configuration: configuration(mode: .on),
            powerState: VoiceInkRollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
        )

        XCTAssertFalse(policy.allowsPreload(
            for: VoiceInkRollingBufferPreloadModelSnapshot(supportsStreaming: false, isCloudTranscriptionProvider: false),
            perModelEnabled: true
        ))
        XCTAssertFalse(policy.allowsPreload(
            for: VoiceInkRollingBufferPreloadModelSnapshot(supportsStreaming: true, isCloudTranscriptionProvider: false),
            perModelEnabled: false
        ))
    }

    func testPolicyHonorsModeOnAndOff() {
        let model = VoiceInkRollingBufferPreloadModelSnapshot(
            supportsStreaming: true,
            isCloudTranscriptionProvider: true
        )
        let powerState = VoiceInkRollingBufferPowerState(isOnBattery: true, batteryLevelPercent: 1)

        XCTAssertTrue(VoiceInkRollingBufferPreloadPolicy(
            configuration: configuration(mode: .on, autoDisablesCloudModels: true),
            powerState: powerState
        ).allowsPreload(for: model, perModelEnabled: true))
        XCTAssertFalse(VoiceInkRollingBufferPreloadPolicy(
            configuration: configuration(mode: .off),
            powerState: powerState
        ).allowsPreload(for: model, perModelEnabled: true))
    }

    func testAutoPolicyCanDisableCloudModels() {
        let policy = VoiceInkRollingBufferPreloadPolicy(
            configuration: configuration(mode: .auto, autoDisablesCloudModels: true),
            powerState: VoiceInkRollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
        )

        XCTAssertFalse(policy.allowsPreload(
            for: VoiceInkRollingBufferPreloadModelSnapshot(supportsStreaming: true, isCloudTranscriptionProvider: true),
            perModelEnabled: true
        ))
        XCTAssertTrue(policy.allowsPreload(
            for: VoiceInkRollingBufferPreloadModelSnapshot(supportsStreaming: true, isCloudTranscriptionProvider: false),
            perModelEnabled: true
        ))
    }

    func testAutoPolicyCanDisableLocalModelsOnLowBattery() {
        let configuration = configuration(
            mode: .auto,
            autoDisablesLowBatteryLocalModels: true,
            lowBatteryThresholdPercent: 40
        )
        let model = VoiceInkRollingBufferPreloadModelSnapshot(
            supportsStreaming: true,
            isCloudTranscriptionProvider: false
        )

        XCTAssertFalse(VoiceInkRollingBufferPreloadPolicy(
            configuration: configuration,
            powerState: VoiceInkRollingBufferPowerState(isOnBattery: true, batteryLevelPercent: 20)
        ).allowsPreload(for: model, perModelEnabled: true))
        XCTAssertTrue(VoiceInkRollingBufferPreloadPolicy(
            configuration: configuration,
            powerState: VoiceInkRollingBufferPowerState(isOnBattery: true, batteryLevelPercent: 40)
        ).allowsPreload(for: model, perModelEnabled: true))
        XCTAssertTrue(VoiceInkRollingBufferPreloadPolicy(
            configuration: configuration,
            powerState: VoiceInkRollingBufferPowerState(isOnBattery: false, batteryLevelPercent: 20)
        ).allowsPreload(for: model, perModelEnabled: true))
    }

    func testBufferedSnapshotTranscriptionStrategyUsesRecordedFileCapability() {
        XCTAssertEqual(
            VoiceInkRollingBufferBufferedSnapshotTranscriptionPolicy.strategy(
                for: VoiceInkRollingBufferPreloadModelSnapshot(
                    supportsStreaming: true,
                    isCloudTranscriptionProvider: false,
                    supportsRecordedFileTranscription: true
                )
            ),
            .recordedFile
        )
        XCTAssertEqual(
            VoiceInkRollingBufferBufferedSnapshotTranscriptionPolicy.strategy(
                for: VoiceInkRollingBufferPreloadModelSnapshot(
                    supportsStreaming: true,
                    isCloudTranscriptionProvider: true,
                    supportsRecordedFileTranscription: false
                )
            ),
            .unavailable
        )
    }

    func testQuickReleaseClaimStrategyPreservesDiagnosticLabels() {
        XCTAssertEqual(VoiceInkRollingBufferQuickReleaseClaimStrategy.none.displayName, "None")
        XCTAssertEqual(VoiceInkRollingBufferQuickReleaseClaimStrategy.readyPreload.displayName, "Ready Preload")
        XCTAssertEqual(
            VoiceInkRollingBufferQuickReleaseClaimStrategy.bufferedAudioSnapshot.displayName,
            "Buffered Audio Snapshot"
        )
        XCTAssertEqual(VoiceInkRollingBufferQuickReleaseClaimStrategy.unavailable.displayName, "Unavailable")
        XCTAssertEqual(VoiceInkRollingBufferQuickReleaseClaimStrategy.invalidated.displayName, "Invalidated")
        XCTAssertEqual(VoiceInkRollingBufferQuickReleaseClaimStrategy.failed.displayName, "Failed")
    }

    func testQuickReleaseClaimSnapshotFormatsDisplayAndExportSummaries() {
        var snapshot = VoiceInkRollingBufferQuickReleaseClaimSnapshot(
            strategy: .bufferedAudioSnapshot,
            reason: "no-claim",
            audioBytes: 1024,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            claimElapsedSeconds: 0.1234,
            transcriptionReadySeconds: nil,
            activeWindowReadySeconds: nil,
            pasteStartingSeconds: nil,
            pasteCompletedSeconds: nil,
            pipelineReturnedSeconds: 0.8,
            idleSeconds: nil,
            sessionFinishedSeconds: nil,
            savedSeconds: nil
        )

        XCTAssertEqual(
            snapshot.displaySummary,
            "Buffered Audio Snapshot - no-claim - 1 KB - claim 0.123s - returned 0.800s"
        )

        snapshot.recordTiming(
            stage: .pasteCompleted,
            elapsedSeconds: 0.4567,
            at: Date(timeIntervalSince1970: 2_000)
        )
        snapshot.recordTiming(
            stage: .idle,
            elapsedSeconds: 0.9,
            at: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertEqual(
            snapshot.displaySummary,
            "Buffered Audio Snapshot - no-claim - 1 KB - paste 0.457s - idle 0.900s"
        )
        XCTAssertTrue(snapshot.exportSummary.contains("claim=0.123s"))
        XCTAssertTrue(snapshot.exportSummary.contains("paste-complete=0.457s"))
        XCTAssertTrue(snapshot.exportSummary.contains("returned=0.800s"))
        XCTAssertTrue(snapshot.exportSummary.contains("idle=0.900s"))
    }

    private func configuration(
        mode: VoiceInkRollingBufferPreloadMode,
        autoDisablesCloudModels: Bool = false,
        autoDisablesLowBatteryLocalModels: Bool = true,
        lowBatteryThresholdPercent: Int = 40
    ) -> VoiceInkRollingBufferPreloadConfiguration {
        VoiceInkRollingBufferPreloadConfiguration(
            mode: mode,
            autoDisablesCloudModels: autoDisablesCloudModels,
            autoDisablesLowBatteryLocalModels: autoDisablesLowBatteryLocalModels,
            lowBatteryThresholdPercent: lowBatteryThresholdPercent,
            bufferDurationSeconds: 3.0,
            preRunFinalization: true
        )
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.RollingBufferPreloadPolicyTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        run(defaults)
    }
}
