import XCTest
import RomaCore

final class IOSDiagnosticsTests: XCTestCase {
    func testDiagnosticRangesCalculateExpectedStartDates() {
        let now = Date(timeIntervalSince1970: 100_000)
        let session = now.addingTimeInterval(-123)

        XCTAssertEqual(
            RomaIOSDiagnosticRange.fifteenMinutes.startDate(now: now, sessionStartDate: session),
            now.addingTimeInterval(-900)
        )
        XCTAssertEqual(
            RomaIOSDiagnosticRange.oneHour.startDate(now: now, sessionStartDate: session),
            now.addingTimeInterval(-3_600)
        )
        XCTAssertEqual(
            RomaIOSDiagnosticRange.oneDay.startDate(now: now, sessionStartDate: session),
            now.addingTimeInterval(-86_400)
        )
        XCTAssertEqual(
            RomaIOSDiagnosticRange.currentSession.startDate(now: now, sessionStartDate: session),
            session
        )
    }

    func testRedactionRemovesSecretsEmailsAndHomeDirectory() {
        let source = "API_KEY=top-secret Authorization: Bearer-123 user@example.com /Users/felix/file.wav?token=query-secret"
        let redacted = RomaDiagnosticRedactionPolicy.redact(
            source,
            homeDirectory: "/Users/felix"
        )

        XCTAssertFalse(redacted.contains("top-secret"))
        XCTAssertFalse(redacted.contains("Bearer-123"))
        XCTAssertFalse(redacted.contains("user@example.com"))
        XCTAssertFalse(redacted.contains("/Users/felix"))
        XCTAssertFalse(redacted.contains("query-secret"))
        XCTAssertTrue(redacted.contains(RomaDiagnosticRedactionPolicy.redactedText))
        XCTAssertTrue(redacted.contains("~/file.wav"))
    }

    func testSupportBundleIncludesSystemFactsAndEmptyLogMarker() {
        let facts = RomaIOSDiagnosticSystemFacts(
            appVersion: "1.0",
            buildVersion: "42",
            operatingSystem: "iOS 26",
            deviceModel: "iPhone",
            physicalMemory: "8 GB",
            selectedMode: "Meeting",
            selectedLanguage: "en",
            microphonePermission: "Microphone Ready",
            keyboardRecordingState: "Idle"
        )
        let content = RomaIOSDiagnosticSupportBundlePolicy.content(
            generatedAt: Date(timeIntervalSince1970: 0),
            range: .oneHour,
            systemInformation: RomaIOSDiagnosticSupportBundlePolicy.systemInformation(facts),
            logLines: []
        )

        XCTAssertTrue(content.contains("App Version: 1.0"))
        XCTAssertTrue(content.contains("Selected Mode: Meeting"))
        XCTAssertTrue(content.contains("Range: Last Hour"))
        XCTAssertTrue(content.contains(RomaIOSDiagnosticSupportBundlePolicy.noLogsMessage))
    }

    func testSupportBundleFilenameUsesLogExtension() {
        let filename = RomaIOSDiagnosticSupportBundlePolicy.filename(
            for: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(filename.hasPrefix(RomaIOSDiagnosticSupportBundlePolicy.defaultFilenamePrefix))
        XCTAssertTrue(filename.hasSuffix(".log"))
    }
}
