import Foundation
import Security

public enum RomaKeychainQuery {
    public static let service = RomaAppIdentity.bundleIdentifier

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

public struct RomaKeychainLoadResult: Equatable {
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

public struct RomaKeychainStringLoadResult: Equatable {
    public let status: OSStatus
    public let value: String?

    public init(status: OSStatus, data: Data?) {
        self.status = status
        self.value = RomaKeychainValueStore.string(from: data)
    }

    public var isSuccess: Bool {
        status == errSecSuccess
    }
}

public enum RomaKeychainDataStore {
    @discardableResult
    public static func saveData(
        _ data: Data,
        account: String,
        syncable: Bool = true
    ) -> OSStatus {
        delete(account: account, syncable: syncable)

        return SecItemAdd(
            RomaKeychainQuery.add(data: data, account: account, syncable: syncable) as CFDictionary,
            nil
        )
    }

    public static func loadData(
        account: String,
        syncable: Bool = true
    ) -> RomaKeychainLoadResult {
        var result: AnyObject?
        let status = SecItemCopyMatching(
            RomaKeychainQuery.copyData(account: account, syncable: syncable) as CFDictionary,
            &result
        )

        return RomaKeychainLoadResult(status: status, data: result as? Data)
    }

    @discardableResult
    public static func delete(
        account: String,
        syncable: Bool = true
    ) -> OSStatus {
        SecItemDelete(
            RomaKeychainQuery.delete(account: account, syncable: syncable) as CFDictionary
        )
    }

    public static func exists(
        account: String,
        syncable: Bool = true
    ) -> Bool {
        SecItemCopyMatching(
            RomaKeychainQuery.exists(account: account, syncable: syncable) as CFDictionary,
            nil
        ) == errSecSuccess
    }
}

public enum RomaKeychainValueStore {
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

        return RomaKeychainDataStore.saveData(data, account: account, syncable: syncable)
    }

    public static func loadString(
        account: String,
        syncable: Bool = true
    ) -> RomaKeychainStringLoadResult {
        let result = RomaKeychainDataStore.loadData(account: account, syncable: syncable)
        return RomaKeychainStringLoadResult(status: result.status, data: result.data)
    }

    @discardableResult
    public static func deleteValue(
        account: String,
        syncable: Bool = true
    ) -> OSStatus {
        RomaKeychainDataStore.delete(account: account, syncable: syncable)
    }

    public static func isSuccessfulDeleteStatus(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecItemNotFound
    }
}

public enum RomaKeychainDiagnostics {
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

public struct RomaProviderAPIKeyStorageMutationResult: Equatable, Sendable {
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

public enum RomaProviderAPIKeyStorage {
    public static func account(for provider: RomaProviderKind) -> String? {
        provider.apiKeyAccount
    }

    public static func storedKey(
        for provider: RomaProviderKind,
        loadStoredKey: (String) -> String? = {
            RomaKeychainValueStore.loadString(account: $0).value
        }
    ) -> String {
        guard let account = account(for: provider) else { return "" }
        return loadStoredKey(account) ?? ""
    }

    @discardableResult
    public static func saveStoredKey(
        _ key: String,
        for provider: RomaProviderKind,
        saveStoredKey: (String, String) -> OSStatus? = {
            RomaKeychainValueStore.saveString($0, account: $1)
        }
    ) -> RomaProviderAPIKeyStorageMutationResult {
        guard let account = account(for: provider) else {
            return RomaProviderAPIKeyStorageMutationResult(account: nil, status: nil)
        }

        return RomaProviderAPIKeyStorageMutationResult(
            account: account,
            status: saveStoredKey(key, account)
        )
    }

    @discardableResult
    public static func deleteStoredKey(
        for provider: RomaProviderKind,
        deleteStoredKey: (String) -> OSStatus = {
            RomaKeychainValueStore.deleteValue(account: $0)
        }
    ) -> RomaProviderAPIKeyStorageMutationResult {
        guard let account = account(for: provider) else {
            return RomaProviderAPIKeyStorageMutationResult(account: nil, status: nil)
        }

        return RomaProviderAPIKeyStorageMutationResult(
            account: account,
            status: deleteStoredKey(account)
        )
    }

