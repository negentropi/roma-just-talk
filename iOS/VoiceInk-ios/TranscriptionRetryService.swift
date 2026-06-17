//
//  TranscriptionRetryService.swift
//  VoiceInk-ios
//
//  Created by AI Assistant on 12/08/2025.
//

import Foundation
import VoiceInkCore

class TranscriptionRetryService {
    private let runProcessor = VoiceInkTranscriptionRunProcessor()
    
    static let shared = TranscriptionRetryService()
    
    private init() {}

    func transcribe(fileURL: URL) async throws -> VoiceInkTranscriptionRunResult {
        let settings = AppSettings.shared
        let modeConfiguration = await settings.effectiveModeConfiguration
        let cleanupConfiguration = await settings.transcriptionCleanupConfiguration
        let transcriptionLanguage = await settings.selectedTranscriptionLanguage

        return try await runProcessor.transcribe(
            fileURL: fileURL,
            configuration: modeConfiguration,
            cleanupConfiguration: cleanupConfiguration,
            transcriptionLanguage: transcriptionLanguage,
            apiKeyProvider: { provider in
                await settings.apiKey(for: provider)
            },
            transcriptionServiceProvider: { provider in
                TranscriptionServiceFactory.service(for: provider)
            }
        )
    }

    /// Retries transcription for a given note using current app settings
    func retranscribe(note: Transcription) async throws -> String {
        guard let fileURL = note.existingAudioFileURL() else {
            throw VoiceInkEngineError.audioFileNotFound
        }

        let result = try await transcribe(fileURL: fileURL)
        
        // Update note
        note.text = result.cleanedText
        note.enhancedText = result.enhancedText
        note.transcriptionModelName = result.transcriptionModelName
        note.aiEnhancementModelName = result.aiEnhancementModelName
        note.transcriptionStatus = .completed
        note.transcriptionError = result.postProcessingError
        
        return result.finalText
    }
}
