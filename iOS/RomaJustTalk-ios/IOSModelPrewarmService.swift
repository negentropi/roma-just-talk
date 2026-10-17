import Combine
import Foundation
import OSLog
import UIKit
import RomaCore

@MainActor
final class IOSModelPrewarmService: ObservableObject {
    static let shared = IOSModelPrewarmService()

    private var prewarmTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private let modelManager = LocalModelManager.shared
    private let settings = AppSettings.shared
    private let logger = RomaIOSLogger.localWhisper

    private init() {
        NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.schedulePrewarm(
                    diagnosticMessage: RomaModelPrewarmDiagnostics.iOSActivityScheduledMessage
                )
            }
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.cancelPrewarm()
                await self?.modelManager.releaseRetainedContext()
                await IOSFluidAudioRuntime.shared.release()
            }
        }
        .store(in: &cancellables)

        schedulePrewarm(
            diagnosticMessage: RomaModelPrewarmDiagnostics.appLaunchScheduledMessage
        )
    }

    func schedulePrewarm(diagnosticMessage: String? = nil) {
        prewarmTask?.cancel()
        if let diagnosticMessage {
            logger.notice("\(diagnosticMessage, privacy: .public)")
        }

        prewarmTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: RomaModelRuntimePreference.prewarmScheduleDelay
                )
                try Task.checkCancellation()
                await self?.performPrewarm()
            } catch is CancellationError {
            } catch {
                self?.logger.error("\(RomaModelPrewarmDiagnostics.failedMessage(errorDescription: error.localizedDescription), privacy: .public)")
            }
        }
    }

    func cancelPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
    }

    private func performPrewarm() async {
        let configuration = settings.currentTranscriptionRunSettings().configuration
        let modelName = configuration.transcriptionModel
        let isLocalWhisper = configuration.transcriptionProvider == .localWhisper
        let isLocalFluidAudio = configuration.transcriptionProvider == .localFluidAudio
        let hasModel: Bool
        if isLocalWhisper {
            hasModel = modelManager.managementSnapshot.modelPath(
                forRuntimeModelName: modelName
            ) != nil
        } else if isLocalFluidAudio {
            hasModel = FluidAudioModelManager.shared.isFluidAudioModelDownloaded(
                named: modelName
            )
        } else {
            hasModel = true
        }
        let plan = RomaModelPrewarmPlan.plan(
            isEnabled: RomaModelRuntimePreference.shouldPrewarmModelOnWake(),
            hasCurrentModel: hasModel,
            shouldPrewarmModel: isLocalWhisper || isLocalFluidAudio
        )

        guard plan.shouldRun else {
            if let message = plan.diagnosticMessage {
                logger.notice("\(message, privacy: .public)")
            }
            return
        }

        logger.notice("\(RomaModelPrewarmDiagnostics.prewarmingMessage(modelDisplayName: modelName), privacy: .public)")
        let startedAt = Date()
        do {
            if isLocalFluidAudio {
                try await IOSFluidAudioRuntime.shared.prewarm(modelName: modelName)
            } else {
                try await modelManager.prewarmContext(
                    forRuntimeModelName: modelName
                )
            }
            logger.notice("\(RomaModelPrewarmDiagnostics.completedMessage(duration: Date().timeIntervalSince(startedAt)), privacy: .public)")
        } catch is CancellationError {
        } catch {
            logger.error("\(RomaModelPrewarmDiagnostics.failedMessage(errorDescription: error.localizedDescription), privacy: .public)")
        }
    }
}
