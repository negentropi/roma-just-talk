import XCTest
import VoiceInkCore

final class IOSDiagnosticsTests: XCTestCase {
    func testDiagnosticRangesCalculateExpectedStartDates() {
        let now = Date(timeIntervalSince1970: 100_000)
        let session = now.addingTimeInterval(-123)

        XCTAssertEqual(
            VoiceInkIOSDiagnosticRange.fifteenMinutes.startDate(now: now, sessionStartDate: session),
            now.addingTimeInterval(-900)
        )
        XCTAssertEqual(
            VoiceInkIOSDiagnosticRange.oneHour.startDate(now: now, sessionStartDate: session),
            now.addingTimeInterval(-3_600)
        )
        XCTAssertEqual(
            VoiceInkIOSDiagnosticRange.oneDay.startDate(now: now, sessionStartDate: session),
            now.addingTimeInterval(-86_400)
        )
        XCTAssertEqual(
            VoiceInkIOSDiagnosticRange.currentSession.startDate(now: now, sessionStartDate: session),
            session
        )
    }

    func testRedactionRemovesSecretsEmailsAndHomeDirectory() {
        let source = "API_KEY=top-secret Authorization: Bearer-123 user@example.com /Users/felix/file.wav?token=query-secret"
        let redacted = VoiceInkDiagnosticRedactionPolicy.redact(
            source,
            homeDirectory: "/Users/felix"
        )

        XCTAssertFalse(redacted.contains("top-secret"))
        XCTAssertFalse(redacted.contains("Bearer-123"))
        XCTAssertFalse(redacted.contains("user@example.com"))
        XCTAssertFalse(redacted.contains("/Users/felix"))
        XCTAssertFalse(redacted.contains("query-secret"))
        XCTAssertTrue(redacted.contains(VoiceInkDiagnosticRedactionPolicy.redactedText))
        XCTAssertTrue(redacted.contains("~/file.wav"))
    }

    func testSupportBundleIncludesSystemFactsAndEmptyLogMarker() {
        let facts = VoiceInkIOSDiagnosticSystemFacts(
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
        let content = VoiceInkIOSDiagnosticSupportBundlePolicy.content(
            generatedAt: Date(timeIntervalSince1970: 0),
            range: .oneHour,
            systemInformation: VoiceInkIOSDiagnosticSupportBundlePolicy.systemInformation(facts),
            logLines: []
        )

        XCTAssertTrue(content.contains("App Version: 1.0"))
        XCTAssertTrue(content.contains("Selected Mode: Meeting"))
        XCTAssertTrue(content.contains("Range: Last Hour"))
        XCTAssertTrue(content.contains(VoiceInkIOSDiagnosticSupportBundlePolicy.noLogsMessage))
    }

    func testSupportBundleFilenameUsesLogExtension() {
        let filename = VoiceInkIOSDiagnosticSupportBundlePolicy.filename(
            for: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(filename.hasPrefix(VoiceInkIOSDiagnosticSupportBundlePolicy.defaultFilenamePrefix))
        XCTAssertTrue(filename.hasSuffix(".log"))
    }
}
