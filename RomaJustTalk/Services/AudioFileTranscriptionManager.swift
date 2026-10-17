import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import os
import RomaCore

@MainActor
class AudioTranscriptionManager: ObservableObject {
    static let shared = AudioTranscriptionManager()

    // MARK: - Published State

    @Published var queue: [AudioFileQueueItem] = []
    @Published var isProcessingQueue = false
    @Published var lastCompletedItemId: UUID?

    // MARK: - Private

    private var processingTask: Task<Void, Never>?
    private var processingGeneration: UInt64 = 0
    private let audioProcessor = AudioProcessor()
    private let logger = Logger(
        subsystem: RomaAppIdentity.loggingSubsystem,
        category: RomaMacOSLogCategory.audioTranscriptionManager
    )

    private init() {}

    // MARK: - Queue Management

    /// Add one or more audio file URLs to the queue. Invalid files are silently skipped.
    func addToQueue(urls: [URL]) {
        let candidates = urls.map {
            RomaAudioFileQueueCandidate(
                url: $0,
                fileExists: FileManager.default.fileExists(atPath: $0.path),
                isSupported: RomaSupportedMedia.isSupported(url: $0)
            )
        }

        for url in RomaAudioFileQueuePolicy.eligibleAdditionURLs(from: candidates, existingItems: queueFacts) {
            let item = AudioFileQueueItem(url: url)
            queue.append(item)
        }
    }

    /// Remove a pending item from the queue.
    func removeFromQueue(id: UUID) {
        guard RomaAudioFileQueuePolicy.canRemoveItem(id: id, from: queueFacts) else { return }
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue.remove(at: index)
    }

    /// Clear all items from the queue, cancelling any in-progress work.
    func clearAll() {
        cancelProcessing()
        queue.removeAll()
        lastCompletedItemId = nil
    }

    /// Retry a failed item by resetting it to pending and re-enqueuing.
    func retryItem(id: UUID) {
        guard let item = queue.first(where: { $0.id == id }),
              let retryStatus = RomaAudioFileQueuePolicy.statusAfterRetryRequest(item.status) else { return }

        item.status = retryStatus
    }

    /// Start processing pending items in the queue sequentially.
    func startProcessing(modelContext: ModelContext, engine: RomaEngine) {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        processingGeneration &+= 1
        let generation = processingGeneration

        processingTask = Task { [weak self] in
            guard let self else { return }

            while let item = self.nextPendingItem() {
                guard !Task.isCancelled else { break }
                await self.processItem(item, modelContext: modelContext, engine: engine)
            }

            if self.processingGeneration == generation {
                self.isProcessingQueue = false
            }
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessingQueue = false

        let statuses = RomaAudioFileQueuePolicy.statusesAfterCancelingProcessing(queue.map(\.status))
        for (item, status) in zip(queue, statuses) {
            item.status = status
        }
    }

    var hasPendingItems: Bool {
        RomaAudioFileQueuePolicy.hasPendingItems(in: queueFacts)
    }

    // MARK: - Private

    private var queueFacts: [RomaAudioFileQueueItemFacts<UUID>] {
        queue.map {
            RomaAudioFileQueueItemFacts(
                id: $0.id,
                standardizedPath: $0.url.standardizedFileURL.path,
                status: $0.status
            )
        }
    }

    private func nextPendingItem() -> AudioFileQueueItem? {
        guard let id = RomaAudioFileQueuePolicy.nextPendingItemID(in: queueFacts) else { return nil }
        return queue.first { $0.id == id }
    }

    private func processItem(_ item: AudioFileQueueItem, modelContext: ModelContext, engine: RomaEngine) async {
        let serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: engine.whisperModelManager,
            modelsDirectory: engine.whisperModelManager.modelsDirectory,
            modelContext: modelContext,
            qwenRuntimeResult: engine.serviceRegistry.qwenRuntimeResult
        )

        do {
            guard let currentModel = engine.transcriptionModelManager.currentTranscriptionModel else {
                throw RomaEngineError.noTranscriptionModelSelected
            }

            // Phase: Loading
            item.status = .processing(phase: .loading)
            try Task.checkCancellation()

            // Phase: Processing Audio
            item.status = .processing(phase: .processingAudio)

            let accessing = item.url.startAccessingSecurityScopedResource()
            defer { if accessing { item.url.stopAccessingSecurityScopedResource() } }

            let samples = try await audioProcessor.processAudioToSamples(item.url)
            try Task.checkCancellation()

            let audioAsset = AVURLAsset(url: item.url)
            let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))

