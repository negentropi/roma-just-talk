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

public struct VoiceInkKeychainStringLoadResult: Equatable {
    public let status: OSStatus
    public let value: String?

    public init(status: OSStatus, data: Data?) {
        self.status = status
        self.value = VoiceInkKeychainValueStore.string(from: data)
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

public enum VoiceInkKeychainValueStore {
    public static func data(forString value: String) -> Data? {
        value.data(using: .utf8)
    }

    public static func string(from data: Data?) -> String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func saveString(
        _ value: String,
        account: String,
        syncable: Bool = true
    ) -> OSStatus? {
        guard let data = data(forString: value) else {
            return nil
        }

        return VoiceInkKeychainDataStore.saveData(data, account: account, syncable: syncable)
    }

    public static func loadString(
        account: String,
        syncable: Bool = true
    ) -> VoiceInkKeychainStringLoadResult {
        let result = VoiceInkKeychainDataStore.loadData(account: account, syncable: syncable)
        return VoiceInkKeychainStringLoadResult(status: result.status, data: result.data)
    }

    @discardableResult
    public static func deleteValue(
        account: String,
        syncable: Bool = true
    ) -> OSStatus {
        VoiceInkKeychainDataStore.delete(account: account, syncable: syncable)
    }

    public static func isSuccessfulDeleteStatus(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecItemNotFound
    }
}

public enum VoiceInkKeychainDiagnostics {
    public static func valueEncodingFailureMessage(key: String) -> String {
        "Failed to convert value to data for key: \(key)"
    }

    public static func itemLoadFailureMessage(key: String, status: OSStatus) -> String {
        "Failed to retrieve keychain item for key: \(key), status: \(status)"
    }

    public static func itemDeleteSuccessMessage(key: String) -> String {
        "Successfully deleted keychain item for key: \(key)"
    }

    public static func itemDeleteFailureMessage(key: String, status: OSStatus) -> String {
        "Failed to delete keychain item for key: \(key), status: \(status)"
    }

    public static func itemSaveSuccessMessage(key: String) -> String {
        "Successfully saved keychain item for key: \(key)"
    }

    public static func itemSaveFailureMessage(key: String, status: OSStatus) -> String {
        "Failed to save keychain item for key: \(key), status: \(status)"
    }
}

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

    @discardableResult
    public static func deleteStoredKeys(
        for providers: [VoiceInkProviderKind],
        deleteStoredKey: (String) -> OSStatus = {
            VoiceInkKeychainValueStore.deleteValue(account: $0)
        }
    ) -> [VoiceInkProviderAPIKeyStorageMutationResult] {
        providers.map { provider in
            self.deleteStoredKey(for: provider, deleteStoredKey: deleteStoredKey)
        }
    }
}

public enum VoiceInkProviderAPIKeyStorageDiagnostics {
    public static func saveFailureMessage(status: OSStatus) -> String {
        "Error saving API key to keychain: \(status)"
    }

    public static func savedProviderAPIKeyMessage(providerName: String, keyIdentifier: String) -> String {
        "Saved API key for provider: \(providerName) with key: \(keyIdentifier)"
    }

    public static func deletedProviderAPIKeyMessage(providerName: String) -> String {
        "Deleted API key for provider: \(providerName)"
    }

    public static func savedCustomModelAPIKeyMessage(modelId: UUID) -> String {
        "Saved API key for custom model: \(modelId.uuidString)"
    }

    public static func deletedCustomModelAPIKeyMessage(modelId: UUID) -> String {
        "Deleted API key for custom model: \(modelId.uuidString)"
    }
}

public enum VoiceInkProviderAPIKeyListRowTone: Equatable, Sendable {
    case verified
    case attention
}

public struct VoiceInkProviderAPIKeyListRowPresentation: Equatable, Sendable {
    public let title: String
    public let statusSystemImageName: String
    public let tone: VoiceInkProviderAPIKeyListRowTone
}

public struct VoiceInkProviderAPIKeyListRow: Identifiable, Equatable, Sendable {
    public let provider: VoiceInkProviderKind
    public let presentation: VoiceInkProviderAPIKeyListRowPresentation

    public var id: VoiceInkProviderKind { provider }

