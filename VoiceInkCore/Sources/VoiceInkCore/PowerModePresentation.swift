import Foundation

public enum VoiceInkPowerModePresentation {
    public static let defaultOverrideDisplayText = "Default"
    public static let autoLanguageDisplayText = "Auto"
    public static let englishLanguageDisplayText = "English"

    public static func displayName(name: String?, emoji: String?) -> String {
        switch (emoji?.trimmingCharacters(in: .whitespacesAndNewlines), name?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (.some(emojiValue), .some(nameValue)) where !emojiValue.isEmpty && !nameValue.isEmpty:
            return "\(emojiValue) \(nameValue)"
        case let (.some(emojiValue), _) where !emojiValue.isEmpty:
            return emojiValue
        case let (_, .some(nameValue)) where !nameValue.isEmpty:
            return nameValue
        default:
            return ""
        }
    }

    public static func selectedLanguageDisplayText(
        selectedLanguage: String?,
        languageOptions: [String: String]
    ) -> String {
        guard let selectedLanguage else {
            return defaultOverrideDisplayText
        }

        if selectedLanguage == VoiceInkLanguageCatalog.autoDetectCode {
            return autoLanguageDisplayText
        }

        if selectedLanguage == "en" {
            return englishLanguageDisplayText
        }

        return languageOptions[selectedLanguage] ?? selectedLanguage.uppercased()
    }
}
