import Foundation
@testable import VoiceInkCore

final class TranscriptionStreamingPreferenceTests: XCTestCase {
    func testStreamingEventsCarrySessionAndTextUpdates() {
        assertSessionStarted(.sessionStarted)
        assertText(.partial(text: "draft"), expectedText: "draft")
        assertText(.committed(text: "final"), expectedText: "final")
    }

    func testStreamingErrorEventCarriesOriginalError() {
        let error = VoiceInkStreamingTranscriptionError.serverError("closed")
        guard case .error(let carriedError) = VoiceInkStreamingTranscriptionEvent.error(error) else {
            XCTFail("Expected error event")
            return
        }

        XCTAssertEqual(
            carriedError.localizedDescription,
            "Streaming server error: closed"
        )
    }

    func testErrorDescriptionsPreserveExistingMacOSStreamingMessages() {
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.missingAPIKey.errorDescription,
            "API key not configured for streaming transcription"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.connectionFailed("socket closed").errorDescription,
            "Streaming connection failed: socket closed"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.timeout.errorDescription,
            "Streaming transcription timed out waiting for final result"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.serverError("bad request").errorDescription,
            "Streaming server error: bad request"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.notConnected.errorDescription,
            "Not connected to streaming transcription service"
        )
    }

    func testUnknownServerErrorFallbackPreservesExistingText() {
        XCTAssertEqual(VoiceInkStreamingTranscriptionError.unknownServerErrorMessage, "Unknown error")
    }

    func testKeyPreservesExistingPerModelPattern() {
        XCTAssertEqual(VoiceInkTranscriptionStreamingPreference.keyPrefix, "streaming-enabled-")
        XCTAssertEqual(
            VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3"),
            "streaming-enabled-parakeet-tdt-0.6b-v3"
        )
    }

    func testServiceRouteClassifiesCloudAndLocalProviders() {
        XCTAssertTrue(VoiceInkTranscriptionServiceRoute.cloud.isCloudTranscriptionProvider)
        XCTAssertFalse(VoiceInkTranscriptionServiceRoute.cloud.isLocalTranscriptionProvider)
        XCTAssertFalse(VoiceInkTranscriptionServiceRoute.localWhisper.isCloudTranscriptionProvider)
        XCTAssertTrue(VoiceInkTranscriptionServiceRoute.localWhisper.isLocalTranscriptionProvider)
        XCTAssertFalse(VoiceInkTranscriptionServiceRoute.localFluidAudio.isCloudTranscriptionProvider)
        XCTAssertTrue(VoiceInkTranscriptionServiceRoute.localFluidAudio.isLocalTranscriptionProvider)
        XCTAssertFalse(VoiceInkTranscriptionServiceRoute.nativeApple.isCloudTranscriptionProvider)
        XCTAssertTrue(VoiceInkTranscriptionServiceRoute.nativeApple.isLocalTranscriptionProvider)
    }

    func testTranscriptionServiceRouteDiagnosticsPreservesRuntimeLogCopy() {
        XCTAssertEqual(
            VoiceInkTranscriptionServiceRouteDiagnostics.transcribingMessage(
                modelDisplayName: "nova-3",
                serviceTypeDescription: "CloudTranscriptionService"
            ),
            "Transcribing with nova-3 using CloudTranscriptionService"
        )
    }

    func testStreamingTranscriptAssemblyPreservesCommittedPreviewAndFinalText() {
        XCTAssertEqual(VoiceInkStreamingTranscriptAssembly.committedText(["hello", "world"]), "hello world")
        XCTAssertEqual(VoiceInkStreamingTranscriptAssembly.committedText([]), "")
        XCTAssertEqual(
            VoiceInkStreamingTranscriptAssembly.previewText(
                committedSegments: [],
                partialText: "hel"
            ),
            "hel"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptAssembly.previewText(
                committedSegments: ["hello", "world"],
                partialText: "hello world again"
            ),
            "hello world again"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptAssembly.previewText(
                committedSegments: ["hello", "world"],
                partialText: "again"
            ),
            "hello world again"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptAssembly.previewText(
                committedSegments: ["hello"],
                partialText: ""
            ),
            "hello "
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

    func testMigrationKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkStreamingKeysMigration.didMigrateKey, "streaming-keys-migrated")
        XCTAssertEqual(VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey, "parakeet-streaming-enabled")
        XCTAssertEqual(VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey, "powerModeConfigurationsV2")
        XCTAssertEqual(VoiceInkStreamingKeysMigration.powerModeSelectedTranscriptionModelNameKey, "selectedTranscriptionModelName")
        XCTAssertEqual(VoiceInkUserDefaultsKey.powerModeConfigurations, "powerModeConfigurationsV2")
    }

    func testRunMigratesLegacyParakeetStreamingSettingToCurrentModels() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey)

            XCTAssertTrue(VoiceInkStreamingKeysMigration.run(in: defaults))

            XCTAssertNil(defaults.object(forKey: VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey))
            XCTAssertEqual(
                defaults.object(forKey: VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v2")) as? Bool,
                false
            )
            XCTAssertEqual(
                defaults.object(forKey: VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3")) as? Bool,
                false
            )
            XCTAssertTrue(defaults.bool(forKey: VoiceInkStreamingKeysMigration.didMigrateKey))
        }
    }

    func testRunRepairsRemovedCurrentAndPowerModeTranscriptionModels() {
        withIsolatedDefaults { defaults in
            VoiceInkCurrentTranscriptionModelPreference.saveModelName("stt-rt-v4", to: defaults)
            defaults.set(
                powerModeData([
                    [
                        "name": "Realtime",
                        "selectedTranscriptionModelName": "voxtral-mini-transcribe-realtime-2602"
                    ],
                    [
                        "name": "Unchanged",
                        "selectedTranscriptionModelName": "nova-3"
                    ],
                    [
                        "name": "Missing"
                    ]
                ]),
                forKey: VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey
            )

            VoiceInkStreamingKeysMigration.run(in: defaults)

            XCTAssertEqual(
                VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults),
                "stt-async-v4"
            )
            let configs = powerModeConfigs(from: defaults)
            XCTAssertEqual(configs[0]["selectedTranscriptionModelName"] as? String, "voxtral-mini-latest")
            XCTAssertEqual(configs[1]["selectedTranscriptionModelName"] as? String, "nova-3")
            XCTAssertNil(configs[2]["selectedTranscriptionModelName"])
        }
    }

    func testRunLeavesInvalidPowerModeJSONAloneButStillMarksMigrationComplete() {
        withIsolatedDefaults { defaults in
            let invalidData = Data("not-json".utf8)
            defaults.set(invalidData, forKey: VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey)

            XCTAssertTrue(VoiceInkStreamingKeysMigration.run(in: defaults))

            XCTAssertEqual(defaults.data(forKey: VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey), invalidData)
            XCTAssertTrue(defaults.bool(forKey: VoiceInkStreamingKeysMigration.didMigrateKey))
        }
    }

    func testRunSkipsAllWorkAfterMigrationFlagIsSet() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: VoiceInkStreamingKeysMigration.didMigrateKey)
            defaults.set(false, forKey: VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey)
            VoiceInkCurrentTranscriptionModelPreference.saveModelName("stt-rt-v4", to: defaults)

            XCTAssertFalse(VoiceInkStreamingKeysMigration.run(in: defaults))

            XCTAssertEqual(
                defaults.object(forKey: VoiceInkStreamingKeysMigration.legacyParakeetStreamingEnabledKey) as? Bool,
                false
            )
            XCTAssertEqual(
                VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults),
                "stt-rt-v4"
            )
        }
    }

    func testStreamingModePresentationForStreamingOnlyModelsForcesStreamingToggle() {
        let presentation = VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: false,
            isStreamingOnly: true,
            isPreloadEnabled: false
        )

        XCTAssertEqual(presentation.streamingToggleTitle, "Streaming")
        XCTAssertTrue(presentation.isStreamingToggleForcedOn)
        XCTAssertTrue(presentation.isStreamingToggleDisabled)
        XCTAssertEqual(presentation.streamingToggleHelp, "This model only supports active-recording streaming")
    }

    func testStreamingModePresentationForEnabledBatchCapableModelUsesStreamingHelp() {
        let presentation = VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: true,
            isStreamingOnly: false,
            isPreloadEnabled: false
        )

        XCTAssertFalse(presentation.isStreamingToggleForcedOn)
        XCTAssertFalse(presentation.isStreamingToggleDisabled)
        XCTAssertEqual(
            presentation.streamingToggleHelp,
            "Streams active-recording audio; click to use saved-file batch mode"
        )
    }

    func testStreamingModePresentationForDisabledBatchCapableModelUsesBatchHelp() {
        let presentation = VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: false,
            isStreamingOnly: false,
            isPreloadEnabled: false
        )

        XCTAssertFalse(presentation.isStreamingToggleForcedOn)
        XCTAssertFalse(presentation.isStreamingToggleDisabled)
        XCTAssertEqual(
            presentation.streamingToggleHelp,
            "Saved-file batch mode; click to stream active-recording audio"
        )
    }

    func testStreamingModePresentationPreservesPreloadHelp() {
        let enabled = VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: true,
            isStreamingOnly: false,
            isPreloadEnabled: true
        )
        let disabled = VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: true,
            isStreamingOnly: false,
            isPreloadEnabled: false
        )

        XCTAssertEqual(enabled.preloadToggleTitle, "Buffer Preload")
        XCTAssertEqual(
            enabled.preloadToggleHelp,
            "Rolling buffer can pre-run this model when global policy allows it"
        )
        XCTAssertEqual(disabled.preloadToggleTitle, "Buffer Preload")
        XCTAssertEqual(disabled.preloadToggleHelp, "Rolling buffer preload disabled for this model")
    }

    func testStreamingModePresentationPreservesFluidAudioPreloadHelp() {
        let enabled = VoiceInkTranscriptionStreamingModePresentation(
            isStreamingEnabled: true,
            isStreamingOnly: false,
            isPreloadEnabled: true,
            preloadHelpContext: .localFluidAudio
        )

        XCTAssertEqual(enabled.preloadToggleTitle, "Buffer Preload")
        XCTAssertEqual(enabled.preloadToggleHelp, "Rolling buffer can pre-run this model")
    }

    func testStreamingFinalCommitTimeoutPreservesCloudDefault() {
        XCTAssertEqual(VoiceInkStreamingFinalCommitTimeout.cloudNanoseconds, 10_000_000_000)
        XCTAssertEqual(
            VoiceInkStreamingFinalCommitTimeout.nanoseconds(for: .cloud),
            10_000_000_000
        )
    }

    func testStreamingFinalCommitTimeoutPreservesLocalFluidAudioFastCommit() {
        XCTAssertEqual(VoiceInkStreamingFinalCommitTimeout.localFluidAudioNanoseconds, 1_000_000_000)
        XCTAssertEqual(
            VoiceInkStreamingFinalCommitTimeout.nanoseconds(for: .localFluidAudio),
            1_000_000_000
        )
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

    func testSessionRouteExecutionPlanUsesFileServiceWhenStreamingDisabled() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .cloud, modelName: "nova-3")
            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "nova-3",
                to: defaults
            )

            let plan = facts.plan(forceStreaming: false, defaults: defaults)

            XCTAssertEqual(
                executionSummary(for: plan.executionPlan),
                "file:cloud"
            )
        }
    }

    func testSessionRouteExecutionPlanPackagesStreamingAdapterPreloadAndTimeout() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .localFluidAudio, modelName: "parakeet-tdt-0.6b-v3")
            VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "parakeet-tdt-0.6b-v3",
                to: defaults
            )

            let plan = facts.plan(forceStreaming: true, defaults: defaults)
            let expectedSummary = [
                "streaming",
                "localFluidAudio",
                "localFluidAudio",
                "true",
                "\(VoiceInkStreamingFinalCommitTimeout.localFluidAudioNanoseconds)"
            ].joined(separator: ":")

            XCTAssertEqual(
                executionSummary(for: plan.executionPlan),
                expectedSummary
            )
        }
    }

    private func executionSummary(for plan: VoiceInkTranscriptionSessionExecutionPlan) -> String {
        plan.applyRuntimeState(
            file: { serviceRoute in
                "file:\(serviceRoute)"
            },
            streaming: { request in
                [
                    "streaming",
                    "\(request.serviceRoute)",
                    "\(request.adapterKind)",
                    "\(request.usesRollingPreload)",
                    "\(request.finalCommitTimeoutNanoseconds)"
                ].joined(separator: ":")
            }
        )
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

    private func powerModeData(_ configs: [[String: Any]]) -> Data {
        (try? JSONSerialization.data(withJSONObject: configs)) ?? Data()
    }

    private func powerModeConfigs(from defaults: UserDefaults) -> [[String: Any]] {
        guard let data = defaults.data(forKey: VoiceInkStreamingKeysMigration.defaultPowerModeConfigurationsKey),
              let configs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            XCTFail("Failed to decode power mode configs")
            return []
        }
        return configs
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

    private func assertSessionStarted(_ event: VoiceInkStreamingTranscriptionEvent) {
        guard case .sessionStarted = event else {
            XCTFail("Expected sessionStarted event")
            return
        }
    }

    private func assertText(
        _ event: VoiceInkStreamingTranscriptionEvent,
        expectedText: String
    ) {
        switch event {
        case .partial(let text), .committed(let text):
            XCTAssertEqual(text, expectedText)
        default:
            XCTFail("Expected text event")
        }
    }
}
