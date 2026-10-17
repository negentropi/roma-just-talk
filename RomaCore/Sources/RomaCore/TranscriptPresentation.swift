import Foundation

public enum RomaDatePresentation {
    public static func abbreviatedTimestamp(
        _ date: Date,
        locale: Locale = .current,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        date.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        ))
    }

    public static func compactTimestamp(
        _ date: Date,
        locale: Locale = .current,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        date.formatted(Date.FormatStyle(
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        .month(.abbreviated)
        .day()
        .hour()
        .minute())
    }

    public static func relativeTimestamp(
        _ date: Date,
        relativeTo referenceDate: Date = Date(),
        locale: Locale = .current
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

public enum RomaDurationPresentation {
    public static let metadataSeparatorText = "•"

    public static func shouldShowPositiveDuration(_ duration: TimeInterval) -> Bool {
        duration > 0
    }

    public static func minutesSeconds(
        _ duration: TimeInterval,
        padMinutesToTwoDigits: Bool = false
    ) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let format = padMinutesToTwoDigits ? "%02d:%02d" : "%d:%02d"
        return String(format: format, minutes, seconds)
    }

    public static func abbreviatedMinutesSeconds(
        _ duration: TimeInterval,
        fallback: String = "0s"
    ) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? fallback
    }

    public static func positiveDuration(
        _ duration: TimeInterval,
        style: DateComponentsFormatter.UnitsStyle,
        fallback: String = "–"
    ) -> String {
        guard duration > 0 else { return fallback }

        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = style
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute, .second]
        return formatter.string(from: duration) ?? fallback
    }

    public static func compactElapsed(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }

        if duration < 60 {
            return String(format: "%.1fs", duration)
        }

        let minutes = Int(duration) / 60
        let seconds = duration.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.0fs", minutes, seconds)
    }
}

public enum RomaTranscriptFileExport {
    public static let defaultBaseFilename = "transcription"
    public static let plainTextFileExtension = "txt"
    public static let markdownFileExtension = "md"

    public static func suggestedBaseFilename(for text: String) -> String {
        let cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let words = cleanedText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let wordCount = min(words.count, words.count <= 3 ? words.count : (words.count <= 6 ? 6 : 8))
        let selectedWords = Array(words.prefix(wordCount))

        if selectedWords.isEmpty { return defaultBaseFilename }

        let fileName = selectedWords.joined(separator: "-")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return fileName.isEmpty ? defaultBaseFilename : String(fileName.prefix(50))
    }

    public static func markdownContent(
        for text: String,
        date: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        markdownContent(
            for: text,
            timestamp: timestampString(for: date, locale: locale, timeZone: timeZone)
        )
    }

    public static func markdownContent(for text: String, timestamp: String) -> String {
        """
        # Transcription

        **Date:** \(timestamp)

        \(text)
        """
    }

    static func timestampString(for date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

public struct RomaTranscriptionCSVRecord: Equatable, Sendable {
    public let originalText: String
    public let enhancedText: String?
    public let enhancementModel: String?
    public let promptName: String?
    public let transcriptionModel: String?
    public let powerModeName: String?
    public let powerModeEmoji: String?
    public let enhancementTime: Double?
    public let transcriptionTime: Double?
    public let timestamp: Date
    public let duration: Double

    public init(
        originalText: String,
        enhancedText: String? = nil,
        enhancementModel: String? = nil,
        promptName: String? = nil,
        transcriptionModel: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        enhancementTime: Double? = nil,
        transcriptionTime: Double? = nil,
        timestamp: Date,
        duration: Double
    ) {
        self.originalText = originalText
        self.enhancedText = enhancedText
        self.enhancementModel = enhancementModel
        self.promptName = promptName
        self.transcriptionModel = transcriptionModel
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
        self.enhancementTime = enhancementTime
        self.transcriptionTime = transcriptionTime
        self.timestamp = timestamp
        self.duration = duration
    }
}

public enum RomaTranscriptionCSVExporter {
    public static let defaultFilename = "roma-just-talk-transcription.csv"
    public static let writeFailurePrefix = "Error writing CSV file:"
    public static let header = "Original Transcript,Enhanced Transcript,Enhancement Model,Prompt Name,Transcription Model,Power Mode,Enhancement Time,Transcription Time,Timestamp,Duration"

    public static func writeFailureDiagnosticMessage(errorDescription: String) -> String {
        "\(writeFailurePrefix) \(errorDescription)"
    }

    public static func csvString(for records: [RomaTranscriptionCSVRecord]) -> String {
        var csvString = header + "\n"

        for record in records {
            let row = [
                escapeCSVString(record.originalText),
                escapeCSVString(record.enhancedText ?? ""),
                escapeCSVString(record.enhancementModel ?? ""),
                escapeCSVString(record.promptName ?? ""),
                escapeCSVString(record.transcriptionModel ?? ""),
                escapeCSVString(
                    RomaPowerModePresentation.displayName(
                        name: record.powerModeName,
                        emoji: record.powerModeEmoji
                    )
                ),
                "\(record.enhancementTime ?? 0)",
                "\(record.transcriptionTime ?? 0)",
                record.timestamp.ISO8601Format(),
                "\(record.duration)"
            ].joined(separator: ",")

            csvString.append(row)
            csvString.append("\n")
        }

        return csvString
    }

    public static func escapeCSVString(_ string: String) -> String {
        let escapedString = string.replacingOccurrences(of: "\"", with: "\"\"")
        if escapedString.contains(",") || escapedString.contains("\n") {
            return "\"\(escapedString)\""
        }
        return escapedString
    }
}

public extension RomaTranscriptionStatus {
    var needsTranscription: Bool {
        self == .pending || self == .failed
    }
}

public struct RomaTranscriptStatusPresentation: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case processing
        case failed
    }

