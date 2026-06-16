import Foundation

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
