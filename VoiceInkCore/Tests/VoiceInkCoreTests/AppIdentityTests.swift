import Foundation
@testable import VoiceInkCore

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
        XCTAssertEqual(VoiceInkMacOSLogCategory.transcriptionAutoCleanupService, "TranscriptionAutoCleanupService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.sessionMetricMigrationService, "SessionMetricMigrationService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.modelPrewarm, "ModelPrewarm")
        XCTAssertEqual(VoiceInkMacOSLogCategory.cursorPaster, "CursorPaster")
        XCTAssertEqual(VoiceInkMacOSLogCategory.sessionMetricRecorder, "SessionMetricRecorder")
        XCTAssertEqual(VoiceInkMacOSLogCategory.soundPlaybackEngine, "SoundPlaybackEngine")
        XCTAssertEqual(VoiceInkMacOSLogCategory.audioTranscriptionManager, "AudioTranscriptionManager")
        XCTAssertEqual(VoiceInkMacOSLogCategory.audioTranscriptionService, "AudioTranscriptionService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.coreAudioRecorder, "CoreAudioRecorder")
        XCTAssertEqual(VoiceInkMacOSLogCategory.whisperTranscriptionService, "WhisperTranscriptionService")
        XCTAssertEqual(VoiceInkMacOSLogCategory.whisperModelManager, "WhisperModelManager")
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
}