    public enum Tone: Equatable, Sendable {
        case processing
        case failure
    }

    enum InlineAccessory: Equatable, Sendable {
        case progress
        case badge
    }

    let kind: Kind
    public let title: String
    public let badgeText: String

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

    var inlineAccessory: InlineAccessory {
        switch kind {
        case .processing:
            return .progress
        case .failed:
            return .badge
        }
    }

    init(kind: Kind, title: String, badgeText: String) {
        self.kind = kind
        self.title = title
        self.badgeText = badgeText
    }

    public var shouldShowInlineProgress: Bool {
        inlineAccessory == .progress
    }

    public var shouldShowInlineBadge: Bool {
        inlineAccessory == .badge
    }
}

public struct RomaNoteRowPresentation: Equatable, Sendable {
    public let displayText: String
    public let timestampText: String
    public let durationText: String?
    public let metadataSeparatorText: String?
    public let statusPresentation: RomaTranscriptStatusPresentation?

    public init(
        displayText: String,
        timestampText: String,
        durationText: String?,
        metadataSeparatorText: String?,
        statusPresentation: RomaTranscriptStatusPresentation?
    ) {
        self.displayText = displayText
        self.timestampText = timestampText
        self.durationText = durationText
        self.metadataSeparatorText = metadataSeparatorText
        self.statusPresentation = statusPresentation
    }

    public static func make(
        status: RomaTranscriptionStatus,
        rawText: String,
        enhancedText: String?,
        timestamp: Date,
        duration: TimeInterval,
        referenceDate: Date = Date(),
        locale: Locale = .current
    ) -> RomaNoteRowPresentation {
        let durationText = RomaDurationPresentation.shouldShowPositiveDuration(duration)
            ? RomaDurationPresentation.minutesSeconds(duration, padMinutesToTwoDigits: true)
            : nil

        return RomaNoteRowPresentation(
            displayText: RomaTranscriptPresentation.displayText(
                status: status,
                rawText: rawText,
                enhancedText: enhancedText
            ),
            timestampText: RomaDatePresentation.relativeTimestamp(
                timestamp,
                relativeTo: referenceDate,
                locale: locale
            ),
            durationText: durationText,
            metadataSeparatorText: durationText == nil ? nil : RomaDurationPresentation.metadataSeparatorText,
            statusPresentation: RomaTranscriptPresentation.statusPresentation(for: status)
        )
    }
}

public struct RomaTranscriptContentPresentation: Equatable, Sendable {
    public let title: String
    public let text: String
    public let copySystemImageName: String

    public init(title: String, text: String, copySystemImageName: String) {
        self.title = title
        self.text = text
        self.copySystemImageName = copySystemImageName
    }
}

public struct RomaNoteDetailStatusPanelPresentation: Equatable, Sendable {
    public let statusPresentation: RomaTranscriptStatusPresentation
    public let errorDetail: String?
    public let retryControls: RomaTranscriptRetryControlsPresentation
    public let retryButtonTitle: String
    public let retryButtonSystemImageName: String

