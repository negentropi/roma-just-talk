//
//  TranscriptionRetryService.swift
//  VoiceInk-ios
//
//  Created by AI Assistant on 12/08/2025.
//

import Foundation
import VoiceInkCore

class TranscriptionRetryService {
    typealias TranscribeFile = (URL) async throws -> VoiceInkTranscriptionRunResult

    private let runProcessor = VoiceInkTranscriptionRunProcessor()
    private let transcriptionServiceFactory = VoiceInkAudioTranscriptionServiceFactory {
        WhisperTranscriptionService()
    }
    private let transcribeFileOverride: TranscribeFile?
    
    static let shared = TranscriptionRetryService()
    
    init(transcribeFileOverride: TranscribeFile? = nil) {
        self.transcribeFileOverride = transcribeFileOverride
    }

    func transcribe(fileURL: URL) async throws -> VoiceInkTranscriptionRunResult {
        if let transcribeFileOverride {
            return try await transcribeFileOverride(fileURL)
        }

        let settings = AppSettings.shared
        let runSettings = await settings.transcriptionRunSettings

        return try await runSettings.transcribe(
            fileURL: fileURL,
            processor: runProcessor,
            apiKeyProvider: { provider in
                await settings.apiKey(for: provider)
            },
            transcriptionServiceProvider: { provider in
                transcriptionServiceFactory.service(for: provider)
            }
        )
    }

    /// Retries transcription for a given note using current app settings
    func retranscribe(note: Transcription) async throws -> String {
        try await note.retranscribeStoredAudio { fileURL in
            try await transcribe(fileURL: fileURL)
        }
    }
}
