import Foundation

public enum RomaIOSSettingsBackupCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case general
    case modes
    case prompts
    case dictionary
    case customModels

    public var title: String {
        switch self {
        case .general: "General Settings"
        case .modes: "Modes"
        case .prompts: "Custom Prompts"
        case .dictionary: "Dictionary"
        case .customModels: "Custom Model Definitions"
        }
    }
}

public struct RomaIOSGeneralSettingsBackup: Codable, Equatable, Sendable {
    public let audioSessionTimeoutSeconds: Int
    public let transcriptionCleanupSettings: RomaIOSTranscriptionCleanupBackup
    public let fillerWords: [String]
    public let selectedTranscriptionLanguage: String
    public let isVADEnabled: Bool
    public let shouldPrewarmModel: Bool
    public let appendTrailingSpace: Bool
    public let isTranscriptionCleanupEnabled: Bool
    public let transcriptionRetentionMinutes: Int
    public let isAudioCleanupEnabled: Bool
    public let audioRetentionDays: Int

    public init(
        audioSessionTimeoutSeconds: Int,
        transcriptionCleanupSettings: RomaIOSTranscriptionCleanupBackup,
        fillerWords: [String],
        selectedTranscriptionLanguage: String,
        isVADEnabled: Bool,
        shouldPrewarmModel: Bool,
        appendTrailingSpace: Bool,
        isTranscriptionCleanupEnabled: Bool,
        transcriptionRetentionMinutes: Int,
        isAudioCleanupEnabled: Bool,
        audioRetentionDays: Int
    ) {
        self.audioSessionTimeoutSeconds = audioSessionTimeoutSeconds
        self.transcriptionCleanupSettings = transcriptionCleanupSettings
        self.fillerWords = fillerWords
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.isVADEnabled = isVADEnabled
        self.shouldPrewarmModel = shouldPrewarmModel
        self.appendTrailingSpace = appendTrailingSpace
        self.isTranscriptionCleanupEnabled = isTranscriptionCleanupEnabled
        self.transcriptionRetentionMinutes = transcriptionRetentionMinutes
        self.isAudioCleanupEnabled = isAudioCleanupEnabled
        self.audioRetentionDays = audioRetentionDays
    }
}

public struct RomaIOSTranscriptionCleanupBackup: Codable, Equatable, Sendable {
    public let punctuationMode: PunctuationCleanupMode
    public let isTextFormattingEnabled: Bool
    public let lowercaseTranscription: Bool
    public let removeFillerWords: Bool

    public init(
        punctuationMode: PunctuationCleanupMode,
        isTextFormattingEnabled: Bool,
        lowercaseTranscription: Bool,
        removeFillerWords: Bool
    ) {
        self.punctuationMode = punctuationMode
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.lowercaseTranscription = lowercaseTranscription
        self.removeFillerWords = removeFillerWords
    }

    public init(_ settings: RomaTranscriptionCleanupSettings) {
        self.init(
            punctuationMode: settings.punctuationMode,
            isTextFormattingEnabled: settings.isTextFormattingEnabled,
            lowercaseTranscription: settings.lowercaseTranscription,
            removeFillerWords: settings.removeFillerWords
        )
    }

    public var settings: RomaTranscriptionCleanupSettings {
        RomaTranscriptionCleanupSettings(
            punctuationMode: punctuationMode,
            isTextFormattingEnabled: isTextFormattingEnabled,
            lowercaseTranscription: lowercaseTranscription,
            removeFillerWords: removeFillerWords
        )
    }
}

public struct RomaIOSModesBackup: Codable {
    public let modes: [Mode]
    public let selectedModeId: UUID?

    public init(modes: [Mode], selectedModeId: UUID?) {
        self.modes = modes
        self.selectedModeId = selectedModeId
    }
}

public struct RomaIOSDictionaryBackup: Codable, Equatable, Sendable {
    public let vocabularyTerms: [String]
    public let wordReplacements: [RomaWordReplacementRule]

    public init(
        vocabularyTerms: [String],
        wordReplacements: [RomaWordReplacementRule]
    ) {
        self.vocabularyTerms = vocabularyTerms
        self.wordReplacements = wordReplacements
    }
}

/// Portable custom-model metadata. API keys intentionally have no wire field.
public struct RomaIOSCustomModelDefinition: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let displayName: String
    public let description: String
    public let apiEndpoint: String
    public let modelName: String
    public let isMultilingualModel: Bool
    public let supportedLanguages: [String: String]

    public init(
        id: UUID,
        name: String,
        displayName: String,
        description: String,
        apiEndpoint: String,
        modelName: String,
        isMultilingualModel: Bool,
        supportedLanguages: [String: String]
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.modelName = modelName
        self.isMultilingualModel = isMultilingualModel
        self.supportedLanguages = supportedLanguages
    }

    public init(_ record: RomaCustomCloudModelStoredRecord) {
        self.init(
            id: record.id,
            name: record.name,
            displayName: record.displayName,
            description: record.description,
            apiEndpoint: record.apiEndpoint,
            modelName: record.modelName,
            isMultilingualModel: record.isMultilingualModel,
            supportedLanguages: record.supportedLanguages
        )
    }

    public var storedRecord: RomaCustomCloudModelStoredRecord {
        RomaCustomCloudModelStoredRecord(
            id: id,
            name: name,
            displayName: displayName,
            description: description,
            apiEndpoint: apiEndpoint,
            modelName: modelName,
            isMultilingualModel: isMultilingualModel,
            supportedLanguages: supportedLanguages
        )
    }
}

