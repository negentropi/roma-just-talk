import Foundation
import VoiceInkCore

class EmojiManager: ObservableObject {
    static let shared = EmojiManager()

    @Published var customEmojis: [String] = []

    private init() {
        loadCustomEmojis()
    }

    var allEmojis: [String] {
        VoiceInkPowerModeEmojiCatalog.allEmojis(customEmojis: customEmojis)
    }

    func addCustomEmoji(_ emoji: String) -> VoiceInkPowerModeCustomEmojiAddResult {
        let result = VoiceInkPowerModeEmojiCatalog.addCustomEmoji(
            emoji,
            customEmojis: customEmojis
        )

        if case .added(_, let updatedEmojis) = result {
            customEmojis = updatedEmojis
            saveCustomEmojis()
        }

        return result
    }

    private func loadCustomEmojis() {
        customEmojis = VoiceInkPowerModeEmojiCatalog.customEmojis()
    }

    private func saveCustomEmojis() {
        VoiceInkPowerModeEmojiCatalog.saveCustomEmojis(customEmojis)
    }

    func removeCustomEmoji(_ emoji: String) -> Bool {
        if let updatedEmojis = VoiceInkPowerModeEmojiCatalog.removeCustomEmoji(
            emoji,
            customEmojis: customEmojis
        ) {
            customEmojis = updatedEmojis
            saveCustomEmojis()
            return true
        }
        return false
    }

    func isCustomEmoji(_ emoji: String) -> Bool {
        VoiceInkPowerModeEmojiCatalog.isCustomEmoji(emoji, customEmojis: customEmojis)
    }

    func inputDraft(for rawText: String) -> VoiceInkPowerModeEmojiInputDraft {
        VoiceInkPowerModeEmojiInputPresentation.inputDraft(
            for: rawText,
            customEmojis: customEmojis
        )
    }
}