    public init(
        statusPresentation: RomaTranscriptStatusPresentation,
        errorDetail: String?,
        retryControls: RomaTranscriptRetryControlsPresentation,
        retryButtonTitle: String,
        retryButtonSystemImageName: String
    ) {
        self.statusPresentation = statusPresentation
        self.errorDetail = errorDetail
        self.retryControls = retryControls
        self.retryButtonTitle = retryButtonTitle
        self.retryButtonSystemImageName = retryButtonSystemImageName
    }
}

public struct RomaNoteDetailPresentation: Equatable, Sendable {
    public let navigationTitle: String
    public let transcriptContent: RomaTranscriptContentPresentation?
    public let statusPanel: RomaNoteDetailStatusPanelPresentation?
    public let audioAvailability: RomaStoredAudioAvailability
    public let shouldShowAudioSection: Bool

    public init(
        navigationTitle: String,
        transcriptContent: RomaTranscriptContentPresentation?,
        statusPanel: RomaNoteDetailStatusPanelPresentation?,
        audioAvailability: RomaStoredAudioAvailability,
        shouldShowAudioSection: Bool
    ) {
        self.navigationTitle = navigationTitle
        self.transcriptContent = transcriptContent
        self.statusPanel = statusPanel
        self.audioAvailability = audioAvailability
        self.shouldShowAudioSection = shouldShowAudioSection
    }

    public static func make(
        status: RomaTranscriptionStatus,
        rawText: String,
        enhancedText: String?,
        transcriptionError: String?,
        isRetranscribing: Bool,
        canCancel: Bool = false,
        audioAvailability: RomaStoredAudioAvailability,
        duration: TimeInterval
    ) -> RomaNoteDetailPresentation {
        let transcriptContent = RomaTranscriptPresentation.shouldShowCompletedContent(for: status)
            ? RomaTranscriptContentPresentation(
                title: RomaTranscriptPresentation.transcriptTitle,
                text: RomaTranscriptPresentation.preferredTextOrEmptyContent(
                    rawText: rawText,
                    enhancedText: enhancedText
                ),
                copySystemImageName: RomaTranscriptPresentation.copyTranscriptSystemImageName
            )
            : nil

        let statusPanel = RomaTranscriptPresentation.statusPresentation(for: status).map { statusPresentation in
            RomaNoteDetailStatusPanelPresentation(
                statusPresentation: statusPresentation,
                errorDetail: RomaTranscriptPresentation.statusErrorDetail(transcriptionError),
                retryControls: RomaTranscriptPresentation.retryControls(
                    for: status,
                    isRetranscribing: isRetranscribing,
                    canCancel: canCancel
                ),
                retryButtonTitle: RomaTranscriptPresentation.retryTranscriptionButtonTitle,
                retryButtonSystemImageName: RomaTranscriptPresentation.retryTranscriptionSystemImageName
            )
        }

        return RomaNoteDetailPresentation(
            navigationTitle: RomaTranscriptPresentation.noteDetailNavigationTitle,
            transcriptContent: transcriptContent,
            statusPanel: statusPanel,
            audioAvailability: audioAvailability,
            shouldShowAudioSection: audioAvailability.shouldShowAudioSection(duration: duration)
        )
    }
}

enum RomaTranscriptRetryControlAction: Equatable, Sendable {
    case hidden
    case showProgress
    case showRetryButton

    func runtimeAction(
        retry: @escaping () -> Void
    ) -> (() -> Void)? {
        switch self {
        case .hidden,
             .showProgress:
            return nil
        case .showRetryButton:
            return retry
        }
    }
}

public struct RomaTranscriptRetryControlsPresentation: Equatable, Sendable {
    public let shouldShowModeSelection: Bool
    public let shouldShowCancelButton: Bool
    let action: RomaTranscriptRetryControlAction
    let progressText: String?

    init(
        shouldShowModeSelection: Bool,
        shouldShowCancelButton: Bool = false,
        action: RomaTranscriptRetryControlAction,
        progressText: String? = nil
    ) {
        self.shouldShowModeSelection = shouldShowModeSelection
        self.shouldShowCancelButton = shouldShowCancelButton
        self.action = action
        self.progressText = progressText
    }

    public var shouldShowProgress: Bool {
        action == .showProgress
    }

    public var progressDisplayText: String? {
        shouldShowProgress ? progressText : nil
    }