    @discardableResult
    public static func deleteStoredKeys(
        for providers: [RomaProviderKind],
        deleteStoredKey: (String) -> OSStatus = {
            RomaKeychainValueStore.deleteValue(account: $0)
        }
    ) -> [RomaProviderAPIKeyStorageMutationResult] {
        providers.map { provider in
            self.deleteStoredKey(for: provider, deleteStoredKey: deleteStoredKey)
        }
    }
}

public enum RomaProviderAPIKeyStorageDiagnostics {
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

public enum RomaProviderAPIKeyListRowTone: Equatable, Sendable {
    case verified
    case attention
}

public struct RomaProviderAPIKeyListRowPresentation: Equatable, Sendable {
    public let title: String
    public let statusSystemImageName: String
    public let tone: RomaProviderAPIKeyListRowTone
}

public struct RomaProviderAPIKeyListRow: Identifiable, Equatable, Sendable {
    public let provider: RomaProviderKind
    public let presentation: RomaProviderAPIKeyListRowPresentation

    public var id: RomaProviderKind { provider }

    public init(
        provider: RomaProviderKind,
        presentation: RomaProviderAPIKeyListRowPresentation
    ) {
        self.provider = provider
        self.presentation = presentation
    }
}

public struct RomaProviderAPIKeyFormSnapshot: Equatable, Sendable {
    public let provider: RomaProviderKind
    public let presentation: RomaProviderAPIKeyFormPresentation
    public let isProviderReady: Bool
    public let isEditing: Bool
    public let enteredKey: String
    public let controlPresentation: RomaProviderAPIKeyFormControlPresentation
    public let storedKeyPresentation: RomaProviderAPIKeyStoredKeyPresentation?
    public let visibleResultFeedback: RomaProviderAPIKeyVerificationFeedback?

    private let formState: RomaProviderAPIKeyFormState
    private let storedKey: String
    private let storedRuntimeKey: String?

    fileprivate init(
        provider: RomaProviderKind,
        formState: RomaProviderAPIKeyFormState,
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

    public var loadedFormState: RomaProviderAPIKeyFormState {
        .loaded(storedKey: storedKey, isVerified: isProviderReady)
    }

    public var storedKeyEditPlan: RomaProviderAPIKeyEditPlan {
        formState.iOSStoredKeyEditPlan(storedKey: storedKey)
    }

    public func verificationStartPlan(
        missingCandidatePolicy: RomaProviderAPIKeyMissingVerificationCandidatePolicy
    ) -> RomaProviderAPIKeyVerificationStartPlan {
        formState.verificationStartPlan(
            storedRuntimeKey: storedRuntimeKey,
            missingCandidatePolicy: missingCandidatePolicy
        )
    }
}

fileprivate enum RomaProviderAPIKeyStatePersistenceAction: Equatable, Sendable {
    case persistStoredKey(String)
    case persistVerificationFlag(Bool)
}

public struct RomaProviderAPIKeyStateUpdatePlan: Equatable, Sendable {
    private let state: RomaProviderAPIKeyState
    private let persistenceActions: [RomaProviderAPIKeyStatePersistenceAction]

