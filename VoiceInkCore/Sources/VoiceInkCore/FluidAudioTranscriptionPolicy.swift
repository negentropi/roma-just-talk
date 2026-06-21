import Foundation

public struct VoiceInkFluidAudioCachedFinalTextPlan: Equatable, Sendable {
    public let text: String?
    public let pendingSamples: Int
    public let isTooStale: Bool
}

public enum VoiceInkFluidAudioTranscriptionPolicy {
    public static let trailingSilenceSeconds: Double = 1
    public static let maxSingleChunkSamples = 240_000

    public static var trailingSilenceSamples: Int {
        VoiceInkPCM16Audio.sampleCount(forMono16kDuration: trailingSilenceSeconds)
    }

    public static func paddedSamplesForTranscription(
        _ samples: [Float],
        trailingSilenceSamples: Int = trailingSilenceSamples,
        maxSingleChunkSamples: Int = maxSingleChunkSamples
    ) -> [Float] {
        guard trailingSilenceSamples > 0 else {
            return samples
        }

        guard samples.count + trailingSilenceSamples <= maxSingleChunkSamples else {
            return samples
        }

        return samples + [Float](repeating: 0, count: trailingSilenceSamples)
    }

    public static func shouldScheduleImmediatePass(
        config: AgreementConfig,
        hasImmediatePassInFlight: Bool,
        absoluteSampleCount: Int,
        lastScheduledSampleCount: Int,
        minimumAudioSamples: Int,
        minimumNewSamples: Int
    ) -> Bool {
        config.runsImmediatePassOnBufferedAudio &&
        !hasImmediatePassInFlight &&
        absoluteSampleCount >= minimumAudioSamples &&
        absoluteSampleCount - lastScheduledSampleCount >= minimumNewSamples
    }

    public static func shouldRunTranscriptionPass(
        absoluteSampleCount: Int,
        lastTranscribedSampleCount: Int,
        minimumAudioSamples: Int,
        minimumNewSamples: Int
    ) -> Bool {
        absoluteSampleCount - lastTranscribedSampleCount >= minimumNewSamples &&
        absoluteSampleCount >= minimumAudioSamples
    }

    public static func seekSample(
        hypothesisStartTime: Double,
        confirmedEndTime: Double,
        sampleRate: Double
    ) -> Int {
        let seekTime = hypothesisStartTime > 0 ? hypothesisStartTime : confirmedEndTime
        return max(0, Int(seekTime * sampleRate))
    }

    public static func bufferRelativeSeek(
        seekSample: Int,
        trimmedSampleCount: Int
    ) -> Int {
        max(0, seekSample - trimmedSampleCount)
    }

    public static func cachedFinalTextPlan(
        latestHypothesisText: String,
        latestHypothesisSampleCount: Int,
        absoluteSampleCount: Int,
        maxCachedFinalizationLagSamples: Int
    ) -> VoiceInkFluidAudioCachedFinalTextPlan {
        let cachedText = latestHypothesisText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cachedText.isEmpty else {
            return VoiceInkFluidAudioCachedFinalTextPlan(
                text: nil,
                pendingSamples: 0,
                isTooStale: false
            )
        }

        let pendingSamples = max(0, absoluteSampleCount - latestHypothesisSampleCount)
        guard pendingSamples <= maxCachedFinalizationLagSamples else {
            return VoiceInkFluidAudioCachedFinalTextPlan(
                text: nil,
                pendingSamples: pendingSamples,
                isTooStale: true
            )
        }

        return VoiceInkFluidAudioCachedFinalTextPlan(
            text: cachedText,
            pendingSamples: pendingSamples,
            isTooStale: false
        )
    }
}
