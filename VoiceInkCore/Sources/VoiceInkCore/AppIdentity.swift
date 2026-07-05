import Foundation

public enum VoiceInkAppNotificationKind: String, CaseIterable, Sendable {
    case error
    case warning
    case info
    case success

    public static let defaultDisplayDuration: TimeInterval = 3.0

    public var systemImageName: String {
        switch self {
        case .error:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        }
    }

    public var playsFailureSound: Bool {
        self == .error
    }
}

public enum VoiceInkSupportContactPolicy {
    public static let emailAddress = "support@tryvoiceink.com"
    public static let emailSubject = "VoiceInk Support Request"
    public static let commonIssuesURLString = "https://tryvoiceink.com/common-issues"

    public static func emailBody(systemInformation: String) -> String {
        """

        ------------------------
        ✨ **SCREEN RECORDING HIGHLY RECOMMENDED** ✨
        ▶️ Create a quick screen recording showing the issue!
        ▶️ It helps me understand and fix the problem much faster.

        📝 ISSUE DETAILS:
        - What steps did you take before the issue occurred?
        - What did you expect to happen?
        - What actually happened instead?


        ## 📋 COMMON ISSUES:
        Check out our Common Issues page before sending an email: \(commonIssuesURLString)
        ------------------------

        System Information:
        \(systemInformation)


        """
    }

    public static func mailtoURL(subject: String = emailSubject) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = emailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]
        return components.url
    }
}

public struct VoiceInkRemoteAnnouncement: Decodable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let url: String?
    public let startAt: String?
    public let endAt: String?

    public init(
        id: String,
        title: String,
        description: String?,
        url: String?,
        startAt: String?,
        endAt: String?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.startAt = startAt
        self.endAt = endAt
    }
}

public struct VoiceInkAnnouncementPresentation: Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let learnMoreURL: URL?
    public let closeButtonSystemImageName: String
    public let learnMoreButtonTitle: String
    public let dismissButtonTitle: String

    public init(
        id: String,
        title: String,
        description: String?,
        learnMoreURL: URL?,
        closeButtonSystemImageName: String = "xmark",
        learnMoreButtonTitle: String = "Learn more",
        dismissButtonTitle: String = "Dismiss"
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.learnMoreURL = learnMoreURL
        self.closeButtonSystemImageName = closeButtonSystemImageName
        self.learnMoreButtonTitle = learnMoreButtonTitle
        self.dismissButtonTitle = dismissButtonTitle
    }

    public var descriptionText: String {
        description ?? ""
    }

    public var shouldShowDescription: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum VoiceInkAnnouncementPreference {
    public static let isEnabledKey = VoiceInkUserDefaultsKey.enableAnnouncements
    public static let dismissedIdsKey = "dismissedAnnouncementIds"
    public static let defaultIsEnabled = VoiceInkPreferenceDefault.enableAnnouncements
    public static let maxDismissedIdsToKeep = 2
    public static let announcementsURLString = "https://beingpax.github.io/VoiceInk/announcements.json"
    public static let refreshInterval: TimeInterval = 4 * 60 * 60
    public static let initialFetchDelay: TimeInterval = 5
    public static let requestTimeout: TimeInterval = 10

    public static var announcementsURL: URL {
        URL(string: announcementsURLString)!
    }

    public static var registeredDefaults: [String: Any] {
        [
            isEnabledKey: defaultIsEnabled
        ]
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }

        return defaults.bool(forKey: isEnabledKey)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: isEnabledKey)
    }

    public static func dismissedIds(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: dismissedIdsKey) ?? []
    }

    public static func saveDismissedIds(_ ids: [String], to defaults: UserDefaults = .standard) {
        defaults.set(ids, forKey: dismissedIdsKey)
    }

    public static func isDismissed(_ id: String, dismissedIds: [String]) -> Bool {
        dismissedIds.contains(id)
    }

    public static func dismissedIds(afterDismissing id: String, currentIds: [String]) -> [String] {
        var ids = currentIds
        if !ids.contains(id) {
            ids.append(id)
        }

        if ids.count > maxDismissedIdsToKeep {
            ids.removeFirst(ids.count - maxDismissedIdsToKeep)
        }

        return ids
    }
}

