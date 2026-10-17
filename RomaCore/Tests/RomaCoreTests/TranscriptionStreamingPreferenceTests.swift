import Foundation
import RomaCore

final class TranscriptionStreamingPreferenceTests: XCTestCase {
    func testStreamingEventsCarrySessionAndTextUpdates() {
        assertSessionStarted(.sessionStarted)
        assertText(.partial(text: "draft"), expectedText: "draft")
        assertText(.committed(text: "final"), expectedText: "final")
    }

    func testStreamingErrorEventCarriesOriginalError() {
        let error = RomaStreamingTranscriptionError.serverError("closed")
        guard case .error(let carriedError) = RomaStreamingTranscriptionEvent.error(error) else {
            XCTFail("Expected error event")
            return
        }

        XCTAssertEqual(
            carriedError.localizedDescription,
            "Streaming server error: closed"
        )
    }

    func testUnknownServerErrorFallbackPreservesExistingText() {
        XCTAssertEqual(RomaStreamingTranscriptionError.unknownServerErrorMessage, "Unknown error")
    }

    func testKeyPreservesExistingPerModelPattern() {
        XCTAssertEqual(RomaTranscriptionStreamingPreference.keyPrefix, "streaming-enabled-")
        XCTAssertEqual(
            RomaTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3"),
            "streaming-enabled-parakeet-tdt-0.6b-v3"
        )
    }

    func testServiceRouteClassifiesCloudAndLocalProviders() {
        XCTAssertTrue(RomaTranscriptionServiceRoute.cloud.isCloudTranscriptionProvider)
        XCTAssertFalse(RomaTranscriptionServiceRoute.cloud.isLocalTranscriptionProvider)
        XCTAssertFalse(RomaTranscriptionServiceRoute.localWhisper.isCloudTranscriptionProvider)
        XCTAssertTrue(RomaTranscriptionServiceRoute.localWhisper.isLocalTranscriptionProvider)
        XCTAssertFalse(RomaTranscriptionServiceRoute.localFluidAudio.isCloudTranscriptionProvider)
        XCTAssertTrue(RomaTranscriptionServiceRoute.localFluidAudio.isLocalTranscriptionProvider)
        XCTAssertFalse(RomaTranscriptionServiceRoute.nativeApple.isCloudTranscriptionProvider)
        XCTAssertTrue(RomaTranscriptionServiceRoute.nativeApple.isLocalTranscriptionProvider)
    }

    func testPendingStreamingStartupUsesRecordedFileFallbackWithoutWaiting() {
        XCTAssertEqual(
            RomaStreamingStartupResolutionPolicy.plan(
                hasPendingStartup: true,
                streamingFailed: false,
                supportsRecordedFileTranscription: true
            ),
            .cancelStartupAndUseRecordedFileFallback
        )
    }

    func testPendingStreamingOnlyStartupStillWaitsForConnection() {
        XCTAssertEqual(
            RomaStreamingStartupResolutionPolicy.plan(
                hasPendingStartup: true,
                streamingFailed: false,
                supportsRecordedFileTranscription: false
            ),
            .waitForStreamingStartup
        )
    }

    func testResolvedOrFailedStreamingStartupProceedsNormally() {
        XCTAssertEqual(
            RomaStreamingStartupResolutionPolicy.plan(
                hasPendingStartup: false,
                streamingFailed: false,
                supportsRecordedFileTranscription: true
            ),
            .proceed
        )
        XCTAssertEqual(
            RomaStreamingStartupResolutionPolicy.plan(
                hasPendingStartup: true,
                streamingFailed: true,
                supportsRecordedFileTranscription: true
            ),
            .proceed
        )
    }

