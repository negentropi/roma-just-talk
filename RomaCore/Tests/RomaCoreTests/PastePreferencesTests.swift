import Foundation
import RomaCore

final class PastePreferencesTests: XCTestCase {
    func testFinalPastedTextReturnsTranscriptWithoutTrailingSpace() {
        let pastedText = RomaTranscriptionPasteOutputPolicy.finalPastedText(
            "hello",
            appendTrailingSpace: false
        )

        XCTAssertEqual(pastedText, "hello")
    }

    func testFinalPastedTextAppendsTrailingSpaceWhenEnabled() {
        let pastedText = RomaTranscriptionPasteOutputPolicy.finalPastedText(
            "hello",
            appendTrailingSpace: true
        )

        XCTAssertEqual(pastedText, "hello ")
    }

    func testCursorPasteTextPlanSkipsCursorReadWhenLowercaseCleanupIsEnabled() {
        let plan = RomaTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            "Hello there",
            shouldLowercase: true
        )

        XCTAssertFalse(plan.shouldReadCursorContext)
        XCTAssertEqual(plan.text(beforeCursor: "mid sentence "), "Hello there")
    }

    func testCursorPasteTextPlanSkipsCursorReadForUncasedText() {
        let plan = RomaTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            "12345",
            shouldLowercase: false
        )

        XCTAssertFalse(plan.shouldReadCursorContext)
        XCTAssertEqual(plan.text(beforeCursor: "mid sentence "), "12345")
    }

    func testCursorPasteTextPlanAppliesSharedCapitalizationWithCursorContext() {
        let plan = RomaTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            "Hello there",
            shouldLowercase: false
        )

        XCTAssertTrue(plan.shouldReadCursorContext)
        XCTAssertEqual(plan.text(beforeCursor: "mid sentence "), "hello there")
        XCTAssertEqual(plan.text(beforeCursor: "Sentence ended. "), "Hello there")
    }

    func testLowercasesTitlecaseTextAfterMidSentencePrefix() {
        let result = RomaContextualCapitalizationFormatter.format(
            "Model output",
            beforeCursor: "this is the "
        )

        XCTAssertEqual(result, "model output")
    }

    func testKeepsTitlecaseTextAfterSentenceBoundary() {
        let result = RomaContextualCapitalizationFormatter.format(
            "Model output",
            beforeCursor: "this is done. "
        )

        XCTAssertEqual(result, "Model output")
    }

    func testCapitalizesLowercaseTextAtDocumentStart() {
        let result = RomaContextualCapitalizationFormatter.format(
            "model output",
            beforeCursor: ""
        )

        XCTAssertEqual(result, "Model output")
    }

    func testPreservesAcronymsAfterMidSentencePrefix() {
        let result = RomaContextualCapitalizationFormatter.format(
            "API response",
            beforeCursor: "call the "
        )

        XCTAssertEqual(result, "API response")
    }

    func testSkipsCursorContextWhenTextCannotChange() {
        XCTAssertFalse(RomaContextualCapitalizationFormatter.needsCursorContext("API response"))
        XCTAssertFalse(RomaContextualCapitalizationFormatter.needsCursorContext("iPhone setup"))
        XCTAssertFalse(RomaContextualCapitalizationFormatter.needsCursorContext("1234"))
    }

    func testReadsCursorContextWhenTextCanChange() {
        XCTAssertTrue(RomaContextualCapitalizationFormatter.needsCursorContext("Model output"))
        XCTAssertTrue(RomaContextualCapitalizationFormatter.needsCursorContext("model output"))
    }

    func testCursorPasteTextPlanReadsLowercaseCleanupPreference() {
        withTemporaryDefaults { defaults in
            RomaTranscriptionCleanupPreferenceStorage.clearTextPreferences(from: defaults)

            XCTAssertTrue(
                RomaTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
                    "Hello there",
                    from: defaults
                ).shouldReadCursorContext
            )

            RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)

            XCTAssertFalse(
                RomaTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
                    "Hello there",
                    from: defaults
                ).shouldReadCursorContext
            )
        }
    }

    func testAppendTrailingSpacePreferencePreservesStorageAndDefault() {
        withTemporaryDefaults { defaults in
            RomaAppendTrailingSpacePreference.clear(from: defaults)

            XCTAssertEqual(RomaUserDefaultsKey.appendTrailingSpace, "AppendTrailingSpace")
            XCTAssertEqual(RomaAppendTrailingSpacePreference.userDefaultsKey, "AppendTrailingSpace")
            XCTAssertTrue(RomaAppendTrailingSpacePreference.defaultIsEnabled)
            XCTAssertEqual(
                RomaAppendTrailingSpacePreference.registeredDefaults[
                    RomaAppendTrailingSpacePreference.userDefaultsKey
                ] as? Bool,
                true
            )
            XCTAssertTrue(RomaAppendTrailingSpacePreference.isEnabled(from: defaults))

            RomaAppendTrailingSpacePreference.saveIsEnabled(false, to: defaults)
            XCTAssertFalse(RomaAppendTrailingSpacePreference.isEnabled(from: defaults))
        }
    }

    func testAppendTrailingSpacePreferencePreservesMacOSSettingsPresentation() {
        let presentation = RomaAppendTrailingSpacePreference.macOSSettingsPresentation

        XCTAssertEqual(presentation.toggleTitle, "Add Space After Paste")
        XCTAssertEqual(presentation.helpText, "Add a trailing space after pasted transcription output.")
    }

    func testCursorTextContextPolicyPreservesMacOSAccessibilityReadBounds() {
        XCTAssertEqual(RomaCursorTextContextPolicy.defaultMaximumLength, 240)
        XCTAssertEqual(RomaCursorTextContextPolicy.parentTraversalLimit, 4)
        XCTAssertTrue(RomaCursorTextContextPolicy.shouldAttemptRead(maximumLength: 1))
        XCTAssertFalse(RomaCursorTextContextPolicy.shouldAttemptRead(maximumLength: 0))
        XCTAssertFalse(RomaCursorTextContextPolicy.shouldAttemptRead(maximumLength: -1))
    }

    func testCursorTextContextPolicyOwnsTextInputRoles() {
        XCTAssertTrue(RomaCursorTextContextPolicy.isTextInputRole("AXTextField"))
        XCTAssertTrue(RomaCursorTextContextPolicy.isTextInputRole("AXTextArea"))
        XCTAssertTrue(RomaCursorTextContextPolicy.isTextInputRole("AXComboBox"))
        XCTAssertFalse(RomaCursorTextContextPolicy.isTextInputRole("AXButton"))
        XCTAssertFalse(RomaCursorTextContextPolicy.isTextInputRole(nil))
    }

    func testCursorTextContextPolicyBoundsPrefixLength() {
        XCTAssertEqual(
            RomaCursorTextContextPolicy.prefixLength(cursorLocation: 120, maximumLength: 240),
            120
        )
        XCTAssertEqual(
            RomaCursorTextContextPolicy.prefixLength(cursorLocation: 300, maximumLength: 240),
            240
        )
        XCTAssertEqual(
            RomaCursorTextContextPolicy.prefixLength(cursorLocation: 0, maximumLength: 240),
            0
        )
        XCTAssertNil(RomaCursorTextContextPolicy.prefixLength(cursorLocation: -1, maximumLength: 240))
        XCTAssertNil(RomaCursorTextContextPolicy.prefixLength(cursorLocation: 1, maximumLength: 0))
    }

    func testCursorTextContextPolicyBoundsValueSuffixToTextInputRoles() {
        XCTAssertEqual(
            RomaCursorTextContextPolicy.boundedSuffix("hello world", maximumLength: 5),
            "world"
        )
        XCTAssertNil(RomaCursorTextContextPolicy.boundedSuffix(nil, maximumLength: 5))
        XCTAssertNil(RomaCursorTextContextPolicy.boundedSuffix("hello", maximumLength: 0))

        XCTAssertEqual(
            RomaCursorTextContextPolicy.valueSuffix(
                from: "hello",
                role: "AXTextField",
                maximumLength: 10
            ),
            "hello"
        )
        XCTAssertEqual(
            RomaCursorTextContextPolicy.valueSuffix(
                from: "hello world",
                role: "AXTextArea",
                maximumLength: 5
            ),
            "world"
        )
        XCTAssertNil(
            RomaCursorTextContextPolicy.valueSuffix(
                from: "hello",
                role: "AXButton",
                maximumLength: 10
            )
        )
        XCTAssertNil(
            RomaCursorTextContextPolicy.valueSuffix(
                from: "hello",
                role: "AXTextField",
                maximumLength: 0
            )
        )
    }

    func testPasteMethodPreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(RomaPasteMethod.standard.rawValue, "default")
        XCTAssertEqual(RomaPasteMethod.appleScript.rawValue, "appleScript")
        XCTAssertEqual(RomaPasteMethod.standard.displayName, "Default")
        XCTAssertEqual(RomaPasteMethod.appleScript.displayName, "AppleScript")
        XCTAssertEqual(RomaPasteMethod.userDefaultsKey, "pasteMethod")
        XCTAssertEqual(RomaPasteMethod.legacyAppleScriptPasteKey, "useAppleScriptPaste")
    }

    func testPasteMethodCurrentUsesStoredMethodBeforeLegacyFlag() {
        withTemporaryDefaults { defaults in
            defaults.set(RomaPasteMethod.standard.rawValue, forKey: RomaPasteMethod.userDefaultsKey)
            defaults.set(true, forKey: RomaPasteMethod.legacyAppleScriptPasteKey)

            XCTAssertEqual(RomaPasteMethod.current(in: defaults), .standard)
        }
    }

    func testPasteMethodCurrentFallsBackToLegacyAppleScriptFlag() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: RomaPasteMethod.legacyAppleScriptPasteKey)

            XCTAssertEqual(RomaPasteMethod.current(in: defaults), .appleScript)
        }
    }

    func testPasteMethodSelectionFromStoredRawValueUsesValidMethodBeforeDefaults() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: RomaPasteMethod.legacyAppleScriptPasteKey)

            XCTAssertEqual(
                RomaPasteMethod.selection(fromStoredRawValue: RomaPasteMethod.standard.rawValue, in: defaults),
                .standard
            )
        }
    }

    func testPasteMethodSelectionFromStoredRawValueFallsBackToLegacyDefaults() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: RomaPasteMethod.legacyAppleScriptPasteKey)

            XCTAssertEqual(
                RomaPasteMethod.selection(fromStoredRawValue: "unknown", in: defaults),
                .appleScript
            )
        }
    }

    func testSetCurrentWritesModernAndLegacyCompatibilityKeys() {
        withTemporaryDefaults { defaults in
            RomaPasteMethod.setCurrent(.appleScript, in: defaults)

            XCTAssertEqual(defaults.string(forKey: RomaPasteMethod.userDefaultsKey), "appleScript")
            XCTAssertTrue(defaults.bool(forKey: RomaPasteMethod.legacyAppleScriptPasteKey))

            RomaPasteMethod.setCurrent(.standard, in: defaults)

            XCTAssertEqual(defaults.string(forKey: RomaPasteMethod.userDefaultsKey), "default")
            XCTAssertFalse(defaults.bool(forKey: RomaPasteMethod.legacyAppleScriptPasteKey))
        }
    }

    func testMigrateLegacyUserDefaultWritesModernMethodWhenMissing() {
        withTemporaryDefaults { defaults in
            defaults.set(true, forKey: RomaPasteMethod.legacyAppleScriptPasteKey)

            RomaPasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)

            XCTAssertEqual(defaults.string(forKey: RomaPasteMethod.userDefaultsKey), "appleScript")
            XCTAssertTrue(defaults.bool(forKey: RomaPasteMethod.legacyAppleScriptPasteKey))
        }
    }

    func testMigrateLegacyUserDefaultDoesNotOverwriteValidModernMethod() {
        withTemporaryDefaults { defaults in
            defaults.set(RomaPasteMethod.standard.rawValue, forKey: RomaPasteMethod.userDefaultsKey)
            defaults.set(true, forKey: RomaPasteMethod.legacyAppleScriptPasteKey)

            RomaPasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)

            XCTAssertEqual(defaults.string(forKey: RomaPasteMethod.userDefaultsKey), "default")
            XCTAssertTrue(defaults.bool(forKey: RomaPasteMethod.legacyAppleScriptPasteKey))
        }
    }

    func testPastePreferenceKeysDefaultsAndRegisteredDefaults() {
        XCTAssertEqual(RomaPastePreference.restoreClipboardAfterPasteKey, "restoreClipboardAfterPaste")
        XCTAssertEqual(RomaPastePreference.clipboardRestoreDelayKey, "clipboardRestoreDelay")
        XCTAssertTrue(RomaPastePreference.defaultRestoreClipboardAfterPaste)
        XCTAssertEqual(RomaPastePreference.defaultClipboardRestoreDelay, 2.0)
        XCTAssertEqual(RomaPastePreference.minimumClipboardRestoreDelay, 0.25)
        XCTAssertEqual(
            RomaPastePreference.registeredDefaults[RomaPastePreference.restoreClipboardAfterPasteKey] as? Bool,
            true
        )
        XCTAssertEqual(
            RomaPastePreference.registeredDefaults[RomaPastePreference.clipboardRestoreDelayKey] as? TimeInterval,
            2.0
        )
        XCTAssertEqual(
            RomaPastePreference.registeredDefaults[RomaPasteMethod.legacyAppleScriptPasteKey] as? Bool,
            false
        )
        XCTAssertNil(RomaPastePreference.registeredDefaults[RomaPasteMethod.userDefaultsKey])
    }

    func testPastePreferenceReadsSavesAndBoundsRestoreDelay() {
        withTemporaryDefaults { defaults in
            RomaPastePreference.saveShouldRestoreClipboardAfterPaste(true, to: defaults)
            RomaPastePreference.saveClipboardRestoreDelay(0.1, to: defaults)

            XCTAssertTrue(RomaPastePreference.shouldRestoreClipboardAfterPaste(from: defaults))
            XCTAssertEqual(RomaPastePreference.clipboardRestoreDelay(from: defaults), 0.1)
            XCTAssertEqual(RomaPastePreference.boundedClipboardRestoreDelay(from: defaults), 0.25)

            RomaPastePreference.saveClipboardRestoreDelay(3.0, to: defaults)
            XCTAssertEqual(RomaPastePreference.boundedClipboardRestoreDelay(from: defaults), 3.0)
        }
    }

    func testBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            RomaPastePreference.backupPreferences(
                shouldRestoreClipboardAfterPaste: false,
                clipboardRestoreDelay: 4.0
            ),
            RomaPasteBackupPreferences(
                shouldRestoreClipboardAfterPaste: false,
                clipboardRestoreDelay: 4.0
            )
        )
    }

    func testBackupImportPlanPreservesOptionalRestorePolicy() {
        XCTAssertEqual(
            RomaPastePreference.backupImportPlan(
                from: RomaPasteBackupPreferences(
                    shouldRestoreClipboardAfterPaste: true,
                    clipboardRestoreDelay: 0.1
                )
            ),
            RomaPasteBackupImportPlan(
                shouldRestoreClipboardAfterPaste: true,
                clipboardRestoreDelay: 0.1
            )
        )

        XCTAssertEqual(
            RomaPastePreference.backupImportPlan(
                from: RomaPasteBackupPreferences(
                    shouldRestoreClipboardAfterPaste: nil,
                    clipboardRestoreDelay: nil
                )
            ),
            RomaPasteBackupImportPlan(
                shouldRestoreClipboardAfterPaste: nil,
                clipboardRestoreDelay: nil
            )
        )
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "RomaCore.PastePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
    }
}
