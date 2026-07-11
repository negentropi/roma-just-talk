import SwiftData
import SwiftUI
import VoiceInkCore

struct IOSHistoryCleanupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Transcription.timestamp, order: .reverse)]) private var notes: [Transcription]
    @StateObject private var manager = IOSHistoryCleanupManager.shared
    @StateObject private var transcriptionTasks = IOSTranscriptionTaskCoordinator.shared
    @AppStorage(VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
    private var isTranscriptCleanupEnabled = false
    @AppStorage(VoiceInkUserDefaultsKey.transcriptionRetentionMinutes)
    private var transcriptRetentionMinutes = VoiceInkPreferenceDefault.transcriptionRetentionMinutes
    @AppStorage(VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
    private var isAudioCleanupEnabled = false
    @AppStorage(VoiceInkUserDefaultsKey.audioRetentionPeriodDays)
    private var audioRetentionDays = VoiceInkPreferenceDefault.audioRetentionDays
    @State private var showConfirmation = false
    @State private var showResult = false

    private let presentation = VoiceInkMacOSCleanupSettingsPresentation.macOS

    var body: some View {
        Form {
            Section {
                Toggle(presentation.transcriptToggleTitle, isOn: $isTranscriptCleanupEnabled)
                if isTranscriptCleanupEnabled {
                    Picker(
                        presentation.transcriptRetentionPickerTitle,
                        selection: $transcriptRetentionMinutes
                    ) {
                        ForEach(presentation.transcriptRetentionOptions) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                }
            } footer: {
                Text(presentation.transcriptHelpText)
            }

            Section {
                Toggle(presentation.audioToggleTitle, isOn: $isAudioCleanupEnabled)
                if isAudioCleanupEnabled {
                    Picker(
                        presentation.audioRetentionPickerTitle,
                        selection: $audioRetentionDays
                    ) {
                        ForEach(presentation.audioRetentionOptions) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                }
            } footer: {
                Text(presentation.audioHelpText)
            }

            Section {
                LabeledContent("Transcripts", value: "\(manager.preview.transcriptCount)")
                LabeledContent("Audio Files", value: "\(manager.preview.audioFileCount)")
                LabeledContent(
                    "Audio Size",
                    value: presentation.audioCleanupFileSizeText(manager.preview.audioByteCount)
                )
                LabeledContent("Orphan Files", value: "\(manager.preview.orphanFileCount)")

                Button(presentation.manualCleanupButtonTitle) {
                    refreshPreview()
                    showConfirmation = true
                }
                .disabled(
                    manager.isWorking
                        || (!isTranscriptCleanupEnabled && !isAudioCleanupEnabled)
                )
            } header: {
                Text("Cleanup Preview")
            }
        }
        .navigationTitle("History Retention")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshPreview)
        .onChange(of: isTranscriptCleanupEnabled) { _, _ in refreshPreview() }
        .onChange(of: transcriptRetentionMinutes) { _, _ in refreshPreview() }
        .onChange(of: isAudioCleanupEnabled) { _, _ in refreshPreview() }
        .onChange(of: audioRetentionDays) { _, _ in refreshPreview() }
        .confirmationDialog(
            "Run History Cleanup?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button(presentation.manualCleanupButtonTitle, role: .destructive) {
                manager.runManualCleanup(
                    notes: notes,
                    modelContext: modelContext,
                    activeNoteIDs: transcriptionTasks.activeNoteIDs
                )
                showResult = true
            }
            Button(presentation.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert(presentation.cleanupCompleteAlertTitle, isPresented: $showResult) {
            Button(presentation.okButtonTitle, role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    private var confirmationMessage: String {
        let preview = manager.preview
        return "Delete \(preview.transcriptCount) transcripts, \(preview.audioFileCount) retained audio files, and \(preview.orphanFileCount) orphan files?"
    }

    private var resultMessage: String {
        guard let result = manager.lastResult else {
            return presentation.transcriptCleanupCompleteMessage
        }
        return "Deleted \(result.deletedTranscriptCount) transcripts, \(result.deletedAudioFileCount) audio files, and \(result.deletedOrphanFileCount) orphan files. Failed: \(result.errorCount)."
    }

    private func refreshPreview() {
        manager.refreshPreview(
            notes: notes,
            activeNoteIDs: transcriptionTasks.activeNoteIDs
        )
    }
}
