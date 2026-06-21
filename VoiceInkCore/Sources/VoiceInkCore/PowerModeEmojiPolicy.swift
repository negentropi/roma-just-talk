import Foundation

public enum VoiceInkPowerModeCustomEmojiAddResult: Equatable, Sendable {
    case added(emoji: String, customEmojis: [String])
    case empty
    case invalid
    case duplicate

    public var addedEmoji: String? {
        guard case .added(let emoji, _) = self else {
            return nil
        }
        return emoji
    }
}

public struct VoiceInkPowerModeEmojiRemovalAlertPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let buttonTitle: String

    public init(title: String, message: String, buttonTitle: String) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
    }
}

public struct VoiceInkPowerModeEmojiInputDraft: Equatable, Sendable {
    public let text: String
    public let feedbackMessage: String
    public let canSubmit: Bool

    public init(text: String, feedbackMessage: String, canSubmit: Bool) {
        self.text = text
        self.feedbackMessage = feedbackMessage
        self.canSubmit = canSubmit
    }
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
    public static let addEmojiSystemImageName = "plus.circle.fill"
    public static let addCustomEmojiHelpText = "Add custom emoji"
    public static let removeCustomEmojiSystemImageName = "xmark.circle.fill"
    public static let emptySubmitMessage = "Emoji cannot be empty."
    public static let invalidPreviewMessage = "Invalid emoji."
    public static let invalidSubmitMessage = "Invalid emoji character."
    public static let duplicateMessage = "Emoji already exists!"
    public static let inUseAlertTitle = "Emoji in Use"
    public static let inUseAlertButtonTitle = "OK"

    public static func isErrorMessage(_ message: String) -> Bool {
        message == duplicateMessage
            || message == invalidPreviewMessage
            || message == invalidSubmitMessage
            || message == emptySubmitMessage
    }

    public static func inputDraft(
        for rawText: String,
        customEmojis: [String]
    ) -> VoiceInkPowerModeEmojiInputDraft {
        let text = VoiceInkPowerModeEmojiCatalog.firstValidEmojiCharacter(in: rawText)

        guard !text.isEmpty else {
            return VoiceInkPowerModeEmojiInputDraft(text: text, feedbackMessage: "", canSubmit: false)
        }

        guard !VoiceInkPowerModeEmojiCatalog.allEmojis(customEmojis: customEmojis).contains(text) else {
            return VoiceInkPowerModeEmojiInputDraft(text: text, feedbackMessage: duplicateMessage, canSubmit: false)
        }

        guard VoiceInkPowerModeEmojiCatalog.isValidEmoji(text) else {
            return VoiceInkPowerModeEmojiInputDraft(text: text, feedbackMessage: invalidPreviewMessage, canSubmit: false)
        }

        return VoiceInkPowerModeEmojiInputDraft(text: text, feedbackMessage: "", canSubmit: true)
    }

    public static func submitFeedbackMessage(for result: VoiceInkPowerModeCustomEmojiAddResult) -> String {
        switch result {
        case .added:
            return ""
        case .empty:
            return emptySubmitMessage
        case .invalid:
            return invalidSubmitMessage
        case .duplicate:
            return duplicateMessage
        }
    }

    public static func inUseAlert(emoji: String) -> VoiceInkPowerModeEmojiRemovalAlertPresentation {
        VoiceInkPowerModeEmojiRemovalAlertPresentation(
            title: inUseAlertTitle,
            message: "The emoji \"\(emoji)\" is currently used by one or more Power Modes and cannot be removed.",
            buttonTitle: inUseAlertButtonTitle
        )
    }
}
