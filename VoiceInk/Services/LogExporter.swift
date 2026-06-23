import Foundation
import OSLog
import VoiceInkCore

final class LogExporter {
    static let shared = LogExporter()

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "LogExporter")
    private let subsystem = VoiceInkAppIdentity.loggingSubsystem

    private(set) var sessionStartDates: [Date] = []

    private init() {
        sessionStartDates = VoiceInkDiagnosticLogExportPolicy.sessionStartDates(
            starting: Date(),
            storedDates: VoiceInkDiagnosticLogExportPolicy.storedSessionStartDates()
        )
        saveSessions()

        logger.notice("🎙️ LogExporter initialized, \(self.sessionStartDates.count, privacy: .public) session(s) tracked")
    }

    private func saveSessions() {
        VoiceInkDiagnosticLogExportPolicy.saveSessionStartDates(sessionStartDates)
    }

    func exportLogs() async throws -> URL {
        logger.notice("🎙️ Starting log export")

        let logs = try await fetchLogs()
        let fileURL = try saveLogsToFile(logs)

        logger.notice("🎙️ Log export completed: \(fileURL.path, privacy: .public)")
        return fileURL
    }

    private func fetchLogs() async throws -> [String] {
        let systemInfo = await MainActor.run {
            SystemInfoService.shared.getSystemInfoString()
        }

        let store = try OSLogStore(scope: .system)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)

        var logLines = VoiceInkDiagnosticLogExportPolicy.headerLines(
            exportDate: Date(),
            subsystem: subsystem,
            sessionCount: sessionStartDates.count,
            systemInfo: systemInfo
        )

        // Fetch logs for each session (oldest first for chronological order)
        for range in VoiceInkDiagnosticLogExportPolicy.sessionRanges(from: sessionStartDates).reversed() {
            logLines.append(contentsOf: VoiceInkDiagnosticLogExportPolicy.sessionHeaderLines(label: range.label))

            let position = store.position(date: range.start)
            let entries = try store.getEntries(at: position, matching: predicate)

            var sessionLogCount = 0
            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }

                if let endDate = range.end, logEntry.date >= endDate { break }

                logLines.append(VoiceInkDiagnosticLogExportPolicy.logEntryLine(
                    date: logEntry.date,
                    level: VoiceInkDiagnosticLogExportPolicy.logLevelLabel(for: logEntry.level),
                    category: logEntry.category,
                    message: logEntry.composedMessage
                ))
                sessionLogCount += 1
            }

            if sessionLogCount == 0 {
                logLines.append(VoiceInkDiagnosticLogExportPolicy.noLogsFoundMessage)
            }

            logLines.append("")
        }

        return logLines
    }

    private func saveLogsToFile(_ logs: [String]) throws -> URL {
        let fileName = VoiceInkDiagnosticLogExportPolicy.fileName(for: Date())

        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw VoiceInkDiagnosticLogExportPolicy.downloadsDirectoryUnavailableError()
        }

        let fileURL = downloadsURL.appendingPathComponent(fileName)
        let content = logs.joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}
