import Foundation
import SwiftData
import VoiceInkCore

@Model
final class Transcription {
    static let canceledTranscriptionText = "The transcription was canceled."

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
         transcriptionStatus: VoiceInkTranscriptionStatus = .pending) {
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

    func markAsCanceledTranscription(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        text = Self.canceledTranscriptionText
        enhancedText = nil
        transcriptionState = .canceled
        if let duration {
            self.duration = duration
        }
        if let modelName {
            transcriptionModelName = modelName
        }
        transcriptionDuration = nil
        enhancementDuration = nil
        aiEnhancementModelName = nil
        promptName = nil
        aiRequestSystemMessage = nil
        aiRequestUserMessage = nil
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

    func resolvedAudioFileURL(relativeTo recordingsDirectory: URL? = nil) -> URL? {
        VoiceInkStoredAudioFile.resolvedURL(for: audioFileURL, relativeTo: recordingsDirectory)
    }

    func existingAudioFileURL(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        VoiceInkStoredAudioFile.existingURL(
            for: audioFileURL,
            relativeTo: recordingsDirectory,
            fileManager: fileManager
        )
    }

    func hasStoredAudioFile(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        existingAudioFileURL(relativeTo: recordingsDirectory, fileManager: fileManager) != nil
    }
}
