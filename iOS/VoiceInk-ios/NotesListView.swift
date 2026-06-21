import SwiftUI
import SwiftData
import VoiceInkCore

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Transcription.timestamp, order: .reverse)]) private var notes: [Transcription]

    @State private var searchText: String = ""
    @State private var recordingStartAlert: VoiceInkRecordingAlertPresentation?
    @EnvironmentObject private var recordingManager: RecordingManager
    @StateObject private var settings = AppSettings.shared

    var filteredNotes: [Transcription] {
        notes.filter { note in
            VoiceInkTranscriptPresentation.matchesSearch(
                rawText: note.text,
                enhancedText: note.enhancedText,
                query: searchText
            )
        }
    }

    init() {}

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(VoiceInkAppIdentity.displayName)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: VoiceInkNoteListPresentation.settingsSystemImageName)
                        }
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
                .safeAreaInset(edge: .bottom) { 
                    unifiedRecordingComponent
                }
                .sheet(
                    isPresented: Binding(
                        get: { recordingManager.isRecordingSheetPresented },
                        set: { recordingManager.setRecordingSheetPresented($0) }
                    )
                ) {
                    RecordingSheetView(
                        recordingManager: recordingManager,
                        settings: settings,
                        onCancel: { recordingManager.cancelRecording() },
                        onStop: { recordingManager.stopRecording(modelContext: modelContext) }
                    )
                    .presentationDetents([.height(220)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(16)
                    .interactiveDismissDisabled(true)
                }
                .alert(item: $recordingManager.activeRecordingAlert) { alertType in
                    alert(for: alertType)
                }
                .alert(item: $recordingStartAlert) { alertType in
                    alert(for: alertType)
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: VoiceInkAppIdentity.iOSStopRecordingFromKeyboardNotificationName
                )) { _ in
                    if recordingManager.isRecording {
                        recordingManager.stopRecording(modelContext: modelContext)
                    }
                }
        }
    }

    private var content: some View {
        Group {
            if filteredNotes.isEmpty {
                emptyState
            } else {
                List {
                    Section(header: sectionHeader) {
                        ForEach(filteredNotes) { note in
                            NavigationLink(destination: NoteDetailView(note: note)) {
                                NoteRowView(note: note)
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private var sectionHeader: some View {
        let summaryPresentation = VoiceInkNoteListSummaryPresentation.make(from: filteredNotes)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(VoiceInkNoteListPresentation.sectionTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(summaryPresentation.dashboardText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let performanceSummaryText = summaryPresentation.fastestModelText {
                    Text(performanceSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(summaryPresentation.countText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        let presentation = VoiceInkHistoryPresentation.iOSNotesEmptyState

        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 88, height: 88)
                Image(systemName: presentation.systemImageName)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(presentation.title)
                .font(.title3.weight(.semibold))
            if let message = presentation.message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var unifiedRecordingComponent: some View {
        Button(action: {
            if let alert = VoiceInkRecordingAlertPresentation.noModesAvailableIfNeeded(
                modeCount: settings.modes.count
            ) {
                recordingStartAlert = alert
            } else {
                recordingManager.startRecordingFlow()
            }
        }) {
            Label(
                VoiceInkNoteListPresentation.startRecordingButtonTitle,
                systemImage: VoiceInkNoteListPresentation.startRecordingSystemImageName
            )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.red)
        .controlSize(.large)
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    // MARK: - Helper Functions
    private func alert(for presentation: VoiceInkRecordingAlertPresentation) -> Alert {
        switch presentation.action {
        case .openSettings:
            return Alert(
                title: Text(presentation.title),
                message: Text(presentation.message),
                primaryButton: .default(
                    Text(presentation.primaryButtonTitle),
                    action: recordingManager.openSettings
                ),
                secondaryButton: .cancel(Text(
                    presentation.secondaryButtonTitle ?? VoiceInkRecordingSheetPresentation.iOS.cancelButtonTitle
                ))
            )
        case .dismiss:
            return Alert(
                title: Text(presentation.title),
                message: Text(presentation.message),
                dismissButton: .default(Text(presentation.primaryButtonTitle))
            )
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for note in VoiceInkTranscriptPresentation.deletionTargets(atOffsets: offsets, from: filteredNotes) {
                do {
                    try note.deleteExistingAudioFile()
                } catch {
                    print(VoiceInkStoredAudioFile.deletionErrorMessage(for: error))
                }
                modelContext.delete(note)
            }
        }
    }
}

#Preview {
    NotesListView()
        .modelContainer(for: [Transcription.self])
        .environmentObject(RecordingManager())
}
