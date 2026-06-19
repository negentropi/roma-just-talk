import Foundation
@testable import VoiceInkCore

final class OnboardingPresentationTests: XCTestCase {
    func testIOSOnboardingAppIconFallbackPreservesSymbolName() {
        XCTAssertEqual(VoiceInkIOSOnboardingPresentation.appIconFallbackSystemImageName, "app.fill")
    }

    func testIOSWelcomeOnboardingPresentationPreservesCopyAndFeatureOrder() {
        let presentation = VoiceInkIOSOnboardingPresentation.welcome

        XCTAssertEqual(presentation.title, "Welcome to roma just talk")
        XCTAssertEqual(presentation.subtitle, "Transform your thoughts into text effortlessly.")
        XCTAssertEqual(presentation.primaryButtonTitle, "Get Started")
        XCTAssertEqual(
            presentation.features,
            [
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
            ]
        )
    }

    func testIOSModelDownloadOnboardingPresentationPreservesCopy() {
        let presentation = VoiceInkIOSOnboardingPresentation.modelDownload

        XCTAssertEqual(presentation.iconSystemName, "cpu")
        XCTAssertEqual(presentation.title, "Offline Transcription")
        XCTAssertEqual(
            presentation.subtitle,
            "Download a local model to transcribe audio even without an internet connection."
        )
        XCTAssertEqual(presentation.continueButtonTitle, "Continue")
    }

    func testMacOSModelDownloadOnboardingPresentationPreservesCopyAndButtonPolicy() {
        let presentation = VoiceInkMacOSOnboardingPresentation.modelDownload

        XCTAssertEqual(presentation.title, "Download AI Model")
        XCTAssertEqual(presentation.subtitle, "We'll download the optimized model to get you started.")
        XCTAssertEqual(presentation.continueButtonTitle, "Continue")
        XCTAssertEqual(presentation.downloadingButtonTitle, "Downloading...")
        XCTAssertEqual(presentation.setAsDefaultButtonTitle, "Set as Default")
        XCTAssertEqual(presentation.downloadButtonTitle, "Download Model")
        XCTAssertEqual(presentation.speedLabel, "Speed")
        XCTAssertEqual(presentation.accuracyLabel, "Accuracy")
        XCTAssertEqual(presentation.ramLabel, "RAM")
        XCTAssertEqual(
            presentation.buttonTitle(isModelSet: true, isDownloading: true, isModelDownloaded: true),
            "Continue"
        )
        XCTAssertEqual(
            presentation.buttonTitle(isModelSet: false, isDownloading: true, isModelDownloaded: true),
            "Downloading..."
        )
        XCTAssertEqual(
            presentation.buttonTitle(isModelSet: false, isDownloading: false, isModelDownloaded: true),
            "Set as Default"
        )
        XCTAssertEqual(
            presentation.buttonTitle(isModelSet: false, isDownloading: false, isModelDownloaded: false),
            "Download Model"
        )
    }

    func testIOSReadyOnboardingPresentationPreservesCopyAndStepOrder() {
        let presentation = VoiceInkIOSOnboardingPresentation.ready

        XCTAssertEqual(presentation.iconSystemName, "checkmark.circle.fill")
        XCTAssertEqual(presentation.title, "You're All Set!")
        XCTAssertEqual(presentation.subtitle, "Start recording your thoughts and ideas.")
        XCTAssertEqual(presentation.primaryButtonTitle, "Start Using roma just talk")
        XCTAssertEqual(
            presentation.steps,
            [
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
            ]
        )
    }

    func testMacOSOnboardingPermissionPresentationPreservesStepOrderAndCopy() {
        let presentations = VoiceInkMacOSOnboardingPermissionPresentation.all

        XCTAssertEqual(
            presentations.map(\.kind),
            [.microphone, .audioDeviceSelection, .accessibility, .inputMonitoring, .screenRecording, .keyboardShortcut]
        )
        XCTAssertEqual(presentations[0].title, "Microphone Access")
        XCTAssertEqual(
            presentations[0].description,
            "Enable your microphone to start speaking and converting your voice to text instantly."
        )
        XCTAssertEqual(presentations[0].iconSystemName, "waveform")
        XCTAssertEqual(presentations[1].title, "Microphone Selection")
        XCTAssertEqual(
            presentations[1].description,
            "Select the audio input device you want to use with roma-just-talk."
        )
        XCTAssertEqual(presentations[2].title, "Accessibility Access")
        XCTAssertEqual(presentations[3].title, "Input Monitoring")
        XCTAssertEqual(presentations[4].title, "Screen Context (Optional)")
        XCTAssertEqual(
            presentations[4].description,
            "Enable screen context only if you want roma-just-talk to use visible text for transcript enhancement."
        )
        XCTAssertEqual(
            presentations[4].screenContextInfoMessage,
            VoiceInkMacOSOnboardingPermissionPresentation.screenContextInfoHelpMessage
        )
        XCTAssertEqual(
            presentations[4].screenContextInfoURLString,
            "https://tryvoiceink.com/docs/contextual-awareness"
        )
        XCTAssertEqual(presentations[5].title, "Keyboard Shortcut")
        XCTAssertEqual(presentations[5].iconSystemName, "keyboard")
    }

    func testMacOSOnboardingPermissionButtonTitlesAndSkipPolicy() {
        let presentations = VoiceInkMacOSOnboardingPermissionPresentation.all
        let microphone = presentations[0]
        let audioDeviceSelection = presentations[1]
        let screenRecording = presentations[4]
        let keyboardShortcut = presentations[5]

        XCTAssertEqual(microphone.buttonTitle(isGranted: false, requiresRelaunch: false), "Grant")
        XCTAssertEqual(microphone.buttonTitle(isGranted: true, requiresRelaunch: false), "Continue")
        XCTAssertEqual(
            microphone.buttonTitle(isGranted: true, requiresRelaunch: true),
            "Relaunch to Apply"
        )
        XCTAssertEqual(audioDeviceSelection.buttonTitle(isGranted: false, requiresRelaunch: false), "Continue")
        XCTAssertEqual(screenRecording.buttonTitle(isGranted: false, requiresRelaunch: false), "Enable")
        XCTAssertEqual(keyboardShortcut.buttonTitle(isGranted: false, requiresRelaunch: false), "Set Shortcut")

        XCTAssertTrue(microphone.canSkipWhenNotGranted)
        XCTAssertTrue(screenRecording.canSkipWhenNotGranted)
        XCTAssertFalse(audioDeviceSelection.canSkipWhenNotGranted)
        XCTAssertFalse(keyboardShortcut.canSkipWhenNotGranted)
        XCTAssertEqual(
            VoiceInkMacOSOnboardingPermissionPresentation.relaunchRequiredMessage,
            "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."
        )
    }
}
