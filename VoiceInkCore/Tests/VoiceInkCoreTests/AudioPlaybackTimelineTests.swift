import Foundation
import VoiceInkCore

final class AudioPlaybackTimelineTests: XCTestCase {
    func testProgressClampsCurrentTimeAgainstDuration() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: -1, duration: 10), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: 5, duration: 10), 0.5)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: 12, duration: 10), 1)
    }

    func testProgressReturnsZeroForInvalidDuration() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: 5, duration: 0), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: 5, duration: -1), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(currentTime: .infinity, duration: 10), 0)
    }

    func testLocationProgressClampsAgainstWidth() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: -10, width: 100), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: 25, width: 100), 0.25)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: 125, width: 100), 1)
    }

    func testLocationProgressReturnsZeroForInvalidWidth() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: 10, width: 0), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: 10, width: -5), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.progress(locationX: .infinity, width: 100), 0)
    }

    func testTimeAtLocationUsesClampedLocationProgress() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.time(atLocationX: 25, width: 100, duration: 40), 10)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.time(atLocationX: -25, width: 100, duration: 40), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.time(atLocationX: 125, width: 100, duration: 40), 40)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.time(atLocationX: 25, width: 100, duration: 0), 0)
    }

    func testClampedTimeBoundsDirectSeekRequests() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.clampedTime(-3, duration: 10), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.clampedTime(4, duration: 10), 4)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.clampedTime(14, duration: 10), 10)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.clampedTime(4, duration: 0), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.clampedTime(.infinity, duration: 10), 0)
    }

    func testSampleProgressUsesStableWaveformPosition() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.sampleProgress(index: 0, sampleCount: 200), 0)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.sampleProgress(index: 100, sampleCount: 200), 0.5)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.sampleProgress(index: 250, sampleCount: 200), 1)
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.sampleProgress(index: 1, sampleCount: 0), 0)
    }

    func testTimelineUpdateIntervalPreservesPlatformAudioPlayerCadence() {
        XCTAssertEqual(VoiceInkAudioPlaybackTimeline.updateInterval, 0.1)
    }

    func testTimerTickPlanPreservesPlatformCompletionBehavior() {
        XCTAssertEqual(
            VoiceInkAudioPlaybackTimerTickPlan.macOS(currentTime: 4, duration: 10),
            VoiceInkAudioPlaybackTimerTickPlan(currentTime: 4, action: .none)
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackTimerTickPlan.macOS(currentTime: 10, duration: 10),
            VoiceInkAudioPlaybackTimerTickPlan(currentTime: 10, action: .markStoppedAndSeek(0))
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackTimerTickPlan.iOS(
                currentTime: 9.5,
                playerIsPlaying: false,
                shellIsPlaying: true
            ),
            VoiceInkAudioPlaybackTimerTickPlan(currentTime: 9.5, action: .markStopped)
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackTimerTickPlan.iOS(
                currentTime: 9.5,
                playerIsPlaying: false,
                shellIsPlaying: false
            ),
            VoiceInkAudioPlaybackTimerTickPlan(currentTime: 9.5, action: .none)
        )
    }

    func testTimerTickPlanExposesShellSideEffectHints() {
        XCTAssertEqual(
            VoiceInkAudioPlaybackTimerTickPlan(currentTime: 4, action: .none).shouldStopTimer,
            false
        )
        XCTAssertNil(VoiceInkAudioPlaybackTimerTickPlan(currentTime: 4, action: .none).playerSeekTime)

        XCTAssertEqual(
            VoiceInkAudioPlaybackTimerTickPlan(currentTime: 9.5, action: .markStopped).shouldStopTimer,
            true
        )
        XCTAssertNil(VoiceInkAudioPlaybackTimerTickPlan(currentTime: 9.5, action: .markStopped).playerSeekTime)

        XCTAssertEqual(
            VoiceInkAudioPlaybackTimerTickPlan(currentTime: 10, action: .markStoppedAndSeek(0)).shouldStopTimer,
            true
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackTimerTickPlan(currentTime: 10, action: .markStoppedAndSeek(0)).playerSeekTime,
            0
        )
    }

    func testPlaybackStateLoadPreservesPlatformResetBehavior() {
        let state = VoiceInkAudioPlaybackState(
            isPlaying: true,
            currentTime: 4,
            duration: 10,
            playbackRate: 1.5
        )

        XCTAssertEqual(
            state.loaded(duration: 12, resetCurrentTime: true),
            VoiceInkAudioPlaybackState(isPlaying: true, currentTime: 0, duration: 12, playbackRate: 1.5)
        )
        XCTAssertEqual(
            state.loaded(duration: 12, resetCurrentTime: false),
            VoiceInkAudioPlaybackState(isPlaying: true, currentTime: 4, duration: 12, playbackRate: 1.5)
        )
    }

    func testPlaybackStatePlansPlayPauseStopAndTickUpdates() {
        let state = VoiceInkAudioPlaybackState(
            isPlaying: false,
            currentTime: 3,
            duration: 10,
            playbackRate: 1
        )

        XCTAssertEqual(state.playing().isPlaying, true)
        XCTAssertEqual(state.playing().paused().isPlaying, false)
        XCTAssertEqual(
            state.playing().stopped(),
            VoiceInkAudioPlaybackState(isPlaying: false, currentTime: 0, duration: 10, playbackRate: 1)
        )
        XCTAssertEqual(
            state.updatingCurrentTime(6),
            VoiceInkAudioPlaybackState(isPlaying: false, currentTime: 6, duration: 10, playbackRate: 1)
        )
    }

    func testPlaybackStateAppliesTimerTickPlanActions() {
        let state = VoiceInkAudioPlaybackState(
            isPlaying: true,
            currentTime: 3,
            duration: 10,
            playbackRate: 1
        )

        XCTAssertEqual(
            state.applyingTimerTickPlan(VoiceInkAudioPlaybackTimerTickPlan(currentTime: 6, action: .none)),
            VoiceInkAudioPlaybackState(isPlaying: true, currentTime: 6, duration: 10, playbackRate: 1)
        )
        XCTAssertEqual(
            state.applyingTimerTickPlan(VoiceInkAudioPlaybackTimerTickPlan(currentTime: 9.5, action: .markStopped)),
            VoiceInkAudioPlaybackState(isPlaying: false, currentTime: 9.5, duration: 10, playbackRate: 1)
        )
        XCTAssertEqual(
            state.applyingTimerTickPlan(VoiceInkAudioPlaybackTimerTickPlan(currentTime: 10, action: .markStoppedAndSeek(0))),
            VoiceInkAudioPlaybackState(isPlaying: false, currentTime: 0, duration: 10, playbackRate: 1)
        )
    }

    func testPlaybackStateSeekAndRateCycleUseSharedPolicies() {
        let state = VoiceInkAudioPlaybackState(
            isPlaying: false,
            currentTime: 3,
            duration: 10,
            playbackRate: 1
        )

        XCTAssertEqual(state.seeking(to: -2).currentTime, 0)
        XCTAssertEqual(state.seeking(to: 14).currentTime, 10)
        XCTAssertEqual(state.cyclingPlaybackRate().playbackRate, 1.5)
    }

    func testPlaybackRateRestoresExistingPositiveMacOSValues() {
        XCTAssertEqual(VoiceInkAudioPlaybackRate.restoredRate(0), 1.0)
        XCTAssertEqual(VoiceInkAudioPlaybackRate.restoredRate(-1), 1.0)
        XCTAssertEqual(VoiceInkAudioPlaybackRate.restoredRate(1.25), 1.25)
    }

    func testPlaybackRateCyclesThroughExistingMacOSOrder() {
        XCTAssertEqual(VoiceInkAudioPlaybackRate.next(after: 1.0), 1.5)
        XCTAssertEqual(VoiceInkAudioPlaybackRate.next(after: 1.5), 2.0)
        XCTAssertEqual(VoiceInkAudioPlaybackRate.next(after: 2.0), 1.0)
        XCTAssertEqual(VoiceInkAudioPlaybackRate.next(after: 1.25), 1.0)
    }

    func testPlaybackRateLabelsPreserveExistingMacOSPresentation() {
        XCTAssertEqual(VoiceInkAudioPlaybackRate.label(for: 1.0), "1×")
        XCTAssertEqual(VoiceInkAudioPlaybackRate.label(for: 1.5), "1.5×")
        XCTAssertEqual(VoiceInkAudioPlaybackRate.label(for: 2.0), "2×")
        XCTAssertEqual(VoiceInkAudioPlaybackRate.label(for: 1.25), "2×")
    }

    func testPlaybackRatePreferenceUsesSharedStorageKey() {
        let suiteName = "VoiceInkAudioPlaybackRateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(VoiceInkAudioPlaybackRate.current(from: defaults), 1.0)

        VoiceInkAudioPlaybackRate.save(1.5, to: defaults)
        XCTAssertEqual(defaults.float(forKey: VoiceInkUserDefaultsKey.audioPlaybackRate), 1.5)
        XCTAssertEqual(VoiceInkAudioPlaybackRate.current(from: defaults), 1.5)

        VoiceInkAudioPlaybackRate.clear(from: defaults)
        XCTAssertEqual(VoiceInkAudioPlaybackRate.current(from: defaults), 1.0)
    }

    func testPlaybackPresentationPreservesPlatformLoadingAndPlayPauseCopy() {
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.loadingText, "Loading...")
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.timestampSystemImageName, "calendar")
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.durationSystemImageName, "waveform")
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.playPauseSystemImageName(isPlaying: true), "pause.fill")
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.playPauseSystemImageName(isPlaying: false), "play.fill")
    }
}
