import Foundation
import AVFoundation
import SwiftData
import os
import VoiceInkCore

@MainActor
class AudioTranscriptionService {
    private let modelContext: ModelContext
    private let enhancementService: AIEnhancementService?
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.audioTranscriptionService
    )
    private let serviceRegistry: TranscriptionServiceRegistry

    init(modelContext: ModelContext, engine: VoiceInkEngine) {
        self.modelContext = modelContext
        self.enhancementService = engine.enhancementService
        self.serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: engine.whisperModelManager,
            modelsDirectory: engine.whisperModelManager.modelsDirectory,
            modelContext: modelContext,
            qwenRuntimeResult: engine.serviceRegistry.qwenRuntimeResult
        )
    }

    init(modelContext: ModelContext, serviceRegistry: TranscriptionServiceRegistry, enhancementService: AIEnhancementService?) {
        self.modelContext = modelContext
        self.enhancementService = enhancementService
        self.serviceRegistry = serviceRegistry
    }
    
    func retranscribeAudio(from url: URL, using model: any TranscriptionModel) async throws -> Transcription {
        let cleanupProfile = VoiceInkDictationProfile.current()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoiceInkEngineError.audioFileNotFound
        }
        
        do {
            try Task.checkCancellation()
            let transcriptionStart = Date()
            let rawText = try await serviceRegistry.transcribe(audioURL: url, model: model)
            try Task.checkCancellation()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            let cleanupConfiguration = VoiceInkTranscriptionCleanupConfiguration.current()

            let powerModeMetadata = VoiceInkPowerModeTranscriptionMetadata.active(
                from: PowerModeManager.shared.activeConfiguration
            )

            let textPlan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
                rawText,
                cleanupConfiguration: cleanupConfiguration,
                cleanupProfile: cleanupProfile
            ) { text in
                DictionaryService.applyWordReplacements(to: text, using: modelContext)
            }
            let text = textPlan.textForEnhancement
            if textPlan.allowsEnhancement {
                logger.notice("\(VoiceInkAudioFileTranscriptionDiagnostics.wordReplacementsAppliedMessage, privacy: .public)")
            }
            let cleanedText = textPlan.cleanedText

            let audioAsset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))
            try Task.checkCancellation()
            let appSupportDirectory = VoiceInkMacOSStorageDirectories.appSupportDirectory
            let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: appSupportDirectory)
            
            let permanentURL = VoiceInkStoredAudioFile.retranscriptionFileURL(in: recordingsDirectory)
            
            do {
                try FileManager.default.copyItem(at: url, to: permanentURL)
            } catch {
                let message = VoiceInkAudioFileTranscriptionDiagnostics.permanentCopyFailedMessage(
                    localizedDescription: error.localizedDescription
                )
                logger.error("\(message, privacy: .public)")
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

            if textPlan.allowsEnhancement,
               let enhancementService = enhancementService,
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

            let enhancementRequest: VoiceInkTranscriptionEnhancementRequest? = if textPlan.allowsEnhancement {
                textPlan.enhancementRequest(
                    isEnhancementEnabled: enhancementService?.isEnhancementEnabled == true,
                    isEnhancementConfigured: enhancementService?.isConfigured == true,
                    promptDetectionResult: promptDetectionResult,
                    skipConfiguration: VoiceInkPostProcessingSkipConfiguration.current()
                )
            } else {
                nil
            }

            let completionResult: VoiceInkAudioFileTranscriptionCompletionResult
            if textPlan.allowsEnhancement {
                completionResult = await VoiceInkAudioFileTranscriptionDraft.completionResult(
                    context: draftContext,
                    enhancementRequest: enhancementRequest,
                    enhancementFailurePolicy: .omitEnhancedText
                ) { [enhancementService] request in
                    guard let enhancementService else {
                        throw VoiceInkEngineError.unknownError
                    }
                    return try await enhancementService.enhance(request.text)
                }
            } else {
                completionResult = VoiceInkAudioFileTranscriptionCompletionResult(
                    draft: VoiceInkAudioFileTranscriptionDraft.completed(context: draftContext)
                )
            }

            try Task.checkCancellation()
            let newTranscription = Transcription(completedDraft: completionResult.draft)
            saveCompletedTranscription(newTranscription)
            return newTranscription
        } catch {
            let message = VoiceInkAudioFileTranscriptionDiagnostics.transcriptionFailedMessage(
                localizedDescription: error.localizedDescription
            )
            logger.error("\(message, privacy: .public)")
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
            let message = VoiceInkAudioFileTranscriptionDiagnostics.saveFailedMessage(
                localizedDescription: error.localizedDescription
            )
            logger.error("\(message, privacy: .public)")
        }
    }
}
