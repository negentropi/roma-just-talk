import Foundation
import OSLog
@testable import VoiceInkCore

final class DiagnosticLogExportPolicyTests: XCTestCase {
    func testDiagnosticsSettingsPresentationPreservesMacOSCopyAndIcons() {
        XCTAssertEqual(VoiceInkDiagnosticsSettingsPresentation.rollingBufferLastClaimLabel, "Rolling Buffer Last Claim")
        XCTAssertEqual(VoiceInkDiagnosticsSettingsPresentation.showInFinderButtonTitle, "Show in Finder")
        XCTAssertEqual(VoiceInkDiagnosticsSettingsPresentation.exportButtonTitle, "Export")
        XCTAssertEqual(VoiceInkDiagnosticsSettingsPresentation.exportLogsLabel, "Export Logs")
        XCTAssertEqual(VoiceInkDiagnosticsSettingsPresentation.exportFailedAlertTitle, "Export Failed")
        XCTAssertEqual(VoiceInkDiagnosticsSettingsPresentation.alertDismissButtonTitle, "OK")
        XCTAssertEqual(
            VoiceInkDiagnosticsSettingsPresentation.exportedLogSuccessSystemImageName,
            "checkmark.circle.fill"
        )
    }

    func testDiagnosticLogExportPolicyPreservesMacOSStorageAndFormattingConstants() {
        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.sessionStartDatesKey,
            "logExporter.sessionStartDates.v1"
        )
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.maxSessionStartDatesToKeep, 3)
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.timestampDateFormat, "yyyy-MM-dd HH:mm:ss.SSS")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.fileNameDateFormat, "yyyy-MM-dd_HH-mm-ss")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.fileNamePrefix, "VoiceInk_Logs_")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.fileNameExtension, "log")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.headerTitle, "=== VoiceInk Diagnostic Logs ===")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.headerDivider, "================================")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.noLogsFoundMessage, "No logs found for this session.")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.exporterErrorDomain, "LogExporter")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.downloadsDirectoryUnavailableErrorCode, 1)
        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.downloadsDirectoryUnavailableDescription,
            "Downloads directory unavailable"
        )
    }

    func testDiagnosticLogExportPolicyLoadsAndSavesStoredSessionStartDates() throws {
        try withTemporaryDefaults { defaults in
            let first = try localDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0, second: 0)
            let second = try localDate(year: 2026, month: 6, day: 21, hour: 13, minute: 0, second: 0)

            XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.storedSessionStartDates(from: defaults), [])

            VoiceInkDiagnosticLogExportPolicy.saveSessionStartDates([first, second], to: defaults)

            XCTAssertEqual(
                VoiceInkDiagnosticLogExportPolicy.storedSessionStartDates(from: defaults),
                [first, second]
            )
        }
    }

    func testDiagnosticLogExportPolicyFallsBackToEmptyStoredSessionsForInvalidData() {
        withTemporaryDefaults { defaults in
            defaults.set(Data([0xff]), forKey: VoiceInkDiagnosticLogExportPolicy.sessionStartDatesKey)

            XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.storedSessionStartDates(from: defaults), [])
        }
    }

    func testDiagnosticLogExportPolicyPrependsCurrentSessionAndKeepsThreeMostRecent() throws {
        let current = try localDate(year: 2026, month: 6, day: 21, hour: 15, minute: 0, second: 0)
        let older = [
            try localDate(year: 2026, month: 6, day: 21, hour: 14, minute: 0, second: 0),
            try localDate(year: 2026, month: 6, day: 21, hour: 13, minute: 0, second: 0),
            try localDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0, second: 0)
        ]

        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.sessionStartDates(
                starting: current,
                storedDates: older
            ),
            [current, older[0], older[1]]
        )
    }

    func testDiagnosticLogExportPolicyBuildsSessionRangesWithCurrentMiddleAndOldestLabels() throws {
        let newest = try localDate(year: 2026, month: 6, day: 21, hour: 15, minute: 0, second: 0)
        let middle = try localDate(year: 2026, month: 6, day: 21, hour: 14, minute: 0, second: 0)
        let oldest = try localDate(year: 2026, month: 6, day: 21, hour: 13, minute: 0, second: 0)

        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.sessionRanges(from: [newest, middle, oldest]),
            [
                VoiceInkDiagnosticLogSessionRange(label: "Session 3 (Current)", start: newest, end: nil),
                VoiceInkDiagnosticLogSessionRange(label: "Session 2", start: middle, end: newest),
                VoiceInkDiagnosticLogSessionRange(label: "Session 1 (Oldest)", start: oldest, end: middle)
            ]
        )
    }

    func testDiagnosticLogExportPolicyBuildsSingleSessionRangeLabel() throws {
        let date = try localDate(year: 2026, month: 6, day: 21, hour: 15, minute: 0, second: 0)

        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.sessionRanges(from: [date]),
            [
                VoiceInkDiagnosticLogSessionRange(label: "Session 1 (Current)", start: date, end: nil)
            ]
        )
    }

    func testDiagnosticLogExportPolicyBuildsHeaderSessionHeaderAndLogLines() throws {
        let date = try localDate(
            year: 2026,
            month: 6,
            day: 21,
            hour: 12,
            minute: 34,
            second: 56,
            nanosecond: 789_000_000
        )
        let formattedTimestamp = legacyFormattedDate(
            date,
            format: VoiceInkDiagnosticLogExportPolicy.timestampDateFormat
        )

        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.headerLines(
                exportDate: date,
                subsystem: "com.prakashjoshipax.voiceink",
                sessionCount: 2,
                systemInfo: "System info"
            ),
            [
                "=== VoiceInk Diagnostic Logs ===",
                "Export Date: \(formattedTimestamp)",
                "Subsystem: com.prakashjoshipax.voiceink",
                "Total Sessions: 2",
                "================================",
                "",
                "System info",
                ""
            ]
        )
        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.sessionHeaderLines(label: "Session 2 (Current)"),
            ["--- Session 2 (Current) ---", ""]
        )
        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.logEntryLine(
                date: date,
                level: "NOTICE",
                category: "LogExporter",
                message: "Ready"
            ),
            "[\(formattedTimestamp)] [NOTICE] [LogExporter] Ready"
        )
    }

    func testDiagnosticLogExportPolicyOwnsOSLogLevelLabels() {
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.logLevelLabel(for: .undefined), "UNDEFINED")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.logLevelLabel(for: .debug), "DEBUG")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.logLevelLabel(for: .info), "INFO")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.logLevelLabel(for: .notice), "NOTICE")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.logLevelLabel(for: .error), "ERROR")
        XCTAssertEqual(VoiceInkDiagnosticLogExportPolicy.logLevelLabel(for: .fault), "FAULT")
    }

    func testDiagnosticLogExportPolicyBuildsMacOSExportFileName() throws {
        let date = try localDate(year: 2026, month: 6, day: 21, hour: 12, minute: 34, second: 56)
        let timestamp = legacyFormattedDate(
            date,
            format: VoiceInkDiagnosticLogExportPolicy.fileNameDateFormat
        )

        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.fileName(for: date),
            "VoiceInk_Logs_\(timestamp).log"
        )
    }

    func testDiagnosticLogExportPolicyBuildsDownloadsUnavailableError() {
        let error = VoiceInkDiagnosticLogExportPolicy.downloadsDirectoryUnavailableError()

        XCTAssertEqual(error.domain, "LogExporter")
        XCTAssertEqual(error.code, 1)
        XCTAssertEqual(error.userInfo[NSLocalizedDescriptionKey] as? String, "Downloads directory unavailable")
        XCTAssertEqual(error.localizedDescription, "Downloads directory unavailable")
    }

    private func localDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        nanosecond: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        return try XCTUnwrap(components.date)
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "VoiceInkCore.DiagnosticLogExportPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        try test(defaults)
    }

    private func legacyFormattedDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