    public init(
        provider: VoiceInkProviderKind,
        presentation: VoiceInkProviderAPIKeyListRowPresentation
    ) {
        self.provider = provider
        self.presentation = presentation
    }
}

public struct VoiceInkProviderAPIKeyFormSnapshot: Equatable, Sendable {
    public let provider: VoiceInkProviderKind
    public let presentation: VoiceInkProviderAPIKeyFormPresentation
    public let isProviderReady: Bool
    public let isEditing: Bool
    public let enteredKey: String
    public let controlPresentation: VoiceInkProviderAPIKeyFormControlPresentation
    public let storedKeyPresentation: VoiceInkProviderAPIKeyStoredKeyPresentation?
    public let visibleResultFeedback: VoiceInkProviderAPIKeyVerificationFeedback?

    private let formState: VoiceInkProviderAPIKeyFormState
    private let storedKey: String
    private let storedRuntimeKey: String?

    fileprivate init(
        provider: VoiceInkProviderKind,
        formState: VoiceInkProviderAPIKeyFormState,
        storedKey: String,
        storedRuntimeKey: String?,
        isProviderReady: Bool
    ) {
        self.provider = provider
        self.presentation = provider.apiKeyFormPresentation
        self.isProviderReady = isProviderReady
        self.isEditing = formState.isEditing
        self.enteredKey = formState.enteredKey
        self.controlPresentation = formState.iOSControlPresentation(storedRuntimeKey: storedRuntimeKey)
        self.storedKeyPresentation = formState.iOSStoredKeyPresentation(storedKey: storedKey)
        self.visibleResultFeedback = formState.iOSVisibleResultFeedback(isProviderReady: isProviderReady)
        self.formState = formState
        self.storedKey = storedKey
        self.storedRuntimeKey = storedRuntimeKey
    }

    public var loadedFormState: VoiceInkProviderAPIKeyFormState {
        .loaded(storedKey: storedKey, isVerified: isProviderReady)
    }

    public var storedKeyEditPlan: VoiceInkProviderAPIKeyEditPlan {
        formState.iOSStoredKeyEditPlan(storedKey: storedKey)
    }

    public func verificationStartPlan(
        missingCandidatePolicy: VoiceInkProviderAPIKeyMissingVerificationCandidatePolicy
    ) -> VoiceInkProviderAPIKeyVerificationStartPlan {
        formState.verificationStartPlan(
            storedRuntimeKey: storedRuntimeKey,
            missingCandidatePolicy: missingCandidatePolicy
        )
    }
}

fileprivate enum VoiceInkProviderAPIKeyStatePersistenceAction: Equatable, Sendable {
    case persistStoredKey(String)
    case persistVerificationFlag(Bool)
}

public struct VoiceInkProviderAPIKeyStateUpdatePlan: Equatable, Sendable {
    private let state: VoiceInkProviderAPIKeyState
    private let persistenceActions: [VoiceInkProviderAPIKeyStatePersistenceAction]

    fileprivate init(
        state: VoiceInkProviderAPIKeyState,
        persistenceActions: [VoiceInkProviderAPIKeyStatePersistenceAction]
    ) {
        self.state = state
        self.persistenceActions = persistenceActions
    }

}

public extension VoiceInkProviderAPIKeyStateUpdatePlan {
    func applyRuntimeState(
        setAPIKeyState: (VoiceInkProviderAPIKeyState) -> Void,
        persistStoredKey: (String) -> Void,
        persistVerificationFlag: (Bool) -> Void
    ) {
        guard !persistenceActions.isEmpty else { return }

        setAPIKeyState(state)
        applyPersistenceActions(
            persistStoredKey: persistStoredKey,
            persistVerificationFlag: persistVerificationFlag
        )
    }

    private func applyPersistenceActions(
        persistStoredKey: (String) -> Void,
        persistVerificationFlag: (Bool) -> Void
    ) {
        for action in persistenceActions {
            switch action {
            case .persistStoredKey(let key):
                persistStoredKey(key)
            case .persistVerificationFlag(let flag):
                persistVerificationFlag(flag)
            }
        }
    }
}

public struct VoiceInkProviderAPIKeyState: Equatable, Sendable {
    private var storedKeysByProvider: [VoiceInkProviderKind: String]
    private var verifiedProviders: Set<VoiceInkProviderKind>

