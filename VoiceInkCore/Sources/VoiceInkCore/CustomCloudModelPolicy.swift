import Foundation

public struct VoiceInkCustomCloudModelDraft: Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let apiEndpoint: String
    public let apiKey: String
    public let modelName: String

    public init(
        name: String,
        displayName: String,
        apiEndpoint: String,
        apiKey: String,
        modelName: String
    ) {
        self.name = name
        self.displayName = displayName
        self.apiEndpoint = apiEndpoint
        self.apiKey = apiKey
        self.modelName = modelName
    }
}

public struct VoiceInkCustomCloudModelIdentity: Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct VoiceInkCustomCloudModelFormPresentation: Equatable, Sendable {
    public let defaultAPIEndpoint: String
    public let defaultModelName: String
    public let defaultIsMultilingual: Bool
    public let addButtonTitle: String
    public let editButtonTitle: String
    public let addTitle: String
    public let editTitle: String
    public let addButtonSystemImageName: String
    public let closeSystemImageName: String
    public let warningSystemImageName: String
    public let compatibilityWarningText: String
    public let displayNameFieldTitle: String
    public let displayNamePlaceholder: String
    public let apiEndpointFieldTitle: String
    public let apiEndpointPlaceholder: String
    public let apiKeyFieldTitle: String
    public let apiKeyPlaceholder: String
    public let modelNameFieldTitle: String
    public let modelNamePlaceholder: String
    public let multilingualToggleTitle: String
    public let cancelButtonTitle: String
    public let addSubmitButtonTitle: String
    public let editSubmitButtonTitle: String
    public let addSubmitSystemImageName: String
    public let editSubmitSystemImageName: String
    public let validationAlertTitle: String
    public let validationAlertDismissButtonTitle: String
    public let defaultModelDescription: String
    public let keychainSaveFailureMessage: String

    public static let macOS = VoiceInkCustomCloudModelFormPresentation(
        defaultAPIEndpoint: "https://api.example.com/v1/audio/transcriptions",
        defaultModelName: "large-v3-turbo",
        defaultIsMultilingual: true,
        addButtonTitle: "Add Model",
        editButtonTitle: "Edit Model",
        addTitle: "Add Custom Model",
        editTitle: "Edit Custom Model",
        addButtonSystemImageName: "plus",
        closeSystemImageName: "xmark",
        warningSystemImageName: "exclamationmark.triangle.fill",
        compatibilityWarningText: "Only OpenAI-compatible transcription APIs are supported",
        displayNameFieldTitle: "Display Name",
        displayNamePlaceholder: "My Custom Model",
        apiEndpointFieldTitle: "API Endpoint",
        apiEndpointPlaceholder: "https://api.example.com/v1/audio/transcriptions",
        apiKeyFieldTitle: "API Key",
        apiKeyPlaceholder: "your-api-key",
        modelNameFieldTitle: "Model Name",
        modelNamePlaceholder: "whisper-1",
        multilingualToggleTitle: "Multilingual Model",
        cancelButtonTitle: "Cancel",
        addSubmitButtonTitle: "Add Model",
        editSubmitButtonTitle: "Update Model",
        addSubmitSystemImageName: "plus.circle.fill",
        editSubmitSystemImageName: "checkmark.circle.fill",
        validationAlertTitle: "Validation Errors",
        validationAlertDismissButtonTitle: "OK",
        defaultModelDescription: "Custom transcription model",
        keychainSaveFailureMessage: "Failed to securely save API Key to Keychain. Please check your system settings or try again."
    )

    public func buttonTitle(isEditing: Bool) -> String {
        isEditing ? editButtonTitle : addButtonTitle
    }

    public func title(isEditing: Bool) -> String {
        isEditing ? editTitle : addTitle
    }

    public func submitButtonTitle(isEditing: Bool) -> String {
        isEditing ? editSubmitButtonTitle : addSubmitButtonTitle
    }

    public func submitButtonSystemImageName(isEditing: Bool) -> String {
        isEditing ? editSubmitSystemImageName : addSubmitSystemImageName
    }
}

