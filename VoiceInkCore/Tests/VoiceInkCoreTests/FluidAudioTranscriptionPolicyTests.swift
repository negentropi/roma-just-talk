import Foundation
@testable import VoiceInkCore

final class FluidAudioTranscriptionPolicyTests: XCTestCase {
    func testDownloadStatusPresentationPreservesFluidAudioDownloadCopy() {
        XCTAssertEqual(VoiceInkFluidAudioDownloadStatus.compactDownloadingStatusText, "Downloading...")

        let preparing = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: -0.2,
            phase: .preparingDownload
        )
        XCTAssertEqual(preparing.fractionCompleted, 0)
        XCTAssertEqual(preparing.message, "Preparing FluidAudio download...")
        XCTAssertEqual(preparing.percentText, "0%")

        let listing = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.1,
            phase: .listingFiles
        )
        XCTAssertEqual(listing.message, "Listing files from repository...")

        let checkingCache = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.2,
            phase: .checkingCachedModels
        )
        XCTAssertEqual(checkingCache.message, "Checking cached models...")

        let downloading = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.427,
            phase: .downloadingFiles(completedFiles: 3, totalFiles: 7)
        )
        XCTAssertEqual(downloading.message, "Downloading models: 3/7 files")
        XCTAssertEqual(downloading.percentText, "42%")

        let finalizing = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 1.4,
            phase: .finalizingModels
        )
        XCTAssertEqual(finalizing.fractionCompleted, 1)
        XCTAssertEqual(finalizing.message, "Finalizing models...")
        XCTAssertEqual(finalizing.percentText, "100%")

        let compiling = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.8,
            phase: .compiling(modelComponentName: "Parakeet.mlmodelc")
        )
        XCTAssertEqual(compiling.message, "Compiling Parakeet")
    }

    func testTrailingSilenceDefaultsPreserveFluidAudioChunkPolicy() {
        XCTAssertEqual(VoiceInkFluidAudioTranscriptionPolicy.trailingSilenceSeconds, 1)
        XCTAssertEqual(VoiceInkFluidAudioTranscriptionPolicy.trailingSilenceSamples, 16_000)
        XCTAssertEqual(VoiceInkFluidAudioTranscriptionPolicy.maxSingleChunkSamples, 240_000)
    }

    func testPaddedSamplesAppendTrailingSilenceWhenChunkFits() {
        let samples: [Float] = [0.1, -0.2, 0.3]

        let padded = VoiceInkFluidAudioTranscriptionPolicy.paddedSamplesForTranscription(
            samples,
            trailingSilenceSamples: 2,
            maxSingleChunkSamples: 5
        )

        XCTAssertEqual(padded, [0.1, -0.2, 0.3, 0, 0])
    }

    func testPaddedSamplesPreserveChunkWhenSilenceWouldExceedLimit() {
        let samples: [Float] = [0.1, -0.2, 0.3, 0.4]

        let padded = VoiceInkFluidAudioTranscriptionPolicy.paddedSamplesForTranscription(
            samples,
            trailingSilenceSamples: 2,
            maxSingleChunkSamples: 5
        )

        XCTAssertEqual(padded, samples)
    }

    func testImmediatePassSchedulingRequiresEnabledConfigNoInFlightTaskAndEnoughNewAudio() {
        let disabledConfig = AgreementConfig(runsImmediatePassOnBufferedAudio: false)
        let enabledConfig = AgreementConfig(runsImmediatePassOnBufferedAudio: true)

        XCTAssertFalse(VoiceInkFluidAudioTranscriptionPolicy.shouldScheduleImmediatePass(
            config: disabledConfig,
            hasImmediatePassInFlight: false,
            absoluteSampleCount: 32_000,
            lastScheduledSampleCount: 0,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
        XCTAssertFalse(VoiceInkFluidAudioTranscriptionPolicy.shouldScheduleImmediatePass(
            config: enabledConfig,
            hasImmediatePassInFlight: true,
            absoluteSampleCount: 32_000,
            lastScheduledSampleCount: 0,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
        XCTAssertFalse(VoiceInkFluidAudioTranscriptionPolicy.shouldScheduleImmediatePass(
            config: enabledConfig,
            hasImmediatePassInFlight: false,
            absoluteSampleCount: 15_999,
            lastScheduledSampleCount: 0,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
        XCTAssertFalse(VoiceInkFluidAudioTranscriptionPolicy.shouldScheduleImmediatePass(
            config: enabledConfig,
            hasImmediatePassInFlight: false,
            absoluteSampleCount: 20_000,
            lastScheduledSampleCount: 8_000,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
        XCTAssertTrue(VoiceInkFluidAudioTranscriptionPolicy.shouldScheduleImmediatePass(
            config: enabledConfig,
            hasImmediatePassInFlight: false,
            absoluteSampleCount: 24_000,
            lastScheduledSampleCount: 8_000,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
    }

    func testTranscriptionPassSchedulingRequiresMinimumTotalAndNewAudio() {
        XCTAssertFalse(VoiceInkFluidAudioTranscriptionPolicy.shouldRunTranscriptionPass(
            absoluteSampleCount: 15_999,
            lastTranscribedSampleCount: 0,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
        XCTAssertFalse(VoiceInkFluidAudioTranscriptionPolicy.shouldRunTranscriptionPass(
            absoluteSampleCount: 24_000,
            lastTranscribedSampleCount: 12_000,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
        XCTAssertTrue(VoiceInkFluidAudioTranscriptionPolicy.shouldRunTranscriptionPass(
            absoluteSampleCount: 28_000,
            lastTranscribedSampleCount: 12_000,
            minimumAudioSamples: 16_000,
            minimumNewSamples: 16_000
        ))
    }

    func testSeekSamplePrefersHypothesisStartAndFallsBackToConfirmedEnd() {
        XCTAssertEqual(
            VoiceInkFluidAudioTranscriptionPolicy.seekSample(
                hypothesisStartTime: 1.5,
                confirmedEndTime: 5,
                sampleRate: 16_000
            ),
            24_000
        )
        XCTAssertEqual(
            VoiceInkFluidAudioTranscriptionPolicy.seekSample(
                hypothesisStartTime: 0,
                confirmedEndTime: 2,
                sampleRate: 16_000
            ),
            32_000
        )
        XCTAssertEqual(
            VoiceInkFluidAudioTranscriptionPolicy.seekSample(
                hypothesisStartTime: -1,
                confirmedEndTime: -2,
                sampleRate: 16_000
            ),
            0
        )
    }

    func testBufferRelativeSeekAccountsForTrimmedSamples() {
        XCTAssertEqual(
            VoiceInkFluidAudioTranscriptionPolicy.bufferRelativeSeek(
                seekSample: 24_000,
                trimmedSampleCount: 8_000
            ),
            16_000
        )
        XCTAssertEqual(
            VoiceInkFluidAudioTranscriptionPolicy.bufferRelativeSeek(
                seekSample: 4_000,
                trimmedSampleCount: 8_000
            ),
            0
        )
    }

    func testCachedFinalTextPlanReturnsFreshTrimmedHypothesis() {
        let plan = VoiceInkFluidAudioTranscriptionPolicy.cachedFinalTextPlan(
            latestHypothesisText: " hello world ",
            latestHypothesisSampleCount: 10_000,
            absoluteSampleCount: 12_000,
            maxCachedFinalizationLagSamples: 4_000
        )

        XCTAssertEqual(plan.text, "hello world")
        XCTAssertEqual(plan.pendingSamples, 2_000)
        XCTAssertFalse(plan.isTooStale)
    }

    func testCachedFinalTextPlanRejectsBlankAndStaleHypotheses() {
        let blankPlan = VoiceInkFluidAudioTranscriptionPolicy.cachedFinalTextPlan(
            latestHypothesisText: " ",
            latestHypothesisSampleCount: 10_000,
            absoluteSampleCount: 12_000,
            maxCachedFinalizationLagSamples: 4_000
        )
        XCTAssertNil(blankPlan.text)
        XCTAssertEqual(blankPlan.pendingSamples, 0)
        XCTAssertFalse(blankPlan.isTooStale)

        let stalePlan = VoiceInkFluidAudioTranscriptionPolicy.cachedFinalTextPlan(
            latestHypothesisText: "old",
            latestHypothesisSampleCount: 10_000,
            absoluteSampleCount: 15_001,
            maxCachedFinalizationLagSamples: 5_000
        )
        XCTAssertNil(stalePlan.text)
        XCTAssertEqual(stalePlan.pendingSamples, 5_001)
        XCTAssertTrue(stalePlan.isTooStale)
    }
}
