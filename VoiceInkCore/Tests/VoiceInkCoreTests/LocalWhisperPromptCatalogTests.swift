import Foundation
@testable import VoiceInkCore

final class LocalWhisperPromptCatalogTests: XCTestCase {
    func testCustomLanguagePromptsKeyPreservesExistingMacOSStorageName() {
        XCTAssertEqual(VoiceInkLocalWhisperPromptCatalog.customLanguagePromptsKey, "CustomLanguagePrompts")
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

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.LocalWhisperPromptCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
