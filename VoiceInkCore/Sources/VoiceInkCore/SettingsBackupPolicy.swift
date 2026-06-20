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
