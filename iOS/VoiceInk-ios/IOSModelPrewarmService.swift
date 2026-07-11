import Combine
import Foundation
import UIKit
import VoiceInkCore

@MainActor
final class IOSModelPrewarmService: ObservableObject {
    static let shared = IOSModelPrewarmService()

    private var prewarmTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private let modelManager = LocalModelManager.shared
    private let settings = AppSettings.shared
    private let logger = VoiceInkIOSLogger.localWhisper

    private init() {
        NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.schedulePrewarm(
                    diagnosticMessage: VoiceInkModelPrewarmDiagnostics.iOSActivityScheduledMessage
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
            }
        }
        .store(in: &cancellables)

        schedulePrewarm(
            diagnosticMessage: VoiceInkModelPrewarmDiagnostics.appLaunchScheduledMessage
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
                    for: VoiceInkModelRuntimePreference.prewarmScheduleDelay
                )
                try Task.checkCancellation()
                await self?.performPrewarm()
            } catch is CancellationError {
            } catch {
                self?.logger.error("\(VoiceInkModelPrewarmDiagnostics.failedMessage(errorDescription: error.localizedDescription), privacy: .public)")
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
        let hasModel = isLocalWhisper && modelManager.managementSnapshot.modelPath(
            forRuntimeModelName: modelName
        ) != nil
        let plan = VoiceInkModelPrewarmPlan.plan(
            isEnabled: VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(),
            hasCurrentModel: isLocalWhisper ? hasModel : true,
            shouldPrewarmModel: isLocalWhisper,
            hasSampleAudio: true
        )

        guard plan.shouldRun else {
            if let message = plan.diagnosticMessage {
                logger.notice("\(message, privacy: .public)")
            }
            return
        }

        logger.notice("\(VoiceInkModelPrewarmDiagnostics.prewarmingMessage(modelDisplayName: modelName), privacy: .public)")
        let startedAt = Date()
        do {
            try await modelManager.prewarmContext(
                forRuntimeModelName: modelName
            )
            logger.notice("\(VoiceInkModelPrewarmDiagnostics.completedMessage(duration: Date().timeIntervalSince(startedAt)), privacy: .public)")
        } catch is CancellationError {
        } catch {
            logger.error("\(VoiceInkModelPrewarmDiagnostics.failedMessage(errorDescription: error.localizedDescription), privacy: .public)")
        }
    }
}
