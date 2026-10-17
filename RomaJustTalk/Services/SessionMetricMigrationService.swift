import Foundation
import SwiftData
import OSLog
import RomaCore

@MainActor
final class SessionMetricMigrationService {
    static let shared = SessionMetricMigrationService()

    private let logger = Logger(
        subsystem: RomaAppIdentity.loggingSubsystem,
        category: RomaMacOSLogCategory.sessionMetricMigrationService
    )
    private(set) var isRunning = false

    private init() {}

    @discardableResult
    func runIfNeeded(modelContainer: ModelContainer) -> Task<Void, Never>? {
        guard !RomaSessionMetricMigrationPreference.isCompleted(), !isRunning else { return nil }
        isRunning = true

        let logger = self.logger

        return Task.detached(priority: .utility) {
            let backgroundContext = ModelContext(modelContainer)
            var insertedCount = 0

            do {
                // Build a Set of already-migrated IDs in one query instead of
                // checking per-record — turns N queries into 1.
                let existingIds = Set(
                    try backgroundContext.fetch(FetchDescriptor<SessionMetric>())
                        .map { $0.transcriptionId }
                )

                let completedStatus = RomaSessionMetricPolicy.completedTranscriptionStatusRawValue
                let descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { $0.transcriptionStatus == completedStatus }
                )
                let transcriptions = try backgroundContext.fetch(descriptor)

                for transcription in transcriptions {
                    guard !existingIds.contains(transcription.id) else { continue }

                    let draft = RomaSessionMetricPolicy.recorderDraft(
                        transcriptionId: transcription.id,
                        timestamp: transcription.timestamp,
                        source: transcription,
                        transcriptionModelName: transcription.transcriptionModelName,
                        powerModeName: transcription.powerModeName,
                        aiEnhancementModelName: transcription.aiEnhancementModelName
                    )
                    backgroundContext.insert(SessionMetric(draft: draft))
                    insertedCount += 1
                }

                if insertedCount > 0 {
                    try backgroundContext.save()
                }

                RomaSessionMetricMigrationPreference.markCompleted()
                let message = RomaSessionMetricMigrationDiagnostics.completedMessage(insertedCount: insertedCount)
                logger.notice("\(message, privacy: .public)")
            } catch {
                let message = RomaSessionMetricMigrationDiagnostics.failedMessage(
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
