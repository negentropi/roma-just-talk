import Foundation
import os
import RomaCore

class CustomCloudModelManager: ObservableObject {
    static let shared = CustomCloudModelManager()
    
    private let logger = Logger(
        subsystem: RomaAppIdentity.loggingSubsystem,
        category: RomaMacOSLogCategory.customCloudModelManager
    )
    
    @Published var customModels: [CustomCloudModel] = []
    
    private init() {
        loadCustomModels()
    }
    
    // MARK: - CRUD Operations
    
    func addCustomModel(_ model: CustomCloudModel) {
        customModels.append(model)
        saveCustomModels()
    }

    func removeCustomModel(withId id: UUID) {
        customModels.removeAll { $0.id == id }
        saveCustomModels()
        APIKeyManager.shared.deleteCustomModelAPIKey(forModelId: id)
    }

    func updateCustomModel(_ updatedModel: CustomCloudModel) {
        if let index = customModels.firstIndex(where: { $0.id == updatedModel.id }) {
            customModels[index] = updatedModel
            saveCustomModels()
        }
    }
    
    // MARK: - Persistence
    
    private func loadCustomModels() {
        do {
            let storedModels: [CustomCloudModel]? = try RomaCustomCloudModelStorage.loadModels()
            customModels = storedModels ?? []
        } catch {
            logger.error("\(RomaCustomCloudModelStorage.decodeFailedMessage(errorDescription: error.localizedDescription), privacy: .public)")
            customModels = []
        }
    }
    
    func saveCustomModels() {
        do {
            try RomaCustomCloudModelStorage.saveModels(customModels)
        } catch {
            logger.error("\(RomaCustomCloudModelStorage.encodeFailedMessage(errorDescription: error.localizedDescription), privacy: .public)")
        }
    }
    
    // MARK: - Validation
    
    func validateModel(_ draft: RomaCustomCloudModelDraft, excludingId: UUID? = nil) -> [String] {
        RomaCustomCloudModelPolicy.validationErrors(
            for: draft,
            existingModels: customModels.map { RomaCustomCloudModelIdentity(id: $0.id, name: $0.name) },
            excludingId: excludingId
        )
    }
} 
