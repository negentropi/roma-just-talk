import Foundation
@testable import RomaCore

final class RecordingStatePolicyTests: XCTestCase {
    func testActiveRecordingPolicyOnlyAllowsRecordingState() {
        XCTAssertFalse(RomaRecordingState.idle.isActivelyRecording)
        XCTAssertFalse(RomaRecordingState.starting.isActivelyRecording)
        XCTAssertTrue(RomaRecordingState.recording.isActivelyRecording)
        XCTAssertFalse(RomaRecordingState.transcribing.isActivelyRecording)
        XCTAssertFalse(RomaRecordingState.enhancing.isActivelyRecording)
        XCTAssertFalse(RomaRecordingState.busy.isActivelyRecording)
    }

    func testRecorderCaptureStatePolicyPreservesMacOSCancellationPath() {
        XCTAssertFalse(RomaRecordingState.idle.isRecorderCaptureInProgress)
        XCTAssertTrue(RomaRecordingState.starting.isRecorderCaptureInProgress)
        XCTAssertTrue(RomaRecordingState.recording.isRecorderCaptureInProgress)
        XCTAssertFalse(RomaRecordingState.transcribing.isRecorderCaptureInProgress)
        XCTAssertFalse(RomaRecordingState.enhancing.isRecorderCaptureInProgress)
        XCTAssertFalse(RomaRecordingState.busy.isRecorderCaptureInProgress)
    }

    func testMacOSRecordingStartupOverlapsStreamingWhenPowerModeCannotChangeSession() {
        let plan = RomaMacOSRecordingStartupOrchestrationPolicy.plan(
            powerModeConfigurationCount: 0
        )

        XCTAssertFalse(plan.shouldResolvePowerMode)
        XCTAssertTrue(plan.shouldPrepareTranscriptionSessionBeforeRecorder)
    }

    func testMacOSRecordingStartupDefersStreamingWhenPowerModeCanChangeSession() {
        let plan = RomaMacOSRecordingStartupOrchestrationPolicy.plan(
            powerModeConfigurationCount: 1
        )

        XCTAssertTrue(plan.shouldResolvePowerMode)
        XCTAssertFalse(plan.shouldPrepareTranscriptionSessionBeforeRecorder)
    }

    func testRecordingShortcutActionGatePreservesMacOSBusyStatePolicy() {
        XCTAssertTrue(RomaRecordingState.idle.acceptsRecordingShortcutAction)
        XCTAssertTrue(RomaRecordingState.starting.acceptsRecordingShortcutAction)
        XCTAssertTrue(RomaRecordingState.recording.acceptsRecordingShortcutAction)
        XCTAssertFalse(RomaRecordingState.transcribing.acceptsRecordingShortcutAction)
        XCTAssertFalse(RomaRecordingState.enhancing.acceptsRecordingShortcutAction)
        XCTAssertFalse(RomaRecordingState.busy.acceptsRecordingShortcutAction)
    }

