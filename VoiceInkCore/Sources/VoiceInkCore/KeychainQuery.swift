import Foundation
import Security

public enum VoiceInkKeychainQuery {
    public static let service = VoiceInkAppIdentity.bundleIdentifier

    public static func base(
        account: String,
        syncable: Bool = true
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]

        if syncable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }

        return query
    }

    public static func add(
        data: Data,
        account: String,
        syncable: Bool = true
    ) -> [String: Any] {
        var query = base(account: account, syncable: syncable)
        query[kSecValueData as String] = data
        return query
    }

    public static func copyData(
        account: String,
        syncable: Bool = true
    ) -> [String: Any] {
        var query = base(account: account, syncable: syncable)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    public static func delete(
        account: String,
        syncable: Bool = true
    ) -> [String: Any] {
        base(account: account, syncable: syncable)
    }

    public static func exists(
        account: String,
        syncable: Bool = true
    ) -> [String: Any] {
        var query = base(account: account, syncable: syncable)
        query[kSecReturnData as String] = kCFBooleanFalse
        return query
    }
}

public struct VoiceInkKeychainLoadResult: Equatable {
    public let status: OSStatus
    public let data: Data?

    public init(status: OSStatus, data: Data?) {
        self.status = status
        self.data = data
    }

    public var isSuccess: Bool {
        status == errSecSuccess
    }
}

public enum VoiceInkKeychainDataStore {
    @discardableResult
    public static func saveData(
        _ data: Data,
        account: String,
        syncable: Bool = true
    ) -> OSStatus {
        delete(account: account, syncable: syncable)

        return SecItemAdd(
            VoiceInkKeychainQuery.add(data: data, account: account, syncable: syncable) as CFDictionary,
            nil
        )
    }

    public static func loadData(
        account: String,
        syncable: Bool = true
    ) -> VoiceInkKeychainLoadResult {
        var result: AnyObject?
        let status = SecItemCopyMatching(
            VoiceInkKeychainQuery.copyData(account: account, syncable: syncable) as CFDictionary,
            &result
        )

        return VoiceInkKeychainLoadResult(status: status, data: result as? Data)
    }

    @discardableResult
    public static func delete(
        account: String,
        syncable: Bool = true
    ) -> OSStatus {
        SecItemDelete(
            VoiceInkKeychainQuery.delete(account: account, syncable: syncable) as CFDictionary
        )
    }

    public static func exists(
        account: String,
        syncable: Bool = true
    ) -> Bool {
        SecItemCopyMatching(
            VoiceInkKeychainQuery.exists(account: account, syncable: syncable) as CFDictionary,
            nil
        ) == errSecSuccess
    }
}