    fileprivate init(
        state: RomaProviderAPIKeyState,
        persistenceActions: [RomaProviderAPIKeyStatePersistenceAction]
    ) {
        self.state = state
        self.persistenceActions = persistenceActions
    }

}

public extension RomaProviderAPIKeyStateUpdatePlan {
    func applyRuntimeState(
        setAPIKeyState: (RomaProviderAPIKeyState) -> Void,
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

public struct RomaProviderAPIKeyState: Equatable, Sendable {
    private var storedKeysByProvider: [RomaProviderKind: String]
    private var verifiedProviders: Set<RomaProviderKind>

    public init(
        storedKeysByProvider: [RomaProviderKind: String] = [:],
        verifiedProviders: Set<RomaProviderKind> = []
    ) {
        self.storedKeysByProvider = storedKeysByProvider
        self.verifiedProviders = verifiedProviders.filter(\.requiresUserAPIKey)
    }

    public static func loadingStoredKeys(
        for providers: [RomaProviderKind] = RomaProviderKind.userAPIKeyProviders,
        verifiedProviders: Set<RomaProviderKind>,
        loadStoredAPIKey: (RomaProviderKind) -> String
    ) -> Self {
        let storedKeys: [RomaProviderKind: String] = providers.reduce(into: [:]) { result, provider in
            guard provider.requiresUserAPIKey else { return }
            result[provider] = loadStoredAPIKey(provider)
        }

        return Self(
            storedKeysByProvider: storedKeys,
            verifiedProviders: verifiedProviders
        )
    }

    public func storedAPIKey(for provider: RomaProviderKind) -> String {
        storedKeysByProvider[provider] ?? ""
    }

    public func runtimeAPIKey(for provider: RomaProviderKind) -> String? {
        guard provider.requiresUserAPIKey else {
            return provider.runtimeAPIKeyIfAvailable(userAPIKey: "")
        }

        return RomaProviderAPIKeyLookup.usableAPIKey(
            storedKey: storedKeysByProvider[provider],
            provider: provider
        )
    }

    public func isReady(
        for provider: RomaProviderKind,
        localWhisperModelAvailable: Bool,
        localFluidAudioModelAvailable: Bool = false,
        nativeAppleSpeechAvailable: Bool = false,
        customCloudModelAvailable: Bool = false,
        localEnhancementServiceAvailable: Bool = false
    ) -> Bool {
        provider.isReady(
            userAPIKey: runtimeAPIKey(for: provider) ?? "",
            userAPIKeyVerified: verifiedProviders.contains(provider),
            localWhisperModelAvailable: localWhisperModelAvailable,
            localFluidAudioModelAvailable: localFluidAudioModelAvailable,
            nativeAppleSpeechAvailable: nativeAppleSpeechAvailable,
            customCloudModelAvailable: customCloudModelAvailable,
            localEnhancementServiceAvailable: localEnhancementServiceAvailable
        )
    }

    public func availableProviders(
        for use: RomaProviderModelUse,
        localWhisperModelAvailable: Bool,
        localFluidAudioModelAvailable: Bool = false,
        nativeAppleSpeechAvailable: Bool = false,
        customCloudModelAvailable: Bool = false,
        localEnhancementServiceAvailable: Bool = false
    ) -> [RomaProviderKind] {
        RomaProviderKind.availableProviders(for: use) { provider in
            isReady(
                for: provider,
                localWhisperModelAvailable: localWhisperModelAvailable,
                localFluidAudioModelAvailable: localFluidAudioModelAvailable,
                nativeAppleSpeechAvailable: nativeAppleSpeechAvailable,
                customCloudModelAvailable: customCloudModelAvailable,
                localEnhancementServiceAvailable: localEnhancementServiceAvailable
            )
        }
    }

    public func listRowPresentation(
        for provider: RomaProviderKind,
        localWhisperModelAvailable: Bool
    ) -> RomaProviderAPIKeyListRowPresentation {
        let isReady = isReady(
            for: provider,
            localWhisperModelAvailable: localWhisperModelAvailable
        )

        return RomaProviderAPIKeyListRowPresentation(
            title: provider.displayName,
            statusSystemImageName: isReady
                ? "checkmark.seal.fill"
                : "exclamationmark.triangle.fill",
            tone: isReady ? .verified : .attention
        )
    }

    public func listRows(
        for providers: [RomaProviderKind] = RomaProviderKind.userAPIKeyProviders,
        localWhisperModelAvailable: Bool
    ) -> [RomaProviderAPIKeyListRow] {
        providers
            .filter(\.requiresUserAPIKey)
            .map { provider in
                RomaProviderAPIKeyListRow(
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
        for provider: RomaProviderKind
    ) -> [RomaProviderAPIKeyStatePersistenceAction] {
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
        for provider: RomaProviderKind
    ) -> [RomaProviderAPIKeyStatePersistenceAction] {
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

public extension RomaProviderAPIKeyState {
    func applyingStoredAPIKey(
        _ key: String,
        for provider: RomaProviderKind
    ) -> RomaProviderAPIKeyStateUpdatePlan {
        var updatedState = self
        let persistenceActions = updatedState.applyStoredAPIKey(key, for: provider)
        return RomaProviderAPIKeyStateUpdatePlan(
            state: updatedState,
            persistenceActions: persistenceActions
        )
    }

    func applyingVerification(
        _ verified: Bool,
        for provider: RomaProviderKind
    ) -> RomaProviderAPIKeyStateUpdatePlan {
        var updatedState = self
        let persistenceActions = updatedState.applyVerification(verified, for: provider)
        return RomaProviderAPIKeyStateUpdatePlan(
            state: updatedState,
            persistenceActions: persistenceActions
        )
    }

    func applyingEditPlan(
        _ plan: RomaProviderAPIKeyEditPlan,
        for provider: RomaProviderKind
    ) -> RomaProviderAPIKeyStateUpdatePlan {
        guard let verificationFlag = plan.verificationFlagToPersist else {
            return RomaProviderAPIKeyStateUpdatePlan(state: self, persistenceActions: [])
        }

        return applyingVerification(verificationFlag, for: provider)
    }

    func applyingVerificationPlan(
        _ plan: RomaProviderAPIKeyVerificationApplicationPlan,
        for provider: RomaProviderKind
    ) -> RomaProviderAPIKeyStateUpdatePlan {
        guard let persistenceApplicationPlan = plan.successPersistenceApplicationPlan else {
            return RomaProviderAPIKeyStateUpdatePlan(state: self, persistenceActions: [])
        }

        var updatedState = self
        var persistenceActions: [RomaProviderAPIKeyStatePersistenceAction] = []
        persistenceApplicationPlan.applyRuntimeState(
            saveKey: { key in
                persistenceActions.append(contentsOf: updatedState.applyStoredAPIKey(key, for: provider))
            },
            persistVerificationFlag: { flag in
                persistenceActions.append(contentsOf: updatedState.applyVerification(flag, for: provider))
            }
        )

        return RomaProviderAPIKeyStateUpdatePlan(
            state: updatedState,
            persistenceActions: persistenceActions
        )
    }
}

public struct RomaProviderAccessSnapshot: Equatable, Sendable {
    public let apiKeyState: RomaProviderAPIKeyState
    public let localWhisperModelAvailable: Bool
    public let localFluidAudioModelAvailable: Bool
    public let nativeAppleSpeechAvailable: Bool
    public let customCloudModelAvailable: Bool
    public let localEnhancementServiceAvailable: Bool

    public init(
        apiKeyState: RomaProviderAPIKeyState,
        localWhisperModelAvailable: Bool,
        localFluidAudioModelAvailable: Bool = false,
        nativeAppleSpeechAvailable: Bool = false,
        customCloudModelAvailable: Bool = false,
        localEnhancementServiceAvailable: Bool = false
    ) {
        self.apiKeyState = apiKeyState
        self.localWhisperModelAvailable = localWhisperModelAvailable
        self.localFluidAudioModelAvailable = localFluidAudioModelAvailable
        self.nativeAppleSpeechAvailable = nativeAppleSpeechAvailable
        self.customCloudModelAvailable = customCloudModelAvailable
        self.localEnhancementServiceAvailable = localEnhancementServiceAvailable
    }

    public func isProviderReady(for provider: RomaProviderKind) -> Bool {
        apiKeyState.isReady(
            for: provider,
            localWhisperModelAvailable: localWhisperModelAvailable,
            localFluidAudioModelAvailable: localFluidAudioModelAvailable,
            nativeAppleSpeechAvailable: nativeAppleSpeechAvailable,
            customCloudModelAvailable: customCloudModelAvailable,
            localEnhancementServiceAvailable: localEnhancementServiceAvailable
        )
    }

    public func apiKeyListRows() -> [RomaProviderAPIKeyListRow] {
        apiKeyState.listRows(localWhisperModelAvailable: localWhisperModelAvailable)
    }

    public func availableProviders(for use: RomaProviderModelUse) -> [RomaProviderKind] {
        apiKeyState.availableProviders(
            for: use,
            localWhisperModelAvailable: localWhisperModelAvailable,
            localFluidAudioModelAvailable: localFluidAudioModelAvailable,
            nativeAppleSpeechAvailable: nativeAppleSpeechAvailable,
            customCloudModelAvailable: customCloudModelAvailable,
            localEnhancementServiceAvailable: localEnhancementServiceAvailable
        )
    }

    public var modeFormProviderAvailability: RomaModeFormProviderAvailability {
        RomaModeFormProviderAvailability(
            transcriptionProviders: availableProviders(for: .transcription),
            postProcessingProviders: availableProviders(for: .postProcessing)
        )
    }

    public func apiKeyFormSnapshot(
        for provider: RomaProviderKind,
        formState: RomaProviderAPIKeyFormState
    ) -> RomaProviderAPIKeyFormSnapshot {
        RomaProviderAPIKeyFormSnapshot(
            provider: provider,
            formState: formState,
            storedKey: apiKeyState.storedAPIKey(for: provider),
            storedRuntimeKey: apiKeyState.runtimeAPIKey(for: provider),
            isProviderReady: isProviderReady(for: provider)
        )
    }
}
