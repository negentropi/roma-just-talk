import Foundation

public enum RomaWhisperTranscriptSegments {
    public static func joinedText(_ segments: [String]) -> String {
        segments.joined()
    }

    public static func joinedText(
        segmentCount: Int32,
        textAt index: (Int32) -> String?
    ) -> String {
        guard segmentCount > 0 else { return "" }

        var segments: [String] = []
        segments.reserveCapacity(Int(segmentCount))

        for segmentIndex in 0..<segmentCount {
            if let text = index(segmentIndex) {
                segments.append(text)
            }
        }

        return joinedText(segments)
    }
}

public enum RomaWhisperRuntimeDefaults {
    public static let maxThreadCount = 8
    public static let reservedProcessorCount = 2
    public static let printRealtime = true
    public static let printProgress = false
    public static let printTimestamps = true
    public static let printSpecial = false
    public static let translate = false
    public static let offsetMilliseconds: Int32 = 0
    public static let noContext = true
    public static let singleSegment = false
    public static let transcriptionTemperature: Float = 0.2
    public static let audioLevelingTargetPeak: Int16 = 12_000
    public static let audioLevelingNoiseFloorPeak: Int16 = 32
    public static let audioLevelingMaxGain: Float = 16

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

public enum RomaWhisperRuntimeDiagnostics {
    public static let logCategory = "WhisperContext"
    public static let simulatorCPUModeMessage = "Running on the simulator, using CPU"
    public static let metalFlashAttentionMessage = "Flash attention enabled for Metal"
    public static let vadBundleModelLoadedMessage = "VAD model loaded from bundle resources"
    public static let vadModelPathMissingWarningMessage = "VAD model path not found, VAD will be disabled."

    public static func transcriptionFailedMessage(
        isVADEnabled: Bool,
        platform: RomaLocalWhisperPlatform
    ) -> String {
        "\(diagnosticPrefix(for: platform))Failed to run whisper_full. VAD enabled: \(isVADEnabled)"
    }

    public static func modelLoadFailedMessagePrefix(
        platform: RomaLocalWhisperPlatform
    ) -> String {
        "\(diagnosticPrefix(for: platform))Couldn't load model at"
    }

    private static func diagnosticPrefix(for platform: RomaLocalWhisperPlatform) -> String {
        switch platform {
        case .macOS:
            return "❌ "
        case .iOS:
            return ""
        }
    }
}

public enum RomaWhisperContextEnvironment: Equatable, Sendable {
    case simulator
    case device

    public static var current: RomaWhisperContextEnvironment {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        return .device
        #endif
    }
}

public struct RomaWhisperContextRuntimePlan: Equatable, Sendable {
    public let useGPU: Bool?
    public let flashAttention: Bool?
    public let diagnosticMessage: String

    public init(
        useGPU: Bool?,
        flashAttention: Bool?,
        diagnosticMessage: String
    ) {
        self.useGPU = useGPU
        self.flashAttention = flashAttention
        self.diagnosticMessage = diagnosticMessage
    }

    public static func current(
        environment: RomaWhisperContextEnvironment = .current
    ) -> RomaWhisperContextRuntimePlan {
        switch environment {
        case .simulator:
            return RomaWhisperContextRuntimePlan(
                useGPU: false,
                flashAttention: nil,
                diagnosticMessage: RomaWhisperRuntimeDiagnostics.simulatorCPUModeMessage
            )
        case .device:
            return RomaWhisperContextRuntimePlan(
                useGPU: nil,
                flashAttention: true,
                diagnosticMessage: RomaWhisperRuntimeDiagnostics.metalFlashAttentionMessage
            )
        }
    }
}

public protocol RomaWhisperContextParameterSink {
    var use_gpu: Bool { get set }
    var flash_attn: Bool { get set }
}

public extension RomaWhisperContextRuntimePlan {
    func apply<Parameters: RomaWhisperContextParameterSink>(to params: inout Parameters) {
        if let useGPU {
            params.use_gpu = useGPU
        }

        if let flashAttention {
            params.flash_attn = flashAttention
        }
    }
}

public struct RomaWhisperRuntimeOptions: Equatable, Sendable {
    public let printRealtime: Bool
    public let printProgress: Bool
    public let printTimestamps: Bool
    public let printSpecial: Bool
    public let translate: Bool
    public let offsetMilliseconds: Int32
    public let noContext: Bool
    public let singleSegment: Bool