    public func runtimeAction(
        retry: @escaping () -> Void
    ) -> (() -> Void)? {
        action.runtimeAction(retry: retry)
    }
}

public struct RomaHistoryEmptyStatePresentation: Equatable, Sendable {
    public let systemImageName: String
    public let title: String
    public let message: String?

    public init(systemImageName: String, title: String, message: String? = nil) {
        self.systemImageName = systemImageName
        self.title = title
        self.message = message
    }
}

public struct RomaHistoryActionPresentation: Equatable, Sendable {
    public let title: String
    public let systemImageName: String

    public init(title: String, systemImageName: String) {
        self.title = title
        self.systemImageName = systemImageName
    }
}

public struct RomaHistoryShortcutTipPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let shortcutLabel: String
    public let systemImageName: String

    public init(
        title: String,
        subtitle: String,
        shortcutLabel: String,
        systemImageName: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.shortcutLabel = shortcutLabel
        self.systemImageName = systemImageName
    }
}

public struct RomaTranscriptionMetadataRowPresentation: Equatable, Sendable {
    public let label: String
    public let systemImageName: String

    public init(label: String, systemImageName: String) {
        self.label = label
        self.systemImageName = systemImageName
    }
}

public enum RomaTranscriptTextVariant: String, CaseIterable, Sendable {
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

public enum RomaTranscriptionMetadataPresentation {
    public static let detailsSectionTitle = "Details"
    public static let aiRequestSectionTitle = "AI Request"
    public static let systemPromptLabel = "System Prompt"
    public static let userMessageLabel = "User Message"

    public static let dateRow = RomaTranscriptionMetadataRowPresentation(
        label: "Date",
        systemImageName: "calendar"
    )

    public static let durationRow = RomaTranscriptionMetadataRowPresentation(
        label: "Duration",
        systemImageName: "hourglass"
    )

    public static let transcriptionModelRow = RomaTranscriptionMetadataRowPresentation(
        label: "Transcription Model",
        systemImageName: "cpu.fill"
    )

    public static let transcriptionTimeRow = RomaTranscriptionMetadataRowPresentation(
        label: "Transcription Time",
        systemImageName: "clock.fill"
    )

    public static let enhancementModelRow = RomaTranscriptionMetadataRowPresentation(
        label: "Enhancement Model",
        systemImageName: "sparkles"
    )

    public static let enhancementTimeRow = RomaTranscriptionMetadataRowPresentation(
        label: "Enhancement Time",
        systemImageName: "clock.fill"
    )

    public static let promptRow = RomaTranscriptionMetadataRowPresentation(
        label: "Prompt",
        systemImageName: "text.bubble.fill"
    )

