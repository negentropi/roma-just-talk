import Foundation
import Security
import os
import RomaCore

/// Securely stores and retrieves API keys using Keychain with iCloud sync.
/// For local (unsigned) builds, uses UserDefaults instead since Keychain
/// requires stable code signing to reliably persist data across rebuilds.
final class KeychainService {
    static let shared = KeychainService()

    private let logger = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaMacOSLogCategory.keychainService)

    #if LOCAL_BUILD
    private let defaults = UserDefaults.standard
    private let localPrefix = "LocalKeychain_"
    #endif

    private init() {}

    // MARK: - Public API

    /// Saves a string value to Keychain.
    @discardableResult
    func save(_ value: String, forKey key: String, syncable: Bool = true) -> Bool {
        #if LOCAL_BUILD
        guard let data = RomaKeychainValueStore.data(forString: value) else {
            let message = RomaKeychainDiagnostics.valueEncodingFailureMessage(key: key)
            logger.error("\(message, privacy: .public)")
            return false
        }
        defaults.set(data, forKey: localPrefix + key)
        return true
        #else
        guard let status = RomaKeychainValueStore.saveString(value, account: key, syncable: syncable) else {
            let message = RomaKeychainDiagnostics.valueEncodingFailureMessage(key: key)
            logger.error("\(message, privacy: .public)")
            return false
        }
        return didSave(status: status, key: key)
        #endif
    }

    /// Saves data to Keychain.
    @discardableResult
    func save(data: Data, forKey key: String, syncable: Bool = true) -> Bool {
        #if LOCAL_BUILD
        defaults.set(data, forKey: localPrefix + key)
        return true
        #else
        let status = RomaKeychainDataStore.saveData(data, account: key, syncable: syncable)

        return didSave(status: status, key: key)
        #endif
    }

    /// Retrieves a string value from Keychain.
    func getString(forKey key: String, syncable: Bool = true) -> String? {
        #if LOCAL_BUILD
        guard let data = getData(forKey: key, syncable: syncable) else {
            return nil
        }
        return RomaKeychainValueStore.string(from: data)
        #else
        let result = RomaKeychainValueStore.loadString(account: key, syncable: syncable)

        if result.isSuccess {
            return result.value
        } else if result.status != errSecItemNotFound {
            let message = RomaKeychainDiagnostics.itemLoadFailureMessage(key: key, status: result.status)
            logger.error("\(message, privacy: .public)")
        }

        return nil
        #endif
    }

    /// Retrieves data from Keychain.
    func getData(forKey key: String, syncable: Bool = true) -> Data? {
        #if LOCAL_BUILD
        return defaults.data(forKey: localPrefix + key)
        #else
        let result = RomaKeychainDataStore.loadData(account: key, syncable: syncable)

        if result.isSuccess {
            return result.data
        } else if result.status != errSecItemNotFound {
            let message = RomaKeychainDiagnostics.itemLoadFailureMessage(key: key, status: result.status)
            logger.error("\(message, privacy: .public)")
        }

        return nil
        #endif
    }

    /// Deletes an item from Keychain.
    @discardableResult
    func delete(forKey key: String, syncable: Bool = true) -> Bool {
        #if LOCAL_BUILD
        defaults.removeObject(forKey: localPrefix + key)
        return true
        #else
        let status = RomaKeychainValueStore.deleteValue(account: key, syncable: syncable)

        if RomaKeychainValueStore.isSuccessfulDeleteStatus(status) {
            if status == errSecSuccess {
                let message = RomaKeychainDiagnostics.itemDeleteSuccessMessage(key: key)
                logger.info("\(message, privacy: .public)")
            }
            return true
        } else {
            let message = RomaKeychainDiagnostics.itemDeleteFailureMessage(key: key, status: status)
            logger.error("\(message, privacy: .public)")
            return false
        }
        #endif
    }

    /// Checks if a key exists in Keychain.
    func exists(forKey key: String, syncable: Bool = true) -> Bool {
        #if LOCAL_BUILD
        return defaults.data(forKey: localPrefix + key) != nil
        #else
        return RomaKeychainDataStore.exists(account: key, syncable: syncable)
        #endif
    }

    private func didSave(status: OSStatus, key: String) -> Bool {
        if status == errSecSuccess {
            let message = RomaKeychainDiagnostics.itemSaveSuccessMessage(key: key)
            logger.info("\(message, privacy: .public)")
            return true
        } else {
            let message = RomaKeychainDiagnostics.itemSaveFailureMessage(key: key, status: status)
            logger.error("\(message, privacy: .public)")
            return false
        }
    }
}
