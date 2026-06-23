import Foundation
@testable import VoiceInkCore

final class PermissionPresentationTests: XCTestCase {
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
        XCTAssertEqual(state.consumePoll(), .continuePolling)
        XCTAssertEqual(state.pollsRemaining, 1)
        XCTAssertEqual(state.consumePoll(), .stopPolling)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.consumePoll(), .stopPolling)

        let negativeState = VoiceInkMacOSPermissionPollingState(pollsRemaining: -1)
        XCTAssertFalse(negativeState.isActive)
        XCTAssertEqual(negativeState.pollsRemaining, 0)
    }
}
