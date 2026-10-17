import Foundation
import RomaCore

class EmojiManager: ObservableObject {
    static let shared = EmojiManager()

    @Published var customEmojis: [String] = []

    private init() {
        customEmojis = RomaPowerModeEmojiCatalog.customEmojis()
    }

    var allEmojis: [String] {
        RomaPowerModeEmojiCatalog.allEmojis(customEmojis: customEmojis)
    }

    func addCustomEmoji(_ emoji: String) -> RomaPowerModeCustomEmojiAddResult {
        let result = RomaPowerModeEmojiCatalog.addCustomEmoji(
            emoji,
            customEmojis: customEmojis
        )

        if case .added(_, let updatedEmojis) = result {
            customEmojis = updatedEmojis
            RomaPowerModeEmojiCatalog.saveCustomEmojis(customEmojis)
        }

        return result
    }

    func removeCustomEmoji(_ emoji: String) -> Bool {
        if let updatedEmojis = RomaPowerModeEmojiCatalog.removeCustomEmoji(
            emoji,
            customEmojis: customEmojis
        ) {
            customEmojis = updatedEmojis
            RomaPowerModeEmojiCatalog.saveCustomEmojis(customEmojis)
            return true
        }
        return false
    }

    func isCustomEmoji(_ emoji: String) -> Bool {
        RomaPowerModeEmojiCatalog.isCustomEmoji(emoji, customEmojis: customEmojis)
    }

    func inputDraft(for rawText: String) -> RomaPowerModeEmojiInputDraft {
        RomaPowerModeEmojiInputPresentation.inputDraft(
            for: rawText,
            customEmojis: customEmojis
        )
    }
}
