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

    func testIOSModelDownloadOnboardingDefaultModelUsesSharedBaseModel() {
        XCTAssertEqual(
            VoiceInkIOSOnboardingPresentation.defaultDownloadModel,
            VoiceInkWhisperModelFiles.baseModel
        )
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

    func testIOSModelDownloadOnboardingSnapshotBuildsDefaultModelRowAndActions() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.OnboardingModelDownloadSnapshotTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkIOSOnboardingPresentation.defaultDownloadModel
        var trackingState = VoiceInkWhisperModelSimpleDownloadTrackingState()

        let idleSnapshot = VoiceInkWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState
        ).iOSOnboardingModelDownloadSnapshot()

        XCTAssertEqual(idleSnapshot.onboardingPresentation, VoiceInkIOSOnboardingPresentation.modelDownload)
        XCTAssertEqual(idleSnapshot.model, model)
        XCTAssertEqual(idleSnapshot.row.model, model)
        XCTAssertEqual(idleSnapshot.rowPresentation.action, .download)
        XCTAssertEqual(
            idleSnapshot.primaryAction,
            .requestDownload(title: "Download Model (142 MB)", systemImageName: "arrow.down.circle.fill")
        )
        XCTAssertEqual(idleSnapshot.downloadConfirmation, .download(for: model))

        var events: [String] = []
        idleSnapshot.confirmedDownloadRuntimeAction { events.append("download") }?()
        XCTAssertEqual(events, ["download"])

        XCTAssertTrue(trackingState.startDownload(for: model))
        trackingState.updateProgress(0.42, for: model)
        let downloadingSnapshot = VoiceInkWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState
        ).iOSOnboardingModelDownloadSnapshot()

        XCTAssertEqual(downloadingSnapshot.rowPresentation.action, .downloading)
        XCTAssertEqual(downloadingSnapshot.primaryAction, .waitForDownload(title: "Downloading..."))
        XCTAssertNil(downloadingSnapshot.confirmedDownloadRuntimeAction { events.append("download") })

        try Data().write(to: model.fileURL(in: modelsDirectory))
        trackingState.finishDownload(for: model)
        let downloadedSnapshot = VoiceInkWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState
        ).iOSOnboardingModelDownloadSnapshot()

        XCTAssertEqual(downloadedSnapshot.rowPresentation.action, .downloaded)
        XCTAssertEqual(downloadedSnapshot.primaryAction, .continueSetup(title: "Continue"))
        XCTAssertNil(downloadedSnapshot.confirmedDownloadRuntimeAction { events.append("download") })
    }

    func testMacOSModelDownloadOnboardingPresentationPreservesCopyAndButtonPolicy() {
        let presentation = VoiceInkMacOSOnboardingPresentation.modelDownload

        XCTAssertEqual(presentation.title, "Download AI Model")
        XCTAssertEqual(
            presentation.subtitle,
            "Your default model starts downloading automatically. You can wait here, choose another model, or skip setup for now."
        )
        XCTAssertEqual(presentation.nextButtonTitle, "Next")
        XCTAssertEqual(presentation.skipButtonTitle, "Skip for now")
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

    func testMacOSSetupStepCompletionPolicyPreservesMacOSChecks() {
        let steps = VoiceInkMacOSSetupPresentation.steps
        XCTAssertEqual(steps.map(\.id), ["shortcut", "accessibility", "screenContext", "modelDownload"])
        XCTAssertEqual(
            steps.map {
                $0.isCompleted(
                    isShortcutConfigured: true,
                    isAccessibilityEnabled: false,
                    isScreenRecordingEnabled: false,
                    hasCurrentTranscriptionModel: false
                )
            },
            [true, false, false, false]
        )
        XCTAssertEqual(
            steps.map {
                $0.isCompleted(
                    isShortcutConfigured: false,
                    isAccessibilityEnabled: true,
                    isScreenRecordingEnabled: false,
                    hasCurrentTranscriptionModel: false
                )
            },
            [false, true, false, false]
        )
        XCTAssertEqual(
            steps.map {
                $0.isCompleted(
                    isShortcutConfigured: false,
                    isAccessibilityEnabled: false,
                    isScreenRecordingEnabled: true,
                    hasCurrentTranscriptionModel: false
                )
            },
            [false, false, true, false]
        )
        XCTAssertEqual(
            steps.map {
                $0.isCompleted(
                    isShortcutConfigured: false,
                    isAccessibilityEnabled: false,
                    isScreenRecordingEnabled: false,
                    hasCurrentTranscriptionModel: true
                )
            },
            [false, false, false, true]
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
        XCTAssertTrue(keyboardShortcut.canSkipWhenNotGranted)
        XCTAssertFalse(audioDeviceSelection.canSkipWhenNotGranted)
        XCTAssertEqual(VoiceInkMacOSOnboardingPermissionPresentation.skipButtonTitle, "Skip for now")
        XCTAssertEqual(
            VoiceInkMacOSOnboardingPermissionPresentation.relaunchRequiredMessage,
            "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."
        )
    }

    func testMacOSPermissionSettingsPresentationPreservesHeaderAndStatusIcons() {
        XCTAssertEqual(VoiceInkMacOSPermissionSettingsPresentation.headerIconSystemName, "shield.lefthalf.filled")
        XCTAssertEqual(VoiceInkMacOSPermissionSettingsPresentation.headerTitle, "App Permissions")
        XCTAssertEqual(
            VoiceInkMacOSPermissionSettingsPresentation.headerDescription,
            "Microphone and shortcut access are needed for recording. Screen context is optional."
        )
        XCTAssertEqual(VoiceInkMacOSPermissionSettingsPresentation.refreshButtonSystemImageName, "arrow.clockwise")
        XCTAssertEqual(VoiceInkMacOSPermissionSettingsPresentation.grantedStatusSystemImageName, "checkmark.seal.fill")
        XCTAssertEqual(VoiceInkMacOSPermissionSettingsPresentation.deniedStatusSystemImageName, "xmark.seal.fill")
        XCTAssertEqual(VoiceInkMacOSPermissionSettingsPresentation.actionSystemImageName, "arrow.right")
        XCTAssertEqual(
            VoiceInkMacOSPermissionSettingsPresentation.relaunchRequiredMessage,
            "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."
        )
    }

    func testMacOSPermissionSettingsCardsPreserveCopyAndButtonPolicy() {
        let inputMonitoring = VoiceInkMacOSPermissionSettingsPresentation.inputMonitoringCard
        let microphone = VoiceInkMacOSPermissionSettingsPresentation.microphoneCard
        let accessibility = VoiceInkMacOSPermissionSettingsPresentation.accessibilityCard
        let screenContext = VoiceInkMacOSPermissionSettingsPresentation.screenContextCard

        XCTAssertEqual(inputMonitoring.kind, .inputMonitoring)
        XCTAssertEqual(inputMonitoring.iconSystemName, "keyboard.badge.eye")
        XCTAssertEqual(inputMonitoring.grantedIconSystemName, "keyboard.badge.eye.fill")
        XCTAssertEqual(inputMonitoring.title, "Input Monitoring Access")
        XCTAssertEqual(inputMonitoring.description, "Allow roma-just-talk to listen for your recording hotkey globally")
        XCTAssertEqual(inputMonitoring.buttonTitle(requiresRelaunch: false), "Grant")
        XCTAssertEqual(inputMonitoring.buttonTitle(requiresRelaunch: true), "Relaunch to Apply")
        XCTAssertEqual(
            inputMonitoring.infoTipMessage,
            "roma-just-talk uses Input Monitoring only to detect your configured recording shortcut while other apps are active."
        )

        XCTAssertEqual(microphone.kind, .microphone)
        XCTAssertEqual(microphone.iconSystemName, "mic")
        XCTAssertEqual(microphone.title, "Microphone Access")
        XCTAssertEqual(microphone.description, "Allow roma-just-talk to record your voice for transcription")
        XCTAssertEqual(microphone.buttonTitle(requiresRelaunch: true), "Grant")

        XCTAssertEqual(accessibility.kind, .accessibility)
        XCTAssertEqual(accessibility.iconSystemName, "hand.raised")
        XCTAssertEqual(accessibility.title, "Accessibility Access")
        XCTAssertEqual(accessibility.description, "Add roma-just-talk to Accessibility, then turn its switch on")
        XCTAssertEqual(
            accessibility.infoTipMessage,
            "macOS requires you to enable the roma-just-talk switch yourself. Dragging the app into the list only adds it when it is missing."
        )

        XCTAssertEqual(screenContext.kind, .screenContext)
        XCTAssertEqual(screenContext.iconSystemName, "rectangle.on.rectangle")
        XCTAssertEqual(screenContext.title, "Screen Context (Optional)")
        XCTAssertEqual(screenContext.description, "Use visible screen text to improve transcript enhancement when you choose.")
        XCTAssertEqual(screenContext.buttonTitle(requiresRelaunch: false), "Enable")
        XCTAssertEqual(screenContext.buttonTitle(requiresRelaunch: true), "Relaunch to Apply")
        XCTAssertEqual(
            screenContext.infoTipMessage,
            "roma-just-talk captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored."
        )
        XCTAssertEqual(screenContext.infoTipURLString, "https://tryvoiceink.com/docs/contextual-awareness")
    }

    func testMacOSDashboardAccessibilityCalloutPreservesMetricsCopy() {
        let callout = VoiceInkMacOSPermissionSettingsPresentation.dashboardAccessibilityCallout

        XCTAssertEqual(callout.kind, .accessibility)
        XCTAssertEqual(callout.iconSystemName, "hand.raised")
        XCTAssertEqual(callout.title, "Accessibility Access")
        XCTAssertEqual(callout.description, "VoiceInk needs Accessibility permission to work reliably across your entire Mac")
        XCTAssertEqual(callout.buttonTitle(requiresRelaunch: true), "Open System Settings")
        XCTAssertEqual(callout.infoTipMessage, "VoiceInk uses Accessibility to work reliably across apps.")
    }

    func testMacOSPermissionTimingPolicyPreservesPollingAndRelaunchDelays() {
        XCTAssertEqual(VoiceInkMacOSPermissionTimingPolicy.pollingInterval, 0.5)
        XCTAssertEqual(VoiceInkMacOSPermissionTimingPolicy.refreshPollLimit, 120)
        XCTAssertEqual(VoiceInkMacOSPermissionTimingPolicy.relaunchRequiredDelay, 6.0)
        XCTAssertEqual(VoiceInkMacOSPermissionTimingPolicy.manualRefreshAnimationResetDelay, 0.5)
        XCTAssertEqual(VoiceInkMacOSPermissionTimingPolicy.floatingAuthorizationPanelDelay, 0.25)
        XCTAssertEqual(VoiceInkMacOSPermissionTimingPolicy.openPermissionsGrantMicrophoneDelay, 0.2)
    }

    func testMacOSPermissionPollingStateStopsAfterConfiguredPollLimit() {
        var state = VoiceInkMacOSPermissionPollingState.started(limit: 2)

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.pollsRemaining, 2)
        XCTAssertFalse(state.consumePollAndShouldStop())
        XCTAssertEqual(state.pollsRemaining, 1)
        XCTAssertTrue(state.consumePollAndShouldStop())
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.consumePollAndShouldStop())

        let negativeState = VoiceInkMacOSPermissionPollingState(pollsRemaining: -1)
        XCTAssertFalse(negativeState.isActive)
        XCTAssertEqual(negativeState.pollsRemaining, 0)
    }

    func testMacOSOnboardingStageResumeFlagsPreserveExistingFlow() {
        XCTAssertFalse(VoiceInkMacOSOnboardingStage.welcome.resumesPermissionsView)
        XCTAssertFalse(VoiceInkMacOSOnboardingStage.welcome.resumesModelDownload)
        XCTAssertFalse(VoiceInkMacOSOnboardingStage.welcome.resumesTutorial)

        XCTAssertTrue(VoiceInkMacOSOnboardingStage.permissions.resumesPermissionsView)
        XCTAssertFalse(VoiceInkMacOSOnboardingStage.permissions.resumesModelDownload)
        XCTAssertFalse(VoiceInkMacOSOnboardingStage.permissions.resumesTutorial)

        XCTAssertTrue(VoiceInkMacOSOnboardingStage.modelDownload.resumesPermissionsView)
        XCTAssertTrue(VoiceInkMacOSOnboardingStage.modelDownload.resumesModelDownload)
        XCTAssertFalse(VoiceInkMacOSOnboardingStage.modelDownload.resumesTutorial)

        XCTAssertTrue(VoiceInkMacOSOnboardingStage.tutorial.resumesPermissionsView)
        XCTAssertTrue(VoiceInkMacOSOnboardingStage.tutorial.resumesModelDownload)
        XCTAssertTrue(VoiceInkMacOSOnboardingStage.tutorial.resumesTutorial)
    }

    func testMacOSOnboardingProgressPersistedRawValuesStayStable() {
        XCTAssertEqual(VoiceInkMacOSOnboardingStage.welcome.rawValue, "welcome")
        XCTAssertEqual(VoiceInkMacOSOnboardingStage.permissions.rawValue, "permissions")
        XCTAssertEqual(VoiceInkMacOSOnboardingStage.modelDownload.rawValue, "modelDownload")
        XCTAssertEqual(VoiceInkMacOSOnboardingStage.tutorial.rawValue, "tutorial")

        XCTAssertEqual(VoiceInkMacOSOnboardingPermissionKind.microphone.rawValue, "microphone")
        XCTAssertEqual(VoiceInkMacOSOnboardingPermissionKind.audioDeviceSelection.rawValue, "audioDeviceSelection")
        XCTAssertEqual(VoiceInkMacOSOnboardingPermissionKind.accessibility.rawValue, "accessibility")
        XCTAssertEqual(VoiceInkMacOSOnboardingPermissionKind.inputMonitoring.rawValue, "inputMonitoring")
        XCTAssertEqual(VoiceInkMacOSOnboardingPermissionKind.screenRecording.rawValue, "screenRecording")
        XCTAssertEqual(VoiceInkMacOSOnboardingPermissionKind.keyboardShortcut.rawValue, "keyboardShortcut")
    }

    func testMacOSOnboardingProgressStoreDefaultsAndIgnoresMalformedValues() {
        let suiteName = "VoiceInkCore.OnboardingPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults), .welcome)
        XCTAssertNil(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults))

        defaults.set("unknown", forKey: "macOSOnboardingStage")
        defaults.set("unknown", forKey: "macOSOnboardingPermissionKind")

        XCTAssertEqual(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults), .welcome)
        XCTAssertNil(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults))
    }

    func testMacOSOnboardingProgressStoreRoundTripsStageAndPermissionKind() {
        let suiteName = "VoiceInkCore.OnboardingPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        VoiceInkMacOSOnboardingProgressStore.saveStage(.modelDownload, in: defaults)
        VoiceInkMacOSOnboardingProgressStore.savePermissionKind(.screenRecording, in: defaults)

        XCTAssertEqual(defaults.string(forKey: "macOSOnboardingStage"), "modelDownload")
        XCTAssertEqual(defaults.string(forKey: "macOSOnboardingPermissionKind"), "screenRecording")
        XCTAssertEqual(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults), .modelDownload)
        XCTAssertEqual(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults), .screenRecording)
    }

    func testMacOSOnboardingProgressStoreResetClearsStageAndPermissionKind() {
        let suiteName = "VoiceInkCore.OnboardingPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        VoiceInkMacOSOnboardingProgressStore.saveStage(.tutorial, in: defaults)
        VoiceInkMacOSOnboardingProgressStore.savePermissionKind(.keyboardShortcut, in: defaults)
        VoiceInkMacOSOnboardingProgressStore.reset(in: defaults)

        XCTAssertNil(defaults.string(forKey: "macOSOnboardingStage"))
        XCTAssertNil(defaults.string(forKey: "macOSOnboardingPermissionKind"))
        XCTAssertEqual(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults), .welcome)
        XCTAssertNil(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults))
    }
}
