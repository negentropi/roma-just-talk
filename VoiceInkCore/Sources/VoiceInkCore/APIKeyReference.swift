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
