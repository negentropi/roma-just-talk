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
    private let transcriptionServiceFactory = VoiceInkAudioTranscriptionServiceFactory {
        WhisperTranscriptionService()
    }

    static let shared = TranscriptionRetryService()

    private init() {}

    func transcribe(fileURL: URL) async throws -> VoiceInkTranscriptionRunResult {
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
