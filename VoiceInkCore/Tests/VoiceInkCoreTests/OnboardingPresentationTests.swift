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
}
