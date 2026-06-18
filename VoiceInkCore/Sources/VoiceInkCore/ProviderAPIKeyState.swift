import Foundation

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

    @discardableResult
    public mutating func setStoredAPIKey(
        _ key: String,
        for provider: VoiceInkProviderKind
    ) -> Bool {
        guard provider.requiresUserAPIKey else {
            return false
        }

        let oldKey = storedKeysByProvider[provider] ?? ""
        storedKeysByProvider[provider] = key

        guard oldKey != key else {
            return false
        }

        verifiedProviders.remove(provider)
        return true
    }

    @discardableResult
    public mutating func setVerified(
        _ verified: Bool,
        for provider: VoiceInkProviderKind
    ) -> Bool {
        guard provider.requiresUserAPIKey else {
            return false
        }

        if verified {
            verifiedProviders.insert(provider)
        } else {
            verifiedProviders.remove(provider)
        }
        return true
    }
}
