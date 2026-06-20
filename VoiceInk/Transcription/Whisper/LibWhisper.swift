import Foundation
import VoiceInkCore
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif
import os


// Meet Whisper C++ constraint: Don't access from more than one thread at a time.
actor WhisperContext {
    private var context: OpaquePointer?
    private var vadModelPath: String?
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkWhisperRuntimeDiagnostics.logCategory
    )

    private init() {}

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        if let context = context {
            whisper_free(context)
        }
    }

    func fullTranscribe(samples: [Float], language: String? = nil, prompt: String? = nil) -> Bool {
        guard let context = context else { return false }
        
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        let invocationPlan = VoiceInkWhisperRuntimeInvocationPlan.current(
            language: language,
            prompt: prompt,
            vadModelPath: vadModelPath
        )
        let runtimeConfiguration = invocationPlan.configuration
        
        params.print_realtime = runtimeConfiguration.options.printRealtime
        params.print_progress = runtimeConfiguration.options.printProgress
        params.print_timestamps = runtimeConfiguration.options.printTimestamps
        params.print_special = runtimeConfiguration.options.printSpecial
        params.translate = runtimeConfiguration.options.translate
        params.n_threads = runtimeConfiguration.threadCount
        params.offset_ms = runtimeConfiguration.options.offsetMilliseconds
        params.no_context = runtimeConfiguration.options.noContext
        params.single_segment = runtimeConfiguration.options.singleSegment
        params.temperature = runtimeConfiguration.temperature

        whisper_reset_timings(context)
        
        if let vad = runtimeConfiguration.vad {
            params.vad = true
            
            var vadParams = whisper_vad_default_params()
            vadParams.threshold = vad.threshold
            vadParams.min_speech_duration_ms = vad.minSpeechDurationMs
            vadParams.min_silence_duration_ms = vad.minSilenceDurationMs
            vadParams.max_speech_duration_s = vad.maxSpeechDurationSeconds
            vadParams.speech_pad_ms = vad.speechPadMs
            vadParams.samples_overlap = vad.samplesOverlap
            params.vad_params = vadParams
        } else {
            params.vad = false
            params.vad_model_path = nil
        }

        return invocationPlan.withUnsafeCStringPointers { languagePointer, promptPointer, vadModelPathPointer in
            params.language = languagePointer
            params.initial_prompt = promptPointer
            params.vad_model_path = vadModelPathPointer

            var success = true
            samples.withUnsafeBufferPointer { samplesBuffer in
                if whisper_full(context, params, samplesBuffer.baseAddress, Int32(samplesBuffer.count)) != 0 {
                    logger.error("❌ Failed to run whisper_full. VAD enabled: \(params.vad, privacy: .public)")
                    success = false
                }
            }
            return success
        }
    }

    func getTranscription() -> String {
        guard let context = context else { return "" }
        var segments: [String] = []
        for i in 0..<whisper_full_n_segments(context) {
            segments.append(String(cString: whisper_full_get_segment_text(context, i)))
        }
        return VoiceInkWhisperTranscriptSegments.joinedText(segments)
    }

    static func createContext(path: String) async throws -> WhisperContext {
        let whisperContext = WhisperContext()
        try await whisperContext.initializeModel(path: path)
        
        // Load VAD model from bundle resources
        let vadModelPath = VoiceInkVADModelFiles.sileroPath()
        await whisperContext.setVADModelPath(vadModelPath)
        
        return whisperContext
    }
    
    private func initializeModel(path: String) throws {
        var params = whisper_context_default_params()
        let runtimePlan = VoiceInkWhisperContextRuntimePlan.current()
        if let useGPU = runtimePlan.useGPU {
            params.use_gpu = useGPU
        }
        if let flashAttention = runtimePlan.flashAttention {
            params.flash_attn = flashAttention
        }
        logger.info("\(runtimePlan.diagnosticMessage, privacy: .public)")
        
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            self.context = context
        } else {
            logger.error("❌ Couldn't load model at \(path, privacy: .public)")
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: .macOS)
        }
    }
    
    private func setVADModelPath(_ path: String?) {
        self.vadModelPath = path
        if path != nil {
            logger.info("\(VoiceInkWhisperRuntimeDiagnostics.vadBundleModelLoadedMessage, privacy: .public)")
        }
    }

    func releaseResources() {
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
    }
}
