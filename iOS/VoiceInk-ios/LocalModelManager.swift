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
    
    static let shared = LocalModelManager()
    
    nonisolated static var modelsDirectory: URL {
        VoiceInkIOSStorageDirectories.preparedModelsDirectory
    }
    
    private init() {
        setupModelsDirectory()
    }
    
    private func setupModelsDirectory() {
        let _ = Self.modelsDirectory // This will create the directory
    }
    
    /// Download a specific model
    func downloadModel(_ model: VoiceInkWhisperModelFileSpec) async {
        guard startDownloadTracking(for: model) else {
            print("LocalModelManager: Model \(model.modelName) is already being downloaded")
            return
        }
        
        print("LocalModelManager: Starting download of \(model.modelName) from \(model.downloadURL.absoluteString)")
        
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
        
        if let error = error {
            downloadError = .downloadFailed(for: error)
            print("LocalModelManager: Download failed for \(model.modelName): \(error)")
            return
        }
        
        switch VoiceInkWhisperModelDownloadResponsePolicy.completion(
            temporaryURL: temporaryURL,
            response: response
        ) {
        case .serverError:
            downloadError = .serverErrorDuringDownload
            print("LocalModelManager: Server error for \(model.modelName)")
            return

        case .missingTemporaryFile:
            downloadError = .noFileReceived
            print("LocalModelManager: Missing downloaded file for \(model.modelName)")
            return

        case .ready(let temporaryURL):
            installDownloadedModel(model, from: temporaryURL)
        }
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
            
            print("LocalModelManager: Successfully downloaded \(model.modelName) to \(finalURL.path)")
            updateDownloadProgress(1.0, for: model)
            
        } catch {
            downloadError = .saveFailed(for: error)
            print("LocalModelManager: Failed to save \(model.modelName): \(error)")
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
    func deleteModel(_ model: VoiceInkWhisperModelFileSpec) throws {
        guard model.isDownloaded(in: Self.modelsDirectory) else {
            print("LocalModelManager: Model \(model.modelName) is not downloaded")
            return 
        }
        
        do {
            try model.deleteDownloadedFiles(in: Self.modelsDirectory)
            print("LocalModelManager: Successfully deleted model \(model.modelName)")
            
            // Trigger UI update
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        } catch {
            print("LocalModelManager: Failed to delete model \(model.modelName): \(error)")
            throw error
        }
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
