import Foundation

public enum VoiceInkWhisperAudioSamples {
    public static func floatSamples(fromWAVData data: Data) -> [Float]? {
        VoiceInkPCM16Audio.leveledFloatSamples(
            fromWAVData: data,
            targetPeak: VoiceInkWhisperRuntimeDefaults.audioLevelingTargetPeak,
            noiseFloorPeak: VoiceInkWhisperRuntimeDefaults.audioLevelingNoiseFloorPeak,
            maxGain: VoiceInkWhisperRuntimeDefaults.audioLevelingMaxGain
        )
    }

    public static func floatSamples(fromWAVFileAt url: URL) throws -> [Float]? {
        try floatSamples(fromWAVData: Data(contentsOf: url))
    }
}
