//
//  LocalModelManager.swift
//  VoiceInk-ios
//
//  Manages local Whisper model downloading and storage
//

import Foundation
import Combine
import OSLog
import VoiceInkCore

@MainActor
class LocalModelManager: ObservableObject {
    @Published private var downloadSessionState = VoiceInkWhisperModelSimpleDownloadSessionState()
    @Published var localModelAvailabilityRevision = 0
    @Published var downloadError: VoiceInkWhisperModelOperationAlertPresentation?
    @Published private(set) var importedModels: [VoiceInkWhisperLocalModelFile] = []
    @Published var importAlert: IOSLocalWhisperModelImportAlert?
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    private let logger = VoiceInkIOSLogger.localModelManagement
    private let contextCache = IOSRetainedContextCache<WhisperContext>(
        factory: { try await WhisperContext.createContext(path: $0) },
        release: { await $0.releaseResources() }
    )
    
    static let shared = LocalModelManager()
    
    nonisolated static var modelsDirectory: URL {
        VoiceInkIOSStorageDirectories.preparedModelsDirectory
    }
    
    private init() {
        _ = Self.modelsDirectory
        refreshImportedModels()
    }

    var managementSnapshot: VoiceInkWhisperModelManagementSnapshot {
        VoiceInkWhisperModelManagementSnapshot(
            modelsDirectory: Self.modelsDirectory,
            downloadTrackingState: downloadSessionState.downloadTrackingState
        )
    }

    func retainedContext(
        forRuntimeModelName modelName: String
    ) async throws -> (context: WhisperContext, modelPath: String) {
        guard let modelPath = managementSnapshot.modelPath(
            forRuntimeModelName: modelName
        ) else {
            throw VoiceInkLocalWhisperFailurePolicy.error(
                for: .modelUnavailable,
                platform: .iOS
            )
        }
        return (
            try await contextCache.context(forModelPath: modelPath),
            modelPath
        )
    }

    func prewarmContext(forRuntimeModelName modelName: String) async throws {
        let retained = try await retainedContext(
            forRuntimeModelName: modelName
        )
        let context = retained.context
        let cancellationToken = VoiceInkWhisperCancellationToken()
        let success = await withTaskCancellationHandler {
            if Task.isCancelled {
                cancellationToken.cancel()
            }
            return await context.fullTranscribe(
                samples: [Float](
                    repeating: 0,
                    count: VoiceInkModelPrewarmSamplePolicy.generatedSilenceSampleCount
                ),
                language: nil,
                cancellationToken: cancellationToken
            )
        } onCancel: {
            cancellationToken.cancel()
        }
        try Task.checkCancellation()
        guard success else {
            throw VoiceInkLocalWhisperFailurePolicy.error(
                for: .transcriptionFailed,
                platform: .iOS
            )
        }
    }

    func releaseRetainedContext() async {
        await contextCache.releaseRetainedContext()
    }

    var importedModelNames: [String] {
        importedModels.map(\.name)
    }

    func selectableLocalModelNames(catalogModelNames: [String]) -> [String] {
        catalogModelNames + VoiceInkWhisperModelFiles.importedLocalModelNamesToAdd(
            downloadedLocalModels: importedModels,
            existingModelNames: catalogModelNames
        )
    }

    func importModel(from sourceURL: URL) async {
        let modelsDirectory = Self.modelsDirectory
        let outcome = await Task.detached {
            IOSLocalWhisperModelImporter.importModel(
                from: sourceURL,
                into: modelsDirectory
            )
        }.value

        switch outcome {
        case .imported(let model):
            refreshImportedModels()
            localModelAvailabilityRevision += 1
            importAlert = .success(filename: model.url.lastPathComponent)
        case .duplicate(let filename):
            importAlert = .duplicate(filename: filename)
        case .unsupportedFile:
            importAlert = .unsupportedFile
        case .failed(let message):
            importAlert = .failure(message: message)
        }
    }

    func deleteImportedModel(_ model: VoiceInkWhisperLocalModelFile) {
        do {
            try VoiceInkWhisperModelFiles.deleteModelFiles(
                forModelName: model.name,
                modelFileURL: model.url,
                coreMLEncoderURL: model.coreMLEncoderURL,
                in: Self.modelsDirectory
            )
            refreshImportedModels()
            localModelAvailabilityRevision += 1
            Task {
                if await contextCache.retainedModelPath() == model.url.path {
                    await contextCache.releaseRetainedContext()
                }
            }
        } catch {
            importAlert = .failure(message: error.localizedDescription)
        }
    }

