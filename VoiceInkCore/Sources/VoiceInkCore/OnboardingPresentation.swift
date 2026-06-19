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

public enum VoiceInkMacOSOnboardingPermissionKind: String, Equatable, Sendable {
    case microphone
    case audioDeviceSelection
    case accessibility
    case inputMonitoring
    case screenRecording
    case keyboardShortcut
}

public struct VoiceInkMacOSOnboardingPermissionPresentation: Identifiable, Equatable, Sendable {
    public let kind: VoiceInkMacOSOnboardingPermissionKind
    public let title: String
    public let description: String
    public let iconSystemName: String

    public var id: VoiceInkMacOSOnboardingPermissionKind { kind }

    public init(
        kind: VoiceInkMacOSOnboardingPermissionKind,
        title: String,
        description: String,
        iconSystemName: String
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.iconSystemName = iconSystemName
    }

    public static let relaunchRequiredMessage =
        "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."

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
            iconSystemName: "headphones"
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
