import Foundation

public struct VoiceInkOnboardingFeaturePresentation: Equatable, Sendable {
    public let iconSystemName: String
    public let title: String
    public let description: String

    public init(iconSystemName: String, title: String, description: String) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.description = description
    }
}

public struct VoiceInkOnboardingStepPresentation: Equatable, Sendable {
    public let number: String
    public let title: String
    public let description: String

    public init(number: String, title: String, description: String) {
        self.number = number
        self.title = title
        self.description = description
    }
}

public struct VoiceInkOnboardingWelcomePresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let features: [VoiceInkOnboardingFeaturePresentation]
    public let primaryButtonTitle: String

    public init(
        title: String,
        subtitle: String,
        features: [VoiceInkOnboardingFeaturePresentation],
        primaryButtonTitle: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.features = features
        self.primaryButtonTitle = primaryButtonTitle
    }
}

public struct VoiceInkMacOSOnboardingWelcomePresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let primaryButtonTitle: String
    public let skipButtonTitle: String
    public let typewriterRoles: [String]

    public init(
        title: String,
        subtitle: String,
        primaryButtonTitle: String,
        skipButtonTitle: String,
        typewriterRoles: [String]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryButtonTitle = primaryButtonTitle
        self.skipButtonTitle = skipButtonTitle
        self.typewriterRoles = typewriterRoles
    }
}

public struct VoiceInkOnboardingModelDownloadPresentation: Equatable, Sendable {
    public let iconSystemName: String
    public let title: String
    public let subtitle: String
    public let continueButtonTitle: String

    public init(
        iconSystemName: String,
        title: String,
        subtitle: String,
        continueButtonTitle: String
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.subtitle = subtitle
        self.continueButtonTitle = continueButtonTitle
    }

    public func primaryAction(
        for rowPresentation: VoiceInkWhisperModelDownloadRowPresentation
    ) -> VoiceInkOnboardingModelDownloadPrimaryAction {
        switch rowPresentation.action {
        case .downloading:
            return .waitForDownload(title: rowPresentation.progress.compactStatusText)
        case .downloaded:
            return .continueSetup(title: continueButtonTitle)
        case .download:
            return .requestDownload(
                title: rowPresentation.downloadButtonTitle,
                systemImageName: rowPresentation.downloadButtonSystemImageName
            )
        }
    }
}

private enum VoiceInkOnboardingModelDownloadPrimaryActionKind: Equatable, Sendable {
    case waitForDownload
    case continueSetup
    case requestDownload
}

public struct VoiceInkOnboardingModelDownloadPrimaryAction: Equatable, Sendable {
    public let title: String
    public let systemImageName: String?
    private let kind: VoiceInkOnboardingModelDownloadPrimaryActionKind

    static func waitForDownload(title: String) -> Self {
        VoiceInkOnboardingModelDownloadPrimaryAction(
            title: title,
            systemImageName: nil,
            kind: .waitForDownload
        )
    }

    static func continueSetup(title: String) -> Self {
        VoiceInkOnboardingModelDownloadPrimaryAction(
            title: title,
            systemImageName: nil,
            kind: .continueSetup
        )
    }

    static func requestDownload(title: String, systemImageName: String) -> Self {
        VoiceInkOnboardingModelDownloadPrimaryAction(
            title: title,
            systemImageName: systemImageName,
            kind: .requestDownload
        )
    }

    public var isEnabled: Bool {
        runtimeAction(continueSetup: {}, requestDownload: {}) != nil
    }

    public func runtimeAction(
        continueSetup: @escaping () -> Void,
        requestDownload: @escaping () -> Void
    ) -> (() -> Void)? {
        switch kind {
        case .waitForDownload:
            return nil
        case .continueSetup:
            return continueSetup
        case .requestDownload:
            return requestDownload
        }
    }
}

