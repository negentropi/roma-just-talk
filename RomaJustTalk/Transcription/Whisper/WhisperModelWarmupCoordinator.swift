import Foundation
import Combine
import RomaCore

@MainActor
final class WhisperModelWarmupCoordinator: ObservableObject {
    static let shared = WhisperModelWarmupCoordinator()

    @Published private(set) var warmingModels: Set<String> = []

    private init() {}

    func isWarming(modelNamed name: String) -> Bool {
        warmingModels.contains(name)
    }

    func scheduleWarmup(for model: WhisperModel, whisperModelManager: WhisperModelManager) {
        guard RomaWhisperModelWarmupPolicy.shouldScheduleWarmup(
            supportsCoreML: RomaWhisperModelFiles.supportsCoreML(forModelName: model.name),
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
                    whisperModelManager.logger.error("\(RomaWhisperModelWarmupDiagnostics.failedMessage(modelName: model.name, errorDescription: error.localizedDescription), privacy: .public)")
                }
            }

            await MainActor.run {
                self.warmingModels.remove(model.name)
            }
        }
    }

    private func runWarmup(for model: WhisperModel, whisperModelManager: WhisperModelManager) async throws {
        guard let localModel = RomaWhisperModelFiles.downloadedLocalModelFile(
            forModelName: model.name,
            in: whisperModelManager.availableModels
        ) else {
            throw RomaEngineError.modelLoadFailed
        }
        try await whisperModelManager.prewarmModel(localModel)
    }
}
