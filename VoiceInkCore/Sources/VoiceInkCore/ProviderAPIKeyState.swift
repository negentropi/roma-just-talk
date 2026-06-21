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

public struct VoiceInkProviderAPIKeyStorageMutationPlan: Equatable, Sendable {
    public let shouldPersistStoredKey: Bool
    public let verificationFlagToPersist: Bool?

    public init(
        shouldPersistStoredKey: Bool,
        verificationFlagToPersist: Bool?
    ) {
        self.shouldPersistStoredKey = shouldPersistStoredKey
        self.verificationFlagToPersist = verificationFlagToPersist
    }
}

public struct VoiceInkProviderAPIKeyVerificationMutationPlan: Equatable, Sendable {
    public let shouldPersistVerificationFlag: Bool

    public init(shouldPersistVerificationFlag: Bool) {
        self.shouldPersistVerificationFlag = shouldPersistVerificationFlag
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

    public mutating func applyStoredAPIKey(
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

    public mutating func applyVerification(
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
