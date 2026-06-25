import Foundation
import SwiftData
import OSLog
import VoiceInkCore

class TranscriptionAutoCleanupService {
    static let shared = TranscriptionAutoCleanupService()

    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.transcriptionAutoCleanupService
    )
    private var modelContext: ModelContext?

    private var recordingsDirectory: URL {
        VoiceInkMacOSStorageDirectories.recordingsDirectory
    }

    private init() {}

    func startMonitoring(modelContext: ModelContext) {
        self.modelContext = modelContext

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTranscriptionCompleted(_:)),
            name: .transcriptionCompleted,
            object: nil
        )

        if VoiceInkTranscriptionAutoCleanupPreference.isEnabled() {
            Task { [weak self] in
                guard let self = self, let modelContext = self.modelContext else { return }
                await self.sweepOldTranscriptions(modelContext: modelContext)
                await self.cleanupOrphanAudioFiles(modelContext: modelContext)
            }
        }
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self, name: .transcriptionCompleted, object: nil)
    }

    func runManualCleanup(modelContext: ModelContext) async {
        await sweepOldTranscriptions(modelContext: modelContext)
    }

    @objc private func handleTranscriptionCompleted(_ notification: Notification) {
        let cleanupConfiguration = VoiceInkTranscriptionAutoCleanupPreference.current()

        cleanupConfiguration.applyCompletionRuntimeState(
            ignore: {},
            sweepOldTranscriptions: {
                if let modelContext = self.modelContext {
                    Task { [weak self] in
                        guard let self = self else { return }
                        await self.sweepOldTranscriptions(modelContext: modelContext)
                    }
                }
            },
            deleteCompletedTranscription: {
                self.deleteCompletedTranscription(from: notification)
            }
        )
    }

    private func deleteCompletedTranscription(from notification: Notification) {
        guard let transcription = notification.object as? Transcription,
              let modelContext = self.modelContext else {
            logger.error("\(VoiceInkTranscriptionAutoCleanupDiagnostics.invalidCompletedTranscriptionMessage, privacy: .public)")
            return
        }

        transcription.deleteExistingAudioFileReportingFailure(relativeTo: recordingsDirectory) { message in
            logger.error("\(message, privacy: .public)")
        }

        modelContext.delete(transcription)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
        } catch {
            let message = VoiceInkTranscriptionAutoCleanupDiagnostics.saveAfterCompletedDeletionFailedMessage(
                errorDescription: error.localizedDescription
            )
            logger.error("\(message, privacy: .public)")
        }
    }

    private func sweepOldTranscriptions(modelContext: ModelContext) async {
        let cleanupConfiguration = VoiceInkTranscriptionAutoCleanupPreference.current()
        guard cleanupConfiguration.isEnabled else {
            return
        }

        let cutoffDate = cleanupConfiguration.cutoffDate()

        let modelContainer = await MainActor.run { modelContext.container }

        do {
            let backgroundContext = ModelContext(modelContainer)

            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { transcription in
                    transcription.timestamp < cutoffDate
                }
            )
            let items = try backgroundContext.fetch(descriptor)
            var deletedCount = 0
            for transcription in items {
                try? transcription.deleteExistingAudioFile(relativeTo: recordingsDirectory)
                backgroundContext.delete(transcription)
                deletedCount += 1
            }
            if deletedCount > 0 {
                try backgroundContext.save()
                let message = VoiceInkTranscriptionAutoCleanupDiagnostics.oldTranscriptionsCleanedMessage(
                    deletedCount: deletedCount
                )
                logger.notice("\(message, privacy: .public)")
                await MainActor.run {
                    NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
                }
            }
        } catch {
            let message = VoiceInkTranscriptionAutoCleanupDiagnostics.transcriptionCleanupFailedMessage(
                errorDescription: error.localizedDescription
            )
            logger.error("\(message, privacy: .public)")
        }
    }

    /// Deletes audio files in Recordings directory that have no corresponding Transcription record
    private func cleanupOrphanAudioFiles(modelContext: ModelContext) async {
        guard VoiceInkTranscriptionAutoCleanupPreference.isEnabled() else {
            return
        }

        let modelContainer = await MainActor.run { modelContext.container }

        do {
            let backgroundContext = ModelContext(modelContainer)

            var descriptor = FetchDescriptor<Transcription>()
            descriptor.propertiesToFetch = [\.audioFileURL]

            let transcriptions = try backgroundContext.fetch(descriptor)
            let referencedFiles = Set(transcriptions.compactMap { transcription -> String? in
                transcription.resolvedAudioFileURL(relativeTo: recordingsDirectory)?.lastPathComponent
            })

            guard FileManager.default.fileExists(atPath: recordingsDirectory.path) else { return }
            let filesInDirectory = try FileManager.default.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: nil
            )

            var deletedCount = 0
            for fileURL in filesInDirectory {
                let fileName = fileURL.lastPathComponent
                if !referencedFiles.contains(fileName) {
                    try? FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                let message = VoiceInkTranscriptionAutoCleanupDiagnostics.orphanAudioFilesCleanedMessage(
                    deletedCount: deletedCount
                )
                logger.notice("\(message, privacy: .public)")
            }
        } catch {
            let message = VoiceInkTranscriptionAutoCleanupDiagnostics.orphanAudioCleanupFailedMessage(
                errorDescription: error.localizedDescription
            )
            logger.error("\(message, privacy: .public)")
        }
    }
}
