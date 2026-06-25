import Foundation
import VoiceInkCore

final class TranscriptionRuntimeResourcePolicyTests: XCTestCase {
    func testLocalWhisperRoutePrewarmsAndLoadsWhisperAtRecordingStartup() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(events, ["whisper"])
    }

    func testLocalFluidAudioRoutePrewarmsAndLoadsFluidAudioAtRecordingStartup() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(events, ["fluid"])
    }

    func testCloudRouteSkipsLocalRuntimeWork() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(events, [])
    }

    func testNativeAppleRouteSkipsLocalRuntimeWork() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(events, [])
    }

    func testModelSelectionResourcePlanOwnsLocalWhisperRuntimeUpdate() {
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)
                .modelSelectionLocalWhisperRuntimeUpdate),
            []
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
    }

    func testDeletedCurrentModelPlanClearsSelectionAndMarksLocalWhisperUnloaded() {
        let plan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "ggml-base.en"
        )

        XCTAssertEqual(
            transcriptionModelDeletionEvents(for: plan),
            ["clearCurrentModel", "clearLoadedModel", "isModelLoaded:false"]
        )
    }

    func testDeletedNonCurrentModelPlanPreservesSelectionAndLocalWhisperRuntime() {
        let plan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "parakeet-tdt-0.6b-v2"
        )

        XCTAssertEqual(transcriptionModelDeletionEvents(for: plan), [])
    }

    private func localWhisperRuntimeUpdateEvents(for update: VoiceInkLocalWhisperRuntimeUpdate) -> [String] {
        var events: [String] = []

        update.applyRuntimeState(
            clearLoadedModel: { events.append("clearLoadedModel") },
            setIsModelLoaded: { events.append("isModelLoaded:\($0)") }
        )

        return events
    }

    private func transcriptionModelDeletionEvents(for plan: VoiceInkTranscriptionModelDeletionPlan) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            clearCurrentModel: { events.append("clearCurrentModel") },
            applyLocalWhisperRuntimeUpdate: {
                events.append(contentsOf: localWhisperRuntimeUpdateEvents(for: $0))
            }
        )

        return events
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
            VoiceInkModelPrewarmDiagnostics.completedMessage(duration: 1.234),
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
