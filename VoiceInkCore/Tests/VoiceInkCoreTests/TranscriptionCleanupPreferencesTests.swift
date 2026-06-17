import Foundation
@testable import VoiceInkCore

final class TranscriptionCleanupPreferencesTests: XCTestCase {
    func testPunctuationModeDisplayNamesMatchMacOSSettingsLabels() {
        XCTAssertEqual(PunctuationCleanupMode.keep.displayName, "Keep")
        XCTAssertEqual(PunctuationCleanupMode.removeAll.displayName, "Remove all")
        XCTAssertEqual(PunctuationCleanupMode.removeTrailingPeriod.displayName, "Remove trailing period")
    }

    func testCurrentFallsBackToLegacyRemovePunctuationFlag() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
        }
    }

    func testSetCurrentWritesNewModeAndLegacyCompatibilityFlag() {
        withIsolatedDefaults { defaults in
            PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
            XCTAssertEqual(defaults.string(forKey: PunctuationCleanupMode.userDefaultsKey), "removeTrailingPeriod")
            XCTAssertFalse(defaults.bool(forKey: PunctuationCleanupMode.legacyRemovePunctuationKey))

            PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
            XCTAssertEqual(defaults.string(forKey: PunctuationCleanupMode.userDefaultsKey), "removeAll")
            XCTAssertTrue(defaults.bool(forKey: PunctuationCleanupMode.legacyRemovePunctuationKey))
        }
    }

    func testCleanupConfigurationDefaultsToCurrentNoOpPolicy() {
        XCTAssertEqual(VoiceInkTranscriptionCleanupConfiguration.disabled.punctuationMode, .keep)
        XCTAssertFalse(VoiceInkTranscriptionCleanupConfiguration.disabled.shouldLowercase)
        XCTAssertFalse(VoiceInkTranscriptionCleanupConfiguration.disabled.shouldRemoveFillerWords)
        XCTAssertEqual(VoiceInkTranscriptionCleanupConfiguration.disabled.fillerWords, VoiceInkFillerWords.defaultWords)
    }

    func testCurrentCleanupConfigurationReadsSharedDefaults() {
        withIsolatedDefaults { defaults in
            PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
            defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
            defaults.set(true, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
            defaults.set(["um", "like"], forKey: VoiceInkUserDefaultsKey.fillerWords)

            XCTAssertEqual(
                VoiceInkTranscriptionCleanupConfiguration.current(in: defaults),
                VoiceInkTranscriptionCleanupConfiguration(
                    punctuationMode: .removeTrailingPeriod,
                    shouldLowercase: true,
                    shouldRemoveFillerWords: true,
                    fillerWords: ["um", "like"]
                )
            )
        }
    }

    func testCurrentCleanupConfigurationUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionCleanupConfiguration.current(in: defaults),
                VoiceInkTranscriptionCleanupConfiguration(
                    punctuationMode: .keep,
                    shouldLowercase: VoiceInkPreferenceDefault.lowercaseTranscription,
                    shouldRemoveFillerWords: VoiceInkPreferenceDefault.removeFillerWords,
                    fillerWords: VoiceInkFillerWords.defaultWords
                )
            )
        }
    }

    func testRemoveTrailingPeriodPreservesEllipsisAndTrailingWhitespace() {
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupPreferences.removeTrailingPeriod(from: "Ship it.  "),
            "Ship it  "
        )
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupPreferences.removeTrailingPeriod(from: "Wait..."),
            "Wait..."
        )
    }

    func testRemovePunctuationDropsApostrophesAndNormalizesInlineWhitespace() {
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupPreferences.removePunctuation(from: "Felix's note: ship, test, release."),
            "Felixs note ship test release"
        )
    }

    func testApplyRunsPunctuationCleanupBeforeLowercasing() {
        XCTAssertEqual(
            VoiceInkTranscriptionCleanupPreferences.apply(
                "Ship, PLEASE.",
                punctuationMode: .removeAll,
                shouldLowercase: true
            ),
            "ship please"
        )
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.TranscriptionCleanupPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
