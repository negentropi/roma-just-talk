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

    func testRecordingPermissionPolicyPreservesStartPermissionActions() {
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.action(for: .granted),
            .startRecording
        )
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.action(for: .denied),
            .presentPermissionDenied
        )
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.action(for: .undetermined),
            .requestPermission
        )
    }

    func testRecordingPermissionPolicyPreservesPermissionRequestResults() {
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.action(afterPermissionRequestGranted: true),
            .startRecording
        )
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.action(afterPermissionRequestGranted: false),
            .presentPermissionDenied
        )
    }

    func testRecordingPermissionActionAppliesRuntimeState() {
        var events: [String] = []

        VoiceInkRecordingPermissionAction.startRecording.applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        VoiceInkRecordingPermissionAction.presentPermissionDenied.applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        VoiceInkRecordingPermissionAction.requestPermission.applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(true)
            }
        )
        VoiceInkRecordingPermissionAction.requestPermission.applyRuntimeState(
            startRecording: { events.append("start") },
            presentPermissionDenied: { events.append("denied") },
            requestPermission: { completion in
                events.append("request")
                completion(false)
            }
        )

        XCTAssertEqual(events, [
            "start",
            "denied",
            "request",
            "start",
            "request",
            "denied"
        ])
    }

    func testRecordingPermissionPolicyPreservesSettingsOpenFallback() {
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.settingsOpenAction(
                hasSettingsURL: true,
                canOpenSettingsURL: true
            ),
            .openSettings
        )
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.settingsOpenAction(
                hasSettingsURL: false,
                canOpenSettingsURL: true
            ),
            .ignore
        )
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.settingsOpenAction(
                hasSettingsURL: true,
                canOpenSettingsURL: false
            ),
            .ignore
        )
        XCTAssertEqual(
            VoiceInkRecordingPermissionPolicy.settingsOpenAction(
                hasSettingsURL: false,
                canOpenSettingsURL: false
            ),
            .ignore
        )
    }

    func testRecordingPermissionSettingsActionAppliesRuntimeState() {
        var events: [String] = []

        VoiceInkRecordingPermissionSettingsAction.ignore.applyRuntimeState {
            events.append("open")
        }
        VoiceInkRecordingPermissionSettingsAction.openSettings.applyRuntimeState {
            events.append("open")
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

        XCTAssertEqual(
            state.requestRecording(hasCompletedOnboarding: true),
            .startRecordingAfterLaunchDelay
        )
        XCTAssertFalse(state.hasPendingRecordingAfterOnboarding)
    }

    func testLaunchRecordingRequestDefersUntilOnboardingCompletes() {
        var state = VoiceInkLaunchRecordingRequestState()

        XCTAssertEqual(
            state.requestRecording(hasCompletedOnboarding: false),
            .deferUntilOnboardingCompletes
        )
        XCTAssertTrue(state.hasPendingRecordingAfterOnboarding)

        XCTAssertEqual(
            state.consumePendingRecordingIfReady(hasCompletedOnboarding: false),
            .none
        )
        XCTAssertTrue(state.hasPendingRecordingAfterOnboarding)

        XCTAssertEqual(
            state.consumePendingRecordingIfReady(hasCompletedOnboarding: true),
            .startRecordingAfterLaunchDelay
        )
        XCTAssertFalse(state.hasPendingRecordingAfterOnboarding)
    }

    func testLaunchRecordingRequestNoOpsWhenNothingIsPending() {
        var state = VoiceInkLaunchRecordingRequestState()

        XCTAssertEqual(
            state.consumePendingRecordingIfReady(hasCompletedOnboarding: true),
            .none
        )
    }

    func testLaunchRecordingRequestClearsPendingStateWhenRecordingCanStartNow() {
        var state = VoiceInkLaunchRecordingRequestState(
            hasPendingRecordingAfterOnboarding: true
        )

        XCTAssertEqual(
            state.requestRecording(hasCompletedOnboarding: true),
            .startRecordingAfterLaunchDelay
        )
        XCTAssertFalse(state.hasPendingRecordingAfterOnboarding)
    }

    func testLaunchRecordingRequestActionAppliesRuntimeState() {
        var events: [String] = []

        VoiceInkLaunchRecordingRequestAction.none.applyRuntimeState {
            events.append("start")
        }
        VoiceInkLaunchRecordingRequestAction.deferUntilOnboardingCompletes.applyRuntimeState {
            events.append("start")
        }
        VoiceInkLaunchRecordingRequestAction.startRecordingAfterLaunchDelay.applyRuntimeState {
            events.append("start")
        }

        XCTAssertEqual(events, ["start"])
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

    func testKeyboardRecordingButtonTapPlanStopsActiveRecordingAndRefreshesState() {
        XCTAssertEqual(
            VoiceInkKeyboardRecordingButtonTapPolicy.plan(isRecording: true),
            VoiceInkKeyboardRecordingButtonTapPlan(
                action: .requestStopRecording,
                shouldRefreshButtonStateAfterAction: true
            )
        )
    }

    func testKeyboardRecordingButtonTapPlanOpensAppWhenIdleWithoutRefreshingState() {
        XCTAssertEqual(
            VoiceInkKeyboardRecordingButtonTapPolicy.plan(isRecording: false),
            VoiceInkKeyboardRecordingButtonTapPlan(
                action: .openMainAppForRecording,
                shouldRefreshButtonStateAfterAction: false
            )
        )
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

    func testKeyboardOpenAppPolicyPreservesFallbackOrder() {
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.initialAction(hasExtensionContext: true),
            .openExtensionContext
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.initialAction(hasExtensionContext: false),
            .openThroughApplicationOrResponderChain
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.actionAfterExtensionContextOpen(succeeded: true),
            .finish
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.actionAfterExtensionContextOpen(succeeded: false),
            .openThroughApplicationOrResponderChain
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.applicationAction(canOpenURL: true),
            .openViaApplication
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.applicationAction(canOpenURL: false),
            .openViaResponderChain
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.actionAfterApplicationOpen(succeeded: true),
            .finish
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.actionAfterApplicationOpen(succeeded: false),
            .showFallback
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.responderAction(hasResponder: true),
            .performResponderChainOpen
        )
        XCTAssertEqual(
            VoiceInkKeyboardOpenAppPolicy.responderAction(hasResponder: false),
            .showFallback
        )
    }

    func testKeyboardOpenAppActionsApplyRuntimeState() {
        var events: [String] = []

        VoiceInkKeyboardOpenAppAction.openExtensionContext.applyRuntimeState(
            openExtensionContext: { events.append("extension") },
            openThroughApplicationOrResponderChain: { events.append("fallbackChain") },
            finish: { events.append("finish") },
            showFallback: { events.append("fallback") }
        )
        VoiceInkKeyboardOpenAppAction.openThroughApplicationOrResponderChain.applyRuntimeState(
            openExtensionContext: { events.append("extension") },
            openThroughApplicationOrResponderChain: { events.append("fallbackChain") },
            finish: { events.append("finish") },
            showFallback: { events.append("fallback") }
        )
        VoiceInkKeyboardOpenAppAction.finish.applyRuntimeState(
            openExtensionContext: { events.append("extension") },
            openThroughApplicationOrResponderChain: { events.append("fallbackChain") },
            finish: { events.append("finish") },
            showFallback: { events.append("fallback") }
        )
        VoiceInkKeyboardOpenAppAction.showFallback.applyRuntimeState(
            openExtensionContext: { events.append("extension") },
            openThroughApplicationOrResponderChain: { events.append("fallbackChain") },
            finish: { events.append("finish") },
            showFallback: { events.append("fallback") }
        )
        VoiceInkKeyboardOpenAppApplicationAction.openViaApplication.applyRuntimeState(
            openViaApplication: { events.append("application") },
            openViaResponderChain: { events.append("responderChain") }
        )
        VoiceInkKeyboardOpenAppApplicationAction.openViaResponderChain.applyRuntimeState(
            openViaApplication: { events.append("application") },
            openViaResponderChain: { events.append("responderChain") }
        )
        VoiceInkKeyboardOpenAppResponderAction.performResponderChainOpen.applyRuntimeState(
            performResponderChainOpen: { events.append("responder") },
            showFallback: { events.append("responderFallback") }
        )
        VoiceInkKeyboardOpenAppResponderAction.showFallback.applyRuntimeState(
            performResponderChainOpen: { events.append("responder") },
            showFallback: { events.append("responderFallback") }
        )

        XCTAssertEqual(events, [
            "extension",
            "fallbackChain",
            "finish",
            "fallback",
            "application",
            "responderChain",
            "responder",
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

    func testKeyboardStopRecordingRequestHandlesOnlyActiveRecording() {
        XCTAssertEqual(
            VoiceInkKeyboardStopRecordingRequestPolicy.action(recordingState: .recording),
            .handleStopRequest
        )

        for state in [
            VoiceInkRecordingState.idle,
            .starting,
            .transcribing,
            .enhancing,
            .busy
        ] {
            XCTAssertEqual(
                VoiceInkKeyboardStopRecordingRequestPolicy.action(recordingState: state),
                .ignore,
                "\(state) should ignore keyboard stop requests"
            )
        }
    }

    func testKeyboardStopRecordingRequestActionAppliesRuntimeState() {
        var handledStopRequest = false
        VoiceInkKeyboardStopRecordingRequestAction.ignore.applyRuntimeState {
            handledStopRequest = true
        }
        XCTAssertFalse(handledStopRequest)

        VoiceInkKeyboardStopRecordingRequestAction.handleStopRequest.applyRuntimeState {
            handledStopRequest = true
        }
        XCTAssertTrue(handledStopRequest)
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

    func testRecordingStartPolicyStartsWhenModesAreAvailable() {
        XCTAssertEqual(
            VoiceInkRecordingStartPolicy.action(modeCount: 1),
            .startRecording
        )
    }

    func testRecordingStartPolicyPresentsNoModeAlertWhenNoModesAreAvailable() {
        XCTAssertEqual(
            VoiceInkRecordingStartPolicy.action(modeCount: 0),
            .presentAlert(.noModesAvailable)
        )

        let alert = VoiceInkRecordingAlertPresentation.noModesAvailable
        XCTAssertEqual(alert.id, "noModesAvailable")
        XCTAssertEqual(alert.title, "No Modes Found")
        XCTAssertEqual(alert.message, "Please create a new mode in Settings before recording.")
        XCTAssertEqual(alert.primaryButtonTitle, "OK")
        XCTAssertNil(alert.secondaryButtonTitle)
        XCTAssertEqual(alert.action, .dismiss)
    }

    func testRecordingStartActionAppliesRuntimeState() {
        var events: [String] = []

        VoiceInkRecordingStartAction.startRecording.applyRuntimeState(
            startRecording: { events.append("start") },
            presentAlert: { alert in events.append("alert:\(alert.id)") }
        )
        VoiceInkRecordingStartAction.presentAlert(.noModesAvailable).applyRuntimeState(
            startRecording: { events.append("start") },
            presentAlert: { alert in events.append("alert:\(alert.id)") }
        )

        XCTAssertEqual(events, [
            "start",
            "alert:noModesAvailable"
        ])
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
