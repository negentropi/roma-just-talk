import Foundation
import OSLog
import RomaCore

final class LogExporter {
    static let shared = LogExporter()

    private let logger = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaMacOSLogCategory.logExporter)
    private let subsystem = RomaAppIdentity.loggingSubsystem

    private(set) var sessionStartDates: [Date] = []

    private init() {
        sessionStartDates = RomaDiagnosticLogExportPolicy.sessionStartDates(
            starting: Date(),
            storedDates: RomaDiagnosticLogExportPolicy.storedSessionStartDates()
        )
        saveSessions()

        logger.notice("🎙️ LogExporter initialized, \(self.sessionStartDates.count, privacy: .public) session(s) tracked")
    }

    private func saveSessions() {
        RomaDiagnosticLogExportPolicy.saveSessionStartDates(sessionStartDates)
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

        var logLines = RomaDiagnosticLogExportPolicy.headerLines(
            exportDate: Date(),
            subsystem: subsystem,
            sessionCount: sessionStartDates.count,
            systemInfo: systemInfo
        )

        // Fetch logs for each session (oldest first for chronological order)
        for range in RomaDiagnosticLogExportPolicy.sessionRanges(from: sessionStartDates).reversed() {
            logLines.append(contentsOf: RomaDiagnosticLogExportPolicy.sessionHeaderLines(label: range.label))

            let position = store.position(date: range.start)
            let entries = try store.getEntries(at: position, matching: predicate)

            var sessionLogCount = 0
            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }

                if let endDate = range.end, logEntry.date >= endDate { break }

                logLines.append(RomaDiagnosticLogExportPolicy.logEntryLine(
                    date: logEntry.date,
                    level: RomaDiagnosticLogExportPolicy.logLevelLabel(for: logEntry.level),
                    category: logEntry.category,
                    message: logEntry.composedMessage
                ))
                sessionLogCount += 1
            }

            if sessionLogCount == 0 {
                logLines.append(RomaDiagnosticLogExportPolicy.noLogsFoundMessage)
            }

            logLines.append("")
        }

        return logLines
    }

    private func saveLogsToFile(_ logs: [String]) throws -> URL {
        let fileName = RomaDiagnosticLogExportPolicy.fileName(for: Date())

        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw RomaDiagnosticLogExportPolicy.downloadsDirectoryUnavailableError()
        }

        let fileURL = downloadsURL.appendingPathComponent(fileName)
        let content = RomaDiagnosticLogExportPolicy.exportContent(from: logs)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}
