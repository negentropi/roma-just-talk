import Foundation
import SwiftData
import VoiceInkCore

@Model
final class Transcription: VoiceInkMutableTranscriptionRecord {
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
    
    var resolvedAudioFileURL: URL? {
        VoiceInkStoredAudioFile.resolvedURL(for: audioFileURL, relativeTo: Self.recordingsDirectory)
    }

    func existingAudioFileURL(fileManager: FileManager = .default) -> URL? {
        VoiceInkStoredAudioFile.existingURL(
            for: audioFileURL,
            relativeTo: Self.recordingsDirectory,
            fileManager: fileManager
        )
    }

    func hasStoredAudioFile(fileManager: FileManager = .default) -> Bool {
        existingAudioFileURL(fileManager: fileManager) != nil
    }

    @discardableResult
    func deleteExistingAudioFile(fileManager: FileManager = .default) throws -> URL? {
        try VoiceInkStoredAudioFile.deleteExistingFile(
            for: audioFileURL,
            relativeTo: Self.recordingsDirectory,
            fileManager: fileManager
        )
    }

    private static var recordingsDirectory: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return VoiceInkStoredAudioFile.recordingsDirectory(in: documentsDirectory)
    }
}
