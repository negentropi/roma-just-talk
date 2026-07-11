import SwiftUI
import SwiftData
import OSLog
import VoiceInkCore

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\Transcription.timestamp, order: .reverse)]) private var notes: [Transcription]

    @State private var searchText: String = ""
    @EnvironmentObject private var recordingManager: RecordingManager
    @StateObject private var settings = AppSettings.shared
    @StateObject private var transcriptionTasks = IOSTranscriptionTaskCoordinator.shared
    @StateObject private var audioImport = IOSAudioImportManager.shared
    @State private var editMode: EditMode = .inactive
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirmation = false

    private var noteListSnapshot: VoiceInkNoteListSnapshot<Transcription> {
        VoiceInkNoteListSnapshot.make(
            from: notes,
            query: searchText,
            rawText: \.text,
            enhancedText: \.enhancedText
        )
    }

    private var selectedNotes: [Transcription] {
        notes.filter { selectedNoteIDs.contains($0.id) }
    }

    private var areAllDisplayedNotesSelected: Bool {
        VoiceInkHistorySelectionPolicy.areAllDisplayedItemsSelected(
            displayedItems: noteListSnapshot.displayedItems.map(\.id),
            selectedItems: selectedNoteIDs
        )
    }

    private var content: some View {
        let snapshot = noteListSnapshot

        return Group {
            if snapshot.shouldShowEmptyState {
                emptyState(snapshot.emptyStatePresentation)
            } else {
                List(selection: $selectedNoteIDs) {
                    Section(header: sectionHeader(snapshot.summaryPresentation)) {
                        ForEach(snapshot.displayedItems) { note in
                            NavigationLink(destination: NoteDetailView(note: note)) {
                                NoteRowView(note: note)
                            }
                            .tag(note.id)
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
                .environment(\.editMode, $editMode)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if !notes.isEmpty {
                            EditButton()
                        }
                    }
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
                    if editMode.isEditing {
                        historySelectionBar
                    } else {
                        unifiedRecordingComponent
                    }
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
                    .presentationDetents([.height(360)])
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
                .alert(
                    VoiceInkHistoryPresentation.deleteConfirmationTitle,
                    isPresented: $showBulkDeleteConfirmation
                ) {
                    Button(
                        VoiceInkHistoryPresentation.deleteConfirmationPrimaryButtonTitle,
                        role: .destructive,
                        action: deleteSelectedNotes
                    )
                    Button(
                        VoiceInkHistoryPresentation.deleteConfirmationCancelButtonTitle,
                        role: .cancel
                    ) {}
                } message: {
                    Text(VoiceInkHistoryPresentation.selectedCountText(selectedNoteIDs.count))
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
                .onReceive(NotificationCenter.default.publisher(
                    for: IOSRecordingAppIntentRequestStore.requestNotification
                )) { _ in
                    handleRecordingAppIntentRequest()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        handleRecordingAppIntentRequest()
                    }
                }
                .onAppear {
                    handleRecordingAppIntentRequest()
                    transcriptionTasks.recoverInterruptedTranscriptions(
                        notes,
                        persist: { try? modelContext.save() }
                    )
                }
                .onChange(of: editMode) { _, newValue in
                    if !newValue.isEditing {
                        selectedNoteIDs.removeAll()
                    }
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

    private var historySelectionBar: some View {
        HStack(spacing: 18) {
            Button(
                areAllDisplayedNotesSelected
                    ? VoiceInkHistoryPresentation.deselectAllButtonTitle
                    : VoiceInkHistoryPresentation.selectAllButtonTitle
            ) {
                if areAllDisplayedNotesSelected {
                    selectedNoteIDs.removeAll()
                } else {
                    selectedNoteIDs = VoiceInkHistorySelectionPolicy.selectingAll(
                        displayedItems: noteListSnapshot.displayedItems.map(\.id),
                        allItems: notes.map(\.id),
                        id: { $0 }
                    )
                }
            }

            Spacer()

            Text(VoiceInkHistoryPresentation.selectedCountText(selectedNoteIDs.count))
                .font(.callout)
                .foregroundStyle(.secondary)

            ShareLink(
                item: VoiceInkIOSCSVExport(transcriptions: selectedNotes),
                preview: SharePreview(VoiceInkTranscriptionCSVExporter.defaultFilename)
            ) {
                Image(systemName: VoiceInkHistoryPresentation.exportAction.systemImageName)
            }
            .disabled(selectedNoteIDs.isEmpty)
            .accessibilityLabel(VoiceInkHistoryPresentation.exportAction.title)

            Button(role: .destructive) {
                showBulkDeleteConfirmation = true
            } label: {
                Image(systemName: VoiceInkHistoryPresentation.deleteAction.systemImageName)
            }
            .disabled(selectedNoteIDs.isEmpty)
            .accessibilityLabel(VoiceInkHistoryPresentation.deleteAction.title)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func handleRecordingAppIntentRequest() {
        guard let request = IOSRecordingAppIntentRequestStore.consume() else { return }

        switch IOSRecordingAppIntentPolicy.runtimeAction(
            for: request,
            recordingState: recordingManager.flowState.recordingState
        ) {
        case .start:
            recordingManager.startRecordingFlow()
        case .stop:
            recordingManager.stopRecording(modelContext: modelContext)
        case .cancel:
            recordingManager.cancelRecording()
        case .ignore:
            return
        }
    }

    // MARK: - Helper Functions
    private func alert(for presentation: VoiceInkRecordingAlertPresentation) -> Alert {
        presentation.iOSAlert(openSettings: recordingManager.openSettings)
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            let deletionPlan = noteListSnapshot.offsetDeletionPlan(
                atOffsets: offsets,
                id: \.id
            )

            deletionPlan.applyRuntimeState { note in
                delete(note)
            }
        }
    }

    private func deleteSelectedNotes() {
        withAnimation {
            let deletionPlan = VoiceInkHistoryDeletionPolicy.selectedItemsDeletionPlan(
                selectedItems: selectedNoteIDs,
                id: { $0 }
            )
            let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })

            deletionPlan.applyRuntimeState { id in
                guard let note = notesByID[id] else { return }
                delete(note)
            }
            selectedNoteIDs = deletionPlan.remainingSelection
            editMode = .inactive
            try? modelContext.save()
        }
    }

    private func delete(_ note: Transcription) {
        transcriptionTasks.cancel(noteID: note.id)
        note.deleteExistingAudioFileReportingFailure { message in
            VoiceInkIOSLogger.notes.error("\(message, privacy: .public)")
        }
        modelContext.delete(note)
    }
}

#Preview {
    NotesListView()
        .modelContainer(for: [Transcription.self])
        .environmentObject(RecordingManager())
}
