import Foundation
import RomaCore

// MARK: - RecorderStateProvider

extension RomaEngine: RecorderStateProvider {}

// MARK: - PowerModeStateProvider

extension RomaEngine: PowerModeStateProvider {
    var currentTranscriptionModel: (any TranscriptionModel)? {
        transcriptionModelManager.currentTranscriptionModel
    }

    var allAvailableModels: [any TranscriptionModel] {
        transcriptionModelManager.allAvailableModels
    }

    var availableModels: [RomaWhisperLocalModelFile] {
        whisperModelManager.availableModels
    }

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        transcriptionModelManager.setDefaultTranscriptionModel(model)
    }

    func cleanupModelResources() async {
        await cleanupResources()
    }

    func loadModel(_ model: RomaWhisperLocalModelFile) async throws {
        try await whisperModelManager.loadModel(model)
    }
}
