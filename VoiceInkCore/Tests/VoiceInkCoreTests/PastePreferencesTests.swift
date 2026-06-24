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

    func testPasteMethodSelectionFromStoredRawValueUsesValidMethodBeforeDefaults() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey)

            XCTAssertEqual(
                VoiceInkPasteMethod.selection(fromStoredRawValue: VoiceInkPasteMethod.standard.rawValue, in: defaults),
                .standard
            )
        }
    }

    func testPasteMethodSelectionFromStoredRawValueFallsBackToLegacyDefaults() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey)

            XCTAssertEqual(
                VoiceInkPasteMethod.selection(fromStoredRawValue: "unknown", in: defaults),
                .appleScript
            )
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

    func testMacOSPasteSettingsPresentationPreservesCopyAndRestoreDelayOptions() {
        let presentation = VoiceInkPastePreference.macOSSettingsPresentation

        XCTAssertEqual(presentation.keepClipboardContentLabel, "Keep Clipboard Content")
        XCTAssertEqual(
            presentation.keepClipboardContentInfoMessage,
            "VoiceInk temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay. When disabled, the pasted transcription stays on your clipboard."
        )
        XCTAssertEqual(presentation.restoreDelayLabel, "Restore Delay")
        XCTAssertEqual(
            presentation.restoreDelayOptions,
            [
                VoiceInkPasteDelayOption(label: "250ms", value: 0.25),
                VoiceInkPasteDelayOption(label: "500ms", value: 0.5),
                VoiceInkPasteDelayOption(label: "1s", value: 1.0),
                VoiceInkPasteDelayOption(label: "2s", value: 2.0),
                VoiceInkPasteDelayOption(label: "3s", value: 3.0),
                VoiceInkPasteDelayOption(label: "4s", value: 4.0),
                VoiceInkPasteDelayOption(label: "5s", value: 5.0)
            ]
        )
        XCTAssertEqual(presentation.pasteMethodLabel, "Paste Method")
        XCTAssertEqual(
            presentation.pasteMethodHelpMessage,
            "Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly."
        )
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

    func testBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            VoiceInkPastePreference.backupPreferences(
                shouldRestoreClipboardAfterPaste: false,
                clipboardRestoreDelay: 4.0
            ),
            VoiceInkPasteBackupPreferences(
                shouldRestoreClipboardAfterPaste: false,
                clipboardRestoreDelay: 4.0
            )
        )
    }

    func testBackupImportPlanPreservesOptionalRestorePolicy() {
        XCTAssertEqual(
            VoiceInkPastePreference.backupImportPlan(
                from: VoiceInkPasteBackupPreferences(
                    shouldRestoreClipboardAfterPaste: true,
                    clipboardRestoreDelay: 0.1
                )
            ),
            VoiceInkPasteBackupImportPlan(
                shouldRestoreClipboardAfterPaste: true,
                clipboardRestoreDelay: 0.1
            )
        )

        XCTAssertEqual(
            VoiceInkPastePreference.backupImportPlan(
                from: VoiceInkPasteBackupPreferences(
                    shouldRestoreClipboardAfterPaste: nil,
                    clipboardRestoreDelay: nil
                )
            ),
            VoiceInkPasteBackupImportPlan(
                shouldRestoreClipboardAfterPaste: nil,
                clipboardRestoreDelay: nil
            )
        )
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
