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
    private let prewarmAudioURL = Bundle.main.url(forResource: "sound7", withExtension: "wav")

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

        logger.notice("ModelPrewarmService initialized - listening for wake and app launch")
    }

    // MARK: - Trigger Handlers

    /// Trigger on app launch (cold start)
    private func schedulePrewarmOnAppLaunch() {
        logger.notice("App launched, scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    /// Trigger on wake from sleep or screen unlock
    @objc private func schedulePrewarm() {
        logger.notice("Mac activity detected (wake/unlock), scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    // MARK: - Core Prewarming Logic

    private func performPrewarm() async {
        guard shouldPrewarm() else { return }

        guard let audioURL = prewarmAudioURL else {
            logger.error("❌ Prewarm audio file (sound7.wav) not found")
            return
        }

        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
            logger.notice("No model selected, skipping prewarm")
            return
        }

        logger.notice("Prewarming \(currentModel.displayName, privacy: .public)")
        let startTime = Date()

        do {
            let _ = try await serviceRegistry.transcribe(audioURL: audioURL, model: currentModel)
            let duration = Date().timeIntervalSince(startTime)

            logger.notice("Prewarm completed in \(String(format: "%.2f", duration), privacy: .public)s")

        } catch {
            logger.error("❌ Prewarm failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Validation

    private func shouldPrewarm() -> Bool {
        guard VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake() else {
            logger.notice("Prewarm disabled by user")
            return false
        }

        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            return false
        }

        guard model.transcriptionRuntimeResourcePlan.shouldPrewarmModel else {
            logger.notice("Skipping prewarm - cloud models don't need it")
            return false
        }

        return true
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("ModelPrewarmService deinitialized")
    }
}
