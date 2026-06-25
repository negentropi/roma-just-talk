import Foundation

public enum VoiceInkSettingsBackupCategory: String, CaseIterable, Hashable, Sendable {
    case general
    case prompts
    case powerMode
    case dictionary
    case customModels

    public var title: String {
        switch self {
        case .general:
            return "General Settings"
        case .prompts:
            return "Custom Prompts"
        case .powerMode:
            return "Power Mode"
        case .dictionary:
            return "Dictionary"
        case .customModels:
            return "Custom Model Definitions"
        }
    }
}

public enum VoiceInkSettingsBackupImportPolicy {
    public static func categorySummary(for categories: Set<VoiceInkSettingsBackupCategory>) -> String {
        if categories == Set(VoiceInkSettingsBackupCategory.allCases) {
            return "All settings"
        }

        return VoiceInkSettingsBackupCategory.allCases
            .filter { categories.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }

    public static func needsAPIKeyReminder(for categories: Set<VoiceInkSettingsBackupCategory>) -> Bool {
        !categories.isDisjoint(with: [.prompts, .powerMode, .customModels])
    }
}

public enum VoiceInkSettingsBackupImportDiagnostics {
    public static let noGeneralSettingsMessage = "No general settings found in the imported file."
    public static let noVocabularyWordsMessage = "No vocabulary words found in the imported file. Existing items remain unchanged."
    public static let noWordReplacementsMessage = "No word replacements found in the imported file. Existing replacements remain unchanged."
    public static let noDictionaryEntriesImportedMessage = "No new dictionary entries were imported."
    public static let generalSettingsImportedMessage = "Successfully imported general settings."
    public static let noCustomModelsMessage = "No custom models found in the imported file."

    public static func saveFailedDescription(item: String, localizedDescription: String) -> String {
        "Failed to save imported \(item): \(localizedDescription)"
    }

    public static func customPromptsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) custom prompts."
    }

    public static func powerModeConfigurationsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) Power Mode configurations."
    }

    public static func skippedInvalidReplacementsMessage(count: Int) -> String {
        "Skipped \(count) invalid word replacements from the imported file."
    }

    public static func dictionaryEntriesImportedMessage(
        vocabularyWordCount: Int,
        wordReplacementCount: Int
    ) -> String {
        "Successfully imported \(vocabularyWordCount) vocabulary words and \(wordReplacementCount) word replacements to SwiftData."
    }

    public static func customModelsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) custom model definitions."
    }
}

public enum VoiceInkSettingsBackupImportError: LocalizedError, Sendable {
    case saveFailed(item: String, localizedDescription: String)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let item, let localizedDescription):
            VoiceInkSettingsBackupImportDiagnostics.saveFailedDescription(
                item: item,
                localizedDescription: localizedDescription
            )
        }
    }
}

public struct VoiceInkSettingsBackupFile<ShortcutBackup: Codable>: Codable {
    public let version: String
    public let customPrompts: [VoiceInkCustomPrompt]
    public let powerModeConfigs: [PowerModeConfig]
    public let powerModeShortcuts: [String: ShortcutBackup]?
    public let vocabularyWords: [VoiceInkVocabularyWordBackup]?
    public let wordReplacements: [String: String]?
    public let generalSettings: VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>?
    public let customEmojis: [String]?
    public let customCloudModels: [VoiceInkCustomCloudModelBackup]?

    private enum CodingKeys: String, CodingKey {
        case version
        case customPrompts
        case powerModeConfigs
        case powerModeShortcuts
        case vocabularyWords
        case wordReplacements
        case generalSettings
        case customEmojis
        case customCloudModels
    }

    public init(
        version: String,
        customPrompts: [VoiceInkCustomPrompt],
        powerModeConfigs: [PowerModeConfig],
        powerModeShortcuts: [String: ShortcutBackup]?,
        vocabularyWords: [VoiceInkVocabularyWordBackup]?,
        wordReplacements: [String: String]?,
        generalSettings: VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>?,
        customEmojis: [String]?,
        customCloudModels: [VoiceInkCustomCloudModelBackup]?
    ) {
        self.version = version
        self.customPrompts = customPrompts
        self.powerModeConfigs = powerModeConfigs
        self.powerModeShortcuts = powerModeShortcuts
        self.vocabularyWords = vocabularyWords
        self.wordReplacements = wordReplacements
        self.generalSettings = generalSettings
        self.customEmojis = customEmojis
        self.customCloudModels = customCloudModels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
        customPrompts = try container.decodeIfPresent([VoiceInkCustomPrompt].self, forKey: .customPrompts) ?? []
        powerModeConfigs = try container.decodeIfPresent([PowerModeConfig].self, forKey: .powerModeConfigs) ?? []
        powerModeShortcuts = try container.decodeIfPresent([String: ShortcutBackup].self, forKey: .powerModeShortcuts)
        vocabularyWords = try container.decodeIfPresent([VoiceInkVocabularyWordBackup].self, forKey: .vocabularyWords)
        wordReplacements = try container.decodeIfPresent([String: String].self, forKey: .wordReplacements)
        generalSettings = try container.decodeIfPresent(VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>.self, forKey: .generalSettings)
        customEmojis = try container.decodeIfPresent([String].self, forKey: .customEmojis)
        customCloudModels = try container.decodeIfPresent([VoiceInkCustomCloudModelBackup].self, forKey: .customCloudModels)
    }
}

