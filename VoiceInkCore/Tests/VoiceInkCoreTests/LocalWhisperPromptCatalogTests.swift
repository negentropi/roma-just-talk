import Foundation
@testable import VoiceInkCore

final class LocalWhisperPromptCatalogTests: XCTestCase {
    func testCustomLanguagePromptsKeyPreservesExistingMacOSStorageName() {
        XCTAssertEqual(VoiceInkLocalWhisperPromptCatalog.customLanguagePromptsKey, "CustomLanguagePrompts")
    }

    func testMacOSPromptSettingsPresentationPreservesExistingCopy() {
        let presentation = VoiceInkLocalWhisperPromptCatalog.macOSSettingsPresentation

        XCTAssertEqual(presentation.sectionTitle, "Output Format")
        XCTAssertEqual(
            presentation.helpText,
            "Only supported for local Whisper models. Unlike GPT, Voice Models(whisper) follows the style of your prompt rather than instructions. Use examples of your desired output format instead of commands."
        )
        XCTAssertEqual(
            presentation.learnMoreURLString,
            "https://cookbook.openai.com/examples/whisper_prompting_guide#comparison-with-gpt-prompting"
        )
        XCTAssertEqual(presentation.saveButtonTitle, "Save")
        XCTAssertEqual(presentation.editButtonTitle, "Edit")
    }

    func testPromptDraftStateOwnsMacOSEditSaveAndLanguageRefresh() {
        let draftState = VoiceInkLocalWhisperPromptDraftState()

        XCTAssertEqual(draftState, VoiceInkLocalWhisperPromptDraftState(text: "", isEditing: false))

        let editingState = draftState.editing(prompt: "Use sentence case.")
        XCTAssertEqual(
            editingState,
            VoiceInkLocalWhisperPromptDraftState(text: "Use sentence case.", isEditing: true)
        )

        XCTAssertEqual(
            editingState.refreshingForSelectedLanguage(prompt: "Use French punctuation."),
            VoiceInkLocalWhisperPromptDraftState(text: "Use French punctuation.", isEditing: true)
        )

        let savedState = editingState.saved()
        XCTAssertEqual(
            savedState,
            VoiceInkLocalWhisperPromptDraftState(text: "Use sentence case.", isEditing: false)
        )

        XCTAssertEqual(
            savedState.refreshingForSelectedLanguage(prompt: "Use German punctuation."),
            savedState
        )
    }

    func testDefaultPromptsPreserveExistingMacOSLanguageSeeds() {
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "en"),
            "Hello, how are you doing? Nice to meet you."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "ja"),
            "こんにちは、お元気ですか？お会いできて嬉しいです。"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "he"),
            ",שלום, מה שלומך? נעים להכיר"
        )
    }

    func testPromptUsesCustomPromptWhenAvailable() {
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.prompt(
                for: "en",
                customPrompts: ["en": "Spell Roma Just Talk exactly."]
            ),
            "Spell Roma Just Talk exactly."
        )
    }

    func testPromptFallsBackToDefaultWhenCustomPromptIsEmptyOrLanguageIsMissing() {
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.prompt(for: "en", customPrompts: ["en": ""]),
            "Hello, how are you doing? Nice to meet you."
        )
        XCTAssertEqual(VoiceInkLocalWhisperPromptCatalog.prompt(for: "xx"), "")
    }

    func testPromptForSelectedLanguageUsesSharedLanguageKeyAndFallbackLanguage() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Hello, how are you doing? Nice to meet you."
            )

            defaults.set("fr", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Bonjour, comment allez-vous? Ravi de vous rencontrer."
            )
        }
    }

    func testStoredCustomPromptsRoundTrip() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults), [:])

            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(
                ["en": "Spell Roma Just Talk exactly."],
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults),
                ["en": "Spell Roma Just Talk exactly."]
            )
        }
    }

    func testSaveCustomPromptUpdatesOneLanguageAndPreservesOthers() {
        withIsolatedDefaults { defaults in
            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(
                ["fr": "Use French punctuation."],
                to: defaults
            )

            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompt(
                "Spell Roma Just Talk exactly.",
                for: "en",
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults),
                [
                    "en": "Spell Roma Just Talk exactly.",
                    "fr": "Use French punctuation."
                ]
            )
        }
    }

    func testPromptForSelectedLanguageUsesStoredCustomPromptsByDefault() {
        withIsolatedDefaults { defaults in
            defaults.set("en", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(
                ["en": "Spell Roma Just Talk exactly."],
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Spell Roma Just Talk exactly."
            )

            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults, customPrompts: [:]),
                "Hello, how are you doing? Nice to meet you."
            )
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.LocalWhisperPromptCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
