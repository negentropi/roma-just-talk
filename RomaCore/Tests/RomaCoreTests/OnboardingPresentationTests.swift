import Foundation
@testable import RomaCore

final class OnboardingPresentationTests: XCTestCase {
    func testIOSOnboardingAppIconFallbackPreservesSymbolName() {
        XCTAssertEqual(RomaIOSOnboardingPresentation.appIconFallbackSystemImageName, "app.fill")
    }

    func testIOSAppIconPolicyExtractsBundleIconFilesFromInfoDictionary() {
        XCTAssertEqual(
            RomaIOSAppIconPolicy.bundleIconFiles(from: [
                "CFBundleIcons": [
                    "CFBundlePrimaryIcon": [
                        "CFBundleIconFiles": ["AppIcon40", "AppIcon60"]
                    ]
                ]
            ]),
            ["AppIcon40", "AppIcon60"]
        )
        XCTAssertNil(RomaIOSAppIconPolicy.bundleIconFiles(from: nil))
        XCTAssertNil(RomaIOSAppIconPolicy.bundleIconFiles(from: [
            "CFBundleIcons": [:]
        ]))
    }

    func testIOSAppIconPolicyUsesLoadableLastBundleIcon() {
        XCTAssertEqual(
            RomaIOSAppIconPolicy.source(
                iconFiles: ["AppIcon40", "AppIcon60"],
                canLoadImageNamed: { $0 == "AppIcon60" }
            ),
            .assetName("AppIcon60")
        )
    }

    func testIOSAppIconPolicyFallsBackWhenLastBundleIconIsMissing() {
        XCTAssertEqual(
            RomaIOSAppIconPolicy.source(
                iconFiles: ["AppIcon40", "AppIcon60"],
                canLoadImageNamed: { $0 == "AppIcon40" }
            ),
            .fallbackSystemImageName("app.fill")
        )
    }

    func testIOSAppIconPolicyFallsBackWithoutBundleIconFiles() {
        XCTAssertEqual(
            RomaIOSAppIconPolicy.source(
                iconFiles: nil,
                canLoadImageNamed: { _ in true }
            ),
            .fallbackSystemImageName("app.fill")
        )
        XCTAssertEqual(
            RomaIOSAppIconPolicy.source(
                iconFiles: [],
                canLoadImageNamed: { _ in true }
            ),
            .fallbackSystemImageName("app.fill")
        )
    }

