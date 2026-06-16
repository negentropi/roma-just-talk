//
//  TranscriptionRetryService.swift
//  VoiceInk-ios
//
//  Created by AI Assistant on 12/08/2025.
//

import Foundation
import VoiceInkCore

struct TranscriptionRunResult {
    let cleanedText: String
    let finalText: String
    let transcriptionModelName: String
    let aiEnhancementModelName: String?
    let postProcessingError: String?
    let postProcessingSucceeded: Bool
}

class TranscriptionRetryService {
    private let postProcessor = VoiceInkPostProcessingClient()
    
    static let shared = TranscriptionRetryService()
    
    private init() {}

    func transcribe(fileURL: URL) async throws -> TranscriptionRunResult {
        let settings = AppSettings.shared
        let modeConfiguration = await settings.effectiveModeConfiguration
        let provider = modeConfiguration.transcriptionProvider
        let apiKey = await settings.apiKey(for: provider)
        let model = modeConfiguration.transcriptionModel

        guard !apiKey.isEmpty else {
            throw TranscriptionError.noApiKey
        }

        let transcriptionService = TranscriptionServiceFactory.service(for: provider)
        let rawText = try await transcriptionService.transcribeAudioFile(
            apiKey: apiKey,
            model: model,
            fileURL: fileURL,
            language: nil
        )

        let cleanedText = VoiceInkTranscriptTextNormalizer.normalizeParagraphSpacing(rawText)
        let aiEnhancementModelName = modeConfiguration.isPostProcessingEnabled ? modeConfiguration.postProcessingModel : nil

        var finalText = cleanedText
        var postProcessingError: String? = nil
        var postProcessingSucceeded = false

        if modeConfiguration.isPostProcessingEnabled {
            let ppPrompt = modeConfiguration.prompt
            if !ppPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let llmProvider = modeConfiguration.postProcessingProvider
                let llmKey = await settings.apiKey(for: llmProvider)
                let llmModel = modeConfiguration.postProcessingModel
                if !llmKey.isEmpty {
                    do {
                        finalText = try await postProcessor.postProcessTranscript(
                            provider: llmProvider,
                            apiKey: llmKey,
                            model: llmModel,
                            prompt: ppPrompt,
                            transcript: cleanedText
                        )
                        postProcessingSucceeded = true
                    } catch {
                        postProcessingError = "Post-processing failed: \(error.localizedDescription)"
                        finalText = cleanedText
                    }
                }
            }
        }

        return TranscriptionRunResult(
            cleanedText: cleanedText,
            finalText: finalText,
            transcriptionModelName: model,
            aiEnhancementModelName: aiEnhancementModelName,
            postProcessingError: postProcessingError,
            postProcessingSucceeded: postProcessingSucceeded
        )
    }

    /// Retries transcription for a given note using current app settings
    func retranscribe(note: Transcription) async throws -> String {
        guard let fileURL = note.resolvedAudioFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        let result = try await transcribe(fileURL: fileURL)
        
        // Update note
        note.text = result.cleanedText
        note.enhancedText = (result.finalText == result.cleanedText) ? nil : result.finalText
        note.transcriptionModelName = result.transcriptionModelName
        note.aiEnhancementModelName = result.aiEnhancementModelName
        note.transcriptionStatus = .completed
        note.transcriptionError = result.postProcessingError
        
        return result.finalText
    }
}

enum TranscriptionError: LocalizedError {
    case audioFileNotFound
    case noApiKey
    
    var errorDescription: String? {
        switch self {
        case .audioFileNotFound:
            return "Audio file not found"
        case .noApiKey:
            return "No API key configured"
        }
    }
}