public struct VoiceInkMacOSOnboardingModelDownloadPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let continueButtonTitle: String
    public let skipButtonTitle: String
    public let downloadingButtonTitle: String
    public let setAsDefaultButtonTitle: String
    public let downloadButtonTitle: String
    public let speedLabel: String
    public let accuracyLabel: String
    public let ramLabel: String

    public init(
        title: String,
        subtitle: String,
        continueButtonTitle: String,
        skipButtonTitle: String,
        downloadingButtonTitle: String,
        setAsDefaultButtonTitle: String,
        downloadButtonTitle: String,
        speedLabel: String,
        accuracyLabel: String,
        ramLabel: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.continueButtonTitle = continueButtonTitle
        self.skipButtonTitle = skipButtonTitle
        self.downloadingButtonTitle = downloadingButtonTitle
        self.setAsDefaultButtonTitle = setAsDefaultButtonTitle
        self.downloadButtonTitle = downloadButtonTitle
        self.speedLabel = speedLabel
        self.accuracyLabel = accuracyLabel
        self.ramLabel = ramLabel
    }

    public func buttonTitle(
        isModelSet: Bool,
        isDownloading: Bool,
        isModelDownloaded: Bool
    ) -> String {
        if isModelSet {
            return continueButtonTitle
        }
        if isDownloading {
            return downloadingButtonTitle
        }
        if isModelDownloaded {
            return setAsDefaultButtonTitle
        }
        return downloadButtonTitle
    }
}

public struct VoiceInkMacOSOnboardingTutorialPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let shortcutTitle: String
    public let instructionSteps: [String]
    public let completeButtonTitle: String
    public let skipButtonTitle: String
    public let placeholderIconSystemName: String
    public let placeholderText: String

    public init(
        title: String,
        subtitle: String,
        shortcutTitle: String,
        instructionSteps: [String],
        completeButtonTitle: String,
        skipButtonTitle: String,
        placeholderIconSystemName: String,
        placeholderText: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.shortcutTitle = shortcutTitle
        self.instructionSteps = instructionSteps
        self.completeButtonTitle = completeButtonTitle
        self.skipButtonTitle = skipButtonTitle
        self.placeholderIconSystemName = placeholderIconSystemName
        self.placeholderText = placeholderText
    }
}

public struct VoiceInkMacOSResetOnboardingPresentation: Equatable, Sendable {
    public let buttonTitle: String
    public let alertTitle: String
    public let cancelButtonTitle: String
    public let confirmButtonTitle: String
    public let message: String

    public init(
        buttonTitle: String,
        alertTitle: String,
        cancelButtonTitle: String,
        confirmButtonTitle: String,
        message: String
    ) {
        self.buttonTitle = buttonTitle
        self.alertTitle = alertTitle
        self.cancelButtonTitle = cancelButtonTitle
        self.confirmButtonTitle = confirmButtonTitle
        self.message = message
    }
}

enum VoiceInkMacOSSetupStepKind: String, Equatable, Sendable {
    case shortcut
    case accessibility
    case screenContext
    case modelDownload
}

public struct VoiceInkMacOSSetupStepPresentation: Identifiable, Equatable, Sendable {
    let kind: VoiceInkMacOSSetupStepKind
    public let isOptional: Bool
    public let iconSystemName: String
    public let title: String
    public let description: String

    public var id: String { kind.rawValue }

    init(
        kind: VoiceInkMacOSSetupStepKind,
        isOptional: Bool,
        iconSystemName: String,
        title: String,
        description: String
    ) {
        self.kind = kind
        self.isOptional = isOptional
        self.iconSystemName = iconSystemName
        self.title = title
        self.description = description
    }

    public func isCompleted(
        isShortcutConfigured: Bool,
        isAccessibilityEnabled: Bool,
        isScreenRecordingEnabled: Bool,
        hasCurrentTranscriptionModel: Bool
    ) -> Bool {
        switch kind {
        case .shortcut:
            return isShortcutConfigured
        case .accessibility:
            return isAccessibilityEnabled
        case .screenContext:
            return isScreenRecordingEnabled
        case .modelDownload:
            return hasCurrentTranscriptionModel
        }
    }
}

public struct VoiceInkOnboardingReadyPresentation: Equatable, Sendable {
    public let iconSystemName: String
    public let title: String
    public let subtitle: String
    public let steps: [VoiceInkOnboardingStepPresentation]
    public let primaryButtonTitle: String