    func testIOSOnboardingStepOrderPreservesExistingFlow() {
        XCTAssertEqual(RomaIOSOnboardingStep.initial, .welcome)
        XCTAssertEqual(
            Array(RomaIOSOnboardingStep.allCases),
            [.welcome, .microphoneSetup, .modelDownload, .keyboardSetup, .tutorial, .ready]
        )
        XCTAssertEqual(RomaIOSOnboardingStep.welcome.nextStep, .microphoneSetup)
        XCTAssertEqual(RomaIOSOnboardingStep.microphoneSetup.nextStep, .modelDownload)
        XCTAssertEqual(RomaIOSOnboardingStep.modelDownload.nextStep, .keyboardSetup)
        XCTAssertEqual(RomaIOSOnboardingStep.keyboardSetup.nextStep, .tutorial)
        XCTAssertEqual(RomaIOSOnboardingStep.tutorial.nextStep, .ready)
        XCTAssertNil(RomaIOSOnboardingStep.ready.nextStep)

        var step = RomaIOSOnboardingStep.initial
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
            RomaIOSOnboardingPresentation.defaultDownloadModel,
            RomaWhisperModelFiles.baseModel
        )
    }

    func testIOSModelDownloadOnboardingPrimaryActionUsesDownloadRowState() {
        let presentation = RomaIOSOnboardingPresentation.modelDownload
        let model = RomaWhisperModelFiles.baseModel

        let downloadingRow = RomaWhisperModelDownloadState(
            isDownloaded: false,
            progress: .simple(modelName: model.modelName, isDownloading: true, progress: 0.42)
        ).rowPresentation(for: model)
        XCTAssertEqual(
            presentation.primaryAction(for: downloadingRow),
            .waitForDownload(title: "Downloading...")
        )

        let downloadedRow = RomaWhisperModelDownloadState(
            isDownloaded: true,
            progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
        ).rowPresentation(for: model)
        XCTAssertEqual(
            presentation.primaryAction(for: downloadedRow),
            .continueSetup(title: "Continue")
        )

        let idleRow = RomaWhisperModelDownloadState(
            isDownloaded: false,
            progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
        ).rowPresentation(for: model)
        XCTAssertEqual(
            presentation.primaryAction(for: idleRow),
            .requestDownload(title: "Download Model (142 MB)", systemImageName: "arrow.down.circle.fill")
        )
    }

    func testIOSModelDownloadOnboardingPrimaryActionBuildsButtonStateAndRuntimeAction() {
        let waiting = RomaOnboardingModelDownloadPrimaryAction.waitForDownload(title: "Downloading...")
        XCTAssertEqual(waiting.title, "Downloading...")
        XCTAssertNil(waiting.systemImageName)
        XCTAssertFalse(waiting.isEnabled)
        XCTAssertNil(waiting.runtimeAction(continueSetup: {}, requestDownload: {}))

        let continueSetup = RomaOnboardingModelDownloadPrimaryAction.continueSetup(title: "Continue")
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

        let requestDownload = RomaOnboardingModelDownloadPrimaryAction.requestDownload(
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
            .appendingPathComponent("RomaCore.OnboardingModelDownloadSnapshotTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try RomaWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = RomaIOSOnboardingPresentation.defaultDownloadModel
        var trackingState = RomaWhisperModelSimpleDownloadTrackingState()

        let idleSnapshot = RomaWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState
        ).iOSOnboardingModelDownloadSnapshot()

        XCTAssertEqual(idleSnapshot.onboardingPresentation, RomaIOSOnboardingPresentation.modelDownload)
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
        let downloadingSnapshot = RomaWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState
        ).iOSOnboardingModelDownloadSnapshot()

        XCTAssertEqual(downloadingSnapshot.rowPresentation.action, .downloading)
        XCTAssertEqual(downloadingSnapshot.primaryAction, .waitForDownload(title: "Downloading..."))
        XCTAssertNil(downloadingSnapshot.confirmedDownloadRuntimeAction { events.append("download") })

        try Data().write(to: model.fileURL(in: modelsDirectory))
        trackingState.finishDownload(for: model)
        let downloadedSnapshot = RomaWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState
        ).iOSOnboardingModelDownloadSnapshot()

        XCTAssertEqual(downloadedSnapshot.rowPresentation.action, .downloaded)
        XCTAssertEqual(downloadedSnapshot.primaryAction, .continueSetup(title: "Continue"))
        XCTAssertNil(downloadedSnapshot.confirmedDownloadRuntimeAction { events.append("download") })
    }

    func testMacOSSetupPresentationPreservesHeaderAndStepOrder() {
        XCTAssertEqual(RomaMacOSSetupPresentation.title, "Welcome to Roma Just Talk")
        XCTAssertEqual(RomaMacOSSetupPresentation.subtitle, "Complete the setup to get started")
        XCTAssertEqual(
            RomaMacOSSetupPresentation.helpText,
            "Need help? Check the Help menu for support options"
        )
        XCTAssertEqual(RomaMacOSSetupPresentation.actionSystemImageName, "arrow.right")
        XCTAssertEqual(RomaMacOSSetupPresentation.completedSystemImageName, "checkmark.circle.fill")
        XCTAssertEqual(RomaMacOSSetupPresentation.optionalSystemImageName, "circle")
        XCTAssertEqual(RomaMacOSSetupPresentation.requiredSystemImageName, "chevron.right")
        XCTAssertEqual(
            RomaMacOSSetupPresentation.steps,
            [
                RomaMacOSSetupStepPresentation(
                    kind: .shortcut,
                    isOptional: false,
                    iconSystemName: "command",
                    title: "Set Keyboard Shortcut",
                    description: "Use Roma Just Talk anywhere with a shortcut."
                ),
                RomaMacOSSetupStepPresentation(
                    kind: .accessibility,
                    isOptional: false,
                    iconSystemName: "hand.raised.fill",
                    title: "Enable Accessibility",
                    description: "Paste transcribed text at your cursor."
                ),
                RomaMacOSSetupStepPresentation(
                    kind: .screenContext,
                    isOptional: true,
                    iconSystemName: "video.fill",
                    title: "Screen Context (Optional)",
                    description: "Use visible text for better transcript enhancement when you choose."
                ),
                RomaMacOSSetupStepPresentation(
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
        let steps = RomaMacOSSetupPresentation.steps
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
            RomaMacOSSetupPresentation.actionButtonTitle(
                isShortcutConfigured: false,
                isAccessibilityEnabled: false,
                hasTranscriptionModel: false
            ),
            "Configure Shortcut"
        )
        XCTAssertEqual(
            RomaMacOSSetupPresentation.actionButtonTitle(
                isShortcutConfigured: true,
                isAccessibilityEnabled: false,
                hasTranscriptionModel: false
            ),
            "Enable Accessibility"
        )
        XCTAssertEqual(
            RomaMacOSSetupPresentation.actionButtonTitle(
                isShortcutConfigured: true,
                isAccessibilityEnabled: true,
                hasTranscriptionModel: false
            ),
            "Download Model"
        )
        XCTAssertEqual(
            RomaMacOSSetupPresentation.actionButtonTitle(
                isShortcutConfigured: true,
                isAccessibilityEnabled: true,
                hasTranscriptionModel: true
            ),
            "Get Started"
        )
    }

    func testMacOSOnboardingPermissionKindsStayInRuntimeOrder() {
        XCTAssertEqual(
            RomaMacOSOnboardingPermissionPresentation.all.map(\.kind),
            [.microphone, .audioDeviceSelection, .accessibility, .inputMonitoring, .screenRecording, .keyboardShortcut]
        )
    }

    func testMacOSOnboardingPermissionButtonTitlesAndSkipPolicy() {
        let presentations = RomaMacOSOnboardingPermissionPresentation.all
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
        XCTAssertEqual(RomaMacOSOnboardingPermissionPresentation.skipButtonTitle, "Skip for now")
        XCTAssertEqual(
            RomaMacOSOnboardingPermissionPresentation.relaunchRequiredMessage,
            "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."
        )
    }

    func testMacOSPermissionTimingPolicyPreservesPollingAndRelaunchDelays() {
        XCTAssertEqual(RomaMacOSPermissionTimingPolicy.pollingInterval, 0.5)
        XCTAssertEqual(RomaMacOSPermissionTimingPolicy.refreshPollLimit, 120)
        XCTAssertEqual(RomaMacOSPermissionTimingPolicy.relaunchRequiredDelay, 6.0)
        XCTAssertEqual(RomaMacOSPermissionTimingPolicy.manualRefreshAnimationResetDelay, 0.5)
        XCTAssertEqual(RomaMacOSPermissionTimingPolicy.floatingAuthorizationPanelDelay, 0.25)
        XCTAssertEqual(RomaMacOSPermissionTimingPolicy.openPermissionsGrantMicrophoneDelay, 0.2)
    }

    func testMacOSPermissionPollingStateStopsAfterConfiguredPollLimit() {
        var state = RomaMacOSPermissionPollingState.started(limit: 2)

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.pollsRemaining, 2)
        XCTAssertFalse(state.consumePollAndShouldStop())
        XCTAssertEqual(state.pollsRemaining, 1)
        XCTAssertTrue(state.consumePollAndShouldStop())
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.consumePollAndShouldStop())

        let negativeState = RomaMacOSPermissionPollingState(pollsRemaining: -1)
        XCTAssertFalse(negativeState.isActive)
        XCTAssertEqual(negativeState.pollsRemaining, 0)
    }

    func testMacOSOnboardingStageResumeFlagsPreserveExistingFlow() {
        XCTAssertFalse(RomaMacOSOnboardingStage.welcome.resumesPermissionsView)
        XCTAssertFalse(RomaMacOSOnboardingStage.welcome.resumesModelDownload)
        XCTAssertFalse(RomaMacOSOnboardingStage.welcome.resumesTutorial)

        XCTAssertTrue(RomaMacOSOnboardingStage.permissions.resumesPermissionsView)
        XCTAssertFalse(RomaMacOSOnboardingStage.permissions.resumesModelDownload)
        XCTAssertFalse(RomaMacOSOnboardingStage.permissions.resumesTutorial)

        XCTAssertTrue(RomaMacOSOnboardingStage.modelDownload.resumesPermissionsView)
        XCTAssertTrue(RomaMacOSOnboardingStage.modelDownload.resumesModelDownload)
        XCTAssertFalse(RomaMacOSOnboardingStage.modelDownload.resumesTutorial)

        XCTAssertTrue(RomaMacOSOnboardingStage.tutorial.resumesPermissionsView)
        XCTAssertTrue(RomaMacOSOnboardingStage.tutorial.resumesModelDownload)
        XCTAssertTrue(RomaMacOSOnboardingStage.tutorial.resumesTutorial)
    }

    func testMacOSOnboardingProgressPersistedRawValuesStayStable() {
        XCTAssertEqual(RomaMacOSOnboardingStage.welcome.rawValue, "welcome")
        XCTAssertEqual(RomaMacOSOnboardingStage.permissions.rawValue, "permissions")
        XCTAssertEqual(RomaMacOSOnboardingStage.modelDownload.rawValue, "modelDownload")
        XCTAssertEqual(RomaMacOSOnboardingStage.tutorial.rawValue, "tutorial")

        XCTAssertEqual(RomaMacOSOnboardingPermissionKind.microphone.rawValue, "microphone")
        XCTAssertEqual(RomaMacOSOnboardingPermissionKind.audioDeviceSelection.rawValue, "audioDeviceSelection")
        XCTAssertEqual(RomaMacOSOnboardingPermissionKind.accessibility.rawValue, "accessibility")
        XCTAssertEqual(RomaMacOSOnboardingPermissionKind.inputMonitoring.rawValue, "inputMonitoring")
        XCTAssertEqual(RomaMacOSOnboardingPermissionKind.screenRecording.rawValue, "screenRecording")
        XCTAssertEqual(RomaMacOSOnboardingPermissionKind.keyboardShortcut.rawValue, "keyboardShortcut")
    }

    func testMacOSOnboardingProgressStoreDefaultsAndIgnoresMalformedValues() {
        let suiteName = "RomaCore.OnboardingPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(RomaMacOSOnboardingProgressStore.stage(in: defaults), .welcome)
        XCTAssertNil(RomaMacOSOnboardingProgressStore.permissionKind(in: defaults))

        defaults.set("unknown", forKey: "macOSOnboardingStage")
        defaults.set("unknown", forKey: "macOSOnboardingPermissionKind")

        XCTAssertEqual(RomaMacOSOnboardingProgressStore.stage(in: defaults), .welcome)
        XCTAssertNil(RomaMacOSOnboardingProgressStore.permissionKind(in: defaults))
    }

    func testMacOSOnboardingProgressStoreRoundTripsStageAndPermissionKind() {
        let suiteName = "RomaCore.OnboardingPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RomaMacOSOnboardingProgressStore.saveStage(.modelDownload, in: defaults)
        RomaMacOSOnboardingProgressStore.savePermissionKind(.screenRecording, in: defaults)

        XCTAssertEqual(defaults.string(forKey: "macOSOnboardingStage"), "modelDownload")
        XCTAssertEqual(defaults.string(forKey: "macOSOnboardingPermissionKind"), "screenRecording")
        XCTAssertEqual(RomaMacOSOnboardingProgressStore.stage(in: defaults), .modelDownload)
        XCTAssertEqual(RomaMacOSOnboardingProgressStore.permissionKind(in: defaults), .screenRecording)
    }

    func testMacOSOnboardingProgressStoreResetClearsStageAndPermissionKind() {
        let suiteName = "RomaCore.OnboardingPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RomaMacOSOnboardingProgressStore.saveStage(.tutorial, in: defaults)
        RomaMacOSOnboardingProgressStore.savePermissionKind(.keyboardShortcut, in: defaults)
        RomaMacOSOnboardingProgressStore.reset(in: defaults)

        XCTAssertNil(defaults.string(forKey: "macOSOnboardingStage"))
        XCTAssertNil(defaults.string(forKey: "macOSOnboardingPermissionKind"))
        XCTAssertEqual(RomaMacOSOnboardingProgressStore.stage(in: defaults), .welcome)
        XCTAssertNil(RomaMacOSOnboardingProgressStore.permissionKind(in: defaults))
    }
}
