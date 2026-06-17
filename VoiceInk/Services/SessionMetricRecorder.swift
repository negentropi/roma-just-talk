import Foundation
import SwiftData
import OSLog
import VoiceInkCore

enum SessionMetricRecorder {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SessionMetricRecorder")
    private static let source = "recorder"

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

        let metricValues = VoiceInkSessionMetricPolicy.values(for: transcription)

        let metric = SessionMetric(
            transcriptionId: transcription.id,
            timestamp: timestamp,
            source: source,
            wordCount: metricValues.wordCount,
            audioDuration: metricValues.audioDuration,
            transcriptionModelName: transcription.transcriptionModelName ?? modelDisplayName,
            transcriptionDuration: metricValues.transcriptionDuration,
            speedFactor: metricValues.speedFactor,
            powerModeName: transcription.powerModeName,
            aiEnhancementModelName: transcription.aiEnhancementModelName,
            enhancementDuration: metricValues.enhancementDuration
        )

        modelContext.insert(metric)
        logger.notice("Recorded session metric for transcription \(transcriptionId.uuidString, privacy: .public)")
        return true
    }

}
