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
