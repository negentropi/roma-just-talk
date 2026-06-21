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
            ForEach(modelManager.managementRows()) { row in
                ModelRowView(row: row, modelManager: modelManager)
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
    let row: VoiceInkWhisperModelManagementRow
    @ObservedObject var modelManager: LocalModelManager
    @State private var showingDeleteAlert = false
    @State private var showingDownloadConfirmation = false
    
    var body: some View {
        let presentation = row.presentation

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
                        modelManager.cancelDownload(for: row.model)
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
                Button(row.deleteConfirmation.primaryButtonTitle) {
                    showingDeleteAlert = true
                }
                .tint(.red)
            }
        }
        .alert(row.deleteConfirmation.title, isPresented: $showingDeleteAlert) {
            Button(row.deleteConfirmation.primaryButtonTitle, role: .destructive) {
                deleteModel()
            }
            Button(row.deleteConfirmation.cancelButtonTitle, role: .cancel) { }
        } message: {
            Text(row.deleteConfirmation.message)
        }
        .alert(row.downloadConfirmation.title, isPresented: $showingDownloadConfirmation) {
            Button(row.downloadConfirmation.primaryButtonTitle) {
                Task {
                    await modelManager.downloadModel(row.model)
                }
            }
            Button(row.downloadConfirmation.cancelButtonTitle, role: .cancel) { }
        } message: {
            Text(row.downloadConfirmation.message)
        }
    }
    
    private func deleteModel() {
        do {
            try modelManager.deleteModel(row.model)
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
