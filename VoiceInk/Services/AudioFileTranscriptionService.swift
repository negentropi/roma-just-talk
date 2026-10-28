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
        let plan = DictationPostprocessingPlan.capture(
            profile: .current(), using: modelContext, enhancementService: enhancementService
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoiceInkEngineError.audioFileNotFound
        }
        var ownedCopy: URL?
        var committed = false
        defer {
            if !committed, let ownedCopy { try? FileManager.default.removeItem(at: ownedCopy) }
        }
        do {
            try Task.checkCancellation()
            let transcriptionStart = Date()
            let rawText = try await serviceRegistry.transcribe(audioURL: url, model: model)
            try Task.checkCancellation()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            let powerModeMetadata = VoiceInkPowerModeTranscriptionMetadata.active(
                from: PowerModeManager.shared.activeConfiguration
            )
            let preparation = AudioFileDictationPostprocessing.prepare(
                recognitionText: rawText, plan: plan, modelContext: modelContext
            )

            let audioAsset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))
            try Task.checkCancellation()
            let appSupportDirectory = VoiceInkMacOSStorageDirectories.appSupportDirectory
            let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: appSupportDirectory)
            
            let permanentURL = VoiceInkStoredAudioFile.retranscriptionFileURL(in: recordingsDirectory)
            
            do {
                guard !FileManager.default.fileExists(atPath: permanentURL.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                ownedCopy = permanentURL
                try FileManager.default.copyItem(at: url, to: permanentURL)
            } catch {
                if (error as? CocoaError)?.code == .fileWriteFileExists { ownedCopy = nil }
                let message = VoiceInkAudioFileTranscriptionDiagnostics.permanentCopyFailedMessage(
                    localizedDescription: error.localizedDescription
                )
                logger.error("\(message, privacy: .public)")
                throw error
            }
            
            let draft = try await AudioFileDictationPostprocessing.completedDraft(
                recognitionText: rawText,
                preparation: preparation,
                duration: duration,
                audioFileURL: permanentURL.absoluteString,
                transcriptionModelName: model.displayName,
                transcriptionDuration: transcriptionDuration,
                powerModeMetadata: powerModeMetadata,
                enhancementService: enhancementService,
                detectsPromptTriggers: true,
                enhancementFailurePolicy: .omitEnhancedText
            )
            try Task.checkCancellation()
            let savedID = try AudioFileTranscriptionPersistence.save(draft, in: modelContext.container)
            committed = true
            guard let newTranscription = modelContext.model(for: savedID) as? Transcription else {
                throw AudioFileTranscriptionPersistence.SavedTranscriptionUnavailable()
            }
            NotificationCenter.default.post(name: .transcriptionCreated, object: newTranscription)
            NotificationCenter.default.post(name: .transcriptionCompleted, object: newTranscription)
            return newTranscription
        } catch {
            let message = VoiceInkAudioFileTranscriptionDiagnostics.transcriptionFailedMessage(
                localizedDescription: error.localizedDescription
            )
            logger.error("\(message, privacy: .public)")
            throw error
        }
    }
}

@MainActor
enum AudioFileTranscriptionPersistence {
    struct SavedTranscriptionUnavailable: LocalizedError {
        var errorDescription: String? { "The transcription was saved, but History could not reopen it." }
    }

    static func save(_ draft: VoiceInkCompletedTranscriptionDraft, in container: ModelContainer) throws -> PersistentIdentifier {
        // A rejected save can leak a pending row into its context's first fetch. Keep that writer private.
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let transcription = Transcription(completedDraft: draft)
        writer.insert(transcription)
        do {
            try writer.save()
            return transcription.persistentModelID
        } catch {
            writer.rollback()
            throw error
        }
    }
}

/// File adapters share postprocessing while keeping Custom's trigger and failure policies explicit.
@MainActor
enum AudioFileDictationPostprocessing {
    enum Preparation {
        case custom(VoiceInkTranscriptionEnhancementTextPlan)
        case captured(DictationPostprocessingPlan)
    }