    public init(
        printRealtime: Bool = RomaWhisperRuntimeDefaults.printRealtime,
        printProgress: Bool = RomaWhisperRuntimeDefaults.printProgress,
        printTimestamps: Bool = RomaWhisperRuntimeDefaults.printTimestamps,
        printSpecial: Bool = RomaWhisperRuntimeDefaults.printSpecial,
        translate: Bool = RomaWhisperRuntimeDefaults.translate,
        offsetMilliseconds: Int32 = RomaWhisperRuntimeDefaults.offsetMilliseconds,
        noContext: Bool = RomaWhisperRuntimeDefaults.noContext,
        singleSegment: Bool = RomaWhisperRuntimeDefaults.singleSegment
    ) {
        self.printRealtime = printRealtime
        self.printProgress = printProgress
        self.printTimestamps = printTimestamps
        self.printSpecial = printSpecial
        self.translate = translate
        self.offsetMilliseconds = offsetMilliseconds
        self.noContext = noContext
        self.singleSegment = singleSegment
    }
}

public struct RomaWhisperVADRuntimeConfiguration: Equatable, Sendable {
    public let modelPath: String
    public let threshold: Float
    public let minSpeechDurationMs: Int32
    public let minSilenceDurationMs: Int32
    public let maxSpeechDurationSeconds: Float
    public let speechPadMs: Int32
    public let samplesOverlap: Float

    public init(
        modelPath: String,
        threshold: Float = RomaWhisperRuntimeDefaults.vadThreshold,
        minSpeechDurationMs: Int32 = RomaWhisperRuntimeDefaults.vadMinSpeechDurationMs,
        minSilenceDurationMs: Int32 = RomaWhisperRuntimeDefaults.vadMinSilenceDurationMs,
        maxSpeechDurationSeconds: Float = RomaWhisperRuntimeDefaults.vadMaxSpeechDurationSeconds,
        speechPadMs: Int32 = RomaWhisperRuntimeDefaults.vadSpeechPadMs,
        samplesOverlap: Float = RomaWhisperRuntimeDefaults.vadSamplesOverlap
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
        isEnabled: Bool = RomaVADPreference.isEnabled()
    ) -> RomaWhisperVADRuntimeConfiguration? {
        guard isEnabled, let modelPath, !modelPath.isEmpty else { return nil }
        return RomaWhisperVADRuntimeConfiguration(modelPath: modelPath)
    }
}

public struct RomaWhisperRuntimeConfiguration: Equatable, Sendable {
    public let language: String?
    public let prompt: String?
    public let options: RomaWhisperRuntimeOptions
    public let threadCount: Int32
    public let temperature: Float
    public let vad: RomaWhisperVADRuntimeConfiguration?

    public init(
        language: String? = nil,
        prompt: String? = nil,
        options: RomaWhisperRuntimeOptions = RomaWhisperRuntimeOptions(),
        threadCount: Int32 = RomaWhisperRuntimeDefaults.threadCount(),
        temperature: Float = RomaWhisperRuntimeDefaults.transcriptionTemperature,
        vad: RomaWhisperVADRuntimeConfiguration? = nil
    ) {
        self.language = language
        self.prompt = prompt
        self.options = options
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
    ) -> RomaWhisperRuntimeConfiguration {
        RomaWhisperRuntimeConfiguration(
            language: RomaTranscriptionLanguageSupport.requestLanguage(language),
            prompt: prompt,
            threadCount: RomaWhisperRuntimeDefaults.threadCount(processorCount: processorCount),
            temperature: RomaWhisperRuntimeDefaults.transcriptionTemperature,
            vad: RomaWhisperVADRuntimeConfiguration.current(
                modelPath: vadModelPath,
                isEnabled: RomaVADPreference.isEnabled(from: defaults)
            )
        )
    }
}

public protocol RomaWhisperRuntimeVADParameterSink {
    var threshold: Float { get set }
    var min_speech_duration_ms: Int32 { get set }
    var min_silence_duration_ms: Int32 { get set }
    var max_speech_duration_s: Float { get set }
    var speech_pad_ms: Int32 { get set }
    var samples_overlap: Float { get set }
}

public protocol RomaWhisperRuntimeFullParameterSink {
    associatedtype VADParameters: RomaWhisperRuntimeVADParameterSink

