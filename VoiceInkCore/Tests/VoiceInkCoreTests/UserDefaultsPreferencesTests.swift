import Foundation
@testable import VoiceInkCore

final class UserDefaultsPreferencesTests: XCTestCase {
    func testSharedPreferenceKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkUserDefaultsKey.hasCompletedOnboarding, "hasCompletedOnboarding")
        XCTAssertEqual(VoiceInkUserDefaultsKey.lowercaseTranscription, "LowercaseTranscription")
        XCTAssertEqual(VoiceInkUserDefaultsKey.removeFillerWords, "RemoveFillerWords")
        XCTAssertEqual(VoiceInkUserDefaultsKey.fillerWords, "FillerWords")
        XCTAssertEqual(VoiceInkUserDefaultsKey.modes, "modes")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedModeId, "selectedModeId")
        XCTAssertEqual(VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds, "audioSessionTimeoutSeconds")
    }

    func testSharedPreferenceDefaultsPreserveExistingIOSAudioSessionTimeout() {
        XCTAssertEqual(VoiceInkPreferenceDefault.audioSessionTimeoutSeconds, 90)
    }

    func testModeStorageRoundTripsModesAndSelectedModeId() {
        withIsolatedDefaults { defaults in
            let localMode = Mode.defaultLocalWhisper(name: "Local")
            let cloudMode = Mode(
                name: "Cloud",
                transcriptionProvider: .deepgram,
                transcriptionModel: "nova-3-medical"
            )

            VoiceInkModeStorage.saveModes([localMode, cloudMode], to: defaults)
            VoiceInkModeStorage.saveSelectedModeId(cloudMode.id, to: defaults)

            let loadedModes = VoiceInkModeStorage.loadModes(from: defaults)
            XCTAssertEqual(loadedModes.map(\.name), ["Local", "Cloud"])
            XCTAssertEqual(loadedModes.map(\.id), [localMode.id, cloudMode.id])
            XCTAssertEqual(VoiceInkModeStorage.loadSelectedModeId(from: defaults), cloudMode.id)
        }
    }

    func testModeStorageFallsBackToEmptyModesForMissingOrInvalidData() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)

            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.modes)
            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)
        }
    }

    func testModeStorageClearRemovesModesAndSelectedModeId() {
        withIsolatedDefaults { defaults in
            let mode = Mode.defaultLocalWhisper()
            VoiceInkModeStorage.saveModes([mode], to: defaults)
            VoiceInkModeStorage.saveSelectedModeId(mode.id, to: defaults)

            VoiceInkModeStorage.clear(from: defaults)

            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkModeStorage.loadSelectedModeId(from: defaults))
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
