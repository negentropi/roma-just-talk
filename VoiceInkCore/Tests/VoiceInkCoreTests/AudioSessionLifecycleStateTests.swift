import Foundation
@testable import VoiceInkCore

final class AudioSessionLifecycleStateTests: XCTestCase {
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
