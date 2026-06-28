import Foundation

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

private struct VoiceInkProviderAPIKeyStorageMutationPlan: Equatable, Sendable {
    let shouldPersistStoredKey: Bool
    let verificationFlagToPersist: Bool?

    init(
        shouldPersistStoredKey: Bool,
        verificationFlagToPersist: Bool?
    ) {
        self.shouldPersistStoredKey = shouldPersistStoredKey
        self.verificationFlagToPersist = verificationFlagToPersist
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

    public var shouldApplyState: Bool {
        !persistenceActions.isEmpty
    }
}

public extension VoiceInkProviderAPIKeyStateUpdatePlan {
    func applyRuntimeState(
        setAPIKeyState: (VoiceInkProviderAPIKeyState) -> Void,
        persistStoredKey: (String) -> Void,
        persistVerificationFlag: (Bool) -> Void
    ) {
        guard shouldApplyState else { return }

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

private extension VoiceInkProviderAPIKeyStorageMutationPlan {
    func persistenceActions(storedKey: String) -> [VoiceInkProviderAPIKeyStatePersistenceAction] {
        guard shouldPersistStoredKey else { return [] }

        var actions: [VoiceInkProviderAPIKeyStatePersistenceAction] = [
            .persistStoredKey(storedKey)
        ]
        if let verificationFlagToPersist {
            actions.append(.persistVerificationFlag(verificationFlagToPersist))
        }
        return actions
    }
}

private struct VoiceInkProviderAPIKeyVerificationMutationPlan: Equatable, Sendable {
    let shouldPersistVerificationFlag: Bool

    init(shouldPersistVerificationFlag: Bool) {
        self.shouldPersistVerificationFlag = shouldPersistVerificationFlag
    }
}

private extension VoiceInkProviderAPIKeyVerificationMutationPlan {
    func persistenceActions(verificationFlag: Bool) -> [VoiceInkProviderAPIKeyStatePersistenceAction] {
        guard shouldPersistVerificationFlag else { return [] }
        return [.persistVerificationFlag(verificationFlag)]
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
    ) -> VoiceInkProviderAPIKeyStorageMutationPlan {
        guard provider.requiresUserAPIKey else {
            return VoiceInkProviderAPIKeyStorageMutationPlan(
                shouldPersistStoredKey: false,
                verificationFlagToPersist: nil
            )
        }

        let oldKey = storedKeysByProvider[provider] ?? ""
        storedKeysByProvider[provider] = key

        guard oldKey != key else {
            return VoiceInkProviderAPIKeyStorageMutationPlan(
                shouldPersistStoredKey: true,
                verificationFlagToPersist: nil
            )
        }

        verifiedProviders.remove(provider)
        return VoiceInkProviderAPIKeyStorageMutationPlan(
            shouldPersistStoredKey: true,
            verificationFlagToPersist: false
        )
    }

    fileprivate mutating func applyVerification(
        _ verified: Bool,
        for provider: VoiceInkProviderKind
    ) -> VoiceInkProviderAPIKeyVerificationMutationPlan {
        guard provider.requiresUserAPIKey else {
            return VoiceInkProviderAPIKeyVerificationMutationPlan(shouldPersistVerificationFlag: false)
        }

        if verified {
            verifiedProviders.insert(provider)
        } else {
            verifiedProviders.remove(provider)
        }
        return VoiceInkProviderAPIKeyVerificationMutationPlan(shouldPersistVerificationFlag: true)
    }
}

public extension VoiceInkProviderAPIKeyState {
    func applyingStoredAPIKey(
        _ key: String,
        for provider: VoiceInkProviderKind
    ) -> VoiceInkProviderAPIKeyStateUpdatePlan {
        var updatedState = self
        let mutationPlan = updatedState.applyStoredAPIKey(key, for: provider)
        return VoiceInkProviderAPIKeyStateUpdatePlan(
            state: updatedState,
            persistenceActions: mutationPlan.persistenceActions(storedKey: key)
        )
    }

    func applyingVerification(
        _ verified: Bool,
        for provider: VoiceInkProviderKind
    ) -> VoiceInkProviderAPIKeyStateUpdatePlan {
        var updatedState = self
        let mutationPlan = updatedState.applyVerification(verified, for: provider)
        return VoiceInkProviderAPIKeyStateUpdatePlan(
            state: updatedState,
            persistenceActions: mutationPlan.persistenceActions(verificationFlag: verified)
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
                let mutationPlan = updatedState.applyStoredAPIKey(key, for: provider)
                persistenceActions.append(contentsOf: mutationPlan.persistenceActions(storedKey: key))
            },
            persistVerificationFlag: { flag in
                let mutationPlan = updatedState.applyVerification(flag, for: provider)
                persistenceActions.append(contentsOf: mutationPlan.persistenceActions(verificationFlag: flag))
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

    public func isKeyVerified(for provider: VoiceInkProviderKind) -> Bool {
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
}
