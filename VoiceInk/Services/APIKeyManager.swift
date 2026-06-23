import Foundation
import os
import VoiceInkCore

/// Manages API keys using secure Keychain storage.
final class APIKeyManager {
    static let shared = APIKeyManager()

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkMacOSLogCategory.apiKeyManager)
    private let keychain = KeychainService.shared

    private init() {}

    // MARK: - Standard Provider API Keys

    /// Saves an API key for a provider.
    @discardableResult
    func saveAPIKey(_ key: String, forProvider provider: String) -> Bool {
        let keyIdentifier = VoiceInkProviderAPIKeyAccount.accountIdentifier(forProviderName: provider)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for provider: \(provider, privacy: .public) with key: \(keyIdentifier, privacy: .public)")
        }
        return success
    }

    @discardableResult
    func applyProviderVerificationPlan(
        _ plan: VoiceInkProviderAPIKeyVerificationApplicationPlan,
        forProvider provider: String
    ) -> Bool {
        plan.applySuccessPersistence { [self] key in
            saveAPIKey(key, forProvider: provider)
        }
    }

    func applyAIEnhancementVerificationPlan(
        _ plan: VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan
    ) {
        guard let persistencePlan = plan.successPersistencePlan else { return }

        if let keyToSave = persistencePlan.keyToSave,
           let providerKeyStorageNameToSave = persistencePlan.providerKeyStorageNameToSave {
            saveAPIKey(keyToSave, forProvider: providerKeyStorageNameToSave)
        }
    }

    func applyAIEnhancementAPIKeyClearPlan(_ plan: VoiceInkAIEnhancementAPIKeyClearPlan) {
        let persistencePlan = plan.persistencePlan
        deleteAPIKey(forProvider: persistencePlan.providerKeyStorageNameToDelete)
    }

    /// Retrieves an API key for a provider.
    func getAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = VoiceInkProviderAPIKeyAccount.accountIdentifier(forProviderName: provider)
        return VoiceInkProviderAPIKeyLookup.usableAPIKey(
            storedKey: keychain.getString(forKey: keyIdentifier),
            providerName: provider
        )
    }

    /// Retrieves the literal stored API key, preserving references like "$ELEVENLABS_API_KEY" for the UI.
    func getStoredAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = VoiceInkProviderAPIKeyAccount.accountIdentifier(forProviderName: provider)
        return keychain.getString(forKey: keyIdentifier)
    }

    /// Deletes an API key for a provider.
    @discardableResult
    func deleteAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = VoiceInkProviderAPIKeyAccount.accountIdentifier(forProviderName: provider)
        let success = keychain.delete(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for provider: \(provider, privacy: .public)")
        }
        return success
    }

    /// Checks if an API key exists for a provider.
    func hasAPIKey(forProvider provider: String) -> Bool {
        getAPIKey(forProvider: provider) != nil
    }

    // MARK: - Custom Model API Keys

    /// Saves an API key for a custom model.
    @discardableResult
    func saveCustomModelAPIKey(_ key: String, forModelId modelId: UUID) -> Bool {
        let keyIdentifier = VoiceInkProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: modelId)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
    }

    /// Retrieves an API key for a custom model.
    func getCustomModelAPIKey(forModelId modelId: UUID) -> String? {
        let keyIdentifier = VoiceInkProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: modelId)
        guard let storedKey = keychain.getString(forKey: keyIdentifier) else { return nil }
        return VoiceInkAPIKeyReference.resolvedValue(storedKey)
    }

    /// Deletes an API key for a custom model.
    @discardableResult
    func deleteCustomModelAPIKey(forModelId modelId: UUID) -> Bool {
        let keyIdentifier = VoiceInkProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: modelId)
        let success = keychain.delete(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
    }

}
