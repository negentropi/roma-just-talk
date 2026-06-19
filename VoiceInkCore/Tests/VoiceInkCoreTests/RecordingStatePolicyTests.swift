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
}
