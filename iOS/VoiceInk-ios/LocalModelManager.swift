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
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadError: String?
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    
    static let shared = LocalModelManager()
    
    nonisolated static var modelsDirectory: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return (try? VoiceInkWhisperModelFiles.createModelsDirectory(in: documentsDir))
            ?? VoiceInkWhisperModelFiles.modelsDirectory(in: documentsDir)
    }
    
    private init() {
        setupModelsDirectory()
    }
    
    private func setupModelsDirectory() {
        let _ = Self.modelsDirectory // This will create the directory
    }
    
    /// Download a specific model
    func downloadModel(_ model: VoiceInkWhisperModelFileSpec) async {
        guard !isDownloading[model.id, default: false] else {
            print("LocalModelManager: Model \(model.modelName) is already being downloaded")
            return
        }
        
        print("LocalModelManager: Starting download of \(model.modelName) from \(model.downloadURL.absoluteString)")
        
        isDownloading[model.id] = true
        downloadProgress[model.id] = 0.0
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
                self?.downloadProgress[model.id] = progress.fractionCompleted
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
            isDownloading[model.id] = false
            downloadTasks[model.id] = nil
            progressObservations[model.id] = nil
            downloadProgress[model.id] = nil
        }
        
        if let error = error {
            downloadError = "Download failed: \(error.localizedDescription)"
            print("LocalModelManager: Download failed for \(model.modelName): \(error)")
            return
        }
        
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            downloadError = "Server error during download"
            print("LocalModelManager: Server error for \(model.modelName)")
            return
        }
        
        guard let temporaryURL = temporaryURL else {
            downloadError = "No file received"
            print("LocalModelManager: No file received for \(model.modelName)")
            return
        }
        
        do {
            // Move file to final location
            let finalURL = model.fileURL(in: Self.modelsDirectory)
            
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
            
            print("LocalModelManager: Successfully downloaded \(model.modelName) to \(finalURL.path)")
            downloadProgress[model.id] = 1.0
            
        } catch {
            downloadError = "Failed to save model: \(error.localizedDescription)"
            print("LocalModelManager: Failed to save \(model.modelName): \(error)")
        }
    }
    
    /// Cancel download for a specific model
    func cancelDownload(for model: VoiceInkWhisperModelFileSpec) {
        downloadTasks[model.id]?.cancel()
        downloadTasks[model.id] = nil
        progressObservations[model.id] = nil
        isDownloading[model.id] = false
        downloadProgress[model.id] = nil
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
    
    /// Get the path to the downloaded base model, if available
    var baseModelPath: String? {
        VoiceInkWhisperModelFiles.availableBootstrapModelFileURL(in: Self.modelsDirectory)?.path
    }
    
    /// Check if any model is available for transcription
    var hasAvailableModel: Bool {
        VoiceInkWhisperModelFiles.availableBootstrapModelFileURL(in: Self.modelsDirectory) != nil
    }
    
}
