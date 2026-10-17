import Foundation
import RomaCore

final class TranscriptPresentationTests: XCTestCase {

    func testInlineHistoryEmptyStatePresentationPreservesSearchBranching() {
        XCTAssertEqual(
            RomaHistoryPresentation.macOSInlineHistoryEmptyState(searchText: ""),
            RomaHistoryEmptyStatePresentation(
                systemImageName: "doc.text.magnifyingglass",
                title: "No transcriptions yet",
                message: "Your transcription history will appear here"
            )
        )
        XCTAssertEqual(
            RomaHistoryPresentation.macOSInlineHistoryEmptyState(searchText: "invoice"),
            RomaHistoryEmptyStatePresentation(
                systemImageName: "doc.text.magnifyingglass",
                title: "No results found",
                message: "Try a different search term"
            )
        )
    }

    func testHistoryPaginationPolicyBuildsInitialPageState() {
        let first = HistoryItem(id: 1, timestamp: Date(timeIntervalSince1970: 200))
        let second = HistoryItem(id: 2, timestamp: Date(timeIntervalSince1970: 100))

        let plan = RomaHistoryPaginationPolicy.initialPage(
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

        let appended = RomaHistoryPaginationPolicy.appendingPage(
            currentItems: [current],
            newItems: [next],
            pageSize: 2,
            timestamp: \.timestamp
        )

        XCTAssertEqual(appended.displayedItems, [current, next])
        XCTAssertEqual(appended.lastTimestamp, next.timestamp)
        XCTAssertFalse(appended.hasMoreContent)
        XCTAssertFalse(appended.isLoading)

        let empty = RomaHistoryPaginationPolicy.appendingPage(
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
        let reset: RomaHistoryPaginationPlan<HistoryItem> = RomaHistoryPaginationPolicy.reset()

        XCTAssertTrue(reset.displayedItems.isEmpty)
        XCTAssertNil(reset.lastTimestamp)
        XCTAssertTrue(reset.hasMoreContent)
        XCTAssertFalse(reset.isLoading)
        XCTAssertEqual(
            RomaHistoryPaginationPolicy.loadMoreCursor(
                isLoading: false,
                hasMoreContent: true,
                lastTimestamp: timestamp
            ),
            timestamp
        )
        XCTAssertNil(RomaHistoryPaginationPolicy.loadMoreCursor(
            isLoading: true,
            hasMoreContent: true,
            lastTimestamp: timestamp
        ))
        XCTAssertNil(RomaHistoryPaginationPolicy.loadMoreCursor(
            isLoading: false,
            hasMoreContent: false,
            lastTimestamp: timestamp
        ))
        XCTAssertNil(RomaHistoryPaginationPolicy.loadMoreCursor(
            isLoading: false,
            hasMoreContent: true,
            lastTimestamp: nil
        ))
    }

    func testHistorySelectionPolicyOwnsToggleAndDisplayedSelectionState() {
        let first = HistorySelectionItem(id: 1, label: "first")
        let second = HistorySelectionItem(id: 2, label: "second")

        XCTAssertFalse(RomaHistorySelectionPolicy.areAllDisplayedItemsSelected(
            displayedItems: [first, second],
            selectedItems: [first]
        ))
        XCTAssertTrue(RomaHistorySelectionPolicy.areAllDisplayedItemsSelected(
            displayedItems: [first, second],
            selectedItems: [first, second]
        ))
        XCTAssertFalse(RomaHistorySelectionPolicy.areAllDisplayedItemsSelected(
            displayedItems: [HistorySelectionItem](),
            selectedItems: Set<HistorySelectionItem>()
        ))
        XCTAssertEqual(
            RomaHistorySelectionPolicy.toggling(second, in: [first]),
            [first, second]
        )
        XCTAssertEqual(
            RomaHistorySelectionPolicy.toggling(first, in: [first, second]),
            [second]
        )
    }

    func testHistorySelectionPolicySelectsAllWhilePreservingDisplayedInstances() {
        let visible = HistorySelectionItem(id: 1, label: "visible")
        let fetchedDuplicate = HistorySelectionItem(id: 1, label: "fetched duplicate")
        let hidden = HistorySelectionItem(id: 2, label: "hidden")

        let selection = RomaHistorySelectionPolicy.selectingAll(
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

        let plan = RomaHistoryDeletionPolicy.selectedItemsDeletionPlan(
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

        let plan = RomaHistoryDeletionPolicy.deleting(
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

        let plan = RomaHistoryDeletionPolicy.deleting(
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
        let plan = RomaHistoryDeletionPolicy.deleting(
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

        let plan = RomaHistoryDeletionPolicy.offsetDeletionPlan(
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
            historyRefreshEvents(for: RomaHistoryRefreshPolicy.searchTextDidChange()),
            ["reload"]
        )
    }

    func testHistoryRefreshPolicyReloadsForVisibleLatestItemChanges() {
        XCTAssertEqual(
            historyRefreshEvents(
                for: RomaHistoryRefreshPolicy.latestItemDidChange(
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
                for: RomaHistoryRefreshPolicy.latestItemDidChange(
                    oldID: 1,
                    newID: 2,
                    isViewVisible: false
                )
            ),
            []
        )
        XCTAssertEqual(
            historyRefreshEvents(
                for: RomaHistoryRefreshPolicy.latestItemDidChange(
                    oldID: 1,
                    newID: 1,
                    isViewVisible: true
                )
            ),
            []
        )
        XCTAssertEqual(
            historyRefreshEvents(
                for: RomaHistoryRefreshPolicy.latestItemDidChange(
                    oldID: Optional<Int>.none,
                    newID: Optional<Int>.none,
                    isViewVisible: true
                )
            ),
            []
        )
    }

    private func historyRefreshEvents(for plan: RomaHistoryRefreshPlan) -> [String] {
        var events: [String] = []
        plan.applyRuntimeState(
            reload: {
                events.append("reload")
            }
        )
        return events
    }

    func testTranscriptionMetadataPresentationPreservesMacOSDetailRows() {
        XCTAssertEqual(RomaTranscriptionMetadataPresentation.detailsSectionTitle, "Details")
        XCTAssertEqual(
            [
                RomaTranscriptionMetadataPresentation.dateRow,
                RomaTranscriptionMetadataPresentation.durationRow,
                RomaTranscriptionMetadataPresentation.transcriptionModelRow,
                RomaTranscriptionMetadataPresentation.transcriptionTimeRow,
                RomaTranscriptionMetadataPresentation.enhancementModelRow,
                RomaTranscriptionMetadataPresentation.enhancementTimeRow,
                RomaTranscriptionMetadataPresentation.promptRow,
                RomaTranscriptionMetadataPresentation.powerModeRow
            ],
            [
                RomaTranscriptionMetadataRowPresentation(label: "Date", systemImageName: "calendar"),
                RomaTranscriptionMetadataRowPresentation(label: "Duration", systemImageName: "hourglass"),
                RomaTranscriptionMetadataRowPresentation(label: "Transcription Model", systemImageName: "cpu.fill"),
                RomaTranscriptionMetadataRowPresentation(label: "Transcription Time", systemImageName: "clock.fill"),
                RomaTranscriptionMetadataRowPresentation(label: "Enhancement Model", systemImageName: "sparkles"),
                RomaTranscriptionMetadataRowPresentation(label: "Enhancement Time", systemImageName: "clock.fill"),
                RomaTranscriptionMetadataRowPresentation(label: "Prompt", systemImageName: "text.bubble.fill"),
                RomaTranscriptionMetadataRowPresentation(label: "Power Mode", systemImageName: "bolt.fill")
            ]
        )
    }

    func testTranscriptionMetadataPresentationPreservesAIRequestVisibilityRule() {
        XCTAssertFalse(
            RomaTranscriptionMetadataPresentation.shouldShowAIRequestSection(
                systemMessage: nil,
                userMessage: nil
            )
        )
        XCTAssertTrue(
            RomaTranscriptionMetadataPresentation.shouldShowAIRequestSection(
                systemMessage: "",
                userMessage: nil
            )
        )
        XCTAssertTrue(
            RomaTranscriptionMetadataPresentation.shouldShowAIRequestSection(
                systemMessage: nil,
                userMessage: ""
            )
        )
    }

    func testPreferredTextUsesEnhancedTextWhenPresent() {
        XCTAssertEqual(
            RomaTranscriptPresentation.preferredText(
                rawText: "raw transcript",
                enhancedText: "enhanced transcript"
            ),
            "enhanced transcript"
        )
    }

    func testPreferredTextFallsBackToRawTextWhenEnhancedTextIsEmpty() {
        XCTAssertEqual(
            RomaTranscriptPresentation.preferredText(
                rawText: "raw transcript",
                enhancedText: ""
            ),
            "raw transcript"
        )
    }

    func testPreferredTextReturnsNilWhenAllTextIsEmpty() {
        XCTAssertNil(
            RomaTranscriptPresentation.preferredText(
                rawText: "",
                enhancedText: nil
            )
        )
    }

    func testPreferredTextOrEmptyContentUsesSharedFallback() {
        XCTAssertEqual(
            RomaTranscriptPresentation.preferredTextOrEmptyContent(
                rawText: "",
                enhancedText: nil
            ),
            "No content available."
        )
    }

    func testTranscriptActionTextUsesPreferredTextWhenCollapsed() {
        XCTAssertEqual(
            RomaTranscriptPresentation.transcriptActionText(
                selectedVariant: .original,
                isExpanded: false,
                rawText: "raw transcript",
                enhancedText: "enhanced transcript"
            ),
            "enhanced transcript"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.transcriptActionText(
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
            RomaTranscriptPresentation.transcriptActionText(
                selectedVariant: .original,
                isExpanded: true,
                rawText: "raw transcript",
                enhancedText: "enhanced transcript"
            ),
            "raw transcript"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.transcriptActionText(
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
            RomaTranscriptPresentation.transcriptActionText(
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
            RomaTranscriptPresentation.deleteConfirmationMessage(selectedCount: 1),
            "This action cannot be undone. Are you sure you want to delete 1 item?"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.deleteConfirmationMessage(selectedCount: 2),
            "This action cannot be undone. Are you sure you want to delete 2 items?"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.deleteConfirmationMessage(selectedCount: 0),
            "This action cannot be undone. Are you sure you want to delete 0 items?"
        )
    }

    func testHistoryDeletionPolicyUsesDisplayedListOffsets() {
        let plan = RomaHistoryDeletionPolicy.offsetDeletionPlan(
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
        let plan = RomaHistoryDeletionPolicy.offsetDeletionPlan(
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
            RomaTranscriptPresentation.failedTranscriptText(reason: "No model selected"),
            "Transcription Failed: No model selected"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.failedTranscriptText(reason: "Audio file not found"),
            "Transcription Failed: Audio file not found"
        )
    }

    func testMatchesSearchReturnsTrueForEmptyQuery() {
        XCTAssertTrue(
            RomaTranscriptPresentation.matchesSearch(
                rawText: "Raw transcript",
                enhancedText: nil,
                query: ""
            )
        )
    }

    func testMatchesSearchChecksRawTextCaseInsensitively() {
        XCTAssertTrue(
            RomaTranscriptPresentation.matchesSearch(
                rawText: "Schedule the launch review",
                enhancedText: nil,
                query: "LAUNCH"
            )
        )
    }

    func testMatchesSearchChecksEnhancedTextCaseInsensitively() {
        XCTAssertTrue(
            RomaTranscriptPresentation.matchesSearch(
                rawText: "raw",
                enhancedText: "Follow up with design",
                query: "DESIGN"
            )
        )
    }

    func testMatchesSearchUsesMacOSStandardSearchSemantics() {
        XCTAssertTrue(
            RomaTranscriptPresentation.matchesSearch(
                rawText: "Cafe notes",
                enhancedText: nil,
                query: "café"
            )
        )
        XCTAssertTrue(
            RomaTranscriptPresentation.matchesSearch(
                rawText: "raw",
                enhancedText: "Review the résumé",
                query: "resume"
            )
        )
    }

    func testMatchesSearchReturnsFalseWhenQueryIsAbsent() {
        XCTAssertFalse(
            RomaTranscriptPresentation.matchesSearch(
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
            RomaTranscriptPresentation.filteredItems(
                notes,
                query: "café",
                rawText: \.rawText,
                enhancedText: \.enhancedText
            ).map(\.id),
            [1]
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.filteredItems(
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
            RomaTranscriptPresentation.filteredItems(
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
            RomaTranscriptPresentation.displayText(
                status: .pending,
                rawText: "",
                enhancedText: nil
            ),
            "New transcription"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.displayText(
                status: .failed,
                rawText: "",
                enhancedText: nil
            ),
            "Transcription failed - tap to retry"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.displayText(
                status: .canceled,
                rawText: "",
                enhancedText: nil
            ),
            "Transcription canceled"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.displayText(
                status: .completed,
                rawText: "",
                enhancedText: nil
            ),
            "No audible content detected."
        )
    }

    func testCustomDisplayTextStillAllowsShellFallbacks() {
        XCTAssertEqual(
            RomaTranscriptPresentation.displayText(
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
            RomaDatePresentation.abbreviatedTimestamp(
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
            RomaDatePresentation.compactTimestamp(
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
            RomaDatePresentation.relativeTimestamp(
                referenceDate.addingTimeInterval(-60),
                relativeTo: referenceDate,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "1 min. ago"
        )
        XCTAssertEqual(
            RomaDatePresentation.relativeTimestamp(
                referenceDate.addingTimeInterval(60),
                relativeTo: referenceDate,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "in 1 min."
        )
    }

    func testPositiveDurationVisibilityOnlyAllowsPositiveDurations() {
        XCTAssertEqual(RomaDurationPresentation.metadataSeparatorText, "•")
        XCTAssertFalse(RomaDurationPresentation.shouldShowPositiveDuration(-1))
        XCTAssertFalse(RomaDurationPresentation.shouldShowPositiveDuration(0))
        XCTAssertTrue(RomaDurationPresentation.shouldShowPositiveDuration(0.1))
    }

    func testMinutesSecondsUsesUnpaddedMinutesByDefault() {
        XCTAssertEqual(RomaDurationPresentation.minutesSeconds(5), "0:05")
        XCTAssertEqual(RomaDurationPresentation.minutesSeconds(65), "1:05")
    }

    func testMinutesSecondsCanPadMinutesToTwoDigits() {
        XCTAssertEqual(
            RomaDurationPresentation.minutesSeconds(5, padMinutesToTwoDigits: true),
            "00:05"
        )
        XCTAssertEqual(
            RomaDurationPresentation.minutesSeconds(65, padMinutesToTwoDigits: true),
            "01:05"
        )
    }

    func testMinutesSecondsTruncatesFractionalSeconds() {
        XCTAssertEqual(RomaDurationPresentation.minutesSeconds(65.9), "1:05")
    }

    func testAbbreviatedMinutesSecondsMatchesMetricsFormatting() {
        XCTAssertEqual(RomaDurationPresentation.abbreviatedMinutesSeconds(0), "0s")
        XCTAssertEqual(RomaDurationPresentation.abbreviatedMinutesSeconds(65), "1m 5s")
        XCTAssertEqual(RomaDurationPresentation.abbreviatedMinutesSeconds(125.6), "2m 5s")
    }

    func testPositiveDurationReturnsFallbackForZeroOrNegativeDurations() {
        XCTAssertEqual(
            RomaDurationPresentation.positiveDuration(0, style: .full, fallback: "Time savings coming soon"),
            "Time savings coming soon"
        )
        XCTAssertEqual(RomaDurationPresentation.positiveDuration(-1, style: .abbreviated), "–")
    }

    func testPositiveDurationUsesMinuteSecondUnitsBelowOneHour() {
        XCTAssertEqual(RomaDurationPresentation.positiveDuration(65, style: .abbreviated), "1m 5s")
    }

    func testPositiveDurationUsesHourMinuteUnitsFromOneHour() {
        XCTAssertEqual(RomaDurationPresentation.positiveDuration(3665, style: .abbreviated), "1h 1m")
    }

    func testCompactElapsedUsesMillisecondsForSubsecondDurations() {
        XCTAssertEqual(RomaDurationPresentation.compactElapsed(0.125), "125ms")
    }

    func testCompactElapsedUsesOneDecimalSecondsUnderOneMinute() {
        XCTAssertEqual(RomaDurationPresentation.compactElapsed(12.34), "12.3s")
    }

    func testCompactElapsedUsesMinutesAndRoundedSecondsFromOneMinute() {
        XCTAssertEqual(RomaDurationPresentation.compactElapsed(125.6), "2m 6s")
    }

    func testNoteRowPresentationBuildsCompletedIOSRow() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = referenceDate.addingTimeInterval(-300)
        let locale = Locale(identifier: "en_US_POSIX")

        let presentation = RomaNoteRowPresentation.make(
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
            RomaDatePresentation.relativeTimestamp(timestamp, relativeTo: referenceDate, locale: locale)
        )
        XCTAssertEqual(presentation.durationText, "02:05")
        XCTAssertEqual(presentation.metadataSeparatorText, RomaDurationPresentation.metadataSeparatorText)
        XCTAssertNil(presentation.statusPresentation)
    }

    func testNoteRowPresentationUsesStatusFallbacksForRetryStates() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let locale = Locale(identifier: "en_US_POSIX")

        let pending = RomaNoteRowPresentation.make(
            status: .pending,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: 0,
            referenceDate: referenceDate,
            locale: locale
        )
        let failed = RomaNoteRowPresentation.make(
            status: .failed,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: 0,
            referenceDate: referenceDate,
            locale: locale
        )
        let canceled = RomaNoteRowPresentation.make(
            status: .canceled,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: 0,
            referenceDate: referenceDate,
            locale: locale
        )

        XCTAssertEqual(pending.displayText, RomaTranscriptPresentation.pendingDisplayText)
        XCTAssertTrue(pending.statusPresentation?.shouldShowInlineProgress == true)
        XCTAssertEqual(failed.displayText, RomaTranscriptPresentation.failedDisplayText)
        XCTAssertTrue(failed.statusPresentation?.shouldShowInlineBadge == true)
        XCTAssertEqual(canceled.displayText, RomaTranscriptPresentation.canceledDisplayText)
        XCTAssertNil(canceled.statusPresentation)
    }

    func testNoteRowPresentationOmitsNonPositiveDuration() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

        let zeroDuration = RomaNoteRowPresentation.make(
            status: .completed,
            rawText: "raw transcript",
            enhancedText: nil,
            timestamp: referenceDate,
            duration: 0,
            referenceDate: referenceDate,
            locale: Locale(identifier: "en_US_POSIX")
        )
        let negativeDuration = RomaNoteRowPresentation.make(
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

        let presentation = RomaNoteDetailPresentation.make(
            status: .completed,
            rawText: "raw transcript",
            enhancedText: "enhanced transcript",
            transcriptionError: nil,
            isRetranscribing: false,
            audioAvailability: .available(audioURL),
            duration: 0
        )

        XCTAssertEqual(presentation.navigationTitle, RomaTranscriptPresentation.noteDetailNavigationTitle)
        XCTAssertEqual(presentation.transcriptContent?.title, RomaTranscriptPresentation.transcriptTitle)
        XCTAssertEqual(presentation.transcriptContent?.text, "enhanced transcript")
        XCTAssertEqual(
            presentation.transcriptContent?.copySystemImageName,
            RomaTranscriptPresentation.copyTranscriptSystemImageName
        )
        XCTAssertNil(presentation.statusPanel)
        XCTAssertEqual(presentation.audioAvailability, .available(audioURL))
        XCTAssertTrue(presentation.shouldShowAudioSection)
    }

    func testNoteDetailPresentationUsesRawTextWhenEnhancedTextIsEmpty() {
        let presentation = RomaNoteDetailPresentation.make(
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
        let presentation = RomaNoteDetailPresentation.make(
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
            RomaTranscriptPresentation.emptyPreferredText
        )
        XCTAssertNil(presentation.statusPanel)
        XCTAssertFalse(presentation.shouldShowAudioSection)
    }

    func testNoteDetailPresentationHidesCanceledContentAndStatusPanel() {
        let presentation = RomaNoteDetailPresentation.make(
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
        let presentation = RomaNoteDetailPresentation.make(
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
            RomaTranscriptPresentation.retryTranscriptionButtonTitle
        )
        XCTAssertEqual(
            presentation.statusPanel?.retryButtonSystemImageName,
            RomaTranscriptPresentation.retryTranscriptionSystemImageName
        )
        XCTAssertTrue(presentation.shouldShowAudioSection)
    }

    func testNoteDetailPresentationPreservesMissingAudioAvailability() {
        let missingURL = URL(fileURLWithPath: "/tmp/missing.wav")
        let presentation = RomaNoteDetailPresentation.make(
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
        let presentation = RomaNoteDetailPresentation.make(
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
            RomaTranscriptPresentation.transcribingDisplayText
        )
    }

    func testNoteDetailPresentationUsesRetranscribingProgressPanel() {
        let presentation = RomaNoteDetailPresentation.make(
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
            RomaTranscriptPresentation.retranscribingDisplayText
        )
    }

    func testStatusTitleReturnsRetryStateTitles() {
        XCTAssertEqual(
            RomaTranscriptPresentation.statusTitle(for: .pending),
            "Transcription Pending"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.statusTitle(for: .failed),
            "Transcription Failed"
        )
    }

    func testStatusTitleReturnsNilForNonRetryStates() {
        XCTAssertNil(RomaTranscriptPresentation.statusTitle(for: .completed))
        XCTAssertNil(RomaTranscriptPresentation.statusTitle(for: .canceled))
    }

    func testStatusBadgeTextReturnsRetryStateLabels() {
        XCTAssertEqual(
            RomaTranscriptPresentation.statusBadgeText(for: .pending),
            "Processing"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.statusBadgeText(for: .failed),
            "Failed"
        )
    }

    func testStatusBadgeTextReturnsNilForNonRetryStates() {
        XCTAssertNil(RomaTranscriptPresentation.statusBadgeText(for: .completed))
        XCTAssertNil(RomaTranscriptPresentation.statusBadgeText(for: .canceled))
    }

    func testStatusPresentationReturnsRetryStateMetadata() {
        let pending = RomaTranscriptPresentation.statusPresentation(for: .pending)
        XCTAssertEqual(pending?.title, "Transcription Pending")
        XCTAssertEqual(pending?.badgeText, "Processing")
        XCTAssertEqual(pending?.tone, .processing)
        XCTAssertEqual(pending?.panelSystemImageName, "clock.fill")
        XCTAssertEqual(pending?.shouldShowInlineProgress, true)
        XCTAssertEqual(pending?.shouldShowInlineBadge, false)

        let failed = RomaTranscriptPresentation.statusPresentation(for: .failed)
        XCTAssertEqual(failed?.title, "Transcription Failed")
        XCTAssertEqual(failed?.badgeText, "Failed")
        XCTAssertEqual(failed?.tone, .failure)
        XCTAssertEqual(failed?.panelSystemImageName, "exclamationmark.triangle.fill")
        XCTAssertEqual(failed?.shouldShowInlineProgress, false)
        XCTAssertEqual(failed?.shouldShowInlineBadge, true)
    }

    func testStatusPresentationContentVisibilityMatchesTranscriptState() {
        XCTAssertTrue(RomaTranscriptPresentation.shouldShowStatusPanel(for: .pending))
        XCTAssertTrue(RomaTranscriptPresentation.shouldShowStatusPanel(for: .failed))
        XCTAssertFalse(RomaTranscriptPresentation.shouldShowStatusPanel(for: .completed))
        XCTAssertFalse(RomaTranscriptPresentation.shouldShowStatusPanel(for: .canceled))

        XCTAssertTrue(RomaTranscriptPresentation.shouldShowCompletedContent(for: .completed))
        XCTAssertFalse(RomaTranscriptPresentation.shouldShowCompletedContent(for: .pending))
        XCTAssertFalse(RomaTranscriptPresentation.shouldShowCompletedContent(for: .failed))
        XCTAssertFalse(RomaTranscriptPresentation.shouldShowCompletedContent(for: .canceled))
    }

    func testStatusErrorDetailShowsOnlyNonEmptyErrors() {
        XCTAssertNil(RomaTranscriptPresentation.statusErrorDetail(nil))
        XCTAssertNil(RomaTranscriptPresentation.statusErrorDetail(""))
        XCTAssertEqual(
            RomaTranscriptPresentation.statusErrorDetail("Missing audio file"),
            "Missing audio file"
        )
    }

    func testRetryControlsPresentationShowsRetryControlsWhenIdle() {
        let presentation = RomaTranscriptPresentation.retryControls(for: .failed, isRetranscribing: false)

        XCTAssertTrue(presentation.shouldShowModeSelection)
        XCTAssertFalse(presentation.shouldShowProgress)
        XCTAssertNil(presentation.progressDisplayText)
    }

    func testRetryControlsPresentationShowsProgressWhenRetranscribing() {
        let presentation = RomaTranscriptPresentation.retryControls(for: .failed, isRetranscribing: true)

        XCTAssertFalse(presentation.shouldShowModeSelection)
        XCTAssertTrue(presentation.shouldShowProgress)
        XCTAssertEqual(presentation.progressDisplayText, "Retranscribing...")
    }

    func testRetryControlsPresentationShowsPendingProgressWithoutRetryControls() {
        let presentation = RomaTranscriptPresentation.retryControls(for: .pending, isRetranscribing: false)

        XCTAssertFalse(presentation.shouldShowModeSelection)
        XCTAssertTrue(presentation.shouldShowProgress)
        XCTAssertEqual(presentation.progressDisplayText, "Transcribing...")
    }

    func testRetryControlsPresentationHidesControlsForTerminalNonFailedStates() {
        let completed = RomaTranscriptPresentation.retryControls(for: .completed, isRetranscribing: false)
        XCTAssertFalse(completed.shouldShowModeSelection)
        XCTAssertFalse(completed.shouldShowProgress)
        XCTAssertNil(completed.progressDisplayText)
        XCTAssertNil(completed.runtimeAction {})

        let canceled = RomaTranscriptPresentation.retryControls(for: .canceled, isRetranscribing: false)
        XCTAssertFalse(canceled.shouldShowModeSelection)
        XCTAssertFalse(canceled.shouldShowProgress)
        XCTAssertNil(canceled.progressDisplayText)
        XCTAssertNil(canceled.runtimeAction {})
    }

    func testRetryControlsPresentationMapsRetryButtonToRuntimeRetry() {
        let presentation = RomaTranscriptPresentation.retryControls(for: .failed, isRetranscribing: false)
        var didRetry = false

        let retryAction = presentation.runtimeAction {
            didRetry = true
        }

        XCTAssertTrue(retryAction != nil)
        retryAction?()
        XCTAssertTrue(didRetry)

        XCTAssertNil(RomaTranscriptPresentation.retryControls(
            for: .failed,
            isRetranscribing: true
        ).runtimeAction {})
        XCTAssertNil(RomaTranscriptPresentation.retryControls(
            for: .pending,
            isRetranscribing: false
        ).runtimeAction {})
    }

    func testTranscriptTextVariantDisplayTextPreservesMacOSTabSelection() {
        XCTAssertEqual(
            RomaTranscriptTextVariant.original.displayText(
                rawText: "raw",
                enhancedText: "enhanced"
            ),
            "raw"
        )
        XCTAssertEqual(
            RomaTranscriptTextVariant.enhanced.displayText(
                rawText: "raw",
                enhancedText: "enhanced"
            ),
            "enhanced"
        )
        XCTAssertEqual(
            RomaTranscriptTextVariant.enhanced.displayText(
                rawText: "raw",
                enhancedText: nil
            ),
            ""
        )
    }

    func testTranscriptTextVariantTabVisibilityPreservesMacOSNilOnlyRule() {
        XCTAssertFalse(RomaTranscriptTextVariant.shouldShowTabs(enhancedText: nil))
        XCTAssertTrue(RomaTranscriptTextVariant.shouldShowTabs(enhancedText: ""))
        XCTAssertTrue(RomaTranscriptTextVariant.shouldShowTabs(enhancedText: "enhanced"))
    }

    func testLastTranscriptionPresentationPreservesMacOSNotificationCopy() {
        XCTAssertEqual(RomaTranscriptPresentation.noTranscriptionAvailableTitle, "No transcription available")
        XCTAssertEqual(RomaTranscriptPresentation.lastTranscriptionCopiedTitle, "Last transcription copied")
        XCTAssertEqual(RomaTranscriptPresentation.failedToCopyTranscriptionTitle, "Failed to copy transcription")
        XCTAssertEqual(RomaTranscriptPresentation.copiedToClipboardTitle, "Copied to clipboard")
        XCTAssertEqual(
            RomaTranscriptPresentation.cannotRetryTitle(errorDescription: "Audio file not found"),
            "Cannot retry: Audio file not found"
        )
        XCTAssertEqual(
            RomaTranscriptPresentation.retryFailedTitle(errorDescription: "provider unavailable"),
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
            candidate(rawText: RomaTranscriptPresentation.canceledTranscriptionText, status: .canceled),
            candidate(id: expected, rawText: "legacy usable", status: nil)
        ]

        XCTAssertEqual(
            RomaLastTranscriptionPolicy.firstPasteableCandidate(
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
            RomaLastTranscriptionPolicy.firstPasteableCandidate(in: candidates)?.id,
            newest
        )
    }

    func testPasteTextUsesOriginalOrEnhancedFallbackPolicy() {
        let enhanced = candidate(rawText: "raw text", enhancedText: "enhanced text")
        let rawOnly = candidate(rawText: "raw text", enhancedText: nil)

        XCTAssertEqual(
            RomaLastTranscriptionPolicy.pasteText(for: enhanced, preference: .original),
            "raw text"
        )
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.pasteText(for: enhanced, preference: .preferred),
            "enhanced text"
        )
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.pasteText(for: rawOnly, preference: .preferred),
            "raw text"
        )
    }

    func testFetchLimitPreservesMacOSLastTranscriptionFetchWindow() {
        XCTAssertEqual(RomaLastTranscriptionPolicy.fetchLimit, 20)
    }

    func testLastTranscriptionNotificationPresentationsPreserveCopyOutcomes() {
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.noTranscriptionNotification,
            RomaLastTranscriptionNotificationPresentation(
                title: "No transcription available",
                kind: .error
            )
        )
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.copyCompletionNotification(didCopy: true),
            RomaLastTranscriptionNotificationPresentation(
                title: "Last transcription copied",
                kind: .success
            )
        )
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.copyCompletionNotification(didCopy: false),
            RomaLastTranscriptionNotificationPresentation(
                title: "Failed to copy transcription",
                kind: .error
            )
        )
    }

    func testLastTranscriptionRetryNotificationPresentationsPreserveMacOSCopy() {
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.retryPreflightFailureNotification(.missingAudio),
            RomaLastTranscriptionNotificationPresentation(
                title: "Cannot retry: Audio file not found",
                kind: .error
            )
        )
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.retryPreflightFailureNotification(.noTranscriptionModelSelected),
            RomaLastTranscriptionNotificationPresentation(
                title: "No transcription model selected",
                kind: .error
            )
        )
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.retrySuccessNotification,
            RomaLastTranscriptionNotificationPresentation(
                title: "Copied to clipboard",
                kind: .success
            )
        )
        XCTAssertEqual(
            RomaLastTranscriptionPolicy.retryFailureNotification(errorDescription: "provider unavailable"),
            RomaLastTranscriptionNotificationPresentation(
                title: "Retry failed: provider unavailable",
                kind: .error
            )
        )
    }

    func testPostProcessingFailureTextPreservesExistingIOSRetryPrefix() {
        XCTAssertEqual(
            RomaPostProcessingFailurePresentation.postProcessingFailureText(reason: "provider down"),
            "Post-processing failed: provider down"
        )
    }

    func testEnhancementFailureTextPreservesExistingMacOSPrefix() {
        XCTAssertEqual(
            RomaPostProcessingFailurePresentation.enhancementFailureText(reason: "provider down"),
            "Enhancement failed: provider down"
        )
    }

    func testEnhancementFailureNotificationTitlePreservesEightyCharacterReasonLimit() {
        let reason = String(repeating: "a", count: 100)
        let title = RomaPostProcessingFailurePresentation.enhancementFailureNotificationTitle(reason: reason)

        XCTAssertEqual(title, "Enhancement failed: \(String(repeating: "a", count: 80))")
    }

    func testEnhancementFailureNotificationTitleClampsNegativeReasonLimit() {
        XCTAssertEqual(
            RomaPostProcessingFailurePresentation.enhancementFailureNotificationTitle(
                reason: "provider down",
                reasonLimit: -1
            ),
            "Enhancement failed: "
        )
    }

    func testDefaultPasteEligibilityRejectsCanceledTranscriptionText() {
        XCTAssertFalse(
            RomaTranscriptPresentation.isPasteable(
                rawText: RomaTranscriptPresentation.canceledTranscriptionText,
                statusRawValue: RomaTranscriptionStatus.completed.rawValue
            )
        )
    }

    func testTranscriptFileExportPreservesMacOSFileExtensions() {
        XCTAssertEqual(RomaTranscriptFileExport.plainTextFileExtension, "txt")
        XCTAssertEqual(RomaTranscriptFileExport.markdownFileExtension, "md")
    }

    func testSuggestedBaseFilenameUsesFallbackForBlankOrPunctuationOnlyText() {
        XCTAssertEqual(
            RomaTranscriptFileExport.suggestedBaseFilename(for: " \n\t "),
            "transcription"
        )
        XCTAssertEqual(
            RomaTranscriptFileExport.suggestedBaseFilename(for: "!!!"),
            "transcription"
        )
    }

    func testSuggestedBaseFilenamePreservesMacOSWordSelectionPolicy() {
        XCTAssertEqual(
            RomaTranscriptFileExport.suggestedBaseFilename(for: "One two three"),
            "one-two-three"
        )
        XCTAssertEqual(
            RomaTranscriptFileExport.suggestedBaseFilename(for: "One two three four"),
            "one-two-three-four"
        )
        XCTAssertEqual(
            RomaTranscriptFileExport.suggestedBaseFilename(for: "One two three four five six seven"),
            "one-two-three-four-five-six-seven"
        )
        XCTAssertEqual(
            RomaTranscriptFileExport.suggestedBaseFilename(for: "One two three four five six seven eight nine"),
            "one-two-three-four-five-six-seven-eight"
        )
    }

    func testSuggestedBaseFilenameSanitizesAndLimitsLength() {
        XCTAssertEqual(
            RomaTranscriptFileExport.suggestedBaseFilename(for: "Hello, ROMA!\nJust talk."),
            "hello-roma-just-talk"
        )

        let longName = RomaTranscriptFileExport.suggestedBaseFilename(
            for: "Supercalifragilisticexpialidocious abcdefghijklmnopqrstuvwxyz extra words"
        )

        XCTAssertEqual(longName.count, 50)
        XCTAssertEqual(longName, "supercalifragilisticexpialidocious-abcdefghijklmno")
    }

    func testMarkdownContentPreservesMacOSBodyShape() {
        XCTAssertEqual(
            RomaTranscriptFileExport.markdownContent(
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
            RomaTranscriptFileExport.markdownContent(
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

    func testCSVStringPreservesMacOSHeaderAndColumnOrder() {
        let csv = RomaTranscriptionCSVExporter.csvString(for: [
            RomaTranscriptionCSVRecord(
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

        XCTAssertTrue(csv.hasPrefix(RomaTranscriptionCSVExporter.header + "\n"))
        XCTAssertTrue(csv.contains("raw,enhanced,gpt,Assistant,Whisper,W Writing,1.25,2.5,"))
        XCTAssertTrue(csv.hasSuffix(",3.75\n"))
    }

    func testCSVStringUsesMacOSOptionalFallbacks() {
        let csv = RomaTranscriptionCSVExporter.csvString(for: [
            RomaTranscriptionCSVRecord(
                originalText: "raw",
                timestamp: Date(timeIntervalSince1970: 0),
                duration: 0
            )
        ])

        XCTAssertTrue(csv.contains("raw,,,,,,0.0,0.0,"))
    }

    func testEscapeCSVStringPreservesExistingMacOSQuotingPolicy() {
        XCTAssertEqual(RomaTranscriptionCSVExporter.escapeCSVString("plain"), "plain")
        XCTAssertEqual(RomaTranscriptionCSVExporter.escapeCSVString("hello, world"), "\"hello, world\"")
        XCTAssertEqual(RomaTranscriptionCSVExporter.escapeCSVString("hello\nworld"), "\"hello\nworld\"")
        XCTAssertEqual(RomaTranscriptionCSVExporter.escapeCSVString("he said \"yes\""), "he said \"\"yes\"\"")
    }

    func testCSVStringUsesSharedPowerModeDisplayName() {
        let csv = RomaTranscriptionCSVExporter.csvString(for: [
            RomaTranscriptionCSVRecord(
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
        status: RomaTranscriptionStatus? = .completed
    ) -> RomaLastTranscriptionCandidate<UUID> {
        RomaLastTranscriptionCandidate(
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
