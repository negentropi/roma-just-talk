import Foundation
import SwiftData
import VoiceInkCore

@Model
final class SessionMetric: VoiceInkPerformanceRecord, VoiceInkDashboardMetricRecord {
    var id: UUID = UUID()
    var transcriptionId: UUID = UUID()
    var timestamp: Date = Date()
    var source: String?
    var wordCount: Int = 0
    var audioDuration: TimeInterval = 0
    var transcriptionModelName: String?
    var transcriptionDuration: TimeInterval?
    var speedFactor: Double?
    var powerModeName: String?
    var aiEnhancementModelName: String?
    var enhancementDuration: TimeInterval?

    init(
        transcriptionId: UUID,
        timestamp: Date = Date(),
        source: String? = VoiceInkSessionMetricPolicy.recorderSource,
        wordCount: Int,
        audioDuration: TimeInterval,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        speedFactor: Double?,
        powerModeName: String?,
        aiEnhancementModelName: String?,
        enhancementDuration: TimeInterval?
    ) {
        self.id = UUID()
        self.transcriptionId = transcriptionId
        self.timestamp = timestamp
        self.source = source
        self.wordCount = wordCount
        self.audioDuration = audioDuration
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.speedFactor = speedFactor
        self.powerModeName = powerModeName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.enhancementDuration = enhancementDuration
    }

    convenience init(draft: VoiceInkSessionMetricDraft) {
        self.init(
            transcriptionId: draft.transcriptionId,
            timestamp: draft.timestamp,
            source: draft.source,
            wordCount: draft.wordCount,
            audioDuration: draft.audioDuration,
            transcriptionModelName: draft.transcriptionModelName,
            transcriptionDuration: draft.transcriptionDuration,
            speedFactor: draft.speedFactor,
            powerModeName: draft.powerModeName,
            aiEnhancementModelName: draft.aiEnhancementModelName,
            enhancementDuration: draft.enhancementDuration
        )
    }
}

extension SessionMetric {
    var performanceAudioDuration: TimeInterval { audioDuration }
    var performanceTranscriptionDuration: TimeInterval? { transcriptionDuration }
    var performanceEnhancementDuration: TimeInterval? { enhancementDuration }
    var performanceEnhancedText: String? { nil }
    var dashboardWordCount: Int { wordCount }
    var dashboardAudioDuration: TimeInterval { audioDuration }
}
