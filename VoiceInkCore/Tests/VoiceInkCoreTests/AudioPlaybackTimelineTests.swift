import Foundation
import VoiceInkCore

final class AudioPlaybackTimelineTests: XCTestCase {
    func testIOSAudioPlaybackSessionConfigurationPreservesPlaybackPolicy() {
        XCTAssertEqual(
            VoiceInkIOSAudioPlaybackSessionConfiguration.notePlayback,
            VoiceInkIOSAudioPlaybackSessionConfiguration(
                category: .playback,
                mode: .spokenAudio
            )
        )
    }

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

    func testIOSAudioRecorderConfigurationUsesMono16kPCM16Policy() {
        XCTAssertEqual(
            VoiceInkIOSAudioRecorderConfiguration.voiceRecording,
            VoiceInkIOSAudioRecorderConfiguration(
                format: .linearPCM,
                sampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
                channelCount: VoiceInkPCM16Audio.monoChannelCount,
                bitDepth: VoiceInkPCM16Audio.bitsPerSample,
                isBigEndian: VoiceInkPCM16Audio.isBigEndian,
                isFloatingPoint: VoiceInkPCM16Audio.isFloatingPoint,
                quality: .high,
                isMeteringEnabled: true
            )
        )
    }

    func testPlaybackDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            VoiceInkAudioPlaybackDiagnostics.loadFailedMessage(errorDescription: "missing file"),
            "Failed to load audio: missing file"
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackDiagnostics.playFailedMessage(errorDescription: "session denied"),
            "Failed to play audio: session denied"
        )
    }

    func testPlaybackDiagnosticsPreserveMacOSConsoleCopy() {
        XCTAssertEqual(
            VoiceInkAudioPlaybackDiagnostics.macOSWaveformReadFailedMessage(errorDescription: "file is corrupt"),
            "Error reading audio file: file is corrupt"
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackDiagnostics.macOSLoadFailedMessage(localizedDescription: "format unsupported"),
            "Error loading audio: format unsupported"
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

        XCTAssertEqual(playbackActivationEvents(from: &activeState), ["cancel", "deactivate", "mark"])
        XCTAssertEqual(activeState.timeoutRemaining, 0)
        XCTAssertTrue(activeState.isSessionActive)

        var inactiveState = VoiceInkAudioSessionLifecycleState()
        XCTAssertEqual(playbackActivationEvents(from: &inactiveState), ["cancel"])
        XCTAssertFalse(inactiveState.isSessionActive)
    }

    func testAudioSessionPlaybackActivationPlanAppliesRuntimeStateInOrder() {
        var activeState = VoiceInkAudioSessionLifecycleState(isSessionActive: true)
        XCTAssertEqual(playbackActivationEvents(from: &activeState), ["cancel", "deactivate", "mark"])

        var inactiveState = VoiceInkAudioSessionLifecycleState(isSessionActive: false)
        XCTAssertEqual(playbackActivationEvents(from: &inactiveState), ["cancel"])
    }

    private func playbackActivationEvents(from state: inout VoiceInkAudioSessionLifecycleState) -> [String] {
        let plan = state.beginPlaybackActivation()
        var events: [String] = []

        do {
            try plan.applyRuntimeState(
                cancelScheduledDeactivation: { events.append("cancel") },
                deactivateCurrentSession: { events.append("deactivate") },
                markDeactivated: { events.append("mark") }
            )
        } catch {
            XCTFail("Unexpected playback activation error: \(error)")
        }

        return events
    }

    func testAudioSessionLifecycleStatePlansImmediateDeactivationSideEffects() {
        var activeState = VoiceInkAudioSessionLifecycleState(isSessionActive: true, timeoutRemaining: 12)

        XCTAssertEqual(immediateDeactivationApplication(from: &activeState).events, ["cancel", "deactivate", "mark"])
        XCTAssertEqual(activeState.timeoutRemaining, 0)
        XCTAssertTrue(activeState.isSessionActive)

        var inactiveState = VoiceInkAudioSessionLifecycleState(isSessionActive: false, timeoutRemaining: 12)
        XCTAssertEqual(immediateDeactivationApplication(from: &inactiveState).events, ["cancel"])
        XCTAssertEqual(inactiveState.timeoutRemaining, 0)
        XCTAssertFalse(inactiveState.isSessionActive)
    }

    func testAudioSessionImmediateDeactivationPlanAppliesRuntimeStateInOrder() {
        var activeState = VoiceInkAudioSessionLifecycleState(isSessionActive: true)
        let activeApplication = immediateDeactivationApplication(from: &activeState)
        XCTAssertTrue(activeApplication.didDeactivate)
        XCTAssertEqual(activeApplication.events, ["cancel", "deactivate", "mark"])

        var inactiveState = VoiceInkAudioSessionLifecycleState(isSessionActive: false)
        let inactiveApplication = immediateDeactivationApplication(from: &inactiveState)
        XCTAssertFalse(inactiveApplication.didDeactivate)
        XCTAssertEqual(inactiveApplication.events, ["cancel"])
    }

    private func immediateDeactivationApplication(
        from state: inout VoiceInkAudioSessionLifecycleState
    ) -> (didDeactivate: Bool, events: [String]) {
        let plan = state.beginImmediateDeactivation()
        var events: [String] = []
        var didDeactivate = false

        do {
            didDeactivate = try plan.applyRuntimeState(
                cancelScheduledDeactivation: { events.append("cancel") },
                deactivateSession: { events.append("deactivate") },
                markDeactivated: { events.append("mark") }
            )
        } catch {
            XCTFail("Unexpected immediate deactivation error: \(error)")
        }

        return (didDeactivate, events)
    }

    func testAudioSessionLifecycleStateRequestsDeactivationWhenCountdownExpires() {
        var state = VoiceInkAudioSessionLifecycleState(isSessionActive: true, timeoutRemaining: 1)

        XCTAssertEqual(state.advanceCountdown(), .immediate)
        XCTAssertEqual(state.timeoutRemaining, 0)
        XCTAssertTrue(state.isSessionActive)
    }

    func testAudioSessionLifecycleStateReturnsShellExecutionPlans() {
        var state = VoiceInkAudioSessionLifecycleState(isSessionActive: true)

        assertDeactivationExecution(
            state.scheduleDeactivationExecution(timeoutSeconds: 90),
            expectedEvents: ["timer", "scheduled"]
        )
        XCTAssertEqual(state.timeoutRemaining, 90)

        state = VoiceInkAudioSessionLifecycleState(isSessionActive: true)
        assertDeactivationExecution(
            state.scheduleDeactivationExecution(timeoutSeconds: 0),
            expectedEvents: ["deactivate"]
        )
        XCTAssertEqual(state.timeoutRemaining, 0)

        state = VoiceInkAudioSessionLifecycleState(isSessionActive: true, timeoutRemaining: 1)
        assertDeactivationExecution(
            state.advanceCountdownExecution(),
            expectedEvents: ["deactivate"]
        )
        XCTAssertEqual(state.timeoutRemaining, 0)
    }

    private func assertDeactivationExecution(
        _ plan: VoiceInkAudioSessionDeactivationExecutionPlan,
        expectedEvents: [String]
    ) {
        var events: [String] = []

        plan.applyRuntimeState(
            deactivateSession: { events.append("deactivate") },
            runCountdownTimer: { events.append("timer") },
            countdownTimerDidStart: { events.append("scheduled") }
        )

        XCTAssertEqual(events, expectedEvents)
    }

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
        let playingState = VoiceInkAudioPlaybackState(
            isPlaying: true,
            currentTime: 4,
            duration: 10,
            playbackRate: 1
        )

        XCTAssertEqual(
            playingState.applyingTimerTickPlan(
                VoiceInkAudioPlaybackTimerTickPlan.macOS(currentTime: 4, duration: 10)
            ),
            VoiceInkAudioPlaybackState(isPlaying: true, currentTime: 4, duration: 10, playbackRate: 1)
        )
        XCTAssertEqual(
            playingState.applyingTimerTickPlan(
                VoiceInkAudioPlaybackTimerTickPlan.macOS(currentTime: 10, duration: 10)
            ),
            VoiceInkAudioPlaybackState(isPlaying: false, currentTime: 0, duration: 10, playbackRate: 1)
        )
        XCTAssertEqual(
            playingState.applyingTimerTickPlan(
                VoiceInkAudioPlaybackTimerTickPlan.iOS(
                    currentTime: 9.5,
                    playerIsPlaying: false,
                    shellIsPlaying: true
                )
            ),
            VoiceInkAudioPlaybackState(isPlaying: false, currentTime: 9.5, duration: 10, playbackRate: 1)
        )
        XCTAssertEqual(
            playingState.applyingTimerTickPlan(
                VoiceInkAudioPlaybackTimerTickPlan.iOS(
                    currentTime: 9.5,
                    playerIsPlaying: false,
                    shellIsPlaying: false
                )
            ),
            VoiceInkAudioPlaybackState(isPlaying: true, currentTime: 9.5, duration: 10, playbackRate: 1)
        )
    }

    func testTimerTickPlanAppliesRuntimeStateInOrder() {
        var events: [String] = []

        VoiceInkAudioPlaybackTimerTickPlan.iOS(
            currentTime: 4,
            playerIsPlaying: true,
            shellIsPlaying: true
        ).applyRuntimeState(
            seekPlayer: { events.append("seek:\($0)") },
            stopTimer: { events.append("stop") }
        )

        VoiceInkAudioPlaybackTimerTickPlan.iOS(
            currentTime: 9.5,
            playerIsPlaying: false,
            shellIsPlaying: true
        ).applyRuntimeState(
            seekPlayer: { events.append("seek:\($0)") },
            stopTimer: { events.append("stop") }
        )

        VoiceInkAudioPlaybackTimerTickPlan.macOS(currentTime: 10, duration: 10).applyRuntimeState(
            seekPlayer: { events.append("seek:\($0)") },
            stopTimer: { events.append("stop") }
        )

        XCTAssertEqual(events, ["stop", "seek:0.0", "stop"])
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

    func testPlaybackStateBuildsPlayPauseRuntimePlan() {
        var events: [String] = []
        let stopped = VoiceInkAudioPlaybackState(
            isPlaying: false,
            currentTime: 0,
            duration: 10,
            playbackRate: 1
        )
        let playing = VoiceInkAudioPlaybackState(
            isPlaying: true,
            currentTime: 1,
            duration: 10,
            playbackRate: 1
        )

        stopped.playPausePlan.applyRuntimeState(
            play: { events.append("play") },
            pause: { events.append("pause") }
        )
        playing.playPausePlan.applyRuntimeState(
            play: { events.append("play") },
            pause: { events.append("pause") }
        )

        XCTAssertEqual(events, ["play", "pause"])
    }

    func testPlaybackStateAppliesTimerTickPlanActions() {
        let state = VoiceInkAudioPlaybackState(
            isPlaying: true,
            currentTime: 3,
            duration: 10,
            playbackRate: 1
        )

        XCTAssertEqual(
            state.applyingTimerTickPlan(
                VoiceInkAudioPlaybackTimerTickPlan.iOS(
                    currentTime: 6,
                    playerIsPlaying: true,
                    shellIsPlaying: true
                )
            ),
            VoiceInkAudioPlaybackState(isPlaying: true, currentTime: 6, duration: 10, playbackRate: 1)
        )
        XCTAssertEqual(
            state.applyingTimerTickPlan(
                VoiceInkAudioPlaybackTimerTickPlan.iOS(
                    currentTime: 9.5,
                    playerIsPlaying: false,
                    shellIsPlaying: true
                )
            ),
            VoiceInkAudioPlaybackState(isPlaying: false, currentTime: 9.5, duration: 10, playbackRate: 1)
        )
        XCTAssertEqual(
            state.applyingTimerTickPlan(
                VoiceInkAudioPlaybackTimerTickPlan.macOS(currentTime: 10, duration: 10)
            ),
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

    func testPlaybackPresentationPreservesMacOSActionHelpCopy() {
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.showInFinderHelpText, "Show in Finder")
        XCTAssertEqual(
            VoiceInkAudioPlaybackPresentation.selectEnhancementPromptHelpText,
            "Select enhancement prompt"
        )
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.enhancementPromptFallbackSystemImageName, "sparkles")
        XCTAssertEqual(
            VoiceInkAudioPlaybackPresentation.enhancementPromptSystemImageName(activePromptIcon: "wand.and.stars"),
            "wand.and.stars"
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackPresentation.enhancementPromptSystemImageName(activePromptIcon: nil),
            "sparkles"
        )
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.retranscribeAudioHelpText, "Retranscribe this audio")
        XCTAssertEqual(
            VoiceInkAudioPlaybackPresentation.reEnhanceWithSelectedPromptHelpText,
            "Re-enhance with selected prompt"
        )
        XCTAssertEqual(VoiceInkAudioPlaybackPresentation.viewDetailsHelpText, "View details")
    }

    func testPlaybackActionBannerPresentationPreservesMacOSActionCopy() {
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.retranscriptionSuccess,
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "Retranscription successful",
                isError: false
            )
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.reEnhancementSuccess,
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "Re-enhancement successful",
                isError: false
            )
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.retranscriptionFailure(errorDescription: ""),
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "Retranscription failed",
                isError: true
            )
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.retranscriptionFailure(
                errorDescription: "provider unavailable"
            ),
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "provider unavailable",
                isError: true
            )
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.reEnhancementFailure(errorDescription: ""),
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "Re-enhancement failed",
                isError: true
            )
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.reEnhancementFailure(errorDescription: "timeout"),
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "timeout",
                isError: true
            )
        )
    }

    func testPlaybackActionBannerPresentationPreservesMacOSGuardCopy() {
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.retranscriptionNoModelFailure,
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "No transcription model selected",
                isError: true
            )
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.reEnhancementUnavailable(
                isEnabled: false,
                isConfigured: false
            ),
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "AI Enhancement is not enabled or configured",
                isError: true
            )
        )
        XCTAssertEqual(
            VoiceInkAudioPlaybackActionBannerPresentation.reEnhancementUnavailable(
                isEnabled: true,
                isConfigured: false
            ),
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "AI Enhancement is not enabled or configured",
                isError: true
            )
        )
        XCTAssertNil(
            VoiceInkAudioPlaybackActionBannerPresentation.reEnhancementUnavailable(
                isEnabled: true,
                isConfigured: true
            )
        )
    }

    func testPlaybackReEnhancementControlPresentationOwnsAvailabilityAndOpacity() {
        let available = VoiceInkAudioPlaybackReEnhancementControlPresentation(
            isOperationInProgress: false,
            isEnhancementEnabled: true,
            isEnhancementConfigured: true
        )
        XCTAssertFalse(available.isActionDisabled)
        XCTAssertEqual(available.opacity, 1.0)
        XCTAssertNil(available.unavailableBannerPresentation)

        let unavailable = VoiceInkAudioPlaybackReEnhancementControlPresentation(
            isOperationInProgress: false,
            isEnhancementEnabled: false,
            isEnhancementConfigured: false
        )
        XCTAssertTrue(unavailable.isActionDisabled)
        XCTAssertEqual(unavailable.opacity, 0.4)
        XCTAssertEqual(
            unavailable.unavailableBannerPresentation,
            VoiceInkAudioPlaybackActionBannerPresentation(
                message: "AI Enhancement is not enabled or configured",
                isError: true
            )
        )

        let busy = VoiceInkAudioPlaybackReEnhancementControlPresentation(
            isOperationInProgress: true,
            isEnhancementEnabled: true,
            isEnhancementConfigured: true
        )
        XCTAssertTrue(busy.isActionDisabled)
        XCTAssertEqual(busy.opacity, 1.0)
        XCTAssertNil(busy.unavailableBannerPresentation)
    }
}
