import Foundation

public enum VoiceInkIOSSettingsBackupCategory: String, CaseIterable, Codable, Hashable, Sendable {
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

public struct VoiceInkIOSGeneralSettingsBackup: Codable, Equatable, Sendable {
    public let audioSessionTimeoutSeconds: Int
    public let transcriptionCleanupSettings: VoiceInkIOSTranscriptionCleanupBackup
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
        transcriptionCleanupSettings: VoiceInkIOSTranscriptionCleanupBackup,
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

public struct VoiceInkIOSTranscriptionCleanupBackup: Codable, Equatable, Sendable {
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

    public init(_ settings: VoiceInkTranscriptionCleanupSettings) {
        self.init(
            punctuationMode: settings.punctuationMode,
            isTextFormattingEnabled: settings.isTextFormattingEnabled,
            lowercaseTranscription: settings.lowercaseTranscription,
            removeFillerWords: settings.removeFillerWords
        )
    }

    public var settings: VoiceInkTranscriptionCleanupSettings {
        VoiceInkTranscriptionCleanupSettings(
            punctuationMode: punctuationMode,
            isTextFormattingEnabled: isTextFormattingEnabled,
            lowercaseTranscription: lowercaseTranscription,
            removeFillerWords: removeFillerWords
        )
    }
}

public struct VoiceInkIOSModesBackup: Codable {
    public let modes: [Mode]
    public let selectedModeId: UUID?

    public init(modes: [Mode], selectedModeId: UUID?) {
        self.modes = modes
        self.selectedModeId = selectedModeId
    }
}

public struct VoiceInkIOSDictionaryBackup: Codable, Equatable, Sendable {
    public let vocabularyTerms: [String]
    public let wordReplacements: [VoiceInkWordReplacementRule]

    public init(
        vocabularyTerms: [String],
        wordReplacements: [VoiceInkWordReplacementRule]
    ) {
        self.vocabularyTerms = vocabularyTerms
        self.wordReplacements = wordReplacements
    }
}

/// Portable custom-model metadata. API keys intentionally have no wire field.
public struct VoiceInkIOSCustomModelDefinition: Codable, Equatable, Sendable {
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

    public init(_ record: VoiceInkCustomCloudModelStoredRecord) {
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

    public var storedRecord: VoiceInkCustomCloudModelStoredRecord {
        VoiceInkCustomCloudModelStoredRecord(
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

public struct VoiceInkIOSSettingsBackupFile: Codable {
    public let version: String
    public let general: VoiceInkIOSGeneralSettingsBackup?
    public let modes: VoiceInkIOSModesBackup?
    public let prompts: [VoiceInkCustomPrompt]?
    public let dictionary: VoiceInkIOSDictionaryBackup?
    public let customModels: [VoiceInkIOSCustomModelDefinition]?

    public init(
        version: String,
        general: VoiceInkIOSGeneralSettingsBackup? = nil,
        modes: VoiceInkIOSModesBackup? = nil,
        prompts: [VoiceInkCustomPrompt]? = nil,
        dictionary: VoiceInkIOSDictionaryBackup? = nil,
        customModels: [VoiceInkIOSCustomModelDefinition]? = nil
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
            ?? VoiceInkIOSSettingsBackupCodec.fallbackVersion
        general = try container.decodeIfPresent(VoiceInkIOSGeneralSettingsBackup.self, forKey: .general)
        modes = try container.decodeIfPresent(VoiceInkIOSModesBackup.self, forKey: .modes)
        prompts = try container.decodeIfPresent([VoiceInkCustomPrompt].self, forKey: .prompts)
        dictionary = try container.decodeIfPresent(VoiceInkIOSDictionaryBackup.self, forKey: .dictionary)
        customModels = try container.decodeIfPresent([VoiceInkIOSCustomModelDefinition].self, forKey: .customModels)
    }

    public var availableCategories: Set<VoiceInkIOSSettingsBackupCategory> {
        var categories = Set<VoiceInkIOSSettingsBackupCategory>()
        if general != nil { categories.insert(.general) }
        if modes != nil { categories.insert(.modes) }
        if prompts != nil { categories.insert(.prompts) }
        if dictionary != nil { categories.insert(.dictionary) }
        if customModels != nil { categories.insert(.customModels) }
        return categories
    }
}

public enum VoiceInkIOSSettingsBackupCodec {
    public static let fallbackVersion = "0.0.0"
    public static let defaultFilename = "Roma_Just_Talk_iOS_Settings.json"

    public static func encode(_ backup: VoiceInkIOSSettingsBackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> VoiceInkIOSSettingsBackupFile {
        try JSONDecoder().decode(VoiceInkIOSSettingsBackupFile.self, from: data)
    }
}

public struct VoiceInkIOSSettingsBackupImportPlan {
    public let backup: VoiceInkIOSSettingsBackupFile
    public let categories: Set<VoiceInkIOSSettingsBackupCategory>

    public init(
        backup: VoiceInkIOSSettingsBackupFile,
        categories: Set<VoiceInkIOSSettingsBackupCategory>
    ) throws {
        guard !categories.isEmpty else {
            throw VoiceInkIOSSettingsBackupError.emptySelection
        }
        guard categories.isSubset(of: backup.availableCategories) else {
            throw VoiceInkIOSSettingsBackupError.unavailableCategory
        }
        self.backup = backup
        self.categories = categories
    }

    public func applyRuntimeState(
        replaceCustomModels: ([VoiceInkIOSCustomModelDefinition]) throws -> Void,
        applyGeneral: (VoiceInkIOSGeneralSettingsBackup) -> Void,
        applyModes: (VoiceInkIOSModesBackup) -> Void,
        applyPrompts: ([VoiceInkCustomPrompt]) -> Void,
        applyDictionary: (VoiceInkIOSDictionaryBackup) -> Void
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

public enum VoiceInkIOSSettingsBackupError: LocalizedError, Equatable, Sendable {
    case emptySelection
    case unavailableCategory

    public var errorDescription: String? {
        switch self {
        case .emptySelection: "Select at least one category to import."
        case .unavailableCategory: "The backup does not contain one or more selected categories."
        }
    }
}
