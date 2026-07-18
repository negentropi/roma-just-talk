import Foundation
import SwiftData
import os
import VoiceInkCore
import AppKit

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let transcriptionModelManager: TranscriptionModelManager
    private let whisperModelManager: WhisperModelManager
    private let modelContext: ModelContext
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.modelPrewarm
    )
    private let serviceRegistry: TranscriptionServiceRegistry

    init(
        transcriptionModelManager: TranscriptionModelManager,
        whisperModelManager: WhisperModelManager,
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry? = nil
    ) {
        self.transcriptionModelManager = transcriptionModelManager
        self.whisperModelManager = whisperModelManager
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry ?? TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )
        setupNotifications()
        schedulePrewarmOnAppLaunch()
    }

    // MARK: - Notification Setup

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        // Trigger on wake from sleep
        center.addObserver(
            self,
            selector: #selector(schedulePrewarm),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        logger.notice("\(VoiceInkModelPrewarmDiagnostics.initializedMessage, privacy: .public)")
    }

    // MARK: - Trigger Handlers

    /// Trigger on app launch (cold start)
    private func schedulePrewarmOnAppLaunch() {
        logger.notice("\(VoiceInkModelPrewarmDiagnostics.appLaunchScheduledMessage, privacy: .public)")
        scheduleDelayedPrewarm()
    }

    /// Trigger on wake from sleep or screen unlock
    @objc private func schedulePrewarm() {
        logger.notice("\(VoiceInkModelPrewarmDiagnostics.macActivityScheduledMessage, privacy: .public)")
        scheduleDelayedPrewarm()
    }

    private func scheduleDelayedPrewarm() {
        Task {
            try? await Task.sleep(for: VoiceInkModelRuntimePreference.prewarmScheduleDelay)
            await performPrewarm()
        }
    }

    // MARK: - Core Prewarming Logic

    private func performPrewarm() async {
        let currentModel = transcriptionModelManager.currentTranscriptionModel
        let prewarmPlan = VoiceInkModelPrewarmPlan.plan(
            isEnabled: VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(),
            hasCurrentModel: currentModel != nil,
            shouldPrewarmModel: currentModel?.transcriptionRuntimeResourcePlan.shouldPrewarmModel ?? false
        )

        guard prewarmPlan.shouldRun else {
            if let diagnosticMessage = prewarmPlan.diagnosticMessage {
                logger.notice("\(diagnosticMessage, privacy: .public)")
            }
            return
        }
        guard let currentModel else { return }

        logger.notice("\(VoiceInkModelPrewarmDiagnostics.prewarmingMessage(modelDisplayName: currentModel.displayName), privacy: .public)")
        let startTime = Date()

        do {
            try await currentModel.transcriptionRuntimeResourcePlan.applyRecordingStartupRuntimeState(
                loadLocalWhisperModel: {
                    guard let localModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                        forModelName: currentModel.name,
                        in: self.whisperModelManager.availableModels
                    ) else {
                        throw VoiceInkEngineError.modelLoadFailed
                    }
                    try await self.whisperModelManager.prewarmModel(localModel)
                },
                loadLocalFluidAudioModel: {
                    guard let fluidAudioModel = currentModel as? FluidAudioModel else {
                        throw VoiceInkEngineError.modelLoadFailed
                    }
                    try await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidAudioModel)
                }
            )
            let duration = Date().timeIntervalSince(startTime)

            logger.notice("\(VoiceInkModelPrewarmDiagnostics.completedMessage(duration: duration), privacy: .public)")
        } catch is CancellationError {
        } catch {
            logger.error("\(VoiceInkModelPrewarmDiagnostics.failedMessage(errorDescription: error.localizedDescription), privacy: .public)")
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("\(VoiceInkModelPrewarmDiagnostics.deinitializedMessage, privacy: .public)")
    }
}
