import Foundation
@testable import VoiceInkCore

final class EnhancementSettingsPresentationTests: XCTestCase {
    func testMacOSEnhancementSettingsPresentationPreservesCopy() {
        let presentation = VoiceInkEnhancementSettingsPresentation.macOS

        XCTAssertEqual(presentation.title, "Enhancement Settings")
        XCTAssertEqual(presentation.closeButtonHelp, "Close")
        XCTAssertEqual(presentation.contextSectionTitle, "Context")
        XCTAssertEqual(presentation.clipboardContextTitle, "Clipboard Context")
        XCTAssertEqual(presentation.clipboardContextHelp, "Use clipboard text to understand context for better enhancement.")
        XCTAssertEqual(presentation.screenContextTitle, "Screen Context")
        XCTAssertEqual(presentation.screenContextHelp, "Capture on-screen text to understand context for better enhancement.")
        XCTAssertEqual(presentation.skipShortEnhancementTitle, "Skip short transcriptions")
        XCTAssertEqual(
            presentation.skipShortEnhancementHelp,
            "Automatically skip AI enhancement when the transcription has very few words. Short phrases like \"yes\", \"thank you\", or quick commands don't benefit from enhancement."
        )
        XCTAssertEqual(presentation.disclosureSystemImageName, "chevron.right")
        XCTAssertEqual(presentation.minimumWordsPickerTitle, "Minimum words")
        XCTAssertEqual(presentation.timeoutPickerTitle, "Timeout duration")
        XCTAssertEqual(presentation.timeoutRetryPickerTitle, "On timeout")
        XCTAssertEqual(presentation.requestTimeoutSectionTitle, "Request Timeout")
        XCTAssertEqual(
            presentation.requestTimeoutHelp,
            "Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request (up to 3 attempts)."
        )
        XCTAssertEqual(presentation.shortcutsSectionTitle, "Shortcuts")
    }

    func testMacOSEnhancementSettingsPresentationPreservesOptions() {
        let presentation = VoiceInkEnhancementSettingsPresentation.macOS

        XCTAssertEqual(
            presentation.shortEnhancementWordOptions,
            (1...15).map {
                VoiceInkEnhancementIntegerOption(title: "\($0) \($0 == 1 ? "word" : "words")", value: $0)
            }
        )
        XCTAssertEqual(
            presentation.timeoutOptions,
            [3, 5, 7, 10, 15, 20, 30, 40, 50, 60].map {
                VoiceInkEnhancementIntegerOption(title: "\($0) seconds", value: $0)
            }
        )
        XCTAssertEqual(
            presentation.timeoutRetryOptions,
            [
                VoiceInkEnhancementRetryOption(title: "Fail immediately", value: false),
                VoiceInkEnhancementRetryOption(title: "Retry", value: true)
            ]
        )
    }
}
