import Foundation
import SwiftData
import VoiceInkCore

@Model
final class Transcription: VoiceInkStoredAudioRecord, VoiceInkSessionMetricSource, VoiceInkPerformanceRecord, VoiceInkMutableTranscriptionEnhancementMetadataRecord {
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
    var recognitionText: String?
    var dictationProfileRawValue: String?
    var clarityStyleRawValue: String?
    var processingFailureReason: String?

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
         transcriptionStatus: VoiceInkTranscriptionStatus = .pending,
         recognitionText: String? = nil,
         dictationProfile: VoiceInkDictationProfile? = nil,
         clarityStyle: VoiceInkClarityStyle? = nil,
         processingFailureReason: String? = nil) {
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
        self.recognitionText = recognitionText
        self.dictationProfileRawValue = dictationProfile?.rawValue
        self.clarityStyleRawValue = clarityStyle?.rawValue
        self.processingFailureReason = processingFailureReason
    }

    convenience init(completedDraft draft: VoiceInkCompletedTranscriptionDraft) {
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
            transcriptionStatus: draft.transcriptionStatus,
            recognitionText: draft.recognitionText,
            dictationProfile: draft.dictationProfile,
            clarityStyle: draft.clarityStyle,
            processingFailureReason: draft.processingFailureReason
        )
    }

    func applyCompletedDraft(_ draft: VoiceInkCompletedTranscriptionDraft) {
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
        recognitionText = draft.recognitionText
        dictationProfileRawValue = draft.dictationProfile?.rawValue
        clarityStyleRawValue = draft.clarityStyle?.rawValue
        processingFailureReason = draft.processingFailureReason
    }

    convenience init(recordingDraft draft: VoiceInkRecordingTranscriptionDraft) {
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
        let plan = VoiceInkTranscriptionRecordCancellationPlan(
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
        recognitionText = nil
        dictationProfileRawValue = nil
        clarityStyleRawValue = nil
        processingFailureReason = nil
    }

    func markAsFailedTranscription(reason: String) {
        let plan = VoiceInkTranscriptionRecordFailurePlan(errorDescription: reason)
        text = plan.failedTranscriptText
        transcriptionState = plan.status
    }

    var transcriptionState: VoiceInkTranscriptionStatus? {
        get {
            guard let transcriptionStatus else { return nil }
            return VoiceInkTranscriptionStatus(rawValue: transcriptionStatus)
        }
        set {
            transcriptionStatus = newValue?.rawValue
        }
    }

    var dictationProfile: VoiceInkDictationProfile? {
        dictationProfileRawValue.flatMap(VoiceInkDictationProfile.init(rawValue:))
    }

    var clarityStyle: VoiceInkClarityStyle? {
        clarityStyleRawValue.flatMap(VoiceInkClarityStyle.init(rawValue:))
    }

}
