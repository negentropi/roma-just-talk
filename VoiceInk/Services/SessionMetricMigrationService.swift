import Foundation
import SwiftData
import OSLog
import VoiceInkCore

@MainActor
final class SessionMetricMigrationService {
    static let shared = SessionMetricMigrationService()

    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.sessionMetricMigrationService
    )
    private(set) var isRunning = false

    private init() {}

    @discardableResult
    func runIfNeeded(
        transcriptionContainer: ModelContainer,
        metricWriter: Task<SessionMetricRecorder, Never>
    ) -> Task<Void, Never>? {
        guard !VoiceInkSessionMetricMigrationPreference.isCompleted(), !isRunning else { return nil }
        isRunning = true

        let logger = self.logger

        return Task.detached(priority: .utility) {
            let backgroundContext = ModelContext(transcriptionContainer)
            var insertedCount = 0

            do {
                try Task.checkCancellation()
                let completedStatus = VoiceInkSessionMetricPolicy.completedTranscriptionStatusRawValue
                let descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { $0.transcriptionStatus == completedStatus }
                )
                let drafts = try backgroundContext.fetch(descriptor).map { transcription in
                    VoiceInkSessionMetricPolicy.recorderDraft(
                        transcriptionId: transcription.id,
                        timestamp: transcription.timestamp,
                        source: transcription,
                        transcriptionModelName: transcription.transcriptionModelName,
                        powerModeName: transcription.powerModeName,
                        aiEnhancementModelName: transcription.aiEnhancementModelName
                    )
                }
                let writer = await metricWriter.value
                let batchSize = 100
                for start in stride(from: 0, to: drafts.count, by: batchSize) {
                    try Task.checkCancellation()
                    let end = min(start + batchSize, drafts.count)
                    insertedCount += try await writer.record(Array(drafts[start..<end]))
                }
                try Task.checkCancellation()
                VoiceInkSessionMetricMigrationPreference.markCompleted()
                let message = VoiceInkSessionMetricMigrationDiagnostics.completedMessage(insertedCount: insertedCount)
                logger.notice("\(message, privacy: .public)")
            } catch {
                let message = VoiceInkSessionMetricMigrationDiagnostics.failedMessage(
                    localizedDescription: error.localizedDescription
                )
                logger.error("\(message, privacy: .public)")
            }

            await MainActor.run {
                SessionMetricMigrationService.shared.isRunning = false
                NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
            }
        }
    }
}
