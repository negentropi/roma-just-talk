import Foundation
@testable import VoiceInkCore

final class PastePreferencesTests: XCTestCase {
    func testFinalPastedTextReturnsTranscriptWithoutTrailingSpace() {
        let pastedText = VoiceInkTranscriptionPasteOutputPolicy.finalPastedText(
            "hello",
            appendTrailingSpace: false,
            isTrialExpired: false
        )

        XCTAssertEqual(pastedText, "hello")
    }

    func testFinalPastedTextAppendsTrailingSpaceWhenEnabled() {
        let pastedText = VoiceInkTranscriptionPasteOutputPolicy.finalPastedText(
            "hello",
            appendTrailingSpace: true,
            isTrialExpired: false
        )

        XCTAssertEqual(pastedText, "hello ")
    }

    func testFinalPastedTextPreservesTrialExpiredPrefixAndBlankLine() {
        let pastedText = VoiceInkTranscriptionPasteOutputPolicy.finalPastedText(
            "hello",
            appendTrailingSpace: false,
            isTrialExpired: true
        )

        XCTAssertEqual(
            pastedText,
            "Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy\n\nhello"
        )
    }

    func testCursorPasteTextPlanSkipsCursorReadWhenLowercaseCleanupIsEnabled() {
        let plan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            "Hello there",
            shouldLowercase: true
        )

