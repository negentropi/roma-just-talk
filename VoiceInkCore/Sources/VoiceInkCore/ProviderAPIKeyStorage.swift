import Foundation
import Security

public struct VoiceInkProviderAPIKeyStorageMutationResult: Equatable, Sendable {
    public let account: String?
    public let status: OSStatus?

    public init(account: String?, status: OSStatus?) {
        self.account = account
        self.status = status
    }

    public var shouldReportFailure: Bool {
        guard let status else { return false }
        return status != errSecSuccess
    }
}

public enum VoiceInkProviderAPIKeyStorage {
    public static func account(for provider: VoiceInkProviderKind) -> String? {
        provider.apiKeyAccount
    }

    public static func storedKey(
        for provider: VoiceInkProviderKind,
        loadStoredKey: (String) -> String? = {
            VoiceInkKeychainValueStore.loadString(account: $0).value
        }
    ) -> String {
        guard let account = account(for: provider) else { return "" }
        return loadStoredKey(account) ?? ""
    }

    @discardableResult
    public static func saveStoredKey(
        _ key: String,
        for provider: VoiceInkProviderKind,
        saveStoredKey: (String, String) -> OSStatus? = {
            VoiceInkKeychainValueStore.saveString($0, account: $1)
        }
    ) -> VoiceInkProviderAPIKeyStorageMutationResult {
        guard let account = account(for: provider) else {
            return VoiceInkProviderAPIKeyStorageMutationResult(account: nil, status: nil)
        }

        return VoiceInkProviderAPIKeyStorageMutationResult(
            account: account,
            status: saveStoredKey(key, account)
        )
    }

    @discardableResult
    public static func deleteStoredKey(
        for provider: VoiceInkProviderKind,
        deleteStoredKey: (String) -> OSStatus = {
            VoiceInkKeychainValueStore.deleteValue(account: $0)
        }
    ) -> VoiceInkProviderAPIKeyStorageMutationResult {
        guard let account = account(for: provider) else {
            return VoiceInkProviderAPIKeyStorageMutationResult(account: nil, status: nil)
        }

        return VoiceInkProviderAPIKeyStorageMutationResult(
            account: account,
            status: deleteStoredKey(account)
        )
    }
}

public enum VoiceInkProviderAPIKeyStorageDiagnostics {
    public static func saveFailureMessage(status: OSStatus) -> String {
        "Error saving API key to keychain: \(status)"
    }
}
