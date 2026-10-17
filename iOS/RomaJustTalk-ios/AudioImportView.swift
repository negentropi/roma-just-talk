import SwiftData
import SwiftUI
import RomaCore

struct AudioImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var manager = IOSAudioImportManager.shared
    @StateObject private var settings = AppSettings.shared
    @State private var isFileImporterPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if manager.queue.isEmpty {
                    ContentUnavailableView {
                        Label(
                            "Transcribe Audio Files",
                            systemImage: RomaAudioImportPresentation.dropTargetSystemImageName
                        )
                    } description: {
                        Text(RomaSupportedMedia.supportedFileTypesText)
                    } actions: {
                        Button(RomaAudioImportPresentation.chooseFilesButtonTitle) {
                            isFileImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section("Mode") {
                            RomaModeSelectionControlView(
                                modes: settings.modes,
                                selectedModeId: $settings.selectedModeId
                            )
                        }

                        Section(RomaAudioImportPresentation.queueCountText(manager.queue.count)) {
                            ForEach(manager.queue) { item in
                                queueRow(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Audio Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: RomaAudioImportPresentation.addButtonSystemImageName)
                    }
                    .accessibilityLabel(RomaAudioImportPresentation.addButtonTitle)

                    if manager.isProcessingQueue {
                        Button(role: .destructive) {
                            manager.cancelProcessing()
                        } label: {
                            Image(systemName: RomaAudioImportPresentation.cancelButtonSystemImageName)
                        }
                        .accessibilityLabel(RomaAudioImportPresentation.cancelButtonTitle)
                    } else if manager.hasPendingItems {
                        Button {
                            manager.startProcessing(modelContext: modelContext)
                        } label: {
                            Image(systemName: RomaAudioImportPresentation.startButtonSystemImageName)
                        }
                        .accessibilityLabel(RomaAudioImportPresentation.startButtonTitle)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        manager.clearFinishedAndPendingItems()
                    } label: {
                        Label(
                            RomaAudioImportPresentation.clearButtonTitle,
                            systemImage: RomaAudioImportPresentation.clearButtonSystemImageName
                        )
                    }
                    .disabled(manager.queue.isEmpty || manager.isProcessingQueue)
                }
            }
            .overlay {
                if manager.isImporting {
                    ProgressView("Preparing files...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: RomaSupportedMedia.contentTypes,
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                Task { await manager.add(urls: urls) }
            }
            .alert(
                "Import Failed",
                isPresented: Binding(
                    get: { manager.importErrorMessage != nil },
                    set: { if !$0 { manager.importErrorMessage = nil } }
                )
            ) {
                Button("OK") { manager.importErrorMessage = nil }
            } message: {
                Text(manager.importErrorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func queueRow(_ item: RomaIOSAudioImportQueueItem) -> some View {
        HStack(spacing: 12) {
            statusIcon(item.status)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText(item.status))
                    .font(.caption)
                    .foregroundStyle(statusColor(item.status))
            }

            Spacer()

            switch item.status {
            case .pending:
                Button(role: .destructive) {
                    manager.removePendingItem(id: item.id)
                } label: {
                    Image(systemName: RomaAudioFileQueuePresentation.removeButtonSystemImageName)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove")
            case .processing:
                ProgressView()
            case .completed:
                if let note = item.transcription {
                    ShareLink(item: preferredText(note)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Share transcript")
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("View transcript")
                }
            case .failed:
                Button {
                    manager.retryItem(id: item.id)
                    manager.startProcessing(modelContext: modelContext)
                } label: {
                    Image(systemName: RomaAudioFileQueuePresentation.retryButtonSystemImageName)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Retry")
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: RomaAudioFileQueueStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: RomaAudioFileQueuePresentation.pendingStatusSystemImageName)
                .foregroundStyle(.secondary)
        case .processing:
            Image(systemName: "waveform")
                .foregroundStyle(.blue)
        case .completed:
            Image(systemName: RomaAudioFileQueuePresentation.completedStatusSystemImageName)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: RomaAudioFileQueuePresentation.failedStatusSystemImageName)
                .foregroundStyle(.red)
        }
    }

    private func statusText(_ status: RomaAudioFileQueueStatus) -> String {
        switch status {
        case .pending:
            return RomaAudioFileQueuePresentation.pendingStatusText
        case .processing(let phase):
            return phase.displayText
        case .completed:
            return "Completed"
        case .failed(let message):
            return message
        }
    }

    private func statusColor(_ status: RomaAudioFileQueueStatus) -> Color {
        switch status {
        case .failed:
            return .red
        case .processing:
            return .blue
        case .pending, .completed:
            return .secondary
        }
    }

    private func preferredText(_ note: Transcription) -> String {
        RomaTranscriptPresentation.preferredText(
            rawText: note.text,
            enhancedText: note.enhancedText
        ) ?? note.text
    }
}