    public init(
        storedKeysByProvider: [VoiceInkProviderKind: String] = [:],
        verifiedProviders: Set<VoiceInkProviderKind> = []
    ) {
        self.storedKeysByProvider = storedKeysByProvider
        self.verifiedProviders = verifiedProviders.filter(\.requiresUserAPIKey)
    }

    public static func loadingStoredKeys(
        for providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders,
        verifiedProviders: Set<VoiceInkProviderKind>,
        loadStoredAPIKey: (VoiceInkProviderKind) -> String
    ) -> Self {
        let storedKeys: [VoiceInkProviderKind: String] = providers.reduce(into: [:]) { result, provider in
            guard provider.requiresUserAPIKey else { return }
            result[provider] = loadStoredAPIKey(provider)
        }

        return Self(
            storedKeysByProvider: storedKeys,
            verifiedProviders: verifiedProviders
        )
    }

    public func storedAPIKey(for provider: VoiceInkProviderKind) -> String {
        storedKeysByProvider[provider] ?? ""
    }

    public func runtimeAPIKey(for provider: VoiceInkProviderKind) -> String? {
        guard provider.requiresUserAPIKey else {
            return provider.runtimeAPIKeyIfAvailable(userAPIKey: "")
        }

        return VoiceInkProviderAPIKeyLookup.usableAPIKey(
            storedKey: storedKeysByProvider[provider],
            provider: provider
        )
    }

    public func isReady(
        for provider: VoiceInkProviderKind,
        localWhisperModelAvailable: Bool
    ) -> Bool {
        provider.isReady(
            userAPIKey: runtimeAPIKey(for: provider) ?? "",
            userAPIKeyVerified: verifiedProviders.contains(provider),
            localWhisperModelAvailable: localWhisperModelAvailable
        )
    }

    public func availableProviders(
        for use: VoiceInkProviderModelUse,
        localWhisperModelAvailable: Bool
    ) -> [VoiceInkProviderKind] {
        VoiceInkProviderKind.availableProviders(for: use) { provider in
            isReady(
                for: provider,
                localWhisperModelAvailable: localWhisperModelAvailable
            )
        }
    }

    public func listRowPresentation(
        for provider: VoiceInkProviderKind,
        localWhisperModelAvailable: Bool
    ) -> VoiceInkProviderAPIKeyListRowPresentation {
        let isReady = isReady(
            for: provider,
            localWhisperModelAvailable: localWhisperModelAvailable
        )

        return VoiceInkProviderAPIKeyListRowPresentation(
            title: provider.displayName,
            statusSystemImageName: isReady
                ? "checkmark.seal.fill"
                : "exclamationmark.triangle.fill",
            tone: isReady ? .verified : .attention
        )
    }

    public func listRows(
        for providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders,
        localWhisperModelAvailable: Bool
    ) -> [VoiceInkProviderAPIKeyListRow] {
        providers
            .filter(\.requiresUserAPIKey)
            .map { provider in
                VoiceInkProviderAPIKeyListRow(
                    provider: provider,
                    presentation: listRowPresentation(
                        for: provider,
                        localWhisperModelAvailable: localWhisperModelAvailable
                    )
                )
            }
    }

    fileprivate mutating func applyStoredAPIKey(
        _ key: String,
        for provider: VoiceInkProviderKind
    ) -> [VoiceInkProviderAPIKeyStatePersistenceAction] {
        guard provider.requiresUserAPIKey else {
            return []
        }

        let oldKey = storedKeysByProvider[provider] ?? ""
        storedKeysByProvider[provider] = key

        guard oldKey != key else {
            return [.persistStoredKey(key)]
        }

        verifiedProviders.remove(provider)
        return [
            .persistStoredKey(key),
            .persistVerificationFlag(false)
        ]
    }

    fileprivate mutating func applyVerification(
        _ verified: Bool,
        for provider: VoiceInkProviderKind
    ) -> [VoiceInkProviderAPIKeyStatePersistenceAction] {
        guard provider.requiresUserAPIKey else {
            return []
        }

        if verified {
            verifiedProviders.insert(provider)
        } else {
            verifiedProviders.remove(provider)
        }
        return [.persistVerificationFlag(verified)]
    }
}

public extension VoiceInkProviderAPIKeyState {
    func applyingStoredAPIKey(
        _ key: String,
        for provider: VoiceInkProviderKind
    ) -> VoiceInkProviderAPIKeyStateUpdatePlan {
        var updatedState = self
        let persistenceActions = updatedState.applyStoredAPIKey(key, for: provider)
        return VoiceInkProviderAPIKeyStateUpdatePlan(
            state: updatedState,
            persistenceActions: persistenceActions
        )
    }