    var print_realtime: Bool { get set }
    var print_progress: Bool { get set }
    var print_timestamps: Bool { get set }
    var print_special: Bool { get set }
    var translate: Bool { get set }
    var n_threads: Int32 { get set }
    var offset_ms: Int32 { get set }
    var no_context: Bool { get set }
    var single_segment: Bool { get set }
    var temperature: Float { get set }
    var vad: Bool { get set }
    var vad_params: VADParameters { get set }
}

public extension RomaWhisperRuntimeConfiguration {
    func apply<Parameters: RomaWhisperRuntimeFullParameterSink>(
        to params: inout Parameters,
        makeVADParameters: () -> Parameters.VADParameters
    ) {
        params.print_realtime = options.printRealtime
        params.print_progress = options.printProgress
        params.print_timestamps = options.printTimestamps
        params.print_special = options.printSpecial
        params.translate = options.translate
        params.n_threads = threadCount
        params.offset_ms = options.offsetMilliseconds
        params.no_context = options.noContext
        params.single_segment = options.singleSegment
        params.temperature = temperature

        guard let vad else {
            params.vad = false
            return
        }

        params.vad = true
        var vadParams = makeVADParameters()
        vad.apply(to: &vadParams)
        params.vad_params = vadParams
    }
}

private extension RomaWhisperVADRuntimeConfiguration {
    func apply<Parameters: RomaWhisperRuntimeVADParameterSink>(to params: inout Parameters) {
        params.threshold = threshold
        params.min_speech_duration_ms = minSpeechDurationMs
        params.min_silence_duration_ms = minSilenceDurationMs
        params.max_speech_duration_s = maxSpeechDurationSeconds
        params.speech_pad_ms = speechPadMs
        params.samples_overlap = samplesOverlap
    }
}

public struct RomaWhisperRuntimeInvocationPlan: Equatable, Sendable {
    public let configuration: RomaWhisperRuntimeConfiguration

    public init(configuration: RomaWhisperRuntimeConfiguration) {
        self.configuration = configuration
    }

    public static func current(
        language: String? = nil,
        prompt: String? = nil,
        vadModelPath: String? = nil,
        defaults: UserDefaults = .standard,
        processorCount: Int = ProcessInfo.processInfo.processorCount
    ) -> RomaWhisperRuntimeInvocationPlan {
        RomaWhisperRuntimeInvocationPlan(
            configuration: RomaWhisperRuntimeConfiguration.current(
                language: language,
                prompt: prompt,
                vadModelPath: vadModelPath,
                defaults: defaults,
                processorCount: processorCount
            )
        )
    }

