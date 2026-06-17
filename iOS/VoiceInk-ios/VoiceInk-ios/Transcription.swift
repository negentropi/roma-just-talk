import Foundation
import SwiftData
import VoiceInkCore

@Model
final class Transcription: VoiceInkMutableTranscriptionRecord, VoiceInkStoredAudioRecord, VoiceInkSessionMetricSource, VoiceInkPerformanceRecord {
    var id: UUID
    var text: String
    var enhancedText: String?
    var timestamp: Date
    var duration: TimeInterval
    var audioFileURL: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    var transcriptionStatus: VoiceInkTranscriptionStatus
    var transcriptionError: String?
    
    init(text: String, duration: TimeInterval, enhancedText: String? = nil, audioFileURL: String? = nil, transcriptionModelName: String? = nil, aiEnhancementModelName: String? = nil, transcriptionDuration: TimeInterval? = nil, enhancementDuration: TimeInterval? = nil, transcriptionStatus: VoiceInkTranscriptionStatus = .pending, transcriptionError: String? = nil) {
        self.id = UUID()
        self.text = text
        self.enhancedText = enhancedText
        self.timestamp = Date()
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
    }
    
    var storedAudioRecordingsDirectory: URL? {
        VoiceInkIOSStorageDirectories.recordingsDirectory
    }
}

extension Transcription {
    var performanceAudioDuration: TimeInterval { duration }
    var performanceTranscriptionModelName: String? { transcriptionModelName }
    var performanceTranscriptionDuration: TimeInterval? { transcriptionDuration }
    var performanceEnhancementModelName: String? { aiEnhancementModelName }
    var performanceEnhancementDuration: TimeInterval? { enhancementDuration }
    var performanceEnhancedText: String? { enhancedText }
}
