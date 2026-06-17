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
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperContext")

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
        let runtimeConfiguration = VoiceInkWhisperRuntimeConfiguration.current(
            language: language,
            prompt: prompt,
            vadModelPath: vadModelPath
        )
        let languageCString = runtimeConfiguration.language.map { Array($0.utf8CString) }
        let promptCString = runtimeConfiguration.prompt.map { Array($0.utf8CString) }
        let vadModelPathCString = runtimeConfiguration.vad?.modelPath.utf8CString
        
        params.print_realtime = true
        params.print_progress = false
        params.print_timestamps = true
        params.print_special = false
        params.translate = false
        params.n_threads = runtimeConfiguration.threadCount
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = false
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
        
        var success = true

        func runWhisper() {
            samples.withUnsafeBufferPointer { samplesBuffer in
                if whisper_full(context, params, samplesBuffer.baseAddress, Int32(samplesBuffer.count)) != 0 {
                    logger.error("❌ Failed to run whisper_full. VAD enabled: \(params.vad, privacy: .public)")
                    success = false
                }
            }
        }

        func runWithPrompt() {
            if let promptCString {
                promptCString.withUnsafeBufferPointer { promptBuffer in
                    params.initial_prompt = promptBuffer.baseAddress
                    runWhisper()
                }
            } else {
                params.initial_prompt = nil
                runWhisper()
            }
        }

        func runWithLanguage() {
            if let languageCString {
                languageCString.withUnsafeBufferPointer { languageBuffer in
                    params.language = languageBuffer.baseAddress
                    runWithPrompt()
                }
            } else {
                params.language = nil
                runWithPrompt()
            }
        }

        if let vadModelPathCString {
            vadModelPathCString.withUnsafeBufferPointer { vadModelPathBuffer in
                params.vad_model_path = vadModelPathBuffer.baseAddress
                runWithLanguage()
            }
        } else {
            runWithLanguage()
        }
        
        return success
    }

    func getTranscription() -> String {
        guard let context = context else { return "" }
        var transcription = ""
        for i in 0..<whisper_full_n_segments(context) {
            transcription += String(cString: whisper_full_get_segment_text(context, i))
        }
        return transcription
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
        #if targetEnvironment(simulator)
        params.use_gpu = false
        logger.info("Running on the simulator, using CPU")
        #else
        params.flash_attn = true // Enable flash attention for Metal
        logger.info("Flash attention enabled for Metal")
        #endif
        
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            self.context = context
        } else {
            logger.error("❌ Couldn't load model at \(path, privacy: .public)")
            throw VoiceInkEngineError.modelLoadFailed
        }
    }
    
    private func setVADModelPath(_ path: String?) {
        self.vadModelPath = path
        if path != nil {
            logger.info("VAD model loaded from bundle resources")
        }
    }

    func releaseResources() {
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
    }
}
