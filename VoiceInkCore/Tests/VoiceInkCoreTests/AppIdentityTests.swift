import Foundation
import OSLog
import VoiceInkCore

final class AppIdentityTests: XCTestCase {
    func testAppIdentityPreservesSharedVisibleNames() {
        XCTAssertEqual(VoiceInkAppIdentity.bundleIdentifier, "com.prakashjoshipax.VoiceInk")
        XCTAssertEqual(VoiceInkAppIdentity.loggingSubsystem, "com.prakashjoshipax.voiceink")
        XCTAssertEqual(VoiceInkAppIdentity.displayName, "roma just talk")
        XCTAssertEqual(VoiceInkAppIdentity.compactDisplayName, "roma-just-talk")
        XCTAssertEqual(VoiceInkAppIdentity.sidebarSubtitle, "speak before hotkey")
        XCTAssertEqual(VoiceInkAppIdentity.iCloudContainerIdentifier, "iCloud.com.prakashjoshipax.VoiceInk")
        XCTAssertEqual(VoiceInkAppIdentity.iOSAppGroupIdentifier, "group.com.prakashjoshipax.VoiceInk")
        XCTAssertEqual(VoiceInkAppIdentity.iOSRecordDeepLinkScheme, "voiceink")
        XCTAssertEqual(VoiceInkAppIdentity.iOSRecordDeepLinkHost, "record")
        XCTAssertEqual(VoiceInkAppIdentity.iOSRecordDeepLinkURL.absoluteString, "voiceink://record")
        XCTAssertEqual(
            VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName,
            "com.prakashjoshipax.VoiceInk.stopRecording"
        )
        XCTAssertEqual(
            VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName,
            "com.prakashjoshipax.VoiceInk.recordingStateChanged"
        )
        XCTAssertEqual(
            VoiceInkAppIdentity.iOSStopRecordingFromKeyboardNotificationName.rawValue,
            "stopRecordingFromKeyboard"
        )
        XCTAssertEqual(VoiceInkAppIdentity.welcomeTitle, "Welcome to roma just talk")
        XCTAssertEqual(VoiceInkAppIdentity.startUsingTitle, "Start Using roma just talk")
        XCTAssertEqual(VoiceInkAppIdentity.onboardingWindowTitle, "roma-just-talk Onboarding")
        XCTAssertEqual(
            VoiceInkAppIdentity.storageFailureMessage,
            "roma-just-talk cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
        )
    }

    func testAppNotificationKindsPreserveCasesAndDefaultDuration() {
        XCTAssertEqual(
            VoiceInkAppNotificationKind.allCases.map(\.rawValue),
            ["error", "warning", "info", "success"]
        )
        XCTAssertEqual(VoiceInkAppNotificationKind.defaultDisplayDuration, 3.0, accuracy: 0.0001)
    }

    func testAppNotificationKindsPreserveSystemImages() {
        XCTAssertEqual(VoiceInkAppNotificationKind.error.systemImageName, "xmark.octagon.fill")
        XCTAssertEqual(VoiceInkAppNotificationKind.warning.systemImageName, "exclamationmark.triangle.fill")
        XCTAssertEqual(VoiceInkAppNotificationKind.info.systemImageName, "info.circle.fill")
        XCTAssertEqual(VoiceInkAppNotificationKind.success.systemImageName, "checkmark.circle.fill")
    }

    func testOnlyErrorNotificationsPlayFailureSound() {
        XCTAssertTrue(VoiceInkAppNotificationKind.error.playsFailureSound)
        XCTAssertFalse(VoiceInkAppNotificationKind.warning.playsFailureSound)
        XCTAssertFalse(VoiceInkAppNotificationKind.info.playsFailureSound)
        XCTAssertFalse(VoiceInkAppNotificationKind.success.playsFailureSound)
    }

    func testSupportContactPolicyPreservesEmailIdentityAndSubject() {
        XCTAssertEqual(VoiceInkSupportContactPolicy.emailAddress, "support@tryvoiceink.com")
        XCTAssertEqual(VoiceInkSupportContactPolicy.emailSubject, "VoiceInk Support Request")
        XCTAssertEqual(VoiceInkSupportContactPolicy.commonIssuesURLString, "https://tryvoiceink.com/common-issues")
    }

