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
