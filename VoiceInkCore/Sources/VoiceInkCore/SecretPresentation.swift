import Foundation

public enum VoiceInkSecretPresentation {
    public static func obfuscatedAPIKey(_ key: String) -> String? {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return nil
        }

        let count = trimmedKey.count
        if count <= 6 {
            return String(repeating: "•", count: count)
        }

        let prefixCount = min(4, count)
        let suffixCount = min(4, max(0, count - prefixCount))
        let start = trimmedKey.prefix(prefixCount)
        let end = trimmedKey.suffix(suffixCount)
        let middleCount = max(4, count - prefixCount - suffixCount)
        return "\(start)\(String(repeating: "•", count: middleCount))\(end)"
    }
}
