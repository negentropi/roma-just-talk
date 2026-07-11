import FluidAudio
import Foundation
import VoiceInkCore

struct IOSFluidAudioTranscriptionService: VoiceInkAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) async throws -> String {
        guard VoiceInkTranscriptionModelCatalog.fluidAudioModels.contains(where: {
            $0.name == model
        }) else {
            throw IOSFluidAudioTranscriptionError.invalidModel
        }

        return try await IOSFluidAudioRuntime.shared.transcribe(
            fileURL: fileURL,
            modelName: model,
            languageCode: language
        )
    }
}

enum IOSFluidAudioTranscriptionError: LocalizedError {
    case invalidModel
    case modelNotDownloaded
    case invalidAudio

    var errorDescription: String? {
        switch self {
        case .invalidModel:
            return "The selected Parakeet model is unavailable."
        case .modelNotDownloaded:
            return "Download the selected Parakeet model before transcribing."
        case .invalidAudio:
            return "The recording could not be prepared for Parakeet transcription."
        }
    }
}

actor IOSFluidAudioRuntime {
    static let shared = IOSFluidAudioRuntime()

    private var asrManager: AsrManager?
    private var vadManager: VadManager?
    private var activeVersion: AsrModelVersion?

    func transcribe(
        fileURL: URL,
        modelName: String,
        languageCode: String?
    ) async throws -> String {
        try Task.checkCancellation()
        let version = FluidAudioModelManager.asrVersion(for: modelName)
        try await ensureLoaded(version: version)

        guard let asrManager else {
            throw IOSFluidAudioTranscriptionError.modelNotDownloaded
        }
        guard let audioSamples = try VoiceInkPCM16Audio.floatSamples(fromWAVFileAt: fileURL) else {
            throw IOSFluidAudioTranscriptionError.invalidAudio
        }

        var speechAudio = audioSamples
        let duration = Double(audioSamples.count) / VoiceInkPCM16Audio.mono16kSampleRate
        if duration >= VoiceInkFluidAudioTranscriptionPolicy.batchVADMinimumDurationSeconds,
           VoiceInkVADPreference.isEnabled() {
            if vadManager == nil {
                vadManager = try? await VadManager(config: VadConfig(
                    defaultThreshold: VoiceInkFluidAudioTranscriptionPolicy.batchVADThreshold
                ))
            }
            if let vadManager,
               let segments = try? await vadManager.segmentSpeechAudio(audioSamples),
               !segments.isEmpty {
                speechAudio = segments.flatMap { $0 }
            }
        }

        try Task.checkCancellation()
        speechAudio = VoiceInkFluidAudioTranscriptionPolicy.paddedSamplesForTranscription(speechAudio)
        var decoderState = TdtDecoderState.make(
            decoderLayers: await asrManager.decoderLayerCount
        )
        let result = try await asrManager.transcribe(
            speechAudio,
            decoderState: &decoderState,
            language: FluidAudioModelManager.languageHint(
                from: languageCode,
                for: modelName
            )
        )
        try Task.checkCancellation()
        return TextNormalizer.shared.normalizeSentence(result.text)
    }

    func prewarm(modelName: String) async throws {
        try await ensureLoaded(
            version: FluidAudioModelManager.asrVersion(for: modelName)
        )
    }

    func release() async {
        await asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
        activeVersion = nil
    }

    private func ensureLoaded(version: AsrModelVersion) async throws {
        if asrManager != nil, activeVersion == version {
            return
        }

        let directory = AsrModels.defaultCacheDirectory(for: version)
        guard AsrModels.modelsExist(at: directory, version: version) else {
            throw IOSFluidAudioTranscriptionError.modelNotDownloaded
        }

        await asrManager?.cleanup()
        let models = try await AsrModels.load(from: directory, version: version)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
        activeVersion = version
    }
}