public struct VoiceInkCustomCloudModelBackup: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let displayName: String
    public let description: String
    public let apiEndpoint: String
    public let modelName: String
    public let isMultilingualModel: Bool
    public let supportedLanguages: [String: String]
    public let apiKey: String?

    public init(
        id: UUID,
        name: String,
        displayName: String,
        description: String,
        apiEndpoint: String,
        modelName: String,
        isMultilingualModel: Bool,
        supportedLanguages: [String: String],
        apiKey: String?
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.modelName = modelName
        self.isMultilingualModel = isMultilingualModel
        self.supportedLanguages = supportedLanguages
        self.apiKey = apiKey
    }

    public var normalizedAPIEndpointForImport: String {
        apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedModelNameForImport: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var apiKeyForImport: String? {
        guard let apiKey, !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }

    public var importPlan: VoiceInkCustomCloudModelImportPlan {
        VoiceInkCustomCloudModelImportPlan(
            id: id,
            name: name,
            displayName: displayName,
            description: description,
            apiEndpoint: normalizedAPIEndpointForImport,
            modelName: normalizedModelNameForImport,
            isMultilingualModel: isMultilingualModel,
            supportedLanguages: supportedLanguages,
            apiKeyToRestore: apiKeyForImport
        )
    }
}

public struct VoiceInkCustomCloudModelImportPlan: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let displayName: String
    public let description: String
    public let apiEndpoint: String
    public let modelName: String
    public let isMultilingualModel: Bool
    public let supportedLanguages: [String: String]
    public let apiKeyToRestore: String?

    public init(
        id: UUID,
        name: String,
        displayName: String,
        description: String,
        apiEndpoint: String,
        modelName: String,
        isMultilingualModel: Bool,
        supportedLanguages: [String: String],
        apiKeyToRestore: String?
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.modelName = modelName
        self.isMultilingualModel = isMultilingualModel
        self.supportedLanguages = supportedLanguages
        self.apiKeyToRestore = apiKeyToRestore
    }
}

public struct VoiceInkCustomCloudModelStoredRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let displayName: String
    public let description: String
    public let apiEndpoint: String
    public let modelName: String
    public let isMultilingualModel: Bool
    public let supportedLanguages: [String: String]
    public let legacyAPIKey: String?

    public init(
        id: UUID,
        name: String,
        displayName: String,
        description: String,
        apiEndpoint: String,
        modelName: String,
        isMultilingualModel: Bool,
        supportedLanguages: [String: String],
        legacyAPIKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.modelName = modelName
        self.isMultilingualModel = isMultilingualModel
        self.supportedLanguages = supportedLanguages
        self.legacyAPIKey = legacyAPIKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, apiEndpoint, modelName, isMultilingualModel, supportedLanguages
        case apiKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        apiEndpoint = try container.decode(String.self, forKey: .apiEndpoint)
        modelName = try container.decode(String.self, forKey: .modelName)
        isMultilingualModel = try container.decode(Bool.self, forKey: .isMultilingualModel)
        supportedLanguages = try container.decode([String: String].self, forKey: .supportedLanguages)
        legacyAPIKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(apiEndpoint, forKey: .apiEndpoint)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(isMultilingualModel, forKey: .isMultilingualModel)
        try container.encode(supportedLanguages, forKey: .supportedLanguages)
    }

    public var legacyAPIKeyForKeychainMigration: String? {
        guard let legacyAPIKey, !legacyAPIKey.isEmpty else {
            return nil
        }
        return legacyAPIKey
    }
}

public enum VoiceInkCustomCloudModelPolicy {
    public static func generatedName(fromDisplayName displayName: String) -> String {
        displayName.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    public static func normalizedDraft(
        displayName: String,
        apiEndpoint: String,
        apiKey: String,
        modelName: String
    ) -> VoiceInkCustomCloudModelDraft {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return VoiceInkCustomCloudModelDraft(
            name: generatedName(fromDisplayName: trimmedDisplayName),
            displayName: trimmedDisplayName,
            apiEndpoint: apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public static func hasRequiredFields(_ draft: VoiceInkCustomCloudModelDraft) -> Bool {
        !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func validationErrors(
        for draft: VoiceInkCustomCloudModelDraft,
        existingModels: [VoiceInkCustomCloudModelIdentity],
        excludingId: UUID? = nil
    ) -> [String] {
        var errors = [String]()

        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Name cannot be empty")
        }

        if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Display name cannot be empty")
        }

        if draft.apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API endpoint cannot be empty")
        } else if !isValidEndpoint(draft.apiEndpoint) {
            errors.append("API endpoint must be a valid URL")
        }

        if draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API key cannot be empty")
        }

        if draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Model name cannot be empty")
        }

        if existingModels.contains(where: { $0.name == draft.name && $0.id != excludingId }) {
            errors.append("A model with this name already exists")
        }

        return errors
    }

    public static func isValidEndpoint(_ value: String) -> Bool {
        guard let url = URL(string: value) else {
            return false
        }
        return url.scheme != nil && url.host != nil
    }
}
