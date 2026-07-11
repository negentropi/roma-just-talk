import SwiftUI
import VoiceInkCore

struct IOSFluidAudioModelManagementSection: View {
    @ObservedObject var modelManager: FluidAudioModelManager

    var body: some View {
        Section("Parakeet") {
            ForEach(VoiceInkTranscriptionModelCatalog.fluidAudioModels, id: \.name) { model in
                IOSFluidAudioModelRow(model: model, modelManager: modelManager)
            }
        }
    }
}

private struct IOSFluidAudioModelRow: View {
    let model: VoiceInkFluidAudioTranscriptionModelSpec
    @ObservedObject var modelManager: FluidAudioModelManager
    @State private var isShowingDownloadConfirmation = false
    @State private var isShowingDeleteConfirmation = false

    private var isDownloaded: Bool {
        modelManager.isFluidAudioModelDownloaded(named: model.name)
    }

    private var isDownloading: Bool {
        modelManager.isFluidAudioModelDownloading(named: model.name)
    }

    private var status: VoiceInkFluidAudioDownloadStatus? {
        modelManager.downloadStatus(forModelNamed: model.name)
    }

    private var issue: FluidAudioModelDownloadIssue? {
        modelManager.downloadIssue(forModelNamed: model.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(model.size, systemImage: "internaldrive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                actionControl
            }

            if let status {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(status.message)
                        Spacer()
                        Text(status.percentText)
                    }
                    .font(.caption)
                    ProgressView(value: status.fractionCompleted)
                }
            }

            if let issue {
                Label(issue.message, systemImage: issue.systemImage)
                    .font(.caption)
                    .foregroundStyle(issue == .stalled ? Color.orange : Color.secondary)
            }
        }
        .confirmationDialog(
            "Download \(model.displayName)?",
            isPresented: $isShowingDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Download") {
                Task {
                    await modelManager.downloadFluidAudioModel(named: model.name)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The model requires approximately \(model.size) of local storage.")
        }
        .alert(
            "Delete \(model.displayName)?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                modelManager.deleteFluidAudioModel(named: model.name)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Modes using this model will switch to another available transcription provider.")
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        if isDownloading {
            Button {
                modelManager.cancelFluidAudioModelDownload(named: model.name)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .accessibilityLabel("Cancel download")
        } else if issue != nil {
            Button("Retry") {
                Task {
                    await modelManager.retryFluidAudioModelDownload(named: model.name)
                }
            }
            .buttonStyle(.borderedProminent)
        } else if isDownloaded {
            Menu {
                Button("Delete Model", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .accessibilityLabel("Model downloaded")
        } else {
            Button("Download") {
                isShowingDownloadConfirmation = true
            }
            .buttonStyle(.bordered)
        }
    }
}
