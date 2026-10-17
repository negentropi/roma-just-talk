import Foundation
import RomaCore

enum TranscriptionModelRegistry {

    static var models: [any TranscriptionModel] {
        return predefinedModels + CustomCloudModelManager.shared.customModels
    }

    static var defaultMacOSFluidAudioModel: FluidAudioModel {
        FluidAudioModel(spec: RomaTranscriptionModelCatalog.defaultMacOSFluidAudioModel)
    }
    
    private static let predefinedModels: [any TranscriptionModel] = {
        let platformModels: [any TranscriptionModel] = [
            NativeAppleModel(spec: RomaTranscriptionModelCatalog.nativeAppleModel),
            QwenModel()
        ] + RomaTranscriptionModelCatalog.fluidAudioModels.map(FluidAudioModel.init(spec:))
        let localModels = RomaWhisperModelFiles.downloadableModels.map(WhisperModel.init(spec:))
        let nonCloudModels = platformModels + localModels

        let cloudModels: [any TranscriptionModel] = RomaMacOSTranscriptionModelProvider.allCases.flatMap { modelProvider in
            return modelProvider.cloudModelSpecs.map { spec -> any TranscriptionModel in
                CloudModel(spec: spec, provider: modelProvider)
            }
        }
        return nonCloudModels + cloudModels
    }()
}
