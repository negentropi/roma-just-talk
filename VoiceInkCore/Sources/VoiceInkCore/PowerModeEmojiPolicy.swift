import Foundation

public enum VoiceInkPowerModeCustomEmojiAddResult: Equatable, Sendable {
    case added(emoji: String, customEmojis: [String])
    case empty
    case invalid
    case duplicate
}

public enum VoiceInkPowerModeEmojiCatalog {
    public static let customEmojisKey = "userAddedEmojis"
    public static let defaultEmojis = ["🏢", "🏠", "💼", "🎮", "📱", "📺", "🎵", "📚", "✏️", "🎨", "🧠", "⚙️", "💻", "🌐", "📝", "📊", "🔍", "💬", "📈", "🔧"]

    public static func customEmojis(from defaults: UserDefaults = .standard) -> [String] {
        defaults.array(forKey: customEmojisKey) as? [String] ?? []
    }

    public static func saveCustomEmojis(
        _ customEmojis: [String],
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(customEmojis, forKey: customEmojisKey)
    }

    public static func allEmojis(customEmojis: [String]) -> [String] {
        defaultEmojis + customEmojis
    }

    public static func isCustomEmoji(_ emoji: String, customEmojis: [String]) -> Bool {
        customEmojis.contains(emoji)
    }

    public static func addCustomEmoji(
        _ emoji: String,
        customEmojis: [String]
    ) -> VoiceInkPowerModeCustomEmojiAddResult {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmoji.isEmpty else {
            return .empty
        }

        guard isValidEmoji(trimmedEmoji) else {
            return .invalid
        }

        guard !allEmojis(customEmojis: customEmojis).contains(trimmedEmoji) else {
            return .duplicate
        }

        return .added(emoji: trimmedEmoji, customEmojis: customEmojis + [trimmedEmoji])
    }

    public static func removeCustomEmoji(
        _ emoji: String,
        customEmojis: [String]
    ) -> [String]? {
        guard let index = customEmojis.firstIndex(of: emoji) else {
            return nil
        }

        var updatedEmojis = customEmojis
        updatedEmojis.remove(at: index)
        return updatedEmojis
    }

    public static func isValidEmoji(_ value: String) -> Bool {
        guard !value.isEmpty, value.count == 1, let character = value.first else {
            return false
        }

        let scalars = character.unicodeScalars
        if scalars.count > 1 {
            return scalars.contains { $0.properties.isEmoji }
        }
        return scalars.first?.properties.isEmojiPresentation == true
    }

    public static func firstValidEmojiCharacter(in value: String) -> String {
        for character in value {
            let emoji = String(character)
            if isValidEmoji(emoji) {
                return emoji
            }
        }
        return ""
    }
}

public enum VoiceInkPowerModeEmojiInputPresentation {
    public static let customEmojiFieldPlaceholder = "➕"
    public static let addButtonTitle = "Add"
    public static let cancelButtonTitle = "Cancel"
    public static let tipText = "Tip: Use ⌃⌘Space for emoji picker or paste an emoji."
    public static let addEmojiAccessibilityLabel = "Add Emoji"
    public static let addCustomEmojiHelpText = "Add custom emoji"
    public static let emptySubmitMessage = "Emoji cannot be empty."
    public static let invalidPreviewMessage = "Invalid emoji."
    public static let invalidSubmitMessage = "Invalid emoji character."
    public static let duplicateMessage = "Emoji already exists!"

    public static func isErrorMessage(_ message: String) -> Bool {
        message == duplicateMessage
            || message == invalidPreviewMessage
            || message == invalidSubmitMessage
            || message == emptySubmitMessage
    }
}
