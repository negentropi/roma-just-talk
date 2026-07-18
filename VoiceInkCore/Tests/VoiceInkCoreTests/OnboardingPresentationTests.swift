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
        XCTAssertEqual(
            Array(VoiceInkIOSOnboardingStep.allCases),
            [.welcome, .microphoneSetup, .modelDownload, .keyboardSetup, .tutorial, .ready]
        )
        XCTAssertEqual(VoiceInkIOSOnboardingStep.welcome.nextStep, .microphoneSetup)
        XCTAssertEqual(VoiceInkIOSOnboardingStep.microphoneSetup.nextStep, .modelDownload)
        XCTAssertEqual(VoiceInkIOSOnboardingStep.modelDownload.nextStep, .keyboardSetup)
        XCTAssertEqual(VoiceInkIOSOnboardingStep.keyboardSetup.nextStep, .tutorial)
        XCTAssertEqual(VoiceInkIOSOnboardingStep.tutorial.nextStep, .ready)
        XCTAssertNil(VoiceInkIOSOnboardingStep.ready.nextStep)

        var step = VoiceInkIOSOnboardingStep.initial
        step.advance()
        XCTAssertEqual(step, .microphoneSetup)
        step.advance()
        XCTAssertEqual(step, .modelDownload)
        step.advance()
        XCTAssertEqual(step, .keyboardSetup)
        step.advance()
        XCTAssertEqual(step, .tutorial)
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
