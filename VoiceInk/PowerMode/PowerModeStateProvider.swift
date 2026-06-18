import Foundation
import VoiceInkCore

/// Protocol that VoiceInkEngine conforms to for power mode session management.
@MainActor
protocol PowerModeStateProvider: AnyObject {
    var currentTranscriptionModel: (any TranscriptionModel)? { get }
    var allAvailableModels: [any TranscriptionModel] { get }

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel)
    func cleanupModelResources() async
    func loadModel(_ model: VoiceInkWhisperLocalModelFile) async throws

    var availableModels: [VoiceInkWhisperLocalModelFile] { get }
}
