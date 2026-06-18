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
        let modeConfiguration = await settings.effectiveModeConfiguration
        let cleanupConfiguration = await settings.transcriptionCleanupConfiguration
        let transcriptionLanguage = await settings.selectedTranscriptionLanguage
        let transcriptionPrompt = await settings.localWhisperPrompt
        let wordReplacementRules = await settings.runtimeWordReplacementRules
        let customVocabulary = await settings.runtimeCustomVocabularyTerms

        return try await runProcessor.transcribe(
            fileURL: fileURL,
            configuration: modeConfiguration,
            cleanupConfiguration: cleanupConfiguration,
            applyingWordReplacements: { text in
                VoiceInkWordReplacementEngine.apply(wordReplacementRules, to: text)
            },
            postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration.current(),
            transcriptionLanguage: transcriptionLanguage,
            transcriptionPrompt: transcriptionPrompt,
            customVocabulary: customVocabulary,
            apiKeyProvider: { provider in
                await settings.apiKey(for: provider)
            },
            transcriptionServiceProvider: { provider in
                switch provider.transcriptionServiceKind {
                case .remote:
                    return VoiceInkRemoteTranscriptionService(provider: provider)
                case .localWhisper:
                    return WhisperTranscriptionService()
                }
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