public enum VoiceInkAnnouncementPolicy {
    public static func nextAnnouncement(
        from announcements: [VoiceInkRemoteAnnouncement],
        dismissedIds: [String],
        now: Date
    ) -> VoiceInkAnnouncementPresentation? {
        let formatter = ISO8601DateFormatter()

        guard let announcement = announcements.first(where: {
            !VoiceInkAnnouncementPreference.isDismissed($0.id, dismissedIds: dismissedIds)
                && isActive($0, at: now, formatter: formatter)
        }) else {
            return nil
        }

        return VoiceInkAnnouncementPresentation(
            id: announcement.id,
            title: announcement.title,
            description: announcement.description,
            learnMoreURL: announcement.url.flatMap(URL.init(string:))
        )
    }

    public static func isActive(
        _ announcement: VoiceInkRemoteAnnouncement,
        at date: Date
    ) -> Bool {
        isActive(announcement, at: date, formatter: ISO8601DateFormatter())
    }

    private static func isActive(
        _ announcement: VoiceInkRemoteAnnouncement,
        at date: Date,
        formatter: ISO8601DateFormatter
    ) -> Bool {
        if let startAt = announcement.startAt,
           let start = formatter.date(from: startAt),
           date < start {
            return false
        }

        if let endAt = announcement.endAt,
           let end = formatter.date(from: endAt),
           date > end {
            return false
        }

        return true
    }
}

public struct VoiceInkAppIntentPresentation: Equatable, Sendable {
    public let title: String
    public let description: String
    public let successDialog: String

    public init(title: String, description: String, successDialog: String) {
        self.title = title
        self.description = description
        self.successDialog = successDialog
    }
}

public enum VoiceInkMiniRecorderAppIntentPresentation {
    public static let toggle = VoiceInkAppIntentPresentation(
        title: "Toggle VoiceInk Recorder",
        description: "Start or stop the VoiceInk mini recorder for voice transcription.",
        successDialog: "VoiceInk recorder toggled"
    )

    public static let dismiss = VoiceInkAppIntentPresentation(
        title: "Dismiss VoiceInk Recorder",
        description: "Dismiss the VoiceInk mini recorder and cancel any active recording.",
        successDialog: "VoiceInk recorder dismissed"
    )
}

public enum VoiceInkMiniRecorderRequest {
    public static let toggleNotificationName = Notification.Name("toggleMiniRecorder")
    public static let dismissNotificationName = Notification.Name("dismissMiniRecorder")
}

public struct VoiceInkMacOSStorageAlertPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let buttonTitle: String
}

public enum VoiceInkMacOSNavigationDestination: String, CaseIterable, Sendable {
    case settings = "Settings"
    case aiModels = "AI Models"
    case license = "VoiceInk Pro"
    case history = "History"
    case permissions = "Permissions"
    case enhancement = "Enhancement"
    case transcribeAudio = "Transcribe Audio"
    case powerMode = "Power Mode"
}

