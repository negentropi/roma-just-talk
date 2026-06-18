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
        .alert(item: $modelManager.downloadError) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(alert.primaryButtonTitle)) {
                    modelManager.downloadError = nil
                }
            )
        }
    }
    

}

struct ModelRowView: View {
    let model: VoiceInkWhisperModelFileSpec
    @ObservedObject var modelManager: LocalModelManager
    @State private var showingDeleteAlert = false
    @State private var showingDownloadConfirmation = false

    private var downloadState: VoiceInkWhisperModelDownloadState {
        VoiceInkWhisperModelDownloadState.simple(
            model: model,
            modelsDirectory: LocalModelManager.modelsDirectory,
            isDownloadingByModelID: modelManager.isDownloading,
            downloadProgressByModelID: modelManager.downloadProgress
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
                if downloadState.isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else if downloadState.isDownloading {
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
            if downloadState.progress.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(downloadState.progress.compactStatusText)
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                        Text(downloadState.progress.percentText)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    ProgressView(value: downloadState.progress.fraction)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if downloadState.isDownloaded {
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
            modelManager.downloadError = .deleteFailed(for: error)
        }
    }
}

// MARK: - Preview

#Preview {
    LocalModelManagementView()
}
