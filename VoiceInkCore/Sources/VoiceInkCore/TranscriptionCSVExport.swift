import Foundation

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
    public static let header = "Original Transcript,Enhanced Transcript,Enhancement Model,Prompt Name,Transcription Model,Power Mode,Enhancement Time,Transcription Time,Timestamp,Duration"

    public static func csvString(for records: [VoiceInkTranscriptionCSVRecord]) -> String {
        var csvString = header + "\n"

        for record in records {
            let row = [
                escapeCSVString(record.originalText),
                escapeCSVString(record.enhancedText ?? ""),
                escapeCSVString(record.enhancementModel ?? ""),
                escapeCSVString(record.promptName ?? ""),
                escapeCSVString(record.transcriptionModel ?? ""),
                escapeCSVString(powerModeDisplay(name: record.powerModeName, emoji: record.powerModeEmoji)),
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

    public static func powerModeDisplay(name: String?, emoji: String?) -> String {
        switch (emoji?.trimmingCharacters(in: .whitespacesAndNewlines), name?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (.some(emojiValue), .some(nameValue)) where !emojiValue.isEmpty && !nameValue.isEmpty:
            return "\(emojiValue) \(nameValue)"
        case let (.some(emojiValue), _) where !emojiValue.isEmpty:
            return emojiValue
        case let (_, .some(nameValue)) where !nameValue.isEmpty:
            return nameValue
        default:
            return ""
        }
    }
}
