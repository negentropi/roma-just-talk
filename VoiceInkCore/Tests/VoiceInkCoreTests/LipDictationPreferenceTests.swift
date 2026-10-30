import Foundation
import VoiceInkCore

final class LipDictationPreferenceTests: XCTestCase {
    func testFreshPreferencesKeepVoiceOnlyAndCameraClosed() {
        withTemporaryDefaults { defaults, _ in
            XCTAssertEqual(VoiceInkLipDictationPreference.mode(in: defaults), .voice)
            defaults.register(defaults: VoiceInkLipDictationPreference.registeredDefaults)
            let mode = VoiceInkLipDictationPreference.mode(in: defaults)
            XCTAssertEqual(mode, .voice)
            XCTAssertTrue(mode.usesMicrophone)
            XCTAssertFalse(mode.usesCamera)
            XCTAssertFalse(VoiceInkLipDictationPreference.isEnabled(from: defaults))
            XCTAssertFalse(VoiceInkLipDictationPreference.isLipOnly(from: defaults))
        }
    }

    func testEnablingLipDictationActivatesVoiceAndCameraTogether() {
        withTemporaryDefaults { defaults, _ in
            VoiceInkLipDictationPreference.saveIsEnabled(true, to: defaults)
            let mode = VoiceInkLipDictationPreference.mode(in: defaults)
            XCTAssertEqual(mode, .voiceAndLips)
            XCTAssertTrue(mode.usesMicrophone)
            XCTAssertTrue(mode.usesCamera)
        }
    }

    func testLipOnlySelectionDisablesMicrophoneUntilMasterIsOff() {
        withTemporaryDefaults { defaults, _ in
            VoiceInkLipDictationPreference.saveIsEnabled(true, to: defaults)
            VoiceInkLipDictationPreference.saveLipOnly(true, to: defaults)
            let activeMode = VoiceInkLipDictationPreference.mode(in: defaults)
            XCTAssertEqual(activeMode, .lips)
            XCTAssertFalse(activeMode.usesMicrophone)
            XCTAssertTrue(activeMode.usesCamera)

            VoiceInkLipDictationPreference.saveIsEnabled(false, to: defaults)
            XCTAssertEqual(VoiceInkLipDictationPreference.mode(in: defaults), .voice)
            XCTAssertTrue(VoiceInkLipDictationPreference.isLipOnly(from: defaults))
            VoiceInkLipDictationPreference.saveIsEnabled(true, to: defaults)
            XCTAssertEqual(VoiceInkLipDictationPreference.mode(in: defaults), .lips)
        }
    }

    func testLipOnlyChoicePersistsAcrossPreferenceInstancesWithoutAffectingAnotherSuite() {
        withTemporaryDefaults { defaults, suiteName in
            VoiceInkLipDictationPreference.saveIsEnabled(true, to: defaults)
            VoiceInkLipDictationPreference.saveLipOnly(true, to: defaults)
            defaults.synchronize()

            let relaunchedDefaults = UserDefaults(suiteName: suiteName)!
            XCTAssertEqual(VoiceInkLipDictationPreference.mode(in: relaunchedDefaults), .lips)

            withTemporaryDefaults { independentDefaults, _ in
                XCTAssertEqual(VoiceInkLipDictationPreference.mode(in: independentDefaults), .voice)
            }
        }
    }

    private func withTemporaryDefaults(_ test: (UserDefaults, String) -> Void) {
        let suiteName = "VoiceInkCore.LipDictationPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        test(defaults, suiteName)
    }
}
