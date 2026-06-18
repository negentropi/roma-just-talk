import Foundation

public enum VoiceInkTranscriptFileExport {
    public static let defaultBaseFilename = "transcription"

    public static func suggestedBaseFilename(for text: String) -> String {
        let cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let words = cleanedText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let wordCount = min(words.count, words.count <= 3 ? words.count : (words.count <= 6 ? 6 : 8))
        let selectedWords = Array(words.prefix(wordCount))

        if selectedWords.isEmpty { return defaultBaseFilename }

        let fileName = selectedWords.joined(separator: "-")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return fileName.isEmpty ? defaultBaseFilename : String(fileName.prefix(50))
    }

    public static func markdownContent(for text: String, timestamp: String) -> String {
        """
        # Transcription

        **Date:** \(timestamp)

        \(text)
        """
    }
}
