import Foundation
import Combine
import OSLog
import Security
import RomaCore

enum IOSCustomCloudModelMutationError: LocalizedError {
    case validation([String])
    case keychainSave
    case storage(Error)

    var errorDescription: String? {
        switch self {
        case .validation(let errors):
            return errors.joined(separator: "\n")
        case .keychainSave:
            return RomaCustomCloudModelFormPresentation.macOS.keychainSaveFailureMessage
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

    @Published private(set) var models: [RomaCustomCloudModelStoredRecord]

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
            let stored: [RomaCustomCloudModelStoredRecord]? = try RomaCustomCloudModelStorage.loadModels(
                from: defaults
            )
            self.models = stored ?? []
            migrateLegacyAPIKeysIfNeeded()
        } catch {
            RomaIOSLogger.settings.error(
                "\(RomaCustomCloudModelStorage.decodeFailedMessage(errorDescription: error.localizedDescription), privacy: .public)"
            )
            self.models = []
        }
    }

    // Xcode 26.1-26.3 corrupts actor-isolated deinit back-deployment on Simulator.
    nonisolated deinit {}

    var modelNames: [String] {
        models.map(\.name)
    }

    func model(named name: String) -> RomaCustomCloudModelStoredRecord? {
        models.first { $0.name == name }
    }

    func apiKey(for modelID: UUID) -> String? {
        loadAPIKey(modelID)
    }

    func validationErrors(
        for draft: RomaCustomCloudModelDraft,
        excludingID: UUID? = nil
    ) -> [String] {
        RomaCustomCloudModelPolicy.validationErrors(
            for: draft,
            existingModels: models.map {
                RomaCustomCloudModelIdentity(id: $0.id, name: $0.name)
            },
            excludingId: excludingID
        )
    }

    @discardableResult
    func save(
        draft: RomaCustomCloudModelDraft,
        isMultilingual: Bool,
        editingID: UUID? = nil
    ) throws -> RomaCustomCloudModelStoredRecord {
        let errors = validationErrors(for: draft, excludingID: editingID)
        guard errors.isEmpty else {
            throw IOSCustomCloudModelMutationError.validation(errors)
        }

        let id = editingID ?? UUID()
        let oldAPIKey = editingID.flatMap(loadAPIKey)
        guard saveAPIKey(draft.apiKey, id) else {
            throw IOSCustomCloudModelMutationError.keychainSave
        }

        let record = RomaCustomCloudModelStoredRecord(
            id: id,
            name: draft.name,
            displayName: draft.displayName,
            description: RomaCustomCloudModelFormPresentation.macOS.defaultModelDescription,
            apiEndpoint: draft.apiEndpoint,
            modelName: draft.modelName,
            isMultilingualModel: isMultilingual,
            supportedLanguages: isMultilingual
                ? RomaLanguageCatalog.whisperLanguages()
                : RomaLanguageCatalog.englishOnly
        )
        var updatedModels = models.filter { $0.id != id }
        updatedModels.append(record)

        do {
            try RomaCustomCloudModelStorage.saveModels(updatedModels, to: defaults)
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
            try RomaCustomCloudModelStorage.saveModels(updatedModels, to: defaults)
            models = updatedModels
            deleteAPIKey(id)
        } catch {
            throw IOSCustomCloudModelMutationError.storage(error)
        }
    }

    func removeAll() {
        models.forEach { deleteAPIKey($0.id) }
        models = []
        RomaCustomCloudModelStorage.clear(from: defaults)
    }

    func replaceDefinitions(_ definitions: [RomaIOSCustomModelDefinition]) throws {
        let records = definitions.map(\.storedRecord)
        let errors = RomaCustomCloudModelPolicy.storedRecordValidationErrors(records)
        guard errors.isEmpty else {
            throw IOSCustomCloudModelMutationError.validation(errors)
        }

        do {
            try RomaCustomCloudModelStorage.saveModels(records, to: defaults)
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
        try? RomaCustomCloudModelStorage.saveModels(models, to: defaults)
    }

    private static func saveAPIKeyToKeychain(_ key: String, id: UUID) -> Bool {
        RomaKeychainValueStore.saveString(
            key,
            account: RomaProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: id)
        ) == errSecSuccess
    }

    private static func loadAPIKeyFromKeychain(id: UUID) -> String? {
        RomaKeychainValueStore.loadString(
            account: RomaProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: id)
        ).value
    }

    private static func deleteAPIKeyFromKeychain(id: UUID) {
        RomaKeychainValueStore.deleteValue(
            account: RomaProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: id)
        )
    }
}
