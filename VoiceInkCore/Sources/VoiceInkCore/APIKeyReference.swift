import Foundation

public enum VoiceInkAPIKeyReference {
    public static func resolvedValue(
        _ value: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let variableName: String
        if trimmed.hasPrefix("${"), trimmed.hasSuffix("}") {
            variableName = String(trimmed.dropFirst(2).dropLast())
        } else if trimmed.hasPrefix("$") {
            variableName = String(trimmed.dropFirst())
        } else {
            return trimmed
        }

        guard !variableName.isEmpty,
              variableName.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
              let resolvedValue = environment[variableName],
              VoiceInkProviderCredential.nonBlank(resolvedValue) != nil else {
            return nil
        }

        return resolvedValue
    }
}

public enum VoiceInkProviderAPIKeyLookup {
    public static func usableAPIKey(
        storedKey: String?,
        provider: VoiceInkProviderKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        usableAPIKey(
            storedKey: storedKey,
            providerName: provider.displayName,
            environment: environment
        )
    }

    public static func usableAPIKey(
        storedKey: String?,
        providerName: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let storedKey,
           let resolvedKey = VoiceInkAPIKeyReference.resolvedValue(storedKey, environment: environment),
           let apiKey = VoiceInkProviderCredential.nonBlank(resolvedKey) {
            return apiKey
        }

        guard let environmentKey = VoiceInkProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: providerName),
              let value = environment[environmentKey],
              let apiKey = VoiceInkProviderCredential.nonBlank(value) else {
            return nil
        }

        return apiKey
    }
}