    public static let powerModeRow = RomaTranscriptionMetadataRowPresentation(
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

public enum RomaHistoryPresentation {
    public static let macOSHistorySearchPrompt = "Search transcriptions"
    public static let macOSInlineHistorySearchPrompt = "Search transcriptions..."
    public static let loadingText = "Loading..."
    public static let loadMoreButtonTitle = "Load More"
    public static let selectAllButtonTitle = "Select All"
    public static let deselectAllButtonTitle = "Deselect All"
    public static let deleteConfirmationTitle = "Delete Selected Items?"
    public static let deleteConfirmationPrimaryButtonTitle = "Delete"
    public static let deleteConfirmationCancelButtonTitle = "Cancel"
    public static let macOSShortcutTip = RomaHistoryShortcutTipPresentation(
        title: "Quick Access",
        subtitle: "Open history from anywhere with a global shortcut",
        shortcutLabel: "Open History Window",
        systemImageName: "command.circle"
    )

    public static let analyzeAction = RomaHistoryActionPresentation(
        title: "Analyze",
        systemImageName: "chart.bar.xaxis"
    )

    public static let exportAction = RomaHistoryActionPresentation(
        title: "Export",
        systemImageName: "square.and.arrow.up"
    )

    public static let deleteAction = RomaHistoryActionPresentation(
        title: "Delete",
        systemImageName: "trash"
    )

    public static let iOSNotesEmptyState = RomaHistoryEmptyStatePresentation(
        systemImageName: "waveform",
        title: "No notes yet",
        message: "Tap Start Recording to capture your first note."
    )

    public static let macOSHistoryListEmptyState = RomaHistoryEmptyStatePresentation(
        systemImageName: "doc.text.magnifyingglass",
        title: "No transcriptions"
    )

    public static let macOSNoSelectionEmptyState = RomaHistoryEmptyStatePresentation(
        systemImageName: "doc.text",
        title: "No Selection",
        message: "Select a transcription to view details"
    )

    public static let macOSNoMetadataEmptyState = RomaHistoryEmptyStatePresentation(
        systemImageName: "info.circle",
        title: "No Metadata"
    )

    public static func macOSInlineHistoryEmptyState(
        searchText: String
    ) -> RomaHistoryEmptyStatePresentation {
        searchText.isEmpty
            ? RomaHistoryEmptyStatePresentation(
                systemImageName: "doc.text.magnifyingglass",
                title: "No transcriptions yet",
                message: "Your transcription history will appear here"
            )
            : RomaHistoryEmptyStatePresentation(
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

public enum RomaHistoryDiagnostics {
    public static func initialLoadFailedMessage(errorDescription: String) -> String {
        "Error loading transcriptions: \(errorDescription)"
    }

    public static func loadMoreFailedMessage(errorDescription: String) -> String {
        "Error loading more transcriptions: \(errorDescription)"
    }

    public static func saveDeletionFailedMessage(localizedDescription: String) -> String {
        "Error saving deletion: \(localizedDescription)"
    }

    public static func selectAllFailedMessage(errorDescription: String) -> String {
        "Error selecting all transcriptions: \(errorDescription)"
    }
}

public struct RomaHistoryPaginationPlan<Item> {
    public let displayedItems: [Item]
    public let lastTimestamp: Date?
    public let hasMoreContent: Bool
    public let isLoading: Bool

    public init(
        displayedItems: [Item],
        lastTimestamp: Date?,
        hasMoreContent: Bool,
        isLoading: Bool
    ) {
        self.displayedItems = displayedItems
        self.lastTimestamp = lastTimestamp
        self.hasMoreContent = hasMoreContent
        self.isLoading = isLoading
    }
}

public enum RomaHistoryPaginationPolicy {
    public static let defaultPageSize = 20

    public static func initialPage<Item>(
        _ items: [Item],
        pageSize: Int = RomaHistoryPaginationPolicy.defaultPageSize,
        timestamp: (Item) -> Date?
    ) -> RomaHistoryPaginationPlan<Item> {
        RomaHistoryPaginationPlan(
            displayedItems: items,
            lastTimestamp: items.last.flatMap(timestamp),
            hasMoreContent: items.count == pageSize,
            isLoading: false
        )
    }

    public static func appendingPage<Item>(
        currentItems: [Item],
        newItems: [Item],
        pageSize: Int = RomaHistoryPaginationPolicy.defaultPageSize,
        timestamp: (Item) -> Date?
    ) -> RomaHistoryPaginationPlan<Item> {
        RomaHistoryPaginationPlan(
            displayedItems: currentItems + newItems,
            lastTimestamp: newItems.last.flatMap(timestamp),
            hasMoreContent: newItems.count == pageSize,
            isLoading: false
        )
    }

    public static func reset<Item>() -> RomaHistoryPaginationPlan<Item> {
        RomaHistoryPaginationPlan(
            displayedItems: [],
            lastTimestamp: nil,
            hasMoreContent: true,
            isLoading: false
        )
    }

    public static func loadMoreCursor(
        isLoading: Bool,
        hasMoreContent: Bool,
        lastTimestamp: Date?
    ) -> Date? {
        guard !isLoading, hasMoreContent else {
            return nil
        }
        return lastTimestamp
    }
}

public enum RomaHistorySelectionPolicy {
    public static func areAllDisplayedItemsSelected<Item: Hashable>(
        displayedItems: [Item],
        selectedItems: Set<Item>
    ) -> Bool {
        !displayedItems.isEmpty && displayedItems.allSatisfy { selectedItems.contains($0) }
    }

    public static func toggling<Item: Hashable>(
        _ item: Item,
        in selectedItems: Set<Item>
    ) -> Set<Item> {
        var updatedSelection = selectedItems
        if updatedSelection.contains(item) {
            updatedSelection.remove(item)
        } else {
            updatedSelection.insert(item)
        }
        return updatedSelection
    }

    public static func selectingAll<Item: Hashable, ID: Hashable>(
        displayedItems: [Item],
        allItems: [Item],
        id: (Item) -> ID
    ) -> Set<Item> {
        var selection = Set(displayedItems)
        let displayedIds = Set(displayedItems.map(id))

        for item in allItems where !displayedIds.contains(id(item)) {
            selection.insert(item)
        }

        return selection
    }
}

public struct RomaHistoryDeletionPlan<Item: Hashable, ID: Hashable> {
    private let targets: [Item]
    public let remainingSelection: Set<Item>
    private let targetIDs: Set<ID>
    private let targetItems: Set<Item>

    init(
        targets: [Item],
        remainingSelection: Set<Item>,
        targetIDs: Set<ID>
    ) {
        self.targets = targets
        self.remainingSelection = remainingSelection
        self.targetIDs = targetIDs
        self.targetItems = Set(targets)
    }

    public func deletesItem(_ item: Item?) -> Bool {
        guard let item else { return false }
        return targetItems.contains(item)
    }

    public func deletesID(_ id: ID?) -> Bool {
        guard let id else { return false }
        return targetIDs.contains(id)
    }

    public func applyRuntimeState(deleteTarget: (Item) -> Void) {
        for target in targets {
            deleteTarget(target)
        }
    }
}

public enum RomaHistoryDeletionPolicy {
    private static func targets<Item>(
        atOffsets offsets: IndexSet,
        from displayedItems: [Item]
    ) -> [Item] {
        offsets.compactMap { index in
            guard displayedItems.indices.contains(index) else {
                return nil
            }
            return displayedItems[index]
        }
    }

    public static func selectedItemsDeletionPlan<Item: Hashable, ID: Hashable>(
        selectedItems: Set<Item>,
        id: (Item) -> ID
    ) -> RomaHistoryDeletionPlan<Item, ID> {
        deleting(Array(selectedItems), from: selectedItems, id: id)
    }

    public static func offsetDeletionPlan<Item: Hashable, ID: Hashable>(
        atOffsets offsets: IndexSet,
        from displayedItems: [Item],
        id: (Item) -> ID
    ) -> RomaHistoryDeletionPlan<Item, ID> {
        deleting(
            targets(atOffsets: offsets, from: displayedItems),
            from: Set<Item>(),
            id: id
        )
    }

    public static func deleting<Item: Hashable, ID: Hashable>(
        _ targets: [Item],
        from selectedItems: Set<Item>,
        id: (Item) -> ID
    ) -> RomaHistoryDeletionPlan<Item, ID> {
        let targetItems = Set(targets)
        return RomaHistoryDeletionPlan(
            targets: targets,
            remainingSelection: selectedItems.subtracting(targetItems),
            targetIDs: Set(targets.map(id))
        )
    }
}

fileprivate enum RomaHistoryRefreshAction: Equatable, Sendable {
    case ignore
    case reload
}

public struct RomaHistoryRefreshPlan: Sendable {
    private let action: RomaHistoryRefreshAction

    fileprivate init(action: RomaHistoryRefreshAction) {
        self.action = action
    }

    public func applyRuntimeState(reload: () -> Void) {
        switch action {
        case .ignore:
            break
        case .reload:
            reload()
        }
    }
}

public enum RomaHistoryRefreshPolicy {
    public static func searchTextDidChange() -> RomaHistoryRefreshPlan {
        RomaHistoryRefreshPlan(action: .reload)
    }

    public static func latestItemDidChange<ID: Equatable>(
        oldID: ID?,
        newID: ID?,
        isViewVisible: Bool
    ) -> RomaHistoryRefreshPlan {
        guard isViewVisible, oldID != newID else {
            return RomaHistoryRefreshPlan(action: .ignore)
        }
        return RomaHistoryRefreshPlan(action: .reload)
    }
}

public enum RomaPostProcessingFailurePresentation {
    public static let defaultNotificationReasonLimit = 80
    public static let enhancementUnavailableFallbackText = "AI Enhancement is not enabled or configured"

    public static func postProcessingFailureText(reason: String) -> String {
        "Post-processing failed: \(reason)"
    }

    public static func enhancementFailureText(reason: String) -> String {
        "Enhancement failed: \(reason)"
    }

    public static func enhancementUnavailableMessage(
        isEnabled: Bool,
        isConfigured: Bool
    ) -> String? {
        isEnabled && isConfigured ? nil : enhancementUnavailableFallbackText
    }

    public static func enhancementFailureNotificationTitle(
        reason: String,
        reasonLimit: Int = defaultNotificationReasonLimit
    ) -> String {
        "Enhancement failed: \(String(reason.prefix(max(0, reasonLimit))))"
    }
}

public enum RomaTranscriptPresentation {
    public static let pendingDisplayText = "New transcription"
    public static let failedDisplayText = "Transcription failed - tap to retry"
    public static let canceledDisplayText = "Transcription canceled"
    public static let emptyCompletedDisplayText = "No audible content detected."
    public static let emptyPreferredText = "No content available."
    public static let canceledTranscriptionText = "The transcription was canceled."
    public static let backgroundProcessingExpiredError = "iOS ended background processing before transcription finished. Retry using the saved audio."
    public static let interruptedProcessingError = "Transcription stopped when the app was terminated. Retry using the saved audio."
    public static let noteDetailNavigationTitle = "Note"
    public static let transcriptTitle = "Transcript"
    public static let copyTranscriptSystemImageName = "doc.on.doc"
    public static let actionSucceededSystemImageName = "checkmark"
    public static let copyToClipboardHelp = "Copy to clipboard"
    public static let saveTranscriptSystemImageName = "square.and.arrow.down"
    public static let saveTranscriptAsPlainTextButtonTitle = "Save as TXT"
    public static let saveTranscriptAsMarkdownButtonTitle = "Save as MD"
    public static let saveTranscriptHelp = "Save to file"
    public static let saveTranscriptPanelTitle = "Save Transcription"
    public static let saveTranscriptFailureConsolePrefix = "Failed to save file:"
    public static let transcribingDisplayText = "Transcribing..."
    public static let retranscribingDisplayText = "Retranscribing..."
    public static let retryTranscriptionButtonTitle = "Retry Transcription"
    public static let retryTranscriptionSystemImageName = "arrow.clockwise"
    public static let cancelTranscriptionButtonTitle = "Cancel"
    public static let cancelTranscriptionSystemImageName = "xmark.circle"
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
        selectedVariant: RomaTranscriptTextVariant,
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

    public static func filteredItems<Item>(
        _ items: [Item],
        query: String,
        rawText: (Item) -> String,
        enhancedText: (Item) -> String?
    ) -> [Item] {
        items.filter { item in
            matchesSearch(
                rawText: rawText(item),
                enhancedText: enhancedText(item),
                query: query
            )
        }
    }

    public static func displayText(
        status: RomaTranscriptionStatus,
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
        status: RomaTranscriptionStatus,
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

    public static func statusTitle(for status: RomaTranscriptionStatus) -> String? {
        statusPresentation(for: status)?.title
    }

    public static func statusBadgeText(for status: RomaTranscriptionStatus) -> String? {
        statusPresentation(for: status)?.badgeText
    }

    public static func statusPresentation(
        for status: RomaTranscriptionStatus
    ) -> RomaTranscriptStatusPresentation? {
        switch status {
        case .pending:
            return RomaTranscriptStatusPresentation(
                kind: .processing,
                title: "Transcription Pending",
                badgeText: "Processing"
            )
        case .failed:
            return RomaTranscriptStatusPresentation(
                kind: .failed,
                title: "Transcription Failed",
                badgeText: "Failed"
            )
        case .completed, .canceled:
            return nil
        }
    }

    public static func shouldShowStatusPanel(for status: RomaTranscriptionStatus) -> Bool {
        statusPresentation(for: status) != nil
    }

    public static func shouldShowCompletedContent(for status: RomaTranscriptionStatus) -> Bool {
        status == .completed
    }

    public static func statusErrorDetail(_ error: String?) -> String? {
        guard let error, !error.isEmpty else {
            return nil
        }

        return error
    }

    public static func retryControls(
        for status: RomaTranscriptionStatus,
        isRetranscribing: Bool,
        canCancel: Bool = false
    ) -> RomaTranscriptRetryControlsPresentation {
        if isRetranscribing {
            return RomaTranscriptRetryControlsPresentation(
                shouldShowModeSelection: false,
                shouldShowCancelButton: canCancel,
                action: .showProgress,
                progressText: retranscribingDisplayText
            )
        }

        switch status {
        case .pending:
            return RomaTranscriptRetryControlsPresentation(
                shouldShowModeSelection: false,
                shouldShowCancelButton: canCancel,
                action: .showProgress,
                progressText: transcribingDisplayText
            )
        case .failed:
            return RomaTranscriptRetryControlsPresentation(
                shouldShowModeSelection: true,
                action: .showRetryButton
            )
        case .completed, .canceled:
            return RomaTranscriptRetryControlsPresentation(
                shouldShowModeSelection: false,
                action: .hidden
            )
        }
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
            (statusRawValue == nil || statusRawValue == RomaTranscriptionStatus.completed.rawValue)
    }
}

public enum RomaLastTranscriptionTextPreference: Equatable, Sendable {
    case original
    case preferred
}

public struct RomaLastTranscriptionNotificationPresentation: Equatable, Sendable {
    public let title: String
    public let kind: RomaAppNotificationKind

    public init(title: String, kind: RomaAppNotificationKind) {
        self.title = title
        self.kind = kind
    }
}

public enum RomaLastTranscriptionRetryPreflightFailure: Equatable, Sendable {
    case missingAudio
    case noTranscriptionModelSelected
}

public struct RomaLastTranscriptionCandidate<ID: Equatable & Sendable>: Equatable, Sendable {
    public let id: ID
    public let rawText: String
    public let enhancedText: String?
    public let status: RomaTranscriptionStatus?

    public init(
        id: ID,
        rawText: String,
        enhancedText: String?,
        status: RomaTranscriptionStatus?
    ) {
        self.id = id
        self.rawText = rawText
        self.enhancedText = enhancedText
        self.status = status
    }
}

public enum RomaLastTranscriptionPolicy {
    public static let fetchLimit = 20
    public static let noTranscriptionNotification = RomaLastTranscriptionNotificationPresentation(
        title: RomaTranscriptPresentation.noTranscriptionAvailableTitle,
        kind: .error
    )

    public static func fetchFailedDiagnosticMessage(errorDescription: String) -> String {
        "Error fetching last transcription: \(errorDescription)"
    }

    public static func firstPasteableCandidate<ID: Equatable & Sendable>(
        in candidates: [RomaLastTranscriptionCandidate<ID>],
        excluding excludedID: ID? = nil
    ) -> RomaLastTranscriptionCandidate<ID>? {
        candidates.first { candidate in
            candidate.id != excludedID && RomaTranscriptPresentation.isPasteable(
                rawText: candidate.rawText,
                statusRawValue: candidate.status?.rawValue
            )
        }
    }

    public static func pasteText<ID: Equatable & Sendable>(
        for candidate: RomaLastTranscriptionCandidate<ID>,
        preference: RomaLastTranscriptionTextPreference
    ) -> String {
        switch preference {
        case .original:
            return candidate.rawText
        case .preferred:
            return RomaTranscriptPresentation.preferredText(
                rawText: candidate.rawText,
                enhancedText: candidate.enhancedText
            ) ?? candidate.rawText
        }
    }

    public static func copyCompletionNotification(
        didCopy: Bool
    ) -> RomaLastTranscriptionNotificationPresentation {
        RomaLastTranscriptionNotificationPresentation(
            title: didCopy
                ? RomaTranscriptPresentation.lastTranscriptionCopiedTitle
                : RomaTranscriptPresentation.failedToCopyTranscriptionTitle,
            kind: didCopy ? .success : .error
        )
    }

    public static func retryPreflightFailureNotification(
        _ failure: RomaLastTranscriptionRetryPreflightFailure
    ) -> RomaLastTranscriptionNotificationPresentation {
        switch failure {
        case .missingAudio:
            return RomaLastTranscriptionNotificationPresentation(
                title: RomaTranscriptPresentation.cannotRetryTitle(
                    errorDescription: RomaErrorDescription.text(for: RomaEngineError.audioFileNotFound)
                ),
                kind: .error
            )
        case .noTranscriptionModelSelected:
            return RomaLastTranscriptionNotificationPresentation(
                title: RomaErrorDescription.text(for: RomaEngineError.noTranscriptionModelSelected),
                kind: .error
            )
        }
    }

    public static let retrySuccessNotification = RomaLastTranscriptionNotificationPresentation(
        title: RomaTranscriptPresentation.copiedToClipboardTitle,
        kind: .success
    )

    public static func retryFailureNotification(
        errorDescription: String
    ) -> RomaLastTranscriptionNotificationPresentation {
        RomaLastTranscriptionNotificationPresentation(
            title: RomaTranscriptPresentation.retryFailedTitle(errorDescription: errorDescription),
            kind: .error
        )
    }

    public static func retryFailureNotification(
        for error: Error
    ) -> RomaLastTranscriptionNotificationPresentation {
        retryFailureNotification(errorDescription: RomaErrorDescription.text(for: error))
    }
}
