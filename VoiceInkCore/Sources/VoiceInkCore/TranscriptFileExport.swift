import Foundation

public enum VoiceInkTranscriptFileExport {
    public static let defaultBaseFilename = "transcription"
    public static let plainTextFileExtension = "txt"
    public static let markdownFileExtension = "md"

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

    public static func markdownContent(
        for text: String,
        date: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        markdownContent(
            for: text,
            timestamp: timestampString(for: date, locale: locale, timeZone: timeZone)
        )
    }

    public static func markdownContent(for text: String, timestamp: String) -> String {
        """
        # Transcription

        **Date:** \(timestamp)

        \(text)
        """
    }

    static func timestampString(for date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
