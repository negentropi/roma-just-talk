import Foundation

public extension VoiceInkTranscriptionStatus {
    var needsTranscription: Bool {
        self == .pending || self == .failed
    }
}

public struct VoiceInkTranscriptStatusPresentation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case processing
        case failed
    }

    public enum Tone: Equatable, Sendable {
        case processing
        case failure
    }

    public let kind: Kind
    public let title: String
    public let badgeText: String

    public var isProcessing: Bool {
        kind == .processing
    }

    public var isFailure: Bool {
        kind == .failed
    }

    public var tone: Tone {
        switch kind {
        case .processing:
            return .processing
        case .failed:
            return .failure
        }
    }

    public var panelSystemImageName: String {
        switch kind {
        case .processing:
            return "clock.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    public var shouldShowInlineProgress: Bool {
        kind == .processing
    }

    public var shouldShowBadge: Bool {
        kind == .failed
    }

    public init(kind: Kind, title: String, badgeText: String) {
        self.kind = kind
        self.title = title
        self.badgeText = badgeText
    }
}

public struct VoiceInkHistoryEmptyStatePresentation: Equatable, Sendable {
    public let systemImageName: String
    public let title: String
    public let message: String?

    public init(systemImageName: String, title: String, message: String? = nil) {
        self.systemImageName = systemImageName
        self.title = title
        self.message = message
    }
}

public struct VoiceInkHistoryActionPresentation: Equatable, Sendable {
    public let title: String
    public let systemImageName: String

    public init(title: String, systemImageName: String) {
        self.title = title
        self.systemImageName = systemImageName
    }
}

public struct VoiceInkTranscriptionMetadataRowPresentation: Equatable, Sendable {
    public let label: String
    public let systemImageName: String

    public init(label: String, systemImageName: String) {
        self.label = label
        self.systemImageName = systemImageName
    }
}

public enum VoiceInkTranscriptTextVariant: String, CaseIterable, Sendable {
    case original
    case enhanced

    public var title: String {
        switch self {
        case .original:
            return "Original"
        case .enhanced:
            return "Enhanced"
        }
    }

    public static func shouldShowTabs(enhancedText: String?) -> Bool {
        enhancedText != nil
    }

    public func displayText(rawText: String, enhancedText: String?) -> String {
        switch self {
        case .original:
            return rawText
        case .enhanced:
            return enhancedText ?? ""
        }
    }
}

public enum VoiceInkTranscriptionMetadataPresentation {
    public static let detailsSectionTitle = "Details"
    public static let aiRequestSectionTitle = "AI Request"
    public static let systemPromptLabel = "System Prompt"
    public static let userMessageLabel = "User Message"

    public static let dateRow = VoiceInkTranscriptionMetadataRowPresentation(
        label: "Date",
        systemImageName: "calendar"
    )

    public static let durationRow = VoiceInkTranscriptionMetadataRowPresentation(
        label: "Duration",
        systemImageName: "hourglass"
    )

    public static let transcriptionModelRow = VoiceInkTranscriptionMetadataRowPresentation(
        label: "Transcription Model",
        systemImageName: "cpu.fill"
    )

    public static let transcriptionTimeRow = VoiceInkTranscriptionMetadataRowPresentation(
        label: "Transcription Time",
        systemImageName: "clock.fill"
    )

    public static let enhancementModelRow = VoiceInkTranscriptionMetadataRowPresentation(
        label: "Enhancement Model",
        systemImageName: "sparkles"
    )

    public static let enhancementTimeRow = VoiceInkTranscriptionMetadataRowPresentation(
        label: "Enhancement Time",
        systemImageName: "clock.fill"
    )

    public static let promptRow = VoiceInkTranscriptionMetadataRowPresentation(
        label: "Prompt",
        systemImageName: "text.bubble.fill"
    )

    public static let powerModeRow = VoiceInkTranscriptionMetadataRowPresentation(
        label: "Power Mode",
        systemImageName: "bolt.fill"
    )

    public static func shouldShowAIRequestSection(
        systemMessage: String?,
        userMessage: String?
    ) -> Bool {
        systemMessage != nil || userMessage != nil
    }

