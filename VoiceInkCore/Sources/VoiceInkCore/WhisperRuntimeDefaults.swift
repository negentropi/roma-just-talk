import Foundation

public enum VoiceInkWhisperRuntimeDefaults {
    public static let maxThreadCount = 8
    public static let reservedProcessorCount = 2
    public static let transcriptionTemperature: Float = 0.2

    public static let vadThreshold: Float = 0.50
    public static let vadMinSpeechDurationMs: Int32 = 250
    public static let vadMinSilenceDurationMs: Int32 = 100
    public static let vadMaxSpeechDurationSeconds = Float.greatestFiniteMagnitude
    public static let vadSpeechPadMs: Int32 = 30
    public static let vadSamplesOverlap: Float = 0.1

    public static func threadCount(processorCount: Int = ProcessInfo.processInfo.processorCount) -> Int32 {
        Int32(max(1, min(maxThreadCount, processorCount - reservedProcessorCount)))
    }
}
