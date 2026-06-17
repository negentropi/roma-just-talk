//
//  WhisperTranscriptionService.swift
//  VoiceInk-ios
//
//  Local transcription service using Whisper.cpp
//

import Foundation
import VoiceInkCore

struct WhisperTranscriptionService: VoiceInkAudioTranscriptionService {
    
    /// Transcribe audio file using local Whisper model
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil
    ) async throws -> String {
        
        print("WhisperTranscriptionService: Starting local transcription")
        
        // Get available model
        let modelManager = LocalModelManager.shared
        guard let modelPath = await modelManager.baseModelPath else {
            throw VoiceInkEngineError.localModelUnavailable
        }
        
        print("WhisperTranscriptionService: Using model at \(modelPath)")
        
        // Load Whisper context
        let context: WhisperContext
        do {
            context = try await WhisperContext.createContext(path: modelPath)
        } catch {
            print("WhisperTranscriptionService: Failed to load model: \(error)")
            throw VoiceInkEngineError.localModelLoadFailed
        }
        
        // Process audio file (expecting WAV format from recorder)
        let audioSamples: [Float]
        do {
            let data = try Data(contentsOf: fileURL)
            guard let samples = VoiceInkPCM16Audio.floatSamples(fromWAVData: data) else {
                throw NSError(domain: "WhisperTranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file - too small"])
            }
            audioSamples = samples
            print("WhisperTranscriptionService: Processed \(audioSamples.count) audio samples")
        } catch {
            print("WhisperTranscriptionService: Audio processing failed: \(error)")
            // Clean up resources before throwing
            await context.releaseResources()
            print("WhisperTranscriptionService: Whisper context resources released.")
            throw VoiceInkEngineError.audioProcessingFailed
        }
        
        // Perform transcription
        let success = await context.fullTranscribe(
            samples: audioSamples,
            language: VoiceInkTranscriptionLanguageSupport.requestLanguage(language),
            prompt: VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage()
        )
        
        if success {
            let transcription = await context.getTranscription()
            // Clean up resources
            await context.releaseResources()
            print("WhisperTranscriptionService: Whisper context resources released.")
            print("WhisperTranscriptionService: Transcription completed successfully")
            return transcription.isEmpty ? "No audio detected." : transcription
        } else {
            // Clean up resources before throwing error
            await context.releaseResources()
            print("WhisperTranscriptionService: Whisper context resources released.")
            print("WhisperTranscriptionService: Transcription failed")
            throw VoiceInkEngineError.whisperTranscriptionFailed
        }
    }
    
}
