//
//  LocalModelManager.swift
//  VoiceInk-ios
//
//  Manages local Whisper model downloading and storage
//

import Foundation
import Combine
import VoiceInkCore

@MainActor
class LocalModelManager: ObservableObject {
    @Published private var downloadTrackingState = VoiceInkWhisperModelSimpleDownloadTrackingState()
    @Published var downloadError: VoiceInkWhisperModelOperationAlertPresentation?
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    private let logger = VoiceInkIOSLogger.localModelManagement
    
    static let shared = LocalModelManager()
    
    nonisolated static var modelsDirectory: URL {
        VoiceInkIOSStorageDirectories.preparedModelsDirectory
    }
    
    private init() {
        _ = Self.modelsDirectory
    }
    
    /// Download a specific model
    func downloadModel(_ model: VoiceInkWhisperModelFileSpec) async {
        guard startDownloadTracking(for: model) else {
            logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.alreadyDownloadingMessage(modelName: model.modelName), privacy: .public)")
            return
        }
        
        logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.startingDownloadMessage(modelName: model.modelName, downloadURL: model.downloadURL), privacy: .public)")
        
        downloadError = nil
        
        let downloadTask = URLSession.shared.downloadTask(with: model.downloadURL) { [weak self] temporaryURL, response, error in
            Task { @MainActor in
                self?.handleDownloadCompletion(
                    for: model,
                    temporaryURL: temporaryURL,
                    response: response,
                    error: error
                )
            }
        }

        // Track progress
        let progressObservation = downloadTask.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.updateDownloadProgress(progress.fractionCompleted, for: model)
            }
        }

        downloadTasks[model.id] = downloadTask
        progressObservations[model.id] = progressObservation
        downloadTask.resume()
    }
    
    private func handleDownloadCompletion(
        for model: VoiceInkWhisperModelFileSpec,
        temporaryURL: URL?,
        response: URLResponse?,
        error: Error?
    ) {
        defer {
            finishDownloadTracking(for: model)
            downloadTasks[model.id] = nil
            progressObservations[model.id] = nil
        }
        
        VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
            temporaryURL: temporaryURL,
            response: response,
            error: error
        ).applyRuntimeState(
            installTemporaryFile: { temporaryURL in
                installDownloadedModel(model, from: temporaryURL)
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
        from temporaryURL: URL
    ) {
        do {
            let finalURL = try VoiceInkWhisperModelFiles.installDownloadedModelFile(
                model,
                fromTemporaryFile: temporaryURL,
                in: Self.modelsDirectory
            )
            
            logger.notice("\(VoiceInkWhisperModelManagementDiagnostics.downloadedMessage(modelName: model.modelName, finalPath: finalURL.path), privacy: .public)")
            updateDownloadProgress(1.0, for: model)
            
        } catch {
            downloadError = .saveFailed(for: error)
            logger.error("\(VoiceInkWhisperModelManagementDiagnostics.saveFailedMessage(modelName: model.modelName, localizedDescription: error.localizedDescription), privacy: .public)")
        }
    }
    
    /// Cancel download for a specific model
    func cancelDownload(for model: VoiceInkWhisperModelFileSpec) {
        downloadTasks[model.id]?.cancel()
        downloadTasks[model.id] = nil
        progressObservations[model.id] = nil
        finishDownloadTracking(for: model)
    }
    
    /// Delete a downloaded model
    func deleteModel(_ model: VoiceInkWhisperModelFileSpec) {
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
            },
            refreshAfterSuccessfulDelete: {
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
    
    func modelPath(for runtimeModelName: String) -> String? {
        VoiceInkWhisperModelFiles.availableModelFileURL(
            forRuntimeModelName: runtimeModelName,
            in: Self.modelsDirectory
        )?.path
    }
    
    /// Check if any model is available for transcription
    var hasAvailableModel: Bool {
        VoiceInkWhisperModelFiles.availableBootstrapModelFileURL(in: Self.modelsDirectory) != nil
    }

    func downloadState(for model: VoiceInkWhisperModelFileSpec) -> VoiceInkWhisperModelDownloadState {
        downloadTrackingState.downloadState(for: model, modelsDirectory: Self.modelsDirectory)
    }

    func managementRows() -> [VoiceInkWhisperModelManagementRow] {
        VoiceInkWhisperModelManagementList.rows { model in
            downloadState(for: model)
        }
    }

    func managementRow(for model: VoiceInkWhisperModelFileSpec) -> VoiceInkWhisperModelManagementRow {
        VoiceInkWhisperModelManagementList.row(
            for: model,
            downloadState: downloadState(for: model)
        )
    }

    private func startDownloadTracking(for model: VoiceInkWhisperModelFileSpec) -> Bool {
        var trackingState = downloadTrackingState
        guard trackingState.startDownload(for: model) else {
            return false
        }

        downloadTrackingState = trackingState
        return true
    }

    private func updateDownloadProgress(
        _ progress: Double,
        for model: VoiceInkWhisperModelFileSpec
    ) {
        var trackingState = downloadTrackingState
        trackingState.updateProgress(progress, for: model)
        downloadTrackingState = trackingState
    }

    private func finishDownloadTracking(for model: VoiceInkWhisperModelFileSpec) {
        var trackingState = downloadTrackingState
        trackingState.finishDownload(for: model)
        downloadTrackingState = trackingState
    }
    
}