public struct VoiceInkSettingsBackupPresentation: Equatable, Sendable {
    public let defaultFileName: String
    public let exportPanelTitle: String
    public let exportPanelMessage: String
    public let importPanelTitle: String
    public let importPanelMessage: String
    public let importSelectionTitle: String
    public let importSelectionMessage: String
    public let allCategoriesTitle: String
    public let individualCategoriesTitle: String
    public let importActionTitle: String
    public let cancelActionTitle: String
    public let okActionTitle: String
    public let configureAPIKeysActionTitle: String
    public let exportSuccessTitle: String
    public let exportErrorTitle: String
    public let exportCanceledTitle: String
    public let importCanceledTitle: String
    public let importErrorTitle: String
    public let versionMismatchTitle: String
    public let importSuccessTitle: String
    public let exportCanceledMessage: String
    public let importCanceledMessage: String
    public let noSettingsImportedMessage: String
    public let missingFileURLMessage: String
    public let emptyCategorySelectionMessage: String
    public let apiKeyReminderText: String
    public let restartRecommendationText: String

    public static let macOS = VoiceInkSettingsBackupPresentation(
        defaultFileName: "VoiceInk_Settings_Backup.json",
        exportPanelTitle: "Export VoiceInk Settings",
        exportPanelMessage: "Choose a location to save your settings.",
        importPanelTitle: "Import VoiceInk Settings",
        importPanelMessage: "Choose a settings backup, then select what you want to import.",
        importSelectionTitle: "Import Settings",
        importSelectionMessage: "Choose what to import from this backup.",
        allCategoriesTitle: "All",
        individualCategoriesTitle: "Individual categories",
        importActionTitle: "Import",
        cancelActionTitle: "Cancel",
        okActionTitle: "OK",
        configureAPIKeysActionTitle: "Configure API Keys",
        exportSuccessTitle: "Export Successful",
        exportErrorTitle: "Export Error",
        exportCanceledTitle: "Export Canceled",
        importCanceledTitle: "Import Canceled",
        importErrorTitle: "Import Error",
        versionMismatchTitle: "Version Mismatch",
        importSuccessTitle: "Import Successful",
        exportCanceledMessage: "The settings export operation was canceled.",
        importCanceledMessage: "The settings import operation was canceled.",
        noSettingsImportedMessage: "No settings were imported.",
        missingFileURLMessage: "Could not get the file URL from the open panel.",
        emptyCategorySelectionMessage: "Select at least one category to import.",
        apiKeyReminderText: "IMPORTANT: If you were using AI enhancement features, please make sure to reconfigure your API keys in the Enhancement section.",
        restartRecommendationText: "It is recommended to restart VoiceInk for all changes to take full effect."
    )

    public func exportSuccessMessage(fileName: String) -> String {
        "Your settings have been successfully exported to \(fileName)."
    }

    public func exportSaveFailureMessage(localizedDescription: String) -> String {
        "Could not save settings to file: \(localizedDescription)"
    }

    public func exportEncodingFailureMessage(localizedDescription: String) -> String {
        "Could not encode settings to JSON: \(localizedDescription)"
    }

    public func versionMismatchMessage(importedVersion: String, currentVersion: String) -> String {
        "The imported settings file (version \(importedVersion)) is from a different version than your application (version \(currentVersion)). Proceeding with import, but be aware of potential incompatibilities."
    }

    public func importSuccessMessage(
        fileName: String,
        categories: Set<VoiceInkSettingsBackupCategory>
    ) -> String {
        "Settings imported successfully from \(fileName).\n\nImported: \(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))."
    }

    public func importFailureMessage(localizedDescription: String) -> String {
        "Error importing settings: \(localizedDescription). The file might be corrupted or not in the correct format."
    }

    public func importSuccessInformativeText(
        fileName: String,
        categories: Set<VoiceInkSettingsBackupCategory>
    ) -> String {
        var informativeText = importSuccessMessage(fileName: fileName, categories: categories)
        if VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: categories) {
            informativeText += "\n\n\(apiKeyReminderText)"
        }
        informativeText += "\n\n\(restartRecommendationText)"
        return informativeText
    }
}