public enum VoiceInkMacOSMainViewItem: String, CaseIterable, Identifiable, Sendable {
    case metrics
    case transcribeAudio
    case history
    case models
    case enhancement
    case powerMode
    case permissions
    case audioInput
    case dictionary
    case settings
    case license

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .metrics:
            return "home"
        case .transcribeAudio:
            return "manual stt"
        case .history:
            return "past"
        case .models:
            return "models"
        case .enhancement:
            return "style"
        case .powerMode:
            return "Power Mode"
        case .permissions:
            return "Permissions"
        case .audioInput:
            return "Audio Input"
        case .dictionary:
            return "Dictionary"
        case .settings:
            return "Settings"
        case .license:
            return "VoiceInk Pro"
        }
    }

    public var systemImageName: String {
        switch self {
        case .metrics:
            return "gauge.medium"
        case .transcribeAudio:
            return "waveform.circle.fill"
        case .history:
            return "doc.text.fill"
        case .models:
            return "brain.head.profile"
        case .enhancement:
            return "wand.and.stars"
        case .powerMode:
            return "sparkles.square.fill.on.square"
        case .permissions:
            return "shield.fill"
        case .audioInput:
            return "mic.fill"
        case .dictionary:
            return "character.book.closed.fill"
        case .settings:
            return "gearshape.fill"
        case .license:
            return "checkmark.seal.fill"
        }
    }

    public static let defaultSelection = VoiceInkMacOSMainViewItem.metrics
    public static let emptySelectionTitle = "Select a view"

    public static func visibleItems(powerModeEnabled: Bool) -> [VoiceInkMacOSMainViewItem] {
        allCases.filter { item in
            item != .powerMode || powerModeEnabled
        }
    }

    public static func item(forNavigationDestination destination: String) -> VoiceInkMacOSMainViewItem? {
        switch destination {
        case VoiceInkMacOSNavigationDestination.settings.rawValue:
            return .settings
        case VoiceInkMacOSNavigationDestination.aiModels.rawValue, VoiceInkMacOSMainViewItem.models.title:
            return .models
        case VoiceInkMacOSNavigationDestination.license.rawValue:
            return .license
        case VoiceInkMacOSNavigationDestination.history.rawValue, VoiceInkMacOSMainViewItem.history.title:
            return .history
        case VoiceInkMacOSNavigationDestination.permissions.rawValue:
            return .permissions
        case VoiceInkMacOSNavigationDestination.enhancement.rawValue, VoiceInkMacOSMainViewItem.enhancement.title:
            return .enhancement
        case VoiceInkMacOSNavigationDestination.transcribeAudio.rawValue, VoiceInkMacOSMainViewItem.transcribeAudio.title:
            return .transcribeAudio
        case VoiceInkMacOSNavigationDestination.powerMode.rawValue:
            return .powerMode
        default:
            return nil
        }
    }
}

public enum VoiceInkMacOSNavigationRequest {
    public static let notificationName = Notification.Name("navigateToDestination")
    public static let destinationUserInfoKey = "destination"
    public static let defaultDestination = VoiceInkMacOSNavigationDestination.settings

    public static func userInfo(destination: VoiceInkMacOSNavigationDestination) -> [AnyHashable: Any] {
        userInfo(destination: destination.rawValue)
    }

    public static func userInfo(destination: String) -> [AnyHashable: Any] {
        [destinationUserInfoKey: destination]
    }

    public static func destination(from notification: Notification) -> String? {
        notification.userInfo?[destinationUserInfoKey] as? String
    }
}

public enum VoiceInkMacOSFileTranscriptionRequest {
    public static let notificationName = Notification.Name("openFileForTranscription")
    public static let urlUserInfoKey = "url"

    public static func userInfo(url: URL) -> [AnyHashable: Any] {
        [urlUserInfoKey: url]
    }

    public static func url(from notification: Notification) -> URL? {
        notification.userInfo?[urlUserInfoKey] as? URL
    }
}

public enum VoiceInkMacOSAppEventRequest {
    public static let appSettingsDidChangeNotificationName = Notification.Name("appSettingsDidChange")
    public static let languageDidChangeNotificationName = Notification.Name("languageDidChange")
    public static let didChangeModelNotificationName = Notification.Name("didChangeModel")
    public static let openMainWindowRequestedNotificationName = Notification.Name("openMainWindowRequested")
    public static let appPermissionsDidChangeNotificationName = Notification.Name("appPermissionsDidChange")
    public static let promptSelectionChangedNotificationName = Notification.Name("promptSelectionChanged")
    public static let powerModeConfigurationAppliedNotificationName = Notification.Name("powerModeConfigurationApplied")
    public static let powerModeConfigurationsDidChangeNotificationName = Notification.Name("PowerModeConfigurationsDidChange")
    public static let powerModeShortcutAvailabilityDidChangeNotificationName = Notification.Name("powerModeShortcutAvailabilityDidChange")
    public static let transcriptionCreatedNotificationName = Notification.Name("transcriptionCreated")
    public static let transcriptionCompletedNotificationName = Notification.Name("transcriptionCompleted")
    public static let transcriptionDeletedNotificationName = Notification.Name("transcriptionDeleted")
    public static let sessionMetricsDidChangeNotificationName = Notification.Name("sessionMetricsDidChange")
    public static let enhancementToggleChangedNotificationName = Notification.Name("enhancementToggleChanged")
}

