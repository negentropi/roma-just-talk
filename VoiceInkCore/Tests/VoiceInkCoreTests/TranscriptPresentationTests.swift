import Foundation
import VoiceInkCore

final class TranscriptPresentationTests: XCTestCase {
    func testHistoryEmptyStatePresentationPreservesIOSNotesCopy() {
        XCTAssertEqual(
            VoiceInkHistoryPresentation.iOSNotesEmptyState,
            VoiceInkHistoryEmptyStatePresentation(
                systemImageName: "waveform",
                title: "No notes yet",
                message: "Tap Start Recording to capture your first note."
            )
        )
    }

    func testHistoryEmptyStatePresentationPreservesMacOSHistoryCopy() {
        XCTAssertEqual(
            VoiceInkHistoryPresentation.macOSHistoryListEmptyState,
            VoiceInkHistoryEmptyStatePresentation(
                systemImageName: "doc.text.magnifyingglass",
                title: "No transcriptions"
            )
        )
        XCTAssertEqual(
            VoiceInkHistoryPresentation.macOSNoSelectionEmptyState,
            VoiceInkHistoryEmptyStatePresentation(
                systemImageName: "doc.text",
                title: "No Selection",
                message: "Select a transcription to view details"
            )
        )
        XCTAssertEqual(
            VoiceInkHistoryPresentation.macOSNoMetadataEmptyState,
            VoiceInkHistoryEmptyStatePresentation(
                systemImageName: "info.circle",
                title: "No Metadata"
            )
        )
    }

    func testInlineHistoryEmptyStatePresentationPreservesSearchBranching() {
        XCTAssertEqual(
            VoiceInkHistoryPresentation.macOSInlineHistoryEmptyState(searchText: ""),
            VoiceInkHistoryEmptyStatePresentation(
                systemImageName: "doc.text.magnifyingglass",
                title: "No transcriptions yet",
                message: "Your transcription history will appear here"
            )
        )
        XCTAssertEqual(
            VoiceInkHistoryPresentation.macOSInlineHistoryEmptyState(searchText: "invoice"),
            VoiceInkHistoryEmptyStatePresentation(
                systemImageName: "doc.text.magnifyingglass",
                title: "No results found",
                message: "Try a different search term"
            )
        )
    }

    func testHistoryControlPresentationPreservesMacOSSearchAndPagingCopy() {
        XCTAssertEqual(VoiceInkHistoryPresentation.macOSHistorySearchPrompt, "Search transcriptions")
        XCTAssertEqual(VoiceInkHistoryPresentation.macOSInlineHistorySearchPrompt, "Search transcriptions...")
        XCTAssertEqual(VoiceInkHistoryPresentation.loadingOrLoadMoreText(isLoading: true), "Loading...")
        XCTAssertEqual(VoiceInkHistoryPresentation.loadingOrLoadMoreText(isLoading: false), "Load More")
    }

    func testHistorySelectionPresentationPreservesMacOSCopyAndActions() {
        XCTAssertEqual(VoiceInkHistoryPresentation.selectAllButtonTitle, "Select All")
        XCTAssertEqual(VoiceInkHistoryPresentation.deselectAllButtonTitle, "Deselect All")
        XCTAssertEqual(VoiceInkHistoryPresentation.selectedCountText(3), "3 selected")
        XCTAssertEqual(
            VoiceInkHistoryPresentation.analyzeAction,
            VoiceInkHistoryActionPresentation(title: "Analyze", systemImageName: "chart.bar.xaxis")
        )
        XCTAssertEqual(
            VoiceInkHistoryPresentation.exportAction,
            VoiceInkHistoryActionPresentation(title: "Export", systemImageName: "square.and.arrow.up")
        )
        XCTAssertEqual(
            VoiceInkHistoryPresentation.deleteAction,
            VoiceInkHistoryActionPresentation(title: "Delete", systemImageName: "trash")
        )
    }

    func testHistoryShortcutTipPresentationPreservesMacOSCopyAndIcon() {
        XCTAssertEqual(VoiceInkHistoryPresentation.macOSShortcutTip.title, "Quick Access")
        XCTAssertEqual(
            VoiceInkHistoryPresentation.macOSShortcutTip.subtitle,
            "Open history from anywhere with a global shortcut"
        )
        XCTAssertEqual(VoiceInkHistoryPresentation.macOSShortcutTip.shortcutLabel, "Open History Window")
        XCTAssertEqual(VoiceInkHistoryPresentation.macOSShortcutTip.systemImageName, "command.circle")
    }

    func testHistoryPaginationPolicyBuildsInitialPageState() {
        let first = HistoryItem(id: 1, timestamp: Date(timeIntervalSince1970: 200))
        let second = HistoryItem(id: 2, timestamp: Date(timeIntervalSince1970: 100))

        let plan = VoiceInkHistoryPaginationPolicy.initialPage(
            [first, second],
            pageSize: 2,
            timestamp: \.timestamp
        )

        XCTAssertEqual(plan.displayedItems, [first, second])
        XCTAssertEqual(plan.lastTimestamp, second.timestamp)
        XCTAssertTrue(plan.hasMoreContent)
        XCTAssertFalse(plan.isLoading)
    }

    func testHistoryPaginationPolicyAppendsPageAndPreservesEmptyPageBehavior() {
        let current = HistoryItem(id: 1, timestamp: Date(timeIntervalSince1970: 300))
        let next = HistoryItem(id: 2, timestamp: Date(timeIntervalSince1970: 200))

        let appended = VoiceInkHistoryPaginationPolicy.appendingPage(
            currentItems: [current],
            newItems: [next],
            pageSize: 2,
            timestamp: \.timestamp
        )

        XCTAssertEqual(appended.displayedItems, [current, next])
        XCTAssertEqual(appended.lastTimestamp, next.timestamp)
        XCTAssertFalse(appended.hasMoreContent)
        XCTAssertFalse(appended.isLoading)

        let empty = VoiceInkHistoryPaginationPolicy.appendingPage(
            currentItems: [current],
            newItems: [],
            pageSize: 2,
            timestamp: \.timestamp
        )

        XCTAssertEqual(empty.displayedItems, [current])
        XCTAssertNil(empty.lastTimestamp)
        XCTAssertFalse(empty.hasMoreContent)
        XCTAssertFalse(empty.isLoading)
    }

    func testHistoryPaginationPolicyResetsAndGatesLoadMoreCursor() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let reset: VoiceInkHistoryPaginationPlan<HistoryItem> = VoiceInkHistoryPaginationPolicy.reset()

