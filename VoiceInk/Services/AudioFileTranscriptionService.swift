import Foundation
import AVFoundation
import SwiftData
import os
import VoiceInkCore

@MainActor
class AudioTranscriptionService {
    private let modelContext: ModelContext
    private let enhancementService: AIEnhancementService?
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "AudioTranscriptionService")
    private let serviceRegistry: TranscriptionServiceRegistry

    init(modelContext: ModelContext, engine: VoiceInkEngine) {
        self.modelContext = modelContext
        self.enhancementService = engine.enhancementService
        self.serviceRegistry = TranscriptionServiceRegistry(modelProvider: engine.whisperModelManager, modelsDirectory: engine.whisperModelManager.modelsDirectory, modelContext: modelContext)
    }

    init(modelContext: ModelContext, serviceRegistry: TranscriptionServiceRegistry, enhancementService: AIEnhancementService?) {
        self.modelContext = modelContext
        self.enhancementService = enhancementService
        self.serviceRegistry = serviceRegistry
    }
    
    func retranscribeAudio(from url: URL, using model: any TranscriptionModel) async throws -> Transcription {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoiceInkEngineError.audioFileNotFound
        }
        
        do {
            let transcriptionStart = Date()
            let rawText = try await serviceRegistry.transcribe(audioURL: url, model: model)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            let cleanupConfiguration = VoiceInkTranscriptionCleanupConfiguration.current()

            let powerModeMetadata = VoiceInkPowerModeTranscriptionMetadata.active(
                from: PowerModeManager.shared.activeConfiguration
            )

            let textPlan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
                rawText,
                cleanupConfiguration: cleanupConfiguration
            ) { text in
                WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            }
            let text = textPlan.textForEnhancement
            logger.notice("✅ Word replacements applied")
            let cleanedText = textPlan.cleanedText

            let audioAsset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))
            let appSupportDirectory = VoiceInkAppIdentity.macOSApplicationSupportDirectory(
                in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            )
            let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: appSupportDirectory)
            
            let permanentURL = VoiceInkStoredAudioFile.retranscriptionFileURL(in: recordingsDirectory)
            
            do {
                try FileManager.default.copyItem(at: url, to: permanentURL)
            } catch {
                logger.error("❌ Failed to create permanent copy of audio: \(error.localizedDescription, privacy: .public)")
                throw error
            }
            
            let permanentURLString = permanentURL.absoluteString

            // Apply prompt detection for trigger words
            let originalText = cleanedText
            let draftContext = VoiceInkAudioFileTranscriptionDraftContext(
                cleanedText: originalText,
                duration: duration,
                audioFileURL: permanentURLString,
                transcriptionModelName: model.displayName,
                transcriptionDuration: transcriptionDuration,
                powerModeName: powerModeMetadata.name,
                powerModeEmoji: powerModeMetadata.emoji
            )
            var promptDetectionResult: VoiceInkPromptDetectionResult? = nil

            if let enhancementService = enhancementService,
               enhancementService.isConfigured,
               enhancementService.hasPromptTriggerWords {
                let detectionResult = enhancementService.analyzePromptTrigger(in: text)
                promptDetectionResult = detectionResult
                enhancementService.applyPromptDetectionResult(detectionResult)
            }

            defer {
                if let result = promptDetectionResult,
                   result.shouldEnableAI {
                    enhancementService?.restorePromptDetectionSettings(result)
                }
            }

            let enhancementRequest = textPlan.enhancementRequest(
                isEnhancementEnabled: enhancementService?.isEnhancementEnabled == true,
                isEnhancementConfigured: enhancementService?.isConfigured == true,
                promptDetectionResult: promptDetectionResult,
                skipConfiguration: VoiceInkPostProcessingSkipConfiguration.current()
            )

            // Apply AI enhancement if enabled
            if let enhancementService = enhancementService,
               let enhancementRequest {
                do {
                    let enhancement = try await enhancementService.enhance(enhancementRequest.text)
                    let newTranscription = Transcription(completedDraft: VoiceInkAudioFileTranscriptionDraft.completed(
                        context: draftContext,
                        enhancementOutcome: .succeeded(enhancement)
                    ))
                    saveCompletedTranscription(newTranscription)
                    return newTranscription
                } catch {
                    let newTranscription = Transcription(completedDraft: VoiceInkAudioFileTranscriptionDraft.completed(
                        context: draftContext,
                        enhancementOutcome: .failed(
                            reason: VoiceInkErrorDescription.text(for: error),
                            policy: .omitEnhancedText
                        )
                    ))
                    saveCompletedTranscription(newTranscription)
                    return newTranscription
                }
            } else {
                let newTranscription = Transcription(completedDraft: VoiceInkAudioFileTranscriptionDraft.completed(
                    context: draftContext
                ))
                saveCompletedTranscription(newTranscription)
                return newTranscription
            }
        } catch {
            logger.error("❌ Transcription failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func saveCompletedTranscription(_ transcription: Transcription) {
        modelContext.insert(transcription)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
        } catch {
            logger.error("❌ Failed to save transcription: \(error.localizedDescription, privacy: .public)")
        }
    }
}
