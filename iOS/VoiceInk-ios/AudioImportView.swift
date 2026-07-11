import SwiftData
import SwiftUI
import VoiceInkCore

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
                            systemImage: VoiceInkAudioImportPresentation.dropTargetSystemImageName
                        )
                    } description: {
                        Text(VoiceInkSupportedMedia.supportedFileTypesText)
                    } actions: {
                        Button(VoiceInkAudioImportPresentation.chooseFilesButtonTitle) {
                            isFileImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section("Mode") {
                            VoiceInkModeSelectionControlView(
                                modes: settings.modes,
                                selectedModeId: $settings.selectedModeId
                            )
                        }

                        Section(VoiceInkAudioImportPresentation.queueCountText(manager.queue.count)) {
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
                        Image(systemName: VoiceInkAudioImportPresentation.addButtonSystemImageName)
                    }
                    .accessibilityLabel(VoiceInkAudioImportPresentation.addButtonTitle)

                    if manager.isProcessingQueue {
                        Button(role: .destructive) {
                            manager.cancelProcessing()
                        } label: {
                            Image(systemName: VoiceInkAudioImportPresentation.cancelButtonSystemImageName)
                        }
                        .accessibilityLabel(VoiceInkAudioImportPresentation.cancelButtonTitle)
                    } else if manager.hasPendingItems {
                        Button {
                            manager.startProcessing(modelContext: modelContext)
                        } label: {
                            Image(systemName: VoiceInkAudioImportPresentation.startButtonSystemImageName)
                        }
                        .accessibilityLabel(VoiceInkAudioImportPresentation.startButtonTitle)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        manager.clearFinishedAndPendingItems()
                    } label: {
                        Label(
                            VoiceInkAudioImportPresentation.clearButtonTitle,
                            systemImage: VoiceInkAudioImportPresentation.clearButtonSystemImageName
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
                allowedContentTypes: VoiceInkSupportedMedia.contentTypes,
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
    private func queueRow(_ item: VoiceInkIOSAudioImportQueueItem) -> some View {
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
                    Image(systemName: VoiceInkAudioFileQueuePresentation.removeButtonSystemImageName)
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
                    .accessibilityLabel("Share transcript")
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("View transcript")
                }
            case .failed:
                Button {
                    manager.retryItem(id: item.id)
                    manager.startProcessing(modelContext: modelContext)
                } label: {
                    Image(systemName: VoiceInkAudioFileQueuePresentation.retryButtonSystemImageName)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Retry")
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: VoiceInkAudioFileQueueStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: VoiceInkAudioFileQueuePresentation.pendingStatusSystemImageName)
                .foregroundStyle(.secondary)
        case .processing:
            Image(systemName: "waveform")
                .foregroundStyle(.blue)
        case .completed:
            Image(systemName: VoiceInkAudioFileQueuePresentation.completedStatusSystemImageName)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: VoiceInkAudioFileQueuePresentation.failedStatusSystemImageName)
                .foregroundStyle(.red)
        }
    }

    private func statusText(_ status: VoiceInkAudioFileQueueStatus) -> String {
        switch status {
        case .pending:
            return VoiceInkAudioFileQueuePresentation.pendingStatusText
        case .processing(let phase):
            return phase.displayText
        case .completed:
            return "Completed"
        case .failed(let message):
            return message
        }
    }

    private func statusColor(_ status: VoiceInkAudioFileQueueStatus) -> Color {
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
        VoiceInkTranscriptPresentation.preferredText(
            rawText: note.text,
            enhancedText: note.enhancedText
        ) ?? note.text
    }
}