    func testRecorderUITogglePlanAppliesMacOSRuntimeStateMapping() async {
        var events: [String] = []

        for state in [
            RomaRecordingState.idle,
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

        RomaRecordingPermissionPolicy.plan(for: .granted).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        RomaRecordingPermissionPolicy.plan(for: .denied).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        RomaRecordingPermissionPolicy.plan(for: .undetermined).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        RomaRecordingPermissionPolicy.plan(for: .undetermined).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(false)
            }
        )
        RomaRecordingPermissionPolicy.plan(afterPermissionRequestGranted: true).applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(false)
            }
        )
        RomaRecordingPermissionPolicy.plan(afterPermissionRequestGranted: false).applyRuntimeState(
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
            RomaRecordingPermissionPolicy.settingsOpenPlan(
                settingsURL: input.settingsURL,
                canOpenURL: { _ in input.canOpenSettingsURL }
            ).applyRuntimeState { url in
                events.append("open:\(url.absoluteString)")
            }
        }

        XCTAssertEqual(events, ["open:app-settings:"])
    }

    func testPostRecordingProcessingStatePolicyPreservesMacOSProcessingStates() {
        XCTAssertFalse(RomaRecordingState.idle.isPostRecordingProcessing)
        XCTAssertFalse(RomaRecordingState.starting.isPostRecordingProcessing)
        XCTAssertFalse(RomaRecordingState.recording.isPostRecordingProcessing)
        XCTAssertTrue(RomaRecordingState.transcribing.isPostRecordingProcessing)
        XCTAssertTrue(RomaRecordingState.enhancing.isPostRecordingProcessing)
        XCTAssertFalse(RomaRecordingState.busy.isPostRecordingProcessing)
    }

    func testRecorderDismissCancelableStatePolicyPreservesMacOSWindowBehavior() {
        XCTAssertFalse(RomaRecordingState.idle.isRecorderDismissCancelable)
        XCTAssertTrue(RomaRecordingState.starting.isRecorderDismissCancelable)
        XCTAssertTrue(RomaRecordingState.recording.isRecorderDismissCancelable)
        XCTAssertTrue(RomaRecordingState.transcribing.isRecorderDismissCancelable)
        XCTAssertTrue(RomaRecordingState.enhancing.isRecorderDismissCancelable)
        XCTAssertFalse(RomaRecordingState.busy.isRecorderDismissCancelable)
    }

    func testPipelineFinishIdleRepairStatePolicyPreservesMacOSEngineBehavior() {
        XCTAssertFalse(RomaRecordingState.idle.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertFalse(RomaRecordingState.starting.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertFalse(RomaRecordingState.recording.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertTrue(RomaRecordingState.transcribing.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertTrue(RomaRecordingState.enhancing.shouldReturnToIdleWhenActivePipelineFinishes)
        XCTAssertTrue(RomaRecordingState.busy.shouldReturnToIdleWhenActivePipelineFinishes)
    }

    func testMacOSRecordingCancellationPlanFinishesActiveCaptureImmediately() async {
        for state in [RomaRecordingState.starting, .recording] {
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
        for state in [RomaRecordingState.transcribing, .enhancing] {
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
        for state in [RomaRecordingState.idle, .busy] {
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

    private func macOSRecordingCancellationEvents(for state: RomaRecordingState) async -> [String] {
        var events: [String] = []

        await RomaMacOSRecordingCancellationPolicy.plan(recordingState: state).applyRuntimeState(
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
        var flowState = RomaRecordingFlowState(currentDuration: 12)

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
        XCTAssertEqual(flowState.currentDuration, RomaRecordingFlowState.durationUpdateInterval)

        flowState.finishRecording()
        XCTAssertEqual(flowState.recordingState, .idle)
        XCTAssertFalse(flowState.animate)
        XCTAssertFalse(flowState.isRecordingSheetPresented)
        XCTAssertEqual(flowState.currentDuration, RomaRecordingFlowState.durationUpdateInterval)
    }

    func testRecordingStopPlanFinishesFlowAndCreatesPendingDraftOnlyWhenAudioExists() {
        let recordingState = RomaRecordingFlowState(
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
            RomaRecordingTranscriptionDraft.pending(
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
        let recordingState = RomaRecordingFlowState(
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
        let recordingState = RomaRecordingFlowState(
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

    private func audioRecorderStopEvents(for mode: RomaAudioRecorderStopMode) -> [String] {
        var events: [String] = []

        RomaAudioRecorderStopPolicy.plan(for: mode).applyRuntimeState(
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
        XCTAssertEqual(RomaAudioMeterLevel.normalizedLevel(forDecibels: -80), 0)
        XCTAssertEqual(RomaAudioMeterLevel.normalizedLevel(forDecibels: 0), 1)
        XCTAssertEqual(RomaAudioMeterLevel.normalizedLevel(forDecibels: 12), 1)
    }

    func testNormalizedLevelPreservesExistingMinusSixtyToZeroDecibelMapping() {
        XCTAssertEqual(RomaAudioMeterLevel.normalizedLevel(forDecibels: -60), 0)
        XCTAssertEqual(RomaAudioMeterLevel.normalizedLevel(forDecibels: -30), 0.5, accuracy: 0.0001)
        XCTAssertEqual(RomaAudioMeterLevel.normalizedLevel(forDecibels: -15), 0.75, accuracy: 0.0001)
    }

    func testSmoothedLevelPreservesMacOSExponentialMovingAverageWeights() {
        XCTAssertEqual(
            RomaAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75),
            0.45,
            accuracy: 0.0001
        )
    }

    func testSmoothedLevelClampsCustomPreviousWeight() {
        XCTAssertEqual(
            RomaAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75, previousWeight: -1),
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.smoothedLevel(previous: 0.25, current: 0.75, previousWeight: 2),
            0.25,
            accuracy: 0.0001
        )
    }

    func testBoundedHistoryKeepsMostRecentLevels() {
        let history = RomaAudioMeterLevel.boundedHistory(
            appending: 4,
            to: [1, 2, 3],
            limit: 3
        )

        XCTAssertEqual(history, [2, 3, 4])
    }

    func testBoundedHistoryRejectsNonPositiveLimit() {
        XCTAssertEqual(
            RomaAudioMeterLevel.boundedHistory(appending: 1, to: [0], limit: 0),
            []
        )
    }

    func testMacOSMeterUpdatePlanNormalizesAndSmoothsAverageAndPeak() {
        let plan = RomaAudioMeterLevel.macOSMeterUpdatePlan(
            averageDecibels: -30,
            peakDecibels: -15,
            previousSmoothedAverage: 0.25,
            previousSmoothedPeak: 0.5
        )

        XCTAssertEqual(plan.smoothedAverage, 0.35, accuracy: 0.0001)
        XCTAssertEqual(plan.smoothedPeak, 0.6, accuracy: 0.0001)
    }

    func testIOSMeterHistoryUpdatePlanNormalizesAndBoundsHistory() {
        let plan = RomaAudioMeterLevel.iOSMeterHistoryUpdatePlan(
            averageDecibels: -15,
            previousHistory: [0.1, 0.2, 0.3]
        )

        XCTAssertEqual(plan.normalizedLevel, 0.75, accuracy: 0.0001)
        XCTAssertEqual(plan.levelsHistory, [0.1, 0.2, 0.3, 0.75])

        let boundedPlan = RomaAudioMeterLevel.iOSMeterHistoryUpdatePlan(
            averageDecibels: -60,
            previousHistory: Array(repeating: 0.5, count: RomaAudioMeterLevel.defaultLevelHistoryLimit)
        )

        XCTAssertEqual(boundedPlan.levelsHistory.count, RomaAudioMeterLevel.defaultLevelHistoryLimit)
        XCTAssertEqual(boundedPlan.levelsHistory.last, 0)
    }

    func testUpdateCadencesPreservePlatformAudioMeterBehavior() {
        XCTAssertEqual(RomaAudioMeterLevel.macOSUpdateIntervalMilliseconds, 17)
        XCTAssertEqual(RomaAudioMeterLevel.iOSUpdateInterval, 0.1)
    }

    func testMacOSVisualizerGeometryPreservesExistingRecorderShape() {
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerAnimationMinimumInterval, 0.016)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerBarCount, 15)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerBarWidth, 3)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerBarSpacing, 2)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerMinimumBarHeight, 4)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerMaximumBarHeight, 28)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerPhaseStep, 0.4)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerWaveFrequency, 8)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerAmplitudeExponent, 0.7)
        XCTAssertEqual(RomaAudioMeterLevel.macOSVisualizerCenterBoostDropoff, 0.4)
    }

    func testMacOSVisualizerBarHeightPreservesExistingWaveAndCenterBoost() {
        XCTAssertEqual(
            RomaAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: 0,
                time: 0,
                averagePower: 1,
                isActive: true
            ),
            10.8571428571,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.macOSVisualizerBarHeight(
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
            RomaAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: 7,
                time: 0,
                averagePower: 1,
                isActive: false
            ),
            RomaAudioMeterLevel.macOSVisualizerMinimumBarHeight
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.macOSVisualizerBarHeight(
                forBarAt: -1,
                time: 0,
                averagePower: 1,
                isActive: true
            ),
            RomaAudioMeterLevel.macOSVisualizerMinimumBarHeight
        )
    }

    func testIOSVisualizerBarPolicyPreservesGeometryInputs() {
        XCTAssertEqual(RomaAudioMeterLevel.iOSVisualizerBarCount, 8)
        XCTAssertEqual(RomaAudioMeterLevel.iOSVisualizerBarSpacing, 3)
        XCTAssertEqual(RomaAudioMeterLevel.iOSVisualizerBarMinimumWidth, 2)
        XCTAssertEqual(RomaAudioMeterLevel.iOSVisualizerHorizontalPadding, 2)
        XCTAssertEqual(RomaAudioMeterLevel.iOSVisualizerWidthInset, 16)
        XCTAssertEqual(RomaAudioMeterLevel.iOSVisualizerFrameHeight, 48)
        XCTAssertEqual(RomaAudioMeterLevel.iOSVisualizerMinimumBarHeight, 4)
        XCTAssertEqual(RomaAudioMeterLevel.iOSVisualizerAnimationDuration, 0.12)
    }

    func testIOSVisualizerLevelSamplesRecentHistoryAndClampsLevels() {
        let levels: [Float] = [0.2, 0.5, 1.4, -0.3]

        XCTAssertEqual(
            RomaAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: levels, barCount: 4),
            0
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.visualizerLevel(forBarAt: 1, levels: levels, barCount: 4),
            1
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.visualizerLevel(forBarAt: 2, levels: levels, barCount: 4),
            0.5
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.visualizerLevel(forBarAt: 3, levels: levels, barCount: 4),
            0.2
        )
    }

    func testIOSVisualizerLevelHandlesEmptyHistoryAndNonPositiveBarCount() {
        XCTAssertEqual(RomaAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: []), 0)
        XCTAssertEqual(
            RomaAudioMeterLevel.visualizerLevel(forBarAt: 0, levels: [0.5], barCount: 0),
            0
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.visualizerLevel(forBarAt: -1, levels: [0.5], barCount: 1),
            0
        )
    }

    func testIOSVisualizerBarWidthPreservesExistingLayoutMath() {
        XCTAssertEqual(
            RomaAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 96),
            7,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 24),
            RomaAudioMeterLevel.iOSVisualizerBarMinimumWidth,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.iOSVisualizerBarWidth(containerWidth: 96, barCount: 0),
            RomaAudioMeterLevel.iOSVisualizerBarMinimumWidth,
            accuracy: 0.0001
        )
    }

    func testIOSVisualizerBarHeightPreservesExistingLevelMapping() {
        let levels: [Float] = [0.2, 0.5, 1.0]

        XCTAssertEqual(
            RomaAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 0,
                levels: levels,
                containerHeight: 48
            ),
            48,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 1,
                levels: levels,
                containerHeight: 48
            ),
            26,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RomaAudioMeterLevel.iOSVisualizerBarHeight(
                forBarAt: 0,
                levels: [],
                containerHeight: 48
            ),
            RomaAudioMeterLevel.iOSVisualizerMinimumBarHeight,
            accuracy: 0.0001
        )
    }

    func testRecordingFlowStatePreservesIOSStartFailureAndCancelTransitions() {
        var failedState = RomaRecordingFlowState(currentDuration: 8)
        failedState.prepareRecordingStart()
        failedState.failRecordingStart()

        XCTAssertEqual(failedState.recordingState, .idle)
        XCTAssertFalse(failedState.animate)
        XCTAssertFalse(failedState.isRecordingSheetPresented)
        XCTAssertEqual(failedState.currentDuration, 8)

        var canceledState = RomaRecordingFlowState(
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
        XCTAssertEqual(RomaAppGroupRecordingStatePolicy.UserDefaultsKey.isRecording, "isRecording")
        XCTAssertEqual(RomaAppGroupRecordingStatePolicy.UserDefaultsKey.lastRecordingTimestamp, "lastRecordingTimestamp")
        XCTAssertEqual(RomaAppGroupRecordingStatePolicy.staleRecordingInterval, 30)
    }

    func testAppGroupRecordingStatePolicyKeepsFreshRecordingActive() {
        let state = RomaAppGroupRecordingStatePolicy.state(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 129)
        )

        XCTAssertEqual(
            state,
            RomaAppGroupRecordingState(isRecording: true, shouldClearStaleState: false)
        )
    }

    func testAppGroupRecordingStatePolicyClearsStaleRecording() {
        let state = RomaAppGroupRecordingStatePolicy.state(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 131)
        )

        XCTAssertEqual(
            state,
            RomaAppGroupRecordingState(isRecording: false, shouldClearStaleState: true)
        )
    }

    func testAppGroupRecordingStatePolicyDoesNotClearInactiveRecording() {
        let state = RomaAppGroupRecordingStatePolicy.state(
            storedIsRecording: false,
            lastRecordingTimestamp: 0,
            now: Date(timeIntervalSince1970: 10_000)
        )

        XCTAssertEqual(
            state,
            RomaAppGroupRecordingState(isRecording: false, shouldClearStaleState: false)
        )
    }

    func testAppGroupRecordingStateReadPlanDoesNotRepairFreshRecording() {
        let plan = RomaAppGroupRecordingStatePolicy.readPlan(
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
            RomaAppGroupRecordingState(
                isRecording: true,
                shouldClearStaleState: false
            )
        )
        XCTAssertFalse(didRepair)
    }

    func testAppGroupRecordingStateReadPlanOwnsStaleRepairMutation() {
        let plan = RomaAppGroupRecordingStatePolicy.readPlan(
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
            RomaAppGroupRecordingState(
                isRecording: false,
                shouldClearStaleState: true
            )
        )
        XCTAssertEqual(events, [
            "recording:false",
            "timestamp:131.0",
            "notify:\(RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName)"
        ])
    }

    func testAppGroupRecordingStateReadPlanAppliesStaleRepairRuntimeState() {
        var events: [String] = []

        let freshState = RomaAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 129)
        ).applyRuntimeState { _ in
            events.append("fresh-repair")
        }
        events.append("fresh-state:\(freshState.isRecording)")

        let staleState = RomaAppGroupRecordingStatePolicy.readPlan(
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
            "repair-notify:\(RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName)",
            "stale-state:false"
        ])
    }

    func testAppGroupRecordingStateWritePlansPreserveIOSBridgeWrites() {
        var events: [String] = []

        RomaAppGroupRecordingStatePolicy.stopRequestedWritePlan(
            now: Date(timeIntervalSince1970: 42)
        )
        .recordAppGroupWriteEvents(into: &events)

        RomaAppGroupRecordingStatePolicy.recordingStateWritePlan(
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

        RomaAppGroupRecordingStatePolicy.stopRequestedWritePlan(
            now: Date(timeIntervalSince1970: 42)
        )
        .recordAppGroupWriteEvents(into: &events)

        RomaAppGroupRecordingStatePolicy.recordingStateWritePlan(
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

        RomaAppGroupRecordingStatePolicy.stopRequestedMutationPlan(
            now: Date(timeIntervalSince1970: 42)
        ).applyRuntimeState(
            applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events) },
            postDarwinNotification: { events.append("notify:\($0)") }
        )

        RomaAppGroupRecordingStatePolicy.recordingStateMutationPlan(
            isRecording: true,
            now: Date(timeIntervalSince1970: 43)
        ).applyRuntimeState(
            applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events) },
            postDarwinNotification: { events.append("notify:\($0)") }
        )

        XCTAssertEqual(events, [
            "timestamp:42.0",
            "notify:\(RomaAppIdentity.iOSStopRecordingDarwinNotificationName)",
            "recording:true",
            "timestamp:43.0",
            "notify:\(RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName)"
        ])
    }

    func testAppGroupRecordingStateMutationPlanAppliesRuntimeWriteBeforeNotification() {
        var events: [String] = []

        RomaAppGroupRecordingStatePolicy.stopRequestedMutationPlan(
            now: Date(timeIntervalSince1970: 42)
        ).applyRuntimeState(
            applyWritePlan: { $0.recordAppGroupWriteEvents(into: &events, prefix: "write-") },
            postDarwinNotification: {
                events.append("notify:\($0)")
            }
        )

        RomaAppGroupRecordingStatePolicy.recordingStateMutationPlan(
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
            "notify:\(RomaAppIdentity.iOSStopRecordingDarwinNotificationName)",
            "write-recording:true",
            "write-timestamp:43.0",
            "notify:\(RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName)"
        ])
    }

    func testKeyboardRecordingTimingPreservesIOSAppAndKeyboardDelays() {
        XCTAssertEqual(RomaKeyboardRecordingTiming.appLaunchRecordingStartDelay, 0.5)
        XCTAssertEqual(RomaKeyboardRecordingTiming.recordingStatusPollingInterval, 0.5)
        XCTAssertEqual(RomaKeyboardRecordingTiming.openAppFallbackResetDelay, 2.0)
    }

    func testLaunchRecordingRequestStartsImmediatelyWhenOnboardingIsComplete() {
        var state = RomaLaunchRecordingRequestState()
        var events: [String] = []

        state.requestRecording(hasCompletedOnboarding: true).applyRuntimeState {
            events.append("start")
        }

        XCTAssertEqual(events, ["start"])
        XCTAssertFalse(state.hasPendingRecordingAfterOnboarding)
    }

    func testLaunchRecordingRequestDefersUntilOnboardingCompletes() {
        var state = RomaLaunchRecordingRequestState()
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
        var state = RomaLaunchRecordingRequestState()
        var events: [String] = []

        state.consumePendingRecordingIfReady(hasCompletedOnboarding: true).applyRuntimeState {
            events.append("start")
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testLaunchRecordingRequestClearsPendingStateWhenRecordingCanStartNow() {
        var state = RomaLaunchRecordingRequestState(
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
            RomaKeyboardRecordingButtonPresentation.idle,
            RomaKeyboardRecordingButtonPresentation(title: " Record", systemImageName: "mic.fill")
        )
        XCTAssertEqual(
            RomaKeyboardRecordingButtonPresentation.recording,
            RomaKeyboardRecordingButtonPresentation(title: " Stop", systemImageName: "stop.fill")
        )
        XCTAssertEqual(
            RomaKeyboardRecordingButtonPresentation.openAppFallback,
            RomaKeyboardRecordingButtonPresentation(
                title: " Open \(RomaAppIdentity.displayName)",
                systemImageName: "app"
            )
        )
    }

    func testKeyboardRecordingButtonPresentationSelectsCurrentState() {
        XCTAssertEqual(RomaKeyboardRecordingButtonPresentation.current(isRecording: false), .idle)
        XCTAssertEqual(RomaKeyboardRecordingButtonPresentation.current(isRecording: true), .recording)
    }

    func testKeyboardRecordingButtonTapPlanAppliesRuntimeState() {
        var events: [String] = []

        RomaKeyboardRecordingButtonTapPolicy.plan(isRecording: true).applyRuntimeState(
            requestStopRecording: { events.append("stop") },
            openMainAppForRecording: { events.append("open") },
            refreshButtonState: { events.append("refresh") }
        )
        RomaKeyboardRecordingButtonTapPolicy.plan(isRecording: false).applyRuntimeState(
            requestStopRecording: { events.append("stop") },
            openMainAppForRecording: { events.append("open") },
            refreshButtonState: { events.append("refresh") }
        )

        XCTAssertEqual(events, ["stop", "refresh", "open"])
    }

    func testKeyboardOpenAppPlansApplyDiagnosticsAndRuntimeState() {
        var events: [String] = []

        func apply(_ plan: RomaKeyboardOpenAppActionPlan) {
            plan.applyRuntimeState(
                logNotice: { events.append("notice:\($0)") },
                logError: { events.append("error:\($0)") },
                openExtensionContext: { events.append("extension") },
                openThroughApplicationOrResponderChain: { events.append("fallbackChain") },
                finish: { events.append("finish") },
                showFallback: { events.append("fallback") }
            )
        }

        func apply(_ plan: RomaKeyboardOpenAppResponderActionPlan) {
            plan.applyRuntimeState(
                logNotice: { events.append("notice:\($0)") },
                logError: { events.append("error:\($0)") },
                performResponderChainOpen: { events.append("responder") },
                showFallback: { events.append("responderFallback") }
            )
        }

        func apply(_ plan: RomaKeyboardOpenAppApplicationActionPlan) {
            plan.applyRuntimeState(
                openViaApplication: { events.append("application") },
                openViaResponderChain: { events.append("responderChain") }
            )
        }

        apply(RomaKeyboardOpenAppPolicy.initialActionPlan(hasExtensionContext: true))
        apply(RomaKeyboardOpenAppPolicy.initialActionPlan(hasExtensionContext: false))
        apply(RomaKeyboardOpenAppPolicy.applicationActionPlan(canOpenURL: true))
        apply(RomaKeyboardOpenAppPolicy.applicationActionPlan(canOpenURL: false))
        apply(RomaKeyboardOpenAppPolicy.actionPlanAfterExtensionContextOpen(succeeded: true))
        apply(RomaKeyboardOpenAppPolicy.actionPlanAfterExtensionContextOpen(succeeded: false))
        apply(RomaKeyboardOpenAppPolicy.actionPlanAfterApplicationOpen(succeeded: true))
        apply(RomaKeyboardOpenAppPolicy.actionPlanAfterApplicationOpen(succeeded: false))
        apply(RomaKeyboardOpenAppPolicy.responderActionPlan(hasResponder: true))
        apply(RomaKeyboardOpenAppPolicy.responderActionPlan(hasResponder: false))

        XCTAssertEqual(events, [
            "extension",
            "error:\(RomaKeyboardOpenAppDiagnostics.extensionContextUnavailable)",
            "fallbackChain",
            "application",
            "responderChain",
            "notice:\(RomaKeyboardOpenAppDiagnostics.openedViaExtensionContext)",
            "finish",
            "error:\(RomaKeyboardOpenAppDiagnostics.extensionContextOpenFailed)",
            "fallbackChain",
            "notice:\(RomaKeyboardOpenAppDiagnostics.openedViaApplication)",
            "finish",
            "error:\(RomaKeyboardOpenAppDiagnostics.applicationOpenFailed)",
            "fallback",
            "responder",
            "notice:\(RomaKeyboardOpenAppDiagnostics.attemptedViaResponderChain)",
            "error:\(RomaKeyboardOpenAppDiagnostics.allMethodsFailed)",
            "responderFallback"
        ])
    }

    func testKeyboardOpenAppDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            RomaKeyboardOpenAppDiagnostics.extensionContextUnavailable,
            "extensionContext unavailable, trying alternative methods"
        )
        XCTAssertEqual(
            RomaKeyboardOpenAppDiagnostics.openedViaExtensionContext,
            "Opened main app via extensionContext"
        )
        XCTAssertEqual(
            RomaKeyboardOpenAppDiagnostics.extensionContextOpenFailed,
            "extensionContext.open failed, trying alternative methods"
        )
        XCTAssertEqual(
            RomaKeyboardOpenAppDiagnostics.openedViaApplication,
            "Opened main app via UIApplication.open"
        )
        XCTAssertEqual(
            RomaKeyboardOpenAppDiagnostics.applicationOpenFailed,
            "UIApplication.open failed"
        )
        XCTAssertEqual(
            RomaKeyboardOpenAppDiagnostics.attemptedViaResponderChain,
            "Attempted to open main app via responder chain"
        )
        XCTAssertEqual(
            RomaKeyboardOpenAppDiagnostics.allMethodsFailed,
            "All URL opening methods failed"
        )
    }

    func testKeyboardStopRecordingRequestPlanHandlesOnlyActiveRecording() {
        var handledStates: [RomaRecordingState] = []

        for state in [
            RomaRecordingState.recording,
            RomaRecordingState.idle,
            .starting,
            .transcribing,
            .enhancing,
            .busy
        ] {
            RomaKeyboardStopRecordingRequestPolicy.plan(recordingState: state)
                .applyRuntimeState {
                    handledStates.append(state)
                }
        }

        XCTAssertEqual(handledStates, [.recording])
    }

    func testRecorderStylePreferencePreservesMacOSStorageAndLabels() {
        XCTAssertEqual(RomaRecorderStylePreference.userDefaultsKey, "RecorderType")
        XCTAssertEqual(RomaRecorderStylePreference.defaultStyle, .none)
        XCTAssertEqual(RomaRecorderStylePreference.defaultRawValue, "none")
        XCTAssertEqual(RomaRecorderStyle.allCases, [.none, .notch, .mini])
        XCTAssertEqual(RomaRecorderStyle.none.displayName, "None")
        XCTAssertEqual(RomaRecorderStyle.notch.displayName, "Notch")
        XCTAssertEqual(RomaRecorderStyle.mini.displayName, "Mini")
        XCTAssertEqual(RomaRecorderStylePreference.macOSSettingsPresentation.sectionTitle, "Interface")
        XCTAssertEqual(RomaRecorderStylePreference.macOSSettingsPresentation.pickerTitle, "Recorder Style")
    }

    func testRecorderStylePreferenceReadsAndSavesRawValues() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaRecorderStylePreference.rawValue(from: defaults), "none")

            RomaRecorderStylePreference.saveRawValue("notch", to: defaults)
            XCTAssertEqual(RomaRecorderStylePreference.rawValue(from: defaults), "notch")

            RomaRecorderStylePreference.saveRawValue("future-style", to: defaults)
            XCTAssertEqual(RomaRecorderStylePreference.rawValue(from: defaults), "future-style")
        }
    }

    func testRecorderStyleWindowKindPreservesMacOSUnknownStyleFallback() {
        XCTAssertEqual(RomaRecorderStylePreference.windowKind(forRawValue: "none"), .none)
        XCTAssertEqual(RomaRecorderStylePreference.windowKind(forRawValue: "notch"), .notch)
        XCTAssertEqual(RomaRecorderStylePreference.windowKind(forRawValue: "mini"), .mini)
        XCTAssertEqual(RomaRecorderStylePreference.windowKind(forRawValue: "future-style"), .mini)
        XCTAssertFalse(RomaRecorderStylePreference.hasVisibleRecorder(rawValue: "none"))
        XCTAssertTrue(RomaRecorderStylePreference.hasVisibleRecorder(rawValue: "notch"))
        XCTAssertTrue(RomaRecorderStylePreference.hasVisibleRecorder(rawValue: "mini"))
        XCTAssertTrue(RomaRecorderStylePreference.hasVisibleRecorder(rawValue: "future-style"))
    }

    func testRecorderStyleWindowRuntimeStatePreservesMacOSUnknownStyleFallback() {
        var events: [String] = []

        for rawValue in ["none", "notch", "mini", "future-style"] {
            RomaRecorderStylePreference.applyWindowRuntimeState(
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
            RomaRecorderUISessionPolicy.isActiveForRecordingShortcut(
                hasVisibleRecorderType: false,
                recordingState: .idle,
                isRecorderSessionActive: true
            )
        )
        XCTAssertTrue(
            RomaRecorderUISessionPolicy.isActiveForRecordingShortcut(
                hasVisibleRecorderType: false,
                recordingState: .recording,
                isRecorderSessionActive: true
            )
        )
        XCTAssertTrue(
            RomaRecorderUISessionPolicy.isActiveForRecordingShortcut(
                hasVisibleRecorderType: true,
                recordingState: .idle,
                isRecorderSessionActive: true
            )
        )
        XCTAssertFalse(
            RomaRecorderUISessionPolicy.isActiveForRecordingShortcut(
                hasVisibleRecorderType: true,
                recordingState: .recording,
                isRecorderSessionActive: false
            )
        )
    }

    func testRecorderSessionPolicyClearsOnlyStaleHiddenIdleSessions() {
        XCTAssertTrue(
            RomaRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
                hasVisibleRecorderType: false,
                recordingState: .idle,
                isRecorderSessionActive: true
            )
        )
        XCTAssertFalse(
            RomaRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
                hasVisibleRecorderType: false,
                recordingState: .recording,
                isRecorderSessionActive: true
            )
        )
        XCTAssertFalse(
            RomaRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
                hasVisibleRecorderType: true,
                recordingState: .idle,
                isRecorderSessionActive: true
            )
        )
        XCTAssertFalse(
            RomaRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
                hasVisibleRecorderType: false,
                recordingState: .idle,
                isRecorderSessionActive: false
            )
        )
    }

    func testRecordingStartPlanStartsOrPresentsNoModeAlert() {
        var events: [String] = []

        RomaRecordingStartPolicy.plan(modeCount: 1).applyRuntimeState(
            startRecording: { events.append("start") },
            presentAlert: { alert in events.append("alert:\(alert.id)") }
        )
        RomaRecordingStartPolicy.plan(modeCount: 0).applyRuntimeState(
            startRecording: { events.append("start") },
            presentAlert: { alert in events.append("alert:\(alert.id)") }
        )

        XCTAssertEqual(events, ["start", "alert:noModesAvailable"])

        var presentedAlert: RomaRecordingAlertPresentation?
        RomaRecordingStartPolicy.plan(modeCount: 0).applyRuntimeState(
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
        XCTAssertNil(RomaRecordingAlertPresentation.noModesAvailable.runtimeAction {
            didOpenSettings = true
        })
        XCTAssertFalse(didOpenSettings)

        let action = RomaRecordingAlertPresentation.microphonePermissionDenied.runtimeAction {
            didOpenSettings = true
        }
        XCTAssertFalse(didOpenSettings)

        action?()
        XCTAssertTrue(didOpenSettings)
    }

    func testRecordingNotificationPresentationPreservesMacOSStartFailureCopy() {
        XCTAssertEqual(
            RomaRecordingNotificationPresentation.noTranscriptionModelSelected.title,
            "No AI Model Selected"
        )
        XCTAssertEqual(RomaRecordingNotificationPresentation.noTranscriptionModelSelected.duration, 3.0)
        XCTAssertNil(RomaRecordingNotificationPresentation.noTranscriptionModelSelected.actionButtonTitle)

        XCTAssertEqual(
            RomaRecordingNotificationPresentation.failedToStart.title,
            "Recording failed to start"
        )
        XCTAssertEqual(RomaRecordingNotificationPresentation.failedToStart.duration, 3.0)
        XCTAssertNil(RomaRecordingNotificationPresentation.failedToStart.actionButtonTitle)

        XCTAssertEqual(
            RomaRecordingNotificationPresentation.microphonePermissionRequired.title,
            "Microphone permission required"
        )
        XCTAssertEqual(RomaRecordingNotificationPresentation.microphonePermissionRequired.duration, 8.0)
        XCTAssertEqual(RomaRecordingNotificationPresentation.microphonePermissionRequired.actionButtonTitle, "Grant")
    }

    func testRecordingNotificationPresentationPreservesMacOSRuntimeFailureCopy() {
        let presentation = RomaRecordingNotificationPresentation.runtimeFailure(
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
        let alert = RomaRecordingAlertPresentation.recordingStartFailure(
            domain: NSOSStatusErrorDomain,
            code: RomaRecordingAlertPresentation.microphoneInUseOSStatusCode,
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
            RomaRecordingAlertPresentation.iOSRecorderStartReturnedFalseDescription,
            "Failed to start AVAudioRecorder. The record() method returned false. This often happens in the background if the audio session is not configured correctly or if there is a conflict with another app."
        )

        let error = RomaAudioRecorderStartFailurePolicy.returnedFalseError()
        let alert = RomaRecordingAlertPresentation.recordingStartFailure(
            domain: error.domain,
            code: error.code,
            localizedDescription: error.localizedDescription
        )

        XCTAssertEqual(alert.title, "Recording Failed")
        XCTAssertEqual(
            alert.message,
            "Could not start recording: \(RomaRecordingAlertPresentation.iOSRecorderStartReturnedFalseDescription)"
        )
    }

    func testAudioRecorderStartFailurePolicyBuildsIOSReturnedFalseError() {
        let error = RomaAudioRecorderStartFailurePolicy.returnedFalseError()

        XCTAssertEqual(error.domain, RomaAppIdentity.errorDomain(component: "AudioRecorder"))
        XCTAssertEqual(error.code, RomaAudioRecorderStartFailurePolicy.returnedFalseErrorCode)
        XCTAssertEqual(error.userInfo[NSLocalizedDescriptionKey] as? String, RomaAudioRecorderStartFailurePolicy.returnedFalseDescription)
        XCTAssertEqual(error.localizedDescription, RomaAudioRecorderStartFailurePolicy.returnedFalseDescription)
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "RomaCore.RecordingStatePolicyTests.\(UUID().uuidString)"
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
        XCTAssertEqual(RomaAudioInputMode.systemDefault.rawValue, "System Default")
        XCTAssertEqual(RomaAudioInputMode.custom.rawValue, "Custom Device")
        XCTAssertEqual(RomaAudioInputMode.prioritized.rawValue, "Prioritized")
        XCTAssertEqual(RomaAudioInputMode.defaultMode, .custom)
        XCTAssertEqual(RomaAudioInputMode.allCases, [.systemDefault, .custom, .prioritized])
    }

    func testAudioInputPreferencePreservesStorageKeysDefaultsAndRoundTrips() {
        XCTAssertEqual(RomaAudioInputPreference.inputModeKey, "audioInputMode")
        XCTAssertEqual(RomaAudioInputPreference.selectedDeviceUIDKey, "selectedAudioDeviceUID")
        XCTAssertEqual(RomaAudioInputPreference.prioritizedDevicesKey, "prioritizedDevices")
        XCTAssertEqual(RomaAudioInputPreference.lastUsedMicrophoneDeviceIDKey, "lastUsedMicrophoneDeviceID")
        XCTAssertEqual(
            RomaAudioInputPreference.registeredDefaults[RomaAudioInputPreference.inputModeKey] as? String,
            RomaAudioInputMode.defaultMode.rawValue
        )

        withIsolatedDefaults { defaults in
            XCTAssertEqual(RomaAudioInputPreference.inputMode(from: defaults), .custom)

            defaults.set("invalid", forKey: RomaAudioInputPreference.inputModeKey)
            XCTAssertEqual(RomaAudioInputPreference.inputMode(from: defaults), .custom)

            RomaAudioInputPreference.saveInputMode(.prioritized, to: defaults)
            XCTAssertEqual(RomaAudioInputPreference.inputMode(from: defaults), .prioritized)

            XCTAssertNil(RomaAudioInputPreference.selectedDeviceUID(from: defaults))
            RomaAudioInputPreference.saveSelectedDeviceUID("usb-mic", to: defaults)
            XCTAssertEqual(RomaAudioInputPreference.selectedDeviceUID(from: defaults), "usb-mic")
            RomaAudioInputPreference.clearSelectedDeviceUID(from: defaults)
            XCTAssertNil(RomaAudioInputPreference.selectedDeviceUID(from: defaults))

            let devices = [
                RomaAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                RomaAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1)
            ]

            XCTAssertEqual(RomaAudioInputPreference.prioritizedDevices(from: defaults), [])
            RomaAudioInputPreference.savePrioritizedDevices(devices, to: defaults)
            XCTAssertEqual(RomaAudioInputPreference.prioritizedDevices(from: defaults), devices)

            XCTAssertNil(RomaAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
            XCTAssertTrue(RomaAudioInputPreference.shouldAnnounceMicrophoneChange(to: "123", in: defaults))
            RomaAudioInputPreference.saveLastUsedMicrophoneDeviceID("123", to: defaults)
            XCTAssertEqual(RomaAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults), "123")
            XCTAssertFalse(RomaAudioInputPreference.shouldAnnounceMicrophoneChange(to: "123", in: defaults))
            XCTAssertTrue(RomaAudioInputPreference.shouldAnnounceMicrophoneChange(to: "456", in: defaults))
            RomaAudioInputPreference.clearLastUsedMicrophoneDeviceID(from: defaults)
            XCTAssertNil(RomaAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
        }
    }

    func testMacOSAudioDeviceChangeRequestPreservesNotificationContract() {
        XCTAssertEqual(
            RomaMacOSAudioDeviceChangeRequest.deviceChangedNotificationName.rawValue,
            "AudioDeviceChanged"
        )
        XCTAssertEqual(
            RomaMacOSAudioDeviceChangeRequest.switchRequiredNotificationName.rawValue,
            "audioDeviceSwitchRequired"
        )
        XCTAssertEqual(RomaMacOSAudioDeviceChangeRequest.newDeviceIDUserInfoKey, "newDeviceID")

        let userInfo = RomaMacOSAudioDeviceChangeRequest.switchRequiredUserInfo(deviceID: 42)
        XCTAssertEqual(userInfo[RomaMacOSAudioDeviceChangeRequest.newDeviceIDUserInfoKey] as? UInt32, 42)

        let notification = Notification(
            name: RomaMacOSAudioDeviceChangeRequest.switchRequiredNotificationName,
            userInfo: userInfo
        )
        XCTAssertEqual(RomaMacOSAudioDeviceChangeRequest.newDeviceID(from: notification), 42)
        XCTAssertNil(
            RomaMacOSAudioDeviceChangeRequest.newDeviceID(
                from: Notification(name: RomaMacOSAudioDeviceChangeRequest.switchRequiredNotificationName)
            )
        )
    }

    func testAudioInputModePreservesSettingsPresentation() {
        XCTAssertEqual(RomaAudioInputMode.systemDefault.title, "System Default")
        XCTAssertEqual(RomaAudioInputMode.systemDefault.iconSystemName, "display")
        XCTAssertEqual(RomaAudioInputMode.systemDefault.description, "Use your Mac's default input")

        XCTAssertEqual(RomaAudioInputMode.custom.title, "Custom Device")
        XCTAssertEqual(RomaAudioInputMode.custom.iconSystemName, "mic.circle.fill")
        XCTAssertEqual(RomaAudioInputMode.custom.description, "Select a specific input device")

        XCTAssertEqual(RomaAudioInputMode.prioritized.title, "Prioritized")
        XCTAssertEqual(RomaAudioInputMode.prioritized.iconSystemName, "list.number")
        XCTAssertEqual(RomaAudioInputMode.prioritized.description, "Set up device priority order")
    }

    func testMacOSAudioInputSettingsPresentationFormatsPriorityDisplay() {
        let presentation = RomaMacOSAudioInputSettingsPresentation.macOS

        XCTAssertEqual(presentation.priorityDisplayText(for: 0), "1")
        XCTAssertEqual(presentation.priorityDisplayText(for: 4), "5")
    }

    func testAddingPriorityDeviceAppendsNextPriorityAndKeepsDuplicatesNoOp() {
        let existing = [
            RomaAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            RomaAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 3)
        ]

        let added = RomaAudioInputPriorityPolicy.addDevice(
            uid: "studio",
            name: "Studio Mic",
            to: existing
        )

        XCTAssertEqual(
            added,
            existing + [
                RomaAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 4)
            ]
        )
        XCTAssertEqual(
            RomaAudioInputPriorityPolicy.addDevice(uid: "usb", name: "Duplicate", to: existing),
            existing
        )
    }

    func testRemovingPriorityDeviceReindexesRemainingDevices() {
        let devices = [
            RomaAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            RomaAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1),
            RomaAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
        ]

        XCTAssertEqual(
            RomaAudioInputPriorityPolicy.removeDevice(id: "usb", from: devices),
            [
                RomaAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                RomaAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 1)
            ]
        )
    }

    func testMovingPriorityDeviceSwapsAndReindexesWithinBounds() {
        let devices = [
            RomaAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            RomaAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1),
            RomaAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
        ]

        XCTAssertEqual(
            RomaAudioInputPriorityPolicy.moveDevice(id: "studio", direction: .up, in: devices),
            [
                RomaAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                RomaAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 1),
                RomaAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 2)
            ]
        )
        XCTAssertEqual(
            RomaAudioInputPriorityPolicy.moveDevice(id: "built-in", direction: .down, in: devices),
            [
                RomaAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 0),
                RomaAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 1),
                RomaAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
            ]
        )
        XCTAssertEqual(
            RomaAudioInputPriorityPolicy.moveDevice(id: "built-in", direction: .up, in: devices),
            devices
        )
        XCTAssertEqual(
            RomaAudioInputPriorityPolicy.moveDevice(id: "missing", direction: .down, in: devices),
            devices
        )
    }

    func testFirstAvailablePriorityDeviceUsesPriorityOrder() {
        let devices = [
            RomaAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2),
            RomaAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            RomaAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1)
        ]

        XCTAssertEqual(
            RomaAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: devices,
                availableDeviceIDs: ["studio", "usb"]
            ),
            "usb"
        )
        XCTAssertNil(
            RomaAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: devices,
                availableDeviceIDs: []
            )
        )
    }

    func testAutomaticSelectionPolicyPreservesBuiltInDetection() {
        XCTAssertEqual(RomaAudioInputAutomaticSelectionPolicy.builtInUIDMarker, "BuiltIn")
        XCTAssertEqual(RomaAudioInputAutomaticSelectionPolicy.unsafeAirPodsNameMarker, "airpods")
        XCTAssertTrue(RomaAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: true,
            uid: nil
        ))
        XCTAssertTrue(RomaAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: false,
            uid: "AppleUSBAudioEngine:BuiltInMicrophone"
        ))
        XCTAssertFalse(RomaAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: false,
            uid: "external-usb-mic"
        ))
    }

    func testAutomaticSelectionPolicyPreservesSafeDeviceClassification() {
        XCTAssertTrue(RomaAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "MacBook Microphone",
            isBuiltIn: true,
            isBluetooth: true
        ))
        XCTAssertTrue(RomaAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "USB Studio Mic",
            isBuiltIn: false,
            isBluetooth: false
        ))
        XCTAssertFalse(RomaAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "Bluetooth Headset",
            isBuiltIn: false,
            isBluetooth: true
        ))
        XCTAssertFalse(RomaAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "Felix AirPods Pro",
            isBuiltIn: false,
            isBluetooth: false
        ))
    }

    func testAutomaticSelectionPolicyPrefersSafePreferredDevice() {
        let devices = [
            RomaAudioInputAutomaticDevice(id: "built-in", name: "Built-in", isBuiltIn: true, isBluetooth: false),
            RomaAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false)
        ]

        XCTAssertEqual(
            RomaAudioInputAutomaticSelectionPolicy.selection(preferred: "usb", devices: devices),
            RomaAudioInputAutomaticSelection(deviceID: "usb", reason: .preferred)
        )
    }

    func testAutomaticSelectionPolicyFallsBackToBuiltInBeforeOtherSafeDevices() {
        let devices = [
            RomaAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false),
            RomaAudioInputAutomaticDevice(id: "built-in", name: "Built-in", isBuiltIn: true, isBluetooth: false)
        ]

        XCTAssertEqual(
            RomaAudioInputAutomaticSelectionPolicy.selection(preferred: "missing", devices: devices),
            RomaAudioInputAutomaticSelection(deviceID: "built-in", reason: .builtIn)
        )
    }

    func testAutomaticSelectionPolicyUsesSafeFallbackWhenBuiltInUnavailable() {
        let devices = [
            RomaAudioInputAutomaticDevice(id: "airpods", name: "AirPods", isBuiltIn: false, isBluetooth: true),
            RomaAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false)
        ]

        XCTAssertEqual(
            RomaAudioInputAutomaticSelectionPolicy.selection(devices: devices),
            RomaAudioInputAutomaticSelection(deviceID: "usb", reason: .safeFallback)
        )
    }

    func testAutomaticSelectionPolicyRefusesUnsafeAutomaticDevices() {
        let devices = [
            RomaAudioInputAutomaticDevice(id: "airpods", name: "AirPods", isBuiltIn: false, isBluetooth: false),
            RomaAudioInputAutomaticDevice(id: "headset", name: "Bluetooth Headset", isBuiltIn: false, isBluetooth: true)
        ]

        XCTAssertEqual(
            RomaAudioInputAutomaticSelectionPolicy.selection(preferred: "headset", devices: devices),
            RomaAudioInputAutomaticSelection<String>(deviceID: nil, reason: .unavailable)
        )
    }

    func testSelectionPolicyResolvesCurrentDeviceByMode() {
        let availableDevices = [
            RomaAudioInputAvailableDevice(id: "built-in", uid: "built-in-uid", name: "Built-in"),
            RomaAudioInputAvailableDevice(id: "usb", uid: "usb-uid", name: "USB Mic")
        ]
        let priorityDevices = [
            RomaAudioInputPriorityDevice(id: "usb-uid", name: "USB Mic", priority: 1),
            RomaAudioInputPriorityDevice(id: "built-in-uid", name: "Built-in", priority: 2)
        ]

        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.currentDeviceID(
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
            RomaAudioInputSelectionPolicy.currentDeviceID(
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
            RomaAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: "usb",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "usb"
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: "missing",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: nil,
                selectedDeviceIsAvailable: true,
                priorityDeviceID: nil,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .prioritized,
                selectedDeviceID: "built-in",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "usb"
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .prioritized,
                selectedDeviceID: "built-in",
                prioritizedDevices: [
                    RomaAudioInputPriorityDevice(id: "missing-uid", name: "Missing", priority: 0)
                ],
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
    }

    func testSelectionPolicyPreservesModeChangeSelectionBehavior() {
        let availableDevices = [
            RomaAudioInputAvailableDevice(id: 1, uid: "built-in-uid", name: "Built-in"),
            RomaAudioInputAvailableDevice(id: 2, uid: "usb-uid", name: "USB Mic")
        ]
        let priorityDevices = [
            RomaAudioInputPriorityDevice(id: "usb-uid", name: "USB Mic", priority: 0)
        ]

        XCTAssertNil(
            RomaAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: 1,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            )
        )
        XCTAssertNil(
            RomaAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .systemDefault,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            )
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .custom,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            1
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            2
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: nil,
                prioritizedDevices: [
                    RomaAudioInputPriorityDevice(id: "missing-uid", name: "Missing", priority: 0)
                ],
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            1
        )
    }

    func testSelectionPolicyPlansRecordingDeviceSwitches() {
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .prioritized,
                priorityDeviceID: "usb",
                automaticDeviceID: "automatic"
            ),
            RomaAudioInputRecordingSwitchPlan(deviceID: "usb", usedPriorityFallback: false)
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .prioritized,
                priorityDeviceID: nil,
                automaticDeviceID: "automatic"
            ),
            RomaAudioInputRecordingSwitchPlan(deviceID: "automatic", usedPriorityFallback: true)
        )
        XCTAssertEqual(
            RomaAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .custom,
                priorityDeviceID: "usb",
                automaticDeviceID: "automatic"
            ),
            RomaAudioInputRecordingSwitchPlan(deviceID: "automatic", usedPriorityFallback: false)
        )
    }

}

private extension RomaAppGroupRecordingStateWritePlan {
    func recordAppGroupWriteEvents(into events: inout [String], prefix: String = "") {
        applyRuntimeState(
            setIsRecording: { events.append("\(prefix)recording:\($0)") },
            setLastRecordingTimestamp: { events.append("\(prefix)timestamp:\($0)") }
        )
    }
}
