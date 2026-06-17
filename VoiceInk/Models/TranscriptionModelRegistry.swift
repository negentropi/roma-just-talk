import Foundation
import VoiceInkCore

enum TranscriptionModelRegistry {

    static var models: [any TranscriptionModel] {
        return predefinedModels + CustomCloudModelManager.shared.customModels
    }
    
    private static let predefinedModels: [any TranscriptionModel] = {
        let platformModels: [any TranscriptionModel] = [
            NativeAppleModel(spec: VoiceInkTranscriptionModelCatalog.nativeAppleModel)
        ] + VoiceInkTranscriptionModelCatalog.fluidAudioModels.map(FluidAudioModel.init(spec:))
        let localModels = VoiceInkWhisperModelFiles.downloadableModels.map(WhisperModel.init(spec:))
        let nonCloudModels = platformModels + localModels

        let cloudModels: [any TranscriptionModel] = CloudProviderRegistry.allProviders.flatMap { $0.models }
        return nonCloudModels + cloudModels
    }()
}
