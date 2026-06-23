import Foundation
@testable import VoiceInkCore

final class OnboardingPresentationTests: XCTestCase {
    func testIOSOnboardingAppIconFallbackPreservesSymbolName() {
        XCTAssertEqual(VoiceInkIOSOnboardingPresentation.appIconFallbackSystemImageName, "app.fill")
    }

    func testIOSAppIconPolicyExtractsBundleIconFilesFromInfoDictionary() {
        XCTAssertEqual(
            VoiceInkIOSAppIconPolicy.bundleIconFiles(from: [
                "CFBundleIcons": [
                    "CFBundlePrimaryIcon": [
                        "CFBundleIconFiles": ["AppIcon40", "AppIcon60"]
                    ]
                ]
            ]),
            ["AppIcon40", "AppIcon60"]
        )
        XCTAssertNil(VoiceInkIOSAppIconPolicy.bundleIconFiles(from: nil))
        XCTAssertNil(VoiceInkIOSAppIconPolicy.bundleIconFiles(from: [
            "CFBundleIcons": [:]
        ]))
    }

    func testIOSAppIconPolicyUsesLoadableLastBundleIcon() {
        XCTAssertEqual(
            VoiceInkIOSAppIconPolicy.source(
                iconFiles: ["AppIcon40", "AppIcon60"],
                canLoadImageNamed: { $0 == "AppIcon60" }
            ),
            .assetName("AppIcon60")
        )
    }

    func testIOSAppIconPolicyFallsBackWhenLastBundleIconIsMissing() {
        XCTAssertEqual(
            VoiceInkIOSAppIconPolicy.source(
                iconFiles: ["AppIcon40", "AppIcon60"],
                canLoadImageNamed: { $0 == "AppIcon40" }
            ),
            .fallbackSystemImageName("app.fill")
        )
    }

    func testIOSAppIconPolicyFallsBackWithoutBundleIconFiles() {
        XCTAssertEqual(
            VoiceInkIOSAppIconPolicy.source(
                iconFiles: nil,
                canLoadImageNamed: { _ in true }
            ),
            .fallbackSystemImageName("app.fill")
        )
        XCTAssertEqual(
            VoiceInkIOSAppIconPolicy.source(
                iconFiles: [],
                canLoadImageNamed: { _ in true }
            ),
            .fallbackSystemImageName("app.fill")
        )
    }

