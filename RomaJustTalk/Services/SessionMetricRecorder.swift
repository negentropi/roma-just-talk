import Foundation
import SwiftData
import OSLog
import RomaCore

enum SessionMetricRecorder {
    private static let logger = Logger(
        subsystem: RomaAppIdentity.loggingSubsystem,
        category: RomaMacOSLogCategory.sessionMetricRecorder
    )

    @discardableResult
    static func recordRecorderSession(
        transcription: Transcription,
        model: (any TranscriptionModel)?,
        in modelContext: ModelContext,
        timestamp: Date = Date()
    ) throws -> Bool {
        try recordRecorderSession(
            transcription: transcription,
            modelDisplayName: model?.displayName,
            in: modelContext,
            timestamp: timestamp
        )
    }

    @discardableResult
    static func recordRecorderSession(
        transcription: Transcription,
        modelDisplayName: String?,
        in modelContext: ModelContext,
        timestamp: Date = Date()
    ) throws -> Bool {
        guard transcription.transcriptionState == .completed else {
            return false
        }

        let transcriptionId = transcription.id
        let descriptor = FetchDescriptor<SessionMetric>(
            predicate: #Predicate<SessionMetric> { metric in
                metric.transcriptionId == transcriptionId
            }
        )

        if try modelContext.fetchCount(descriptor) > 0 {
            return false
        }

        let draft = RomaSessionMetricPolicy.recorderDraft(
            transcriptionId: transcription.id,
            timestamp: timestamp,
            source: transcription,
            transcriptionModelName: transcription.transcriptionModelName ?? modelDisplayName,
            powerModeName: transcription.powerModeName,
            aiEnhancementModelName: transcription.aiEnhancementModelName
        )

        modelContext.insert(SessionMetric(draft: draft))
        let message = RomaSessionMetricRecorderDiagnostics.recordedSessionMetricMessage(
            transcriptionId: transcriptionId
        )
        logger.notice("\(message, privacy: .public)")
        return true
    }

}
