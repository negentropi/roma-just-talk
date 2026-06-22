import Foundation
import VoiceInkCore
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif
import os

extension whisper_context_params: VoiceInkWhisperContextParameterSink {}
extension whisper_full_params: VoiceInkWhisperRuntimeFullParameterSink {}
extension whisper_vad_params: VoiceInkWhisperRuntimeVADParameterSink {}

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
        runtimeConfiguration.apply(to: &params, makeVADParameters: whisper_vad_default_params)

        whisper_reset_timings(context)

        return invocationPlan.withUnsafeCStringPointers { languagePointer, promptPointer, vadModelPathPointer in
            params.language = languagePointer
            params.initial_prompt = promptPointer
            params.vad_model_path = vadModelPathPointer

            var success = true
            samples.withUnsafeBufferPointer { samplesBuffer in
                if whisper_full(context, params, samplesBuffer.baseAddress, Int32(samplesBuffer.count)) != 0 {
                    logger.error("\(VoiceInkWhisperRuntimeDiagnostics.transcriptionFailedMessage(isVADEnabled: params.vad, platform: .macOS), privacy: .public)")
                    success = false
                }
            }
            return success
        }
    }

    func getTranscription() -> String {
        guard let context = context else { return "" }

        return VoiceInkWhisperTranscriptSegments.joinedText(segmentCount: whisper_full_n_segments(context)) { index in
            guard let text = whisper_full_get_segment_text(context, index) else { return nil }
            return String(cString: text)
        }
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
        runtimePlan.apply(to: &params)
        logger.info("\(runtimePlan.diagnosticMessage, privacy: .public)")
        
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            self.context = context
        } else {
            logger.error("\(VoiceInkWhisperRuntimeDiagnostics.modelLoadFailedMessagePrefix(platform: .macOS), privacy: .public) \(path, privacy: .public)")
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
