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

    func testRecordingAlertPresentationPreservesIOSNoModeGateCopy() {
        XCTAssertNil(VoiceInkRecordingAlertPresentation.noModesAvailableIfNeeded(modeCount: 1))

        let alert = VoiceInkRecordingAlertPresentation.noModesAvailableIfNeeded(modeCount: 0)
        XCTAssertEqual(alert?.id, "noModesAvailable")
        XCTAssertEqual(alert?.title, "No Modes Found")
        XCTAssertEqual(alert?.message, "Please create a new mode in Settings before recording.")
        XCTAssertEqual(alert?.primaryButtonTitle, "OK")
        XCTAssertNil(alert?.secondaryButtonTitle)
        XCTAssertEqual(alert?.action, .dismiss)
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
        XCTAssertEqual(
            VoiceInkRecordingNotificationPresentation.failedToStart.title,
            "Recording failed to start"
        )
    }

    func testRecordingNotificationPresentationPreservesMacOSRuntimeFailureCopy() {
        let presentation = VoiceInkRecordingNotificationPresentation.runtimeFailure(
            localizedDescription: "Device disconnected"
        )

        XCTAssertEqual(
            presentation.title,
            "Recording Failed: Device disconnected"
        )
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

        let alert = VoiceInkRecordingAlertPresentation.recordingStartFailure(
            domain: VoiceInkAppIdentity.errorDomain(component: "AudioRecorder"),
            code: 1001,
            localizedDescription: VoiceInkRecordingAlertPresentation.iOSRecorderStartReturnedFalseDescription
        )

        XCTAssertEqual(alert.title, "Recording Failed")
        XCTAssertEqual(
            alert.message,
            "Could not start recording: \(VoiceInkRecordingAlertPresentation.iOSRecorderStartReturnedFalseDescription)"
        )
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
