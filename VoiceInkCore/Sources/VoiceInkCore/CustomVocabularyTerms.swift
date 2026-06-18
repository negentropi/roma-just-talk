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

    public static func normalized(_ terms: [String], for use: VoiceInkCustomVocabularyUse) -> [String] {
        normalized(terms, limit: use.termLimit)
    }
}

public enum VoiceInkCustomVocabularyUse: Equatable, Sendable {
    case batchTranscription(VoiceInkProviderKind)
    case streamingTranscription(VoiceInkProviderKind)
    case postProcessingContext

    var termLimit: Int? {
        switch self {
        case .streamingTranscription(.deepgram):
            return 50
        case .batchTranscription, .streamingTranscription, .postProcessingContext:
            return nil
        }
    }
}
