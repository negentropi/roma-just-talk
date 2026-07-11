import SwiftUI
import SwiftData
import OSLog
import VoiceInkCore

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Transcription.timestamp, order: .reverse)]) private var notes: [Transcription]

    @State private var searchText: String = ""
    @EnvironmentObject private var recordingManager: RecordingManager
    @StateObject private var settings = AppSettings.shared
    @StateObject private var transcriptionTasks = IOSTranscriptionTaskCoordinator.shared
    @StateObject private var audioImport = IOSAudioImportManager.shared

    private var noteListSnapshot: VoiceInkNoteListSnapshot<Transcription> {
        VoiceInkNoteListSnapshot.make(
            from: notes,
            query: searchText,
            rawText: \.text,
            enhancedText: \.enhancedText
        )
    }

    private var content: some View {
        let snapshot = noteListSnapshot

        return Group {
            if snapshot.shouldShowEmptyState {
                emptyState(snapshot.emptyStatePresentation)
            } else {
                List {
                    Section(header: sectionHeader(snapshot.summaryPresentation)) {
                        ForEach(snapshot.displayedItems) { note in
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

    init() {}

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(VoiceInkAppIdentity.displayName)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            audioImport.isPresented = true
                        } label: {
                            Image(systemName: "waveform.badge.plus")
                        }
                        .accessibilityLabel("Import audio files")

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
                        get: { recordingManager.flowState.isRecordingSheetPresented },
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
                .sheet(isPresented: $audioImport.isPresented) {
                    AudioImportView()
                }
                .alert(item: $recordingManager.activeRecordingAlert) { alertType in
                    alert(for: alertType)
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: VoiceInkAppIdentity.iOSStopRecordingFromKeyboardNotificationName
                )) { _ in
                    VoiceInkKeyboardStopRecordingRequestPolicy.plan(
                        recordingState: recordingManager.flowState.recordingState
                    ).applyRuntimeState {
                        recordingManager.stopRecording(modelContext: modelContext)
                    }
                }
                .onAppear {
                    transcriptionTasks.recoverInterruptedTranscriptions(
                        notes,
                        persist: { try? modelContext.save() }
                    )
                }
        }
    }

    private func sectionHeader(_ summaryPresentation: VoiceInkNoteListSummaryPresentation) -> some View {
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

    private func emptyState(_ presentation: VoiceInkHistoryEmptyStatePresentation) -> some View {
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
            recordingManager.startRecordingFlow()
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
        let primaryAction = presentation.runtimeAction(openSettings: recordingManager.openSettings)
        if let secondaryButtonTitle = presentation.secondaryButtonTitle {
            return Alert(
                title: Text(presentation.title),
                message: Text(presentation.message),
                primaryButton: .default(
                    Text(presentation.primaryButtonTitle),
                    action: primaryAction
                ),
                secondaryButton: .cancel(Text(secondaryButtonTitle))
            )
        }

        return Alert(
            title: Text(presentation.title),
            message: Text(presentation.message),
            dismissButton: .default(
                Text(presentation.primaryButtonTitle),
                action: primaryAction
            )
        )
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            let deletionPlan = noteListSnapshot.offsetDeletionPlan(
                atOffsets: offsets,
                id: \.id
            )

            deletionPlan.applyRuntimeState { note in
                transcriptionTasks.cancel(noteID: note.id)
                note.deleteExistingAudioFileReportingFailure { message in
                    VoiceInkIOSLogger.notes.error("\(message, privacy: .public)")
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
