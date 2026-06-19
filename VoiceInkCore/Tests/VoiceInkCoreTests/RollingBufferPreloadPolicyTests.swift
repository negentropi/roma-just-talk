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
        XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.defaultPreRunFinalization)
        XCTAssertTrue(VoiceInkRollingBufferPreloadSettings.defaultPerModelPreloadEnabled)
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