public enum VoiceInkMacOSWindowIdentity {
    public static var mainIdentifierRawValue: String {
        "\(VoiceInkAppIdentity.loggingSubsystem).mainWindow"
    }

    public static var onboardingIdentifierRawValue: String {
        "\(VoiceInkAppIdentity.loggingSubsystem).onboardingWindow"
    }

    public static var historyIdentifierRawValue: String {
        "\(VoiceInkAppIdentity.loggingSubsystem).historyWindow"
    }

    public static let mainFrameAutosaveName = "VoiceInkMainWindowFrame"
    public static let historyFrameAutosaveName = "VoiceInkHistoryWindowFrame"

    public static var mainTitle: String {
        VoiceInkAppIdentity.compactDisplayName
    }

    public static var onboardingTitle: String {
        VoiceInkAppIdentity.onboardingWindowTitle
    }

    public static var historyTitle: String {
        "\(VoiceInkAppIdentity.compactDisplayName) - Transcription History"
    }

    public static func identifierListDebugText(_ rawValues: [String?]) -> String {
        rawValues.map { $0 ?? "nil" }.joined(separator: ", ")
    }

    public static let configureWindowDuplicateDetectedMessage = "configureWindow: duplicate detected, reusing existing window"
    public static let configureWindowRegisteringMainMessage = "configureWindow: registering main window"
    public static let resolveMainWindowRecoveredMessage = "resolveMainWindow: recovered window via identifier fallback"
    public static let windowWillCloseMainMessage = "windowWillClose: main window closing, clearing weak reference"

    public static func resolveMainWindowSearchingMessage(windowCount: Int) -> String {
        "resolveMainWindow: weak ref is nil, searching \(windowCount) windows by identifier"
    }

    public static func resolveMainWindowFailedMessage(windowCount: Int, identifiers: String) -> String {
        "resolveMainWindow: FAILED — no window found with main identifier. Total windows: \(windowCount), identifiers: \(identifiers)"
    }
}

public enum VoiceInkMacOSLogCategory {
    public static let logExporter = "LogExporter"
    public static let windowManager = "WindowManager"
    public static let menuBarManager = "MenuBarManager"
    public static let apiKeyManager = "APIKeyManager"
    public static let keychainService = "KeychainService"
    public static let polarService = "PolarService"
    public static let licenseViewModel = "LicenseViewModel"
    public static let aiEnhancementService = "AIEnhancementService"
    public static let customCloudModelManager = "CustomCloudModelManager"
    public static let transcriptionAutoCleanupService = "TranscriptionAutoCleanupService"
    public static let sessionMetricMigrationService = "SessionMetricMigrationService"
    public static let modelPrewarm = "ModelPrewarm"
    public static let cursorPaster = "CursorPaster"
    public static let sessionMetricRecorder = "SessionMetricRecorder"
    public static let soundPlaybackEngine = "SoundPlaybackEngine"
    public static let audioTranscriptionManager = "AudioTranscriptionManager"
    public static let audioTranscriptionService = "AudioTranscriptionService"
    public static let coreAudioRecorder = "CoreAudioRecorder"
    public static let transcriptionServiceRegistry = "TranscriptionServiceRegistry"
    public static let nativeAppleTranscriptionService = "NativeAppleTranscriptionService"
    public static let nativeAppleLanguageAssetControl = "NativeAppleLanguageAssetControl"
    public static let whisperTranscriptionService = "WhisperTranscriptionService"
    public static let whisperModelManager = "WhisperModelManager"
    public static let audioDeviceManager = "AudioDeviceManager"
}

