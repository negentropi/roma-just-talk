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

    func testHistoryDeleteConfirmationPresentationPreservesMacOSAlertCopy() {
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationTitle, "Delete Selected Items?")
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationPrimaryButtonTitle, "Delete")
        XCTAssertEqual(VoiceInkHistoryPresentation.deleteConfirmationCancelButtonTitle, "Cancel")
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
        XCTAssertTrue(pending?.isProcessing == true)
        XCTAssertFalse(pending?.isFailure == true)
        XCTAssertEqual(pending?.tone, .processing)
        XCTAssertEqual(pending?.panelSystemImageName, "clock.fill")
        XCTAssertTrue(pending?.shouldShowInlineProgress == true)
        XCTAssertFalse(pending?.shouldShowBadge == true)

        let failed = VoiceInkTranscriptPresentation.statusPresentation(for: .failed)
        XCTAssertEqual(failed?.kind, .failed)
        XCTAssertEqual(failed?.title, "Transcription Failed")
        XCTAssertEqual(failed?.badgeText, "Failed")
        XCTAssertFalse(failed?.isProcessing == true)
        XCTAssertTrue(failed?.isFailure == true)
        XCTAssertEqual(failed?.tone, .failure)
        XCTAssertEqual(failed?.panelSystemImageName, "exclamationmark.triangle.fill")
        XCTAssertFalse(failed?.shouldShowInlineProgress == true)
        XCTAssertTrue(failed?.shouldShowBadge == true)
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

    func testDefaultPasteEligibilityRejectsCanceledTranscriptionText() {
        XCTAssertFalse(
            VoiceInkTranscriptPresentation.isPasteable(
                rawText: VoiceInkTranscriptPresentation.canceledTranscriptionText,
                statusRawValue: VoiceInkTranscriptionStatus.completed.rawValue
            )
        )
    }
}