    public func withUnsafeCStringPointers<Result>(
        _ body: (
            _ languagePointer: UnsafePointer<CChar>?,
            _ promptPointer: UnsafePointer<CChar>?,
            _ vadModelPathPointer: UnsafePointer<CChar>?
        ) -> Result
    ) -> Result {
        let languageCString = configuration.language.map { Array($0.utf8CString) }
        let promptCString = configuration.prompt.map { Array($0.utf8CString) }
        let vadModelPathCString = configuration.vad?.modelPath.utf8CString

        func withPromptPointer(
            languagePointer: UnsafePointer<CChar>?,
            vadModelPathPointer: UnsafePointer<CChar>?
        ) -> Result {
            if let promptCString {
                return promptCString.withUnsafeBufferPointer { promptBuffer in
                    body(languagePointer, promptBuffer.baseAddress, vadModelPathPointer)
                }
            }

            return body(languagePointer, nil, vadModelPathPointer)
        }

        func withLanguagePointer(vadModelPathPointer: UnsafePointer<CChar>?) -> Result {
            if let languageCString {
                return languageCString.withUnsafeBufferPointer { languageBuffer in
                    withPromptPointer(
                        languagePointer: languageBuffer.baseAddress,
                        vadModelPathPointer: vadModelPathPointer
                    )
                }
            }

            return withPromptPointer(languagePointer: nil, vadModelPathPointer: vadModelPathPointer)
        }

        if let vadModelPathCString {
            return vadModelPathCString.withUnsafeBufferPointer { vadModelPathBuffer in
                withLanguagePointer(vadModelPathPointer: vadModelPathBuffer.baseAddress)
            }
        }

        return withLanguagePointer(vadModelPathPointer: nil)
    }
}

public enum RomaLocalWhisperFailure: Equatable, Sendable {
    case modelUnavailable
    case modelLoadFailed
    case audioProcessingFailed
    case transcriptionFailed
}

public enum RomaLocalWhisperPlatform: Equatable, Sendable {
    case macOS
    case iOS
}

public enum RomaLocalWhisperFailurePolicy {
    public static func error(
        for failure: RomaLocalWhisperFailure,
        platform: RomaLocalWhisperPlatform
    ) -> RomaEngineError {
        switch (platform, failure) {
        case (.macOS, .modelUnavailable), (.macOS, .modelLoadFailed):
            return .modelLoadFailed
        case (.macOS, .audioProcessingFailed), (.iOS, .audioProcessingFailed):
            return .audioProcessingFailed
        case (.macOS, .transcriptionFailed):
            return .whisperCoreFailed
        case (.iOS, .modelUnavailable):
            return .localModelUnavailable
        case (.iOS, .modelLoadFailed):
            return .localModelLoadFailed
        case (.iOS, .transcriptionFailed):
            return .whisperTranscriptionFailed
        }
    }
}


public enum RomaLocalWhisperTranscriptionDiagnostics {
    public static let macOSAudioSamplesProcessingFailedMessage = "❌ Failed to process audio samples for local Whisper transcription."
    public static let macOSCoreTranscriptionFailedMessage = "❌ Core transcription engine failed (whisper_full)."
    public static let macOSTranscriptionCompletedMessage = "Whisper transcription completed successfully."
    public static let iOSStartingLocalTranscriptionMessage = "Starting local transcription."
    public static let iOSAudioProcessingFailedMessage = "Audio processing failed."
    public static let iOSTranscriptionFailedMessage = "Transcription failed."
    public static let iOSContextResourcesReleasedMessage = "Whisper context resources released."
    public static let iOSTranscriptionCompletedMessage = "Transcription completed successfully."

    public static func macOSInitiatingLocalTranscriptionMessage(modelDisplayName: String) -> String {
        "Initiating local transcription for model: \(modelDisplayName)"
    }

    public static func macOSUsingLoadedModelMessage(modelName: String) -> String {
        "Using already loaded model: \(modelName)"
    }

    public static func macOSModelFileNotFoundMessage(modelName: String) -> String {
        "❌ Model file not found for: \(modelName)"
    }

    public static func macOSLoadingModelMessage(modelName: String) -> String {
        "Loading model: \(modelName)"
    }

    public static func macOSModelLoadFailedMessage(modelName: String, localizedDescription: String) -> String {
        "❌ Failed to load model: \(modelName) - \(localizedDescription)"
    }

    public static func iOSUsingModelMessage(modelPath: String) -> String {
        "Using model at \(modelPath)"
    }

    public static func iOSProcessedAudioSamplesMessage(count: Int) -> String {
        "Processed \(count) audio samples."
    }

    public static func iOSAudioProcessingFailedMessage(localizedDescription: String) -> String {
        "Audio processing failed: \(localizedDescription)"
    }
}

public struct RomaLocalWhisperContextPlan<Context> {
    public let context: Context
    public let shouldReleaseContext: Bool
    public let shouldReleaseContextOnFailure: Bool

    public init(
        context: Context,
        shouldReleaseContext: Bool,
        shouldReleaseContextOnFailure: Bool? = nil
    ) {
        self.context = context
        self.shouldReleaseContext = shouldReleaseContext
        self.shouldReleaseContextOnFailure = shouldReleaseContextOnFailure ?? shouldReleaseContext
    }
}

public struct RomaLocalWhisperTranscriptionRequest: Equatable, Sendable {
    public let audioURL: URL
    public let language: String?
    public let prompt: String?
    public let failurePlatform: RomaLocalWhisperPlatform
    public let mapsThrownAudioSampleErrors: Bool

    public init(
        audioURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        failurePlatform: RomaLocalWhisperPlatform,
        mapsThrownAudioSampleErrors: Bool = true
    ) {
        self.audioURL = audioURL
        self.language = language
        self.prompt = prompt
        self.failurePlatform = failurePlatform
        self.mapsThrownAudioSampleErrors = mapsThrownAudioSampleErrors
    }

