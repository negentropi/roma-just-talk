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

public struct VoiceInkTranscriptionCSVRecord: Equatable, Sendable {
    public let originalText: String
    public let enhancedText: String?
    public let enhancementModel: String?
    public let promptName: String?
    public let transcriptionModel: String?
    public let powerModeName: String?
    public let powerModeEmoji: String?
    public let enhancementTime: Double?
    public let transcriptionTime: Double?
    public let timestamp: Date
    public let duration: Double

    public init(
        originalText: String,
        enhancedText: String? = nil,
        enhancementModel: String? = nil,
        promptName: String? = nil,
        transcriptionModel: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        enhancementTime: Double? = nil,
        transcriptionTime: Double? = nil,
        timestamp: Date,
        duration: Double
    ) {
        self.originalText = originalText
        self.enhancedText = enhancedText
        self.enhancementModel = enhancementModel
        self.promptName = promptName
        self.transcriptionModel = transcriptionModel
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
        self.enhancementTime = enhancementTime
        self.transcriptionTime = transcriptionTime
        self.timestamp = timestamp
        self.duration = duration
    }
}

public enum VoiceInkTranscriptionCSVExporter {
    public static let defaultFilename = "VoiceInk-transcription.csv"
    public static let writeFailurePrefix = "Error writing CSV file:"
    public static let header = "Original Transcript,Enhanced Transcript,Enhancement Model,Prompt Name,Transcription Model,Power Mode,Enhancement Time,Transcription Time,Timestamp,Duration"

    public static func writeFailureDiagnosticMessage(errorDescription: String) -> String {
        "\(writeFailurePrefix) \(errorDescription)"
    }

    public static func csvString(for records: [VoiceInkTranscriptionCSVRecord]) -> String {
        var csvString = header + "\n"

        for record in records {
            let row = [
                escapeCSVString(record.originalText),
                escapeCSVString(record.enhancedText ?? ""),
                escapeCSVString(record.enhancementModel ?? ""),
                escapeCSVString(record.promptName ?? ""),
                escapeCSVString(record.transcriptionModel ?? ""),
                escapeCSVString(
                    VoiceInkPowerModePresentation.displayName(
                        name: record.powerModeName,
                        emoji: record.powerModeEmoji
                    )
                ),
                "\(record.enhancementTime ?? 0)",
                "\(record.transcriptionTime ?? 0)",
                record.timestamp.ISO8601Format(),
                "\(record.duration)"
            ].joined(separator: ",")

            csvString.append(row)
            csvString.append("\n")
        }

        return csvString
    }

    public static func escapeCSVString(_ string: String) -> String {
        let escapedString = string.replacingOccurrences(of: "\"", with: "\"\"")
        if escapedString.contains(",") || escapedString.contains("\n") {
            return "\"\(escapedString)\""
        }
        return escapedString
    }
}