    func refreshImportedModels(fileManager: FileManager = .default) {
        let localModels = (try? VoiceInkWhisperModelFiles.localModelFiles(
            in: Self.modelsDirectory,
            fileManager: fileManager
        )) ?? []
        let catalogModelNames = VoiceInkWhisperModelFiles.downloadableModels.map(\.modelName)
        let importedModelNames = Set(
            VoiceInkWhisperModelFiles.importedLocalModelNamesToAdd(
                downloadedLocalModels: localModels,
                existingModelNames: catalogModelNames
            )
        )
        importedModels = localModels
            .filter { importedModelNames.contains($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Download a specific model
    func downloadModel(_ model: VoiceInkWhisperModelFileSpec) async {
        guard let downloadSessionID = downloadSessionState.startDownload(for: model) else {
            logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.alreadyDownloadingMessage(modelName: model.modelName), privacy: .public)")
            return
        }
        
        logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.startingDownloadMessage(modelName: model.modelName, downloadURL: model.downloadURL), privacy: .public)")
        
        downloadError = nil
        
        let downloadTask = URLSession.shared.downloadTask(with: model.downloadURL) { [weak self] temporaryURL, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.handleDownloadCompletion(
                    for: model,
                    downloadSessionID: downloadSessionID,
                    temporaryURL: temporaryURL,
                    response: response,
                    error: error
                )
            }
        }

        // Track progress
        let progressObservation = downloadTask.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.downloadSessionState.updateProgress(
                    progress.fractionCompleted,
                    for: model,
                    sessionID: downloadSessionID
                )
            }
        }

        downloadTasks[model.id] = downloadTask
        progressObservations[model.id] = progressObservation
        downloadTask.resume()
    }
    
    private func handleDownloadCompletion(
        for model: VoiceInkWhisperModelFileSpec,
        downloadSessionID: VoiceInkWhisperModelSimpleDownloadSessionID,
        temporaryURL: URL?,
        response: URLResponse?,
        error: Error?
    ) {
        guard downloadSessionState.isCurrentDownload(for: model, sessionID: downloadSessionID) else { return }

        defer {
            downloadSessionState.finishDownload(for: model, sessionID: downloadSessionID)
            downloadTasks[model.id] = nil
            progressObservations[model.id] = nil
        }
        
        VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
            temporaryURL: temporaryURL,
            response: response,
            error: error
        ).applyRuntimeState(
            installTemporaryFile: { temporaryURL in
                installDownloadedModel(model, from: temporaryURL, downloadSessionID: downloadSessionID)
            },
            presentFailure: { alert in
                downloadError = alert
                logger.error("\(VoiceInkWhisperModelManagementDiagnostics.downloadFailedMessage(modelName: model.modelName, alertMessage: alert.message), privacy: .public)")
            },
            ignoreCancellation: {
                logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.downloadCancelledMessage(modelName: model.modelName), privacy: .public)")
            }
        )
    }

    private func installDownloadedModel(
        _ model: VoiceInkWhisperModelFileSpec,
        from temporaryURL: URL,
        downloadSessionID: VoiceInkWhisperModelSimpleDownloadSessionID
    ) {
        do {
            let finalURL = try VoiceInkWhisperModelFiles.installDownloadedModelFile(
                model,
                fromTemporaryFile: temporaryURL,
                in: Self.modelsDirectory
            )
            
            logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.downloadedMessage(modelName: model.modelName, finalPath: finalURL.path), privacy: .public)")
            downloadSessionState.updateProgress(1.0, for: model, sessionID: downloadSessionID)
            localModelAvailabilityRevision += 1
            
        } catch {
            downloadError = .saveFailed(for: error)
            logger.error("\(VoiceInkWhisperModelManagementDiagnostics.saveFailedMessage(modelName: model.modelName, localizedDescription: error.localizedDescription), privacy: .public)")
        }
    }
    
    /// Cancel download for a specific model
    func cancelDownload(for model: VoiceInkWhisperModelFileSpec) {
        if downloadTasks[model.id] != nil {
            logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.downloadCancelledMessage(modelName: model.modelName), privacy: .public)")
        }
        downloadTasks[model.id]?.cancel()
        downloadTasks[model.id] = nil
        progressObservations[model.id] = nil
        downloadSessionState.cancelDownload(for: model)
    }
    
    /// Delete a downloaded model
    func deleteModel(_ model: VoiceInkWhisperModelFileSpec) {
        let deletedModelPath = model.fileURL(in: Self.modelsDirectory).path
        let deletionPlan = VoiceInkWhisperModelDeletionPolicy.plan(
            for: model,
            in: Self.modelsDirectory
        )

        deletionPlan.applyRuntimeState(
            skipMissingFile: {
                logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.notDownloadedMessage(modelName: model.modelName), privacy: .public)")
            },
            deleteDownloadedFiles: {
                try model.deleteDownloadedFiles(in: Self.modelsDirectory)
                logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.deletedMessage(modelName: model.modelName), privacy: .public)")
                localModelAvailabilityRevision += 1
            },
            refreshAfterSuccessfulDelete: {
                Task {
                    if await self.contextCache.retainedModelPath() == deletedModelPath {
                        await self.contextCache.releaseRetainedContext()
                    }
                }
                // The downloaded-state query is file-backed, so force SwiftUI to refresh the row.
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            },
            handleDeleteFailure: { error in
                downloadError = .deleteFailed(for: error)
                logger.error("\(VoiceInkWhisperModelManagementDiagnostics.deleteFailedMessage(modelName: model.modelName, localizedDescription: error.localizedDescription), privacy: .public)")
            }
        )
    }
    
}
