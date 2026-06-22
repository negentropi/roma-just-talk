import Foundation
import VoiceInkCore

final class TranscriptionRuntimeResourcePolicyTests: XCTestCase {
    func testLocalWhisperRoutePrewarmsAndLoadsWhisperAtRecordingStartup() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .loadLocalWhisperModel)
        XCTAssertEqual(plan.modelSelectionResourceAction, .preserveLocalWhisperModel)
    }

    func testLocalFluidAudioRoutePrewarmsAndLoadsFluidAudioAtRecordingStartup() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .loadLocalFluidAudioModel)
        XCTAssertEqual(plan.modelSelectionResourceAction, .clearLocalWhisperModelAndMarkLoaded)
    }

    func testCloudRouteSkipsLocalRuntimeWork() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .none)
        XCTAssertEqual(plan.modelSelectionResourceAction, .clearLocalWhisperModelAndMarkLoaded)
    }

    func testNativeAppleRouteSkipsLocalRuntimeWork() {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(plan.recordingStartupLoadAction, .none)
        XCTAssertEqual(plan.modelSelectionResourceAction, .clearLocalWhisperModelAndMarkLoaded)
    }

    func testModelSelectionResourceActionOwnsLocalWhisperRuntimeUpdate() {
        XCTAssertEqual(
            VoiceInkTranscriptionModelSelectionResourceAction.preserveLocalWhisperModel.localWhisperRuntimeUpdate,
            VoiceInkLocalWhisperRuntimeUpdate(
                shouldClearLoadedModel: false,
                isModelLoadedAfterUpdate: nil
            )
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelSelectionResourceAction.clearLocalWhisperModelAndMarkLoaded.localWhisperRuntimeUpdate,
            VoiceInkLocalWhisperRuntimeUpdate(
                shouldClearLoadedModel: true,
                isModelLoadedAfterUpdate: true
            )
        )
    }

    func testDeletedCurrentModelPlanClearsSelectionAndMarksLocalWhisperUnloaded() {
        let plan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "ggml-base.en"
        )

        XCTAssertTrue(plan.shouldClearCurrentModel)
        XCTAssertEqual(
            plan.localWhisperRuntimeUpdate,
            VoiceInkLocalWhisperRuntimeUpdate(
                shouldClearLoadedModel: true,
                isModelLoadedAfterUpdate: false
            )
        )
    }

    func testDeletedNonCurrentModelPlanPreservesSelectionAndLocalWhisperRuntime() {
        let plan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "parakeet-tdt-0.6b-v2"
        )

        XCTAssertFalse(plan.shouldClearCurrentModel)
        XCTAssertEqual(plan.localWhisperRuntimeUpdate, .preserve)
    }
}
