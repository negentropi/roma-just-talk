import Foundation
import VoiceInkCore
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif
import os

protocol SpeechActivityDetecting: Sendable {
    func containsSpeech(inPCM16LEData data: Data) -> Bool
}

final class SileroSpeechActivityDetector: SpeechActivityDetecting, @unchecked Sendable {
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "SileroSpeechActivityDetector")
    private let lock = NSLock()
    private let threshold: Float
    private var context: OpaquePointer?

    static func makeDefault() async -> SileroSpeechActivityDetector? {
        guard VoiceInkRollingBufferVADSettings.usesSilero(),
              let modelPath = VoiceInkVADModelFiles.sileroPath() else {
            return nil
        }

        return await Task.detached(priority: .utility) {
            SileroSpeechActivityDetector(modelPath: modelPath)
        }.value
    }

    init?(modelPath: String, threshold: Float = 0.5) {
        self.threshold = threshold

        var params = whisper_vad_default_context_params()
        params.n_threads = Int32(max(1, min(2, ProcessInfo.processInfo.processorCount - 1)))
        params.use_gpu = false

        guard let context = whisper_vad_init_from_file_with_params(modelPath, params) else {
            logger.error("Failed to load Silero VAD model at \(modelPath, privacy: .public)")
            return nil
        }

        self.context = context
    }

    deinit {
        if let context {
            whisper_vad_free(context)
        }
    }

    func containsSpeech(inPCM16LEData data: Data) -> Bool {
        let samples = VoiceInkPCM16Audio.floatSamples(fromLittleEndianData: data)
        guard !samples.isEmpty else { return false }

        lock.lock()
        defer { lock.unlock() }

        guard let context else { return true }

        let didRun = samples.withUnsafeBufferPointer { buffer in
            whisper_vad_detect_speech_no_reset(context, buffer.baseAddress, Int32(buffer.count))
        }

        guard didRun else {
            logger.notice("Rolling preload VAD detection failed; treating chunk as speech")
            return true
        }

        let probabilityCount = whisper_vad_n_probs(context)
        guard probabilityCount > 0, let probabilities = whisper_vad_probs(context) else {
            return false
        }

        for index in 0..<Int(probabilityCount) {
            if probabilities[index] >= threshold {
                return true
            }
        }

        return false
    }
}
