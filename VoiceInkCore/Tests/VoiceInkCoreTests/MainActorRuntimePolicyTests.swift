import Foundation
@testable import VoiceInkCore

final class MainActorRuntimePolicyTests: XCTestCase {
    func testRecorderUIToggleRuntimeExecutesOnMainActor() async {
        let probe = await MainActor.run { MainActorExecutionProbe() }

        await Task.detached {
            await VoiceInkRecordingState.recording.applyRecorderUIToggleRuntimeState(
                toggleRecord: { probe.recordCurrentExecutor() },
                cancelRecording: { XCTFail("Unexpected cancel action") },
                dismissRecorder: { XCTFail("Unexpected dismiss action") }
            )
        }.value

        let values = await probe.values
        XCTAssertEqual(values, [true])
    }

    func testMacOSRecordingCancellationRuntimeExecutesOnMainActor() async {
        let probe = await MainActor.run { MainActorExecutionProbe() }

        await Task.detached {
            await VoiceInkMacOSRecordingCancellationPolicy.plan(
                recordingState: .recording
            ).applyRuntimeState(
                clearDeferredStopRequest: { probe.recordCurrentExecutor() },
                requestRecordingCancellation: { probe.recordCurrentExecutor() },
                finishActiveRecorderCancellation: { probe.recordCurrentExecutor() },
                clearPartialTranscript: { XCTFail("Unexpected partial transcript action") },
                clearCancelFlag: { XCTFail("Unexpected cancel flag action") },
                setRecordingState: { _ in XCTFail("Unexpected recording state action") },
                finishRecorderSessionImmediately: { probe.recordCurrentExecutor() }
            )
        }.value

        let values = await probe.values
        XCTAssertEqual(values, [true, true, true, true])
    }

    func testPowerModeRecordingFinishRuntimeExecutesOnMainActor() async {
        let probe = await MainActor.run { MainActorExecutionProbe() }

        await Task.detached {
            await VoiceInkPowerModeRecordingFinishPlan.finishingRecording(
                shouldPersistConfiguredPreferences: false
            ).applyRuntimeState(
                endSession: { probe.recordCurrentExecutor() },
                clearActiveConfiguration: { probe.recordCurrentExecutor() }
            )
        }.value

        let values = await probe.values
        XCTAssertEqual(values, [true, true])
    }

    func testStreamingFallbackRuntimeExecutesOnMainActor() async {
        let probe = await MainActor.run { MainActorExecutionProbe() }

        let result = await Task.detached {
            try? await VoiceInkStreamingFallbackPolicy.run(
                streamingFailed: false,
                streaming: {
                    probe.recordCurrentExecutor()
                    throw StreamingFailure.expected
                },
                onStreamingFailure: { _ in probe.recordCurrentExecutor() },
                cancelStreaming: { probe.recordCurrentExecutor() },
                prepareFallback: { probe.recordCurrentExecutor() },
                fallback: {
                    probe.recordCurrentExecutor()
                    return "fallback"
                }
            )
        }.value

        XCTAssertEqual(result, "fallback")
        let values = await probe.values
        XCTAssertEqual(values, [true, true, true, true, true])
    }
}

private enum StreamingFailure: Error {
    case expected
}

@MainActor
private final class MainActorExecutionProbe {
    private(set) var values: [Bool] = []

    func recordCurrentExecutor() {
        values.append(Thread.isMainThread)
    }
}
