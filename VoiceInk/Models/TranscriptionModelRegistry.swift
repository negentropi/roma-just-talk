import Foundation
import VoiceInkCore

enum TranscriptionModelRegistry {

    static var models: [any TranscriptionModel] {
        return predefinedModels + CustomCloudModelManager.shared.customModels
    }

    static var defaultMacOSFluidAudioModel: FluidAudioModel {
        guard let model = predefinedModels.first(where: {
            $0.name == VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        }) as? FluidAudioModel else {
            preconditionFailure("Missing default macOS FluidAudio model")
        }
        return model
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