            let appSupportDirectory = RomaMacOSStorageDirectories.appSupportDirectory
            let recordingsDirectory = try RomaStoredAudioFile.createRecordingsDirectory(in: appSupportDirectory)

            let permanentURL = RomaStoredAudioFile.importedTranscriptionFileURL(in: recordingsDirectory)

            try audioProcessor.saveSamplesAsWav(samples: samples, to: permanentURL)
            try Task.checkCancellation()

            // Phase: Transcribing
            item.status = .processing(phase: .transcribing)
            let transcriptionStart = Date()
            let rawText = try await serviceRegistry.transcribe(audioURL: permanentURL, model: currentModel)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            let cleanupConfiguration = RomaTranscriptionCleanupConfiguration.current()

            let powerModeMetadata = RomaPowerModeTranscriptionMetadata.active(
                from: PowerModeManager.shared.activeConfiguration
            )

            let textPlan = RomaTranscriptionRunPreparation.prepareAudioFileText(
                rawText,
                cleanupConfiguration: cleanupConfiguration
            ) { text in
                DictionaryService.applyWordReplacements(to: text, using: modelContext)
            }
            let cleanedText = textPlan.cleanedText
            try Task.checkCancellation()

            let enhancementRequest = textPlan.enhancementRequest(
                isEnhancementEnabled: engine.enhancementService?.isEnhancementEnabled == true,
                isEnhancementConfigured: engine.enhancementService?.isConfigured == true,
                skipConfiguration: RomaPostProcessingSkipConfiguration.current()
            )
            let draftContext = RomaAudioFileTranscriptionDraftContext(
                cleanedText: cleanedText,
                duration: duration,
                audioFileURL: permanentURL.absoluteString,
                transcriptionModelName: currentModel.displayName,
                transcriptionDuration: transcriptionDuration,
                powerModeName: powerModeMetadata.name,
                powerModeEmoji: powerModeMetadata.emoji
            )

            if enhancementRequest != nil {
                item.status = .processing(phase: .enhancing)
            }

            let completionResult = await RomaAudioFileTranscriptionDraft.completionResult(
                context: draftContext,
                enhancementRequest: enhancementRequest,
                enhancementFailurePolicy: .storeFailureText
            ) { request in
                guard let enhancementService = engine.enhancementService else {
                    throw RomaEngineError.unknownError
                }
                return try await enhancementService.enhance(request.text)
            }

            if let errorDescription = completionResult.enhancementFailureReason {
                let message = RomaAudioFileQueueDiagnostics.enhancementFailedMessage(
                    errorDescription: errorDescription
                )
                logger.error("\(message, privacy: .public)")
            }

            let transcription = Transcription(completedDraft: completionResult.draft)

            modelContext.insert(transcription)
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)

            item.transcription = transcription
            item.status = .completed
            lastCompletedItemId = item.id

        } catch {
            if Task.isCancelled || error is CancellationError {
                item.status = .pending
            } else {
                let errorDescription = RomaErrorDescription.text(for: error)
                let message = RomaAudioFileQueueDiagnostics.transcriptionErrorMessage(
                    errorDescription: errorDescription
                )
                logger.error("\(message, privacy: .public)")
                item.status = .failed(message: errorDescription)
            }
        }

        await serviceRegistry.cleanup()
    }
}