    func testIOSOnboardingStepOrderPreservesExistingFlow() {
        XCTAssertEqual(VoiceInkIOSOnboardingStep.initial, .welcome)
        XCTAssertEqual(Array(VoiceInkIOSOnboardingStep.allCases), [.welcome, .modelDownload, .ready])
        XCTAssertEqual(VoiceInkIOSOnboardingStep.welcome.nextStep, .modelDownload)
        XCTAssertEqual(VoiceInkIOSOnboardingStep.modelDownload.nextStep, .ready)
        XCTAssertNil(VoiceInkIOSOnboardingStep.ready.nextStep)

        var step = VoiceInkIOSOnboardingStep.initial
        step.advance()
        XCTAssertEqual(step, .modelDownload)
        step.advance()
        XCTAssertEqual(step, .ready)
        step.advance()
        XCTAssertEqual(step, .ready)
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

    func testMacOSWelcomeOnboardingPresentationPreservesCopyAndRoleOrder() {
        let presentation = VoiceInkMacOSOnboardingPresentation.welcome

        XCTAssertEqual(presentation.title, "Welcome to the Future of Typing")
        XCTAssertEqual(presentation.subtitle, "A New Way to Type")
        XCTAssertEqual(presentation.primaryButtonTitle, "Get Started")
        XCTAssertEqual(presentation.skipButtonTitle, "Skip Tour")
        XCTAssertEqual(
            presentation.typewriterRoles,
            [
                "Your Writing Assistant",
                "Your Vibe-Coding Assistant",
                "Works Everywhere on Mac with a click",
                "100% offline & private"
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

    func testIOSModelDownloadOnboardingPrimaryActionUsesDownloadRowState() {
        let presentation = VoiceInkIOSOnboardingPresentation.modelDownload
        let model = VoiceInkWhisperModelFiles.baseModel

        let downloadingRow = VoiceInkWhisperModelDownloadState(
            isDownloaded: false,
            progress: .simple(modelName: model.modelName, isDownloading: true, progress: 0.42)
        ).rowPresentation(for: model)
        XCTAssertEqual(
            presentation.primaryAction(for: downloadingRow),
            .waitForDownload(title: "Downloading...")
        )

        let downloadedRow = VoiceInkWhisperModelDownloadState(
            isDownloaded: true,
            progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
        ).rowPresentation(for: model)
        XCTAssertEqual(
            presentation.primaryAction(for: downloadedRow),
            .continueSetup(title: "Continue")
        )

        let idleRow = VoiceInkWhisperModelDownloadState(
            isDownloaded: false,
            progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
        ).rowPresentation(for: model)
        XCTAssertEqual(
            presentation.primaryAction(for: idleRow),
            .requestDownload(title: "Download Model (142 MB)", systemImageName: "arrow.down.circle.fill")
        )
    }

    func testIOSModelDownloadOnboardingPrimaryActionBuildsButtonStateAndRuntimeAction() {
        let waiting = VoiceInkOnboardingModelDownloadPrimaryAction.waitForDownload(title: "Downloading...")
        XCTAssertEqual(waiting.title, "Downloading...")
        XCTAssertNil(waiting.systemImageName)
        XCTAssertFalse(waiting.isEnabled)
        XCTAssertNil(waiting.runtimeAction(continueSetup: {}, requestDownload: {}))

        let continueSetup = VoiceInkOnboardingModelDownloadPrimaryAction.continueSetup(title: "Continue")
        XCTAssertEqual(continueSetup.title, "Continue")
        XCTAssertNil(continueSetup.systemImageName)
        XCTAssertTrue(continueSetup.isEnabled)

        var events: [String] = []
        let continueAction = continueSetup.runtimeAction(
            continueSetup: { events.append("continue") },
            requestDownload: { events.append("download") }
        )
        XCTAssertTrue(events.isEmpty)
        continueAction?()
        XCTAssertEqual(events, ["continue"])

        let requestDownload = VoiceInkOnboardingModelDownloadPrimaryAction.requestDownload(
            title: "Download Model (142 MB)",
            systemImageName: "arrow.down.circle.fill"
        )
        XCTAssertEqual(requestDownload.title, "Download Model (142 MB)")
        XCTAssertEqual(requestDownload.systemImageName, "arrow.down.circle.fill")
        XCTAssertTrue(requestDownload.isEnabled)

        let downloadAction = requestDownload.runtimeAction(
            continueSetup: { events.append("continue") },
            requestDownload: { events.append("download") }
        )
        downloadAction?()
        XCTAssertEqual(events, ["continue", "download"])
    }

    func testMacOSModelDownloadOnboardingPresentationPreservesCopyAndButtonPolicy() {
        let presentation = VoiceInkMacOSOnboardingPresentation.modelDownload

        XCTAssertEqual(presentation.title, "Download AI Model")
        XCTAssertEqual(presentation.subtitle, "We'll download the optimized model to get you started.")
        XCTAssertEqual(presentation.continueButtonTitle, "Continue")
        XCTAssertEqual(presentation.skipButtonTitle, "Skip for now")
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

    func testMacOSOnboardingTutorialPresentationPreservesCopyAndStepOrder() {
        let presentation = VoiceInkMacOSOnboardingPresentation.tutorial

        XCTAssertEqual(presentation.title, "Try It Out!")
        XCTAssertEqual(presentation.subtitle, "Let's test your roma-just-talk setup.")
        XCTAssertEqual(presentation.shortcutTitle, "Your Shortcut")
        XCTAssertEqual(
            presentation.instructionSteps,
            [
                "Click the text area on the right",
                "Press your shortcut key",
                "Speak something",
                "Press your shortcut key again"
            ]
        )
        XCTAssertEqual(presentation.completeButtonTitle, "Complete Setup")
        XCTAssertEqual(presentation.skipButtonTitle, "Skip for now")
        XCTAssertEqual(presentation.placeholderIconSystemName, "wand.and.stars")
        XCTAssertEqual(presentation.placeholderText, "Click here and start speaking...")
    }

    func testMacOSResetOnboardingSettingsAlertPresentationPreservesCopy() {
        let presentation = VoiceInkMacOSOnboardingPresentation.resetSettingsAlert

        XCTAssertEqual(presentation.buttonTitle, "Reset Onboarding")
        XCTAssertEqual(presentation.alertTitle, "Reset Onboarding")
        XCTAssertEqual(presentation.cancelButtonTitle, "Cancel")
        XCTAssertEqual(presentation.confirmButtonTitle, "Reset")
        XCTAssertEqual(
            presentation.message,
            "You'll see the introduction screens again the next time you launch the app."
        )
    }

    func testMacOSSetupPresentationPreservesHeaderAndStepOrder() {
        XCTAssertEqual(VoiceInkMacOSSetupPresentation.title, "Welcome to VoiceInk")
        XCTAssertEqual(VoiceInkMacOSSetupPresentation.subtitle, "Complete the setup to get started")
        XCTAssertEqual(
            VoiceInkMacOSSetupPresentation.helpText,
            "Need help? Check the Help menu for support options"
        )
        XCTAssertEqual(VoiceInkMacOSSetupPresentation.actionSystemImageName, "arrow.right")
        XCTAssertEqual(VoiceInkMacOSSetupPresentation.completedSystemImageName, "checkmark.circle.fill")
        XCTAssertEqual(VoiceInkMacOSSetupPresentation.optionalSystemImageName, "circle")
        XCTAssertEqual(VoiceInkMacOSSetupPresentation.requiredSystemImageName, "chevron.right")
        XCTAssertEqual(
            VoiceInkMacOSSetupPresentation.steps,
            [
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
        )
    }

    func testMacOSSetupPresentationPreservesActionTitlePolicy() {
        XCTAssertEqual(
            VoiceInkMacOSSetupPresentation.actionButtonTitle(
                isShortcutConfigured: false,
                isAccessibilityEnabled: false,
                hasTranscriptionModel: false
            ),
            "Configure Shortcut"
        )
        XCTAssertEqual(
            VoiceInkMacOSSetupPresentation.actionButtonTitle(
                isShortcutConfigured: true,
                isAccessibilityEnabled: false,
                hasTranscriptionModel: false
            ),
            "Enable Accessibility"
        )
        XCTAssertEqual(
            VoiceInkMacOSSetupPresentation.actionButtonTitle(
                isShortcutConfigured: true,
                isAccessibilityEnabled: true,
                hasTranscriptionModel: false
            ),
            "Download Model"
        )
        XCTAssertEqual(
            VoiceInkMacOSSetupPresentation.actionButtonTitle(
                isShortcutConfigured: true,
                isAccessibilityEnabled: true,
                hasTranscriptionModel: true
            ),
            "Get Started"
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
        XCTAssertEqual(presentations[1].audioDeviceSelection?.emptyStateTitle, "No microphones found")
        XCTAssertEqual(presentations[1].audioDeviceSelection?.pickerLabel, "Microphone:")
        XCTAssertEqual(presentations[1].audioDeviceSelection?.selectedDevicePlaceholder, "Select Device")
        XCTAssertEqual(presentations[1].audioDeviceSelection?.unknownDeviceName, "Unknown Device")
        XCTAssertEqual(
            presentations[1].audioDeviceSelection?.recommendationText,
            "For best results, using your Mac's built-in microphone is recommended."
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
        XCTAssertEqual(VoiceInkMacOSOnboardingPermissionPresentation.skipButtonTitle, "Skip for now")
        XCTAssertEqual(
            VoiceInkMacOSOnboardingPermissionPresentation.relaunchRequiredMessage,
            "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."
        )
    }
}
