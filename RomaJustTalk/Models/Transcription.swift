import Foundation
import SwiftData
import RomaCore

@Model
final class Transcription: RomaStoredAudioRecord, RomaSessionMetricSource, RomaPerformanceRecord, RomaMutableTranscriptionEnhancementMetadataRecord {
    var id: UUID
    var text: String
    var enhancedText: String?
    var timestamp: Date
    var duration: TimeInterval
    var audioFileURL: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?
    var powerModeName: String?
    var powerModeEmoji: String?
    var transcriptionStatus: String?

    init(text: String,
         duration: TimeInterval,
         enhancedText: String? = nil,
         audioFileURL: String? = nil,
         transcriptionModelName: String? = nil,
         aiEnhancementModelName: String? = nil,
         promptName: String? = nil,
         transcriptionDuration: TimeInterval? = nil,
         enhancementDuration: TimeInterval? = nil,
         aiRequestSystemMessage: String? = nil,
         aiRequestUserMessage: String? = nil,
         powerModeName: String? = nil,
         powerModeEmoji: String? = nil,
         transcriptionStatus: RomaTranscriptionStatus = .pending) {
        self.id = UUID()
        self.text = text
        self.enhancedText = enhancedText
        self.timestamp = Date()
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.promptName = promptName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.aiRequestSystemMessage = aiRequestSystemMessage
        self.aiRequestUserMessage = aiRequestUserMessage
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
        self.transcriptionStatus = transcriptionStatus.rawValue
    }

    convenience init(completedDraft draft: RomaCompletedTranscriptionDraft) {
        self.init(
            text: draft.text,
            duration: draft.duration,
            enhancedText: draft.enhancedText,
            audioFileURL: draft.audioFileURL,
            transcriptionModelName: draft.transcriptionModelName,
            aiEnhancementModelName: draft.aiEnhancementModelName,
            promptName: draft.promptName,
            transcriptionDuration: draft.transcriptionDuration,
            enhancementDuration: draft.enhancementDuration,
            aiRequestSystemMessage: draft.aiRequestSystemMessage,
            aiRequestUserMessage: draft.aiRequestUserMessage,
            powerModeName: draft.powerModeName,
            powerModeEmoji: draft.powerModeEmoji,
            transcriptionStatus: draft.transcriptionStatus
        )
    }

    func applyCompletedDraft(_ draft: RomaCompletedTranscriptionDraft) {
        text = draft.text
        duration = draft.duration
        enhancedText = draft.enhancedText
        audioFileURL = draft.audioFileURL
        transcriptionModelName = draft.transcriptionModelName
        aiEnhancementModelName = draft.aiEnhancementModelName
        promptName = draft.promptName
        transcriptionDuration = draft.transcriptionDuration
        enhancementDuration = draft.enhancementDuration
        aiRequestSystemMessage = draft.aiRequestSystemMessage
        aiRequestUserMessage = draft.aiRequestUserMessage
        powerModeName = draft.powerModeName
        powerModeEmoji = draft.powerModeEmoji
        transcriptionState = draft.transcriptionStatus
    }

    convenience init(recordingDraft draft: RomaRecordingTranscriptionDraft) {
        self.init(
            text: draft.text,
            duration: draft.duration,
            audioFileURL: draft.audioFileURL,
            transcriptionModelName: draft.transcriptionModelName,
            powerModeName: draft.powerModeName,
            powerModeEmoji: draft.powerModeEmoji,
            transcriptionStatus: draft.transcriptionStatus
        )
    }

    func markAsCanceledTranscription(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        let plan = RomaTranscriptionRecordCancellationPlan(
            duration: duration,
            modelName: modelName
        )
        text = plan.text
        enhancedText = plan.enhancedText
        transcriptionState = plan.status
        if let plannedDuration = plan.duration {
            self.duration = plannedDuration
        }
        if let plannedModelName = plan.transcriptionModelName {
            transcriptionModelName = plannedModelName
        }
        transcriptionDuration = plan.transcriptionDuration
        enhancementDuration = plan.enhancementDuration
        aiEnhancementModelName = plan.aiEnhancementModelName
        promptName = plan.promptName
        aiRequestSystemMessage = plan.aiRequestSystemMessage
        aiRequestUserMessage = plan.aiRequestUserMessage
    }

    func markAsFailedTranscription(reason: String) {
        let plan = RomaTranscriptionRecordFailurePlan(errorDescription: reason)
        text = plan.failedTranscriptText
        transcriptionState = plan.status
    }

    var transcriptionState: RomaTranscriptionStatus? {
        get {
            guard let transcriptionStatus else { return nil }
            return RomaTranscriptionStatus(rawValue: transcriptionStatus)
        }
        set {
            transcriptionStatus = newValue?.rawValue
        }
    }

}
