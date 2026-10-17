//
//  LocalModelManager.swift
//  RomaJustTalk-ios
//
//  Manages local Whisper model downloading and storage
//

import Foundation
import Combine
import OSLog
import RomaCore

@MainActor
class LocalModelManager: ObservableObject {
    @Published private var downloadSessionState = RomaWhisperModelSimpleDownloadSessionState()
    @Published var localModelAvailabilityRevision = 0
    @Published var downloadError: RomaWhisperModelOperationAlertPresentation?
    @Published private(set) var importedModels: [RomaWhisperLocalModelFile] = []
    @Published var importAlert: IOSLocalWhisperModelImportAlert?
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    private let logger = RomaIOSLogger.localModelManagement
    private let contextCache = IOSRetainedContextCache<WhisperContext>(
        factory: { try await WhisperContext.createContext(path: $0) },
        release: { await $0.releaseResources() }
    )
    
    static let shared = LocalModelManager()
    
    nonisolated static var modelsDirectory: URL {
        RomaIOSStorageDirectories.preparedModelsDirectory
    }
    
    private init() {
        _ = Self.modelsDirectory
        refreshImportedModels()
    }

    var managementSnapshot: RomaWhisperModelManagementSnapshot {
        RomaWhisperModelManagementSnapshot(
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
            throw RomaLocalWhisperFailurePolicy.error(
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
        let cancellationToken = RomaWhisperCancellationToken()
        let success = await withTaskCancellationHandler {
            if Task.isCancelled {
                cancellationToken.cancel()
            }
            return await context.fullTranscribe(
                samples: [Float](
                    repeating: 0,
                    count: RomaModelPrewarmSamplePolicy.generatedSilenceSampleCount
                ),
                language: nil,
                cancellationToken: cancellationToken
            )
        } onCancel: {
            cancellationToken.cancel()
        }
        try Task.checkCancellation()
        guard success else {
            throw RomaLocalWhisperFailurePolicy.error(
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
        catalogModelNames + RomaWhisperModelFiles.importedLocalModelNamesToAdd(
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

    func deleteImportedModel(_ model: RomaWhisperLocalModelFile) {
        do {
            try RomaWhisperModelFiles.deleteModelFiles(
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
        let localModels = (try? RomaWhisperModelFiles.localModelFiles(
            in: Self.modelsDirectory,
            fileManager: fileManager
        )) ?? []
        let catalogModelNames = RomaWhisperModelFiles.downloadableModels.map(\.modelName)
        let importedModelNames = Set(
            RomaWhisperModelFiles.importedLocalModelNamesToAdd(
                downloadedLocalModels: localModels,
                existingModelNames: catalogModelNames
            )
        )
        importedModels = localModels
            .filter { importedModelNames.contains($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Download a specific model
    func downloadModel(_ model: RomaWhisperModelFileSpec) async {
        guard let downloadSessionID = downloadSessionState.startDownload(for: model) else {
            logger.notice("\(RomaWhisperModelManagementDiagnostics.alreadyDownloadingMessage(modelName: model.modelName), privacy: .public)")
            return
        }
        
        logger.notice("\(RomaWhisperModelManagementDiagnostics.startingDownloadMessage(modelName: model.modelName, downloadURL: model.downloadURL), privacy: .public)")
        
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
        for model: RomaWhisperModelFileSpec,
        downloadSessionID: RomaWhisperModelSimpleDownloadSessionID,
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
        
        RomaWhisperModelSimpleDownloadCompletionPlan.completion(
            temporaryURL: temporaryURL,
            response: response,
            error: error
        ).applyRuntimeState(
            installTemporaryFile: { temporaryURL in
                installDownloadedModel(model, from: temporaryURL, downloadSessionID: downloadSessionID)
            },
            presentFailure: { alert in
                downloadError = alert
                logger.error("\(RomaWhisperModelManagementDiagnostics.downloadFailedMessage(modelName: model.modelName, alertMessage: alert.message), privacy: .public)")
            },
            ignoreCancellation: {
                logger.notice("\(RomaWhisperModelManagementDiagnostics.downloadCancelledMessage(modelName: model.modelName), privacy: .public)")
            }
        )
    }

    private func installDownloadedModel(
        _ model: RomaWhisperModelFileSpec,
        from temporaryURL: URL,
        downloadSessionID: RomaWhisperModelSimpleDownloadSessionID
    ) {
        do {
            let finalURL = try RomaWhisperModelFiles.installDownloadedModelFile(
                model,
                fromTemporaryFile: temporaryURL,
                in: Self.modelsDirectory
            )
            
            logger.notice("\(RomaWhisperModelManagementDiagnostics.downloadedMessage(modelName: model.modelName, finalPath: finalURL.path), privacy: .public)")
            downloadSessionState.updateProgress(1.0, for: model, sessionID: downloadSessionID)
            localModelAvailabilityRevision += 1
            
        } catch {
            downloadError = .saveFailed(for: error)
            logger.error("\(RomaWhisperModelManagementDiagnostics.saveFailedMessage(modelName: model.modelName, localizedDescription: error.localizedDescription), privacy: .public)")
        }
    }
    
    /// Cancel download for a specific model
    func cancelDownload(for model: RomaWhisperModelFileSpec) {
        if downloadTasks[model.id] != nil {
            logger.notice("\(RomaWhisperModelManagementDiagnostics.downloadCancelledMessage(modelName: model.modelName), privacy: .public)")
        }
        downloadTasks[model.id]?.cancel()
        downloadTasks[model.id] = nil
        progressObservations[model.id] = nil
        downloadSessionState.cancelDownload(for: model)
    }
    
    /// Delete a downloaded model
    func deleteModel(_ model: RomaWhisperModelFileSpec) {
        let deletedModelPath = model.fileURL(in: Self.modelsDirectory).path
        let deletionPlan = RomaWhisperModelDeletionPolicy.plan(
            for: model,
            in: Self.modelsDirectory
        )

        deletionPlan.applyRuntimeState(
            skipMissingFile: {
                logger.notice("\(RomaWhisperModelManagementDiagnostics.notDownloadedMessage(modelName: model.modelName), privacy: .public)")
            },
            deleteDownloadedFiles: {
                try model.deleteDownloadedFiles(in: Self.modelsDirectory)
                logger.notice("\(RomaWhisperModelManagementDiagnostics.deletedMessage(modelName: model.modelName), privacy: .public)")
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
                logger.error("\(RomaWhisperModelManagementDiagnostics.deleteFailedMessage(modelName: model.modelName, localizedDescription: error.localizedDescription), privacy: .public)")
            }
        )
    }
    
}
