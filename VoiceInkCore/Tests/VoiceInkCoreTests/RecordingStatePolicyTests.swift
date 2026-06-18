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
}