public struct RomaIOSSettingsBackupFile: Codable {
    public let version: String
    public let general: RomaIOSGeneralSettingsBackup?
    public let modes: RomaIOSModesBackup?
    public let prompts: [RomaCustomPrompt]?
    public let dictionary: RomaIOSDictionaryBackup?
    public let customModels: [RomaIOSCustomModelDefinition]?

    public init(
        version: String,
        general: RomaIOSGeneralSettingsBackup? = nil,
        modes: RomaIOSModesBackup? = nil,
        prompts: [RomaCustomPrompt]? = nil,
        dictionary: RomaIOSDictionaryBackup? = nil,
        customModels: [RomaIOSCustomModelDefinition]? = nil
    ) {
        self.version = version
        self.general = general
        self.modes = modes
        self.prompts = prompts
        self.dictionary = dictionary
        self.customModels = customModels
    }

    private enum CodingKeys: String, CodingKey {
        case version, general, modes, prompts, dictionary, customModels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
            ?? RomaIOSSettingsBackupCodec.fallbackVersion
        general = try container.decodeIfPresent(RomaIOSGeneralSettingsBackup.self, forKey: .general)
        modes = try container.decodeIfPresent(RomaIOSModesBackup.self, forKey: .modes)
        prompts = try container.decodeIfPresent([RomaCustomPrompt].self, forKey: .prompts)
        dictionary = try container.decodeIfPresent(RomaIOSDictionaryBackup.self, forKey: .dictionary)
        customModels = try container.decodeIfPresent([RomaIOSCustomModelDefinition].self, forKey: .customModels)
    }

    public var availableCategories: Set<RomaIOSSettingsBackupCategory> {
        var categories = Set<RomaIOSSettingsBackupCategory>()
        if general != nil { categories.insert(.general) }
        if modes != nil { categories.insert(.modes) }
        if prompts != nil { categories.insert(.prompts) }
        if dictionary != nil { categories.insert(.dictionary) }
        if customModels != nil { categories.insert(.customModels) }
        return categories
    }
}

public enum RomaIOSSettingsBackupCodec {
    public static let fallbackVersion = "0.0.0"
    public static let defaultFilename = "Roma_Just_Talk_iOS_Settings.json"

    public static func encode(_ backup: RomaIOSSettingsBackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> RomaIOSSettingsBackupFile {
        try JSONDecoder().decode(RomaIOSSettingsBackupFile.self, from: data)
    }
}

public struct RomaIOSSettingsBackupImportPlan {
    public let backup: RomaIOSSettingsBackupFile
    public let categories: Set<RomaIOSSettingsBackupCategory>

    public init(
        backup: RomaIOSSettingsBackupFile,
        categories: Set<RomaIOSSettingsBackupCategory>
    ) throws {
        guard !categories.isEmpty else {
            throw RomaIOSSettingsBackupError.emptySelection
        }
        guard categories.isSubset(of: backup.availableCategories) else {
            throw RomaIOSSettingsBackupError.unavailableCategory
        }
        self.backup = backup
        self.categories = categories
    }

    public func applyRuntimeState(
        replaceCustomModels: ([RomaIOSCustomModelDefinition]) throws -> Void,
        applyGeneral: (RomaIOSGeneralSettingsBackup) -> Void,
        applyModes: (RomaIOSModesBackup) -> Void,
        applyPrompts: ([RomaCustomPrompt]) -> Void,
        applyDictionary: (RomaIOSDictionaryBackup) -> Void
    ) throws {
        // Commit the only fallible storage operation before mutating live settings.
        if categories.contains(.customModels), let customModels = backup.customModels {
            try replaceCustomModels(customModels)
        }
        if categories.contains(.general), let general = backup.general { applyGeneral(general) }
        if categories.contains(.modes), let modes = backup.modes { applyModes(modes) }
        if categories.contains(.prompts), let prompts = backup.prompts { applyPrompts(prompts) }
        if categories.contains(.dictionary), let dictionary = backup.dictionary { applyDictionary(dictionary) }
    }
}

public enum RomaIOSSettingsBackupError: LocalizedError, Equatable, Sendable {
    case emptySelection
    case unavailableCategory

    public var errorDescription: String? {
        switch self {
        case .emptySelection: "Select at least one category to import."
        case .unavailableCategory: "The backup does not contain one or more selected categories."
        }
    }
}
