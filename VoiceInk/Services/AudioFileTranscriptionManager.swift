import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import os
import VoiceInkCore

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
    private let serviceRegistryFactory: (@MainActor (ModelContext, VoiceInkEngine) -> TranscriptionServiceRegistry)?
    private let processingWarning: @MainActor (String) -> Void
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.audioTranscriptionManager
    )

    init(
        serviceRegistryFactory: (@MainActor (ModelContext, VoiceInkEngine) -> TranscriptionServiceRegistry)? = nil,
        processingWarning: @escaping @MainActor (String) -> Void = { reason in
            NotificationManager.shared.showNotification(
                title: "Processing unavailable. The original recognition was retained. \(reason)", type: .warning
            )
        }
    ) {
        self.serviceRegistryFactory = serviceRegistryFactory
        self.processingWarning = processingWarning
    }

    // MARK: - Queue Management

    /// Add one or more audio file URLs to the queue. Invalid files are silently skipped.
    func addToQueue(urls: [URL]) {
        let candidates = urls.map {
            VoiceInkAudioFileQueueCandidate(
                url: $0,
                fileExists: FileManager.default.fileExists(atPath: $0.path),
                isSupported: VoiceInkSupportedMedia.isSupported(url: $0)
            )
        }

        for url in VoiceInkAudioFileQueuePolicy.eligibleAdditionURLs(from: candidates, existingItems: queueFacts) {
            let item = AudioFileQueueItem(url: url)
            queue.append(item)
        }
    }

    /// Remove a pending item from the queue.
    func removeFromQueue(id: UUID) {
        guard VoiceInkAudioFileQueuePolicy.canRemoveItem(id: id, from: queueFacts) else { return }
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
              let retryStatus = VoiceInkAudioFileQueuePolicy.statusAfterRetryRequest(item.status) else { return }

        item.status = retryStatus
    }

    /// Start processing pending items in the queue sequentially.
    func startProcessing(modelContext: ModelContext, engine: VoiceInkEngine) {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        processingGeneration &+= 1
        let generation = processingGeneration

        processingTask = Task { [weak self] in
            guard let self else { return }

            while let item = self.nextPendingItem() {
                guard !Task.isCancelled, self.processingGeneration == generation else { break }
                await self.processItem(item, generation: generation, modelContext: modelContext, engine: engine)
            }

            if self.processingGeneration == generation {
                self.isProcessingQueue = false
                self.processingTask = nil
            }
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingGeneration &+= 1
        processingTask = nil
        isProcessingQueue = false

        let statuses = VoiceInkAudioFileQueuePolicy.statusesAfterCancelingProcessing(queue.map(\.status))
        for (item, status) in zip(queue, statuses) {
            item.status = status
        }
    }

    var hasPendingItems: Bool {
        VoiceInkAudioFileQueuePolicy.hasPendingItems(in: queueFacts)
    }

    // MARK: - Private

    private var queueFacts: [VoiceInkAudioFileQueueItemFacts<UUID>] {
        queue.map {
            VoiceInkAudioFileQueueItemFacts(
                id: $0.id,
                standardizedPath: $0.url.standardizedFileURL.path,
                status: $0.status
            )
        }
    }

    private func nextPendingItem() -> AudioFileQueueItem? {
        guard let id = VoiceInkAudioFileQueuePolicy.nextPendingItemID(in: queueFacts) else { return nil }
        return queue.first { $0.id == id }
    }

    private func owns(_ item: AudioFileQueueItem, generation: UInt64) -> Bool {
        processingGeneration == generation && queue.contains { $0 === item }
    }

    private func processItem(_ item: AudioFileQueueItem, generation: UInt64, modelContext: ModelContext, engine: VoiceInkEngine) async {
        let plan = DictationPostprocessingPlan.capture(
            profile: .current(), using: modelContext, enhancementService: engine.enhancementService
        )
        let serviceRegistry = serviceRegistryFactory?(modelContext, engine) ?? TranscriptionServiceRegistry(
            modelProvider: engine.whisperModelManager,
            modelsDirectory: engine.whisperModelManager.modelsDirectory,
            modelContext: modelContext,
            qwenRuntimeResult: engine.serviceRegistry.qwenRuntimeResult
        )
        var ownedAudio: URL?
        var committed = false
        defer {
            if !committed, let ownedAudio { try? FileManager.default.removeItem(at: ownedAudio) }
        }
        func checkOwnership() throws {
            try Task.checkCancellation()
            guard owns(item, generation: generation) else { throw CancellationError() }
        }
        do {
            try checkOwnership()
            guard let currentModel = engine.transcriptionModelManager.currentTranscriptionModel else {
                throw VoiceInkEngineError.noTranscriptionModelSelected
            }

            // Phase: Loading
            item.status = .processing(phase: .loading)
            try checkOwnership()

            // Phase: Processing Audio
            item.status = .processing(phase: .processingAudio)

            let accessing = item.url.startAccessingSecurityScopedResource()
            defer { if accessing { item.url.stopAccessingSecurityScopedResource() } }

            let samples = try await audioProcessor.processAudioToSamples(item.url)
            try checkOwnership()

            let audioAsset = AVURLAsset(url: item.url)
            let duration = CMTimeGetSeconds(try await audioAsset.load(.duration))
            try checkOwnership()

            let appSupportDirectory = VoiceInkMacOSStorageDirectories.appSupportDirectory
            let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: appSupportDirectory)

            let permanentURL = VoiceInkStoredAudioFile.importedTranscriptionFileURL(in: recordingsDirectory)
            guard !FileManager.default.fileExists(atPath: permanentURL.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            ownedAudio = permanentURL
            try audioProcessor.saveSamplesAsWav(samples: samples, to: permanentURL)
            try checkOwnership()

            // Phase: Transcribing
            item.status = .processing(phase: .transcribing)
            let transcriptionStart = Date()
            let rawText = try await serviceRegistry.transcribe(audioURL: permanentURL, model: currentModel)
            try checkOwnership()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            let powerModeMetadata = VoiceInkPowerModeTranscriptionMetadata.active(
                from: PowerModeManager.shared.activeConfiguration
            )
            let preparation = AudioFileDictationPostprocessing.prepare(
                recognitionText: rawText, plan: plan, modelContext: modelContext
            )

            let draft = try await AudioFileDictationPostprocessing.completedDraft(
                recognitionText: rawText,
                preparation: preparation,
                duration: duration,
                audioFileURL: permanentURL.absoluteString,
                transcriptionModelName: currentModel.displayName,
                transcriptionDuration: transcriptionDuration,
                powerModeMetadata: powerModeMetadata,
                enhancementService: engine.enhancementService,
                detectsPromptTriggers: false,
                enhancementFailurePolicy: .storeFailureText,
                shouldCancel: { !self.owns(item, generation: generation) },
                willEnhance: {
                    if self.owns(item, generation: generation), !Task.isCancelled {
                        item.status = .processing(phase: .enhancing)
                    }
                }
            )
            try checkOwnership()
            let savedID = try AudioFileTranscriptionPersistence.save(draft, in: modelContext.container)
            committed = true
            try checkOwnership()
            guard let transcription = modelContext.model(for: savedID) as? Transcription else {
                throw AudioFileTranscriptionPersistence.SavedTranscriptionUnavailable()
            }
            try checkOwnership()
            item.transcription = transcription
            item.status = .completed
            lastCompletedItemId = item.id
            try checkOwnership()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            try checkOwnership()
            NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
            if owns(item, generation: generation), let reason = transcription.processingFailureReason {
                processingWarning(reason)
            }

        } catch {
            if !owns(item, generation: generation) {
                // A canceled older task cannot reset a retried item's newer state.
            } else if Task.isCancelled || error is CancellationError {
                item.status = .pending
            } else {
                let errorDescription = VoiceInkErrorDescription.text(for: error)
                let message = VoiceInkAudioFileQueueDiagnostics.transcriptionErrorMessage(
                    errorDescription: errorDescription
                )
                logger.error("\(message, privacy: .public)")
                item.status = .failed(message: errorDescription)
            }
        }

        await serviceRegistry.cleanup()
    }
}