public enum VoiceInkAppIdentity {
    public static let bundleIdentifier = "com.prakashjoshipax.VoiceInk"
    public static let loggingSubsystem = "com.prakashjoshipax.voiceink"
    public static let displayName = "roma just talk"
    public static let compactDisplayName = "roma-just-talk"
    public static let sidebarSubtitle = "speak before hotkey"
    public static let iOSRecordDeepLinkScheme = "voiceink"
    public static let iOSRecordDeepLinkHost = "record"

    public static var iCloudContainerIdentifier: String {
        "iCloud.\(bundleIdentifier)"
    }

    public static var iOSAppGroupIdentifier: String {
        "group.\(bundleIdentifier)"
    }

    public static var iOSRecordDeepLinkURL: URL {
        URL(string: "\(iOSRecordDeepLinkScheme)://\(iOSRecordDeepLinkHost)")!
    }

    public static var iOSStopRecordingDarwinNotificationName: String {
        "\(bundleIdentifier).stopRecording"
    }

    public static var iOSRecordingStateChangedDarwinNotificationName: String {
        "\(bundleIdentifier).recordingStateChanged"
    }

    public static let iOSStopRecordingFromKeyboardNotificationName = Notification.Name("stopRecordingFromKeyboard")

    public static var welcomeTitle: String {
        "Welcome to \(displayName)"
    }

    public static var startUsingTitle: String {
        "Start Using \(displayName)"
    }

    public static var onboardingWindowTitle: String {
        "\(compactDisplayName) Onboarding"
    }

    public static var storageFailureMessage: String {
        "\(compactDisplayName) cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
    }

    public static let storageFallbackWarningPresentation = VoiceInkMacOSStorageAlertPresentation(
        title: "Storage Warning",
        message: "VoiceInk couldn't access its storage location. Your transcriptions will not be saved between sessions.",
        buttonTitle: "OK"
    )

    public static var storageFailurePresentation: VoiceInkMacOSStorageAlertPresentation {
        VoiceInkMacOSStorageAlertPresentation(
            title: "Critical Storage Error",
            message: storageFailureMessage,
            buttonTitle: "Quit"
        )
    }

    public static func macOSApplicationSupportDirectory(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    public static func errorDomain(component: String) -> String {
        "\(bundleIdentifier).\(component)"
    }
}

public enum VoiceInkStorageStartupDiagnostics {
    public static let modelContainerInitializationFailedMessage = "ModelContainer initialization failed"
    public static let modelContainerUnavailablePreconditionMessage = "Unable to create ModelContainer. SwiftData is unavailable."

    public static func iOSModelContainerCreationFailedMessage(errorDescription: String) -> String {
        "Could not create ModelContainer: \(errorDescription)"
    }
}

public enum VoiceInkIOSLogCategory {
    public static let app = "iOSApp"
    public static let appGroup = "iOSAppGroup"
    public static let audioPlayback = "iOSAudioPlayback"
    public static let audioSession = "iOSAudioSession"
    public static let keyboard = "iOSKeyboard"
    public static let localWhisper = "iOSLocalWhisper"
    public static let localModelManagement = "iOSLocalModelManagement"
    public static let notes = "iOSNotes"
    public static let recording = "iOSRecording"
    public static let settings = "iOSSettings"
}

public enum VoiceInkAppDeepLink: Equatable, Sendable {
    case record

    public var url: URL {
        switch self {
        case .record:
            return VoiceInkAppIdentity.iOSRecordDeepLinkURL
        }
    }

    public init?(url: URL) {
        guard url.scheme == VoiceInkAppIdentity.iOSRecordDeepLinkScheme else {
            return nil
        }

        guard url.host == VoiceInkAppIdentity.iOSRecordDeepLinkHost else {
            return nil
        }

        self = .record
    }

    public func applyRuntimeState(
        handleRecord: () -> Void
    ) {
        switch self {
        case .record:
            handleRecord()
        }
    }
}
