import Foundation
import OSLog
import RomaCore

final class AppIdentityTests: XCTestCase {
    func testAppIdentityPreservesSharedVisibleNames() {
        XCTAssertEqual(RomaAppIdentity.bundleIdentifier, "com.negentropi.RomaJustTalk")
        XCTAssertEqual(RomaAppIdentity.loggingSubsystem, "com.negentropi.RomaJustTalk")
        XCTAssertEqual(RomaAppIdentity.displayName, "roma just talk")
        XCTAssertEqual(RomaAppIdentity.compactDisplayName, "roma-just-talk")
        XCTAssertEqual(RomaAppIdentity.sidebarSubtitle, "speak before hotkey")
        XCTAssertEqual(RomaAppIdentity.iCloudContainerIdentifier, "iCloud.com.negentropi.RomaJustTalk")
        XCTAssertEqual(RomaAppIdentity.iOSAppGroupIdentifier, "group.com.negentropi.RomaJustTalk")
        XCTAssertEqual(RomaAppIdentity.iOSRecordDeepLinkScheme, "romajusttalk")
        XCTAssertEqual(RomaAppIdentity.iOSRecordDeepLinkHost, "record")
        XCTAssertEqual(RomaAppIdentity.iOSRecordDeepLinkURL.absoluteString, "romajusttalk://record")
        XCTAssertEqual(
            RomaAppIdentity.iOSStopRecordingDarwinNotificationName,
            "com.negentropi.RomaJustTalk.stopRecording"
        )
        XCTAssertEqual(
            RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName,
            "com.negentropi.RomaJustTalk.recordingStateChanged"
        )
        XCTAssertEqual(
            RomaAppIdentity.iOSStopRecordingFromKeyboardNotificationName.rawValue,
            "stopRecordingFromKeyboard"
        )
        XCTAssertEqual(RomaAppIdentity.welcomeTitle, "Welcome to roma just talk")
        XCTAssertEqual(RomaAppIdentity.startUsingTitle, "Start Using roma just talk")
        XCTAssertEqual(RomaAppIdentity.onboardingWindowTitle, "roma-just-talk Onboarding")
        XCTAssertEqual(
            RomaAppIdentity.storageFailureMessage,
            "roma-just-talk cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
        )
    }

    func testAppNotificationKindsPreserveCasesAndDefaultDuration() {
        XCTAssertEqual(
            RomaAppNotificationKind.allCases.map(\.rawValue),
            ["error", "warning", "info", "success"]
        )
        XCTAssertEqual(RomaAppNotificationKind.defaultDisplayDuration, 3.0, accuracy: 0.0001)
    }

    func testOnlyErrorNotificationsPlayFailureSound() {
        XCTAssertTrue(RomaAppNotificationKind.error.playsFailureSound)
        XCTAssertFalse(RomaAppNotificationKind.warning.playsFailureSound)
        XCTAssertFalse(RomaAppNotificationKind.info.playsFailureSound)
        XCTAssertFalse(RomaAppNotificationKind.success.playsFailureSound)
    }

    func testSupportContactPolicyPreservesEmailIdentityAndSubject() {
        XCTAssertEqual(RomaSupportContactPolicy.emailAddress, "happyfumd@icloud.com")
        XCTAssertEqual(RomaSupportContactPolicy.emailSubject, "Roma Just Talk Support Request")
        XCTAssertEqual(RomaSupportContactPolicy.commonIssuesURLString, "https://roma-just-talk.com/readme")
    }

