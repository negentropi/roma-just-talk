import Foundation
import OSLog
@testable import VoiceInkCore

final class SystemInformationReportTests: XCTestCase {
    func testSystemArchitecturePreservesMacOSDisplayNameForCompileTarget() {
        #if arch(arm64)
        XCTAssertEqual(VoiceInkSystemArchitecture.macOSDisplayName, "Apple Silicon (ARM64)")
        #elseif arch(x86_64)
        XCTAssertEqual(VoiceInkSystemArchitecture.macOSDisplayName, "Intel (x86_64)")
        #else
        XCTAssertEqual(VoiceInkSystemArchitecture.macOSDisplayName, "Unknown")
        #endif
    }

    func testSystemArchitectureIntelMacPredicateMatchesCompileTarget() {
        #if os(macOS) && arch(x86_64)
        XCTAssertTrue(VoiceInkSystemArchitecture.isIntelMac)
        #else
        XCTAssertFalse(VoiceInkSystemArchitecture.isIntelMac)
        #endif
    }

    func testMacOSSystemInformationReportPreservesSectionOrderAndLabels() {
        let report = VoiceInkSystemInformationReport.macOS(Self.sampleFacts)

        XCTAssertEqual(
            report,
            """
            === VOICEINK SYSTEM INFORMATION ===
            Generated: June 24, 2026 at 3:42:11 PM

            APP INFORMATION:
            App Version: 1.2.3
            Build Version: 456
            License Status: Licensed (Pro)

            OPERATING SYSTEM:
            macOS Version: Version 26.0

            HARDWARE INFORMATION:
            Device Model: Mac16,1
            CPU: Apple M4 Pro
            Memory: 48 GB
            Architecture: arm64

            AUDIO SETTINGS:
            Input Mode: automatic
            Current Audio Device: Studio Display Microphone
            Available Audio Devices: Built-in Microphone, Studio Display Microphone

            HOTKEY SETTINGS:
            Primary Shortcut: Control Space
            Secondary Shortcut: Option Space
            Middle-Click Recording: true
            Middle-Click Activation Delay: 300 ms

            TRANSCRIPTION SETTINGS:
            Selected Model: Parakeet V3
            Selected Language: en
            AI Enhancement: Enabled
            AI Provider: OpenAI
            AI Model: gpt-5-mini

            ROLLING BUFFER PRELOAD:
            Mode: Smart
            Pre-run Finalization: true
            Buffer Duration: 8.0s
            Last Quick Release Claim: none

            UI SETTINGS:
            Hide Dock Icon: false
            Recorder Style: notch

            RECORDING FEEDBACK:
            Sound Feedback: true
            Pause Media While Recording: false
            Mute Audio While Recording: smart
            Audio Resumption Delay: 1.25s

            CLIPBOARD & PASTE SETTINGS:
            Restore Clipboard After Paste: true
            Clipboard Restore Delay: 0.5s
            Paste Method: Standard

            POWER MODE:
            Power Mode Enabled: true
            Persist Configured Preferences: false

            DATA CLEANUP SETTINGS:
            Auto-Delete Transcriptions: false
            Transcription Retention: 60 minutes
            Auto-Delete Audio Files: true
            Audio Retention Period: 7 days

            PERMISSIONS:
            Accessibility: Granted
            Input Monitoring: Not Granted
            Screen Recording: Granted
            Microphone: Denied
            """
        )
    }

    func testMacOSSystemInformationReportKeepsRollingBufferBlockVerbatim() {
        let facts = VoiceInkMacOSSystemInformationFacts(
            generated: "now",
            appVersion: "app",
            buildVersion: "build",
            licenseStatus: "license",
            operatingSystemVersion: "os",
            deviceModel: "model",
            cpu: "cpu",
            memory: "memory",
            architecture: "arch",
            audioInputMode: "mode",
            currentAudioDevice: "current",
            availableAudioDevices: "available",
            primaryShortcut: "",
            secondaryShortcut: "",
            middleClickRecording: false,
            middleClickActivationDelayMilliseconds: 0,
            selectedModel: "selected",
            selectedLanguage: "auto",
            aiEnhancement: "disabled",
            aiProvider: "none",
            aiModel: "none",
            rollingBufferPreload: "line one\nline two",
            hideDockIcon: true,
            recorderStyle: "mini",
            soundFeedback: false,
            pauseMediaWhileRecording: true,
            muteAudioWhileRecording: "off",
            audioResumptionDelaySeconds: 0,
            restoreClipboardAfterPaste: false,
            clipboardRestoreDelaySeconds: 0,
            pasteMethod: "Direct",
            powerModeEnabled: false,
            persistConfiguredPreferences: true,
            autoDeleteTranscriptions: true,
            transcriptionRetentionMinutes: 10,
            autoDeleteAudioFiles: false,
            audioRetentionPeriodDays: 1,
            accessibilityPermission: "Unknown",
            inputMonitoringPermission: "Unknown",
            screenRecordingPermission: "Unknown",
            microphonePermission: "Unknown"
        )

        XCTAssertTrue(VoiceInkSystemInformationReport.macOS(facts).contains("ROLLING BUFFER PRELOAD:\nline one\nline two\n\nUI SETTINGS:"))
    }

    func testAvailableAudioDevicesTextPreservesMacOSDiagnosticsListPolicy() {
        XCTAssertEqual(
            VoiceInkSystemInformationReport.availableAudioDevicesText([
                "Built-in Microphone",
                "Studio Display Microphone"
            ]),
            "Built-in Microphone, Studio Display Microphone"
        )
        XCTAssertEqual(
            VoiceInkSystemInformationReport.availableAudioDevicesText([]),
            "None detected"
        )
    }

