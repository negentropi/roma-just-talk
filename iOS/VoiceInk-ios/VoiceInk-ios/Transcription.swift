import Foundation
import SwiftData
import VoiceInkCore

@Model
final class Transcription {
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
    
    var needsTranscription: Bool {
        return transcriptionStatus.needsTranscription
    }

    var resolvedAudioFileURL: URL? {
        VoiceInkStoredAudioFile.resolvedURL(for: audioFileURL, relativeTo: Self.recordingsDirectory)
    }
    
    /// Get the full path to the audio file
    var fullAudioPath: String? {
        resolvedAudioFileURL?.path
    }

    private static var recordingsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings")
    }
}
