import Foundation

public enum VoiceInkTranscriptionOutputWhitespacePolicy: Sendable {
    case collapseRuns
    case preserveParagraphs
}

public enum VoiceInkTranscriptTextNormalizer {
    public static func collapseWhitespaceRunsAndTrim(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizeParagraphSpacing(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
    }

    public static func normalizeInlineWhitespaceAndTrim(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[^\S\r\n]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum VoiceInkTranscriptionOutputFilter {
    public static let defaultFillerWords = VoiceInkFillerWords.defaultWords

    private static let hallucinationPatterns = [
        #"\[.*?\]"#,
        #"\(.*?\)"#,
        #"\{.*?\}"#
    ]

    public static func filter(
        _ text: String,
        fillerWords: [String] = [],
        whitespacePolicy: VoiceInkTranscriptionOutputWhitespacePolicy = .collapseRuns
    ) -> String {
        var filteredText = removeTagBlocks(from: text)
        filteredText = removeBracketedHallucinations(from: filteredText)
        filteredText = removeFillerWords(fillerWords, from: filteredText)

        switch whitespacePolicy {
        case .collapseRuns:
            return VoiceInkTranscriptTextNormalizer.collapseWhitespaceRunsAndTrim(filteredText)
        case .preserveParagraphs:
            return VoiceInkTranscriptTextNormalizer.normalizeInlineWhitespaceAndTrim(filteredText)
        }
    }

    private static func removeTagBlocks(from text: String) -> String {
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        guard let regex = try? NSRegularExpression(pattern: tagBlockPattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private static func removeBracketedHallucinations(from text: String) -> String {
        var filteredText = text
        for pattern in hallucinationPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        return filteredText
    }

    private static func removeFillerWords(_ fillerWords: [String], from text: String) -> String {
        var filteredText = text
        for fillerWord in fillerWords {
            let normalizedFiller = fillerWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedFiller.isEmpty else { continue }

            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: normalizedFiller))\\b[,.]?"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        return filteredText
    }
}