    public static func fullAIRequestText(
        systemMessage: String?,
        userMessage: String?
    ) -> String {
        var parts: [String] = []
        if let systemMessage, !systemMessage.isEmpty {
            parts.append("\(systemPromptLabel):\n\(systemMessage)")
        }
        if let userMessage, !userMessage.isEmpty {
            parts.append("\(userMessageLabel):\n\(userMessage)")
        }
        return parts.joined(separator: "\n\n")
    }
}

public enum VoiceInkHistoryPresentation {
    public static let macOSHistorySearchPrompt = "Search transcriptions"
    public static let macOSInlineHistorySearchPrompt = "Search transcriptions..."
    public static let loadingText = "Loading..."
    public static let loadMoreButtonTitle = "Load More"
    public static let selectAllButtonTitle = "Select All"
    public static let deselectAllButtonTitle = "Deselect All"
    public static let deleteConfirmationTitle = "Delete Selected Items?"
    public static let deleteConfirmationPrimaryButtonTitle = "Delete"
    public static let deleteConfirmationCancelButtonTitle = "Cancel"

    public static let analyzeAction = VoiceInkHistoryActionPresentation(
        title: "Analyze",
        systemImageName: "chart.bar.xaxis"
    )

    public static let exportAction = VoiceInkHistoryActionPresentation(
        title: "Export",
        systemImageName: "square.and.arrow.up"
    )

    public static let deleteAction = VoiceInkHistoryActionPresentation(
        title: "Delete",
        systemImageName: "trash"
    )

    public static let iOSNotesEmptyState = VoiceInkHistoryEmptyStatePresentation(
        systemImageName: "waveform",
        title: "No notes yet",
        message: "Tap Start Recording to capture your first note."
    )

    public static let macOSHistoryListEmptyState = VoiceInkHistoryEmptyStatePresentation(
        systemImageName: "doc.text.magnifyingglass",
        title: "No transcriptions"
    )

    public static let macOSNoSelectionEmptyState = VoiceInkHistoryEmptyStatePresentation(
        systemImageName: "doc.text",
        title: "No Selection",
        message: "Select a transcription to view details"
    )

    public static let macOSNoMetadataEmptyState = VoiceInkHistoryEmptyStatePresentation(
        systemImageName: "info.circle",
        title: "No Metadata"
    )

    public static func macOSInlineHistoryEmptyState(
        searchText: String
    ) -> VoiceInkHistoryEmptyStatePresentation {
        searchText.isEmpty
            ? VoiceInkHistoryEmptyStatePresentation(
                systemImageName: "doc.text.magnifyingglass",
                title: "No transcriptions yet",
                message: "Your transcription history will appear here"
            )
            : VoiceInkHistoryEmptyStatePresentation(
                systemImageName: "doc.text.magnifyingglass",
                title: "No results found",
                message: "Try a different search term"
            )
    }

    public static func loadingOrLoadMoreText(isLoading: Bool) -> String {
        isLoading ? loadingText : loadMoreButtonTitle
    }

    public static func selectedCountText(_ count: Int) -> String {
        "\(count) selected"
    }
}

public enum VoiceInkTranscriptPresentation {
    public static let pendingDisplayText = "New transcription"
    public static let failedDisplayText = "Transcription failed - tap to retry"
    public static let canceledDisplayText = "Transcription canceled"
    public static let emptyCompletedDisplayText = "No audible content detected."
    public static let emptyPreferredText = "No content available."
    public static let canceledTranscriptionText = "The transcription was canceled."
    public static let noteDetailNavigationTitle = "Note"
    public static let transcriptTitle = "Transcript"
    public static let copyTranscriptSystemImageName = "doc.on.doc"
    public static let retranscribingDisplayText = "Retranscribing..."
    public static let retryTranscriptionButtonTitle = "Retry Transcription"
    public static let retryTranscriptionSystemImageName = "arrow.clockwise"
    public static let noTranscriptionAvailableTitle = "No transcription available"
    public static let lastTranscriptionCopiedTitle = "Last transcription copied"
    public static let failedToCopyTranscriptionTitle = "Failed to copy transcription"
    public static let copiedToClipboardTitle = "Copied to clipboard"

    public static func preferredText(rawText: String, enhancedText: String?) -> String? {
        if let enhancedText, !enhancedText.isEmpty {
            return enhancedText
        }
        if !rawText.isEmpty {
            return rawText
        }
        return nil
    }

    public static func preferredTextOrEmptyContent(rawText: String, enhancedText: String?) -> String {
        preferredText(rawText: rawText, enhancedText: enhancedText) ?? emptyPreferredText
    }

