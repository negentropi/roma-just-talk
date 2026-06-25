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

    func testRollingBufferPreviewStatePolicyMatchesMacOSRecorderGate() {
        XCTAssertTrue(VoiceInkRecordingState.idle.acceptsRollingBufferPreloadPreview)
        XCTAssertTrue(VoiceInkRecordingState.recording.acceptsRollingBufferPreloadPreview)
        XCTAssertFalse(VoiceInkRecordingState.starting.acceptsRollingBufferPreloadPreview)
        XCTAssertFalse(VoiceInkRecordingState.transcribing.acceptsRollingBufferPreloadPreview)
        XCTAssertFalse(VoiceInkRecordingState.enhancing.acceptsRollingBufferPreloadPreview)
        XCTAssertFalse(VoiceInkRecordingState.busy.acceptsRollingBufferPreloadPreview)
    }

    func testRecordingShortcutActionGatePreservesMacOSBusyStatePolicy() {
        XCTAssertTrue(VoiceInkRecordingState.idle.acceptsRecordingShortcutAction)
        XCTAssertTrue(VoiceInkRecordingState.starting.acceptsRecordingShortcutAction)
        XCTAssertTrue(VoiceInkRecordingState.recording.acceptsRecordingShortcutAction)
        XCTAssertFalse(VoiceInkRecordingState.transcribing.acceptsRecordingShortcutAction)
        XCTAssertFalse(VoiceInkRecordingState.enhancing.acceptsRecordingShortcutAction)
        XCTAssertFalse(VoiceInkRecordingState.busy.acceptsRecordingShortcutAction)
    }

    func testRecorderUIToggleActionPreservesMacOSStateMapping() {
        XCTAssertEqual(VoiceInkRecordingState.idle.recorderUIToggleAction, .dismissRecorder)
        XCTAssertEqual(VoiceInkRecordingState.starting.recorderUIToggleAction, .toggleRecord)
        XCTAssertEqual(VoiceInkRecordingState.recording.recorderUIToggleAction, .toggleRecord)
        XCTAssertEqual(VoiceInkRecordingState.transcribing.recorderUIToggleAction, .cancelRecording)
        XCTAssertEqual(VoiceInkRecordingState.enhancing.recorderUIToggleAction, .cancelRecording)
        XCTAssertEqual(VoiceInkRecordingState.busy.recorderUIToggleAction, .dismissRecorder)
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

        for input in [
            (hasSettingsURL: true, canOpenSettingsURL: true),
            (hasSettingsURL: false, canOpenSettingsURL: true),
            (hasSettingsURL: true, canOpenSettingsURL: false),
            (hasSettingsURL: false, canOpenSettingsURL: false)
        ] {
            VoiceInkRecordingPermissionPolicy.settingsOpenPlan(
                hasSettingsURL: input.hasSettingsURL,
                canOpenSettingsURL: input.canOpenSettingsURL
            ).applyRuntimeState {
                events.append("open")
            }
        }

        XCTAssertEqual(events, ["open"])
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

    func testRecorderProcessingPresentationPreservesMacOSCopyAndTiming() {
        XCTAssertNil(VoiceInkRecordingState.idle.recorderProcessingPresentation)
        XCTAssertNil(VoiceInkRecordingState.starting.recorderProcessingPresentation)
        XCTAssertNil(VoiceInkRecordingState.recording.recorderProcessingPresentation)
        XCTAssertEqual(
            VoiceInkRecordingState.transcribing.recorderProcessingPresentation,
            VoiceInkRecorderProcessingPresentation(
                label: "Transcribing",
                progressAnimationInterval: 0.18
            )
        )
        XCTAssertEqual(
            VoiceInkRecordingState.enhancing.recorderProcessingPresentation,
            VoiceInkRecorderProcessingPresentation(
                label: "Enhancing",
                progressAnimationInterval: 0.22
            )
        )
        XCTAssertNil(VoiceInkRecordingState.busy.recorderProcessingPresentation)
    }

    func testMacOSRecordingCancellationPlanFinishesActiveCaptureImmediately() {
        for state in [VoiceInkRecordingState.starting, .recording] {
            XCTAssertEqual(
                VoiceInkMacOSRecordingCancellationPolicy.plan(recordingState: state),
                VoiceInkMacOSRecordingCancellationPlan(
                    shouldClearDeferredStopRequest: true,
                    shouldRequestRecordingCancellation: true,
                    shouldFinishActiveRecorderCancellation: true,
                    shouldClearPartialTranscript: false,
                    shouldClearCancelFlag: false,
                    recordingStateAfterImmediateCancel: nil,
                    shouldFinishRecorderSessionImmediately: true
                )
            )
        }
    }

    func testMacOSRecordingCancellationPlanCancelsProcessingWithoutFinishingSession() {
        for state in [VoiceInkRecordingState.transcribing, .enhancing] {
            XCTAssertEqual(
                VoiceInkMacOSRecordingCancellationPolicy.plan(recordingState: state),
                VoiceInkMacOSRecordingCancellationPlan(
                    shouldClearDeferredStopRequest: true,
                    shouldRequestRecordingCancellation: true,
                    shouldFinishActiveRecorderCancellation: false,
                    shouldClearPartialTranscript: true,
                    shouldClearCancelFlag: false,
                    recordingStateAfterImmediateCancel: .idle,
                    shouldFinishRecorderSessionImmediately: false
                )
            )
        }
    }

    func testMacOSRecordingCancellationPlanRepairsIdleAndBusyState() {
        for state in [VoiceInkRecordingState.idle, .busy] {
            XCTAssertEqual(
                VoiceInkMacOSRecordingCancellationPolicy.plan(recordingState: state),
                VoiceInkMacOSRecordingCancellationPlan(
                    shouldClearDeferredStopRequest: true,
                    shouldRequestRecordingCancellation: false,
                    shouldFinishActiveRecorderCancellation: false,
                    shouldClearPartialTranscript: true,
                    shouldClearCancelFlag: true,
                    recordingStateAfterImmediateCancel: .idle,
                    shouldFinishRecorderSessionImmediately: true
                )
            )
        }
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

    func testAudioRecorderStopPolicyPreservesIOSStopCleanup() {
        XCTAssertEqual(
            VoiceInkAudioRecorderStopPolicy.plan(for: .keepRecordingFile),
            VoiceInkAudioRecorderStopPlan(
                shouldStopRecorder: true,
                shouldInvalidateMeterTimer: true,
                isRecordingAfterStop: false,
                shouldClearAudioLevels: true,
                shouldDeleteCurrentRecordingFile: false,
                shouldClearCurrentRecordingURL: false,
                shouldScheduleSessionDeactivation: true
            )
        )
    }

    func testAudioRecorderStopPolicyPreservesIOSDiscardCleanup() {
        XCTAssertEqual(
            VoiceInkAudioRecorderStopPolicy.plan(for: .discardRecordingFile),
            VoiceInkAudioRecorderStopPlan(
                shouldStopRecorder: true,
                shouldInvalidateMeterTimer: true,
                isRecordingAfterStop: false,
                shouldClearAudioLevels: true,
                shouldDeleteCurrentRecordingFile: true,
                shouldClearCurrentRecordingURL: true,
                shouldScheduleSessionDeactivation: true
            )
        )
    }

    func testAudioRecorderStopPlanAppliesRuntimeStateInOrder() {
        var events: [String] = []

        VoiceInkAudioRecorderStopPolicy.plan(for: .keepRecordingFile).applyRuntimeState(
            stopRecorder: { events.append("stop") },
            invalidateMeterTimer: { events.append("timer") },
            setIsRecording: { events.append("recording:\($0)") },
            clearAudioLevels: { events.append("levels") },
            deleteCurrentRecordingFile: { events.append("delete") },
            clearCurrentRecordingURL: { events.append("url") },
            scheduleSessionDeactivation: { events.append("session") }
        )
        VoiceInkAudioRecorderStopPolicy.plan(for: .discardRecordingFile).applyRuntimeState(
            stopRecorder: { events.append("stop") },
            invalidateMeterTimer: { events.append("timer") },
            setIsRecording: { events.append("recording:\($0)") },
            clearAudioLevels: { events.append("levels") },
            deleteCurrentRecordingFile: { events.append("delete") },
            clearCurrentRecordingURL: { events.append("url") },
            scheduleSessionDeactivation: { events.append("session") }
        )

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

        XCTAssertEqual(
            plan,
            VoiceInkAppGroupRecordingStateReadPlan(
                state: VoiceInkAppGroupRecordingState(
                    isRecording: true,
                    shouldClearStaleState: false
                ),
                staleStateRepairMutationPlan: nil
            )
        )
    }

    func testAppGroupRecordingStateReadPlanOwnsStaleRepairMutation() {
        let plan = VoiceInkAppGroupRecordingStatePolicy.readPlan(
            storedIsRecording: true,
            lastRecordingTimestamp: 100,
            now: Date(timeIntervalSince1970: 131)
        )

        XCTAssertEqual(
            plan,
            VoiceInkAppGroupRecordingStateReadPlan(
                state: VoiceInkAppGroupRecordingState(
                    isRecording: false,
                    shouldClearStaleState: true
                ),
                staleStateRepairMutationPlan: VoiceInkAppGroupRecordingStateMutationPlan(
                    writePlan: VoiceInkAppGroupRecordingStateWritePlan(
                        isRecording: false,
                        lastRecordingTimestamp: 131
                    ),
                    darwinNotificationName: VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName
                )
            )
        )
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
            events.append(
                "repair:\(mutationPlan.darwinNotificationName):\(mutationPlan.writePlan.isRecording == false)"
            )
        }
        events.append("stale-state:\(staleState.isRecording)")

        XCTAssertEqual(events, [
            "fresh-state:true",
            "repair:\(VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName):true",
            "stale-state:false"
        ])
    }

    func testAppGroupRecordingStateWritePlansPreserveIOSBridgeWrites() {
        XCTAssertEqual(
            VoiceInkAppGroupRecordingStatePolicy.stopRequestedWritePlan(
                now: Date(timeIntervalSince1970: 42)
            ),
            VoiceInkAppGroupRecordingStateWritePlan(
                isRecording: nil,
                lastRecordingTimestamp: 42
            )
        )

        XCTAssertEqual(
            VoiceInkAppGroupRecordingStatePolicy.recordingStateWritePlan(
                isRecording: true,
                now: Date(timeIntervalSince1970: 43)
            ),
            VoiceInkAppGroupRecordingStateWritePlan(
                isRecording: true,
                lastRecordingTimestamp: 43
            )
        )
    }

    func testAppGroupRecordingStateWritePlanAppliesRuntimeStateInOrder() {
        var events: [String] = []

        VoiceInkAppGroupRecordingStatePolicy.stopRequestedWritePlan(
            now: Date(timeIntervalSince1970: 42)
        ).applyRuntimeState(
            setIsRecording: { events.append("recording:\($0)") },
            setLastRecordingTimestamp: { events.append("timestamp:\($0)") }
        )

        VoiceInkAppGroupRecordingStatePolicy.recordingStateWritePlan(
            isRecording: true,
            now: Date(timeIntervalSince1970: 43)
        ).applyRuntimeState(
            setIsRecording: { events.append("recording:\($0)") },
            setLastRecordingTimestamp: { events.append("timestamp:\($0)") }
        )

        XCTAssertEqual(events, [
            "timestamp:42.0",
            "recording:true",
            "timestamp:43.0"
        ])
    }

    func testAppGroupRecordingStateMutationPlansPreserveIOSBridgeNotifications() {
        XCTAssertEqual(
            VoiceInkAppGroupRecordingStatePolicy.stopRequestedMutationPlan(
                now: Date(timeIntervalSince1970: 42)
            ),
            VoiceInkAppGroupRecordingStateMutationPlan(
                writePlan: VoiceInkAppGroupRecordingStateWritePlan(
                    isRecording: nil,
                    lastRecordingTimestamp: 42
                ),
                darwinNotificationName: VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName
            )
        )

        XCTAssertEqual(
            VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
                isRecording: true,
                now: Date(timeIntervalSince1970: 43)
            ),
            VoiceInkAppGroupRecordingStateMutationPlan(
                writePlan: VoiceInkAppGroupRecordingStateWritePlan(
                    isRecording: true,
                    lastRecordingTimestamp: 43
                ),
                darwinNotificationName: VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName
            )
        )
    }

    func testAppGroupRecordingStateMutationPlanAppliesRuntimeWriteBeforeNotification() {
        var events: [String] = []

        VoiceInkAppGroupRecordingStatePolicy.stopRequestedMutationPlan(
            now: Date(timeIntervalSince1970: 42)
        ).applyRuntimeState(
            applyWritePlan: {
                events.append("write:\($0.isRecording == nil):\($0.lastRecordingTimestamp)")
            },
            postDarwinNotification: {
                events.append("notify:\($0)")
            }
        )

        VoiceInkAppGroupRecordingStatePolicy.recordingStateMutationPlan(
            isRecording: true,
            now: Date(timeIntervalSince1970: 43)
        ).applyRuntimeState(
            applyWritePlan: {
                events.append("write:\($0.isRecording == true):\($0.lastRecordingTimestamp)")
            },
            postDarwinNotification: {
                events.append("notify:\($0)")
            }
        )

        XCTAssertEqual(events, [
            "write:true:42.0",
            "notify:\(VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName)",
            "write:true:43.0",
            "notify:\(VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName)"
        ])
    }

    func testAppGroupRecordingDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            VoiceInkAppGroupRecordingDiagnostics.staleRecordingStateClearedMessage,
            "Recording state appears stale, clearing it"
        )
        XCTAssertEqual(
            VoiceInkAppGroupRecordingDiagnostics.updatedRecordingStateMessage(isRecording: true),
            "Updated recording state: true"
        )
        XCTAssertEqual(
            VoiceInkAppGroupRecordingDiagnostics.updatedRecordingStateMessage(isRecording: false),
            "Updated recording state: false"
        )
    }

    func testIOSRecordingCoordinationDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            VoiceInkIOSRecordingCoordinationDiagnostics.clearedStaleRecordingStateOnLaunchMessage,
            "Cleared stale recording state on app launch"
        )
        XCTAssertEqual(
            VoiceInkIOSRecordingCoordinationDiagnostics.recordDeepLinkOpenedMessage,
            "URL scheme triggered: open app for recording"
        )
        XCTAssertEqual(
            VoiceInkIOSRecordingCoordinationDiagnostics.keyboardRecordingRequestOpenedMessage,
            "App opened via keyboard extension - recording requested"
        )
        XCTAssertEqual(
            VoiceInkIOSRecordingCoordinationDiagnostics.recordingManagerInitializedMessage,
            "RecordingManager initialized"
        )
        XCTAssertEqual(
            VoiceInkIOSRecordingCoordinationDiagnostics.keyboardStopRecordingRequestedMessage,
            "Stop recording requested from keyboard extension"
        )
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
        XCTAssertEqual(alert.action, .dismiss)
    }

    func testRecordingAlertPresentationPreservesIOSPermissionDeniedCopy() {
        let alert = VoiceInkRecordingAlertPresentation.microphonePermissionDenied

        XCTAssertEqual(alert.id, "microphonePermissionDenied")
        XCTAssertEqual(alert.title, "Microphone Access Denied")
        XCTAssertEqual(alert.message, "To record audio, please grant microphone access in Settings.")
        XCTAssertEqual(alert.primaryButtonTitle, "Settings")
        XCTAssertEqual(alert.secondaryButtonTitle, "Cancel")
        XCTAssertEqual(alert.action, .openSettings)
    }

    func testRecordingAlertActionBuildsDeferredRuntimeAction() {
        var didOpenSettings = false
        XCTAssertNil(VoiceInkRecordingAlertPresentation.Action.dismiss.runtimeAction {
            didOpenSettings = true
        })
        XCTAssertFalse(didOpenSettings)

        let action = VoiceInkRecordingAlertPresentation.Action.openSettings.runtimeAction {
            didOpenSettings = true
        }
        XCTAssertFalse(didOpenSettings)

        action?()
        XCTAssertTrue(didOpenSettings)
    }

    func testRecordingSheetPresentationPreservesIOSControlsCopy() {
        let presentation = VoiceInkRecordingSheetPresentation.iOS

        XCTAssertEqual(presentation.cancelButtonTitle, "Cancel")
        XCTAssertEqual(presentation.stopButtonTitle, "Stop Recording")
        XCTAssertEqual(presentation.stopButtonSystemImageName, "stop.fill")
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
        XCTAssertEqual(alert.action, .dismiss)
    }

    func testRecordingStartFailurePreservesGenericFailureCopy() {
        let alert = VoiceInkRecordingAlertPresentation.recordingStartFailure(
            domain: "example",
            code: 42,
            localizedDescription: "Hardware unavailable"
        )

        XCTAssertEqual(alert.id, "recordingFailed-Hardware unavailable")
        XCTAssertEqual(alert.title, "Recording Failed")
        XCTAssertEqual(alert.message, "Could not start recording: Hardware unavailable")
        XCTAssertEqual(alert.primaryButtonTitle, "OK")
        XCTAssertEqual(alert.action, .dismiss)
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
}
