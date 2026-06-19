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
