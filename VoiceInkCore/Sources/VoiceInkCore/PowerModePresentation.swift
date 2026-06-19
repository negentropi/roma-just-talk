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

public struct VoiceInkPowerModeValidationAlertPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let buttonTitle: String

    public init(title: String, message: String, buttonTitle: String) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
    }
}

public enum VoiceInkPowerModeRowDetailChipKind: Hashable, Sendable {
    case transcriptionModel
    case selectedLanguage
    case aiModel
    case autoSend
    case contextAwareness
    case prompt
}

public struct VoiceInkPowerModeRowDetailChipPresentation: Equatable, Identifiable, Sendable {
    public let kind: VoiceInkPowerModeRowDetailChipKind
    public let text: String

    public var id: VoiceInkPowerModeRowDetailChipKind {
        kind
    }

    public init(kind: VoiceInkPowerModeRowDetailChipKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct VoiceInkPowerModeRowDetailPresentation: Equatable, Sendable {
    public let isVisible: Bool
    public let chips: [VoiceInkPowerModeRowDetailChipPresentation]

    public init(isVisible: Bool, chips: [VoiceInkPowerModeRowDetailChipPresentation]) {
        self.isVisible = isVisible
        self.chips = chips
    }
}

public enum VoiceInkPowerModePresentation {
    public static let defaultOverrideDisplayText = "Default"
    public static let autoLanguageDisplayText = "Auto"
    public static let englishLanguageDisplayText = "English"
    public static let deleteConfirmationTitle = "Delete Power Mode?"
    public static let deleteConfirmationPrimaryButtonTitle = "Delete"
    public static let deleteConfirmationCancelButtonTitle = "Cancel"
    public static let validationAlertTitle = "Cannot Save Power Mode"
    public static let validationAlertButtonTitle = "OK"
    public static let validationAlertFallbackMessage = "Please fix the validation errors before saving."
    public static let contextAwarenessDisplayText = "Context Awareness"
    public static let defaultPromptDisplayText = "AI"
    public static let noTranscriptionModelsAvailableText = "No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab."
    public static let noAIProvidersConnectedText = "No providers connected"
    public static let noAIModelsLoadedText = "No models loaded"
    public static let noAIModelsAvailableText = "No models available"
    public static let noEnhancementPromptsAvailableText = "No prompts available"

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

    public static func validationAlert(errors: [VoiceInkPowerModeValidationError]) -> VoiceInkPowerModeValidationAlertPresentation {
        VoiceInkPowerModeValidationAlertPresentation(
            title: validationAlertTitle,
            message: errors.first?.localizedDescription ?? validationAlertFallbackMessage,
            buttonTitle: validationAlertButtonTitle
        )
    }

    public static func rowDetailPresentation(
        config: PowerModeConfig,
        transcriptionModelDisplayText: String?,
        selectedLanguageDisplayText: String?,
        selectedPromptTitle: String?
    ) -> VoiceInkPowerModeRowDetailPresentation {
        var chips: [VoiceInkPowerModeRowDetailChipPresentation] = []

        if let transcriptionModelDisplayText = visibleNonDefaultDisplayText(transcriptionModelDisplayText) {
            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .transcriptionModel, text: transcriptionModelDisplayText))
        }

        if let selectedLanguageDisplayText = visibleNonDefaultDisplayText(selectedLanguageDisplayText) {
            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .selectedLanguage, text: selectedLanguageDisplayText))
        }

        if config.isAIEnhancementEnabled, let aiModelDisplayText = aiModelDisplayText(config.selectedAIModel) {
            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .aiModel, text: aiModelDisplayText))
        }

        if config.autoSendKey.isEnabled {
            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .autoSend, text: config.autoSendKey.displayName))
        }

        if config.isAIEnhancementEnabled {
            if config.useScreenCapture {
                chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .contextAwareness, text: contextAwarenessDisplayText))
            }

            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .prompt, text: selectedPromptTitle ?? defaultPromptDisplayText))
        }

        return VoiceInkPowerModeRowDetailPresentation(
            isVisible: transcriptionModelDisplayText != nil || selectedLanguageDisplayText != nil || config.isAIEnhancementEnabled || config.autoSendKey.isEnabled,
            chips: chips
        )
    }

    public static func aiModelDisplayText(_ modelName: String?) -> String? {
        guard let modelName, !modelName.isEmpty else {
            return nil
        }

        return modelName.count > 20 ? String(modelName.prefix(18)) + "..." : modelName
    }

    public static func noAIModelsAvailableText(for provider: VoiceInkAIEnhancementProviderKind) -> String {
        provider == .openRouter ? noAIModelsLoadedText : noAIModelsAvailableText
    }

    private static func triggerCountText(_ count: Int, singular: String, plural: String) -> String {
        guard count > 0 else {
            return ""
        }
        return count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    private static func visibleNonDefaultDisplayText(_ text: String?) -> String? {
        guard let text, text != defaultOverrideDisplayText else {
            return nil
        }
        return text
    }
}
