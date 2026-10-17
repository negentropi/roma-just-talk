import XCTest
import RomaCore

final class IOSRecordingFeedbackTests: XCTestCase {
    func testFeedbackPlanSupportsHapticSoundAndSilentChoices() throws {
        let defaults = try makeDefaults()

        XCTAssertEqual(
            RomaIOSRecordingFeedbackPreference.plan(from: defaults),
            RomaIOSRecordingFeedbackPlan(playsHaptic: true, playsSound: false)
        )

        RomaIOSRecordingFeedbackPreference.saveHapticFeedbackEnabled(false, to: defaults)
        defaults.set(true, forKey: RomaRecordingFeedbackPreference.isSoundFeedbackEnabledKey)
        XCTAssertEqual(
            RomaIOSRecordingFeedbackPreference.plan(from: defaults),
            RomaIOSRecordingFeedbackPlan(playsHaptic: false, playsSound: true)
        )

        defaults.set(false, forKey: RomaRecordingFeedbackPreference.isSoundFeedbackEnabledKey)
        XCTAssertEqual(
            RomaIOSRecordingFeedbackPreference.plan(from: defaults),
            RomaIOSRecordingFeedbackPlan(playsHaptic: false, playsSound: false)
        )
    }

    func testStartAndStopSoundSelectionsPersistIndependently() throws {
        let defaults = try makeDefaults()
        RomaCustomSoundPreference.saveSelectedBuiltInSound(.sound3, for: .start, to: defaults)
        RomaCustomSoundPreference.saveSelectedBuiltInSound(.sound6, for: .stop, to: defaults)
        RomaCustomSoundPreference.saveCustomFilename("CustomStartSound.wav", for: .start, to: defaults)
        RomaCustomSoundPreference.saveIsUsingCustomSound(true, for: .start, to: defaults)

        XCTAssertEqual(
            RomaCustomSoundPreference.selectionState(for: .start, from: defaults),
            RomaCustomSoundSelectionState(
                type: .start,
                isUsingCustomSound: true,
                selectedBuiltInSound: .sound3,
                customFilename: "CustomStartSound.wav"
            )
        )
        XCTAssertEqual(
            RomaCustomSoundPreference.selectionState(for: .stop, from: defaults).selectedBuiltInSound,
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