    public init(
        iconSystemName: String,
        title: String,
        subtitle: String,
        steps: [VoiceInkOnboardingStepPresentation],
        primaryButtonTitle: String
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.subtitle = subtitle
        self.steps = steps
        self.primaryButtonTitle = primaryButtonTitle
    }
}

public enum VoiceInkMacOSOnboardingPresentation {
    public static let welcome = VoiceInkMacOSOnboardingWelcomePresentation(
        title: "Welcome to the Future of Typing",
        subtitle: "A New Way to Type",
        primaryButtonTitle: "Get Started",
        skipButtonTitle: "Skip Tour",
        typewriterRoles: [
            "Your Writing Assistant",
            "Your Vibe-Coding Assistant",
            "Works Everywhere on Mac with a click",
            "100% offline & private"
        ]
    )

    public static let modelDownload = VoiceInkMacOSOnboardingModelDownloadPresentation(
        title: "Download AI Model",
        subtitle: "We'll download the optimized model to get you started.",
        continueButtonTitle: "Continue",
        skipButtonTitle: "Skip for now",
        downloadingButtonTitle: "Downloading...",
        setAsDefaultButtonTitle: VoiceInkModelManagementPresentation.setAsDefaultButtonTitle,
        downloadButtonTitle: "Download Model",
        speedLabel: "Speed",
        accuracyLabel: "Accuracy",
        ramLabel: "RAM"
    )

    public static let tutorial = VoiceInkMacOSOnboardingTutorialPresentation(
        title: "Try It Out!",
        subtitle: "Let's test your roma-just-talk setup.",
        shortcutTitle: "Your Shortcut",
        instructionSteps: [
            "Click the text area on the right",
            "Press your shortcut key",
            "Speak something",
            "Press your shortcut key again"
        ],
        completeButtonTitle: "Complete Setup",
        skipButtonTitle: "Skip for now",
        placeholderIconSystemName: "wand.and.stars",
        placeholderText: "Click here and start speaking..."
    )

    public static let resetSettingsAlert = VoiceInkMacOSResetOnboardingPresentation(
        buttonTitle: "Reset Onboarding",
        alertTitle: "Reset Onboarding",
        cancelButtonTitle: "Cancel",
        confirmButtonTitle: "Reset",
        message: "You'll see the introduction screens again the next time you launch the app."
    )
}

public enum VoiceInkMacOSSetupPresentation {
    public static let title = "Welcome to VoiceInk"
    public static let subtitle = "Complete the setup to get started"
    public static let helpText = "Need help? Check the Help menu for support options"
    public static let actionSystemImageName = "arrow.right"
    public static let completedSystemImageName = "checkmark.circle.fill"
    public static let optionalSystemImageName = "circle"
    public static let requiredSystemImageName = "chevron.right"

    public static let steps = [
        VoiceInkMacOSSetupStepPresentation(
            kind: .shortcut,
            isOptional: false,
            iconSystemName: "command",
            title: "Set Keyboard Shortcut",
            description: "Use VoiceInk anywhere with a shortcut."
        ),
        VoiceInkMacOSSetupStepPresentation(
            kind: .accessibility,
            isOptional: false,
            iconSystemName: "hand.raised.fill",
            title: "Enable Accessibility",
            description: "Paste transcribed text at your cursor."
        ),
        VoiceInkMacOSSetupStepPresentation(
            kind: .screenContext,
            isOptional: true,
            iconSystemName: "video.fill",
            title: "Screen Context (Optional)",
            description: "Use visible text for better transcript enhancement when you choose."
        ),
        VoiceInkMacOSSetupStepPresentation(
            kind: .modelDownload,
            isOptional: false,
            iconSystemName: "arrow.down.to.line",
            title: "Download Model",
            description: "Choose an AI model to start transcribing."
        )
    ]

    public static func actionButtonTitle(
        isShortcutConfigured: Bool,
        isAccessibilityEnabled: Bool,
        hasTranscriptionModel: Bool
    ) -> String {
        if !isShortcutConfigured {
            return "Configure Shortcut"
        }
        if !isAccessibilityEnabled {
            return "Enable Accessibility"
        }
        if !hasTranscriptionModel {
            return "Download Model"
        }
        return "Get Started"
    }
}