    public static func macOS(
        audioURL: URL,
        isMultilingual: Bool = true,
        defaults: UserDefaults = .standard
    ) -> RomaLocalWhisperTranscriptionRequest {
        let language = RomaTranscriptionLanguagePreference.selectedLanguage(
            source: .whisper, from: defaults, isMultilingual: isMultilingual
        )
        // A language fallback also needs its own prompt, without replacing the user's saved prompt.
        let prompt = language == RomaTranscriptionLanguagePreference.selectedLanguage(from: defaults)
            ? RomaTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(from: defaults)
            : RomaLocalWhisperPromptCatalog.prompt(
                for: language, customPrompts: RomaLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults)
            )
        return RomaLocalWhisperTranscriptionRequest(
            audioURL: audioURL,
            language: language,
            prompt: prompt,
            failurePlatform: .macOS,
            mapsThrownAudioSampleErrors: false
        )
    }

    public static func iOS(
        audioURL: URL,
        language: String? = nil,
        prompt: String? = nil
    ) -> RomaLocalWhisperTranscriptionRequest {
        RomaLocalWhisperTranscriptionRequest(
            audioURL: audioURL,
            language: language,
            prompt: prompt ?? "",
            failurePlatform: .iOS
        )
    }
}

public struct RomaLocalWhisperTranscriptionActions<Context> {
    public let resolveContext: () async throws -> RomaLocalWhisperContextPlan<Context>
    public let readAudioSamples: (URL) throws -> [Float]?
    public let runTranscription: (Context, [Float], String?, String?) async -> Bool
    public let transcriptionText: (Context) async -> String
    public let releaseContext: (Context) async -> Void

    public init(
        resolveContext: @escaping () async throws -> RomaLocalWhisperContextPlan<Context>,
        readAudioSamples: @escaping (URL) throws -> [Float]?,
        runTranscription: @escaping (Context, [Float], String?, String?) async -> Bool,
        transcriptionText: @escaping (Context) async -> String,
        releaseContext: @escaping (Context) async -> Void
    ) {
        self.resolveContext = resolveContext
        self.readAudioSamples = readAudioSamples
        self.runTranscription = runTranscription
        self.transcriptionText = transcriptionText
        self.releaseContext = releaseContext
    }
}

public enum RomaLocalWhisperTranscriptionFlow {
    public static func transcribe<Context>(
        request: RomaLocalWhisperTranscriptionRequest,
        actions: RomaLocalWhisperTranscriptionActions<Context>
    ) async throws -> String {
        try Task.checkCancellation()
        let contextPlan = try await actions.resolveContext()

        do {
            try Task.checkCancellation()
            let samples = try readSamples(
                request: request,
                actions: actions
            )
            try Task.checkCancellation()

            let success = await actions.runTranscription(
                contextPlan.context,
                samples,
                request.language,
                request.prompt
            )
            try Task.checkCancellation()
            guard success else {
                throw RomaLocalWhisperFailurePolicy.error(
                    for: .transcriptionFailed,
                    platform: request.failurePlatform
                )
            }

            let text = await actions.transcriptionText(contextPlan.context)
            try Task.checkCancellation()
            await releaseIfNeeded(contextPlan, afterFailure: false, actions: actions)
            return text
        } catch {
            await releaseIfNeeded(contextPlan, afterFailure: true, actions: actions)
            throw error
        }
    }

    private static func readSamples<Context>(
        request: RomaLocalWhisperTranscriptionRequest,
        actions: RomaLocalWhisperTranscriptionActions<Context>
    ) throws -> [Float] {
        do {
            guard let samples = try actions.readAudioSamples(request.audioURL) else {
                throw RomaLocalWhisperFailurePolicy.error(
                    for: .audioProcessingFailed,
                    platform: request.failurePlatform
                )
            }
            return samples
        } catch let error as RomaEngineError {
            throw error
        } catch {
            guard request.mapsThrownAudioSampleErrors else { throw error }
            throw RomaLocalWhisperFailurePolicy.error(
                for: .audioProcessingFailed,
                platform: request.failurePlatform
            )
        }
    }

    private static func releaseIfNeeded<Context>(
        _ contextPlan: RomaLocalWhisperContextPlan<Context>,
        afterFailure: Bool,
        actions: RomaLocalWhisperTranscriptionActions<Context>
    ) async {
        guard contextPlan.shouldReleaseContext else { return }
        guard !afterFailure || contextPlan.shouldReleaseContextOnFailure else { return }
        await actions.releaseContext(contextPlan.context)
    }
}
