import SwiftUI
import SwiftData
import VoiceInkCore

struct TranscriptionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedTranscription: Transcription?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    @State private var isViewCurrentlyVisible = false
    @State private var isAnalysisPanelPresented = false
    @State private var isLeftSidebarVisible = true
    @State private var isRightSidebarVisible = true
    @State private var leftSidebarWidth: CGFloat = 300
    @State private var rightSidebarWidth: CGFloat = 350
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?

    private let exportService = VoiceInkCSVExportService()
    private let pageSize = 20
    
    @Query(TranscriptionHistoryQuery.latestIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]

    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Transcription> {
        TranscriptionHistoryQuery.cursorDescriptor(
            after: timestamp,
            searchText: searchText,
            pageSize: pageSize
        )
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if isLeftSidebarVisible {
                leftSidebarView
                    .frame(width: leftSidebarWidth)
                    .transition(.move(edge: .leading))

                Divider()
            }

            centerPaneView
                .frame(maxWidth: .infinity)

            if isRightSidebarVisible {
                Divider()

                rightSidebarView
                    .frame(width: rightSidebarWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { withAnimation { isLeftSidebarVisible.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                Button(action: { withAnimation { isRightSidebarVisible.toggle() } }) {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .alert(VoiceInkHistoryPresentation.deleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button(VoiceInkHistoryPresentation.deleteConfirmationPrimaryButtonTitle, role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button(VoiceInkHistoryPresentation.deleteConfirmationCancelButtonTitle, role: .cancel) {}
        } message: {
            Text(VoiceInkTranscriptPresentation.deleteConfirmationMessage(selectedCount: selectedTranscriptions.count))
        }
        .overlay {
            Color.black.opacity(isAnalysisPanelPresented ? 0.1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isAnalysisPanelPresented)
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.3)) {
                        isAnalysisPanelPresented = false
                    }
                }
                .animation(.smooth(duration: 0.3), value: isAnalysisPanelPresented)
        }
        .overlay(alignment: .trailing) {
            if isAnalysisPanelPresented {
                PerformanceAnalysisPanelView(
                    transcriptions: Array(selectedTranscriptions),
                    onClose: {
                        withAnimation(.smooth(duration: 0.3)) {
                            isAnalysisPanelPresented = false
                        }
                    }
                )
                .id(selectedTranscriptions.count)
                .frame(width: 400)
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(width: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, x: -2, y: 0)
                .ignoresSafeArea()
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.3), value: isAnalysisPanelPresented)
        .onAppear {
            isViewCurrentlyVisible = true
            Task {
                await loadInitialContent()
            }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
        }
        .onChange(of: searchText) { _, _ in
            Task {
                await resetPagination()
                await loadInitialContent()
            }
        }
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    await resetPagination()
                    await loadInitialContent()
                }
            }
        }
    }

    private var leftSidebarView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField(VoiceInkHistoryPresentation.macOSHistorySearchPrompt, text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
            )
            .padding(12)

            Divider()

            ZStack(alignment: .bottom) {
                if displayedTranscriptions.isEmpty && !isLoading {
                    let presentation = VoiceInkHistoryPresentation.macOSHistoryListEmptyState

                    VStack(spacing: 12) {
                        Image(systemName: presentation.systemImageName)
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(presentation.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(displayedTranscriptions) { transcription in
                                TranscriptionListItem(
                                    transcription: transcription,
                                    isSelected: selectedTranscription == transcription,
                                    isChecked: selectedTranscriptions.contains(transcription),
                                    onSelect: { selectedTranscription = transcription },
                                    onToggleCheck: { toggleSelection(transcription) }
                                )
                            }

                            if hasMoreContent {
                                Button(action: {
                                    Task { await loadMoreContent() }
                                }) {
                                    HStack(spacing: 8) {
                                        if isLoading {
                                            ProgressView().controlSize(.small)
                                        }
                                        Text(VoiceInkHistoryPresentation.loadingOrLoadMoreText(isLoading: isLoading))
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoading)
                            }
                        }
                        .padding(8)
                        .padding(.bottom, 50)
                    }
                }

                if !displayedTranscriptions.isEmpty {
                    selectionToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var centerPaneView: some View {
        Group {
            if let transcription = selectedTranscription {
                TranscriptionDetailView(transcription: transcription, onInfoTap: {
                    withAnimation { isRightSidebarVisible.toggle() }
                })
                    .id(transcription.id)
            } else {
                let presentation = VoiceInkHistoryPresentation.macOSNoSelectionEmptyState

                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(minHeight: 40)

                        VStack(spacing: 12) {
                            Image(systemName: presentation.systemImageName)
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text(presentation.title)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
                            if let message = presentation.message {
                                Text(message)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }

                        HistoryShortcutTipView()
                            .padding(.horizontal, 24)

                        Spacer()
                            .frame(minHeight: 40)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 600)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }

    private var rightSidebarView: some View {
        Group {
            if let transcription = selectedTranscription {
                TranscriptionInfoPanel(transcription: transcription)
                    .id(transcription.id)
            } else {
                let presentation = VoiceInkHistoryPresentation.macOSNoMetadataEmptyState

                VStack(spacing: 12) {
                    Image(systemName: presentation.systemImageName)
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(presentation.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }

    private var allSelected: Bool {
        VoiceInkHistorySelectionPolicy.areAllDisplayedItemsSelected(
            displayedItems: displayedTranscriptions,
            selectedItems: selectedTranscriptions
        )
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            if allSelected {
                Button(VoiceInkHistoryPresentation.deselectAllButtonTitle) {
                    selectedTranscriptions.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            } else {
                Button(VoiceInkHistoryPresentation.selectAllButtonTitle) {
                    Task { await selectAllTranscriptions() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            }

            if !selectedTranscriptions.isEmpty {
                Divider()
                    .frame(height: 16)

                Button(action: {
                    withAnimation(.smooth(duration: 0.3)) { isAnalysisPanelPresented = true }
                }) {
                    Image(systemName: VoiceInkHistoryPresentation.analyzeAction.systemImageName)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(VoiceInkHistoryPresentation.analyzeAction.title)

                Button(action: {
                    exportService.exportTranscriptionsToCSV(transcriptions: Array(selectedTranscriptions))
                }) {
                    Image(systemName: VoiceInkHistoryPresentation.exportAction.systemImageName)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(VoiceInkHistoryPresentation.exportAction.title)

                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: VoiceInkHistoryPresentation.deleteAction.systemImageName)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(VoiceInkHistoryPresentation.deleteAction.title)
            }

            Spacer()

            if !selectedTranscriptions.isEmpty {
                Text(VoiceInkHistoryPresentation.selectedCountText(selectedTranscriptions.count))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.windowBackgroundColor)
                .shadow(color: Color.black.opacity(0.15), radius: 3, y: -2)
        )
    }
    
    @MainActor
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            lastTimestamp = nil
            let items = try modelContext.fetch(cursorQueryDescriptor())
            applyPaginationPlan(
                VoiceInkHistoryPaginationPolicy.initialPage(
                    items,
                    pageSize: pageSize,
                    timestamp: \.timestamp
                )
            )
        } catch {
            print("Error loading transcriptions: \(error)")
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard let loadMoreTimestamp = VoiceInkHistoryPaginationPolicy.loadMoreCursor(
            isLoading: isLoading,
            hasMoreContent: hasMoreContent,
            lastTimestamp: lastTimestamp
        ) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newItems = try modelContext.fetch(cursorQueryDescriptor(after: loadMoreTimestamp))
            applyPaginationPlan(
                VoiceInkHistoryPaginationPolicy.appendingPage(
                    currentItems: displayedTranscriptions,
                    newItems: newItems,
                    pageSize: pageSize,
                    timestamp: \.timestamp
                )
            )
        } catch {
            print("Error loading more transcriptions: \(error)")
        }
    }
    
    @MainActor
    private func resetPagination() {
        applyPaginationPlan(VoiceInkHistoryPaginationPolicy.reset())
    }

    private func applyPaginationPlan(_ plan: VoiceInkHistoryPaginationPlan<Transcription>) {
        displayedTranscriptions = plan.displayedItems
        lastTimestamp = plan.lastTimestamp
        hasMoreContent = plan.hasMoreContent
        isLoading = plan.isLoading
    }

    private func deleteTranscriptionRecord(_ transcription: Transcription) {
        do {
            try transcription.deleteExistingAudioFile()
        } catch {
            print(VoiceInkStoredAudioFile.deletionErrorMessage(for: error))
        }

        modelContext.delete(transcription)
    }

    private func saveAndReload() async {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            await loadInitialContent()
        } catch {
            print("Error saving deletion: \(error.localizedDescription)")
            await loadInitialContent()
        }
    }

    private func deleteSelectedTranscriptions() {
        let deletionPlan = VoiceInkHistoryDeletionPolicy.selectedItemsDeletionPlan(
            selectedItems: selectedTranscriptions,
            id: \.id
        )

        for transcription in deletionPlan.targets {
            deleteTranscriptionRecord(transcription)
        }

        if deletionPlan.deletesItem(selectedTranscription) {
            selectedTranscription = nil
        }
        selectedTranscriptions = deletionPlan.remainingSelection

        Task {
            await saveAndReload()
        }
    }
    
    private func toggleSelection(_ transcription: Transcription) {
        selectedTranscriptions = VoiceInkHistorySelectionPolicy.toggling(
            transcription,
            in: selectedTranscriptions
        )
    }

    private func selectAllTranscriptions() async {
        do {
            let allDescriptor = TranscriptionHistoryQuery.selectionDescriptor(searchText: searchText)
            let allTranscriptions = try modelContext.fetch(allDescriptor)

            await MainActor.run {
                selectedTranscriptions = VoiceInkHistorySelectionPolicy.selectingAll(
                    displayedItems: displayedTranscriptions,
                    allItems: allTranscriptions,
                    id: \.id
                )
            }
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }
}
