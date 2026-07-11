import XCTest
import VoiceInkCore

final class IOSRecordingFeedbackTests: XCTestCase {
    func testFeedbackPlanSupportsHapticSoundAndSilentChoices() throws {
        let defaults = try makeDefaults()

        XCTAssertEqual(
            VoiceInkIOSRecordingFeedbackPreference.plan(from: defaults),
            VoiceInkIOSRecordingFeedbackPlan(playsHaptic: true, playsSound: false)
        )

        VoiceInkIOSRecordingFeedbackPreference.saveHapticFeedbackEnabled(false, to: defaults)
        defaults.set(true, forKey: VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey)
        XCTAssertEqual(
            VoiceInkIOSRecordingFeedbackPreference.plan(from: defaults),
            VoiceInkIOSRecordingFeedbackPlan(playsHaptic: false, playsSound: true)
        )

        defaults.set(false, forKey: VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey)
        XCTAssertEqual(
            VoiceInkIOSRecordingFeedbackPreference.plan(from: defaults),
            VoiceInkIOSRecordingFeedbackPlan(playsHaptic: false, playsSound: false)
        )
    }

    func testStartAndStopSoundSelectionsPersistIndependently() throws {
        let defaults = try makeDefaults()
        VoiceInkCustomSoundPreference.saveSelectedBuiltInSound(.sound3, for: .start, to: defaults)
        VoiceInkCustomSoundPreference.saveSelectedBuiltInSound(.sound6, for: .stop, to: defaults)
        VoiceInkCustomSoundPreference.saveCustomFilename("CustomStartSound.wav", for: .start, to: defaults)
        VoiceInkCustomSoundPreference.saveIsUsingCustomSound(true, for: .start, to: defaults)

        XCTAssertEqual(
            VoiceInkCustomSoundPreference.selectionState(for: .start, from: defaults),
            VoiceInkCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: true,
                selectedBuiltInSound: .sound3,
                customFilename: "CustomStartSound.wav"
            )
        )
        XCTAssertEqual(
            VoiceInkCustomSoundPreference.selectionState(for: .stop, from: defaults).selectedBuiltInSound,
            .sound6
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "IOSRecordingFeedbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
