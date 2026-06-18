import Foundation
import VoiceInkCore

final class StreamingKeysMigrationTests: XCTestCase {
    func testMigrationKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkStreamingKeysMigration.didMigrateKey, "streaming-keys-migrated")
        XCTAssertEqual(VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey, "parakeet-streaming-enabled")
        XCTAssertEqual(VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey, "powerModeConfigurationsV2")
        XCTAssertEqual(VoiceInkStreamingKeysMigration.powerModeSelectedTranscriptionModelNameKey, "selectedTranscriptionModelName")
        XCTAssertEqual(VoiceInkUserDefaultsKey.powerModeConfigurations, "powerModeConfigurationsV2")
    }

    func testRunMigratesLegacyParakeetStreamingSettingToCurrentModels() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey)

            XCTAssertTrue(VoiceInkStreamingKeysMigration.run(in: defaults))

            XCTAssertNil(defaults.object(forKey: VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey))
            XCTAssertEqual(
                defaults.object(forKey: VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v2")) as? Bool,
                false
            )
            XCTAssertEqual(
                defaults.object(forKey: VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3")) as? Bool,
                false
            )
            XCTAssertTrue(defaults.bool(forKey: VoiceInkStreamingKeysMigration.didMigrateKey))
        }
    }

    func testRunRepairsRemovedCurrentAndPowerModeTranscriptionModels() {
        withIsolatedDefaults { defaults in
            VoiceInkCurrentTranscriptionModelPreference.saveModelName("stt-rt-v4", to: defaults)
            defaults.set(
                powerModeData([
                    [
                        "name": "Realtime",
                        "selectedTranscriptionModelName": "voxtral-mini-transcribe-realtime-2602"
                    ],
                    [
                        "name": "Unchanged",
                        "selectedTranscriptionModelName": "nova-3"
                    ],
                    [
                        "name": "Missing"
                    ]
                ]),
                forKey: VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey
            )

            VoiceInkStreamingKeysMigration.run(in: defaults)

            XCTAssertEqual(
                VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults),
                "stt-async-v4"
            )
            let configs = powerModeConfigs(from: defaults)
            XCTAssertEqual(configs[0]["selectedTranscriptionModelName"] as? String, "voxtral-mini-latest")
            XCTAssertEqual(configs[1]["selectedTranscriptionModelName"] as? String, "nova-3")
            XCTAssertNil(configs[2]["selectedTranscriptionModelName"])
        }
    }

    func testRunLeavesInvalidPowerModeJSONAloneButStillMarksMigrationComplete() {
        withIsolatedDefaults { defaults in
            let invalidData = Data("not-json".utf8)
            defaults.set(invalidData, forKey: VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey)

            XCTAssertTrue(VoiceInkStreamingKeysMigration.run(in: defaults))

            XCTAssertEqual(defaults.data(forKey: VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey), invalidData)
            XCTAssertTrue(defaults.bool(forKey: VoiceInkStreamingKeysMigration.didMigrateKey))
        }
    }

    func testRunSkipsAllWorkAfterMigrationFlagIsSet() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: VoiceInkStreamingKeysMigration.didMigrateKey)
            defaults.set(false, forKey: VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey)
            VoiceInkCurrentTranscriptionModelPreference.saveModelName("stt-rt-v4", to: defaults)

            XCTAssertFalse(VoiceInkStreamingKeysMigration.run(in: defaults))

            XCTAssertEqual(
                defaults.object(forKey: VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey) as? Bool,
                false
            )
            XCTAssertEqual(
                VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults),
                "stt-rt-v4"
            )
        }
    }

    private func powerModeData(_ configs: [[String: Any]]) -> Data {
        (try? JSONSerialization.data(withJSONObject: configs)) ?? Data()
    }

    private func powerModeConfigs(from defaults: UserDefaults) -> [[String: Any]] {
        guard let data = defaults.data(forKey: VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey),
              let configs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            XCTFail("Failed to decode power mode configs")
            return []
        }
        return configs
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.StreamingKeysMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
