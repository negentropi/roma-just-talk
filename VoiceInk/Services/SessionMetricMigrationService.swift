import Foundation
import SwiftData
import OSLog
import VoiceInkCore

@MainActor
final class SessionMetricMigrationService {
    static let shared = SessionMetricMigrationService()

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "SessionMetricMigrationService")
    private(set) var isRunning = false

    private init() {}

    @discardableResult
    func runIfNeeded(modelContainer: ModelContainer) -> Task<Void, Never>? {
        guard !VoiceInkSessionMetricMigrationPreference.isCompleted(), !isRunning else { return nil }
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

                let descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate<Transcription> { $0.transcriptionStatus == "completed" }
                )
                let transcriptions = try backgroundContext.fetch(descriptor)

                for transcription in transcriptions {
                    guard !existingIds.contains(transcription.id) else { continue }

                    let metricValues = VoiceInkSessionMetricPolicy.values(for: transcription)

                    let metric = SessionMetric(
                        transcriptionId: transcription.id,
                        timestamp: transcription.timestamp,
                        source: "recorder",
                        wordCount: metricValues.wordCount,
                        audioDuration: metricValues.audioDuration,
                        transcriptionModelName: transcription.transcriptionModelName,
                        transcriptionDuration: metricValues.transcriptionDuration,
                        speedFactor: metricValues.speedFactor,
                        powerModeName: transcription.powerModeName,
                        aiEnhancementModelName: transcription.aiEnhancementModelName,
                        enhancementDuration: metricValues.enhancementDuration
                    )
                    backgroundContext.insert(metric)
                    insertedCount += 1
                }

                if insertedCount > 0 {
                    try backgroundContext.save()
                }

                VoiceInkSessionMetricMigrationPreference.markCompleted()
                logger.notice("Completed stats migration with \(insertedCount, privacy: .public) session metric(s)")
            } catch {
                logger.error("Stats migration failed: \(error.localizedDescription, privacy: .public)")
            }

            await MainActor.run {
                SessionMetricMigrationService.shared.isRunning = false
                NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
            }
        }
    }
}
