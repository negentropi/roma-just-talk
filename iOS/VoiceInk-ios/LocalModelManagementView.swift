//
//  LocalModelManagementView.swift
//  VoiceInk-ios
//
//  UI for managing local Whisper models
//

import SwiftUI
import Combine
import VoiceInkCore

struct LocalModelManagementView: View {
    @StateObject private var modelManager = LocalModelManager.shared
    
    var body: some View {
        List {
            ForEach(VoiceInkWhisperModelFiles.bootstrapModels) { model in
                ModelRowView(model: model, modelManager: modelManager)
            }
        }
        .navigationTitle("Local Models")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            // Refresh model status
            modelManager.objectWillChange.send()
        }
        .alert("Download Error", isPresented: .constant(modelManager.downloadError != nil)) {
            Button("OK") {
                modelManager.downloadError = nil
            }
        } message: {
            if let error = modelManager.downloadError {
                Text(error)
            }
        }
    }
    

}

struct ModelRowView: View {
    let model: VoiceInkWhisperModelFileSpec
    @ObservedObject var modelManager: LocalModelManager
    @State private var showingDeleteAlert = false
    @State private var showingDownloadConfirmation = false

    private var isDownloaded: Bool {
        model.isDownloaded(in: LocalModelManager.modelsDirectory)
    }

    private var isDownloading: Bool {
        modelManager.isDownloading[model.id] == true
    }

    private var downloadProgress: VoiceInkWhisperModelDownloadProgress {
        VoiceInkWhisperModelDownloadProgress.simple(
            modelName: model.modelName,
            isDownloading: isDownloading,
            progress: modelManager.downloadProgress[model.id]
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action button where size used to be
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else if isDownloading {
                    Button(action: {
                        modelManager.cancelDownload(for: model)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                } else {
                    Button(action: {
                        showingDownloadConfirmation = true
                    }) {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                }
            }
            
            // Progress indicator when downloading
            if downloadProgress.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                        Text(downloadProgress.percentText)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    ProgressView(value: downloadProgress.fraction)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isDownloaded {
                Button("Delete") {
                    showingDeleteAlert = true
                }
                .tint(.red)
            }
        }
        .alert("Delete Model", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteModel()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Delete \(model.displayName)? This will remove the model from your device.")
        }
        .alert("Download Model", isPresented: $showingDownloadConfirmation) {
            Button("Download") {
                downloadModel()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(VoiceInkWhisperModelDownloadProgress.downloadConfirmationMessage(for: model))
        }
    }
    
    private func downloadModel() {
        Task {
            await modelManager.downloadModel(model)
        }
    }
    
    private func deleteModel() {
        do {
            try modelManager.deleteModel(model)
            // Force UI update by triggering objectWillChange
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                modelManager.objectWillChange.send()
            }
        } catch {
            print("Delete failed: \(error)")
            modelManager.downloadError = "Failed to delete model: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#Preview {
    LocalModelManagementView()
}
