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
        .navigationTitle(VoiceInkModelManagementFilter.local.settingsSectionTitle)
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
        modelManager.downloadState(for: model)
    }

    private var downloadConfirmation: VoiceInkWhisperModelOperationConfirmationPresentation {
        .download(for: model)
    }

    private var deleteConfirmation: VoiceInkWhisperModelOperationConfirmationPresentation {
        .delete(for: model)
    }

    private var rowPresentation: VoiceInkWhisperModelDownloadRowPresentation {
        downloadState.rowPresentation(for: model)
    }
    
    var body: some View {
        let presentation = rowPresentation

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.headline)
                    Text(presentation.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action button where size used to be
                switch presentation.action {
                case .downloaded:
                    Image(systemName: presentation.actionSystemImageName)
                        .foregroundColor(.green)
                        .font(.title2)
                case .downloading:
                    Button(action: {
                        modelManager.cancelDownload(for: model)
                    }) {
                        Image(systemName: presentation.actionSystemImageName)
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                case .download:
                    Button(action: {
                        showingDownloadConfirmation = true
                    }) {
                        Image(systemName: presentation.actionSystemImageName)
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                }
            }
            
            // Progress indicator when downloading
            if presentation.shouldShowProgress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(presentation.progress.compactStatusText)
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                        Text(presentation.progress.percentText)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    ProgressView(value: presentation.progress.fraction)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if presentation.action == .downloaded {
                Button(deleteConfirmation.primaryButtonTitle) {
                    showingDeleteAlert = true
                }
                .tint(.red)
            }
        }
        .alert(deleteConfirmation.title, isPresented: $showingDeleteAlert) {
            Button(deleteConfirmation.primaryButtonTitle, role: .destructive) {
                deleteModel()
            }
            Button(deleteConfirmation.cancelButtonTitle, role: .cancel) { }
        } message: {
            Text(deleteConfirmation.message)
        }
        .alert(downloadConfirmation.title, isPresented: $showingDownloadConfirmation) {
            Button(downloadConfirmation.primaryButtonTitle) {
                downloadModel()
            }
            Button(downloadConfirmation.cancelButtonTitle, role: .cancel) { }
        } message: {
            Text(downloadConfirmation.message)
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