    func testKnownTextPreservesMacOSUnknownFallback() {
        XCTAssertEqual(VoiceInkSystemInformationReport.unknownValueText, "Unknown")
        XCTAssertEqual(VoiceInkSystemInformationReport.knownText("Mac16,1"), "Mac16,1")
        XCTAssertEqual(VoiceInkSystemInformationReport.knownText(nil), "Unknown")
    }

    func testGeneratedDateTextPreservesMacOSFormattingStyle() {
        let generatedAt = Date(timeIntervalSince1970: 1_782_315_731)

        XCTAssertEqual(
            VoiceInkSystemInformationReport.generatedDateText(generatedAt),
            generatedAt.formatted(date: .long, time: .standard)
        )
    }

    func testPermissionStatusPresentationPreservesMacOSDiagnosticsCopy() {
        XCTAssertEqual(
            VoiceInkSystemInformationPermissionStatus.grantStatus(isGranted: true),
            .granted
        )
        XCTAssertEqual(
            VoiceInkSystemInformationPermissionStatus.grantStatus(isGranted: false),
            .notGranted
        )
        XCTAssertEqual(VoiceInkSystemInformationPermissionStatus.granted.displayText, "Granted")
        XCTAssertEqual(VoiceInkSystemInformationPermissionStatus.notGranted.displayText, "Not Granted")
        XCTAssertEqual(VoiceInkSystemInformationPermissionStatus.denied.displayText, "Denied")
        XCTAssertEqual(VoiceInkSystemInformationPermissionStatus.restricted.displayText, "Restricted")
        XCTAssertEqual(VoiceInkSystemInformationPermissionStatus.notDetermined.displayText, "Not Determined")
        XCTAssertEqual(VoiceInkSystemInformationPermissionStatus.unknown.displayText, "Unknown")
    }

    func testLicenseStatusPresentationPreservesMacOSDiagnosticsCopy() {
        XCTAssertEqual(
            VoiceInkSystemInformationLicenseStatus.status(hasUsableStoredLicense: true),
            .licensedPro
        )
        XCTAssertEqual(
            VoiceInkSystemInformationLicenseStatus.status(hasUsableStoredLicense: false),
            .notLicensed
        )
        XCTAssertEqual(VoiceInkSystemInformationLicenseStatus.licensedPro.displayText, "Licensed (Pro)")
        XCTAssertEqual(VoiceInkSystemInformationLicenseStatus.notLicensed.displayText, "Not Licensed")
    }

    func testSystemInformationCopyPresentationPreservesDashboardButtonPolicy() {
        XCTAssertEqual(
            VoiceInkSystemInformationCopyPresentation.button(isCopied: false),
            VoiceInkSystemInformationCopyButtonPresentation(
                systemImageName: "doc.on.doc",
                title: "Copy System Info"
            )
        )
        XCTAssertEqual(
            VoiceInkSystemInformationCopyPresentation.button(isCopied: true),
            VoiceInkSystemInformationCopyButtonPresentation(
                systemImageName: "checkmark",
                title: "Copied!"
            )
        )
        XCTAssertEqual(VoiceInkSystemInformationCopyPresentation.copiedResetDelay, 1.5)
    }

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

    func testDiagnosticLogExportPolicyBuildsExportContentWithLineBreaks() {
        XCTAssertEqual(
            VoiceInkDiagnosticLogExportPolicy.exportContent(
                from: [
                    "=== VoiceInk Diagnostic Logs ===",
                    "",
                    "No logs found for this session."
                ]
            ),
            "=== VoiceInk Diagnostic Logs ===\n\nNo logs found for this session."
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
        let suiteName = "VoiceInkCore.SystemInformationReportTests.\(UUID().uuidString)"
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

    private static var sampleFacts: VoiceInkMacOSSystemInformationFacts {
        VoiceInkMacOSSystemInformationFacts(
            generated: "June 24, 2026 at 3:42:11 PM",
            appVersion: "1.2.3",
            buildVersion: "456",
            licenseStatus: "Licensed (Pro)",
            operatingSystemVersion: "Version 26.0",
            deviceModel: "Mac16,1",
            cpu: "Apple M4 Pro",
            memory: "48 GB",
            architecture: "arm64",
            audioInputMode: "automatic",
            currentAudioDevice: "Studio Display Microphone",
            availableAudioDevices: "Built-in Microphone, Studio Display Microphone",
            primaryShortcut: "Control Space",
            secondaryShortcut: "Option Space",
            middleClickRecording: true,
            middleClickActivationDelayMilliseconds: 300,
            selectedModel: "Parakeet V3",
            selectedLanguage: "en",
            aiEnhancement: "Enabled",
            aiProvider: "OpenAI",
            aiModel: "gpt-5-mini",
            rollingBufferPreload: """
            Mode: Smart
            Pre-run Finalization: true
            Buffer Duration: 8.0s
            Last Quick Release Claim: none
            """,
            hideDockIcon: false,
            recorderStyle: "notch",
            soundFeedback: true,
            pauseMediaWhileRecording: false,
            muteAudioWhileRecording: "smart",
            audioResumptionDelaySeconds: 1.25,
            restoreClipboardAfterPaste: true,
            clipboardRestoreDelaySeconds: 0.5,
            pasteMethod: "Standard",
            powerModeEnabled: true,
            persistConfiguredPreferences: false,
            autoDeleteTranscriptions: false,
            transcriptionRetentionMinutes: 60,
            autoDeleteAudioFiles: true,
            audioRetentionPeriodDays: 7,
            accessibilityPermission: "Granted",
            inputMonitoringPermission: "Not Granted",
            screenRecordingPermission: "Granted",
            microphonePermission: "Denied"
        )
    }
}
