import Foundation

public struct VoiceInkDiagnosticLogSessionRange: Equatable, Sendable {
    public let label: String
    public let start: Date
    public let end: Date?

    public init(label: String, start: Date, end: Date?) {
        self.label = label
        self.start = start
        self.end = end
    }
}

public enum VoiceInkDiagnosticLogExportPolicy {
    public static let sessionStartDatesKey = "logExporter.sessionStartDates.v1"
    public static let maxSessionStartDatesToKeep = 3
    public static let timestampDateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    public static let fileNameDateFormat = "yyyy-MM-dd_HH-mm-ss"
    public static let fileNamePrefix = "VoiceInk_Logs_"
    public static let fileNameExtension = "log"
    public static let headerTitle = "=== VoiceInk Diagnostic Logs ==="
    public static let headerDivider = "================================"
    public static let noLogsFoundMessage = "No logs found for this session."

    public static func storedSessionStartDates(from defaults: UserDefaults = .standard) -> [Date] {
        guard let data = defaults.data(forKey: sessionStartDatesKey),
              let dates = try? JSONDecoder().decode([Date].self, from: data) else {
            return []
        }

        return dates
    }

    public static func saveSessionStartDates(
        _ dates: [Date],
        to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(dates) else {
            return
        }

        defaults.set(data, forKey: sessionStartDatesKey)
    }

    public static func sessionStartDates(
        starting currentDate: Date,
        storedDates: [Date]
    ) -> [Date] {
        Array(([currentDate] + storedDates).prefix(maxSessionStartDatesToKeep))
    }

    public static func sessionRanges(
        from sessionStartDates: [Date]
    ) -> [VoiceInkDiagnosticLogSessionRange] {
        let totalSessions = sessionStartDates.count
        return sessionStartDates.enumerated().map { index, start in
            let end: Date? = (index == 0) ? nil : sessionStartDates[index - 1]
            let sessionNumber = totalSessions - index
            return VoiceInkDiagnosticLogSessionRange(
                label: sessionLabel(
                    index: index,
                    totalSessions: totalSessions,
                    sessionNumber: sessionNumber
                ),
                start: start,
                end: end
            )
        }
    }

    public static func headerLines(
        exportDate: Date,
        subsystem: String,
        sessionCount: Int,
        systemInfo: String
    ) -> [String] {
        [
            headerTitle,
            "Export Date: \(formattedTimestamp(exportDate))",
            "Subsystem: \(subsystem)",
            "Total Sessions: \(sessionCount)",
            headerDivider,
            "",
            systemInfo,
            ""
        ]
    }

    public static func sessionHeaderLines(label: String) -> [String] {
        [
            "--- \(label) ---",
            ""
        ]
    }

    public static func logEntryLine(
        date: Date,
        level: String,
        category: String,
        message: String
    ) -> String {
        "[\(formattedTimestamp(date))] [\(level)] [\(category)] \(message)"
    }

    public static func fileName(for date: Date) -> String {
        "\(fileNamePrefix)\(formattedDate(date, format: fileNameDateFormat)).\(fileNameExtension)"
    }

    public static func formattedTimestamp(_ date: Date) -> String {
        formattedDate(date, format: timestampDateFormat)
    }

    private static func sessionLabel(
        index: Int,
        totalSessions: Int,
        sessionNumber: Int
    ) -> String {
        if totalSessions == 1 {
            return "Session 1 (Current)"
        } else if index == 0 {
            return "Session \(sessionNumber) (Current)"
        } else if index == totalSessions - 1 {
            return "Session 1 (Oldest)"
        } else {
            return "Session \(sessionNumber)"
        }
    }

    private static func formattedDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
