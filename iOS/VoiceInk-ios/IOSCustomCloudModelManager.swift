import Foundation
import Combine
import OSLog
import Security
import VoiceInkCore

enum IOSCustomCloudModelMutationError: LocalizedError {
    case validation([String])
    case keychainSave
    case storage(Error)

    var errorDescription: String? {
        switch self {
        case .validation(let errors):
            return errors.joined(separator: "\n")
        case .keychainSave:
            return VoiceInkCustomCloudModelFormPresentation.macOS.keychainSaveFailureMessage
        case .storage(let error):
            return error.localizedDescription
        }
    }
}

@MainActor
final class IOSCustomCloudModelManager: ObservableObject {
    typealias SaveAPIKey = (String, UUID) -> Bool
    typealias LoadAPIKey = (UUID) -> String?
    typealias DeleteAPIKey = (UUID) -> Void

    static let shared = IOSCustomCloudModelManager()

    @Published private(set) var models: [VoiceInkCustomCloudModelStoredRecord]

    private let defaults: UserDefaults
    private let saveAPIKey: SaveAPIKey
    private let loadAPIKey: LoadAPIKey
    private let deleteAPIKey: DeleteAPIKey

    init(
        defaults: UserDefaults = .standard,
        saveAPIKey: @escaping SaveAPIKey = IOSCustomCloudModelManager.saveAPIKeyToKeychain,
        loadAPIKey: @escaping LoadAPIKey = IOSCustomCloudModelManager.loadAPIKeyFromKeychain,
        deleteAPIKey: @escaping DeleteAPIKey = IOSCustomCloudModelManager.deleteAPIKeyFromKeychain
    ) {
        self.defaults = defaults
        self.saveAPIKey = saveAPIKey
        self.loadAPIKey = loadAPIKey
        self.deleteAPIKey = deleteAPIKey

        do {
            let stored: [VoiceInkCustomCloudModelStoredRecord]? = try VoiceInkCustomCloudModelStorage.loadModels(
                from: defaults
            )
            self.models = stored ?? []
            migrateLegacyAPIKeysIfNeeded()
        } catch {
            VoiceInkIOSLogger.settings.error(
                "\(VoiceInkCustomCloudModelStorage.decodeFailedMessage(errorDescription: error.localizedDescription), privacy: .public)"
            )
            self.models = []
        }
    }

    // Xcode 26.1-26.3 corrupts actor-isolated deinit back-deployment on Simulator.
    nonisolated deinit {}

    var modelNames: [String] {
        models.map(\.name)
    }

    func model(named name: String) -> VoiceInkCustomCloudModelStoredRecord? {
        models.first { $0.name == name }
    }

    func apiKey(for modelID: UUID) -> String? {
        loadAPIKey(modelID)
    }

    func validationErrors(
        for draft: VoiceInkCustomCloudModelDraft,
        excludingID: UUID? = nil
    ) -> [String] {
        VoiceInkCustomCloudModelPolicy.validationErrors(
            for: draft,
            existingModels: models.map {
                VoiceInkCustomCloudModelIdentity(id: $0.id, name: $0.name)
            },
            excludingId: excludingID
        )
    }

    @discardableResult
    func save(
        draft: VoiceInkCustomCloudModelDraft,
        isMultilingual: Bool,
        editingID: UUID? = nil
    ) throws -> VoiceInkCustomCloudModelStoredRecord {
        let errors = validationErrors(for: draft, excludingID: editingID)
        guard errors.isEmpty else {
            throw IOSCustomCloudModelMutationError.validation(errors)
        }

        let id = editingID ?? UUID()
        let oldAPIKey = editingID.flatMap(loadAPIKey)
        guard saveAPIKey(draft.apiKey, id) else {
            throw IOSCustomCloudModelMutationError.keychainSave
        }

        let record = VoiceInkCustomCloudModelStoredRecord(
            id: id,
            name: draft.name,
            displayName: draft.displayName,
            description: VoiceInkCustomCloudModelFormPresentation.macOS.defaultModelDescription,
            apiEndpoint: draft.apiEndpoint,
            modelName: draft.modelName,
            isMultilingualModel: isMultilingual,
            supportedLanguages: isMultilingual
                ? VoiceInkLanguageCatalog.whisperLanguages()
                : VoiceInkLanguageCatalog.englishOnly
        )
        var updatedModels = models.filter { $0.id != id }
        updatedModels.append(record)

        do {
            try VoiceInkCustomCloudModelStorage.saveModels(updatedModels, to: defaults)
            models = updatedModels
            return record
        } catch {
            if let oldAPIKey {
                _ = saveAPIKey(oldAPIKey, id)
            } else {
                deleteAPIKey(id)
            }
            throw IOSCustomCloudModelMutationError.storage(error)
        }
    }

    func remove(id: UUID) throws {
        let updatedModels = models.filter { $0.id != id }
        do {
            try VoiceInkCustomCloudModelStorage.saveModels(updatedModels, to: defaults)
            models = updatedModels
            deleteAPIKey(id)
        } catch {
            throw IOSCustomCloudModelMutationError.storage(error)
        }
    }

    func removeAll() {
        models.forEach { deleteAPIKey($0.id) }
        models = []
        VoiceInkCustomCloudModelStorage.clear(from: defaults)
    }

    func replaceDefinitions(_ definitions: [VoiceInkIOSCustomModelDefinition]) throws {
        let records = definitions.map(\.storedRecord)
        let errors = VoiceInkCustomCloudModelPolicy.storedRecordValidationErrors(records)
        guard errors.isEmpty else {
            throw IOSCustomCloudModelMutationError.validation(errors)
        }

        do {
            try VoiceInkCustomCloudModelStorage.saveModels(records, to: defaults)
            let affectedIDs = Set(models.map(\.id) + records.map(\.id))
            affectedIDs.forEach(deleteAPIKey)
            models = records
        } catch {
            throw IOSCustomCloudModelMutationError.storage(error)
        }
    }

    private func migrateLegacyAPIKeysIfNeeded() {
        var didMigrate = false
        for model in models {
            guard let key = model.legacyAPIKeyForKeychainMigration else { continue }
            didMigrate = saveAPIKey(key, model.id) || didMigrate
        }
        guard didMigrate else { return }
        try? VoiceInkCustomCloudModelStorage.saveModels(models, to: defaults)
    }

    private static func saveAPIKeyToKeychain(_ key: String, id: UUID) -> Bool {
        VoiceInkKeychainValueStore.saveString(
            key,
            account: VoiceInkProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: id)
        ) == errSecSuccess
    }

    private static func loadAPIKeyFromKeychain(id: UUID) -> String? {
        VoiceInkKeychainValueStore.loadString(
            account: VoiceInkProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: id)
        ).value
    }

    private static func deleteAPIKeyFromKeychain(id: UUID) {
        VoiceInkKeychainValueStore.deleteValue(
            account: VoiceInkProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: id)
        )
    }
}