public enum VoiceInkIOSOnboardingStep: CaseIterable, Equatable, Sendable {
    case welcome
    case modelDownload
    case ready

    public static let initial = VoiceInkIOSOnboardingStep.welcome

    public var nextStep: VoiceInkIOSOnboardingStep? {
        switch self {
        case .welcome:
            return .modelDownload
        case .modelDownload:
            return .ready
        case .ready:
            return nil
        }
    }

    public mutating func advance() {
        guard let followingStep = nextStep else { return }
        self = followingStep
    }
}

public enum VoiceInkIOSOnboardingPresentation {
    public static let appIconFallbackSystemImageName = "app.fill"

    public static let welcome = VoiceInkOnboardingWelcomePresentation(
        title: VoiceInkAppIdentity.welcomeTitle,
        subtitle: "Transform your thoughts into text effortlessly.",
        features: [
            VoiceInkOnboardingFeaturePresentation(
                iconSystemName: "mic.fill",
                title: "Instant Recording",
                description: "Capture your thoughts with a single tap, anytime, anywhere."
            ),
            VoiceInkOnboardingFeaturePresentation(
                iconSystemName: "bolt.fill",
                title: "Accurate Transcription",
                description: "Leverage powerful AI models for precise speech-to-text conversion."
            ),
            VoiceInkOnboardingFeaturePresentation(
                iconSystemName: "icloud.slash.fill",
                title: "Works Offline",
                description: "Transcribe without an internet connection using local models."
            )
        ],
        primaryButtonTitle: "Get Started"
    )

    public static let modelDownload = VoiceInkOnboardingModelDownloadPresentation(
        iconSystemName: "cpu",
        title: "Offline Transcription",
        subtitle: "Download a local model to transcribe audio even without an internet connection.",
        continueButtonTitle: "Continue"
    )

    public static let ready = VoiceInkOnboardingReadyPresentation(
        iconSystemName: "checkmark.circle.fill",
        title: "You're All Set!",
        subtitle: "Start recording your thoughts and ideas.",
        steps: [
            VoiceInkOnboardingStepPresentation(
                number: "1",
                title: "Record",
                description: "Tap the record button to capture your thoughts."
            ),
            VoiceInkOnboardingStepPresentation(
                number: "2",
                title: "Transcribe",
                description: "AI converts your speech to text automatically."
            ),
            VoiceInkOnboardingStepPresentation(
                number: "3",
                title: "Save & Organize",
                description: "Your notes are saved and ready for review."
            )
        ],
        primaryButtonTitle: VoiceInkAppIdentity.startUsingTitle
    )
}

public enum VoiceInkIOSAppIconSource: Equatable, Sendable {
    case assetName(String)
    case fallbackSystemImageName(String)
}

public enum VoiceInkIOSAppIconPolicy {
    private static let bundleIconsKey = "CFBundleIcons"
    private static let bundlePrimaryIconKey = "CFBundlePrimaryIcon"
    private static let bundleIconFilesKey = "CFBundleIconFiles"

    public static func bundleIconFiles(from infoDictionary: [String: Any]?) -> [String]? {
        guard let iconsDictionary = infoDictionary?[bundleIconsKey] as? [String: Any],
              let primaryIconsDictionary = iconsDictionary[bundlePrimaryIconKey] as? [String: Any] else {
            return nil
        }

        return primaryIconsDictionary[bundleIconFilesKey] as? [String]
    }

    public static func source(
        iconFiles: [String]?,
        canLoadImageNamed: (String) -> Bool
    ) -> VoiceInkIOSAppIconSource {
        guard let iconName = iconFiles?.last, canLoadImageNamed(iconName) else {
            return .fallbackSystemImageName(VoiceInkIOSOnboardingPresentation.appIconFallbackSystemImageName)
        }

        return .assetName(iconName)
    }
}

public enum VoiceInkMacOSOnboardingPermissionKind: String, Equatable, Sendable {
    case microphone
    case audioDeviceSelection
    case accessibility
    case inputMonitoring
    case screenRecording
    case keyboardShortcut
}