    func testSupportEmailBodyPreservesMacOSSupportCopyAndSystemInformationSlot() {
        let body = VoiceInkSupportContactPolicy.emailBody(systemInformation: "macOS: test\nApp: roma just talk")

        XCTAssertTrue(body.contains("------------------------"))
        XCTAssertTrue(body.contains("✨ **SCREEN RECORDING HIGHLY RECOMMENDED** ✨"))
        XCTAssertTrue(body.contains("▶️ Create a quick screen recording showing the issue!"))
        XCTAssertTrue(body.contains("📝 ISSUE DETAILS:"))
        XCTAssertTrue(body.contains("## 📋 COMMON ISSUES:"))
        XCTAssertTrue(body.contains("Check out our Common Issues page before sending an email: https://tryvoiceink.com/common-issues"))
        XCTAssertTrue(body.contains("System Information:\nmacOS: test\nApp: roma just talk"))
        XCTAssertTrue(body.hasSuffix("\n\n"))
    }

    func testSupportMailtoURLPreservesRecipientAndEncodesSubject() throws {
        let url = try XCTUnwrap(VoiceInkSupportContactPolicy.mailtoURL())
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, VoiceInkSupportContactPolicy.emailAddress)
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "subject", value: VoiceInkSupportContactPolicy.emailSubject)
        ])
        XCTAssertEqual(url.absoluteString, "mailto:support@tryvoiceink.com?subject=VoiceInk%20Support%20Request")
    }

    func testAnnouncementPreferencePreservesMacOSStorageAndFetchDefaults() {
        XCTAssertEqual(VoiceInkAnnouncementPreference.isEnabledKey, "enableAnnouncements")
        XCTAssertEqual(VoiceInkAnnouncementPreference.dismissedIdsKey, "dismissedAnnouncementIds")
        XCTAssertEqual(VoiceInkAnnouncementPreference.defaultIsEnabled, true)
        XCTAssertEqual(VoiceInkAnnouncementPreference.maxDismissedIdsToKeep, 2)
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.announcementsURLString,
            "https://beingpax.github.io/VoiceInk/announcements.json"
        )
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.announcementsURL.absoluteString,
            "https://beingpax.github.io/VoiceInk/announcements.json"
        )
        XCTAssertEqual(VoiceInkAnnouncementPreference.refreshInterval, 4 * 60 * 60)
        XCTAssertEqual(VoiceInkAnnouncementPreference.initialFetchDelay, 5)
        XCTAssertEqual(VoiceInkAnnouncementPreference.requestTimeout, 10)
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.registeredDefaults[VoiceInkAnnouncementPreference.isEnabledKey] as? Bool,
            Optional(true)
        )
    }

    func testAnnouncementPreferenceReadsAndSavesEnabledFlagAndDismissedIds() {
        withTemporaryDefaults { defaults in
            XCTAssertTrue(VoiceInkAnnouncementPreference.isEnabled(from: defaults))
            XCTAssertEqual(VoiceInkAnnouncementPreference.dismissedIds(from: defaults), [])

            VoiceInkAnnouncementPreference.saveIsEnabled(false, to: defaults)
            VoiceInkAnnouncementPreference.saveDismissedIds(["one", "two"], to: defaults)

            XCTAssertFalse(VoiceInkAnnouncementPreference.isEnabled(from: defaults))
            XCTAssertEqual(VoiceInkAnnouncementPreference.dismissedIds(from: defaults), ["one", "two"])
        }
    }

    func testDismissedIdsPlanAvoidsDuplicatesAndKeepsMostRecentTwo() {
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.dismissedIds(afterDismissing: "one", currentIds: ["one"]),
            ["one"]
        )
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.dismissedIds(afterDismissing: "three", currentIds: ["one", "two"]),
            ["two", "three"]
        )
        XCTAssertTrue(VoiceInkAnnouncementPreference.isDismissed("two", dismissedIds: ["one", "two"]))
        XCTAssertFalse(VoiceInkAnnouncementPreference.isDismissed("three", dismissedIds: ["one", "two"]))
    }

    func testAnnouncementActiveWindowPreservesOpenEndedAndInvalidDateBehavior() throws {
        let now = try date("2026-06-21T12:00:00Z")

        XCTAssertTrue(VoiceInkAnnouncementPolicy.isActive(
            announcement(id: "current", startAt: "2026-06-21T11:00:00Z", endAt: "2026-06-21T13:00:00Z"),
            at: now
        ))
        XCTAssertFalse(VoiceInkAnnouncementPolicy.isActive(
            announcement(id: "future", startAt: "2026-06-21T13:00:00Z", endAt: nil),
            at: now
        ))
        XCTAssertFalse(VoiceInkAnnouncementPolicy.isActive(
            announcement(id: "expired", startAt: nil, endAt: "2026-06-21T11:00:00Z"),
            at: now
        ))
        XCTAssertTrue(VoiceInkAnnouncementPolicy.isActive(
            announcement(id: "invalid", startAt: "bad", endAt: "also-bad"),
            at: now
        ))
    }

    func testNextAnnouncementSkipsDismissedAndInactiveThenReturnsFirstValidPresentation() throws {
        let now = try date("2026-06-21T12:00:00Z")
        let next = VoiceInkAnnouncementPolicy.nextAnnouncement(
            from: [
                announcement(id: "dismissed"),
                announcement(id: "future", startAt: "2026-06-21T13:00:00Z", endAt: nil),
                announcement(id: "valid", description: "Body", url: "https://tryvoiceink.com/docs")
            ],
            dismissedIds: ["dismissed"],
            now: now
        )

        XCTAssertEqual(next?.id, Optional("valid"))
        XCTAssertEqual(next?.title, Optional("Title valid"))
        XCTAssertEqual(next?.description, Optional("Body"))
        XCTAssertEqual(next?.learnMoreURL, URL(string: "https://tryvoiceink.com/docs"))
    }

    func testAnnouncementPresentationPreservesMacOSActionCopyAndDescriptionVisibility() throws {
        let now = try date("2026-06-21T12:00:00Z")
        let visible = try XCTUnwrap(VoiceInkAnnouncementPolicy.nextAnnouncement(
            from: [
                announcement(id: "visible", description: " Body ", url: "https://tryvoiceink.com/docs")
            ],
            dismissedIds: [],
            now: now
        ))

        XCTAssertEqual(visible.closeButtonSystemImageName, "xmark")
        XCTAssertEqual(visible.learnMoreButtonTitle, "Learn more")
        XCTAssertEqual(visible.dismissButtonTitle, "Dismiss")
        XCTAssertEqual(visible.descriptionText, " Body ")
        XCTAssertTrue(visible.shouldShowDescription)

        let blank = try XCTUnwrap(VoiceInkAnnouncementPolicy.nextAnnouncement(
            from: [
                announcement(id: "blank", description: " \n\t ")
            ],
            dismissedIds: [],
            now: now
        ))

        XCTAssertEqual(blank.descriptionText, " \n\t ")
        XCTAssertFalse(blank.shouldShowDescription)
    }

    func testNextAnnouncementReturnsNilWhenNothingIsEligible() throws {
        let now = try date("2026-06-21T12:00:00Z")
        XCTAssertNil(VoiceInkAnnouncementPolicy.nextAnnouncement(
            from: [
                announcement(id: "dismissed"),
                announcement(id: "future", startAt: "2026-06-21T13:00:00Z", endAt: nil)
            ],
            dismissedIds: ["dismissed"],
            now: now
        ))
    }

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

    func testIOSLogCategoriesPreserveDiagnosticsIdentity() {
        XCTAssertEqual(VoiceInkIOSLogCategory.app, "iOSApp")
        XCTAssertEqual(VoiceInkIOSLogCategory.appGroup, "iOSAppGroup")
        XCTAssertEqual(VoiceInkIOSLogCategory.audioPlayback, "iOSAudioPlayback")
        XCTAssertEqual(VoiceInkIOSLogCategory.audioSession, "iOSAudioSession")
        XCTAssertEqual(VoiceInkIOSLogCategory.keyboard, "iOSKeyboard")
        XCTAssertEqual(VoiceInkIOSLogCategory.localWhisper, "iOSLocalWhisper")
        XCTAssertEqual(VoiceInkIOSLogCategory.localModelManagement, "iOSLocalModelManagement")
        XCTAssertEqual(VoiceInkIOSLogCategory.notes, "iOSNotes")
        XCTAssertEqual(VoiceInkIOSLogCategory.recording, "iOSRecording")
        XCTAssertEqual(VoiceInkIOSLogCategory.settings, "iOSSettings")
    }

    func testMacOSLogCategoriesPreserveDiagnosticsIdentity() {
        XCTAssertEqual(VoiceInkMacOSLogCategory.logExporter, "LogExporter")
        XCTAssertEqual(VoiceInkMacOSLogCategory.windowManager, "WindowManager")
        XCTAssertEqual(VoiceInkMacOSLogCategory.menuBarManager, "MenuBarManager")
        XCTAssertEqual(VoiceInkMacOSLogCategory.apiKeyManager, "APIKeyManager")
        XCTAssertEqual(VoiceInkMacOSLogCategory.keychainService, "KeychainService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.polarService, "PolarService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.licenseViewModel, "LicenseViewModel")
        XCTAssertEqual(VoiceInkMacOSLogCategory.aiEnhancementService, "AIEnhancementService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.customCloudModelManager, "CustomCloudModelManager")
        XCTAssertEqual(VoiceInkMacOSLogCategory.transcriptionAutoCleanupService, "TranscriptionAutoCleanupService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.sessionMetricMigrationService, "SessionMetricMigrationService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.modelPrewarm, "ModelPrewarm")
        XCTAssertEqual(VoiceInkMacOSLogCategory.cursorPaster, "CursorPaster")
        XCTAssertEqual(VoiceInkMacOSLogCategory.sessionMetricRecorder, "SessionMetricRecorder")
        XCTAssertEqual(VoiceInkMacOSLogCategory.soundPlaybackEngine, "SoundPlaybackEngine")
        XCTAssertEqual(VoiceInkMacOSLogCategory.audioTranscriptionManager, "AudioTranscriptionManager")
        XCTAssertEqual(VoiceInkMacOSLogCategory.audioTranscriptionService, "AudioTranscriptionService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.coreAudioRecorder, "CoreAudioRecorder")
        XCTAssertEqual(VoiceInkMacOSLogCategory.transcriptionServiceRegistry, "TranscriptionServiceRegistry")
        XCTAssertEqual(VoiceInkMacOSLogCategory.nativeAppleTranscriptionService, "NativeAppleTranscriptionService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.nativeAppleLanguageAssetControl, "NativeAppleLanguageAssetControl")
        XCTAssertEqual(VoiceInkMacOSLogCategory.whisperTranscriptionService, "WhisperTranscriptionService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.whisperModelManager, "WhisperModelManager")
        XCTAssertEqual(VoiceInkMacOSLogCategory.audioDeviceManager, "AudioDeviceManager")
    }

    func testMacOSWindowIdentityPreservesIdentifiersTitlesAndFrameNames() {
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.mainIdentifierRawValue, "com.prakashjoshipax.voiceink.mainWindow")
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.onboardingIdentifierRawValue, "com.prakashjoshipax.voiceink.onboardingWindow")
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.historyIdentifierRawValue, "com.prakashjoshipax.voiceink.historyWindow")
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.mainFrameAutosaveName, "VoiceInkMainWindowFrame")
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.historyFrameAutosaveName, "VoiceInkHistoryWindowFrame")
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.mainTitle, "roma-just-talk")
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.onboardingTitle, "roma-just-talk Onboarding")
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.historyTitle, "roma-just-talk - Transcription History")
        XCTAssertEqual(
            VoiceInkMacOSWindowIdentity.identifierListDebugText([
                VoiceInkMacOSWindowIdentity.mainIdentifierRawValue,
                nil,
                VoiceInkMacOSWindowIdentity.historyIdentifierRawValue
            ]),
            "com.prakashjoshipax.voiceink.mainWindow, nil, com.prakashjoshipax.voiceink.historyWindow"
        )
        XCTAssertEqual(VoiceInkMacOSWindowIdentity.identifierListDebugText([]), "")
        XCTAssertEqual(
            VoiceInkMacOSWindowIdentity.configureWindowDuplicateDetectedMessage,
            "configureWindow: duplicate detected, reusing existing window"
        )
        XCTAssertEqual(
            VoiceInkMacOSWindowIdentity.configureWindowRegisteringMainMessage,
            "configureWindow: registering main window"
        )
        XCTAssertEqual(
            VoiceInkMacOSWindowIdentity.resolveMainWindowSearchingMessage(windowCount: 3),
            "resolveMainWindow: weak ref is nil, searching 3 windows by identifier"
        )
        XCTAssertEqual(
            VoiceInkMacOSWindowIdentity.resolveMainWindowRecoveredMessage,
            "resolveMainWindow: recovered window via identifier fallback"
        )
        XCTAssertEqual(
            VoiceInkMacOSWindowIdentity.resolveMainWindowFailedMessage(
                windowCount: 3,
                identifiers: "main, nil, history"
            ),
            "resolveMainWindow: FAILED — no window found with main identifier. Total windows: 3, identifiers: main, nil, history"
        )
        XCTAssertEqual(
            VoiceInkMacOSWindowIdentity.windowWillCloseMainMessage,
            "windowWillClose: main window closing, clearing weak reference"
        )
    }

    func testMacOSStorageAlertPresentationPreservesStartupCopy() {
        XCTAssertEqual(
            VoiceInkAppIdentity.storageFallbackWarningPresentation,
            VoiceInkMacOSStorageAlertPresentation(
                title: "Storage Warning",
                message: "VoiceInk couldn't access its storage location. Your transcriptions will not be saved between sessions.",
                buttonTitle: "OK"
            )
        )
        XCTAssertEqual(
            VoiceInkAppIdentity.storageFailurePresentation,
            VoiceInkMacOSStorageAlertPresentation(
                title: "Critical Storage Error",
                message: "roma-just-talk cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists.",
                buttonTitle: "Quit"
            )
        )
    }

    func testStorageStartupDiagnosticsPreserveAppStartupCopy() {
        XCTAssertEqual(
            VoiceInkStorageStartupDiagnostics.modelContainerInitializationFailedMessage,
            "ModelContainer initialization failed"
        )
        XCTAssertEqual(
            VoiceInkStorageStartupDiagnostics.modelContainerUnavailablePreconditionMessage,
            "Unable to create ModelContainer. SwiftData is unavailable."
        )
        XCTAssertEqual(
            VoiceInkStorageStartupDiagnostics.iOSModelContainerCreationFailedMessage(errorDescription: "store denied"),
            "Could not create ModelContainer: store denied"
        )
    }

    func testMacOSNavigationRequestPreservesDestinationContract() {
        XCTAssertEqual(VoiceInkMacOSNavigationRequest.notificationName.rawValue, "navigateToDestination")
        XCTAssertEqual(VoiceInkMacOSNavigationRequest.destinationUserInfoKey, "destination")
        XCTAssertEqual(VoiceInkMacOSNavigationRequest.defaultDestination, .settings)
        XCTAssertEqual(
            VoiceInkMacOSNavigationDestination.allCases.map(\.rawValue),
            [
                "Settings",
                "AI Models",
                "VoiceInk Pro",
                "History",
                "Permissions",
                "Enhancement",
                "Transcribe Audio",
                "Power Mode"
            ]
        )

        let notification = Notification(
            name: VoiceInkMacOSNavigationRequest.notificationName,
            userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: .transcribeAudio)
        )

        XCTAssertEqual(
            VoiceInkMacOSNavigationRequest.destination(from: notification),
            "Transcribe Audio"
        )
    }

    func testMacOSMainViewItemsPreserveSidebarPresentation() {
        XCTAssertEqual(VoiceInkMacOSMainViewItem.defaultSelection, .metrics)
        XCTAssertEqual(VoiceInkMacOSMainViewItem.emptySelectionTitle, "Select a view")
        XCTAssertEqual(
            VoiceInkMacOSMainViewItem.allCases.map(\.title),
            [
                "home",
                "manual stt",
                "past",
                "models",
                "style",
                "Power Mode",
                "Permissions",
                "Audio Input",
                "Dictionary",
                "Settings",
                "VoiceInk Pro"
            ]
        )
        XCTAssertEqual(
            VoiceInkMacOSMainViewItem.allCases.map(\.systemImageName),
            [
                "gauge.medium",
                "waveform.circle.fill",
                "doc.text.fill",
                "brain.head.profile",
                "wand.and.stars",
                "sparkles.square.fill.on.square",
                "shield.fill",
                "mic.fill",
                "character.book.closed.fill",
                "gearshape.fill",
                "checkmark.seal.fill"
            ]
        )
        XCTAssertEqual(
            VoiceInkMacOSMainViewItem.visibleItems(powerModeEnabled: false),
            [.metrics, .transcribeAudio, .history, .models, .enhancement, .permissions, .audioInput, .dictionary, .settings, .license]
        )
        XCTAssertEqual(VoiceInkMacOSMainViewItem.visibleItems(powerModeEnabled: true), VoiceInkMacOSMainViewItem.allCases)
    }

    func testMacOSMainViewItemsMapNavigationDestinationsAndLegacyTitles() {
        XCTAssertEqual(
            VoiceInkMacOSMainViewItem.item(forNavigationDestination: VoiceInkMacOSNavigationDestination.settings.rawValue),
            .settings
        )
        XCTAssertEqual(
            VoiceInkMacOSMainViewItem.item(forNavigationDestination: VoiceInkMacOSNavigationDestination.aiModels.rawValue),
            .models
        )
        XCTAssertEqual(VoiceInkMacOSMainViewItem.item(forNavigationDestination: "models"), .models)
        XCTAssertEqual(VoiceInkMacOSMainViewItem.item(forNavigationDestination: "past"), .history)
        XCTAssertEqual(VoiceInkMacOSMainViewItem.item(forNavigationDestination: "style"), .enhancement)
        XCTAssertEqual(VoiceInkMacOSMainViewItem.item(forNavigationDestination: "manual stt"), .transcribeAudio)
        XCTAssertEqual(
            VoiceInkMacOSMainViewItem.item(forNavigationDestination: VoiceInkMacOSNavigationDestination.license.rawValue),
            .license
        )
        XCTAssertEqual(
            VoiceInkMacOSMainViewItem.item(forNavigationDestination: VoiceInkMacOSNavigationDestination.powerMode.rawValue),
            .powerMode
        )
        XCTAssertNil(VoiceInkMacOSMainViewItem.item(forNavigationDestination: "Audio Input"))
        XCTAssertNil(VoiceInkMacOSMainViewItem.item(forNavigationDestination: "Dictionary"))
    }

    func testMacOSFileTranscriptionRequestPreservesPayloadContract() throws {
        let url = URL(fileURLWithPath: "/tmp/sample.wav")
        let notification = Notification(
            name: VoiceInkMacOSFileTranscriptionRequest.notificationName,
            userInfo: VoiceInkMacOSFileTranscriptionRequest.userInfo(url: url)
        )

        XCTAssertEqual(VoiceInkMacOSFileTranscriptionRequest.notificationName.rawValue, "openFileForTranscription")
        XCTAssertEqual(VoiceInkMacOSFileTranscriptionRequest.urlUserInfoKey, "url")
        XCTAssertEqual(VoiceInkMacOSFileTranscriptionRequest.url(from: notification), url)
    }

    func testMacOSAppEventRequestPreservesNotificationNames() {
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.appSettingsDidChangeNotificationName.rawValue, "appSettingsDidChange")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.languageDidChangeNotificationName.rawValue, "languageDidChange")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.didChangeModelNotificationName.rawValue, "didChangeModel")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.openMainWindowRequestedNotificationName.rawValue, "openMainWindowRequested")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.appPermissionsDidChangeNotificationName.rawValue, "appPermissionsDidChange")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.promptSelectionChangedNotificationName.rawValue, "promptSelectionChanged")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.powerModeConfigurationAppliedNotificationName.rawValue, "powerModeConfigurationApplied")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.powerModeConfigurationsDidChangeNotificationName.rawValue, "PowerModeConfigurationsDidChange")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.powerModeShortcutAvailabilityDidChangeNotificationName.rawValue, "powerModeShortcutAvailabilityDidChange")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.transcriptionCreatedNotificationName.rawValue, "transcriptionCreated")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.transcriptionCompletedNotificationName.rawValue, "transcriptionCompleted")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.transcriptionDeletedNotificationName.rawValue, "transcriptionDeleted")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.sessionMetricsDidChangeNotificationName.rawValue, "sessionMetricsDidChange")
        XCTAssertEqual(VoiceInkMacOSAppEventRequest.enhancementToggleChangedNotificationName.rawValue, "enhancementToggleChanged")
    }

    func testMacOSApplicationSupportDirectoryUsesBundleIdentifier() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        XCTAssertEqual(
            VoiceInkAppIdentity.macOSApplicationSupportDirectory(in: baseDirectory).path,
            "/tmp/Application Support/com.prakashjoshipax.VoiceInk"
        )
    }

    func testBundleScopedErrorDomainUsesBundleIdentifier() {
        XCTAssertEqual(
            VoiceInkAppIdentity.errorDomain(component: "AudioRecorder"),
            "com.prakashjoshipax.VoiceInk.AudioRecorder"
        )
    }

    func testIOSRecordDeepLinkContractRoundTripsThroughSharedCore() throws {
        let url = VoiceInkAppDeepLink.record.url

        XCTAssertEqual(url, VoiceInkAppIdentity.iOSRecordDeepLinkURL)
        XCTAssertEqual(url.scheme, VoiceInkAppIdentity.iOSRecordDeepLinkScheme)
        XCTAssertEqual(url.host, VoiceInkAppIdentity.iOSRecordDeepLinkHost)
        XCTAssertEqual(VoiceInkAppDeepLink(url: url), .record)
        XCTAssertNil(VoiceInkAppDeepLink(url: try XCTUnwrap(URL(string: "voiceink://settings"))))
        XCTAssertNil(VoiceInkAppDeepLink(url: try XCTUnwrap(URL(string: "roma://record"))))
    }

    func testIOSRecordDeepLinkAppliesRuntimeState() {
        var didHandleRecord = false

        VoiceInkAppDeepLink.record.applyRuntimeState {
            didHandleRecord = true
        }

        XCTAssertTrue(didHandleRecord)
    }

    func testMiniRecorderIntentPresentationPreservesMacOSShortcutCopy() {
        XCTAssertEqual(
            VoiceInkMiniRecorderAppIntentPresentation.toggle,
            VoiceInkAppIntentPresentation(
                title: "Toggle VoiceInk Recorder",
                description: "Start or stop the VoiceInk mini recorder for voice transcription.",
                successDialog: "VoiceInk recorder toggled"
            )
        )

        XCTAssertEqual(
            VoiceInkMiniRecorderAppIntentPresentation.dismiss,
            VoiceInkAppIntentPresentation(
                title: "Dismiss VoiceInk Recorder",
                description: "Dismiss the VoiceInk mini recorder and cancel any active recording.",
                successDialog: "VoiceInk recorder dismissed"
            )
        )
    }

    func testMiniRecorderRequestPreservesMacOSNotificationNames() {
        XCTAssertEqual(VoiceInkMiniRecorderRequest.toggleNotificationName.rawValue, "toggleMiniRecorder")
        XCTAssertEqual(VoiceInkMiniRecorderRequest.dismissNotificationName.rawValue, "dismissMiniRecorder")
    }

    private func announcement(
        id: String,
        description: String? = nil,
        url: String? = nil,
        startAt: String? = nil,
        endAt: String? = nil
    ) -> VoiceInkRemoteAnnouncement {
        VoiceInkRemoteAnnouncement(
            id: id,
            title: "Title \(id)",
            description: description,
            url: url,
            startAt: startAt,
            endAt: endAt
        )
    }

    private func date(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "VoiceInkCore.AppIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        try test(defaults)
    }
}