        XCTAssertFalse(plan.shouldReadCursorContext)
        XCTAssertEqual(plan.text(beforeCursor: "mid sentence "), "Hello there")
    }

    func testCursorPasteTextPlanSkipsCursorReadForUncasedText() {
        let plan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            "12345",
            shouldLowercase: false
        )

        XCTAssertFalse(plan.shouldReadCursorContext)
        XCTAssertEqual(plan.text(beforeCursor: "mid sentence "), "12345")
    }

    func testCursorPasteTextPlanAppliesSharedCapitalizationWithCursorContext() {
        let plan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
            "Hello there",
            shouldLowercase: false
        )

        XCTAssertTrue(plan.shouldReadCursorContext)
        XCTAssertEqual(plan.text(beforeCursor: "mid sentence "), "hello there")
        XCTAssertEqual(plan.text(beforeCursor: "Sentence ended. "), "Hello there")
    }

    func testLowercasesTitlecaseTextAfterMidSentencePrefix() {
        let result = VoiceInkContextualCapitalizationFormatter.format(
            "Model output",
            beforeCursor: "this is the "
        )

        XCTAssertEqual(result, "model output")
    }

    func testKeepsTitlecaseTextAfterSentenceBoundary() {
        let result = VoiceInkContextualCapitalizationFormatter.format(
            "Model output",
            beforeCursor: "this is done. "
        )

        XCTAssertEqual(result, "Model output")
    }

    func testCapitalizesLowercaseTextAtDocumentStart() {
        let result = VoiceInkContextualCapitalizationFormatter.format(
            "model output",
            beforeCursor: ""
        )

        XCTAssertEqual(result, "Model output")
    }

    func testPreservesAcronymsAfterMidSentencePrefix() {
        let result = VoiceInkContextualCapitalizationFormatter.format(
            "API response",
            beforeCursor: "call the "
        )

        XCTAssertEqual(result, "API response")
    }

    func testSkipsCursorContextWhenTextCannotChange() {
        XCTAssertFalse(VoiceInkContextualCapitalizationFormatter.needsCursorContext("API response"))
        XCTAssertFalse(VoiceInkContextualCapitalizationFormatter.needsCursorContext("iPhone setup"))
        XCTAssertFalse(VoiceInkContextualCapitalizationFormatter.needsCursorContext("1234"))
    }

    func testReadsCursorContextWhenTextCanChange() {
        XCTAssertTrue(VoiceInkContextualCapitalizationFormatter.needsCursorContext("Model output"))
        XCTAssertTrue(VoiceInkContextualCapitalizationFormatter.needsCursorContext("model output"))
    }

    func testCursorPasteTextPlanReadsLowercaseCleanupPreference() {
        withTemporaryDefaults { defaults in
            VoiceInkTranscriptionCleanupPreferenceStorage.clearTextPreferences(from: defaults)

            XCTAssertTrue(
                VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
                    "Hello there",
                    from: defaults
                ).shouldReadCursorContext
            )

            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)

            XCTAssertFalse(
                VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(
                    "Hello there",
                    from: defaults
                ).shouldReadCursorContext
            )
        }
    }

    func testAppendTrailingSpacePreferencePreservesStorageAndDefault() {
        withTemporaryDefaults { defaults in
            VoiceInkAppendTrailingSpacePreference.clear(from: defaults)

            XCTAssertEqual(VoiceInkUserDefaultsKey.appendTrailingSpace, "AppendTrailingSpace")
            XCTAssertEqual(VoiceInkAppendTrailingSpacePreference.userDefaultsKey, "AppendTrailingSpace")
            XCTAssertTrue(VoiceInkAppendTrailingSpacePreference.defaultIsEnabled)
            XCTAssertEqual(
                VoiceInkAppendTrailingSpacePreference.registeredDefaults[
                    VoiceInkAppendTrailingSpacePreference.userDefaultsKey
                ] as? Bool,
                true
            )
            XCTAssertTrue(VoiceInkAppendTrailingSpacePreference.isEnabled(from: defaults))

            VoiceInkAppendTrailingSpacePreference.saveIsEnabled(false, to: defaults)
            XCTAssertFalse(VoiceInkAppendTrailingSpacePreference.isEnabled(from: defaults))
        }
    }

    func testAppendTrailingSpacePreferencePreservesMacOSSettingsPresentation() {
        let presentation = VoiceInkAppendTrailingSpacePreference.macOSSettingsPresentation

        XCTAssertEqual(presentation.toggleTitle, "Add Space After Paste")
        XCTAssertEqual(presentation.helpText, "Add a trailing space after pasted transcription output.")
    }

    func testCursorTextContextPolicyPreservesMacOSAccessibilityReadBounds() {
        XCTAssertEqual(VoiceInkCursorTextContextPolicy.defaultMaximumLength, 240)
        XCTAssertEqual(VoiceInkCursorTextContextPolicy.parentTraversalLimit, 4)
        XCTAssertTrue(VoiceInkCursorTextContextPolicy.shouldAttemptRead(maximumLength: 1))
        XCTAssertFalse(VoiceInkCursorTextContextPolicy.shouldAttemptRead(maximumLength: 0))
        XCTAssertFalse(VoiceInkCursorTextContextPolicy.shouldAttemptRead(maximumLength: -1))
    }

    func testCursorTextContextPolicyOwnsTextInputRoles() {
        XCTAssertTrue(VoiceInkCursorTextContextPolicy.isTextInputRole("AXTextField"))
        XCTAssertTrue(VoiceInkCursorTextContextPolicy.isTextInputRole("AXTextArea"))
        XCTAssertTrue(VoiceInkCursorTextContextPolicy.isTextInputRole("AXComboBox"))
        XCTAssertFalse(VoiceInkCursorTextContextPolicy.isTextInputRole("AXButton"))
        XCTAssertFalse(VoiceInkCursorTextContextPolicy.isTextInputRole(nil))
    }

    func testCursorTextContextPolicyBoundsPrefixLength() {
        XCTAssertEqual(
            VoiceInkCursorTextContextPolicy.prefixLength(cursorLocation: 120, maximumLength: 240),
            120
        )
        XCTAssertEqual(
            VoiceInkCursorTextContextPolicy.prefixLength(cursorLocation: 300, maximumLength: 240),
            240
        )
        XCTAssertEqual(
            VoiceInkCursorTextContextPolicy.prefixLength(cursorLocation: 0, maximumLength: 240),
            0
        )
        XCTAssertNil(VoiceInkCursorTextContextPolicy.prefixLength(cursorLocation: -1, maximumLength: 240))
        XCTAssertNil(VoiceInkCursorTextContextPolicy.prefixLength(cursorLocation: 1, maximumLength: 0))
    }

    func testCursorTextContextPolicyBoundsValueSuffixToTextInputRoles() {
        XCTAssertEqual(
            VoiceInkCursorTextContextPolicy.valueSuffix(
                from: "hello",
                role: "AXTextField",
                maximumLength: 10
            ),
            "hello"
        )
        XCTAssertEqual(
            VoiceInkCursorTextContextPolicy.valueSuffix(
                from: "hello world",
                role: "AXTextArea",
                maximumLength: 5
            ),
            "world"
        )
        XCTAssertNil(
            VoiceInkCursorTextContextPolicy.valueSuffix(
                from: "hello",
                role: "AXButton",
                maximumLength: 10
            )
        )
        XCTAssertNil(
            VoiceInkCursorTextContextPolicy.valueSuffix(
                from: "hello",
                role: "AXTextField",
                maximumLength: 0
            )
        )
    }

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

    func testPasteDiagnosticsPreserveMacOSLogCopy() {
        XCTAssertEqual(
            VoiceInkPasteDiagnostics.failedToPrepareClipboardMessage,
            "Failed to prepare clipboard for paste"
        )
        XCTAssertEqual(
            VoiceInkPasteDiagnostics.skippedClipboardRestoreCommandNotPostedMessage,
            "Skipping clipboard restore because paste command was not posted"
        )
        XCTAssertEqual(
            VoiceInkPasteDiagnostics.appleScriptPasteScriptUnavailableMessage,
            "AppleScript paste script is unavailable"
        )
        XCTAssertEqual(
            VoiceInkPasteDiagnostics.appleScriptPasteFailedMessage(errorDescription: "event denied"),
            "AppleScript paste failed: event denied"
        )
        XCTAssertEqual(
            VoiceInkPasteDiagnostics.accessibilityPermissionRequiredForSimulatedPasteMessage,
            "Accessibility permission is required to paste with simulated key events"
        )
        XCTAssertEqual(
            VoiceInkPasteDiagnostics.failedToCreateCommandVPasteEventsMessage,
            "Failed to create Cmd+V keyboard events"
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
