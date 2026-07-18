import Foundation
@testable import VoiceInkCore

final class RecordingStatePolicyTests: XCTestCase {
    func testActiveRecordingPolicyOnlyAllowsRecordingState() {
        XCTAssertFalse(VoiceInkRecordingState.idle.isActivelyRecording)
        XCTAssertFalse(VoiceInkRecordingState.starting.isActivelyRecording)
        XCTAssertTrue(VoiceInkRecordingState.recording.isActivelyRecording)
        XCTAssertFalse(VoiceInkRecordingState.transcribing.isActivelyRecording)
        XCTAssertFalse(VoiceInkRecordingState.enhancing.isActivelyRecording)
        XCTAssertFalse(VoiceInkRecordingState.busy.isActivelyRecording)
    }

    func testRecorderCaptureStatePolicyPreservesMacOSCancellationPath() {
        XCTAssertFalse(VoiceInkRecordingState.idle.isRecorderCaptureInProgress)
        XCTAssertTrue(VoiceInkRecordingState.starting.isRecorderCaptureInProgress)
        XCTAssertTrue(VoiceInkRecordingState.recording.isRecorderCaptureInProgress)
        XCTAssertFalse(VoiceInkRecordingState.transcribing.isRecorderCaptureInProgress)
        XCTAssertFalse(VoiceInkRecordingState.enhancing.isRecorderCaptureInProgress)
        XCTAssertFalse(VoiceInkRecordingState.busy.isRecorderCaptureInProgress)
    }

    func testMacOSRecordingStartupOverlapsStreamingWhenPowerModeCannotChangeSession() {
        let plan = VoiceInkMacOSRecordingStartupOrchestrationPolicy.plan(
            powerModeConfigurationCount: 0
        )

        XCTAssertFalse(plan.shouldResolvePowerMode)
        XCTAssertTrue(plan.shouldPrepareTranscriptionSessionBeforeRecorder)
    }

    func testMacOSRecordingStartupDefersStreamingWhenPowerModeCanChangeSession() {
        let plan = VoiceInkMacOSRecordingStartupOrchestrationPolicy.plan(
            powerModeConfigurationCount: 1
        )

        XCTAssertTrue(plan.shouldResolvePowerMode)
        XCTAssertFalse(plan.shouldPrepareTranscriptionSessionBeforeRecorder)
    }

    func testRecordingShortcutActionGatePreservesMacOSBusyStatePolicy() {
        XCTAssertTrue(VoiceInkRecordingState.idle.acceptsRecordingShortcutAction)
        XCTAssertTrue(VoiceInkRecordingState.starting.acceptsRecordingShortcutAction)
        XCTAssertTrue(VoiceInkRecordingState.recording.acceptsRecordingShortcutAction)
        XCTAssertFalse(VoiceInkRecordingState.transcribing.acceptsRecordingShortcutAction)
        XCTAssertFalse(VoiceInkRecordingState.enhancing.acceptsRecordingShortcutAction)
        XCTAssertFalse(VoiceInkRecordingState.busy.acceptsRecordingShortcutAction)
    }

    func testRecorderUITogglePlanAppliesMacOSRuntimeStateMapping() async {
        var events: [String] = []

        for state in [
            VoiceInkRecordingState.idle,
            .starting,
            .recording,
            .transcribing,
            .enhancing,
            .busy,
        ] {
            await state.applyRecorderUIToggleRuntimeState(
                toggleRecord: { events.append("toggle") },
                cancelRecording: { events.append("cancel") },
                dismissRecorder: { events.append("dismiss") }
            )
        }

        XCTAssertEqual(events, [
            "dismiss",
            "toggle",
            "toggle",
            "cancel",
            "cancel",
            "dismiss",
        ])
    }