    public static func transcriptActionText(
        selectedVariant: VoiceInkTranscriptTextVariant,
        isExpanded: Bool,
        rawText: String,
        enhancedText: String?
    ) -> String {
        if isExpanded {
            return selectedVariant.displayText(rawText: rawText, enhancedText: enhancedText)
        }
        return preferredText(rawText: rawText, enhancedText: enhancedText) ?? ""
    }

    public static func deleteConfirmationMessage(selectedCount: Int) -> String {
        "This action cannot be undone. Are you sure you want to delete \(selectedCount) item\(selectedCount == 1 ? "" : "s")?"
    }

    public static func failedTranscriptText(reason: String) -> String {
        "Transcription Failed: \(reason)"
    }

    public static func cannotRetryTitle(errorDescription: String) -> String {
        "Cannot retry: \(errorDescription)"
    }

    public static func retryFailedTitle(errorDescription: String) -> String {
        "Retry failed: \(errorDescription)"
    }

    public static let audioFileRetranscriptionSuccessMessage = "Retranscription successful"
    public static let audioFileReEnhancementSuccessMessage = "Re-enhancement successful"

    public static func audioFileRetranscriptionFailureMessage(errorDescription: String) -> String {
        errorDescription.isEmpty ? "Retranscription failed" : errorDescription
    }

    public static func audioFileReEnhancementFailureMessage(errorDescription: String) -> String {
        errorDescription.isEmpty ? "Re-enhancement failed" : errorDescription
    }

    public static func matchesSearch(rawText: String, enhancedText: String?, query: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        return rawText.localizedStandardContains(query) ||
            (enhancedText?.localizedStandardContains(query) ?? false)
    }

    public static func displayText(
        status: VoiceInkTranscriptionStatus,
        rawText: String,
        enhancedText: String?
    ) -> String {
        displayText(
            status: status,
            rawText: rawText,
            enhancedText: enhancedText,
            pendingText: pendingDisplayText,
            failedText: failedDisplayText,
            canceledText: canceledDisplayText,
            emptyCompletedText: emptyCompletedDisplayText
        )
    }

    public static func displayText(
        status: VoiceInkTranscriptionStatus,
        rawText: String,
        enhancedText: String?,
        pendingText: String,
        failedText: String,
        canceledText: String,
        emptyCompletedText: String
    ) -> String {
        switch status {
        case .pending:
            return pendingText
        case .failed:
            return failedText
        case .canceled:
            return canceledText
        case .completed:
            return preferredText(rawText: rawText, enhancedText: enhancedText) ?? emptyCompletedText
        }
    }

    public static func statusTitle(for status: VoiceInkTranscriptionStatus) -> String? {
        statusPresentation(for: status)?.title
    }

    public static func statusBadgeText(for status: VoiceInkTranscriptionStatus) -> String? {
        statusPresentation(for: status)?.badgeText
    }

    public static func statusPresentation(
        for status: VoiceInkTranscriptionStatus
    ) -> VoiceInkTranscriptStatusPresentation? {
        switch status {
        case .pending:
            return VoiceInkTranscriptStatusPresentation(
                kind: .processing,
                title: "Transcription Pending",
                badgeText: "Processing"
            )
        case .failed:
            return VoiceInkTranscriptStatusPresentation(
                kind: .failed,
                title: "Transcription Failed",
                badgeText: "Failed"
            )
        case .completed, .canceled:
            return nil
        }
    }

    public static func shouldShowStatusPanel(for status: VoiceInkTranscriptionStatus) -> Bool {
        statusPresentation(for: status) != nil
    }

    public static func shouldShowCompletedContent(for status: VoiceInkTranscriptionStatus) -> Bool {
        status == .completed
    }

    public static func isPasteable(
        rawText: String,
        statusRawValue: String?
    ) -> Bool {
        isPasteable(
            rawText: rawText,
            statusRawValue: statusRawValue,
            canceledText: canceledTranscriptionText
        )
    }

    public static func isPasteable(
        rawText: String,
        statusRawValue: String?,
        canceledText: String
    ) -> Bool {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty &&
            trimmedText != canceledText &&
            (statusRawValue == nil || statusRawValue == VoiceInkTranscriptionStatus.completed.rawValue)
    }
}