    static func prepare(
        recognitionText: String,
        plan: DictationPostprocessingPlan,
        modelContext: ModelContext
    ) -> Preparation {
        guard case .custom = plan else { return .captured(plan) }
        return .custom(VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
            recognitionText, cleanupConfiguration: .current(), cleanupProfile: .custom
        ) { DictionaryService.applyWordReplacements(to: $0, using: modelContext) })
    }

    static func completedDraft(
        recognitionText: String,
        preparation: Preparation,
        duration: TimeInterval,
        audioFileURL: String,
        transcriptionModelName: String,
        transcriptionDuration: TimeInterval,
        powerModeMetadata: VoiceInkPowerModeTranscriptionMetadata,
        enhancementService: AIEnhancementService?,
        detectsPromptTriggers: Bool,
        enhancementFailurePolicy: VoiceInkEnhancementFailureDraftPolicy,
        shouldCancel: () -> Bool = { false },
        willEnhance: () -> Void = {}
    ) async throws -> VoiceInkCompletedTranscriptionDraft {
        func checkCancellation() throws {
            if Task.isCancelled || shouldCancel() { throw CancellationError() }
        }
        try checkCancellation()
        let textPlan: VoiceInkTranscriptionEnhancementTextPlan
        switch preparation {
        case .custom(let prepared):
            textPlan = prepared
        case .captured(let plan):
            guard let output = try await plan.process(
                recognitionText: recognitionText, using: enhancementService,
                shouldCancel: shouldCancel, willRequestClarity: willEnhance
            ) else {
                preconditionFailure("Custom text is prepared synchronously by the file adapter.")
            }
            try checkCancellation()
            return VoiceInkCompletedTranscriptionDraft(
                cleanedText: output.preparedText, duration: duration, audioFileURL: audioFileURL,
                transcriptionModelName: transcriptionModelName, transcriptionDuration: transcriptionDuration,
                powerModeName: powerModeMetadata.name, powerModeEmoji: powerModeMetadata.emoji,
                enhancementResult: output.enhancementResult,
                recognitionText: recognitionText, dictationProfile: plan.profile,
                clarityStyle: plan.clarityStyle, processingFailureReason: output.fallbackReason
            )
        }

        var detection: VoiceInkPromptDetectionResult?
        if detectsPromptTriggers, let enhancementService,
           enhancementService.isConfigured, enhancementService.hasPromptTriggerWords {
            detection = enhancementService.analyzePromptTrigger(in: textPlan.textForEnhancement)
            if let detection { enhancementService.applyPromptDetectionResult(detection) }
        }
        defer {
            if let detection, detection.shouldEnableAI {
                enhancementService?.restorePromptDetectionSettings(detection)
            }
        }
        let request = textPlan.enhancementRequest(
            isEnhancementEnabled: enhancementService?.isEnhancementEnabled == true,
            isEnhancementConfigured: enhancementService?.isConfigured == true,
            promptDetectionResult: detection,
            skipConfiguration: .current()
        )
        let context = VoiceInkAudioFileTranscriptionDraftContext(
            cleanedText: textPlan.cleanedText, duration: duration, audioFileURL: audioFileURL,
            transcriptionModelName: transcriptionModelName, transcriptionDuration: transcriptionDuration,
            powerModeName: powerModeMetadata.name, powerModeEmoji: powerModeMetadata.emoji,
            recognitionText: recognitionText, dictationProfile: .custom
        )
        try checkCancellation()
        if request != nil { willEnhance() }
        let result = await VoiceInkAudioFileTranscriptionDraft.completionResult(
            context: context, enhancementRequest: request, enhancementFailurePolicy: enhancementFailurePolicy
        ) { request in
            guard let enhancementService else { throw VoiceInkEngineError.unknownError }
            return try await enhancementService.enhance(request.text)
        }
        try checkCancellation()
        return result.draft
    }
}
