import Foundation
import VoiceInkCore

final class CursorCompanionPolicyTests: XCTestCase {
    func testCompanionAppearsOnlyAfterMicrophoneAudioArrives() {
        var phase = VoiceInkCursorCompanionPhase.hidden
        var visited: [VoiceInkCursorCompanionPhase] = []
        for event: VoiceInkCursorCompanionEvent in [.recordingStarted, .audioReceived, .animationFinished, .recordingEnded, .animationFinished] {
            phase = VoiceInkCursorCompanionPolicy.next(phase, on: event)
            visited.append(phase)
        }

        XCTAssertEqual(visited, [.awaitingAudio, .arriving, .listening, .leaving, .hidden])
        XCTAssertEqual(visited.map(\.isVisible), [false, true, true, true, false])
    }

    func testSilentMicrophoneShowsStalledUntilAudioRecoversOrRecordingEnds() {
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.awaitingAudio, on: .audioStalled), .stalled)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.listening, on: .audioStalled), .stalled)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.stalled, on: .animationFinished), .stalled)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.stalled, on: .audioReceived), .arriving)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.stalled, on: .recordingEnded), .leaving)
        XCTAssertTrue(VoiceInkCursorCompanionPhase.stalled.isVisible)
    }

    func testRecordingThatEndsBeforeAudioArrivesShowsNothing() {
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.awaitingAudio, on: .recordingEnded), .hidden)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.arriving, on: .recordingEnded), .leaving)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.leaving, on: .recordingStarted), .awaitingAudio)
    }

    func testStartFailureWinsFromEveryPhaseAndClearsAfterItsAnimation() {
        for phase: VoiceInkCursorCompanionPhase in [.hidden, .awaitingAudio, .arriving, .listening, .leaving, .failed, .stalled] {
            XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(phase, on: .startFailed), .failed)
        }
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.failed, on: .animationFinished), .hidden)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.failed, on: .recordingStarted), .awaitingAudio)
    }

    func testIrrelevantEventsKeepPhase() {
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.hidden, on: .recordingEnded), .hidden)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.hidden, on: .audioReceived), .hidden)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.hidden, on: .animationFinished), .hidden)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.listening, on: .animationFinished), .listening)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.listening, on: .recordingStarted), .listening)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.listening, on: .audioReceived), .listening)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.next(.failed, on: .recordingEnded), .failed)
    }

    func testCaptureFlowMonitorReportsFirstAudioStallAndRecovery() {
        var monitor = VoiceInkCaptureFlowMonitor(count: 40, now: 10)

        XCTAssertNil(monitor.observe(count: 40, now: 10.5))
        XCTAssertEqual(monitor.observe(count: 41, now: 10.6), .audioReceived)
        XCTAssertNil(monitor.observe(count: 52, now: 11.0))
        XCTAssertNil(monitor.observe(count: 52, now: 12.9))
        XCTAssertEqual(monitor.observe(count: 52, now: 13.0), .audioStalled)
        XCTAssertNil(monitor.observe(count: 52, now: 20.0))
        XCTAssertEqual(monitor.observe(count: 53, now: 20.1), .audioReceived)
    }

    func testCaptureFlowMonitorReportsMicrophoneThatNeverDelivers() {
        var monitor = VoiceInkCaptureFlowMonitor(count: 0, now: 0)

        XCTAssertNil(monitor.observe(count: 0, now: 1.9))
        XCTAssertEqual(monitor.observe(count: 0, now: 2.0), .audioStalled)
    }

    func testRecordingStateTransitionsMapToCompanionEvents() {
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.event(from: .starting, to: .recording), .recordingStarted)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.event(from: .idle, to: .recording), .recordingStarted)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.event(from: .recording, to: .transcribing), .recordingEnded)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.event(from: .recording, to: .idle), .recordingEnded)
        XCTAssertNil(VoiceInkCursorCompanionPolicy.event(from: .idle, to: .starting))
        XCTAssertNil(VoiceInkCursorCompanionPolicy.event(from: .starting, to: .idle))
        XCTAssertNil(VoiceInkCursorCompanionPolicy.event(from: .recording, to: .recording))
        XCTAssertNil(VoiceInkCursorCompanionPolicy.event(from: .transcribing, to: .idle))
    }

    func testOnlyAnimatedPhasesHaveDurations() {
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.duration(of: .arriving), 1.4)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.duration(of: .leaving), 0.35)
        XCTAssertEqual(VoiceInkCursorCompanionPolicy.duration(of: .failed), 2.6)
        XCTAssertNil(VoiceInkCursorCompanionPolicy.duration(of: .hidden))
        XCTAssertNil(VoiceInkCursorCompanionPolicy.duration(of: .awaitingAudio))
        XCTAssertNil(VoiceInkCursorCompanionPolicy.duration(of: .listening))
        XCTAssertNil(VoiceInkCursorCompanionPolicy.duration(of: .stalled))
    }

    func testPreferenceDefaultsToCartoonRoundTripsAndIgnoresUnknownValues() {
        let suiteName = "VoiceInkCore.CursorCompanionPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(VoiceInkCursorCompanionPreference.style(from: defaults), .cartoon)

        VoiceInkCursorCompanionPreference.save(.anime, to: defaults)
        XCTAssertEqual(defaults.string(forKey: "CursorCompanionStyle"), "anime")
        XCTAssertEqual(VoiceInkCursorCompanionPreference.style(from: defaults), .anime)

        VoiceInkCursorCompanionPreference.save(.none, to: defaults)
        XCTAssertEqual(VoiceInkCursorCompanionPreference.style(from: defaults), .none)

        defaults.set("sparkles", forKey: "CursorCompanionStyle")
        XCTAssertEqual(VoiceInkCursorCompanionPreference.style(from: defaults), .cartoon)
    }

    func testStylesPresentInPickerOrderWithNames() {
        XCTAssertEqual(
            VoiceInkCursorCompanionStyle.allCases.map(\.displayName),
            ["Cartoon", "Storybook", "Anime", "None"]
        )
    }
}
