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

public struct VoiceInkWhisperVADRuntimeConfiguration: Equatable, Sendable {
    public let modelPath: String
    public let threshold: Float
    public let minSpeechDurationMs: Int32
    public let minSilenceDurationMs: Int32
    public let maxSpeechDurationSeconds: Float
    public let speechPadMs: Int32
    public let samplesOverlap: Float

    public init(
        modelPath: String,
        threshold: Float = VoiceInkWhisperRuntimeDefaults.vadThreshold,
        minSpeechDurationMs: Int32 = VoiceInkWhisperRuntimeDefaults.vadMinSpeechDurationMs,
        minSilenceDurationMs: Int32 = VoiceInkWhisperRuntimeDefaults.vadMinSilenceDurationMs,
        maxSpeechDurationSeconds: Float = VoiceInkWhisperRuntimeDefaults.vadMaxSpeechDurationSeconds,
        speechPadMs: Int32 = VoiceInkWhisperRuntimeDefaults.vadSpeechPadMs,
        samplesOverlap: Float = VoiceInkWhisperRuntimeDefaults.vadSamplesOverlap
    ) {
        self.modelPath = modelPath
        self.threshold = threshold
        self.minSpeechDurationMs = minSpeechDurationMs
        self.minSilenceDurationMs = minSilenceDurationMs
        self.maxSpeechDurationSeconds = maxSpeechDurationSeconds
        self.speechPadMs = speechPadMs
        self.samplesOverlap = samplesOverlap
    }

    public static func current(
        modelPath: String?,
        isEnabled: Bool = VoiceInkVADPreference.isEnabled()
    ) -> VoiceInkWhisperVADRuntimeConfiguration? {
        guard isEnabled, let modelPath, !modelPath.isEmpty else { return nil }
        return VoiceInkWhisperVADRuntimeConfiguration(modelPath: modelPath)
    }
}

public struct VoiceInkWhisperRuntimeConfiguration: Equatable, Sendable {
    public let language: String?
    public let prompt: String?
    public let threadCount: Int32
    public let temperature: Float
    public let vad: VoiceInkWhisperVADRuntimeConfiguration?

    public init(
        language: String? = nil,
        prompt: String? = nil,
        threadCount: Int32 = VoiceInkWhisperRuntimeDefaults.threadCount(),
        temperature: Float = VoiceInkWhisperRuntimeDefaults.transcriptionTemperature,
        vad: VoiceInkWhisperVADRuntimeConfiguration? = nil
    ) {
        self.language = language
        self.prompt = prompt
        self.threadCount = threadCount
        self.temperature = temperature
        self.vad = vad
    }

    public static func current(
        language: String? = nil,
        prompt: String? = nil,
        vadModelPath: String? = nil,
        defaults: UserDefaults = .standard,
        processorCount: Int = ProcessInfo.processInfo.processorCount
    ) -> VoiceInkWhisperRuntimeConfiguration {
        VoiceInkWhisperRuntimeConfiguration(
            language: VoiceInkTranscriptionLanguageSupport.requestLanguage(language),
            prompt: prompt,
            threadCount: VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: processorCount),
            temperature: VoiceInkWhisperRuntimeDefaults.transcriptionTemperature,
            vad: VoiceInkWhisperVADRuntimeConfiguration.current(
                modelPath: vadModelPath,
                isEnabled: VoiceInkVADPreference.isEnabled(from: defaults)
            )
        )
    }
}
