import Foundation
@testable import VoiceInkCore

final class AudioSessionLifecycleStateTests: XCTestCase {
    func testIOSAudioSessionRecordingConfigurationPreservesRecordingPolicy() {
        XCTAssertEqual(
            VoiceInkIOSAudioSessionRecordingConfiguration.voiceRecording,
            VoiceInkIOSAudioSessionRecordingConfiguration(
                category: .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
        )
    }

    func testAudioSessionDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            VoiceInkAudioSessionDiagnostics.activatedForRecordingMessage,
            "Audio session activated for recording"
        )
        XCTAssertEqual(
            VoiceInkAudioSessionDiagnostics.activatedForPlaybackMessage,
            "Audio session activated for playback"
        )
        XCTAssertEqual(
            VoiceInkAudioSessionDiagnostics.activationFailedMessage(
                localizedDescription: "denied",
                code: 561_017_449
            ),
            "Audio session activation failed: denied (code: 561017449)"
        )
        XCTAssertEqual(
            VoiceInkAudioSessionDiagnostics.deactivationScheduledMessage(seconds: 30),
            "Audio session deactivation scheduled in 30 seconds"
        )
        XCTAssertEqual(
            VoiceInkAudioSessionDiagnostics.deactivatedMessage,
            "Audio session deactivated"
        )
        XCTAssertEqual(
            VoiceInkAudioSessionDiagnostics.deactivationFailedMessage(localizedDescription: "busy"),
            "Failed to deactivate audio session: busy"
        )
    }

    func testAudioSessionLifecycleStatePreservesIOSActivationAndTimeoutFlow() {
        var state = VoiceInkAudioSessionLifecycleState()

        XCTAssertFalse(state.isSessionActive)
        XCTAssertEqual(state.timeoutRemaining, 0)

        state.markActivatedForRecording()
        XCTAssertTrue(state.isSessionActive)
        XCTAssertEqual(state.timeoutRemaining, 0)

        XCTAssertEqual(state.scheduleDeactivation(timeoutSeconds: 90), .delayed(90))
        XCTAssertTrue(state.isSessionActive)
        XCTAssertEqual(state.timeoutRemaining, 90)

        XCTAssertEqual(state.advanceCountdown(), .delayed(89))
        XCTAssertEqual(state.timeoutRemaining, 89)

        state.cancelScheduledDeactivation()
        XCTAssertTrue(state.isSessionActive)
        XCTAssertEqual(state.timeoutRemaining, 0)

        XCTAssertEqual(state.scheduleDeactivation(timeoutSeconds: 0), .immediate)
        XCTAssertEqual(state.timeoutRemaining, 0)

        state.markDeactivated()
        XCTAssertFalse(state.isSessionActive)
        XCTAssertEqual(state.timeoutRemaining, 0)
    }

    func testAudioSessionLifecycleStateCancelsPendingDeactivationForPlayback() {
        var state = VoiceInkAudioSessionLifecycleState(isSessionActive: true)

        XCTAssertEqual(state.scheduleDeactivation(timeoutSeconds: 90), .delayed(90))
        XCTAssertEqual(state.timeoutRemaining, 90)

        state.markActivatedForPlayback()

        XCTAssertTrue(state.isSessionActive)
        XCTAssertEqual(state.timeoutRemaining, 0)
    }

    func testAudioSessionLifecycleStatePlansPlaybackActivationSideEffects() {
        var activeState = VoiceInkAudioSessionLifecycleState(isSessionActive: true)
        XCTAssertEqual(activeState.scheduleDeactivation(timeoutSeconds: 90), .delayed(90))

        XCTAssertEqual(
            activeState.beginPlaybackActivation(),
            VoiceInkAudioSessionPlaybackActivationPlan(
                shouldCancelScheduledDeactivation: true,
                shouldDeactivateCurrentSession: true
            )
        )
        XCTAssertEqual(activeState.timeoutRemaining, 0)
        XCTAssertTrue(activeState.isSessionActive)

        var inactiveState = VoiceInkAudioSessionLifecycleState()
        XCTAssertEqual(
            inactiveState.beginPlaybackActivation(),
            VoiceInkAudioSessionPlaybackActivationPlan(
                shouldCancelScheduledDeactivation: true,
                shouldDeactivateCurrentSession: false
            )
        )
        XCTAssertFalse(inactiveState.isSessionActive)
    }

    func testAudioSessionLifecycleStatePlansImmediateDeactivationSideEffects() {
        var activeState = VoiceInkAudioSessionLifecycleState(isSessionActive: true, timeoutRemaining: 12)

        XCTAssertEqual(
            activeState.beginImmediateDeactivation(),
            VoiceInkAudioSessionImmediateDeactivationPlan(
                shouldCancelScheduledDeactivation: true,
                shouldDeactivateSession: true
            )
        )
        XCTAssertEqual(activeState.timeoutRemaining, 0)
        XCTAssertTrue(activeState.isSessionActive)

        var inactiveState = VoiceInkAudioSessionLifecycleState(isSessionActive: false, timeoutRemaining: 12)
        XCTAssertEqual(
            inactiveState.beginImmediateDeactivation(),
            VoiceInkAudioSessionImmediateDeactivationPlan(
                shouldCancelScheduledDeactivation: true,
                shouldDeactivateSession: false
            )
        )
        XCTAssertEqual(inactiveState.timeoutRemaining, 0)
        XCTAssertFalse(inactiveState.isSessionActive)
    }

    func testAudioSessionLifecycleStateRequestsDeactivationWhenCountdownExpires() {
        var state = VoiceInkAudioSessionLifecycleState(isSessionActive: true, timeoutRemaining: 1)

        XCTAssertEqual(state.advanceCountdown(), .immediate)
        XCTAssertEqual(state.timeoutRemaining, 0)
        XCTAssertTrue(state.isSessionActive)
    }

    func testAudioSessionLifecycleStateReturnsShellExecutionPlans() {
        var state = VoiceInkAudioSessionLifecycleState(isSessionActive: true)

        XCTAssertEqual(
            state.scheduleDeactivationExecution(timeoutSeconds: 90),
            .runCountdownTimer
        )
        XCTAssertEqual(state.timeoutRemaining, 90)

        state = VoiceInkAudioSessionLifecycleState(isSessionActive: true)
        XCTAssertEqual(
            state.scheduleDeactivationExecution(timeoutSeconds: 0),
            .deactivateSession
        )
        XCTAssertEqual(state.timeoutRemaining, 0)

        state = VoiceInkAudioSessionLifecycleState(isSessionActive: true, timeoutRemaining: 1)
        XCTAssertEqual(state.advanceCountdownExecution(), .deactivateSession)
        XCTAssertEqual(state.timeoutRemaining, 0)
    }
}
