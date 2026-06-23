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
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "ModelPrewarm")
    private let serviceRegistry: TranscriptionServiceRegistry
    private var prewarmAudioURL: URL? {
        VoiceInkModelPrewarmSamplePolicy.firstAvailableURL { resource in
            Bundle.main.url(
                forResource: resource.name,
                withExtension: resource.fileExtension,
                subdirectory: resource.subdirectory
            )
        }
    }

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
        let audioURL = prewarmAudioURL
        let prewarmPlan = VoiceInkModelPrewarmPlan.plan(
            isEnabled: VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(),
            hasCurrentModel: currentModel != nil,
            shouldPrewarmModel: currentModel?.transcriptionRuntimeResourcePlan.shouldPrewarmModel ?? false,
            hasSampleAudio: audioURL != nil
        )

        guard prewarmPlan.shouldRun else {
            if let diagnosticMessage = prewarmPlan.diagnosticMessage {
                logger.notice("\(diagnosticMessage, privacy: .public)")
            }
            return
        }
        guard let currentModel, let audioURL else { return }

        logger.notice("\(VoiceInkModelPrewarmDiagnostics.prewarmingMessage(modelDisplayName: currentModel.displayName), privacy: .public)")
        let startTime = Date()

        do {
            let _ = try await serviceRegistry.transcribe(audioURL: audioURL, model: currentModel)
            let duration = Date().timeIntervalSince(startTime)

            logger.notice("\(VoiceInkModelPrewarmDiagnostics.completedMessage(durationText: String(format: "%.2f", duration)), privacy: .public)")

        } catch {
            logger.error("\(VoiceInkModelPrewarmDiagnostics.failedMessage(errorDescription: error.localizedDescription), privacy: .public)")
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("\(VoiceInkModelPrewarmDiagnostics.deinitializedMessage, privacy: .public)")
    }
}