public struct VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation: Equatable, Sendable {
    public let emptyStateTitle: String
    public let pickerLabel: String
    public let selectedDevicePlaceholder: String
    public let unknownDeviceName: String
    public let recommendationText: String

    public init(
        emptyStateTitle: String,
        pickerLabel: String,
        selectedDevicePlaceholder: String,
        unknownDeviceName: String,
        recommendationText: String
    ) {
        self.emptyStateTitle = emptyStateTitle
        self.pickerLabel = pickerLabel
        self.selectedDevicePlaceholder = selectedDevicePlaceholder
        self.unknownDeviceName = unknownDeviceName
        self.recommendationText = recommendationText
    }
}

public struct VoiceInkMacOSOnboardingPermissionPresentation: Identifiable, Equatable, Sendable {
    public let kind: VoiceInkMacOSOnboardingPermissionKind
    public let title: String
    public let description: String
    public let iconSystemName: String
    public let audioDeviceSelection: VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation?

    public var id: VoiceInkMacOSOnboardingPermissionKind { kind }

    public init(
        kind: VoiceInkMacOSOnboardingPermissionKind,
        title: String,
        description: String,
        iconSystemName: String,
        audioDeviceSelection: VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation? = nil
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.iconSystemName = iconSystemName
        self.audioDeviceSelection = audioDeviceSelection
    }

    public static let relaunchRequiredMessage =
        "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."

    public static let skipButtonTitle = "Skip for now"

    public static let audioDeviceSelectionPresentation = VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation(
        emptyStateTitle: "No microphones found",
        pickerLabel: "Microphone:",
        selectedDevicePlaceholder: "Select Device",
        unknownDeviceName: "Unknown Device",
        recommendationText: "For best results, using your Mac's built-in microphone is recommended."
    )

    public static let screenContextInfoHelpMessage =
        "roma-just-talk captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored."

    public static let screenContextInfoLearnMoreURLString = "https://tryvoiceink.com/docs/contextual-awareness"

    public static let all = [
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .microphone,
            title: "Microphone Access",
            description: "Enable your microphone to start speaking and converting your voice to text instantly.",
            iconSystemName: "waveform"
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .audioDeviceSelection,
            title: "Microphone Selection",
            description: "Select the audio input device you want to use with roma-just-talk.",
            iconSystemName: "headphones",
            audioDeviceSelection: audioDeviceSelectionPresentation
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .accessibility,
            title: "Accessibility Access",
            description: "Add roma-just-talk to Accessibility, then turn its switch on.",
            iconSystemName: "accessibility"
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .inputMonitoring,
            title: "Input Monitoring",
            description: "Allow roma-just-talk to detect your recording shortcut while other apps are active.",
            iconSystemName: "keyboard.badge.eye"
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .screenRecording,
            title: "Screen Context (Optional)",
            description: "Enable screen context only if you want roma-just-talk to use visible text for transcript enhancement.",
            iconSystemName: "rectangle.inset.filled.and.person.filled"
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .keyboardShortcut,
            title: "Keyboard Shortcut",
            description: "Set up a keyboard shortcut to quickly access roma-just-talk from anywhere.",
            iconSystemName: "keyboard"
        )
    ]

    public var screenContextInfoMessage: String? {
        kind == .screenRecording ? Self.screenContextInfoHelpMessage : nil
    }

    public var screenContextInfoURLString: String? {
        kind == .screenRecording ? Self.screenContextInfoLearnMoreURLString : nil
    }

    public var canSkipWhenNotGranted: Bool {
        kind != .keyboardShortcut && kind != .audioDeviceSelection
    }

    public func buttonTitle(isGranted: Bool, requiresRelaunch: Bool) -> String {
        if requiresRelaunch {
            return "Relaunch to Apply"
        }

        switch kind {
        case .keyboardShortcut:
            return isGranted ? "Continue" : "Set Shortcut"
        case .audioDeviceSelection:
            return "Continue"
        case .screenRecording:
            return isGranted ? "Continue" : "Enable"
        case .microphone, .accessibility, .inputMonitoring:
            return isGranted ? "Continue" : "Grant"
        }
    }
}