    func testSupportMailtoURLPreservesRecipientAndEncodesSubject() throws {
        let url = try XCTUnwrap(RomaSupportContactPolicy.mailtoURL())
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, RomaSupportContactPolicy.emailAddress)
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "subject", value: RomaSupportContactPolicy.emailSubject)
        ])
        XCTAssertEqual(url.absoluteString, "mailto:happyfumd@icloud.com?subject=Roma%20Just%20Talk%20Support%20Request")
    }

    func testSystemArchitecturePreservesMacOSDisplayNameForCompileTarget() {
        #if arch(arm64)
        XCTAssertEqual(RomaSystemArchitecture.macOSDisplayName, "Apple Silicon (ARM64)")
        #elseif arch(x86_64)
        XCTAssertEqual(RomaSystemArchitecture.macOSDisplayName, "Intel (x86_64)")
        #else
        XCTAssertEqual(RomaSystemArchitecture.macOSDisplayName, "Unknown")
        #endif
    }

    func testSystemArchitectureIntelMacPredicateMatchesCompileTarget() {
        #if os(macOS) && arch(x86_64)
        XCTAssertTrue(RomaSystemArchitecture.isIntelMac)
        #else
        XCTAssertFalse(RomaSystemArchitecture.isIntelMac)
        #endif
    }

    func testAvailableAudioDevicesTextPreservesMacOSDiagnosticsListPolicy() {
        XCTAssertEqual(
            RomaSystemInformationReport.availableAudioDevicesText([
                "Built-in Microphone",
                "Studio Display Microphone"
            ]),
            "Built-in Microphone, Studio Display Microphone"
        )
        XCTAssertEqual(
            RomaSystemInformationReport.availableAudioDevicesText([]),
            "None detected"
        )
    }

    func testKnownTextPreservesMacOSUnknownFallback() {
        XCTAssertEqual(RomaSystemInformationReport.unknownValueText, "Unknown")
        XCTAssertEqual(RomaSystemInformationReport.knownText("Mac16,1"), "Mac16,1")
        XCTAssertEqual(RomaSystemInformationReport.knownText(nil), "Unknown")
    }

    func testGeneratedDateTextPreservesMacOSFormattingStyle() {
        let generatedAt = Date(timeIntervalSince1970: 1_782_315_731)

        XCTAssertEqual(
            RomaSystemInformationReport.generatedDateText(generatedAt),
            generatedAt.formatted(date: .long, time: .standard)
        )
    }

    func testDiagnosticLogExportPolicyPreservesMacOSStorageAndFormattingConstants() {
        XCTAssertEqual(
            RomaDiagnosticLogExportPolicy.sessionStartDatesKey,
            "logExporter.sessionStartDates.v1"
        )
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.maxSessionStartDatesToKeep, 3)
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.timestampDateFormat, "yyyy-MM-dd HH:mm:ss.SSS")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.fileNameDateFormat, "yyyy-MM-dd_HH-mm-ss")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.fileNamePrefix, "Roma_Just_Talk_Logs_")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.fileNameExtension, "log")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.headerTitle, "=== Roma Just Talk Diagnostic Logs ===")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.headerDivider, "================================")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.noLogsFoundMessage, "No logs found for this session.")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.exporterErrorDomain, "LogExporter")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.downloadsDirectoryUnavailableErrorCode, 1)
        XCTAssertEqual(
            RomaDiagnosticLogExportPolicy.downloadsDirectoryUnavailableDescription,
            "Downloads directory unavailable"
        )
    }

    func testDiagnosticLogExportPolicyLoadsAndSavesStoredSessionStartDates() throws {
        try withTemporaryDefaults { defaults in
            let first = try localDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0, second: 0)
            let second = try localDate(year: 2026, month: 6, day: 21, hour: 13, minute: 0, second: 0)

            XCTAssertEqual(RomaDiagnosticLogExportPolicy.storedSessionStartDates(from: defaults), [])

            RomaDiagnosticLogExportPolicy.saveSessionStartDates([first, second], to: defaults)

            XCTAssertEqual(
                RomaDiagnosticLogExportPolicy.storedSessionStartDates(from: defaults),
                [first, second]
            )
        }
    }

    func testDiagnosticLogExportPolicyFallsBackToEmptyStoredSessionsForInvalidData() {
        withTemporaryDefaults { defaults in
            defaults.set(Data([0xff]), forKey: RomaDiagnosticLogExportPolicy.sessionStartDatesKey)

            XCTAssertEqual(RomaDiagnosticLogExportPolicy.storedSessionStartDates(from: defaults), [])
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
            RomaDiagnosticLogExportPolicy.sessionStartDates(
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
            RomaDiagnosticLogExportPolicy.sessionRanges(from: [newest, middle, oldest]),
            [
                RomaDiagnosticLogSessionRange(label: "Session 3 (Current)", start: newest, end: nil),
                RomaDiagnosticLogSessionRange(label: "Session 2", start: middle, end: newest),
                RomaDiagnosticLogSessionRange(label: "Session 1 (Oldest)", start: oldest, end: middle)
            ]
        )
    }

    func testDiagnosticLogExportPolicyBuildsSingleSessionRangeLabel() throws {
        let date = try localDate(year: 2026, month: 6, day: 21, hour: 15, minute: 0, second: 0)

        XCTAssertEqual(
            RomaDiagnosticLogExportPolicy.sessionRanges(from: [date]),
            [
                RomaDiagnosticLogSessionRange(label: "Session 1 (Current)", start: date, end: nil)
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
            format: RomaDiagnosticLogExportPolicy.timestampDateFormat
        )

        XCTAssertEqual(
            RomaDiagnosticLogExportPolicy.headerLines(
                exportDate: date,
                subsystem: "com.negentropi.RomaJustTalk",
                sessionCount: 2,
                systemInfo: "System info"
            ),
            [
                "=== Roma Just Talk Diagnostic Logs ===",
                "Export Date: \(formattedTimestamp)",
                "Subsystem: com.negentropi.RomaJustTalk",
                "Total Sessions: 2",
                "================================",
                "",
                "System info",
                ""
            ]
        )
        XCTAssertEqual(
            RomaDiagnosticLogExportPolicy.sessionHeaderLines(label: "Session 2 (Current)"),
            ["--- Session 2 (Current) ---", ""]
        )
        XCTAssertEqual(
            RomaDiagnosticLogExportPolicy.logEntryLine(
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
            RomaDiagnosticLogExportPolicy.exportContent(
                from: [
                    "=== Roma Just Talk Diagnostic Logs ===",
                    "",
                    "No logs found for this session."
                ]
            ),
            "=== Roma Just Talk Diagnostic Logs ===\n\nNo logs found for this session."
        )
    }

    func testDiagnosticLogExportPolicyOwnsOSLogLevelLabels() {
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.logLevelLabel(for: .undefined), "UNDEFINED")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.logLevelLabel(for: .debug), "DEBUG")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.logLevelLabel(for: .info), "INFO")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.logLevelLabel(for: .notice), "NOTICE")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.logLevelLabel(for: .error), "ERROR")
        XCTAssertEqual(RomaDiagnosticLogExportPolicy.logLevelLabel(for: .fault), "FAULT")
    }

    func testDiagnosticLogExportPolicyBuildsMacOSExportFileName() throws {
        let date = try localDate(year: 2026, month: 6, day: 21, hour: 12, minute: 34, second: 56)
        let timestamp = legacyFormattedDate(
            date,
            format: RomaDiagnosticLogExportPolicy.fileNameDateFormat
        )

        XCTAssertEqual(
            RomaDiagnosticLogExportPolicy.fileName(for: date),
            "Roma_Just_Talk_Logs_\(timestamp).log"
        )
    }

    func testDiagnosticLogExportPolicyBuildsDownloadsUnavailableError() {
        let error = RomaDiagnosticLogExportPolicy.downloadsDirectoryUnavailableError()

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

    private static var sampleFacts: RomaMacOSSystemInformationFacts {
        RomaMacOSSystemInformationFacts(
            generated: "June 24, 2026 at 3:42:11 PM",
            appVersion: "1.2.3",
            buildVersion: "456",
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
        XCTAssertEqual(RomaIOSLogCategory.app, "iOSApp")
        XCTAssertEqual(RomaIOSLogCategory.appGroup, "iOSAppGroup")
        XCTAssertEqual(RomaIOSLogCategory.audioPlayback, "iOSAudioPlayback")
        XCTAssertEqual(RomaIOSLogCategory.audioSession, "iOSAudioSession")
        XCTAssertEqual(RomaIOSLogCategory.keyboard, "iOSKeyboard")
        XCTAssertEqual(RomaIOSLogCategory.localWhisper, "iOSLocalWhisper")
        XCTAssertEqual(RomaIOSLogCategory.localModelManagement, "iOSLocalModelManagement")
        XCTAssertEqual(RomaIOSLogCategory.notes, "iOSNotes")
        XCTAssertEqual(RomaIOSLogCategory.recording, "iOSRecording")
        XCTAssertEqual(RomaIOSLogCategory.settings, "iOSSettings")
    }

    func testMacOSLogCategoriesPreserveDiagnosticsIdentity() {
        XCTAssertEqual(RomaMacOSLogCategory.logExporter, "LogExporter")
        XCTAssertEqual(RomaMacOSLogCategory.windowManager, "WindowManager")
        XCTAssertEqual(RomaMacOSLogCategory.menuBarManager, "MenuBarManager")
        XCTAssertEqual(RomaMacOSLogCategory.apiKeyManager, "APIKeyManager")
        XCTAssertEqual(RomaMacOSLogCategory.keychainService, "KeychainService")
        XCTAssertEqual(RomaMacOSLogCategory.aiEnhancementService, "AIEnhancementService")
        XCTAssertEqual(RomaMacOSLogCategory.customCloudModelManager, "CustomCloudModelManager")
        XCTAssertEqual(RomaMacOSLogCategory.transcriptionAutoCleanupService, "TranscriptionAutoCleanupService")
        XCTAssertEqual(RomaMacOSLogCategory.sessionMetricMigrationService, "SessionMetricMigrationService")
        XCTAssertEqual(RomaMacOSLogCategory.modelPrewarm, "ModelPrewarm")
        XCTAssertEqual(RomaMacOSLogCategory.latencyTrace, "LatencyTrace")
        XCTAssertEqual(RomaMacOSLogCategory.cursorPaster, "CursorPaster")
        XCTAssertEqual(RomaMacOSLogCategory.sessionMetricRecorder, "SessionMetricRecorder")
        XCTAssertEqual(RomaMacOSLogCategory.soundPlaybackEngine, "SoundPlaybackEngine")
        XCTAssertEqual(RomaMacOSLogCategory.audioTranscriptionManager, "AudioTranscriptionManager")
        XCTAssertEqual(RomaMacOSLogCategory.audioTranscriptionService, "AudioTranscriptionService")
        XCTAssertEqual(RomaMacOSLogCategory.coreAudioRecorder, "CoreAudioRecorder")
        XCTAssertEqual(RomaMacOSLogCategory.transcriptionServiceRegistry, "TranscriptionServiceRegistry")
        XCTAssertEqual(RomaMacOSLogCategory.nativeAppleTranscriptionService, "NativeAppleTranscriptionService")
        XCTAssertEqual(RomaMacOSLogCategory.nativeAppleLanguageAssetControl, "NativeAppleLanguageAssetControl")
        XCTAssertEqual(RomaMacOSLogCategory.whisperTranscriptionService, "WhisperTranscriptionService")
        XCTAssertEqual(RomaMacOSLogCategory.whisperModelManager, "WhisperModelManager")
        XCTAssertEqual(RomaMacOSLogCategory.audioDeviceManager, "AudioDeviceManager")
    }

    func testMacOSWindowIdentityPreservesIdentifiersTitlesAndFrameNames() {
        XCTAssertEqual(RomaMacOSWindowIdentity.mainIdentifierRawValue, "com.negentropi.RomaJustTalk.mainWindow")
        XCTAssertEqual(RomaMacOSWindowIdentity.onboardingIdentifierRawValue, "com.negentropi.RomaJustTalk.onboardingWindow")
        XCTAssertEqual(RomaMacOSWindowIdentity.historyIdentifierRawValue, "com.negentropi.RomaJustTalk.historyWindow")
        XCTAssertEqual(RomaMacOSWindowIdentity.mainFrameAutosaveName, "RomaMainWindowFrame")
        XCTAssertEqual(RomaMacOSWindowIdentity.historyFrameAutosaveName, "RomaHistoryWindowFrame")
        XCTAssertEqual(RomaMacOSWindowIdentity.mainTitle, "roma-just-talk")
        XCTAssertEqual(RomaMacOSWindowIdentity.onboardingTitle, "roma-just-talk Onboarding")
        XCTAssertEqual(RomaMacOSWindowIdentity.historyTitle, "roma-just-talk - Transcription History")
        XCTAssertEqual(
            RomaMacOSWindowIdentity.identifierListDebugText([
                RomaMacOSWindowIdentity.mainIdentifierRawValue,
                nil,
                RomaMacOSWindowIdentity.historyIdentifierRawValue
            ]),
            "com.negentropi.RomaJustTalk.mainWindow, nil, com.negentropi.RomaJustTalk.historyWindow"
        )
        XCTAssertEqual(RomaMacOSWindowIdentity.identifierListDebugText([]), "")
        XCTAssertEqual(
            RomaMacOSWindowIdentity.configureWindowDuplicateDetectedMessage,
            "configureWindow: duplicate detected, reusing existing window"
        )
        XCTAssertEqual(
            RomaMacOSWindowIdentity.configureWindowRegisteringMainMessage,
            "configureWindow: registering main window"
        )
        XCTAssertEqual(
            RomaMacOSWindowIdentity.resolveMainWindowSearchingMessage(windowCount: 3),
            "resolveMainWindow: weak ref is nil, searching 3 windows by identifier"
        )
        XCTAssertEqual(
            RomaMacOSWindowIdentity.resolveMainWindowRecoveredMessage,
            "resolveMainWindow: recovered window via identifier fallback"
        )
        XCTAssertEqual(
            RomaMacOSWindowIdentity.resolveMainWindowFailedMessage(
                windowCount: 3,
                identifiers: "main, nil, history"
            ),
            "resolveMainWindow: FAILED — no window found with main identifier. Total windows: 3, identifiers: main, nil, history"
        )
        XCTAssertEqual(
            RomaMacOSWindowIdentity.windowWillCloseMainMessage,
            "windowWillClose: main window closing, clearing weak reference"
        )
    }

    func testMacOSNavigationRequestPreservesDestinationContract() {
        XCTAssertEqual(RomaMacOSNavigationRequest.notificationName.rawValue, "navigateToDestination")
        XCTAssertEqual(RomaMacOSNavigationRequest.destinationUserInfoKey, "destination")
        XCTAssertEqual(RomaMacOSNavigationRequest.defaultDestination, .settings)
        XCTAssertEqual(
            RomaMacOSNavigationDestination.allCases.map(\.rawValue),
            [
                "Settings",
                "AI Models",
                "History",
                "Permissions",
                "Enhancement",
                "Transcribe Audio",
                "Power Mode"
            ]
        )

        let notification = Notification(
            name: RomaMacOSNavigationRequest.notificationName,
            userInfo: RomaMacOSNavigationRequest.userInfo(destination: .transcribeAudio)
        )

        XCTAssertEqual(
            RomaMacOSNavigationRequest.destination(from: notification),
            "Transcribe Audio"
        )
    }

    func testMacOSMainViewItemsMapNavigationDestinationsAndLegacyTitles() {
        XCTAssertEqual(
            RomaMacOSMainViewItem.item(forNavigationDestination: RomaMacOSNavigationDestination.settings.rawValue),
            .settings
        )
        XCTAssertEqual(
            RomaMacOSMainViewItem.item(forNavigationDestination: RomaMacOSNavigationDestination.aiModels.rawValue),
            .models
        )
        XCTAssertEqual(RomaMacOSMainViewItem.item(forNavigationDestination: "models"), .models)
        XCTAssertEqual(RomaMacOSMainViewItem.item(forNavigationDestination: "past"), .history)
        XCTAssertEqual(RomaMacOSMainViewItem.item(forNavigationDestination: "style"), .enhancement)
        XCTAssertEqual(RomaMacOSMainViewItem.item(forNavigationDestination: "manual stt"), .transcribeAudio)
        XCTAssertEqual(
            RomaMacOSMainViewItem.item(forNavigationDestination: RomaMacOSNavigationDestination.powerMode.rawValue),
            .powerMode
        )
        XCTAssertNil(RomaMacOSMainViewItem.item(forNavigationDestination: "Audio Input"))
        XCTAssertNil(RomaMacOSMainViewItem.item(forNavigationDestination: "Dictionary"))
    }

    func testMacOSFileTranscriptionRequestPreservesPayloadContract() throws {
        let url = URL(fileURLWithPath: "/tmp/sample.wav")
        let notification = Notification(
            name: RomaMacOSFileTranscriptionRequest.notificationName,
            userInfo: RomaMacOSFileTranscriptionRequest.userInfo(url: url)
        )

        XCTAssertEqual(RomaMacOSFileTranscriptionRequest.notificationName.rawValue, "openFileForTranscription")
        XCTAssertEqual(RomaMacOSFileTranscriptionRequest.urlUserInfoKey, "url")
        XCTAssertEqual(RomaMacOSFileTranscriptionRequest.url(from: notification), url)
    }

    func testMacOSAppEventRequestPreservesNotificationNames() {
        XCTAssertEqual(RomaMacOSAppEventRequest.appSettingsDidChangeNotificationName.rawValue, "appSettingsDidChange")
        XCTAssertEqual(RomaMacOSAppEventRequest.languageDidChangeNotificationName.rawValue, "languageDidChange")
        XCTAssertEqual(RomaMacOSAppEventRequest.didChangeModelNotificationName.rawValue, "didChangeModel")
        XCTAssertEqual(RomaMacOSAppEventRequest.openMainWindowRequestedNotificationName.rawValue, "openMainWindowRequested")
        XCTAssertEqual(RomaMacOSAppEventRequest.appPermissionsDidChangeNotificationName.rawValue, "appPermissionsDidChange")
        XCTAssertEqual(RomaMacOSAppEventRequest.promptSelectionChangedNotificationName.rawValue, "promptSelectionChanged")
        XCTAssertEqual(RomaMacOSAppEventRequest.powerModeConfigurationAppliedNotificationName.rawValue, "powerModeConfigurationApplied")
        XCTAssertEqual(RomaMacOSAppEventRequest.powerModeConfigurationsDidChangeNotificationName.rawValue, "PowerModeConfigurationsDidChange")
        XCTAssertEqual(RomaMacOSAppEventRequest.powerModeShortcutAvailabilityDidChangeNotificationName.rawValue, "powerModeShortcutAvailabilityDidChange")
        XCTAssertEqual(RomaMacOSAppEventRequest.transcriptionCreatedNotificationName.rawValue, "transcriptionCreated")
        XCTAssertEqual(RomaMacOSAppEventRequest.transcriptionCompletedNotificationName.rawValue, "transcriptionCompleted")
        XCTAssertEqual(RomaMacOSAppEventRequest.transcriptionDeletedNotificationName.rawValue, "transcriptionDeleted")
        XCTAssertEqual(RomaMacOSAppEventRequest.sessionMetricsDidChangeNotificationName.rawValue, "sessionMetricsDidChange")
        XCTAssertEqual(RomaMacOSAppEventRequest.enhancementToggleChangedNotificationName.rawValue, "enhancementToggleChanged")
    }

    func testMacOSApplicationSupportDirectoryUsesBundleIdentifier() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        XCTAssertEqual(
            RomaAppIdentity.macOSApplicationSupportDirectory(in: baseDirectory).path,
            "/tmp/Application Support/com.negentropi.RomaJustTalk"
        )
    }

    func testBundleScopedErrorDomainUsesBundleIdentifier() {
        XCTAssertEqual(
            RomaAppIdentity.errorDomain(component: "AudioRecorder"),
            "com.negentropi.RomaJustTalk.AudioRecorder"
        )
    }

    func testIOSRecordDeepLinkContractRoundTripsThroughSharedCore() throws {
        let url = RomaAppDeepLink.record.url

        XCTAssertEqual(url, RomaAppIdentity.iOSRecordDeepLinkURL)
        XCTAssertEqual(url.scheme, RomaAppIdentity.iOSRecordDeepLinkScheme)
        XCTAssertEqual(url.host, RomaAppIdentity.iOSRecordDeepLinkHost)
        XCTAssertEqual(RomaAppDeepLink(url: url), .record)
        XCTAssertNil(RomaAppDeepLink(url: try XCTUnwrap(URL(string: "romajusttalk://settings"))))
        XCTAssertNil(RomaAppDeepLink(url: try XCTUnwrap(URL(string: "voiceink://record"))))
    }

    func testIOSRecordDeepLinkAppliesRuntimeState() {
        var didHandleRecord = false

        RomaAppDeepLink.record.applyRuntimeState {
            didHandleRecord = true
        }

        XCTAssertTrue(didHandleRecord)
    }

    func testMiniRecorderRequestPreservesMacOSNotificationNames() {
        XCTAssertEqual(RomaMiniRecorderRequest.toggleNotificationName.rawValue, "toggleMiniRecorder")
        XCTAssertEqual(RomaMiniRecorderRequest.dismissNotificationName.rawValue, "dismissMiniRecorder")
    }

    private func date(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "RomaCore.AppIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        try test(defaults)
    }
}
