import Foundation
@testable import VoiceInkCore

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

        XCTAssertEqual(Set(plan.targets), Set([first, second]))
        XCTAssertTrue(plan.remainingSelection.isEmpty)
        XCTAssertEqual(plan.targetIDs, Set([1, 2]))
    }

    func testHistoryDeletionPolicyPreservesUnselectedItemsWhenDeletingSubset() {
        let selected = HistorySelectionItem(id: 1, label: "selected")
        let kept = HistorySelectionItem(id: 2, label: "kept")

        let plan = VoiceInkHistoryDeletionPolicy.deleting(
            [selected],
            from: Set([selected, kept]),
            id: \.id
        )

        XCTAssertEqual(plan.targets, [selected])
        XCTAssertEqual(plan.remainingSelection, Set([kept]))
        XCTAssertEqual(plan.targetIDs, Set([selected.id]))
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

    func testHistoryRefreshPolicyReloadsForSearchTextChanges() {
        XCTAssertEqual(VoiceInkHistoryRefreshPolicy.searchTextDidChange(), .reload)
    }

    func testHistoryRefreshPolicyReloadsForVisibleLatestItemChanges() {
        XCTAssertEqual(
            VoiceInkHistoryRefreshPolicy.latestItemDidChange(
                oldID: 1,
                newID: 2,
                isViewVisible: true
            ),
            .reload
        )
    }

    func testHistoryRefreshPolicyIgnoresHiddenOrUnchangedLatestItemChanges() {
        XCTAssertEqual(
            VoiceInkHistoryRefreshPolicy.latestItemDidChange(
                oldID: 1,
                newID: 2,
                isViewVisible: false
            ),
            .ignore
        )
        XCTAssertEqual(
            VoiceInkHistoryRefreshPolicy.latestItemDidChange(
                oldID: 1,
                newID: 1,
                isViewVisible: true
            ),
            .ignore
        )
        XCTAssertEqual(
            VoiceInkHistoryRefreshPolicy.latestItemDidChange(
                oldID: Optional<Int>.none,
                newID: Optional<Int>.none,
                isViewVisible: true
            ),
            .ignore
        )
    }

    func testHistoryDeleteConfirmationPresentationPreservesMacOSAlertCopy() {
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationTitle, "Delete Selected Items?")
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationPrimaryButtonTitle, "Delete")
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationCancelButtonTitle, "Cancel")
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

    func testDeletionTargetsUseDisplayedListOffsets() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.deletionTargets(
                atOffsets: IndexSet([0, 2]),
                from: ["latest", "hidden-by-search", "oldest"]
            ),
            ["latest", "oldest"]
        )
    }

    func testDeletionTargetsIgnoreStaleOffsets() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.deletionTargets(
                atOffsets: IndexSet([1, 5]),
                from: ["latest", "oldest"]
            ),
            ["oldest"]
        )
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
        XCTAssertEqual(pending?.kind, .processing)
        XCTAssertEqual(pending?.title, "Transcription Pending")
        XCTAssertEqual(pending?.badgeText, "Processing")
        XCTAssertEqual(pending?.tone, .processing)
        XCTAssertEqual(pending?.panelSystemImageName, "clock.fill")
        XCTAssertEqual(pending?.inlineAccessory, .progress)

        let failed = VoiceInkTranscriptPresentation.statusPresentation(for: .failed)
        XCTAssertEqual(failed?.kind, .failed)
        XCTAssertEqual(failed?.title, "Transcription Failed")
        XCTAssertEqual(failed?.badgeText, "Failed")
        XCTAssertEqual(failed?.tone, .failure)
        XCTAssertEqual(failed?.panelSystemImageName, "exclamationmark.triangle.fill")
        XCTAssertEqual(failed?.inlineAccessory, .badge)
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
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.retryControls(for: .failed, isRetranscribing: false),
            VoiceInkTranscriptRetryControlsPresentation(
                shouldShowModeSelection: true,
                action: .showRetryButton
            )
        )
    }

    func testRetryControlsPresentationShowsProgressWhenRetranscribing() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.retryControls(for: .failed, isRetranscribing: true),
            VoiceInkTranscriptRetryControlsPresentation(
                shouldShowModeSelection: false,
                action: .showProgress,
                progressText: "Retranscribing..."
            )
        )
    }

    func testRetryControlsPresentationShowsPendingProgressWithoutRetryControls() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.retryControls(for: .pending, isRetranscribing: false),
            VoiceInkTranscriptRetryControlsPresentation(
                shouldShowModeSelection: false,
                action: .showProgress,
                progressText: "Transcribing..."
            )
        )
    }

    func testRetryControlsPresentationHidesControlsForTerminalNonFailedStates() {
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.retryControls(for: .completed, isRetranscribing: false),
            VoiceInkTranscriptRetryControlsPresentation(
                shouldShowModeSelection: false,
                action: .hidden
            )
        )
        XCTAssertEqual(
            VoiceInkTranscriptPresentation.retryControls(for: .canceled, isRetranscribing: false),
            VoiceInkTranscriptRetryControlsPresentation(
                shouldShowModeSelection: false,
                action: .hidden
            )
        )
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
}

private struct HistoryItem: Hashable {
    let id: Int
    let timestamp: Date
}

private struct HistorySelectionItem: Hashable {
    let id: Int
    let label: String
}
