import Foundation
@testable import VoiceInkCore

final class TranscriptionStreamingPreferenceTests: XCTestCase {
    func testKeyPreservesExistingPerModelPattern() {
        XCTAssertEqual(VoiceInkTranscriptionStreamingPreference.keyPrefix, "streaming-enabled-")
        XCTAssertEqual(
            VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3"),
            "streaming-enabled-parakeet-tdt-0.6b-v3"
        )
    }

    func testStreamingPreferenceDefaultsEnabledWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkTranscriptionStreamingPreference.isEnabled(
                forModelName: "nova-3",
                in: defaults
            ))
        }
    }

    func testStreamingPreferenceSavesAndReadsOverride() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "nova-3",
                to: defaults
            )

            XCTAssertFalse(VoiceInkTranscriptionStreamingPreference.isEnabled(
                forModelName: "nova-3",
                in: defaults
            ))
        }
    }

    func testShouldUseStreamingRejectsUnsupportedModels() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
                for: VoiceInkTranscriptionStreamingModelSnapshot(
                    name: "whisper-base",
                    supportsStreaming: false
                ),
                in: defaults
            ))
        }
    }

    func testShouldUseStreamingForStreamingOnlyModelIgnoresStoredDisabledValue() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "ink-whisper",
                to: defaults
            )

            XCTAssertTrue(VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
                for: VoiceInkTranscriptionStreamingModelSnapshot(
                    name: "ink-whisper",
                    supportsStreaming: true,
                    isStreamingOnly: true
                ),
                in: defaults
            ))
        }
    }

    func testShouldUseStreamingUsesStoredPreferenceForBatchCapableStreamingModel() {
        withIsolatedDefaults { defaults in
            let model = VoiceInkTranscriptionStreamingModelSnapshot(
                name: "universal-3-pro",
                supportsStreaming: true
            )

            XCTAssertTrue(VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(for: model, in: defaults))

            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: model.name,
                to: defaults
            )

            XCTAssertFalse(VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(for: model, in: defaults))
        }
    }

    func testSessionRoutePlanUsesFileTranscriptionWhenStreamingDisabled() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .cloud, modelName: "nova-3")
            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "nova-3",
                to: defaults
            )

            let plan = facts.plan(forceStreaming: false, defaults: defaults)

            XCTAssertFalse(plan.usesStreaming)
            XCTAssertEqual(plan.serviceRoute, .cloud)
            XCTAssertNil(plan.streamingAdapterKind)
            XCTAssertFalse(plan.usesRollingPreload)
            XCTAssertNil(plan.finalCommitSource)
            XCTAssertNil(plan.finalCommitTimeoutNanoseconds)
        }
    }

    func testSessionRoutePlanUsesCloudStreamingAdapterAndTimeout() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .cloud, modelName: "nova-3")

            let plan = facts.plan(forceStreaming: false, defaults: defaults)

            XCTAssertTrue(plan.usesStreaming)
            XCTAssertEqual(plan.streamingAdapterKind, .cloud)
            XCTAssertFalse(plan.usesRollingPreload)
            XCTAssertEqual(plan.finalCommitSource, .cloud)
            XCTAssertEqual(plan.finalCommitTimeoutNanoseconds, VoiceInkStreamingFinalCommitTimeout.cloudNanoseconds)
        }
    }

    func testSessionRoutePlanUsesLocalFluidAudioStreamingAdapterAndTimeout() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .localFluidAudio, modelName: "parakeet-tdt-0.6b-v3")

            let plan = facts.plan(forceStreaming: false, defaults: defaults)

            XCTAssertTrue(plan.usesStreaming)
            XCTAssertEqual(plan.streamingAdapterKind, .localFluidAudio)
            XCTAssertFalse(plan.usesRollingPreload)
            XCTAssertEqual(plan.finalCommitSource, .localFluidAudio)
            XCTAssertEqual(
                plan.finalCommitTimeoutNanoseconds,
                VoiceInkStreamingFinalCommitTimeout.localFluidAudioNanoseconds
            )
        }
    }

    func testSessionRoutePlanEnablesRollingPreloadOnlyForForcedLocalFluidAudioStreaming() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .localFluidAudio, modelName: "parakeet-tdt-0.6b-v3")
            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "parakeet-tdt-0.6b-v3",
                to: defaults
            )

            let plan = facts.plan(forceStreaming: true, defaults: defaults)

            XCTAssertTrue(plan.usesStreaming)
            XCTAssertEqual(plan.streamingAdapterKind, .localFluidAudio)
            XCTAssertTrue(plan.usesRollingPreload)
            XCTAssertEqual(plan.finalCommitSource, .localFluidAudio)
        }
    }

    func testSessionRoutePlanRejectsForcedStreamingForUnsupportedModels() {
        let facts = VoiceInkTranscriptionSessionRouteFacts(
            serviceRoute: .localWhisper,
            streamingSnapshot: VoiceInkTranscriptionStreamingModelSnapshot(
                name: "whisper-base",
                supportsStreaming: false
            )
        )

        let plan = facts.plan(forceStreaming: true)

        XCTAssertFalse(plan.usesStreaming)
        XCTAssertEqual(plan.serviceRoute, .localWhisper)
        XCTAssertNil(plan.streamingAdapterKind)
        XCTAssertNil(plan.finalCommitSource)
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.TranscriptionStreamingPreferenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        run(defaults)
    }

    private func routeFacts(
        serviceRoute: VoiceInkTranscriptionServiceRoute,
        modelName: String
    ) -> VoiceInkTranscriptionSessionRouteFacts {
        VoiceInkTranscriptionSessionRouteFacts(
            serviceRoute: serviceRoute,
            streamingSnapshot: VoiceInkTranscriptionStreamingModelSnapshot(
                name: modelName,
                supportsStreaming: true
            )
        )
    }
}
