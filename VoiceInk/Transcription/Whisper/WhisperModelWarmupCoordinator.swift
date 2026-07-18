import Foundation
import Combine
import VoiceInkCore

@MainActor
final class WhisperModelWarmupCoordinator: ObservableObject {
    static let shared = WhisperModelWarmupCoordinator()

    @Published private(set) var warmingModels: Set<String> = []

    private init() {}

    func isWarming(modelNamed name: String) -> Bool {
        warmingModels.contains(name)
    }

    func scheduleWarmup(for model: WhisperModel, whisperModelManager: WhisperModelManager) {
        guard VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
            supportsCoreML: VoiceInkWhisperModelFiles.supportsCoreML(forModelName: model.name),
            isAlreadyWarming: warmingModels.contains(model.name)
        ) else {
            return
        }

        warmingModels.insert(model.name)

        Task {
            do {
                try await runWarmup(for: model, whisperModelManager: whisperModelManager)
            } catch {
                await MainActor.run {
                    whisperModelManager.logger.error("\(VoiceInkWhisperModelWarmupDiagnostics.failedMessage(modelName: model.name, errorDescription: error.localizedDescription), privacy: .public)")
                }
            }

            await MainActor.run {
                self.warmingModels.remove(model.name)
            }
        }
    }

    private func runWarmup(for model: WhisperModel, whisperModelManager: WhisperModelManager) async throws {
        guard let localModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
            forModelName: model.name,
            in: whisperModelManager.availableModels
        ) else {
            throw VoiceInkEngineError.modelLoadFailed
        }
        try await whisperModelManager.prewarmModel(localModel)
    }
}