    func testStreamingTranscriptAssemblyPreservesCommittedPreviewAndFinalText() {
        XCTAssertEqual(RomaStreamingTranscriptAssembly.committedText(["hello", "world"]), "hello world")
        XCTAssertEqual(RomaStreamingTranscriptAssembly.committedText([]), "")
        XCTAssertEqual(
            RomaStreamingTranscriptAssembly.previewText(
                committedSegments: [],
                partialText: "hel"
            ),
            "hel"
        )
        XCTAssertEqual(
            RomaStreamingTranscriptAssembly.previewText(
                committedSegments: ["hello", "world"],
                partialText: "hello world again"
            ),
            "hello world again"
        )
        XCTAssertEqual(
            RomaStreamingTranscriptAssembly.previewText(
                committedSegments: ["hello", "world"],
                partialText: "again"
            ),
            "hello world again"
        )
        XCTAssertEqual(
            RomaStreamingTranscriptAssembly.previewText(
                committedSegments: ["hello"],
                partialText: ""
            ),
            "hello "
        )
    }

    func testStreamingPreferenceDefaultsEnabledWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(RomaTranscriptionStreamingPreference.isEnabled(
                forModelName: "nova-3",
                in: defaults
            ))
        }
    }

    func testStreamingPreferenceSavesAndReadsOverride() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "nova-3",
                to: defaults
            )

            XCTAssertFalse(RomaTranscriptionStreamingPreference.isEnabled(
                forModelName: "nova-3",
                in: defaults
            ))
        }
    }

    func testShouldUseStreamingRejectsUnsupportedModels() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(RomaTranscriptionStreamingPreference.shouldUseStreaming(
                for: RomaTranscriptionStreamingModelSnapshot(
                    name: "whisper-base",
                    supportsStreaming: false
                ),
                in: defaults
            ))
        }
    }

    func testShouldUseStreamingForStreamingOnlyModelIgnoresStoredDisabledValue() {
        withIsolatedDefaults { defaults in
            RomaTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "ink-whisper",
                to: defaults
            )

            XCTAssertTrue(RomaTranscriptionStreamingPreference.shouldUseStreaming(
                for: RomaTranscriptionStreamingModelSnapshot(
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
            let model = RomaTranscriptionStreamingModelSnapshot(
                name: "universal-3-pro",
                supportsStreaming: true
            )

            XCTAssertTrue(RomaTranscriptionStreamingPreference.shouldUseStreaming(for: model, in: defaults))

            RomaTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: model.name,
                to: defaults
            )

            XCTAssertFalse(RomaTranscriptionStreamingPreference.shouldUseStreaming(for: model, in: defaults))
        }
    }

    func testMigrationKeysPreserveExistingStorageNames() {
        XCTAssertEqual(RomaStreamingKeysMigration.didMigrateKey, "streaming-keys-migrated")
        XCTAssertEqual(RomaStreamingKeysMigration.legacyParakeetStreamingEnabledKey, "parakeet-streaming-enabled")
        XCTAssertEqual(RomaStreamingKeysMigration.defaultPowerModeConfigurationsKey, "powerModeConfigurationsV2")
        XCTAssertEqual(RomaStreamingKeysMigration.powerModeSelectedTranscriptionModelNameKey, "selectedTranscriptionModelName")
        XCTAssertEqual(RomaUserDefaultsKey.powerModeConfigurations, "powerModeConfigurationsV2")
    }

    func testRunMigratesLegacyParakeetStreamingSettingToCurrentModels() {
        withIsolatedDefaults { defaults in
            defaults.set(false, forKey: RomaStreamingKeysMigration.legacyParakeetStreamingEnabledKey)

            XCTAssertTrue(RomaStreamingKeysMigration.run(in: defaults))

            XCTAssertNil(defaults.object(forKey: RomaStreamingKeysMigration.legacyParakeetStreamingEnabledKey))
            XCTAssertEqual(
                defaults.object(forKey: RomaTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v2")) as? Bool,
                false
            )
            XCTAssertEqual(
                defaults.object(forKey: RomaTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3")) as? Bool,
                false
            )
            XCTAssertTrue(defaults.bool(forKey: RomaStreamingKeysMigration.didMigrateKey))
        }
    }

    func testRunRepairsRemovedCurrentAndPowerModeTranscriptionModels() {
        withIsolatedDefaults { defaults in
            RomaCurrentTranscriptionModelPreference.saveModelName("stt-rt-v4", to: defaults)
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
                forKey: RomaStreamingKeysMigration.defaultPowerModeConfigurationsKey
            )

            RomaStreamingKeysMigration.run(in: defaults)

            XCTAssertEqual(
                RomaCurrentTranscriptionModelPreference.modelName(from: defaults),
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
            defaults.set(invalidData, forKey: RomaStreamingKeysMigration.defaultPowerModeConfigurationsKey)

            XCTAssertTrue(RomaStreamingKeysMigration.run(in: defaults))

            XCTAssertEqual(defaults.data(forKey: RomaStreamingKeysMigration.defaultPowerModeConfigurationsKey), invalidData)
            XCTAssertTrue(defaults.bool(forKey: RomaStreamingKeysMigration.didMigrateKey))
        }
    }

    func testRunSkipsAllWorkAfterMigrationFlagIsSet() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: RomaStreamingKeysMigration.didMigrateKey)
            defaults.set(false, forKey: RomaStreamingKeysMigration.legacyParakeetStreamingEnabledKey)
            RomaCurrentTranscriptionModelPreference.saveModelName("stt-rt-v4", to: defaults)

            XCTAssertFalse(RomaStreamingKeysMigration.run(in: defaults))

            XCTAssertEqual(
                defaults.object(forKey: RomaStreamingKeysMigration.legacyParakeetStreamingEnabledKey) as? Bool,
                false
            )
            XCTAssertEqual(
                RomaCurrentTranscriptionModelPreference.modelName(from: defaults),
                "stt-rt-v4"
            )
        }
    }

    func testStreamingModePresentationForStreamingOnlyModelsForcesStreamingToggle() {
        let presentation = RomaTranscriptionStreamingModePresentation(
            isStreamingEnabled: false,
            isStreamingOnly: true
        )

        XCTAssertEqual(presentation.streamingToggleTitle, "Streaming")
        XCTAssertTrue(presentation.isStreamingToggleForcedOn)
        XCTAssertTrue(presentation.isStreamingToggleDisabled)
        XCTAssertEqual(presentation.streamingToggleHelp, "This model only supports active-recording streaming")
    }

    func testStreamingModePresentationForEnabledBatchCapableModelUsesStreamingHelp() {
        let presentation = RomaTranscriptionStreamingModePresentation(
            isStreamingEnabled: true,
            isStreamingOnly: false
        )

        XCTAssertFalse(presentation.isStreamingToggleForcedOn)
        XCTAssertFalse(presentation.isStreamingToggleDisabled)
        XCTAssertEqual(
            presentation.streamingToggleHelp,
            "Streams active-recording audio; click to use saved-file batch mode"
        )
    }

    func testStreamingModePresentationForDisabledBatchCapableModelUsesBatchHelp() {
        let presentation = RomaTranscriptionStreamingModePresentation(
            isStreamingEnabled: false,
            isStreamingOnly: false
        )

        XCTAssertFalse(presentation.isStreamingToggleForcedOn)
        XCTAssertFalse(presentation.isStreamingToggleDisabled)
        XCTAssertEqual(
            presentation.streamingToggleHelp,
            "Saved-file batch mode; click to stream active-recording audio"
        )
    }

    func testTrailingSilenceDefaultsPreserveFluidAudioChunkPolicy() {
        XCTAssertEqual(RomaFluidAudioTranscriptionPolicy.trailingSilenceSeconds, 1)
        XCTAssertEqual(RomaFluidAudioTranscriptionPolicy.trailingSilenceSamples, 16_000)
        XCTAssertEqual(RomaFluidAudioTranscriptionPolicy.maxSingleChunkSamples, 240_000)
    }

    func testPaddedSamplesAppendTrailingSilenceWhenChunkFits() {
        let samples: [Float] = [0.1, -0.2, 0.3]

        let padded = RomaFluidAudioTranscriptionPolicy.paddedSamplesForTranscription(
            samples,
            trailingSilenceSamples: 2,
            maxSingleChunkSamples: 5
        )

        XCTAssertEqual(padded, [0.1, -0.2, 0.3, 0, 0])
    }

    func testPaddedSamplesPreserveChunkWhenSilenceWouldExceedLimit() {
        let samples: [Float] = [0.1, -0.2, 0.3, 0.4]

        let padded = RomaFluidAudioTranscriptionPolicy.paddedSamplesForTranscription(
            samples,
            trailingSilenceSamples: 2,
            maxSingleChunkSamples: 5
        )

        XCTAssertEqual(padded, samples)
    }

    func testResolveHingeStreamingAcceleratesPostKeyDownPassesWithoutChangingDefault() {
        let defaultConfig = AgreementConfig()
        let config = AgreementConfig.resolveHingeStreaming

        XCTAssertEqual(defaultConfig.transcribeIntervalSeconds, 1)
        XCTAssertEqual(config.transcribeIntervalSeconds, 0.35)
    }

    func testResolveHingeCommitReusesOnlyCompleteKeyDownHypothesis() {
        let complete = RomaFluidAudioTranscriptionPolicy.completeHypothesisCommitPlan(
            latestHypothesisText: " ready text ",
            latestHypothesisSampleCount: 48_000,
            absoluteSampleCount: 48_000
        )
        let incomplete = RomaFluidAudioTranscriptionPolicy.completeHypothesisCommitPlan(
            latestHypothesisText: "incomplete text",
            latestHypothesisSampleCount: 48_000,
            absoluteSampleCount: 48_001
        )
        let future = RomaFluidAudioTranscriptionPolicy.completeHypothesisCommitPlan(
            latestHypothesisText: "future text",
            latestHypothesisSampleCount: 48_001,
            absoluteSampleCount: 48_000
        )
        let blank = RomaFluidAudioTranscriptionPolicy.completeHypothesisCommitPlan(
            latestHypothesisText: " ",
            latestHypothesisSampleCount: 48_000,
            absoluteSampleCount: 48_200
        )

        XCTAssertEqual(complete.reusableText, "ready text")
        XCTAssertEqual(complete.pendingSamples, 0)
        XCTAssertFalse(complete.requiresFinalASR)
        XCTAssertNil(incomplete.reusableText)
        XCTAssertEqual(incomplete.pendingSamples, 1)
        XCTAssertTrue(incomplete.requiresFinalASR)
        XCTAssertNil(future.reusableText)
        XCTAssertTrue(future.requiresFinalASR)
        XCTAssertNil(blank.reusableText)
        XCTAssertEqual(blank.pendingSamples, 200)
        XCTAssertTrue(blank.requiresFinalASR)
    }

    func testResolveHingeCommitKeepsLiveHypothesisWhenFinalASRIsEmpty() {
        XCTAssertEqual(
            RomaFluidAudioTranscriptionPolicy.resolvedCommitText(
                finalASRText: " final transcript ",
                latestHypothesisText: "live hypothesis"
            ),
            "final transcript"
        )
        XCTAssertEqual(
            RomaFluidAudioTranscriptionPolicy.resolvedCommitText(
                finalASRText: " ",
                latestHypothesisText: " live hypothesis "
            ),
            "live hypothesis"
        )
        XCTAssertEqual(
            RomaFluidAudioTranscriptionPolicy.resolvedCommitText(
                finalASRText: nil,
                latestHypothesisText: " "
            ),
            ""
        )
    }

    func testTranscriptionPassSchedulingRequiresMinimumTotalAndNewAudio() {
        XCTAssertFalse(RomaFluidAudioTranscriptionPolicy.shouldRunTranscriptionPass(
            absoluteSampleCount: 15_999,
            lastTranscribedSampleCount: 0,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
        XCTAssertFalse(RomaFluidAudioTranscriptionPolicy.shouldRunTranscriptionPass(
            absoluteSampleCount: 24_000,
            lastTranscribedSampleCount: 12_000,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
        XCTAssertTrue(RomaFluidAudioTranscriptionPolicy.shouldRunTranscriptionPass(
            absoluteSampleCount: 28_000,
            lastTranscribedSampleCount: 12_000,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
    }

    func testSeekSamplePrefersHypothesisStartAndFallsBackToConfirmedEnd() {
        XCTAssertEqual(
            RomaFluidAudioTranscriptionPolicy.seekSample(
                hypothesisStartTime: 1.5,
                confirmedEndTime: 5,
                sampleRate: 16_000
            ),
            24_000
        )
        XCTAssertEqual(
            RomaFluidAudioTranscriptionPolicy.seekSample(
                hypothesisStartTime: 0,
                confirmedEndTime: 2,
                sampleRate: 16_000
            ),
            32_000
        )
        XCTAssertEqual(
            RomaFluidAudioTranscriptionPolicy.seekSample(
                hypothesisStartTime: -1,
                confirmedEndTime: -2,
                sampleRate: 16_000
            ),
            0
        )
    }

    func testBufferRelativeSeekAccountsForTrimmedSamples() {
        XCTAssertEqual(
            RomaFluidAudioTranscriptionPolicy.bufferRelativeSeek(
                seekSample: 24_000,
                trimmedSampleCount: 8_000
            ),
            16_000
        )
        XCTAssertEqual(
            RomaFluidAudioTranscriptionPolicy.bufferRelativeSeek(
                seekSample: 4_000,
                trimmedSampleCount: 8_000
            ),
            0
        )
    }

    func testTimedWordNormalizesCaseHyphenAndPunctuationForAgreement() {
        XCTAssertEqual(
            TimedWord(text: "Follow-up!", startTime: 0, endTime: 1).normalizedText,
            "follow up"
        )
    }

    func testFirstPassReturnsHypothesisWithoutConfirmation() {
        let engine = WordAgreementEngine(config: fastConfirmationConfig())
        let words = sentenceWords(["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."])

        let result = engine.processTranscriptionResult(words: words)

        XCTAssertEqual(result.fullText, "One two three. Four five six. Seven eight nine.")
        XCTAssertEqual(result.hypothesisText, "One two three. Four five six. Seven eight nine.")
        XCTAssertEqual(result.newlyConfirmedText, "")
        XCTAssertEqual(engine.confirmedText, "")
    }

    func testStableAgreementConfirmsThroughThirdLatestSentenceBoundary() {
        let engine = WordAgreementEngine(config: fastConfirmationConfig())
        let words = sentenceWords(["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."])

        _ = engine.processTranscriptionResult(words: words)
        let result = engine.processTranscriptionResult(words: words)

        XCTAssertEqual(result.newlyConfirmedText, "One two three.")
        XCTAssertEqual(result.hypothesisText, "Four five six. Seven eight nine.")
        XCTAssertEqual(result.fullText, "One two three. Four five six. Seven eight nine.")
        XCTAssertEqual(engine.confirmedText, "One two three.")
        XCTAssertEqual(engine.confirmedEndTime, 3)
        XCTAssertEqual(engine.hypothesisStartTime, 3)
    }

    func testLowConfidencePassDoesNotCountTowardConfirmation() {
        let engine = WordAgreementEngine(config: AgreementConfig(
            tokenConfirmationsNeeded: 2,
            minWordsToConfirm: 3
        ))
        let words = sentenceWords(["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."])

        _ = engine.processTranscriptionResult(words: words)
        _ = engine.processTranscriptionResult(words: words, resultConfidence: 0.01)
        let result = engine.processTranscriptionResult(words: words)

        XCTAssertEqual(result.newlyConfirmedText, "")
        XCTAssertEqual(engine.confirmedText, "")
    }

    func testLowBoundaryWordConfidencePreventsConfirmation() {
        let engine = WordAgreementEngine(config: fastConfirmationConfig())
        let words = sentenceWords(
            ["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."],
            lowConfidenceIndices: [1]
        )

        _ = engine.processTranscriptionResult(words: words)
        let result = engine.processTranscriptionResult(words: words)

        XCTAssertEqual(result.newlyConfirmedText, "")
        XCTAssertEqual(engine.confirmedText, "")
    }

    func testResetClearsAgreementState() {
        let engine = WordAgreementEngine(config: fastConfirmationConfig())
        let words = sentenceWords(["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."])
        _ = engine.processTranscriptionResult(words: words)
        _ = engine.processTranscriptionResult(words: words)

        engine.reset()

        XCTAssertEqual(engine.confirmedText, "")
        XCTAssertEqual(engine.confirmedEndTime, 0)
        XCTAssertEqual(engine.hypothesisStartTime, 0)
        XCTAssertEqual(engine.processTranscriptionResult(words: words).newlyConfirmedText, "")
    }

    func testStreamingFinalCommitTimeoutPreservesCloudDefault() {
        XCTAssertEqual(RomaStreamingFinalCommitTimeout.cloudNanoseconds, 10_000_000_000)
        XCTAssertEqual(
            RomaStreamingFinalCommitTimeout.nanoseconds(for: .cloud),
            10_000_000_000
        )
    }

    func testStreamingFinalCommitTimeoutPreservesLocalFluidAudioFastCommit() {
        XCTAssertEqual(RomaStreamingFinalCommitTimeout.localFluidAudioNanoseconds, 1_000_000_000)
        XCTAssertEqual(
            RomaStreamingFinalCommitTimeout.nanoseconds(for: .localFluidAudio),
            1_000_000_000
        )
    }

    func testSessionRoutePlanUsesFileTranscriptionWhenStreamingDisabled() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .cloud, modelName: "nova-3")
            RomaTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "nova-3",
                to: defaults
            )

            let plan = facts.plan(defaults: defaults)

            XCTAssertFalse(plan.usesStreaming)
            XCTAssertEqual(plan.serviceRoute, .cloud)
            XCTAssertNil(plan.streamingAdapterKind)
            XCTAssertNil(plan.finalCommitSource)
            XCTAssertNil(plan.finalCommitTimeoutNanoseconds)
        }
    }

    func testSessionRoutePlanUsesCloudStreamingAdapterAndTimeout() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .cloud, modelName: "nova-3")

            let plan = facts.plan(defaults: defaults)

            XCTAssertTrue(plan.usesStreaming)
            XCTAssertEqual(plan.streamingAdapterKind, .cloud)
            XCTAssertEqual(plan.finalCommitSource, .cloud)
            XCTAssertEqual(plan.finalCommitTimeoutNanoseconds, RomaStreamingFinalCommitTimeout.cloudNanoseconds)
        }
    }

    func testSessionRoutePlanUsesLocalFluidAudioStreamingAdapterAndTimeout() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .localFluidAudio, modelName: "parakeet-tdt-0.6b-v3")

            let plan = facts.plan(defaults: defaults)

            XCTAssertTrue(plan.usesStreaming)
            XCTAssertEqual(plan.streamingAdapterKind, .localFluidAudio)
            XCTAssertEqual(plan.finalCommitSource, .localFluidAudio)
            XCTAssertEqual(
                plan.finalCommitTimeoutNanoseconds,
                RomaStreamingFinalCommitTimeout.localFluidAudioNanoseconds
            )
        }
    }

    func testSessionRoutePlanRejectsStreamingForUnsupportedModels() {
        let facts = RomaTranscriptionSessionRouteFacts(
            serviceRoute: .localWhisper,
            streamingSnapshot: RomaTranscriptionStreamingModelSnapshot(
                name: "whisper-base",
                supportsStreaming: false
            )
        )

        let plan = facts.plan()

        XCTAssertFalse(plan.usesStreaming)
        XCTAssertEqual(plan.serviceRoute, .localWhisper)
        XCTAssertNil(plan.streamingAdapterKind)
        XCTAssertNil(plan.finalCommitSource)
    }

    func testSessionRouteExecutionPlanUsesFileServiceWhenStreamingDisabled() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .cloud, modelName: "nova-3")
            RomaTranscriptionStreamingPreference.saveIsEnabled(
                false,
                forModelName: "nova-3",
                to: defaults
            )

            let plan = facts.plan(defaults: defaults)

            XCTAssertEqual(
                executionSummary(for: plan.executionPlan),
                "file:cloud"
            )
        }
    }

    func testSessionRouteExecutionPlanPackagesStreamingAdapterAndTimeout() {
        withIsolatedDefaults { defaults in
            let facts = routeFacts(serviceRoute: .localFluidAudio, modelName: "parakeet-tdt-0.6b-v3")
            RomaTranscriptionStreamingPreference.saveIsEnabled(
                true,
                forModelName: "parakeet-tdt-0.6b-v3",
                to: defaults
            )

            let plan = facts.plan(defaults: defaults)
            let expectedSummary = [
                "streaming",
                "localFluidAudio",
                "localFluidAudio",
                "\(RomaStreamingFinalCommitTimeout.localFluidAudioNanoseconds)"
            ].joined(separator: ":")

            XCTAssertEqual(
                executionSummary(for: plan.executionPlan),
                expectedSummary
            )
        }
    }

    private func executionSummary(for plan: RomaTranscriptionSessionExecutionPlan) -> String {
        plan.applyRuntimeState(
            file: { serviceRoute in
                "file:\(serviceRoute)"
            },
            streaming: { request in
                [
                    "streaming",
                    "\(request.serviceRoute)",
                    "\(request.adapterKind)",
                    "\(request.finalCommitTimeoutNanoseconds)"
                ].joined(separator: ":")
            }
        )
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "RomaCore.TranscriptionStreamingPreferenceTests.\(UUID().uuidString)"
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
        guard let data = defaults.data(forKey: RomaStreamingKeysMigration.defaultPowerModeConfigurationsKey),
              let configs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            XCTFail("Failed to decode power mode configs")
            return []
        }
        return configs
    }

    private func routeFacts(
        serviceRoute: RomaTranscriptionServiceRoute,
        modelName: String
    ) -> RomaTranscriptionSessionRouteFacts {
        RomaTranscriptionSessionRouteFacts(
            serviceRoute: serviceRoute,
            streamingSnapshot: RomaTranscriptionStreamingModelSnapshot(
                name: modelName,
                supportsStreaming: true
            )
        )
    }

    private func fastConfirmationConfig() -> AgreementConfig {
        AgreementConfig(
            transcribeIntervalSeconds: 1,
            tokenConfirmationsNeeded: 1,
            minWordsToConfirm: 3,
            minPassConfidence: 0.15,
            minWordConfidence: 0.6
        )
    }

    private func sentenceWords(_ texts: [String], lowConfidenceIndices: Set<Int> = []) -> [TimedWord] {
        texts.enumerated().map { index, text in
            TimedWord(
                text: text,
                startTime: Double(index),
                endTime: Double(index + 1),
                confidence: lowConfidenceIndices.contains(index) ? 0.2 : 0.95
            )
        }
    }

    private func assertSessionStarted(_ event: RomaStreamingTranscriptionEvent) {
        guard case .sessionStarted = event else {
            XCTFail("Expected sessionStarted event")
            return
        }
    }

    private func assertText(
        _ event: RomaStreamingTranscriptionEvent,
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
