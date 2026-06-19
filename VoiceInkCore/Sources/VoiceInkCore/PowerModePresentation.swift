import Foundation

public struct VoiceInkPowerModeDeleteConfirmationPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let primaryButtonTitle: String
    public let cancelButtonTitle: String

    public init(
        title: String,
        message: String,
        primaryButtonTitle: String,
        cancelButtonTitle: String
    ) {
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
    }
}

public enum VoiceInkPowerModePresentation {
    public static let defaultOverrideDisplayText = "Default"
    public static let autoLanguageDisplayText = "Auto"
    public static let englishLanguageDisplayText = "English"
    public static let deleteConfirmationTitle = "Delete Power Mode?"
    public static let deleteConfirmationPrimaryButtonTitle = "Delete"
    public static let deleteConfirmationCancelButtonTitle = "Cancel"

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

    public static func appTriggerCountText(_ count: Int) -> String {
        triggerCountText(count, singular: "App", plural: "Apps")
    }

    public static func websiteTriggerCountText(_ count: Int) -> String {
        triggerCountText(count, singular: "Website", plural: "Websites")
    }

    public static func deleteConfirmation(configName: String) -> VoiceInkPowerModeDeleteConfirmationPresentation {
        VoiceInkPowerModeDeleteConfirmationPresentation(
            title: deleteConfirmationTitle,
            message: "Are you sure you want to delete the '\(configName)' power mode? This action cannot be undone.",
            primaryButtonTitle: deleteConfirmationPrimaryButtonTitle,
            cancelButtonTitle: deleteConfirmationCancelButtonTitle
        )
    }

    private static func triggerCountText(_ count: Int, singular: String, plural: String) -> String {
        guard count > 0 else {
            return ""
        }
        return count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }
}
