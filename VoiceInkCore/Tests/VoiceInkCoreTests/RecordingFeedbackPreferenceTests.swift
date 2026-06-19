import Foundation
@testable import VoiceInkCore

final class RecordingFeedbackPreferenceTests: XCTestCase {
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

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.RecordingFeedbackPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
    }
}
