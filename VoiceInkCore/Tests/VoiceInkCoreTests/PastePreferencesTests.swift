import Foundation
@testable import VoiceInkCore

final class PastePreferencesTests: XCTestCase {
    func testPasteMethodPreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(VoiceInkPasteMethod.standard.rawValue, "default")
        XCTAssertEqual(VoiceInkPasteMethod.appleScript.rawValue, "appleScript")
        XCTAssertEqual(VoiceInkPasteMethod.standard.displayName, "Default")
        XCTAssertEqual(VoiceInkPasteMethod.appleScript.displayName, "AppleScript")
        XCTAssertEqual(VoiceInkPasteMethod.userDefaultsKey, "pasteMethod")
        XCTAssertEqual(VoiceInkPasteMethod.legacyAppleScriptPasteKey, "useAppleScriptPaste")
    }

    func testPasteMethodCurrentUsesStoredMethodBeforeLegacyFlag() {
        withTemporaryDefaults { defaults in
            defaults.set(VoiceInkPasteMethod.standard.rawValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
            defaults.set(true, forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey)

            XCTAssertEqual(VoiceInkPasteMethod.current(in: defaults), .standard)
        }
    }

    func testPasteMethodCurrentFallsBackToLegacyAppleScriptFlag() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey)

            XCTAssertEqual(VoiceInkPasteMethod.current(in: defaults), .appleScript)
        }
    }

    func testSetCurrentWritesModernAndLegacyCompatibilityKeys() {
        withTemporaryDefaults { defaults in
            VoiceInkPasteMethod.setCurrent(.appleScript, in: defaults)

            XCTAssertEqual(defaults.string(forKey: VoiceInkPasteMethod.userDefaultsKey), "appleScript")
            XCTAssertTrue(defaults.bool(forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey))

            VoiceInkPasteMethod.setCurrent(.standard, in: defaults)

            XCTAssertEqual(defaults.string(forKey: VoiceInkPasteMethod.userDefaultsKey), "default")
            XCTAssertFalse(defaults.bool(forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey))
        }
    }

    func testMigrateLegacyUserDefaultWritesModernMethodWhenMissing() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey)

            VoiceInkPasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)

            XCTAssertEqual(defaults.string(forKey: VoiceInkPasteMethod.userDefaultsKey), "appleScript")
            XCTAssertTrue(defaults.bool(forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey))
        }
    }

    func testMigrateLegacyUserDefaultDoesNotOverwriteValidModernMethod() {
        withTemporaryDefaults { defaults in
            defaults.set(VoiceInkPasteMethod.standard.rawValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
            defaults.set(true, forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey)

            VoiceInkPasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)

            XCTAssertEqual(defaults.string(forKey: VoiceInkPasteMethod.userDefaultsKey), "default")
            XCTAssertTrue(defaults.bool(forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey))
        }
    }

    func testPastePreferenceKeysDefaultsAndRegisteredDefaults() {
        XCTAssertEqual(VoiceInkPastePreference.restoreClipboardAfterPasteKey, "restoreClipboardAfterPaste")
        XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelayKey, "clipboardRestoreDelay")
        XCTAssertTrue(VoiceInkPastePreference.defaultRestoreClipboardAfterPaste)
        XCTAssertEqual(VoiceInkPastePreference.defaultClipboardRestoreDelay, 2.0)
        XCTAssertEqual(VoiceInkPastePreference.minimumClipboardRestoreDelay, 0.25)
        XCTAssertEqual(
            VoiceInkPastePreference.registeredDefaults[VoiceInkPastePreference.restoreClipboardAfterPasteKey] as? Bool,
            true
        )
        XCTAssertEqual(
            VoiceInkPastePreference.registeredDefaults[VoiceInkPastePreference.clipboardRestoreDelayKey] as? TimeInterval,
            2.0
        )
        XCTAssertEqual(
            VoiceInkPastePreference.registeredDefaults[VoiceInkPasteMethod.legacyAppleScriptPasteKey] as? Bool,
            false
        )
        XCTAssertNil(VoiceInkPastePreference.registeredDefaults[VoiceInkPasteMethod.userDefaultsKey])
    }

    func testPastePreferenceReadsSavesAndBoundsRestoreDelay() {
        withTemporaryDefaults { defaults in
            VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(true, to: defaults)
            VoiceInkPastePreference.saveClipboardRestoreDelay(0.1, to: defaults)

            XCTAssertTrue(VoiceInkPastePreference.shouldRestoreClipboardAfterPaste(from: defaults))
            XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 0.1)
            XCTAssertEqual(VoiceInkPastePreference.boundedClipboardRestoreDelay(from: defaults), 0.25)

            VoiceInkPastePreference.saveClipboardRestoreDelay(3.0, to: defaults)
            XCTAssertEqual(VoiceInkPastePreference.boundedClipboardRestoreDelay(from: defaults), 3.0)
        }
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.PastePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
    }
}
