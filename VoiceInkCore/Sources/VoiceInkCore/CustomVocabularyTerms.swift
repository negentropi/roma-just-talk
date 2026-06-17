import Foundation

public enum VoiceInkCustomVocabularyTerms {
    public static func normalized(_ terms: [String], limit: Int? = nil) -> [String] {
        var seen = Set<String>()
        var unique = [String]()

        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }

            seen.insert(key)
            unique.append(trimmed)

            if let limit, unique.count >= limit {
                break
            }
        }

        return unique
    }
}
