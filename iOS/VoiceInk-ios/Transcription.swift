import Foundation
import SwiftData
import VoiceInkCore

@Model
final class Transcription: VoiceInkMutableTranscriptionRecord, VoiceInkMutableTranscriptionEnhancementMetadataRecord, VoiceInkStoredAudioRecord, VoiceInkSessionMetricSource, VoiceInkPerformanceRecord, VoiceInkDashboardMetricRecord {
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
    var transcriptionStatus: VoiceInkTranscriptionStatus
    var transcriptionError: String?

    init(text: String, duration: TimeInterval, enhancedText: String? = nil, audioFileURL: String? = nil, transcriptionModelName: String? = nil, aiEnhancementModelName: String? = nil, promptName: String? = nil, transcriptionDuration: TimeInterval? = nil, enhancementDuration: TimeInterval? = nil, aiRequestSystemMessage: String? = nil, aiRequestUserMessage: String? = nil, transcriptionStatus: VoiceInkTranscriptionStatus = .pending, transcriptionError: String? = nil) {
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
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
    }

    convenience init(recordingDraft draft: VoiceInkRecordingTranscriptionDraft) {
        self.init(
            text: draft.text,
            duration: draft.duration,
            audioFileURL: draft.audioFileURL,
            transcriptionModelName: draft.transcriptionModelName,
            transcriptionStatus: draft.transcriptionStatus
        )
    }

    var storedAudioRecordingsDirectory: URL? {
        VoiceInkIOSStorageDirectories.recordingsDirectory
    }
}
