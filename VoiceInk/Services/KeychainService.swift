import Foundation
import Security
import os
import VoiceInkCore

/// Securely stores and retrieves API keys using Keychain with iCloud sync.
/// For local (unsigned) builds, uses UserDefaults instead since Keychain
/// requires stable code signing to reliably persist data across rebuilds.
final class KeychainService {
    static let shared = KeychainService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "KeychainService")

    #if LOCAL_BUILD
    private let defaults = UserDefaults.standard
    private let localPrefix = "LocalKeychain_"
    #endif

    private init() {}

    // MARK: - Public API

    /// Saves a string value to Keychain.
    @discardableResult
    func save(_ value: String, forKey key: String, syncable: Bool = true) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to convert value to data for key: \(key, privacy: .public)")
            return false
        }
        return save(data: data, forKey: key, syncable: syncable)
    }

    /// Saves data to Keychain.
    @discardableResult
    func save(data: Data, forKey key: String, syncable: Bool = true) -> Bool {
        #if LOCAL_BUILD
        defaults.set(data, forKey: localPrefix + key)
        return true
        #else
        // First, try to delete any existing item to avoid duplicates
        delete(forKey: key, syncable: syncable)

        let status = SecItemAdd(
            VoiceInkKeychainQuery.add(data: data, account: key, syncable: syncable) as CFDictionary,
            nil
        )

        if status == errSecSuccess {
            logger.info("Successfully saved keychain item for key: \(key, privacy: .public)")
            return true
        } else {
            logger.error("Failed to save keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)")
            return false
        }
        #endif
    }

    /// Retrieves a string value from Keychain.
    func getString(forKey key: String, syncable: Bool = true) -> String? {
        guard let data = getData(forKey: key, syncable: syncable) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieves data from Keychain.
    func getData(forKey key: String, syncable: Bool = true) -> Data? {
        #if LOCAL_BUILD
        return defaults.data(forKey: localPrefix + key)
        #else
        var result: AnyObject?
        let status = SecItemCopyMatching(
            VoiceInkKeychainQuery.copyData(account: key, syncable: syncable) as CFDictionary,
            &result
        )

        if status == errSecSuccess {
            return result as? Data
        } else if status != errSecItemNotFound {
            logger.error("Failed to retrieve keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)")
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
        let status = SecItemDelete(
            VoiceInkKeychainQuery.base(account: key, syncable: syncable) as CFDictionary
        )

        if status == errSecSuccess || status == errSecItemNotFound {
            if status == errSecSuccess {
                logger.info("Successfully deleted keychain item for key: \(key, privacy: .public)")
            }
            return true
        } else {
            logger.error("Failed to delete keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)")
            return false
        }
        #endif
    }

    /// Checks if a key exists in Keychain.
    func exists(forKey key: String, syncable: Bool = true) -> Bool {
        #if LOCAL_BUILD
        return defaults.data(forKey: localPrefix + key) != nil
        #else
        let status = SecItemCopyMatching(
            VoiceInkKeychainQuery.exists(account: key, syncable: syncable) as CFDictionary,
            nil
        )
        return status == errSecSuccess
        #endif
    }
}