        XCTAssertTrue(reset.displayedItems.isEmpty)
        XCTAssertNil(reset.lastTimestamp)
        XCTAssertTrue(reset.hasMoreContent)
        XCTAssertFalse(reset.isLoading)
        XCTAssertEqual(
            VoiceInkHistoryPaginationPolicy.loadMoreCursor(
                isLoading: false,
                hasMoreContent: true,
                lastTimestamp: timestamp
            ),
            timestamp
        )
        XCTAssertNil(VoiceInkHistoryPaginationPolicy.loadMoreCursor(
            isLoading: true,
            hasMoreContent: true,
            lastTimestamp: timestamp
        ))
        XCTAssertNil(VoiceInkHistoryPaginationPolicy.loadMoreCursor(
            isLoading: false,
            hasMoreContent: false,
            lastTimestamp: timestamp
        ))
        XCTAssertNil(VoiceInkHistoryPaginationPolicy.loadMoreCursor(
            isLoading: false,
            hasMoreContent: true,
            lastTimestamp: nil
        ))
    }

    func testHistorySelectionPolicyOwnsToggleAndDisplayedSelectionState() {
        let first = HistorySelectionItem(id: 1, label: "first")
        let second = HistorySelectionItem(id: 2, label: "second")

        XCTAssertFalse(VoiceInkHistorySelectionPolicy.areAllDisplayedItemsSelected(
            displayedItems: [first, second],
            selectedItems: [first]
        ))
        XCTAssertTrue(VoiceInkHistorySelectionPolicy.areAllDisplayedItemsSelected(
            displayedItems: [first, second],
            selectedItems: [first, second]
        ))
        XCTAssertFalse(VoiceInkHistorySelectionPolicy.areAllDisplayedItemsSelected(
            displayedItems: [HistorySelectionItem](),
            selectedItems: Set<HistorySelectionItem>()
        ))
        XCTAssertEqual(
            VoiceInkHistorySelectionPolicy.toggling(second, in: [first]),
            [first, second]
        )
        XCTAssertEqual(
            VoiceInkHistorySelectionPolicy.toggling(first, in: [first, second]),
            [second]
        )
    }

    func testHistorySelectionPolicySelectsAllWhilePreservingDisplayedInstances() {
        let visible = HistorySelectionItem(id: 1, label: "visible")
        let fetchedDuplicate = HistorySelectionItem(id: 1, label: "fetched duplicate")
        let hidden = HistorySelectionItem(id: 2, label: "hidden")

        let selection = VoiceInkHistorySelectionPolicy.selectingAll(
            displayedItems: [visible],
            allItems: [fetchedDuplicate, hidden],
            id: \.id
        )

        XCTAssertEqual(selection, Set([visible, hidden]))
        XCTAssertFalse(selection.contains(fetchedDuplicate))
    }

    func testHistoryDeletionPolicyPlansSelectedTargetsAndClearsSelection() {
        let first = HistorySelectionItem(id: 1, label: "first")
        let second = HistorySelectionItem(id: 2, label: "second")

        let plan = VoiceInkHistoryDeletionPolicy.selectedItemsDeletionPlan(
            selectedItems: Set([first, second]),
            id: \.id
        )

        var deletedItems: [HistorySelectionItem] = []
        plan.applyRuntimeState { item in
            deletedItems.append(item)
        }

        XCTAssertEqual(Set(deletedItems), Set([first, second]))
        XCTAssertTrue(plan.remainingSelection.isEmpty)
        XCTAssertTrue(plan.deletesID(first.id))
        XCTAssertTrue(plan.deletesID(second.id))
    }

    func testHistoryDeletionPolicyPreservesUnselectedItemsWhenDeletingSubset() {
        let selected = HistorySelectionItem(id: 1, label: "selected")
        let kept = HistorySelectionItem(id: 2, label: "kept")

        let plan = VoiceInkHistoryDeletionPolicy.deleting(
            [selected],
            from: Set([selected, kept]),
            id: \.id
        )

        var deletedItems: [HistorySelectionItem] = []
        plan.applyRuntimeState { item in
            deletedItems.append(item)
        }

        XCTAssertEqual(deletedItems, [selected])
        XCTAssertEqual(plan.remainingSelection, Set([kept]))
        XCTAssertTrue(plan.deletesID(selected.id))
        XCTAssertFalse(plan.deletesID(kept.id))
    }

    func testHistoryDeletionPolicyRepairsFocusedItemAndIDsSeparately() {
        let visible = HistorySelectionItem(id: 1, label: "visible")
        let sameIDFetchedInstance = HistorySelectionItem(id: 1, label: "fetched")
        let hidden = HistorySelectionItem(id: 2, label: "hidden")

        let plan = VoiceInkHistoryDeletionPolicy.deleting(
            [visible],
            from: Set([visible, hidden]),
            id: \.id
        )

        XCTAssertTrue(plan.deletesItem(visible))
        XCTAssertFalse(plan.deletesItem(sameIDFetchedInstance))
        XCTAssertTrue(plan.deletesID(sameIDFetchedInstance.id))
        XCTAssertFalse(plan.deletesItem(hidden))
        XCTAssertFalse(plan.deletesID(hidden.id))
        XCTAssertFalse(plan.deletesItem(nil))
        XCTAssertFalse(plan.deletesID(nil))
    }

    func testHistoryDeletionPlanAppliesRuntimeDeletionInTargetOrder() {
        let first = HistorySelectionItem(id: 1, label: "first")
        let second = HistorySelectionItem(id: 2, label: "second")
        let plan = VoiceInkHistoryDeletionPolicy.deleting(
            [second, first],
            from: Set([first, second]),
            id: \.id
        )

        var deletedIDs: [Int] = []
        plan.applyRuntimeState { item in
            deletedIDs.append(item.id)
        }

        XCTAssertEqual(deletedIDs, [2, 1])
    }

    func testHistoryDeletionPolicyBuildsOffsetDeletionPlan() {
        let latest = HistorySelectionItem(id: 1, label: "latest")
        let hiddenBySearch = HistorySelectionItem(id: 2, label: "hidden-by-search")
        let oldest = HistorySelectionItem(id: 3, label: "oldest")

        let plan = VoiceInkHistoryDeletionPolicy.offsetDeletionPlan(
            atOffsets: IndexSet([0, 2, 7]),
            from: [latest, hiddenBySearch, oldest],
            id: \.id
        )

        var deletedItems: [HistorySelectionItem] = []
        plan.applyRuntimeState { item in
            deletedItems.append(item)
        }

        XCTAssertEqual(deletedItems, [latest, oldest])
        XCTAssertTrue(plan.remainingSelection.isEmpty)
        XCTAssertTrue(plan.deletesID(latest.id))
        XCTAssertTrue(plan.deletesID(oldest.id))
        XCTAssertFalse(plan.deletesID(hiddenBySearch.id))
    }

    func testHistoryRefreshPolicyReloadsForSearchTextChanges() {
        XCTAssertEqual(
            historyRefreshEvents(for: VoiceInkHistoryRefreshPolicy.searchTextDidChange()),
            ["reload"]
        )
    }

    func testHistoryRefreshPolicyReloadsForVisibleLatestItemChanges() {
        XCTAssertEqual(
            historyRefreshEvents(
                for: VoiceInkHistoryRefreshPolicy.latestItemDidChange(
                    oldID: 1,
                    newID: 2,
                    isViewVisible: true
                )
            ),
            ["reload"]
        )
    }

    func testHistoryRefreshPolicyIgnoresHiddenOrUnchangedLatestItemChanges() {
        XCTAssertEqual(
            historyRefreshEvents(
                for: VoiceInkHistoryRefreshPolicy.latestItemDidChange(
                    oldID: 1,
                    newID: 2,
                    isViewVisible: false
                )
            ),
            []
        )
        XCTAssertEqual(
            historyRefreshEvents(
                for: VoiceInkHistoryRefreshPolicy.latestItemDidChange(
                    oldID: 1,
                    newID: 1,
                    isViewVisible: true
                )
            ),
            []
        )
        XCTAssertEqual(
            historyRefreshEvents(
                for: VoiceInkHistoryRefreshPolicy.latestItemDidChange(
                    oldID: Optional<Int>.none,
                    newID: Optional<Int>.none,
                    isViewVisible: true
                )
            ),
            []
        )
    }

    private func historyRefreshEvents(for plan: VoiceInkHistoryRefreshPlan) -> [String] {
        var events: [String] = []
        plan.applyRuntimeState(
            reload: {
                events.append("reload")
            }
        )
        return events
    }

    func testHistoryDeleteConfirmationPresentationPreservesMacOSAlertCopy() {
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationTitle, "Delete Selected Items?")
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationPrimaryButtonTitle, "Delete")
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationCancelButtonTitle, "Cancel")
    }

    func testHistoryDiagnosticsPreserveMacOSConsoleCopy() {
        XCTAssertEqual(
            VoiceInkHistoryDiagnostics.initialLoadFailedMessage(errorDescription: "store unavailable"),
            "Error loading transcriptions: store unavailable"
        )
        XCTAssertEqual(
            VoiceInkHistoryDiagnostics.loadMoreFailedMessage(errorDescription: "cursor expired"),
            "Error loading more transcriptions: cursor expired"
        )
        XCTAssertEqual(
            VoiceInkHistoryDiagnostics.saveDeletionFailedMessage(localizedDescription: "permission denied"),
            "Error saving deletion: permission denied"
        )
        XCTAssertEqual(
            VoiceInkHistoryDiagnostics.selectAllFailedMessage(errorDescription: "fetch failed"),
            "Error selecting all transcriptions: fetch failed"
        )
    }

    func testTranscriptionMetadataPresentationPreservesMacOSDetailRows() {
        XCTAssertEqual(VoiceInkTranscriptionMetadataPresentation.detailsSectionTitle, "Details")
        XCTAssertEqual(
            [
                VoiceInkTranscriptionMetadataPresentation.dateRow,
                VoiceInkTranscriptionMetadataPresentation.durationRow,
                VoiceInkTranscriptionMetadataPresentation.transcriptionModelRow,
                VoiceInkTranscriptionMetadataPresentation.transcriptionTimeRow,
                VoiceInkTranscriptionMetadataPresentation.enhancementModelRow,
                VoiceInkTranscriptionMetadataPresentation.enhancementTimeRow,
                VoiceInkTranscriptionMetadataPresentation.promptRow,
                VoiceInkTranscriptionMetadataPresentation.powerModeRow
            ],
            [
                VoiceInkTranscriptionMetadataRowPresentation(label: "Date", systemImageName: "calendar"),
                VoiceInkTranscriptionMetadataRowPresentation(label: "Duration", systemImageName: "hourglass"),
                VoiceInkTranscriptionMetadataRowPresentation(label: "Transcription Model", systemImageName: "cpu.fill"),
                VoiceInkTranscriptionMetadataRowPresentation(label: "Transcription Time", systemImageName: "clock.fill"),
                VoiceInkTranscriptionMetadataRowPresentation(label: "Enhancement Model", systemImageName: "sparkles"),
                VoiceInkTranscriptionMetadataRowPresentation(label: "Enhancement Time", systemImageName: "clock.fill"),
                VoiceInkTranscriptionMetadataRowPresentation(label: "Prompt", systemImageName: "text.bubble.fill"),
                VoiceInkTranscriptionMetadataRowPresentation(label: "Power Mode", systemImageName: "bolt.fill")
            ]
        )
    }

    func testTranscriptionMetadataPresentationPreservesAIRequestCopy() {
        XCTAssertEqual(VoiceInkTranscriptionMetadataPresentation.aiRequestSectionTitle, "AI Request")
        XCTAssertEqual(VoiceInkTranscriptionMetadataPresentation.systemPromptLabel, "System Prompt")
        XCTAssertEqual(VoiceInkTranscriptionMetadataPresentation.userMessageLabel, "User Message")
    }

    func testTranscriptionMetadataPresentationPreservesAIRequestVisibilityRule() {
        XCTAssertFalse(
            VoiceInkTranscriptionMetadataPresentation.shouldShowAIRequestSection(
                systemMessage: nil,
                userMessage: nil
            )
        )
        XCTAssertTrue(
            VoiceInkTranscriptionMetadataPresentation.shouldShowAIRequestSection(
                systemMessage: "",
                userMessage: nil
            )
        )
        XCTAssertTrue(
            VoiceInkTranscriptionMetadataPresentation.shouldShowAIRequestSection(
                systemMessage: nil,
                userMessage: ""
            )
        )
    }

    func testFullAIRequestTextPreservesMacOSCopyComposition() {
        XCTAssertEqual(
            VoiceInkTranscriptionMetadataPresentation.fullAIRequestText(
                systemMessage: "Follow style guide.",
                userMessage: "Clean this transcript."
            ),
            "System Prompt:\nFollow style guide.\n\nUser Message:\nClean this transcript."
        )
        XCTAssertEqual(
            VoiceInkTranscriptionMetadataPresentation.fullAIRequestText(
                systemMessage: "Follow style guide.",
                userMessage: nil
            ),
            "System Prompt:\nFollow style guide."
        )
        XCTAssertEqual(
            VoiceInkTranscriptionMetadataPresentation.fullAIRequestText(
                systemMessage: nil,
                userMessage: "Clean this transcript."
            ),
            "User Message:\nClean this transcript."
        )
        XCTAssertEqual(
            VoiceInkTranscriptionMetadataPresentation.fullAIRequestText(
                systemMessage: "",
                userMessage: ""
            ),
            ""
        )
    }

    func testPreferredTextUsesEnhancedTextWhenPresent() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.preferredText(
                rawText: "raw transcript",
                enhancedText: "enhanced transcript"
            ),
            "enhanced transcript"
        )
    }

    func testPreferredTextFallsBackToRawTextWhenEnhancedTextIsEmpty() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.preferredText(
                rawText: "raw transcript",
                enhancedText: ""
            ),
            "raw transcript"
        )
    }

    func testPreferredTextReturnsNilWhenAllTextIsEmpty() {
        XCTAssertNil(
            VoiceInkTranscriptPresentation.preferredText(
                rawText: "",
                enhancedText: nil
            )
        )
    }

    func testPreferredTextOrEmptyContentUsesSharedFallback() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.preferredTextOrEmptyContent(
                rawText: "",
                enhancedText: nil
            ),
            "No content available."
        )
    }

    func testTranscriptActionTextUsesPreferredTextWhenCollapsed() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.transcriptActionText(
                selectedVariant: .original,
                isExpanded: false,
                rawText: "raw transcript",
                enhancedText: "enhanced transcript"
            ),
            "enhanced transcript"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.transcriptActionText(
                selectedVariant: .enhanced,
                isExpanded: false,
                rawText: "raw transcript",
                enhancedText: nil
            ),
            "raw transcript"
        )
    }

    func testTranscriptActionTextUsesSelectedVariantWhenExpanded() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.transcriptActionText(
                selectedVariant: .original,
                isExpanded: true,
                rawText: "raw transcript",
                enhancedText: "enhanced transcript"
            ),
            "raw transcript"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.transcriptActionText(
                selectedVariant: .enhanced,
                isExpanded: true,
                rawText: "raw transcript",
                enhancedText: "enhanced transcript"
            ),
            "enhanced transcript"
        )
    }

    func testTranscriptActionTextReturnsEmptyForMissingText() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.transcriptActionText(
                selectedVariant: .enhanced,
                isExpanded: false,
                rawText: "",
                enhancedText: nil
            ),
            ""
        )
    }

    func testDeleteConfirmationMessagePreservesHistoryPluralization() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.deleteConfirmationMessage(selectedCount: 1),
            "This action cannot be undone. Are you sure you want to delete 1 item?"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.deleteConfirmationMessage(selectedCount: 2),
            "This action cannot be undone. Are you sure you want to delete 2 items?"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.deleteConfirmationMessage(selectedCount: 0),
            "This action cannot be undone. Are you sure you want to delete 0 items?"
        )
    }

    func testHistoryDeletionPolicyUsesDisplayedListOffsets() {
        let plan = VoiceInkHistoryDeletionPolicy.offsetDeletionPlan(
            atOffsets: IndexSet([0, 2]),
            from: ["latest", "hidden-by-search", "oldest"],
            id: \.self
        )

        var deletedItems: [String] = []
        plan.applyRuntimeState { item in
            deletedItems.append(item)
        }

        XCTAssertEqual(deletedItems, ["latest", "oldest"])
    }

    func testHistoryDeletionPolicyIgnoresStaleOffsets() {
        let plan = VoiceInkHistoryDeletionPolicy.offsetDeletionPlan(
            atOffsets: IndexSet([1, 5]),
            from: ["latest", "oldest"],
            id: \.self
        )

        var deletedItems: [String] = []
        plan.applyRuntimeState { item in
            deletedItems.append(item)
        }

        XCTAssertEqual(deletedItems, ["oldest"])
    }

    func testFailedTranscriptTextPreservesMacOSFailurePrefix() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.failedTranscriptText(reason: "No model selected"),
            "Transcription Failed: No model selected"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.failedTranscriptText(reason: "Audio file not found"),
            "Transcription Failed: Audio file not found"
        )
    }

    func testMatchesSearchReturnsTrueForEmptyQuery() {
        XCTAssertTrue(
            VoiceInkTranscriptPresentation.matchesSearch(
                rawText: "Raw transcript",
                enhancedText: nil,
                query: ""
            )
        )
    }

    func testMatchesSearchChecksRawTextCaseInsensitively() {
        XCTAssertTrue(
            VoiceInkTranscriptPresentation.matchesSearch(
                rawText: "Schedule the launch review",
                enhancedText: nil,
                query: "LAUNCH"
            )
        )
    }

    func testMatchesSearchChecksEnhancedTextCaseInsensitively() {
        XCTAssertTrue(
            VoiceInkTranscriptPresentation.matchesSearch(
                rawText: "raw",
                enhancedText: "Follow up with design",
                query: "DESIGN"
            )
        )
    }

    func testMatchesSearchUsesMacOSStandardSearchSemantics() {
        XCTAssertTrue(
            VoiceInkTranscriptPresentation.matchesSearch(
                rawText: "Cafe notes",
                enhancedText: nil,
                query: "café"
            )
        )
        XCTAssertTrue(
            VoiceInkTranscriptPresentation.matchesSearch(
                rawText: "raw",
                enhancedText: "Review the résumé",
                query: "resume"
            )
        )
    }

    func testMatchesSearchReturnsFalseWhenQueryIsAbsent() {
        XCTAssertFalse(
            VoiceInkTranscriptPresentation.matchesSearch(
                rawText: "raw",
                enhancedText: "enhanced",
                query: "invoice"
            )
        )
    }

    func testFilteredItemsUsesSharedTranscriptSearchSemantics() {
        let notes = [
            TranscriptSearchItem(id: 1, rawText: "Cafe notes", enhancedText: nil),
            TranscriptSearchItem(id: 2, rawText: "raw", enhancedText: "Follow up with design"),
            TranscriptSearchItem(id: 3, rawText: "Budget review", enhancedText: nil)
        ]

        XCTAssertEqual(
            VoiceInkTranscriptPresentation.filteredItems(
                notes,
                query: "café",
                rawText: \.rawText,
                enhancedText: \.enhancedText
            ).map(\.id),
            [1]
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.filteredItems(
                notes,
                query: "DESIGN",
                rawText: \.rawText,
                enhancedText: \.enhancedText
            ).map(\.id),
            [2]
        )
    }

    func testFilteredItemsKeepsOriginalOrderForEmptyQuery() {
        let notes = [
            TranscriptSearchItem(id: 1, rawText: "First", enhancedText: nil),
            TranscriptSearchItem(id: 2, rawText: "Second", enhancedText: "Enhanced second")
        ]

        XCTAssertEqual(
            VoiceInkTranscriptPresentation.filteredItems(
                notes,
                query: "",
                rawText: \.rawText,
                enhancedText: \.enhancedText
            ).map(\.id),
            [1, 2]
        )
    }

    func testDefaultDisplayTextUsesSharedFallbacks() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.displayText(
                status: .pending,
                rawText: "",
                enhancedText: nil
            ),
            "New transcription"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.displayText(
                status: .failed,
                rawText: "",
                enhancedText: nil
            ),
            "Transcription failed - tap to retry"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.displayText(
                status: .canceled,
                rawText: "",
                enhancedText: nil
            ),
            "Transcription canceled"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.displayText(
                status: .completed,
                rawText: "",
                enhancedText: nil
            ),
            "No audible content detected."
        )
    }

    func testCustomDisplayTextStillAllowsShellFallbacks() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.displayText(
                status: .pending,
                rawText: "",
                enhancedText: nil,
                pendingText: "Queued",
                failedText: "Broken",
                canceledText: "Stopped",
                emptyCompletedText: "Empty"
            ),
            "Queued"
        )
    }

    func testAbbreviatedTimestampPreservesMacOSDetailFormat() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = testDate(timeZone: timeZone)

        XCTAssertEqual(
            VoiceInkDatePresentation.abbreviatedTimestamp(
                date,
                locale: Locale(identifier: "en_GB"),
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            ),
            "18 Jun 2026 at 12:34"
        )
    }

    func testCompactTimestampPreservesMacOSHistoryListFormat() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = testDate(timeZone: timeZone)

        XCTAssertEqual(
            VoiceInkDatePresentation.compactTimestamp(
                date,
                locale: Locale(identifier: "en_GB"),
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            ),
            "18 Jun at 12:34"
        )
    }

    func testRelativeTimestampUsesShortRelativeStyle() {
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            VoiceInkDatePresentation.relativeTimestamp(
                referenceDate.addingTimeInterval(-60),
                relativeTo: referenceDate,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "1 min. ago"
        )
        XCTAssertEqual(
            VoiceInkDatePresentation.relativeTimestamp(
                referenceDate.addingTimeInterval(60),
                relativeTo: referenceDate,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "in 1 min."
        )
    }

    func testPositiveDurationVisibilityOnlyAllowsPositiveDurations() {
        XCTAssertEqual(VoiceInkDurationPresentation.metadataSeparatorText, "•")
        XCTAssertFalse(VoiceInkDurationPresentation.shouldShowPositiveDuration(-1))
        XCTAssertFalse(VoiceInkDurationPresentation.shouldShowPositiveDuration(0))
        XCTAssertTrue(VoiceInkDurationPresentation.shouldShowPositiveDuration(0.1))
    }

    func testMinutesSecondsUsesUnpaddedMinutesByDefault() {
        XCTAssertEqual(VoiceInkDurationPresentation.minutesSeconds(5), "0:05")
        XCTAssertEqual(VoiceInkDurationPresentation.minutesSeconds(65), "1:05")
    }

    func testMinutesSecondsCanPadMinutesToTwoDigits() {
        XCTAssertEqual(
            VoiceInkDurationPresentation.minutesSeconds(5, padMinutesToTwoDigits: true),
            "00:05"
        )
        XCTAssertEqual(
            VoiceInkDurationPresentation.minutesSeconds(65, padMinutesToTwoDigits: true),
            "01:05"
        )
    }

    func testMinutesSecondsTruncatesFractionalSeconds() {
        XCTAssertEqual(VoiceInkDurationPresentation.minutesSeconds(65.9), "1:05")
    }

    func testAbbreviatedMinutesSecondsMatchesMetricsFormatting() {
        XCTAssertEqual(VoiceInkDurationPresentation.abbreviatedMinutesSeconds(0), "0s")
        XCTAssertEqual(VoiceInkDurationPresentation.abbreviatedMinutesSeconds(65), "1m 5s")
        XCTAssertEqual(VoiceInkDurationPresentation.abbreviatedMinutesSeconds(125.6), "2m 5s")
    }

    func testPositiveDurationReturnsFallbackForZeroOrNegativeDurations() {
        XCTAssertEqual(
            VoiceInkDurationPresentation.positiveDuration(0, style: .full, fallback: "Time savings coming soon"),
            "Time savings coming soon"
        )
        XCTAssertEqual(VoiceInkDurationPresentation.positiveDuration(-1, style: .abbreviated), "–")
    }

    func testPositiveDurationUsesMinuteSecondUnitsBelowOneHour() {
        XCTAssertEqual(VoiceInkDurationPresentation.positiveDuration(65, style: .abbreviated), "1m 5s")
    }

    func testPositiveDurationUsesHourMinuteUnitsFromOneHour() {
        XCTAssertEqual(VoiceInkDurationPresentation.positiveDuration(3665, style: .abbreviated), "1h 1m")
    }

    func testCompactElapsedUsesMillisecondsForSubsecondDurations() {
        XCTAssertEqual(VoiceInkDurationPresentation.compactElapsed(0.125), "125ms")
    }

    func testCompactElapsedUsesOneDecimalSecondsUnderOneMinute() {
        XCTAssertEqual(VoiceInkDurationPresentation.compactElapsed(12.34), "12.3s")
    }

    func testCompactElapsedUsesMinutesAndRoundedSecondsFromOneMinute() {
        XCTAssertEqual(VoiceInkDurationPresentation.compactElapsed(125.6), "2m 6s")
    }

    func testNoteRowPresentationBuildsCompletedIOSRow() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = referenceDate.addingTimeInterval(-300)
        let locale = Locale(identifier: "en_US_POSIX")

        let presentation = VoiceInkNoteRowPresentation.make(
            status: .completed,
            rawText: "raw transcript",
            enhancedText: "enhanced transcript",
            timestamp: timestamp,
            duration: 125,
            referenceDate: referenceDate,
            locale: locale
        )

        XCTAssertEqual(presentation.displayText, "enhanced transcript")
        XCTAssertEqual(
            presentation.timestampText,
            VoiceInkDatePresentation.relativeTimestamp(timestamp, relativeTo: referenceDate, locale: locale)
        )
        XCTAssertEqual(presentation.durationText, "02:05")
        XCTAssertEqual(presentation.metadataSeparatorText, VoiceInkDurationPresentation.metadataSeparatorText)
        XCTAssertNil(presentation.statusPresentation)
    }

    func testNoteRowPresentationUsesStatusFallbacksForRetryStates() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let locale = Locale(identifier: "en_US_POSIX")

        let pending = VoiceInkNoteRowPresentation.make(
            status: .pending,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: 0,
            referenceDate: referenceDate,
            locale: locale
        )
        let failed = VoiceInkNoteRowPresentation.make(
            status: .failed,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: 0,
            referenceDate: referenceDate,
            locale: locale
        )
        let canceled = VoiceInkNoteRowPresentation.make(
            status: .canceled,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: 0,
            referenceDate: referenceDate,
            locale: locale
        )

        XCTAssertEqual(pending.displayText, VoiceInkTranscriptPresentation.pendingDisplayText)
        XCTAssertTrue(pending.statusPresentation?.shouldShowInlineProgress == true)
        XCTAssertEqual(failed.displayText, VoiceInkTranscriptPresentation.failedDisplayText)
        XCTAssertTrue(failed.statusPresentation?.shouldShowInlineBadge == true)
        XCTAssertEqual(canceled.displayText, VoiceInkTranscriptPresentation.canceledDisplayText)
        XCTAssertNil(canceled.statusPresentation)
    }

    func testNoteRowPresentationOmitsNonPositiveDuration() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

        let zeroDuration = VoiceInkNoteRowPresentation.make(
            status: .completed,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: 0,
            referenceDate: referenceDate,
            locale: Locale(identifier: "en_US_POSIX")
        )
        let negativeDuration = VoiceInkNoteRowPresentation.make(
            status: .completed,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: -1,
            referenceDate: referenceDate,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertNil(zeroDuration.durationText)
        XCTAssertNil(zeroDuration.metadataSeparatorText)
        XCTAssertNil(negativeDuration.durationText)
        XCTAssertNil(negativeDuration.metadataSeparatorText)
    }

    func testNoteDetailPresentationBuildsCompletedContentAndAudioSection() {
        let audioURL = URL(fileURLWithPath: "/tmp/recording.wav")

        let presentation = VoiceInkNoteDetailPresentation.make(
            status: .completed,
            rawText: "raw transcript",
            enhancedText: "enhanced transcript",
            transcriptionError: nil,
            isRetranscribing: false,
            audioAvailability: .available(audioURL),
            duration: 0
        )

        XCTAssertEqual(presentation.navigationTitle, VoiceInkTranscriptPresentation.noteDetailNavigationTitle)
        XCTAssertEqual(presentation.transcriptContent?.title, VoiceInkTranscriptPresentation.transcriptTitle)
        XCTAssertEqual(presentation.transcriptContent?.text, "enhanced transcript")
        XCTAssertEqual(
            presentation.transcriptContent?.copySystemImageName,
            VoiceInkTranscriptPresentation.copyTranscriptSystemImageName
        )
        XCTAssertNil(presentation.statusPanel)
        XCTAssertEqual(presentation.audioAvailability, .available(audioURL))
        XCTAssertTrue(presentation.shouldShowAudioSection)
    }

    func testNoteDetailPresentationUsesRawTextWhenEnhancedTextIsEmpty() {
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: .completed,
            rawText: "raw transcript",
            enhancedText: "",
            transcriptionError: nil,
            isRetranscribing: false,
            audioAvailability: .missingPath,
            duration: 0
        )

        XCTAssertEqual(presentation.transcriptContent?.text, "raw transcript")
    }

    func testNoteDetailPresentationUsesEmptyCompletedContentFallback() {
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: .completed,
            rawText: "",
            enhancedText: nil,
            transcriptionError: nil,
            isRetranscribing: false,
            audioAvailability: .missingPath,
            duration: 0
        )

        XCTAssertEqual(
            presentation.transcriptContent?.text,
            VoiceInkTranscriptPresentation.emptyPreferredText
        )
        XCTAssertNil(presentation.statusPanel)
        XCTAssertFalse(presentation.shouldShowAudioSection)
    }

    func testNoteDetailPresentationHidesCanceledContentAndStatusPanel() {
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: .canceled,
            rawText: "raw transcript",
            enhancedText: "enhanced transcript",
            transcriptionError: "Canceled",
            isRetranscribing: false,
            audioAvailability: .missingPath,
            duration: 0
        )

        XCTAssertNil(presentation.transcriptContent)
        XCTAssertNil(presentation.statusPanel)
        XCTAssertFalse(presentation.shouldShowAudioSection)
    }

    func testNoteDetailPresentationBuildsFailedStatusPanel() {
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: .failed,
            rawText: "raw transcript",
            enhancedText: nil,
            transcriptionError: "Missing audio file",
            isRetranscribing: false,
            audioAvailability: .missingPath,
            duration: 12
        )

        XCTAssertNil(presentation.transcriptContent)
        XCTAssertEqual(presentation.statusPanel?.statusPresentation.title, "Transcription Failed")
        XCTAssertEqual(presentation.statusPanel?.errorDetail, "Missing audio file")
        XCTAssertTrue(presentation.statusPanel?.retryControls.shouldShowModeSelection == true)
        XCTAssertFalse(presentation.statusPanel?.retryControls.shouldShowProgress == true)
        XCTAssertEqual(
            presentation.statusPanel?.retryButtonTitle,
            VoiceInkTranscriptPresentation.retryTranscriptionButtonTitle
        )
        XCTAssertEqual(
            presentation.statusPanel?.retryButtonSystemImageName,
            VoiceInkTranscriptPresentation.retryTranscriptionSystemImageName
        )
        XCTAssertTrue(presentation.shouldShowAudioSection)
    }

    func testNoteDetailPresentationPreservesMissingAudioAvailability() {
        let missingURL = URL(fileURLWithPath: "/tmp/missing.wav")
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: .failed,
            rawText: "",
            enhancedText: nil,
            transcriptionError: nil,
            isRetranscribing: false,
            audioAvailability: .missingFile(missingURL),
            duration: 0
        )

        XCTAssertEqual(presentation.audioAvailability, .missingFile(missingURL))
        XCTAssertEqual(presentation.audioAvailability.unavailableTitle, "Audio Unavailable")
        XCTAssertEqual(presentation.audioAvailability.unavailableDetail, "File not found")
        XCTAssertTrue(presentation.shouldShowAudioSection)
    }

    func testNoteDetailPresentationBuildsPendingProgressPanel() {
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: .pending,
            rawText: "",
            enhancedText: nil,
            transcriptionError: nil,
            isRetranscribing: false,
            audioAvailability: .missingPath,
            duration: 0
        )

        XCTAssertNil(presentation.transcriptContent)
        XCTAssertEqual(presentation.statusPanel?.statusPresentation.title, "Transcription Pending")
        XCTAssertFalse(presentation.statusPanel?.retryControls.shouldShowModeSelection == true)
        XCTAssertTrue(presentation.statusPanel?.retryControls.shouldShowProgress == true)
        XCTAssertEqual(
            presentation.statusPanel?.retryControls.progressDisplayText,
            VoiceInkTranscriptPresentation.transcribingDisplayText
        )
    }

    func testNoteDetailPresentationUsesRetranscribingProgressPanel() {
        let presentation = VoiceInkNoteDetailPresentation.make(
            status: .failed,
            rawText: "",
            enhancedText: nil,
            transcriptionError: "",
            isRetranscribing: true,
            audioAvailability: .missingPath,
            duration: 0
        )

        XCTAssertNil(presentation.statusPanel?.errorDetail)
        XCTAssertFalse(presentation.statusPanel?.retryControls.shouldShowModeSelection == true)
        XCTAssertTrue(presentation.statusPanel?.retryControls.shouldShowProgress == true)
        XCTAssertEqual(
            presentation.statusPanel?.retryControls.progressDisplayText,
            VoiceInkTranscriptPresentation.retranscribingDisplayText
        )
    }

    func testStatusTitleReturnsRetryStateTitles() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.statusTitle(for: .pending),
            "Transcription Pending"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.statusTitle(for: .failed),
            "Transcription Failed"
        )
    }

    func testStatusTitleReturnsNilForNonRetryStates() {
        XCTAssertNil(VoiceInkTranscriptPresentation.statusTitle(for: .completed))
        XCTAssertNil(VoiceInkTranscriptPresentation.statusTitle(for: .canceled))
    }

    func testStatusBadgeTextReturnsRetryStateLabels() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.statusBadgeText(for: .pending),
            "Processing"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.statusBadgeText(for: .failed),
            "Failed"
        )
    }

    func testStatusBadgeTextReturnsNilForNonRetryStates() {
        XCTAssertNil(VoiceInkTranscriptPresentation.statusBadgeText(for: .completed))
        XCTAssertNil(VoiceInkTranscriptPresentation.statusBadgeText(for: .canceled))
    }

    func testStatusPresentationReturnsRetryStateMetadata() {
        let pending = VoiceInkTranscriptPresentation.statusPresentation(for: .pending)
        XCTAssertEqual(pending?.title, "Transcription Pending")
        XCTAssertEqual(pending?.badgeText, "Processing")
        XCTAssertEqual(pending?.tone, .processing)
        XCTAssertEqual(pending?.panelSystemImageName, "clock.fill")
        XCTAssertEqual(pending?.shouldShowInlineProgress, true)
        XCTAssertEqual(pending?.shouldShowInlineBadge, false)

        let failed = VoiceInkTranscriptPresentation.statusPresentation(for: .failed)
        XCTAssertEqual(failed?.title, "Transcription Failed")
        XCTAssertEqual(failed?.badgeText, "Failed")
        XCTAssertEqual(failed?.tone, .failure)
        XCTAssertEqual(failed?.panelSystemImageName, "exclamationmark.triangle.fill")
        XCTAssertEqual(failed?.shouldShowInlineProgress, false)
        XCTAssertEqual(failed?.shouldShowInlineBadge, true)
    }

    func testStatusPresentationContentVisibilityMatchesTranscriptState() {
        XCTAssertTrue(VoiceInkTranscriptPresentation.shouldShowStatusPanel(for: .pending))
        XCTAssertTrue(VoiceInkTranscriptPresentation.shouldShowStatusPanel(for: .failed))
        XCTAssertFalse(VoiceInkTranscriptPresentation.shouldShowStatusPanel(for: .completed))
        XCTAssertFalse(VoiceInkTranscriptPresentation.shouldShowStatusPanel(for: .canceled))

        XCTAssertTrue(VoiceInkTranscriptPresentation.shouldShowCompletedContent(for: .completed))
        XCTAssertFalse(VoiceInkTranscriptPresentation.shouldShowCompletedContent(for: .pending))
        XCTAssertFalse(VoiceInkTranscriptPresentation.shouldShowCompletedContent(for: .failed))
        XCTAssertFalse(VoiceInkTranscriptPresentation.shouldShowCompletedContent(for: .canceled))
    }

    func testStatusErrorDetailShowsOnlyNonEmptyErrors() {
        XCTAssertNil(VoiceInkTranscriptPresentation.statusErrorDetail(nil))
        XCTAssertNil(VoiceInkTranscriptPresentation.statusErrorDetail(""))
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.statusErrorDetail("Missing audio file"),
            "Missing audio file"
        )
    }

    func testRetryControlsPresentationShowsRetryControlsWhenIdle() {
        let presentation = VoiceInkTranscriptPresentation.retryControls(for: .failed, isRetranscribing: false)

        XCTAssertTrue(presentation.shouldShowModeSelection)
        XCTAssertFalse(presentation.shouldShowProgress)
        XCTAssertNil(presentation.progressDisplayText)
    }

    func testRetryControlsPresentationShowsProgressWhenRetranscribing() {
        let presentation = VoiceInkTranscriptPresentation.retryControls(for: .failed, isRetranscribing: true)

        XCTAssertFalse(presentation.shouldShowModeSelection)
        XCTAssertTrue(presentation.shouldShowProgress)
        XCTAssertEqual(presentation.progressDisplayText, "Retranscribing...")
    }

    func testRetryControlsPresentationShowsPendingProgressWithoutRetryControls() {
        let presentation = VoiceInkTranscriptPresentation.retryControls(for: .pending, isRetranscribing: false)

        XCTAssertFalse(presentation.shouldShowModeSelection)
        XCTAssertTrue(presentation.shouldShowProgress)
        XCTAssertEqual(presentation.progressDisplayText, "Transcribing...")
    }

    func testRetryControlsPresentationHidesControlsForTerminalNonFailedStates() {
        let completed = VoiceInkTranscriptPresentation.retryControls(for: .completed, isRetranscribing: false)
        XCTAssertFalse(completed.shouldShowModeSelection)
        XCTAssertFalse(completed.shouldShowProgress)
        XCTAssertNil(completed.progressDisplayText)
        XCTAssertNil(completed.runtimeAction {})

        let canceled = VoiceInkTranscriptPresentation.retryControls(for: .canceled, isRetranscribing: false)
        XCTAssertFalse(canceled.shouldShowModeSelection)
        XCTAssertFalse(canceled.shouldShowProgress)
        XCTAssertNil(canceled.progressDisplayText)
        XCTAssertNil(canceled.runtimeAction {})
    }

    func testRetryControlsPresentationMapsRetryButtonToRuntimeRetry() {
        let presentation = VoiceInkTranscriptPresentation.retryControls(for: .failed, isRetranscribing: false)
        var didRetry = false

        let retryAction = presentation.runtimeAction {
            didRetry = true
        }

        XCTAssertTrue(retryAction != nil)
        retryAction?()
        XCTAssertTrue(didRetry)

        XCTAssertNil(VoiceInkTranscriptPresentation.retryControls(
            for: .failed,
            isRetranscribing: true
        ).runtimeAction {})
        XCTAssertNil(VoiceInkTranscriptPresentation.retryControls(
            for: .pending,
            isRetranscribing: false
        ).runtimeAction {})
    }

    func testTranscriptTextVariantTitlesPreserveMacOSTabs() {
        XCTAssertEqual(VoiceInkTranscriptTextVariant.original.title, "Original")
        XCTAssertEqual(VoiceInkTranscriptTextVariant.enhanced.title, "Enhanced")
        XCTAssertEqual(VoiceInkTranscriptTextVariant.allCases, [.original, .enhanced])
    }

    func testTranscriptTextVariantDisplayTextPreservesMacOSTabSelection() {
        XCTAssertEqual(
            VoiceInkTranscriptTextVariant.original.displayText(
                rawText: "raw",
                enhancedText: "enhanced"
            ),
            "raw"
        )
        XCTAssertEqual(
            VoiceInkTranscriptTextVariant.enhanced.displayText(
                rawText: "raw",
                enhancedText: "enhanced"
            ),
            "enhanced"
        )
        XCTAssertEqual(
            VoiceInkTranscriptTextVariant.enhanced.displayText(
                rawText: "raw",
                enhancedText: nil
            ),
            ""
        )
    }

    func testTranscriptTextVariantTabVisibilityPreservesMacOSNilOnlyRule() {
        XCTAssertFalse(VoiceInkTranscriptTextVariant.shouldShowTabs(enhancedText: nil))
        XCTAssertTrue(VoiceInkTranscriptTextVariant.shouldShowTabs(enhancedText: ""))
        XCTAssertTrue(VoiceInkTranscriptTextVariant.shouldShowTabs(enhancedText: "enhanced"))
    }

    func testTranscriptDetailCopyPreservesIOSNoteDetailLabels() {
        XCTAssertEqual(VoiceInkTranscriptPresentation.noteDetailNavigationTitle, "Note")
        XCTAssertEqual(VoiceInkTranscriptPresentation.transcriptTitle, "Transcript")
        XCTAssertEqual(VoiceInkTranscriptPresentation.copyTranscriptSystemImageName, "doc.on.doc")
        XCTAssertEqual(VoiceInkTranscriptPresentation.retranscribingDisplayText, "Retranscribing...")
        XCTAssertEqual(VoiceInkTranscriptPresentation.retryTranscriptionButtonTitle, "Retry Transcription")
        XCTAssertEqual(VoiceInkTranscriptPresentation.retryTranscriptionSystemImageName, "arrow.clockwise")
    }

    func testTranscriptActionControlPresentationPreservesMacOSCopyAndSaveCopy() {
        XCTAssertEqual(VoiceInkTranscriptPresentation.actionSucceededSystemImageName, "checkmark")
        XCTAssertEqual(VoiceInkTranscriptPresentation.copyToClipboardHelp, "Copy to clipboard")
        XCTAssertEqual(VoiceInkTranscriptPresentation.saveTranscriptSystemImageName, "square.and.arrow.down")
        XCTAssertEqual(VoiceInkTranscriptPresentation.saveTranscriptAsPlainTextButtonTitle, "Save as TXT")
        XCTAssertEqual(VoiceInkTranscriptPresentation.saveTranscriptAsMarkdownButtonTitle, "Save as MD")
        XCTAssertEqual(VoiceInkTranscriptPresentation.saveTranscriptHelp, "Save to file")
        XCTAssertEqual(VoiceInkTranscriptPresentation.saveTranscriptPanelTitle, "Save Transcription")
        XCTAssertEqual(VoiceInkTranscriptPresentation.saveTranscriptFailureConsolePrefix, "Failed to save file:")
    }

    func testLastTranscriptionPresentationPreservesMacOSNotificationCopy() {
        XCTAssertEqual(VoiceInkTranscriptPresentation.noTranscriptionAvailableTitle, "No transcription available")
        XCTAssertEqual(VoiceInkTranscriptPresentation.lastTranscriptionCopiedTitle, "Last transcription copied")
        XCTAssertEqual(VoiceInkTranscriptPresentation.failedToCopyTranscriptionTitle, "Failed to copy transcription")
        XCTAssertEqual(VoiceInkTranscriptPresentation.copiedToClipboardTitle, "Copied to clipboard")
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.cannotRetryTitle(errorDescription: "Audio file not found"),
            "Cannot retry: Audio file not found"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.retryFailedTitle(errorDescription: "provider unavailable"),
            "Retry failed: provider unavailable"
        )
    }

    func testFirstPasteableCandidateSkipsExcludedPendingBlankAndCanceledCandidates() {
        let excluded = UUID()
        let expected = UUID()
        let candidates = [
            candidate(id: excluded, rawText: "excluded"),
            candidate(rawText: "still pending", status: .pending),
            candidate(rawText: "   "),
            candidate(rawText: VoiceInkTranscriptPresentation.canceledTranscriptionText, status: .canceled),
            candidate(id: expected, rawText: "legacy usable", status: nil)
        ]

        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.firstPasteableCandidate(
                in: candidates,
                excluding: excluded
            )?.id,
            expected
        )
    }

    func testFirstPasteableCandidatePreservesCandidateOrder() {
        let older = UUID()
        let newest = UUID()
        let candidates = [
            candidate(id: newest, rawText: "newest"),
            candidate(id: older, rawText: "older")
        ]

        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.firstPasteableCandidate(in: candidates)?.id,
            newest
        )
    }

    func testPasteTextUsesOriginalOrEnhancedFallbackPolicy() {
        let enhanced = candidate(rawText: "raw text", enhancedText: "enhanced text")
        let rawOnly = candidate(rawText: "raw text", enhancedText: nil)

        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.pasteText(for: enhanced, preference: .original),
            "raw text"
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.pasteText(for: enhanced, preference: .preferred),
            "enhanced text"
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.pasteText(for: rawOnly, preference: .preferred),
            "raw text"
        )
    }

    func testFetchLimitPreservesMacOSLastTranscriptionFetchWindow() {
        XCTAssertEqual(VoiceInkLastTranscriptionPolicy.fetchLimit, 20)
    }

    func testFetchFailureDiagnosticPreservesMacOSCopy() {
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.fetchFailedDiagnosticMessage(errorDescription: "SwiftData failed"),
            "Error fetching last transcription: SwiftData failed"
        )
    }

    func testLastTranscriptionNotificationPresentationsPreserveCopyOutcomes() {
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.noTranscriptionNotification,
            VoiceInkLastTranscriptionNotificationPresentation(
                title: "No transcription available",
                kind: .error
            )
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.copyCompletionNotification(didCopy: true),
            VoiceInkLastTranscriptionNotificationPresentation(
                title: "Last transcription copied",
                kind: .success
            )
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.copyCompletionNotification(didCopy: false),
            VoiceInkLastTranscriptionNotificationPresentation(
                title: "Failed to copy transcription",
                kind: .error
            )
        )
    }

    func testLastTranscriptionRetryNotificationPresentationsPreserveMacOSCopy() {
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.retryPreflightFailureNotification(.missingAudio),
            VoiceInkLastTranscriptionNotificationPresentation(
                title: "Cannot retry: Audio file not found",
                kind: .error
            )
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.retryPreflightFailureNotification(.noTranscriptionModelSelected),
            VoiceInkLastTranscriptionNotificationPresentation(
                title: "No transcription model selected",
                kind: .error
            )
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.retrySuccessNotification,
            VoiceInkLastTranscriptionNotificationPresentation(
                title: "Copied to clipboard",
                kind: .success
            )
        )
        XCTAssertEqual(
            VoiceInkLastTranscriptionPolicy.retryFailureNotification(errorDescription: "provider unavailable"),
            VoiceInkLastTranscriptionNotificationPresentation(
                title: "Retry failed: provider unavailable",
                kind: .error
            )
        )
    }

    func testPostProcessingFailureTextPreservesExistingIOSRetryPrefix() {
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.postProcessingFailureText(reason: "provider down"),
            "Post-processing failed: provider down"
        )
    }

    func testEnhancementFailureTextPreservesExistingMacOSPrefix() {
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementFailureText(reason: "provider down"),
            "Enhancement failed: provider down"
        )
    }

    func testEnhancementUnavailableMessagePreservesMacOSGuardCopy() {
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableFallbackText,
            "AI Enhancement is not enabled or configured"
        )
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
                isEnabled: false,
                isConfigured: true
            ),
            "AI Enhancement is not enabled or configured"
        )
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
                isEnabled: true,
                isConfigured: false
            ),
            "AI Enhancement is not enabled or configured"
        )
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
                isEnabled: false,
                isConfigured: false
            ),
            "AI Enhancement is not enabled or configured"
        )
        XCTAssertNil(
            VoiceInkPostProcessingFailurePresentation.enhancementUnavailableMessage(
                isEnabled: true,
                isConfigured: true
            )
        )
    }

    func testEnhancementFailureNotificationTitlePreservesEightyCharacterReasonLimit() {
        let reason = String(repeating: "a", count: 100)
        let title = VoiceInkPostProcessingFailurePresentation.enhancementFailureNotificationTitle(reason: reason)

        XCTAssertEqual(title, "Enhancement failed: \(String(repeating: "a", count: 80))")
    }

    func testEnhancementFailureNotificationTitleClampsNegativeReasonLimit() {
        XCTAssertEqual(
            VoiceInkPostProcessingFailurePresentation.enhancementFailureNotificationTitle(
                reason: "provider down",
                reasonLimit: -1
            ),
            "Enhancement failed: "
        )
    }

    func testAudioFileActionStatusPresentationPreservesMacOSBannerCopy() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.audioFileRetranscriptionSuccessMessage,
            "Retranscription successful"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.audioFileReEnhancementSuccessMessage,
            "Re-enhancement successful"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.audioFileRetranscriptionFailureMessage(errorDescription: ""),
            "Retranscription failed"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.audioFileRetranscriptionFailureMessage(
                errorDescription: "provider unavailable"
            ),
            "provider unavailable"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.audioFileReEnhancementFailureMessage(errorDescription: ""),
            "Re-enhancement failed"
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.audioFileReEnhancementFailureMessage(
                errorDescription: "timeout"
            ),
            "timeout"
        )
    }

    func testDefaultPasteEligibilityRejectsCanceledTranscriptionText() {
        XCTAssertFalse(
            VoiceInkTranscriptPresentation.isPasteable(
                rawText: VoiceInkTranscriptPresentation.canceledTranscriptionText,
                statusRawValue: VoiceInkTranscriptionStatus.completed.rawValue
            )
        )
    }

    func testTranscriptFileExportPreservesMacOSFileExtensions() {
        XCTAssertEqual(VoiceInkTranscriptFileExport.plainTextFileExtension, "txt")
        XCTAssertEqual(VoiceInkTranscriptFileExport.markdownFileExtension, "md")
    }

    func testSuggestedBaseFilenameUsesFallbackForBlankOrPunctuationOnlyText() {
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: " \n\t "),
            "transcription"
        )
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "!!!"),
            "transcription"
        )
    }

    func testSuggestedBaseFilenamePreservesMacOSWordSelectionPolicy() {
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "One two three"),
            "one-two-three"
        )
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "One two three four"),
            "one-two-three-four"
        )
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "One two three four five six seven"),
            "one-two-three-four-five-six-seven"
        )
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "One two three four five six seven eight nine"),
            "one-two-three-four-five-six-seven-eight"
        )
    }

    func testSuggestedBaseFilenameSanitizesAndLimitsLength() {
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.suggestedBaseFilename(for: "Hello, ROMA!\nJust talk."),
            "hello-roma-just-talk"
        )

        let longName = VoiceInkTranscriptFileExport.suggestedBaseFilename(
            for: "Supercalifragilisticexpialidocious abcdefghijklmnopqrstuvwxyz extra words"
        )

        XCTAssertEqual(longName.count, 50)
        XCTAssertEqual(longName, "supercalifragilisticexpialidocious-abcdefghijklmno")
    }

    func testMarkdownContentPreservesMacOSBodyShape() {
        XCTAssertEqual(
            VoiceInkTranscriptFileExport.markdownContent(
                for: "Hello\nworld.",
                timestamp: "Jun 18, 2026 at 12:34"
            ),
            """
            # Transcription

            **Date:** Jun 18, 2026 at 12:34

            Hello
            world.
            """
        )
    }

    func testMarkdownContentFormatsTimestampInSharedCore() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone,
            year: 2026,
            month: 6,
            day: 18,
            hour: 12,
            minute: 34
        ).date!

        XCTAssertEqual(
            VoiceInkTranscriptFileExport.markdownContent(
                for: "Shared export.",
                date: date,
                locale: Locale(identifier: "en_GB"),
                timeZone: timeZone
            ),
            """
            # Transcription

            **Date:** 18 Jun 2026 at 12:34

            Shared export.
            """
        )
    }

    func testCSVExportPresentationPreservesMacOSFilenameAndFailureCopy() {
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.defaultFilename, "VoiceInk-transcription.csv")
        XCTAssertEqual(
            VoiceInkTranscriptionCSVExporter.writeFailureDiagnosticMessage(errorDescription: "disk full"),
            "Error writing CSV file: disk full"
        )
    }

    func testCSVStringPreservesMacOSHeaderAndColumnOrder() {
        let csv = VoiceInkTranscriptionCSVExporter.csvString(for: [
            VoiceInkTranscriptionCSVRecord(
                originalText: "raw",
                enhancedText: "enhanced",
                enhancementModel: "gpt",
                promptName: "Assistant",
                transcriptionModel: "Whisper",
                powerModeName: "Writing",
                powerModeEmoji: "W",
                enhancementTime: 1.25,
                transcriptionTime: 2.5,
                timestamp: Date(timeIntervalSince1970: 0),
                duration: 3.75
            )
        ])

        XCTAssertTrue(csv.hasPrefix(VoiceInkTranscriptionCSVExporter.header + "\n"))
        XCTAssertTrue(csv.contains("raw,enhanced,gpt,Assistant,Whisper,W Writing,1.25,2.5,"))
        XCTAssertTrue(csv.hasSuffix(",3.75\n"))
    }

    func testCSVStringUsesMacOSOptionalFallbacks() {
        let csv = VoiceInkTranscriptionCSVExporter.csvString(for: [
            VoiceInkTranscriptionCSVRecord(
                originalText: "raw",
                timestamp: Date(timeIntervalSince1970: 0),
                duration: 0
            )
        ])

        XCTAssertTrue(csv.contains("raw,,,,,,0.0,0.0,"))
    }

    func testEscapeCSVStringPreservesExistingMacOSQuotingPolicy() {
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.escapeCSVString("plain"), "plain")
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.escapeCSVString("hello, world"), "\"hello, world\"")
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.escapeCSVString("hello\nworld"), "\"hello\nworld\"")
        XCTAssertEqual(VoiceInkTranscriptionCSVExporter.escapeCSVString("he said \"yes\""), "he said \"\"yes\"\"")
    }

    func testCSVStringUsesSharedPowerModeDisplayName() {
        let csv = VoiceInkTranscriptionCSVExporter.csvString(for: [
            VoiceInkTranscriptionCSVRecord(
                originalText: "raw",
                powerModeName: " Writing ",
                powerModeEmoji: " W ",
                timestamp: Date(timeIntervalSince1970: 0),
                duration: 0
            )
        ])

        XCTAssertTrue(csv.contains("W Writing"))
    }

    private func candidate(
        id: UUID = UUID(),
        rawText: String,
        enhancedText: String? = nil,
        status: VoiceInkTranscriptionStatus? = .completed
    ) -> VoiceInkLastTranscriptionCandidate<UUID> {
        VoiceInkLastTranscriptionCandidate(
            id: id,
            rawText: rawText,
            enhancedText: enhancedText,
            status: status
        )
    }

    private func testDate(timeZone: TimeZone) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone,
            year: 2026,
            month: 6,
            day: 18,
            hour: 12,
            minute: 34
        ).date!
    }
}

private struct HistoryItem: Hashable {
    let id: Int
    let timestamp: Date
}

private struct HistorySelectionItem: Hashable {
    let id: Int
    let label: String
}

private struct TranscriptSearchItem: Hashable {
    let id: Int
    let rawText: String
    let enhancedText: String?
}