    func applyingVerification(
        _ verified: Bool,
        for provider: VoiceInkProviderKind
    ) -> VoiceInkProviderAPIKeyStateUpdatePlan {
        var updatedState = self
        let persistenceActions = updatedState.applyVerification(verified, for: provider)
        return VoiceInkProviderAPIKeyStateUpdatePlan(
            state: updatedState,
            persistenceActions: persistenceActions
        )
    }

    func applyingEditPlan(
        _ plan: VoiceInkProviderAPIKeyEditPlan,
        for provider: VoiceInkProviderKind
    ) -> VoiceInkProviderAPIKeyStateUpdatePlan {
        guard let verificationFlag = plan.verificationFlagToPersist else {
            return VoiceInkProviderAPIKeyStateUpdatePlan(state: self, persistenceActions: [])
        }

        return applyingVerification(verificationFlag, for: provider)
    }

    func applyingVerificationPlan(
        _ plan: VoiceInkProviderAPIKeyVerificationApplicationPlan,
        for provider: VoiceInkProviderKind
    ) -> VoiceInkProviderAPIKeyStateUpdatePlan {
        guard let persistenceApplicationPlan = plan.successPersistenceApplicationPlan else {
            return VoiceInkProviderAPIKeyStateUpdatePlan(state: self, persistenceActions: [])
        }

        var updatedState = self
        var persistenceActions: [VoiceInkProviderAPIKeyStatePersistenceAction] = []
        persistenceApplicationPlan.applyRuntimeState(
            saveKey: { key in
                persistenceActions.append(contentsOf: updatedState.applyStoredAPIKey(key, for: provider))
            },
            persistVerificationFlag: { flag in
                persistenceActions.append(contentsOf: updatedState.applyVerification(flag, for: provider))
            }
        )

        return VoiceInkProviderAPIKeyStateUpdatePlan(
            state: updatedState,
            persistenceActions: persistenceActions
        )
    }
}

public struct VoiceInkProviderAccessSnapshot: Equatable, Sendable {
    public let apiKeyState: VoiceInkProviderAPIKeyState
    public let localWhisperModelAvailable: Bool

    public init(
        apiKeyState: VoiceInkProviderAPIKeyState,
        localWhisperModelAvailable: Bool
    ) {
        self.apiKeyState = apiKeyState
        self.localWhisperModelAvailable = localWhisperModelAvailable
    }

    public func isProviderReady(for provider: VoiceInkProviderKind) -> Bool {
        apiKeyState.isReady(
            for: provider,
            localWhisperModelAvailable: localWhisperModelAvailable
        )
    }

    public func apiKeyListRows() -> [VoiceInkProviderAPIKeyListRow] {
        apiKeyState.listRows(localWhisperModelAvailable: localWhisperModelAvailable)
    }

    public func availableProviders(for use: VoiceInkProviderModelUse) -> [VoiceInkProviderKind] {
        apiKeyState.availableProviders(
            for: use,
            localWhisperModelAvailable: localWhisperModelAvailable
        )
    }

    public var modeFormProviderAvailability: VoiceInkModeFormProviderAvailability {
        VoiceInkModeFormProviderAvailability(
            transcriptionProviders: availableProviders(for: .transcription),
            postProcessingProviders: availableProviders(for: .postProcessing)
        )
    }

    public func apiKeyFormSnapshot(
        for provider: VoiceInkProviderKind,
        formState: VoiceInkProviderAPIKeyFormState
    ) -> VoiceInkProviderAPIKeyFormSnapshot {
        VoiceInkProviderAPIKeyFormSnapshot(
            provider: provider,
            formState: formState,
            storedKey: apiKeyState.storedAPIKey(for: provider),
            storedRuntimeKey: apiKeyState.runtimeAPIKey(for: provider),
            isProviderReady: isProviderReady(for: provider)
        )
    }
}