    func testRecordingPermissionPlanAppliesStatusAndRequestResultRuntimeState() {
        var events: [String] = []

        VoiceInkRecordingPermissionPolicy.plan(for: .granted).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        VoiceInkRecordingPermissionPolicy.plan(for: .denied).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        VoiceInkRecordingPermissionPolicy.plan(for: .undetermined).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        VoiceInkRecordingPermissionPolicy.plan(for: .undetermined).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(false)
            }
        )
        VoiceInkRecordingPermissionPolicy.plan(afterPermissionRequestGranted: true).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(false)
            }
        )
        VoiceInkRecordingPermissionPolicy.plan(afterPermissionRequestGranted: false).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )

        XCTAssertEqual(events, [
            "start",
            "denied",
            "request",
            "start",
            "request",
            "denied",
            "start",
            "denied"
        ])
    }

    func testRecordingPermissionSettingsOpenPlanAppliesOnlyWhenURLCanOpen() {
        var events: [String] = []
        let settingsURL = URL(string: "app-settings:")!

        for input in [
            (settingsURL: settingsURL as URL?, canOpenSettingsURL: true),
            (settingsURL: nil, canOpenSettingsURL: true),
            (settingsURL: settingsURL as URL?, canOpenSettingsURL: false),
            (settingsURL: nil, canOpenSettingsURL: false)
        ] {
            VoiceInkRecordingPermissionPolicy.settingsOpenPlan(
                settingsURL: input.settingsURL,
                canOpenURL: { _ in input.canOpenSettingsURL }
            ).applyRuntimeState { url in
                events.append("open:\(url.absoluteString)")
            }
        }

        XCTAssertEqual(events, ["open:app-settings:"])
    }

    func testPostRecordingProcessingStatePolicyPreservesMacOSProcessingStates() {
        XCTAssertFalse(VoiceInkRecordingState.idle.isPostRecordingProcessing)
        XCTAssertFalse(VoiceInkRecordingState.starting.isPostRecordingProcessing)
        XCTAssertFalse(VoiceInkRecordingState.recording.isPostRecordingProcessing)
        XCTAssertTrue(VoiceInkRecordingState.transcribing.isPostRecordingProcessing)
        XCTAssertTrue(VoiceInkRecordingState.enhancing.isPostRecordingProcessing)
        XCTAssertFalse(VoiceInkRecordingState.busy.isPostRecordingProcessing)
    }

    func testRecorderDismissCancelableStatePolicyPreservesMacOSWindowBehavior() {
        XCTAssertFalse(VoiceInkRecordingState.idle.isRecorderDismissCancelable)
        XCTAssertTrue(VoiceInkRecordingState.starting.isRecorderDismissCancelable)
        XCTAssertTrue(VoiceInkRecordingState.recording.isRecorderDismissCancelable)
        XCTAssertTrue(VoiceInkRecordingState.transcribing.isRecorderDismissCancelable)
        XCTAssertTrue(VoiceInkRecordingState.enhancing.isRecorderDismissCancelable)
        XCTAssertFalse(VoiceInkRecordingState.busy.isRecorderDismissCancelable)
    }

    func testPipelineFinishIdleRepairStatePolicyPreservesMacOSEngineBehavior() {
        XCTAssertFalse(VoiceInkRecordingState.idle.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertFalse(VoiceInkRecordingState.starting.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertFalse(VoiceInkRecordingState.recording.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertTrue(VoiceInkRecordingState.transcribing.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertTrue(VoiceInkRecordingState.enhancing.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertTrue(VoiceInkRecordingState.busy.shouldReturnToIdleWhenActivePipelineFinishes)
    }

    func testMacOSRecordingCancellationPlanFinishesActiveCaptureImmediately() async {
        for state in [VoiceInkRecordingState.starting, .recording] {
            let events = await macOSRecordingCancellationEvents(for: state)

            XCTAssertEqual(
                events,
                [
                    "clearDeferredStopRequest",
                    "requestRecordingCancellation",
                    "finishActiveRecorderCancellation",
                    "finishRecorderSessionImmediately"
                ]
            )
        }
    }

    func testMacOSRecordingCancellationPlanCancelsProcessingWithoutFinishingSession() async {
        for state in [VoiceInkRecordingState.transcribing, .enhancing] {
            let events = await macOSRecordingCancellationEvents(for: state)

            XCTAssertEqual(
                events,
                [
                    "clearDeferredStopRequest",
                    "requestRecordingCancellation",
                    "clearPartialTranscript",
                    "recordingState:idle"
                ]
            )
        }
    }

    func testMacOSRecordingCancellationPlanRepairsIdleAndBusyState() async {
        for state in [VoiceInkRecordingState.idle, .busy] {
            let events = await macOSRecordingCancellationEvents(for: state)

            XCTAssertEqual(
                events,
                [
                    "clearDeferredStopRequest",
                    "clearPartialTranscript",
                    "clearCancelFlag",
                    "recordingState:idle",
                    "finishRecorderSessionImmediately"
                ]
            )
        }
    }

    private func macOSRecordingCancellationEvents(for state: VoiceInkRecordingState) async -> [String] {
        var events: [String] = []

        await VoiceInkMacOSRecordingCancellationPolicy.plan(recordingState: state).applyRuntimeState(
            clearDeferredStopRequest: { events.append("clearDeferredStopRequest") },
            requestRecordingCancellation: { events.append("requestRecordingCancellation") },
            finishActiveRecorderCancellation: { events.append("finishActiveRecorderCancellation") },
            clearPartialTranscript: { events.append("clearPartialTranscript") },
            clearCancelFlag: { events.append("clearCancelFlag") },
            setRecordingState: { events.append("recordingState:\($0)") },
            finishRecorderSessionImmediately: { events.append("finishRecorderSessionImmediately") }
        )

        return events
    }

    func testRecordingFlowStatePreservesIOSStartAndStopTransitions() {
        var flowState = VoiceInkRecordingFlowState(currentDuration: 12)

        flowState.prepareRecordingStart()
        XCTAssertEqual(flowState.recordingState, .recording)
        XCTAssertTrue(flowState.animate)
        XCTAssertFalse(flowState.isRecordingSheetPresented)
        XCTAssertEqual(flowState.currentDuration, 12)

        flowState.completeRecordingStart()
        XCTAssertEqual(flowState.recordingState, .recording)
        XCTAssertTrue(flowState.animate)
        XCTAssertTrue(flowState.isRecordingSheetPresented)
        XCTAssertEqual(flowState.currentDuration, 0)

        flowState.advanceDuration()
        XCTAssertEqual(flowState.currentDuration, VoiceInkRecordingFlowState.durationUpdateInterval)

        flowState.finishRecording()
        XCTAssertEqual(flowState.recordingState, .idle)
        XCTAssertFalse(flowState.animate)
        XCTAssertFalse(flowState.isRecordingSheetPresented)
        XCTAssertEqual(flowState.currentDuration, VoiceInkRecordingFlowState.durationUpdateInterval)
    }

    func testRecordingStopPlanFinishesFlowAndCreatesPendingDraftOnlyWhenAudioExists() {
        let recordingState = VoiceInkRecordingFlowState(
            recordingState: .recording,
            animate: true,
            isRecordingSheetPresented: true,
            currentDuration: 4.5
        )

        let savedAudioPlan = recordingState.stopRecordingPlan(audioFileURL: "recording_42.wav")

        XCTAssertEqual(savedAudioPlan.flowStateAfterStop.recordingState, .idle)
        XCTAssertFalse(savedAudioPlan.flowStateAfterStop.animate)
        XCTAssertFalse(savedAudioPlan.flowStateAfterStop.isRecordingSheetPresented)
        XCTAssertEqual(savedAudioPlan.flowStateAfterStop.currentDuration, 4.5)
        XCTAssertEqual(
            savedAudioPlan.pendingDraft,
            VoiceInkRecordingTranscriptionDraft.pending(
                duration: 4.5,
                audioFileURL: "recording_42.wav"
            )
        )

        let missingAudioPlan = recordingState.stopRecordingPlan(audioFileURL: nil)

        XCTAssertEqual(missingAudioPlan.flowStateAfterStop.recordingState, .idle)
        XCTAssertFalse(missingAudioPlan.flowStateAfterStop.animate)
        XCTAssertFalse(missingAudioPlan.flowStateAfterStop.isRecordingSheetPresented)
        XCTAssertEqual(missingAudioPlan.flowStateAfterStop.currentDuration, 4.5)
        XCTAssertNil(missingAudioPlan.pendingDraft)
    }

    func testRecordingStopPlanAppliesIOSRuntimeStateInOrder() {
        let recordingState = VoiceInkRecordingFlowState(
            recordingState: .recording,
            animate: true,
            isRecordingSheetPresented: true,
            currentDuration: 4.5
        )
        var events: [String] = []

        recordingState.stopRecordingPlan(audioFileURL: "recording_42.wav").applyRuntimeState(
            stopRecorder: { events.append("stop") },
            stopDurationTimer: { events.append("timer") },
            setFlowState: { events.append("state:\($0.recordingState):\($0.currentDuration)") },
            updateRecordingState: { events.append("coordinator:\($0)") },
            insertPendingDraft: { events.append("draft:\($0.audioFileURL ?? "")") }
        )

        recordingState.stopRecordingPlan(audioFileURL: nil).applyRuntimeState(
            stopRecorder: { events.append("stop") },
            stopDurationTimer: { events.append("timer") },
            setFlowState: { events.append("state:\($0.recordingState):\($0.currentDuration)") },
            updateRecordingState: { events.append("coordinator:\($0)") },
            insertPendingDraft: { events.append("draft:\($0.audioFileURL ?? "")") }
        )

        XCTAssertEqual(events, [
            "stop",
            "timer",
            "state:idle:4.5",
            "coordinator:false",
            "draft:recording_42.wav",
            "stop",
            "timer",
            "state:idle:4.5",
            "coordinator:false"
        ])
    }

    func testRecordingCancelPlanAppliesIOSRuntimeStateInOrder() {
        let recordingState = VoiceInkRecordingFlowState(
            recordingState: .recording,
            animate: true,
            isRecordingSheetPresented: true,
            currentDuration: 4.5
        )
        var events: [String] = []

        recordingState.cancelRecordingPlan().applyRuntimeState(
            discardRecorder: { events.append("discard") },
            stopDurationTimer: { events.append("timer") },
            setFlowState: { events.append("state:\($0.recordingState):\($0.currentDuration)") },
            updateRecordingState: { events.append("coordinator:\($0)") }
        )

        XCTAssertEqual(events, [
            "discard",
            "timer",
            "state:idle:0.0",
            "coordinator:false"
        ])
    }

    func testAudioRecorderStopPolicyPreservesIOSStopCleanup() {
        XCTAssertEqual(
            audioRecorderStopEvents(for: .keepRecordingFile),
            ["stop", "timer", "recording:false", "levels", "session"]
        )
    }

    func testAudioRecorderStopPolicyPreservesIOSDiscardCleanup() {
        XCTAssertEqual(
            audioRecorderStopEvents(for: .discardRecordingFile),
            ["stop", "timer", "recording:false", "levels", "delete", "url", "session"]
        )
    }

    func testAudioRecorderStopPlanAppliesRuntimeStateInOrder() {
        let events = audioRecorderStopEvents(for: .keepRecordingFile) +
            audioRecorderStopEvents(for: .discardRecordingFile)

        XCTAssertEqual(events, [
            "stop",
            "timer",
            "recording:false",
            "levels",
            "session",
            "stop",
            "timer",
            "recording:false",
            "levels",
            "delete",
            "url",
            "session"
        ])
    }

    private func audioRecorderStopEvents(for mode: VoiceInkAudioRecorderStopMode) -> [String] {
        var events: [String] = []

        VoiceInkAudioRecorderStopPolicy.plan(for: mode).applyRuntimeState(
            stopRecorder: { events.append("stop") },
            invalidateMeterTimer: { events.append("timer") },
            setIsRecording: { events.append("recording:\($0)") },
            clearAudioLevels: { events.append("levels") },
            deleteCurrentRecordingFile: { events.append("delete") },
            clearCurrentRecordingURL: { events.append("url") },
            scheduleSessionDeactivation: { events.append("session") }
        )

        return events
    }

    func testNormalizedLevelClampsBelowAndAboveVisibleDecibelRange() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: -80), 0)
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: 0), 1)
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: 12), 1)
    }

    func testNormalizedLevelPreservesExistingMinusSixtyToZeroDecibelMapping() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: -60), 0)
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: -30), 0.5, accuracy: 0.0001)
        XCTAssertEqual(VoiceInkAudioMeterLevel.normalizedLevel(forDecibels: -15), 0.75, accuracy: 0.0001)
    }

    func testSmoothedLevelPreservesMacOSExponentialMovingAverageWeights() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75),
            0.45,
            accuracy: 0.0001
        )
    }

    func testSmoothedLevelClampsCustomPreviousWeight() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75, previousWeight: -1),
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75, previousWeight: 2),
            0.25,
            accuracy: 0.0001
        )
    }

    func testBoundedHistoryKeepsMostRecentLevels() {
        let history = VoiceInkAudioMeterLevel.boundedHistory(
            appending: 4,
            to: [1, 2, 3],
            limit: 3
        )

        XCTAssertEqual(history, [2, 3, 4])
    }

    func testBoundedHistoryRejectsNonPositiveLimit() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.boundedHistory(appending: 1, to: [0], limit: 0),
            []
        )
    }

    func testMacOSMeterUpdatePlanNormalizesAndSmoothsAverageAndPeak() {
        let plan = VoiceInkAudioMeterLevel.macOSMeterUpdatePlan(
            averageDecibels: -30,
            peakDecibels: -15,
            previousSmoothedAverage: 0.25,
            previousSmoothedPeak: 0.5
        )

        XCTAssertEqual(plan.smoothedAverage, 0.35, accuracy: 0.0001)
        XCTAssertEqual(plan.smoothedPeak, 0.6, accuracy: 0.0001)
    }

    func testIOSMeterHistoryUpdatePlanNormalizesAndBoundsHistory() {
        let plan = VoiceInkAudioMeterLevel.iOSMeterHistoryUpdatePlan(
            averageDecibels: -15,
            previousHistory: [0.1, 0.2, 0.3]
        )

        XCTAssertEqual(plan.normalizedLevel, 0.75, accuracy: 0.0001)
        XCTAssertEqual(plan.levelsHistory, [0.1, 0.2, 0.3, 0.75])

        let boundedPlan = VoiceInkAudioMeterLevel.iOSMeterHistoryUpdatePlan(
            averageDecibels: -60,
            previousHistory: Array(repeating: 0.5, count: VoiceInkAudioMeterLevel.defaultLevelHistoryLimit)
        )

        XCTAssertEqual(boundedPlan.levelsHistory.count, VoiceInkAudioMeterLevel.defaultLevelHistoryLimit)
        XCTAssertEqual(boundedPlan.levelsHistory.last, 0)
    }

    func testUpdateCadencesPreservePlatformAudioMeterBehavior() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSUpdateIntervalMilliseconds, 17)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSUpdateInterval, 0.1)
    }

    func testMacOSVisualizerGeometryPreservesExistingRecorderShape() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerAnimationMinimumInterval, 0.016)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerBarCount, 15)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerBarWidth, 3)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerBarSpacing, 2)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerMinimumBarHeight, 4)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerMaximumBarHeight, 28)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerPhaseStep, 0.4)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerWaveFrequency, 8)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerAmplitudeExponent, 0.7)
        XCTAssertEqual(VoiceInkAudioMeterLevel.macOSVisualizerCenterBoostDropoff, 0.4)
    }

    func testMacOSVisualizerBarHeightPreservesExistingWaveAndCenterBoost() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: 0,
                time: 0,
                averagePower: 1,
                isActive: true
            ),
            10.8571428571,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: 7,
                time: 0,
                averagePower: 1,
                isActive: true
            ),
            19.562147579,
            accuracy: 0.0001
        )
    }

    func testMacOSVisualizerBarHeightUsesMinimumForIdleOrInvalidBars() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: 7,
                time: 0,
                averagePower: 1,
                isActive: false
            ),
            VoiceInkAudioMeterLevel.macOSVisualizerMinimumBarHeight
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: -1,
                time: 0,
                averagePower: 1,
                isActive: true
            ),
            VoiceInkAudioMeterLevel.macOSVisualizerMinimumBarHeight
        )
    }

    func testIOSVisualizerBarPolicyPreservesGeometryInputs() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerBarCount, 8)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerBarSpacing, 3)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerBarMinimumWidth, 2)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerHorizontalPadding, 2)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerWidthInset, 16)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerFrameHeight, 48)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerMinimumBarHeight, 4)
        XCTAssertEqual(VoiceInkAudioMeterLevel.iOSVisualizerAnimationDuration, 0.12)
    }

    func testIOSVisualizerLevelSamplesRecentHistoryAndClampsLevels() {
        let levels: [Float] = [0.2, 0.5, 1.4, -0.3]

        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: levels, barCount: 4),
            0
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 1, levels: levels, barCount: 4),
            1
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 2, levels: levels, barCount: 4),
            0.5
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 3, levels: levels, barCount: 4),
            0.2
        )
    }

    func testIOSVisualizerLevelHandlesEmptyHistoryAndNonPositiveBarCount() {
        XCTAssertEqual(VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: []), 0)
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: [0.5], barCount: 0),
            0
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.visualizerLevel(forBarAt: -1, levels: [0.5], barCount: 1),
            0
        )
    }

    func testIOSVisualizerBarWidthPreservesExistingLayoutMath() {
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 96),
            7,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 24),
            VoiceInkAudioMeterLevel.iOSVisualizerBarMinimumWidth,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 96, barCount: 0),
            VoiceInkAudioMeterLevel.iOSVisualizerBarMinimumWidth,
            accuracy: 0.0001
        )
    }

    func testIOSVisualizerBarHeightPreservesExistingLevelMapping() {
        let levels: [Float] = [0.2, 0.5, 1.0]

        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 0,
                levels: levels,
                containerHeight: 48
            ),
            48,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 1,
                levels: levels,
                containerHeight: 48
            ),
            26,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VoiceInkAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 0,
                levels: [],
                containerHeight: 48
            ),
            VoiceInkAudioMeterLevel.iOSVisualizerMinimumBarHeight,
            accuracy: 0.0001
        )
    }

    func testRecordingFlowStatePreservesIOSStartFailureAndCancelTransitions() {
        var failedState = VoiceInkRecordingFlowState(currentDuration: 8)
        failedState.prepareRecordingStart()
        failedState.failRecordingStart()

        XCTAssertEqual(failedState.recordingState, .idle)
        XCTAssertFalse(failedState.animate)
        XCTAssertFalse(failedState.isRecordingSheetPresented)
        XCTAssertEqual(failedState.currentDuration, 8)

        var canceledState = VoiceInkRecordingFlowState(
            recordingState: .recording,
            animate: true,
            isRecordingSheetPresented: true,
            currentDuration: 4
        )
        canceledState.cancelRecording()

        XCTAssertEqual(canceledState.recordingState, .idle)
        XCTAssertFalse(canceledState.animate)
        XCTAssertFalse(canceledState.isRecordingSheetPresented)
        XCTAssertEqual(canceledState.currentDuration, 0)
    }

    func testAppGroupRecordingStatePolicyPreservesIOSStorageKeysAndTimeout() {
        XCTAssertEqual(VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording, "isRecording")
        XCTAssertEqual(VoiceInkAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp, "lastRecordingTimestamp")
        XCTAssertEqual(VoiceInkAppGroupRecordingStatePolicy.staleRecordingInterval, 30)
    }

    func testAppGroupRecordingStatePolicyKeepsFreshRecordingActive() {
        let state = VoiceInkAppGroupRecordingStatePolicy.state(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 129)
        )

        XCTAssertEqual(
            state,
            VoiceInkAppGroupRecordingState(isRecording: true, shouldClearStaleState: false)
        )
    }

    func testAppGroupRecordingStatePolicyClearsStaleRecording() {
        let state = VoiceInkAppGroupRecordingStatePolicy.state(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 131)
        )

        XCTAssertEqual(
            state,
            VoiceInkAppGroupRecordingState(isRecording: false, shouldClearStaleState: true)
        )
    }

    func testAppGroupRecordingStatePolicyDoesNotClearInactiveRecording() {
        let state = VoiceInkAppGroupRecordingStatePolicy.state(
            storedIsRecording: false,
            lastRecordingTimestamp: 0,
            now: Date(timeIntervalSince1970: 10_000)
        )

        XCTAssertEqual(
            state,
            VoiceInkAppGroupRecordingState(isRecording: false, shouldClearStaleState: false)
        )
    }

    func testAppGroupRecordingStateReadPlanDoesNotRepairFreshRecording() {
        let plan = VoiceInkAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 129)
        )

        var didRepair = false
        let state = plan.applyRuntimeState { _ in
            didRepair = true
        }

        XCTAssertEqual(
            state,
            VoiceInkAppGroupRecordingState(
                isRecording: true,
                shouldClearStaleState: false
            )
        )
        XCTAssertFalse(didRepair)
    }

    func testAppGroupRecordingStateReadPlanOwnsStaleRepairMutation() {
        let plan = VoiceInkAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 131)
        )

        var events: [String] = []
        let state = plan.applyRuntimeState { mutationPlan in
            mutationPlan.applyRuntimeState(
                applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events) },
                postDarwinNotification: { events.append("notify:\($0)") }
            )
        }

        XCTAssertEqual(
            state,
            VoiceInkAppGroupRecordingState(
                isRecording: false,
                shouldClearStaleState: true
            )
        )
        XCTAssertEqual(events, [
            "recording:false",
            "timestamp:131.0",
            "notify:\(VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName)"
        ])
    }

    func testAppGroupRecordingStateReadPlanAppliesStaleRepairRuntimeState() {
        var events: [String] = []

        let freshState = VoiceInkAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 129)
        ).applyRuntimeState { _ in
            events.append("fresh-repair")
        }
        events.append("fresh-state:\(freshState.isRecording)")

        let staleState = VoiceInkAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 131)
        ).applyRuntimeState { mutationPlan in
            mutationPlan.applyRuntimeState(
                applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events, prefix: "repair-") },
                postDarwinNotification: { events.append("repair-notify:\($0)") }
            )
        }
        events.append("stale-state:\(staleState.isRecording)")

        XCTAssertEqual(events, [
            "fresh-state:true",
            "repair-recording:false",
            "repair-timestamp:131.0",
            "repair-notify:\(VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName)",
            "stale-state:false"
        ])
    }

    func testAppGroupRecordingStateWritePlansPreserveIOSBridgeWrites() {
        var events: [String] = []

        VoiceInkAppGroupRecordingStatePolicy.stopRequestedWritePlan(
            now: Date(timeIntervalSince1970: 42)
        )
        .recordAppGroupWriteEvents(into: &events)

        VoiceInkAppGroupRecordingStatePolicy.recordingStateWritePlan(
            isRecording: true,
            now: Date(timeIntervalSince1970: 43)
        )
        .recordAppGroupWriteEvents(into: &events)

        XCTAssertEqual(events, [
            "timestamp:42.0",
            "recording:true",
            "timestamp:43.0"
        ])
    }

    func testAppGroupRecordingStateWritePlanAppliesRuntimeStateInOrder() {
        var events: [String] = []

        VoiceInkAppGroupRecordingStatePolicy.stopRequestedWritePlan(
            now: Date(timeIntervalSince1970: 42)
        )
        .recordAppGroupWriteEvents(into: &events)

        VoiceInkAppGroupRecordingStatePolicy.recordingStateWritePlan(
            isRecording: true,
            now: Date(timeIntervalSince1970: 43)
        )
        .recordAppGroupWriteEvents(into: &events)

        XCTAssertEqual(events, [
            "timestamp:42.0",
            "recording:true",
            "timestamp:43.0"
        ])
    }

    func testAppGroupRecordingStateMutationPlansPreserveIOSBridgeNotifications() {
        var events: [String] = []

        VoiceInkAppGroupRecordingStatePolicy.stopRequestedMutationPlan(
            now: Date(timeIntervalSince1970: 42)
        ).applyRuntimeState(
            applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events) },
            postDarwinNotification: { events.append("notify:\($0)") }
        )

        VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
            isRecording: true,
            now: Date(timeIntervalSince1970: 43)
        ).applyRuntimeState(
            applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events) },
            postDarwinNotification: { events.append("notify:\($0)") }
        )

        XCTAssertEqual(events, [
            "timestamp:42.0",
            "notify:\(VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName)",
            "recording:true",
            "timestamp:43.0",
            "notify:\(VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName)"
        ])
    }

    func testAppGroupRecordingStateMutationPlanAppliesRuntimeWriteBeforeNotification() {
        var events: [String] = []

        VoiceInkAppGroupRecordingStatePolicy.stopRequestedMutationPlan(
            now: Date(timeIntervalSince1970: 42)
        ).applyRuntimeState(
            applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events, prefix: "write-") },
            postDarwinNotification: {
                events.append("notify:\($0)")
            }
        )

        VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
            isRecording: true,
            now: Date(timeIntervalSince1970: 43)
        ).applyRuntimeState(
            applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events, prefix: "write-") },
            postDarwinNotification: {
                events.append("notify:\($0)")
            }
        )

        XCTAssertEqual(events, [
            "write-timestamp:42.0",
            "notify:\(VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName)",
            "write-recording:true",
            "write-timestamp:43.0",
            "notify:\(VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName)"
        ])
    }

    func testKeyboardRecordingTimingPreservesIOSAppAndKeyboardDelays() {
        XCTAssertEqual(VoiceInkKeyboardRecordingTiming.appLaunchRecordingStartDelay, 0.5)
        XCTAssertEqual(VoiceInkKeyboardRecordingTiming.recordingStatusPollingInterval, 0.5)
        XCTAssertEqual(VoiceInkKeyboardRecordingTiming.openAppFallbackResetDelay, 2.0)
    }

    func testLaunchRecordingRequestStartsImmediatelyWhenOnboardingIsComplete() {
        var state = VoiceInkLaunchRecordingRequestState()
        var events: [String] = []

        state.requestRecording(hasCompletedOnboarding: true).applyRuntimeState {
            events.append("start")
        }

        XCTAssertEqual(events, ["start"])
        XCTAssertFalse(state.hasPendingRecordingAfterOnboarding)
    }

    func testLaunchRecordingRequestDefersUntilOnboardingCompletes() {
        var state = VoiceInkLaunchRecordingRequestState()
        var events: [String] = []

        state.requestRecording(hasCompletedOnboarding: false).applyRuntimeState {
            events.append("start")
        }
        XCTAssertTrue(state.hasPendingRecordingAfterOnboarding)

        state.consumePendingRecordingIfReady(hasCompletedOnboarding: false).applyRuntimeState {
            events.append("start")
        }
        XCTAssertTrue(state.hasPendingRecordingAfterOnboarding)

        state.consumePendingRecordingIfReady(hasCompletedOnboarding: true).applyRuntimeState {
            events.append("start")
        }

        XCTAssertEqual(events, ["start"])
        XCTAssertFalse(state.hasPendingRecordingAfterOnboarding)
    }

    func testLaunchRecordingRequestNoOpsWhenNothingIsPending() {
        var state = VoiceInkLaunchRecordingRequestState()
        var events: [String] = []

        state.consumePendingRecordingIfReady(hasCompletedOnboarding: true).applyRuntimeState {
            events.append("start")
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testLaunchRecordingRequestClearsPendingStateWhenRecordingCanStartNow() {
        var state = VoiceInkLaunchRecordingRequestState(
            hasPendingRecordingAfterOnboarding: true
        )
        var events: [String] = []

        state.requestRecording(hasCompletedOnboarding: true).applyRuntimeState {
            events.append("start")
        }

        XCTAssertEqual(events, ["start"])
        XCTAssertFalse(state.hasPendingRecordingAfterOnboarding)
    }

    func testKeyboardRecordingButtonPresentationPreservesIOSCopyAndIcons() {
        XCTAssertEqual(
            VoiceInkKeyboardRecordingButtonPresentation.idle,
            VoiceInkKeyboardRecordingButtonPresentation(title: " Record", systemImageName: "mic.fill")
        )
        XCTAssertEqual(
            VoiceInkKeyboardRecordingButtonPresentation.recording,
            VoiceInkKeyboardRecordingButtonPresentation(title: " Stop", systemImageName: "stop.fill")
        )
        XCTAssertEqual(
            VoiceInkKeyboardRecordingButtonPresentation.openAppFallback,
            VoiceInkKeyboardRecordingButtonPresentation(
                title: " Open \(VoiceInkAppIdentity.displayName)",
                systemImageName: "app"
            )
        )
    }

    func testKeyboardRecordingButtonPresentationSelectsCurrentState() {
        XCTAssertEqual(VoiceInkKeyboardRecordingButtonPresentation.current(isRecording: false), .idle)
        XCTAssertEqual(VoiceInkKeyboardRecordingButtonPresentation.current(isRecording: true), .recording)
    }

    func testKeyboardRecordingButtonTapPlanAppliesRuntimeState() {
        var events: [String] = []

        VoiceInkKeyboardRecordingButtonTapPolicy.plan(isRecording: true).applyRuntimeState(
            requestStopRecording: { events.append("stop") },
            openMainAppForRecording: { events.append("open") },
            refreshButtonState: { events.append("refresh") }
        )
        VoiceInkKeyboardRecordingButtonTapPolicy.plan(isRecording: false).applyRuntimeState(
            requestStopRecording: { events.append("stop") },
            openMainAppForRecording: { events.append("open") },
            refreshButtonState: { events.append("refresh") }
        )

        XCTAssertEqual(events, ["stop", "refresh", "open"])
    }

    func testKeyboardOpenAppPlansApplyDiagnosticsAndRuntimeState() {
        var events: [String] = []

        func apply(_ plan: VoiceInkKeyboardOpenAppActionPlan) {
            plan.applyRuntimeState(
                logNotice: { events.append("notice:\($0)") },
                logError: { events.append("error:\($0)") },
                openExtensionContext: { events.append("extension") },
                openThroughApplicationOrResponderChain: { events.append("fallbackChain") },
                finish: { events.append("finish") },
                showFallback: { events.append("fallback") }
            )
        }

        func apply(_ plan: VoiceInkKeyboardOpenAppResponderActionPlan) {
            plan.applyRuntimeState(
                logNotice: { events.append("notice:\($0)") },
                logError: { events.append("error:\($0)") },
                performResponderChainOpen: { events.append("responder") },
                showFallback: { events.append("responderFallback") }
            )
        }

        func apply(_ plan: VoiceInkKeyboardOpenAppApplicationActionPlan) {
            plan.applyRuntimeState(
                openViaApplication: { events.append("application") },
                openViaResponderChain: { events.append("responderChain") }
            )
        }

        apply(VoiceInkKeyboardOpenAppPolicy.initialActionPlan(hasExtensionContext: true))
        apply(VoiceInkKeyboardOpenAppPolicy.initialActionPlan(hasExtensionContext: false))
        apply(VoiceInkKeyboardOpenAppPolicy.applicationActionPlan(canOpenURL: true))
        apply(VoiceInkKeyboardOpenAppPolicy.applicationActionPlan(canOpenURL: false))
        apply(VoiceInkKeyboardOpenAppPolicy.actionPlanAfterExtensionContextOpen(succeeded: true))
        apply(VoiceInkKeyboardOpenAppPolicy.actionPlanAfterExtensionContextOpen(succeeded: false))
        apply(VoiceInkKeyboardOpenAppPolicy.actionPlanAfterApplicationOpen(succeeded: true))
        apply(VoiceInkKeyboardOpenAppPolicy.actionPlanAfterApplicationOpen(succeeded: false))
        apply(VoiceInkKeyboardOpenAppPolicy.responderActionPlan(hasResponder: true))
        apply(VoiceInkKeyboardOpenAppPolicy.responderActionPlan(hasResponder: false))

        XCTAssertEqual(events, [
            "extension",
            "error:\(VoiceInkKeyboardOpenAppDiagnostics.extensionContextUnavailable)",
            "fallbackChain",
            "application",
            "responderChain",
            "notice:\(VoiceInkKeyboardOpenAppDiagnostics.openedViaExtensionContext)",
            "finish",
            "error:\(VoiceInkKeyboardOpenAppDiagnostics.extensionContextOpenFailed)",
            "fallbackChain",
            "notice:\(VoiceInkKeyboardOpenAppDiagnostics.openedViaApplication)",
            "finish",
            "error:\(VoiceInkKeyboardOpenAppDiagnostics.applicationOpenFailed)",
            "fallback",
            "responder",
            "notice:\(VoiceInkKeyboardOpenAppDiagnostics.attemptedViaResponderChain)",
            "error:\(VoiceInkKeyboardOpenAppDiagnostics.allMethodsFailed)",
            "responderFallback"
        ])
    }

    func testKeyboardOpenAppDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppDiagnostics.extensionContextUnavailable,
            "extensionContext unavailable, trying alternative methods"
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppDiagnostics.openedViaExtensionContext,
            "Opened main app via extensionContext"
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppDiagnostics.extensionContextOpenFailed,
            "extensionContext.open failed, trying alternative methods"
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppDiagnostics.openedViaApplication,
            "Opened main app via UIApplication.open"
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppDiagnostics.applicationOpenFailed,
            "UIApplication.open failed"
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppDiagnostics.attemptedViaResponderChain,
            "Attempted to open main app via responder chain"
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppDiagnostics.allMethodsFailed,
            "All URL opening methods failed"
        )
    }

    func testKeyboardStopRecordingRequestPlanHandlesOnlyActiveRecording() {
        var handledStates: [VoiceInkRecordingState] = []

        for state in [
            VoiceInkRecordingState.recording,
            VoiceInkRecordingState.idle,
            .starting,
            .transcribing,
            .enhancing,
            .busy
        ] {
            VoiceInkKeyboardStopRecordingRequestPolicy.plan(recordingState: state)
                .applyRuntimeState {
                    handledStates.append(state)
                }
        }

        XCTAssertEqual(handledStates, [.recording])
    }

    func testRecorderStylePreferencePreservesMacOSStorageAndLabels() {
        XCTAssertEqual(VoiceInkRecorderStylePreference.userDefaultsKey, "RecorderType")
        XCTAssertEqual(VoiceInkRecorderStylePreference.defaultStyle, .none)
        XCTAssertEqual(VoiceInkRecorderStylePreference.defaultRawValue, "none")
        XCTAssertEqual(VoiceInkRecorderStyle.allCases, [.none, .notch, .mini])
        XCTAssertEqual(VoiceInkRecorderStyle.none.displayName, "None")
        XCTAssertEqual(VoiceInkRecorderStyle.notch.displayName, "Notch")
        XCTAssertEqual(VoiceInkRecorderStyle.mini.displayName, "Mini")
        XCTAssertEqual(VoiceInkRecorderStylePreference.macOSSettingsPresentation.sectionTitle, "Interface")
        XCTAssertEqual(VoiceInkRecorderStylePreference.macOSSettingsPresentation.pickerTitle, "Recorder Style")
    }

    func testRecorderStylePreferenceReadsAndSavesRawValues() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkRecorderStylePreference.rawValue(from: defaults), "none")

            VoiceInkRecorderStylePreference.saveRawValue("notch", to: defaults)
            XCTAssertEqual(VoiceInkRecorderStylePreference.rawValue(from: defaults), "notch")

            VoiceInkRecorderStylePreference.saveRawValue("future-style", to: defaults)
            XCTAssertEqual(VoiceInkRecorderStylePreference.rawValue(from: defaults), "future-style")
        }
    }

    func testRecorderStyleWindowKindPreservesMacOSUnknownStyleFallback() {
        XCTAssertEqual(VoiceInkRecorderStylePreference.windowKind(forRawValue: "none"), .none)
        XCTAssertEqual(VoiceInkRecorderStylePreference.windowKind(forRawValue: "notch"), .notch)
        XCTAssertEqual(VoiceInkRecorderStylePreference.windowKind(forRawValue: "mini"), .mini)
        XCTAssertEqual(VoiceInkRecorderStylePreference.windowKind(forRawValue: "future-style"), .mini)
        XCTAssertFalse(VoiceInkRecorderStylePreference.hasVisibleRecorder(rawValue: "none"))
        XCTAssertTrue(VoiceInkRecorderStylePreference.hasVisibleRecorder(rawValue: "notch"))
        XCTAssertTrue(VoiceInkRecorderStylePreference.hasVisibleRecorder(rawValue: "mini"))
        XCTAssertTrue(VoiceInkRecorderStylePreference.hasVisibleRecorder(rawValue: "future-style"))
    }

    func testRecorderStyleWindowRuntimeStatePreservesMacOSUnknownStyleFallback() {
        var events: [String] = []

        for rawValue in ["none", "notch", "mini", "future-style"] {
            VoiceInkRecorderStylePreference.applyWindowRuntimeState(
                forRawValue: rawValue,
                none: { events.append("\(rawValue):none") },
                notch: { events.append("\(rawValue):notch") },
                mini: { events.append("\(rawValue):mini") }
            )
        }

        XCTAssertEqual(events, [
            "none:none",
            "notch:notch",
            "mini:mini",
            "future-style:mini"
        ])
    }

    func testRecorderSessionShortcutPolicyKeepsHiddenIdleRecorderInactive() {
        XCTAssertFalse(
            VoiceInkRecorderUISessionPolicy.isActiveForRecordingShortcut(
                hasVisibleRecorderType: false,
                recordingState: .idle,
                isRecorderSessionActive: true
            )
        )
        XCTAssertTrue(
            VoiceInkRecorderUISessionPolicy.isActiveForRecordingShortcut(
                hasVisibleRecorderType: false,
                recordingState: .recording,
                isRecorderSessionActive: true
            )
        )
        XCTAssertTrue(
            VoiceInkRecorderUISessionPolicy.isActiveForRecordingShortcut(
                hasVisibleRecorderType: true,
                recordingState: .idle,
                isRecorderSessionActive: true
            )
        )
        XCTAssertFalse(
            VoiceInkRecorderUISessionPolicy.isActiveForRecordingShortcut(
                hasVisibleRecorderType: true,
                recordingState: .recording,
                isRecorderSessionActive: false
            )
        )
    }

    func testRecorderSessionPolicyClearsOnlyStaleHiddenIdleSessions() {
        XCTAssertTrue(
            VoiceInkRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
                hasVisibleRecorderType: false,
                recordingState: .idle,
                isRecorderSessionActive: true
            )
        )
        XCTAssertFalse(
            VoiceInkRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
                hasVisibleRecorderType: false,
                recordingState: .recording,
                isRecorderSessionActive: true
            )
        )
        XCTAssertFalse(
            VoiceInkRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
                hasVisibleRecorderType: true,
                recordingState: .idle,
                isRecorderSessionActive: true
            )
        )
        XCTAssertFalse(
            VoiceInkRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
                hasVisibleRecorderType: false,
                recordingState: .idle,
                isRecorderSessionActive: false
            )
        )
    }

    func testRecordingStartPlanStartsOrPresentsNoModeAlert() {
        var events: [String] = []

        VoiceInkRecordingStartPolicy.plan(modeCount: 1).applyRuntimeState(
            startRecording: { events.append("start") },
            presentAlert: { alert in events.append("alert:\(alert.id)") }
        )
        VoiceInkRecordingStartPolicy.plan(modeCount: 0).applyRuntimeState(
            startRecording: { events.append("start") },
            presentAlert: { alert in events.append("alert:\(alert.id)") }
        )

        XCTAssertEqual(events, ["start", "alert:noModesAvailable"])

        var presentedAlert: VoiceInkRecordingAlertPresentation?
        VoiceInkRecordingStartPolicy.plan(modeCount: 0).applyRuntimeState(
            startRecording: {},
            presentAlert: { presentedAlert = $0 }
        )

        guard let alert = presentedAlert else {
            XCTFail("Expected no-modes alert")
            return
        }
        XCTAssertEqual(alert.id, "noModesAvailable")
        XCTAssertEqual(alert.title, "No Modes Found")
        XCTAssertEqual(alert.message, "Please create a new mode in Settings before recording.")
        XCTAssertEqual(alert.primaryButtonTitle, "OK")
        XCTAssertNil(alert.secondaryButtonTitle)
        XCTAssertNil(alert.runtimeAction(openSettings: {}))
    }

    func testRecordingAlertPresentationBuildsDeferredRuntimeAction() {
        var didOpenSettings = false
        XCTAssertNil(VoiceInkRecordingAlertPresentation.noModesAvailable.runtimeAction {
            didOpenSettings = true
        })
        XCTAssertFalse(didOpenSettings)

        let action = VoiceInkRecordingAlertPresentation.microphonePermissionDenied.runtimeAction {
            didOpenSettings = true
        }
        XCTAssertFalse(didOpenSettings)

        action?()
        XCTAssertTrue(didOpenSettings)
    }

    func testRecordingNotificationPresentationPreservesMacOSStartFailureCopy() {
        XCTAssertEqual(
            VoiceInkRecordingNotificationPresentation.noTranscriptionModelSelected.title,
            "No AI Model Selected"
        )
        XCTAssertEqual(VoiceInkRecordingNotificationPresentation.noTranscriptionModelSelected.duration, 3.0)
        XCTAssertNil(VoiceInkRecordingNotificationPresentation.noTranscriptionModelSelected.actionButtonTitle)

        XCTAssertEqual(
            VoiceInkRecordingNotificationPresentation.failedToStart.title,
            "Recording failed to start"
        )
        XCTAssertEqual(VoiceInkRecordingNotificationPresentation.failedToStart.duration, 3.0)
        XCTAssertNil(VoiceInkRecordingNotificationPresentation.failedToStart.actionButtonTitle)

        XCTAssertEqual(
            VoiceInkRecordingNotificationPresentation.microphonePermissionRequired.title,
            "Microphone permission required"
        )
        XCTAssertEqual(VoiceInkRecordingNotificationPresentation.microphonePermissionRequired.duration, 8.0)
        XCTAssertEqual(VoiceInkRecordingNotificationPresentation.microphonePermissionRequired.actionButtonTitle, "Grant")
    }

    func testRecordingNotificationPresentationPreservesMacOSRuntimeFailureCopy() {
        let presentation = VoiceInkRecordingNotificationPresentation.runtimeFailure(
            localizedDescription: "Device disconnected"
        )

        XCTAssertEqual(
            presentation.title,
            "Recording Failed: Device disconnected"
        )
        XCTAssertEqual(presentation.duration, 3.0)
        XCTAssertNil(presentation.actionButtonTitle)
    }

    func testRecordingStartFailureMapsIOSMicrophoneBusyOSStatus() {
        let alert = VoiceInkRecordingAlertPresentation.recordingStartFailure(
            domain: NSOSStatusErrorDomain,
            code: VoiceInkRecordingAlertPresentation.microphoneInUseOSStatusCode,
            localizedDescription: "The operation couldn’t be completed."
        )

        XCTAssertEqual(alert.id, "microphoneInUse")
        XCTAssertEqual(alert.title, "Microphone In Use")
        XCTAssertEqual(alert.message, "Another app is using the microphone. Please try again.")
        XCTAssertEqual(alert.primaryButtonTitle, "OK")
        XCTAssertNil(alert.runtimeAction(openSettings: {}))
    }

    func testRecordingStartFailurePreservesIOSRecorderStartReturnedFalseReason() {
        XCTAssertEqual(
            VoiceInkRecordingAlertPresentation.iOSRecorderStartReturnedFalseDescription,
            "Failed to start AVAudioRecorder. The record() method returned false. This often happens in the background if the audio session is not configured correctly or if there is a conflict with another app."
        )

        let error = VoiceInkAudioRecorderStartFailurePolicy.returnedFalseError()
        let alert = VoiceInkRecordingAlertPresentation.recordingStartFailure(
            domain: error.domain,
            code: error.code,
            localizedDescription: error.localizedDescription
        )

        XCTAssertEqual(alert.title, "Recording Failed")
        XCTAssertEqual(
            alert.message,
            "Could not start recording: \(VoiceInkRecordingAlertPresentation.iOSRecorderStartReturnedFalseDescription)"
        )
    }

    func testAudioRecorderStartFailurePolicyBuildsIOSReturnedFalseError() {
        let error = VoiceInkAudioRecorderStartFailurePolicy.returnedFalseError()

        XCTAssertEqual(error.domain, VoiceInkAppIdentity.errorDomain(component: "AudioRecorder"))
        XCTAssertEqual(error.code, VoiceInkAudioRecorderStartFailurePolicy.returnedFalseErrorCode)
        XCTAssertEqual(error.userInfo[NSLocalizedDescriptionKey] as? String, VoiceInkAudioRecorderStartFailurePolicy.returnedFalseDescription)
        XCTAssertEqual(error.localizedDescription, VoiceInkAudioRecorderStartFailurePolicy.returnedFalseDescription)
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.RecordingStatePolicyTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        run(defaults)
    }

    func testAudioInputModePreservesRawValuesDefaultAndOrder() {
        XCTAssertEqual(VoiceInkAudioInputMode.systemDefault.rawValue, "System Default")
        XCTAssertEqual(VoiceInkAudioInputMode.custom.rawValue, "Custom Device")
        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.rawValue, "Prioritized")
        XCTAssertEqual(VoiceInkAudioInputMode.defaultMode, .custom)
        XCTAssertEqual(VoiceInkAudioInputMode.allCases, [.systemDefault, .custom, .prioritized])
    }

    func testAudioInputPreferencePreservesStorageKeysDefaultsAndRoundTrips() {
        XCTAssertEqual(VoiceInkAudioInputPreference.inputModeKey, "audioInputMode")
        XCTAssertEqual(VoiceInkAudioInputPreference.selectedDeviceUIDKey, "selectedAudioDeviceUID")
        XCTAssertEqual(VoiceInkAudioInputPreference.prioritizedDevicesKey, "prioritizedDevices")
        XCTAssertEqual(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceIDKey, "lastUsedMicrophoneDeviceID")
        XCTAssertEqual(
            VoiceInkAudioInputPreference.registeredDefaults[VoiceInkAudioInputPreference.inputModeKey] as? String,
            VoiceInkAudioInputMode.defaultMode.rawValue
        )

        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkAudioInputPreference.inputMode(from: defaults), .custom)

            defaults.set("invalid", forKey: VoiceInkAudioInputPreference.inputModeKey)
            XCTAssertEqual(VoiceInkAudioInputPreference.inputMode(from: defaults), .custom)

            VoiceInkAudioInputPreference.saveInputMode(.prioritized, to: defaults)
            XCTAssertEqual(VoiceInkAudioInputPreference.inputMode(from: defaults), .prioritized)

            XCTAssertNil(VoiceInkAudioInputPreference.selectedDeviceUID(from: defaults))
            VoiceInkAudioInputPreference.saveSelectedDeviceUID("usb-mic", to: defaults)
            XCTAssertEqual(VoiceInkAudioInputPreference.selectedDeviceUID(from: defaults), "usb-mic")
            VoiceInkAudioInputPreference.clearSelectedDeviceUID(from: defaults)
            XCTAssertNil(VoiceInkAudioInputPreference.selectedDeviceUID(from: defaults))

            let devices = [
                VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1)
            ]

            XCTAssertEqual(VoiceInkAudioInputPreference.prioritizedDevices(from: defaults), [])
            VoiceInkAudioInputPreference.savePrioritizedDevices(devices, to: defaults)
            XCTAssertEqual(VoiceInkAudioInputPreference.prioritizedDevices(from: defaults), devices)

            XCTAssertNil(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
            XCTAssertTrue(VoiceInkAudioInputPreference.shouldAnnounceMicrophoneChange(to: "123", in: defaults))
            VoiceInkAudioInputPreference.saveLastUsedMicrophoneDeviceID("123", to: defaults)
            XCTAssertEqual(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults), "123")
            XCTAssertFalse(VoiceInkAudioInputPreference.shouldAnnounceMicrophoneChange(to: "123", in: defaults))
            XCTAssertTrue(VoiceInkAudioInputPreference.shouldAnnounceMicrophoneChange(to: "456", in: defaults))
            VoiceInkAudioInputPreference.clearLastUsedMicrophoneDeviceID(from: defaults)
            XCTAssertNil(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
        }
    }

    func testMacOSAudioDeviceChangeRequestPreservesNotificationContract() {
        XCTAssertEqual(
            VoiceInkMacOSAudioDeviceChangeRequest.deviceChangedNotificationName.rawValue,
            "AudioDeviceChanged"
        )
        XCTAssertEqual(
            VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredNotificationName.rawValue,
            "audioDeviceSwitchRequired"
        )
        XCTAssertEqual(VoiceInkMacOSAudioDeviceChangeRequest.newDeviceIDUserInfoKey, "newDeviceID")

        let userInfo = VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredUserInfo(deviceID: 42)
        XCTAssertEqual(userInfo[VoiceInkMacOSAudioDeviceChangeRequest.newDeviceIDUserInfoKey] as? UInt32, 42)

        let notification = Notification(
            name: VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredNotificationName,
            userInfo: userInfo
        )
        XCTAssertEqual(VoiceInkMacOSAudioDeviceChangeRequest.newDeviceID(from: notification), 42)
        XCTAssertNil(
            VoiceInkMacOSAudioDeviceChangeRequest.newDeviceID(
                from: Notification(name: VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredNotificationName)
            )
        )
    }

    func testAudioInputModePreservesSettingsPresentation() {
        XCTAssertEqual(VoiceInkAudioInputMode.systemDefault.title, "System Default")
        XCTAssertEqual(VoiceInkAudioInputMode.systemDefault.iconSystemName, "display")
        XCTAssertEqual(VoiceInkAudioInputMode.systemDefault.description, "Use your Mac's default input")

        XCTAssertEqual(VoiceInkAudioInputMode.custom.title, "Custom Device")
        XCTAssertEqual(VoiceInkAudioInputMode.custom.iconSystemName, "mic.circle.fill")
        XCTAssertEqual(VoiceInkAudioInputMode.custom.description, "Select a specific input device")

        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.title, "Prioritized")
        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.iconSystemName, "list.number")
        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.description, "Set up device priority order")
    }

    func testMacOSAudioInputSettingsPresentationFormatsPriorityDisplay() {
        let presentation = VoiceInkMacOSAudioInputSettingsPresentation.macOS

        XCTAssertEqual(presentation.priorityDisplayText(for: 0), "1")
        XCTAssertEqual(presentation.priorityDisplayText(for: 4), "5")
    }

    func testAddingPriorityDeviceAppendsNextPriorityAndKeepsDuplicatesNoOp() {
        let existing = [
            VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 3)
        ]

        let added = VoiceInkAudioInputPriorityPolicy.addDevice(
            uid: "studio",
            name: "Studio Mic",
            to: existing
        )

        XCTAssertEqual(
            added,
            existing + [
                VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 4)
            ]
        )
        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.addDevice(uid: "usb", name: "Duplicate", to: existing),
            existing
        )
    }

    func testRemovingPriorityDeviceReindexesRemainingDevices() {
        let devices = [
            VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1),
            VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.removeDevice(id: "usb", from: devices),
            [
                VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 1)
            ]
        )
    }

    func testMovingPriorityDeviceSwapsAndReindexesWithinBounds() {
        let devices = [
            VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1),
            VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.moveDevice(id: "studio", direction: .up, in: devices),
            [
                VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 1),
                VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 2)
            ]
        )
        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.moveDevice(id: "built-in", direction: .down, in: devices),
            [
                VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 0),
                VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 1),
                VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
            ]
        )
        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.moveDevice(id: "built-in", direction: .up, in: devices),
            devices
        )
        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.moveDevice(id: "missing", direction: .down, in: devices),
            devices
        )
    }

    func testFirstAvailablePriorityDeviceUsesPriorityOrder() {
        let devices = [
            VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2),
            VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: devices,
                availableDeviceIDs: ["studio", "usb"]
            ),
            "usb"
        )
        XCTAssertNil(
            VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: devices,
                availableDeviceIDs: []
            )
        )
    }

    func testAutomaticSelectionPolicyPreservesBuiltInDetection() {
        XCTAssertEqual(VoiceInkAudioInputAutomaticSelectionPolicy.builtInUIDMarker, "BuiltIn")
        XCTAssertEqual(VoiceInkAudioInputAutomaticSelectionPolicy.unsafeAirPodsNameMarker, "airpods")
        XCTAssertTrue(VoiceInkAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: true,
            uid: nil
        ))
        XCTAssertTrue(VoiceInkAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: false,
            uid: "AppleUSBAudioEngine:BuiltInMicrophone"
        ))
        XCTAssertFalse(VoiceInkAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: false,
            uid: "external-usb-mic"
        ))
    }

    func testAutomaticSelectionPolicyPreservesSafeDeviceClassification() {
        XCTAssertTrue(VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "MacBook Microphone",
            isBuiltIn: true,
            isBluetooth: true
        ))
        XCTAssertTrue(VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "USB Studio Mic",
            isBuiltIn: false,
            isBluetooth: false
        ))
        XCTAssertFalse(VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "Bluetooth Headset",
            isBuiltIn: false,
            isBluetooth: true
        ))
        XCTAssertFalse(VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "Felix AirPods Pro",
            isBuiltIn: false,
            isBluetooth: false
        ))
    }

    func testAutomaticSelectionPolicyPrefersSafePreferredDevice() {
        let devices = [
            VoiceInkAudioInputAutomaticDevice(id: "built-in", name: "Built-in", isBuiltIn: true, isBluetooth: false),
            VoiceInkAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(preferred: "usb", devices: devices),
            VoiceInkAudioInputAutomaticSelection(deviceID: "usb", reason: .preferred)
        )
    }

    func testAutomaticSelectionPolicyFallsBackToBuiltInBeforeOtherSafeDevices() {
        let devices = [
            VoiceInkAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false),
            VoiceInkAudioInputAutomaticDevice(id: "built-in", name: "Built-in", isBuiltIn: true, isBluetooth: false)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(preferred: "missing", devices: devices),
            VoiceInkAudioInputAutomaticSelection(deviceID: "built-in", reason: .builtIn)
        )
    }

    func testAutomaticSelectionPolicyUsesSafeFallbackWhenBuiltInUnavailable() {
        let devices = [
            VoiceInkAudioInputAutomaticDevice(id: "airpods", name: "AirPods", isBuiltIn: false, isBluetooth: true),
            VoiceInkAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(devices: devices),
            VoiceInkAudioInputAutomaticSelection(deviceID: "usb", reason: .safeFallback)
        )
    }

    func testAutomaticSelectionPolicyRefusesUnsafeAutomaticDevices() {
        let devices = [
            VoiceInkAudioInputAutomaticDevice(id: "airpods", name: "AirPods", isBuiltIn: false, isBluetooth: false),
            VoiceInkAudioInputAutomaticDevice(id: "headset", name: "Bluetooth Headset", isBuiltIn: false, isBluetooth: true)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(preferred: "headset", devices: devices),
            VoiceInkAudioInputAutomaticSelection<String>(deviceID: nil, reason: .unavailable)
        )
    }

    func testSelectionPolicyResolvesCurrentDeviceByMode() {
        let availableDevices = [
            VoiceInkAudioInputAvailableDevice(id: "built-in", uid: "built-in-uid", name: "Built-in"),
            VoiceInkAudioInputAvailableDevice(id: "usb", uid: "usb-uid", name: "USB Mic")
        ]
        let priorityDevices = [
            VoiceInkAudioInputPriorityDevice(id: "usb-uid", name: "USB Mic", priority: 1),
            VoiceInkAudioInputPriorityDevice(id: "built-in-uid", name: "Built-in", priority: 2)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .systemDefault,
                selectedDeviceID: "usb",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic",
                systemDefaultDeviceID: "system-default"
            ),
            "system-default"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .systemDefault,
                selectedDeviceID: "usb",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic",
                systemDefaultDeviceID: nil
            ),
            "automatic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: "usb",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "usb"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: "missing",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: nil,
                selectedDeviceIsAvailable: true,
                priorityDeviceID: nil,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .prioritized,
                selectedDeviceID: "built-in",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "usb"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .prioritized,
                selectedDeviceID: "built-in",
                prioritizedDevices: [
                    VoiceInkAudioInputPriorityDevice(id: "missing-uid", name: "Missing", priority: 0)
                ],
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
    }

    func testSelectionPolicyPreservesModeChangeSelectionBehavior() {
        let availableDevices = [
            VoiceInkAudioInputAvailableDevice(id: 1, uid: "built-in-uid", name: "Built-in"),
            VoiceInkAudioInputAvailableDevice(id: 2, uid: "usb-uid", name: "USB Mic")
        ]
        let priorityDevices = [
            VoiceInkAudioInputPriorityDevice(id: "usb-uid", name: "USB Mic", priority: 0)
        ]

        XCTAssertNil(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: 1,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            )
        )
        XCTAssertNil(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .systemDefault,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            )
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .custom,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            1
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            2
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: nil,
                prioritizedDevices: [
                    VoiceInkAudioInputPriorityDevice(id: "missing-uid", name: "Missing", priority: 0)
                ],
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            1
        )
    }

    func testSelectionPolicyPlansRecordingDeviceSwitches() {
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .prioritized,
                priorityDeviceID: "usb",
                automaticDeviceID: "automatic"
            ),
            VoiceInkAudioInputRecordingSwitchPlan(deviceID: "usb", usedPriorityFallback: false)
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .prioritized,
                priorityDeviceID: nil,
                automaticDeviceID: "automatic"
            ),
            VoiceInkAudioInputRecordingSwitchPlan(deviceID: "automatic", usedPriorityFallback: true)
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .custom,
                priorityDeviceID: "usb",
                automaticDeviceID: "automatic"
            ),
            VoiceInkAudioInputRecordingSwitchPlan(deviceID: "automatic", usedPriorityFallback: false)
        )
    }

}

private extension VoiceInkAppGroupRecordingStateWritePlan {
    func recordAppGroupWriteEvents(into events: inout [String], prefix: String = "") {
        applyRuntimeState(
            setIsRecording: { events.append("\(prefix)recording:\($0)") },
            setLastRecordingTimestamp: { events.append("\(prefix)timestamp:\($0)") }
        )
    }
}
