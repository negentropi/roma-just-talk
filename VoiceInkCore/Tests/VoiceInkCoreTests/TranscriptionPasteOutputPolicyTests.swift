import Foundation
@testable import VoiceInkCore

final class TranscriptionPasteOutputPolicyTests: XCTestCase {
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

    func testCursorPasteTextPlanReadsLowercaseCleanupPreference() {
        let suiteName = "VoiceInkCore.TranscriptionPasteOutputPolicyTests.cursorPreference"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
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

    func testAppendTrailingSpacePreferencePreservesStorageAndDefault() {
        let suiteName = "VoiceInkCore.TranscriptionPasteOutputPolicyTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
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

    func testAppendTrailingSpacePreferencePreservesMacOSSettingsPresentation() {
        let presentation = VoiceInkAppendTrailingSpacePreference.macOSSettingsPresentation

        XCTAssertEqual(presentation.toggleTitle, "Add Space After Paste")
        XCTAssertEqual(presentation.helpText, "Add a trailing space after pasted transcription output.")
    }
}
