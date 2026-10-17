import Foundation
import RomaCore

/// Protocol that RomaEngine conforms to for power mode session management.
@MainActor
protocol PowerModeStateProvider: AnyObject {
    var currentTranscriptionModel: (any TranscriptionModel)? { get }
    var allAvailableModels: [any TranscriptionModel] { get }

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel)
    func cleanupModelResources() async
    func loadModel(_ model: RomaWhisperLocalModelFile) async throws

    var availableModels: [RomaWhisperLocalModelFile] { get }
}
