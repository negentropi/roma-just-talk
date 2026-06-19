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

    func testAppendTrailingSpacePreferencePreservesStorageAndDefault() {
        let suiteName = "VoiceInkCore.TranscriptionPasteOutputPolicyTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        VoiceInkAppendTrailingSpacePreference.clear(from: defaults)

        XCTAssertEqual(VoiceInkUserDefaultsKey.appendTrailingSpace, "AppendTrailingSpace")
        XCTAssertTrue(VoiceInkAppendTrailingSpacePreference.isEnabled(from: defaults))

        VoiceInkAppendTrailingSpacePreference.saveIsEnabled(false, to: defaults)
        XCTAssertFalse(VoiceInkAppendTrailingSpacePreference.isEnabled(from: defaults))
    }
}
