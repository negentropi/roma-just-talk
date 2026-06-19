import Foundation
@testable import VoiceInkCore

final class EnhancementSettingsPresentationTests: XCTestCase {
    func testMacOSEnhancementSettingsPresentationPreservesCopy() {
        let presentation = VoiceInkEnhancementSettingsPresentation.macOS

        XCTAssertEqual(presentation.title, "Enhancement Settings")
        XCTAssertEqual(presentation.closeButtonHelp, "Close")
        XCTAssertEqual(presentation.generalSectionTitle, "General")
        XCTAssertEqual(presentation.enableEnhancementTitle, "Enable Enhancement")
        XCTAssertEqual(
            presentation.enableEnhancementHelp,
            "AI enhancement lets you pass the transcribed audio through LLMs to post-process using different prompts suitable for different use cases like e-mails, summary, writing, etc."
        )
        XCTAssertEqual(
            presentation.enableEnhancementLearnMoreURLString,
            "https://tryvoiceink.com/docs/enhancements-configuring-models"
        )
        XCTAssertEqual(presentation.settingsButtonSystemImageName, "gear")
        XCTAssertEqual(presentation.settingsButtonHelp, "Enhancement settings")
        XCTAssertEqual(presentation.promptsSectionTitle, "Enhancement Prompts")
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
        XCTAssertEqual(presentation.toggleEnhancementShortcutTitle, "Toggle AI Enhancement")
        XCTAssertEqual(
            presentation.toggleEnhancementShortcutHelp,
            "Quickly enable or disable AI enhancement while recording. Available only when VoiceInk is running and the recorder is visible."
        )
        XCTAssertEqual(presentation.switchPromptShortcutTitle, "Switch Enhancement Prompt")
        XCTAssertEqual(
            presentation.switchPromptShortcutHelp,
            "Switch between your saved prompts using ⌘1 through ⌘0 to activate the corresponding prompt in the order they are saved. Available only when VoiceInk is running and the recorder is visible."
        )
        XCTAssertEqual(presentation.shortcutLearnMoreURLString, "https://tryvoiceink.com/docs/enhancement-shortcuts")
        XCTAssertEqual(presentation.switchPromptKeyChipTitles, ["⌘", "1 – 0"])
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
