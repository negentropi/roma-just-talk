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

    func testModelPrewarmSamplePolicyPreservesMacOSLookupOrder() {
        XCTAssertEqual(
            VoiceInkModelPrewarmSamplePolicy.lookupCandidates,
            [
                VoiceInkModelPrewarmSampleResource(
                    name: "sound7",
                    fileExtension: "wav",
                    subdirectory: "Resources/Sounds"
                ),
                VoiceInkModelPrewarmSampleResource(
                    name: "sound7",
                    fileExtension: "wav",
                    subdirectory: "Sounds"
                ),
                VoiceInkModelPrewarmSampleResource(
                    name: "sound7",
                    fileExtension: "wav",
                    subdirectory: nil
                )
            ]
        )

        let secondCandidateURL = URL(fileURLWithPath: "/tmp/sound7.wav")
        let resolvedURL = VoiceInkModelPrewarmSamplePolicy.firstAvailableURL { resource in
            resource.subdirectory == "Sounds" ? secondCandidateURL : nil
        }

        XCTAssertEqual(resolvedURL, secondCandidateURL)
    }

    func testModelPrewarmPlanPreservesMacOSSkipOrderAndDiagnostics() {
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: false,
                hasCurrentModel: false,
                shouldPrewarmModel: false,
                hasSampleAudio: false
            ).skipReason,
            .disabledByUser
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: false,
                shouldPrewarmModel: false,
                hasSampleAudio: false
            ).skipReason,
            .missingCurrentModel
        )
        XCTAssertNil(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: false,
                shouldPrewarmModel: false,
                hasSampleAudio: false
            ).diagnosticMessage
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: false,
                hasSampleAudio: false
            ).diagnosticMessage,
            "Skipping prewarm - cloud models don't need it"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: true,
                hasSampleAudio: false
            ).diagnosticMessage,
            "❌ Prewarm audio file (sound7.wav) not found"
        )

        XCTAssertTrue(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: true,
                hasSampleAudio: true
            ).shouldRun
        )
    }

    func testWhisperModelWarmupPolicySchedulesOnlyCoreMLModelsNotAlreadyWarming() {
        XCTAssertTrue(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: true,
                isAlreadyWarming: false
            )
        )
        XCTAssertFalse(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: false,
                isAlreadyWarming: false
            )
        )
        XCTAssertFalse(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: true,
                isAlreadyWarming: true
            )
        )
    }

    func testModelPrewarmDiagnosticsPreserveMacOSLogCopy() {
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.initializedMessage,
            "ModelPrewarmService initialized - listening for wake and app launch"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.appLaunchScheduledMessage,
            "App launched, scheduling prewarm"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.macActivityScheduledMessage,
            "Mac activity detected (wake/unlock), scheduling prewarm"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.prewarmingMessage(modelDisplayName: "Base"),
            "Prewarming Base"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.completedMessage(durationText: "1.23"),
            "Prewarm completed in 1.23s"
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmDiagnostics.failedMessage(errorDescription: "timeout"),
            "❌ Prewarm failed: timeout"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelWarmupDiagnostics.failedMessage(
                modelName: "base",
                errorDescription: "bad file"
            ),
            "❌ Warmup failed for base: bad file"
        )
    }
}
