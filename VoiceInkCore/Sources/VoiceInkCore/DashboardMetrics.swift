import Foundation

public protocol VoiceInkSessionMetricSource {
    var text: String { get }
    var enhancedText: String? { get }
    var duration: TimeInterval { get }
    var transcriptionDuration: TimeInterval? { get }
    var enhancementDuration: TimeInterval? { get }
}

public protocol VoiceInkPerformanceRecord {
    var performanceAudioDuration: TimeInterval { get }
    var transcriptionModelName: String? { get }
    var performanceTranscriptionDuration: TimeInterval? { get }
    var aiEnhancementModelName: String? { get }
    var performanceEnhancementDuration: TimeInterval? { get }
    var performanceEnhancedText: String? { get }
}

public extension VoiceInkPerformanceRecord where Self: VoiceInkSessionMetricSource {
    var performanceAudioDuration: TimeInterval { duration }
    var performanceTranscriptionDuration: TimeInterval? { transcriptionDuration }
    var performanceEnhancementDuration: TimeInterval? { enhancementDuration }
    var performanceEnhancedText: String? { enhancedText }
}

public struct VoiceInkSessionMetricValues: Equatable, Sendable {
    public let wordCount: Int
    public let audioDuration: TimeInterval
    public let transcriptionDuration: TimeInterval?
    public let speedFactor: Double?
    public let enhancementDuration: TimeInterval?
}

public struct VoiceInkSessionMetricDraft: Equatable, Sendable {
    public let transcriptionId: UUID
    public let timestamp: Date
    public let source: String
    public let wordCount: Int
    public let audioDuration: TimeInterval
    public let transcriptionModelName: String?
    public let transcriptionDuration: TimeInterval?
    public let speedFactor: Double?
    public let powerModeName: String?
    public let aiEnhancementModelName: String?
    public let enhancementDuration: TimeInterval?
}

public enum VoiceInkSessionMetricPolicy {
    public static let recorderSource = "recorder"
    public static let completedTranscriptionStatusRawValue = VoiceInkTranscriptionStatus.completed.rawValue

    public static func values(for source: some VoiceInkSessionMetricSource) -> VoiceInkSessionMetricValues {
        let audioDuration = max(source.duration, 0)
        let transcriptionDuration = positiveDuration(source.transcriptionDuration)
        let enhancementDuration = positiveDuration(source.enhancementDuration)
        let speedFactor = transcriptionDuration.flatMap { duration in
            audioDuration > 0 ? audioDuration / duration : nil
        }

        return VoiceInkSessionMetricValues(
            wordCount: VoiceInkWordCounter.count(in: textForCounting(from: source)),
            audioDuration: audioDuration,
            transcriptionDuration: transcriptionDuration,
            speedFactor: speedFactor,
            enhancementDuration: enhancementDuration
        )
    }

    public static func recorderDraft(
        transcriptionId: UUID,
        timestamp: Date,
        source: some VoiceInkSessionMetricSource,
        transcriptionModelName: String?,
        powerModeName: String?,
        aiEnhancementModelName: String?
    ) -> VoiceInkSessionMetricDraft {
        let values = values(for: source)
        return VoiceInkSessionMetricDraft(
            transcriptionId: transcriptionId,
            timestamp: timestamp,
            source: recorderSource,
            wordCount: values.wordCount,
            audioDuration: values.audioDuration,
            transcriptionModelName: transcriptionModelName,
            transcriptionDuration: values.transcriptionDuration,
            speedFactor: values.speedFactor,
            powerModeName: powerModeName,
            aiEnhancementModelName: aiEnhancementModelName,
            enhancementDuration: values.enhancementDuration
        )
    }

    static func textForCounting(from source: some VoiceInkSessionMetricSource) -> String {
        if let enhancedText = source.enhancedText,
           source.enhancementDuration != nil,
           !enhancedText.isEmpty {
            return enhancedText
        }

        return source.text
    }

    private static func positiveDuration(_ duration: TimeInterval?) -> TimeInterval? {
        duration.flatMap { $0 > 0 ? $0 : nil }
    }
}

public enum VoiceInkSessionMetricMigrationPreference {
    public static let completionKey = "HasCompletedStatsMigration"

    public static func isCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completionKey)
    }

    public static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completionKey)
    }
}

public enum VoiceInkSessionMetricMigrationDiagnostics {
    public static func completedMessage(insertedCount: Int) -> String {
        "Completed stats migration with \(insertedCount) session metric(s)"
    }

    public static func failedMessage(localizedDescription: String) -> String {
        "Stats migration failed: \(localizedDescription)"
    }
}

public enum VoiceInkSessionMetricRecorderDiagnostics {
    public static func recordedSessionMetricMessage(transcriptionId: UUID) -> String {
        "Recorded session metric for transcription \(transcriptionId.uuidString)"
    }
}

public struct VoiceInkPerformanceAnalysis: Equatable, Sendable {
    public let totalTranscripts: Int
    public let totalWithTranscriptionData: Int
    public let totalAudioDuration: TimeInterval
    public let totalEnhancedFiles: Int
    public let transcriptionModels: [VoiceInkPerformanceModelStat]
    public let enhancementModels: [VoiceInkPerformanceModelStat]

    public var totalTranscriptsText: String {
        "\(totalTranscripts)"
    }

    public var totalWithTranscriptionDataText: String {
        "\(totalWithTranscriptionData)"
    }

    public var totalEnhancedFilesText: String {
        "\(totalEnhancedFiles)"
    }
}

public struct VoiceInkPerformanceModelStat: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var speedFactorText: String {
        String(format: "%.1fx", speedFactor)
    }
    public var speedFactorRealtimeText: String {
        "\(speedFactorText) realtime"
    }
    public var realTimeComparisonText: String {
        speedFactor >= 1.0 ? "Faster than Real-time" : "Slower than Real-time"
    }
    public var avgProcessingTimeCompactText: String {
        String(format: "%.2fs", avgProcessingTime)
    }
    public var avgProcessingTimeSpacedText: String {
        String(format: "%.2f s", avgProcessingTime)
    }

    public let name: String
    public let sampleCount: Int
    public let totalProcessingTime: TimeInterval
    public let avgProcessingTime: TimeInterval
    public let avgAudioDuration: TimeInterval
    public let speedFactor: Double
}

public enum VoiceInkPerformanceTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisYear = "This Year"
    case allTime = "All Time"

    public static let userDefaultsKey = "modelPerfPanelFilter"
    public static let defaultFilter: Self = .last7Days

    public var id: String { rawValue }
    public var label: String { rawValue }

    public static func storedFilter(rawValue: String?) -> Self {
        guard let rawValue, let filter = Self(rawValue: rawValue) else {
            return defaultFilter
        }

        return filter
    }

    public func startDate(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .allTime:
            return nil
        case .last7Days:
            return now.addingTimeInterval(-7 * 24 * 3600)
        case .last30Days:
            return now.addingTimeInterval(-30 * 24 * 3600)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)?.start
        }
    }
}

public enum VoiceInkPerformancePresentation {
    public static let modelPerformancePanelTitle = "Model Performance"
    public static let performanceAnalysisPanelTitle = "Performance Analysis"
    public static let closeSystemImageName = "xmark"
    public static let emptyStateSystemImageName = "chart.bar.xaxis"
    public static let emptyStateTitle = "No data for this period"
    public static let summarySectionTitle = "Summary"
    public static let systemInformationSectionTitle = "System Information"
    public static let transcriptionModelsSectionTitle = "Transcription Models"
    public static let enhancementModelsSectionTitle = "Enhancement Models"
    public static let totalSummaryIconSystemName = "doc.text.fill"
    public static let totalSummaryLabel = "Total"
    public static let analyzableSummaryIconSystemName = "waveform.path.ecg"
    public static let analyzableSummaryLabel = "Analyzable"
    public static let enhancedSummaryIconSystemName = "sparkles"
    public static let enhancedSummaryLabel = "Enhanced"
    public static let deviceInfoLabel = "Device"
    public static let processorInfoLabel = "Processor"
    public static let memoryInfoLabel = "Memory"
    public static let averageAudioLabel = "Avg. Audio"
    public static let averageProcessingLabel = "Avg. Processing"
    public static let averageEnhancementTimeLabel = "Avg. Enhancement Time"

    public static func sessionSampleCountText(_ count: Int) -> String {
        "\(count) sessions"
    }

    public static func transcriptSampleCountText(_ count: Int) -> String {
        "\(count) transcripts"
    }

    public static func physicalMemoryText(byteCount: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: byteCount),
            countStyle: .memory
        )
    }
}

public enum VoiceInkPerformanceAnalyzer {
    public static func analyze<Record: VoiceInkPerformanceRecord>(
        records: [Record]
    ) -> VoiceInkPerformanceAnalysis {
        VoiceInkPerformanceAnalysis(
            totalTranscripts: records.count,
            totalWithTranscriptionData: records.filter { $0.performanceTranscriptionDuration != nil }.count,
            totalAudioDuration: records.reduce(0) { $0 + $1.performanceAudioDuration },
            totalEnhancedFiles: records.filter {
                $0.performanceEnhancedText != nil && $0.performanceEnhancementDuration != nil
            }.count,
            transcriptionModels: transcriptionModelStats(from: records),
            enhancementModels: enhancementModelStats(from: records)
        )
    }

    public static func transcriptionModelStats<Record: VoiceInkPerformanceRecord>(
        from records: [Record],
        requirePositiveDuration: Bool = false
    ) -> [VoiceInkPerformanceModelStat] {
        modelStats(
            from: records,
            name: \.transcriptionModelName,
            processingDuration: \.performanceTranscriptionDuration,
            requirePositiveDuration: requirePositiveDuration
        )
    }

    public static func enhancementModelStats<Record: VoiceInkPerformanceRecord>(
        from records: [Record],
        requirePositiveDuration: Bool = false
    ) -> [VoiceInkPerformanceModelStat] {
        modelStats(
            from: records,
            name: \.aiEnhancementModelName,
            processingDuration: \.performanceEnhancementDuration,
            requirePositiveDuration: requirePositiveDuration
        )
    }

    private static func modelStats<Record: VoiceInkPerformanceRecord>(
        from records: [Record],
        name nameKeyPath: KeyPath<Record, String?>,
        processingDuration durationKeyPath: KeyPath<Record, TimeInterval?>,
        requirePositiveDuration: Bool
    ) -> [VoiceInkPerformanceModelStat] {
        var accumulators: [String: PerformanceAccumulator] = [:]

        for record in records {
            guard let name = record[keyPath: nameKeyPath],
                  let processingDuration = record[keyPath: durationKeyPath],
                  !requirePositiveDuration || processingDuration > 0 else {
                continue
            }

            accumulators[name, default: PerformanceAccumulator()].add(
                audioDuration: record.performanceAudioDuration,
                processingDuration: processingDuration
            )
        }

        return accumulators
            .map { name, accumulator in accumulator.stat(named: name) }
            .sorted { $0.avgProcessingTime < $1.avgProcessingTime }
    }
}

private struct PerformanceAccumulator {
    var sampleCount = 0
    var totalProcessingTime: TimeInterval = 0
    var totalAudioDuration: TimeInterval = 0

    mutating func add(audioDuration: TimeInterval, processingDuration: TimeInterval) {
        sampleCount += 1
        totalProcessingTime += processingDuration
        totalAudioDuration += audioDuration
    }

    func stat(named name: String) -> VoiceInkPerformanceModelStat {
        let safeCount = max(sampleCount, 1)
        let speedFactor = totalProcessingTime > 0 ? totalAudioDuration / totalProcessingTime : 0

        return VoiceInkPerformanceModelStat(
            name: name,
            sampleCount: sampleCount,
            totalProcessingTime: totalProcessingTime,
            avgProcessingTime: totalProcessingTime / Double(safeCount),
            avgAudioDuration: totalAudioDuration / Double(safeCount),
            speedFactor: speedFactor
        )
    }
}

public protocol VoiceInkDashboardMetricRecord {
    var dashboardWordCount: Int { get }
    var dashboardAudioDuration: TimeInterval { get }
}

public extension VoiceInkDashboardMetricRecord where Self: VoiceInkSessionMetricSource {
    var dashboardWordCount: Int {
        VoiceInkSessionMetricPolicy.values(for: self).wordCount
    }

    var dashboardAudioDuration: TimeInterval {
        VoiceInkSessionMetricPolicy.values(for: self).audioDuration
    }
}

public struct VoiceInkDashboardMetricsSummary: Equatable, Sendable {
    public var totalCount: Int
    public var totalWords: Int
    public var totalDuration: TimeInterval

    public init(
        totalCount: Int = 0,
        totalWords: Int = 0,
        totalDuration: TimeInterval = 0
    ) {
        self.totalCount = totalCount
        self.totalWords = totalWords
        self.totalDuration = totalDuration
    }
}

public struct VoiceInkDashboardMetricsAccumulator: Equatable, Sendable {
    public private(set) var totalWords: Int
    public private(set) var totalDuration: TimeInterval

    public init(totalWords: Int = 0, totalDuration: TimeInterval = 0) {
        self.totalWords = totalWords
        self.totalDuration = totalDuration
    }

    public mutating func add(_ record: some VoiceInkDashboardMetricRecord) {
        totalWords += record.dashboardWordCount
        totalDuration += record.dashboardAudioDuration
    }

    public func summary(totalCount: Int) -> VoiceInkDashboardMetricsSummary {
        VoiceInkDashboardMetricsSummary(
            totalCount: totalCount,
            totalWords: totalWords,
            totalDuration: totalDuration
        )
    }
}

public struct VoiceInkDashboardMetrics: Equatable, Sendable {
    public let summary: VoiceInkDashboardMetricsSummary
    public let averageTypingWordsPerMinute: Double
    public let keystrokesPerWord: Double

    public init(
        summary: VoiceInkDashboardMetricsSummary,
        averageTypingWordsPerMinute: Double = 35,
        keystrokesPerWord: Double = 5
    ) {
        self.summary = summary
        self.averageTypingWordsPerMinute = averageTypingWordsPerMinute
        self.keystrokesPerWord = keystrokesPerWord
    }

    public var estimatedTypingTime: TimeInterval {
        guard averageTypingWordsPerMinute > 0 else {
            return 0
        }

        return Double(summary.totalWords) / averageTypingWordsPerMinute * 60
    }

    public var timeSaved: TimeInterval {
        max(estimatedTypingTime - summary.totalDuration, 0)
    }

    public var averageWordsPerMinute: Double {
        guard summary.totalDuration > 0 else {
            return 0
        }

        return Double(summary.totalWords) / (summary.totalDuration / 60)
    }

    public var averageWordsPerMinuteDisplayText: String? {
        guard averageWordsPerMinute > 0 else {
            return nil
        }

        return String(format: "%.1f", averageWordsPerMinute)
    }

    public var totalKeystrokesSaved: Int {
        Int(Double(summary.totalWords) * keystrokesPerWord)
    }
}

public struct VoiceInkDashboardMetricCardPresentation: Equatable, Sendable, Identifiable {
    public let id: String
    public let iconSystemName: String
    public let title: String
    public let value: String
    public let detail: String

    public init(
        id: String,
        iconSystemName: String,
        title: String,
        value: String,
        detail: String
    ) {
        self.id = id
        self.iconSystemName = iconSystemName
        self.title = title
        self.value = value
        self.detail = detail
    }
}

public struct VoiceInkDashboardHeroPillPresentation: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let value: String

    public init(
        id: String,
        title: String,
        value: String
    ) {
        self.id = id
        self.title = title
        self.value = value
    }
}

public enum VoiceInkDashboardPresentation {
    public static let metricValuePlaceholder = "–"
    public static let emptyStateSystemImageName = "waveform"
    public static let emptyStateTitle = "No sessions yet"
    public static let emptyStateMessage = "Start a recording; your dictation rhythm will show here."
    public static let heroSectionTitle = "Dashboard"
    public static let readyTitle = "Ready when you are"
    public static let usageSummaryPendingSubtitle = "Your usage summary will appear here."
    public static let firstRecordingSubtitle = "Your first roma-just-talk recording starts the timeline."
    public static let timeSavedFallbackTitle = "Time savings coming soon"
    public static let sessionsPillTitle = "Sessions"
    public static let wordsPillTitle = "Words"
    public static let modelPerformanceButtonTitle = "Model Performance"
    public static let modelPerformanceSystemImageName = "gauge"
    public static let modelPerformanceHelpText = "View transcription and enhancement model performance"

    public static func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func heroTitle(
        isSnapshotLoaded: Bool,
        timeSaved: TimeInterval
    ) -> String {
        guard isSnapshotLoaded else {
            return readyTitle
        }

        return VoiceInkDurationPresentation.positiveDuration(
            timeSaved,
            style: .full,
            fallback: timeSavedFallbackTitle
        )
    }

    public static func heroSubtitle(
        isSnapshotLoaded: Bool,
        totalCount: Int,
        formattedWordCount: String
    ) -> String {
        guard isSnapshotLoaded else {
            return usageSummaryPendingSubtitle
        }

        guard totalCount > 0 else {
            return firstRecordingSubtitle
        }

        let sessionText = totalCount == 1 ? "session" : "sessions"
        return "Dictated \(formattedWordCount) words across \(totalCount) \(sessionText)."
    }

    public static func heroSubtitle(
        isSnapshotLoaded: Bool,
        totalCount: Int,
        totalWords: Int
    ) -> String {
        heroSubtitle(
            isSnapshotLoaded: isSnapshotLoaded,
            totalCount: totalCount,
            formattedWordCount: formattedNumber(totalWords)
        )
    }

    public static func heroPills(
        isSnapshotLoaded: Bool,
        summary: VoiceInkDashboardMetricsSummary
    ) -> [VoiceInkDashboardHeroPillPresentation] {
        [
            VoiceInkDashboardHeroPillPresentation(
                id: "sessions",
                title: sessionsPillTitle,
                value: isSnapshotLoaded ? formattedNumber(summary.totalCount) : metricValuePlaceholder
            ),
            VoiceInkDashboardHeroPillPresentation(
                id: "words",
                title: wordsPillTitle,
                value: isSnapshotLoaded ? formattedNumber(summary.totalWords) : metricValuePlaceholder
            )
        ]
    }

    public static func metricCards(
        isSnapshotLoaded: Bool,
        metrics: VoiceInkDashboardMetrics
    ) -> [VoiceInkDashboardMetricCardPresentation] {
        [
            VoiceInkDashboardMetricCardPresentation(
                id: "sessions-recorded",
                iconSystemName: "mic.fill",
                title: "Sessions Recorded",
                value: isSnapshotLoaded ? "\(metrics.summary.totalCount)" : metricValuePlaceholder,
                detail: "recordings completed"
            ),
            VoiceInkDashboardMetricCardPresentation(
                id: "words-dictated",
                iconSystemName: "text.alignleft",
                title: "Words Dictated",
                value: isSnapshotLoaded ? formattedNumber(metrics.summary.totalWords) : metricValuePlaceholder,
                detail: "words generated"
            ),
            VoiceInkDashboardMetricCardPresentation(
                id: "words-per-minute",
                iconSystemName: "speedometer",
                title: "Words Per Minute",
                value: isSnapshotLoaded ? metrics.averageWordsPerMinuteDisplayText ?? metricValuePlaceholder : metricValuePlaceholder,
                detail: "dictation pace"
            ),
            VoiceInkDashboardMetricCardPresentation(
                id: "keystrokes-saved",
                iconSystemName: "keyboard.fill",
                title: "Keystrokes Saved",
                value: isSnapshotLoaded ? formattedNumber(metrics.totalKeystrokesSaved) : metricValuePlaceholder,
                detail: "fewer keystrokes"
            )
        ]
    }
}

public struct VoiceInkNoteListSummaryPresentation: Equatable, Sendable {
    public let summary: VoiceInkDashboardMetricsSummary
    public let countText: String
    public let dashboardText: String
    public let fastestModelText: String?

    public init(
        summary: VoiceInkDashboardMetricsSummary,
        fastestModel: VoiceInkPerformanceModelStat? = nil
    ) {
        self.summary = summary
        self.countText = "\(summary.totalCount)"
        self.dashboardText = "\(summary.totalWords) words - \(VoiceInkDurationPresentation.minutesSeconds(summary.totalDuration)) audio"
        self.fastestModelText = fastestModel.map { "\($0.name) \($0.speedFactorRealtimeText)" }
    }

    public static func make<Record>(
        from records: [Record]
    ) -> VoiceInkNoteListSummaryPresentation where Record: VoiceInkDashboardMetricRecord, Record: VoiceInkPerformanceRecord {
        var accumulator = VoiceInkDashboardMetricsAccumulator()
        for record in records {
            accumulator.add(record)
        }

        return VoiceInkNoteListSummaryPresentation(
            summary: accumulator.summary(totalCount: records.count),
            fastestModel: VoiceInkPerformanceAnalyzer.transcriptionModelStats(
                from: records,
                requirePositiveDuration: true
            ).first
        )
    }
}

public struct VoiceInkNoteListSnapshot<Item> {
    public let displayedItems: [Item]
    public let summaryPresentation: VoiceInkNoteListSummaryPresentation
    public let emptyStatePresentation: VoiceInkHistoryEmptyStatePresentation

    public var shouldShowEmptyState: Bool {
        displayedItems.isEmpty
    }

    public init(
        displayedItems: [Item],
        summaryPresentation: VoiceInkNoteListSummaryPresentation,
        emptyStatePresentation: VoiceInkHistoryEmptyStatePresentation = VoiceInkHistoryPresentation.iOSNotesEmptyState
    ) {
        self.displayedItems = displayedItems
        self.summaryPresentation = summaryPresentation
        self.emptyStatePresentation = emptyStatePresentation
    }

    public static func make(
        from items: [Item],
        query: String,
        rawText: (Item) -> String,
        enhancedText: (Item) -> String?
    ) -> VoiceInkNoteListSnapshot<Item> where Item: VoiceInkDashboardMetricRecord, Item: VoiceInkPerformanceRecord {
        let displayedItems = VoiceInkTranscriptPresentation.filteredItems(
            items,
            query: query,
            rawText: rawText,
            enhancedText: enhancedText
        )

        return VoiceInkNoteListSnapshot(
            displayedItems: displayedItems,
            summaryPresentation: VoiceInkNoteListSummaryPresentation.make(from: displayedItems)
        )
    }
}

public extension VoiceInkNoteListSnapshot where Item: Hashable {
    func offsetDeletionPlan<ID: Hashable>(
        atOffsets offsets: IndexSet,
        id: (Item) -> ID
    ) -> VoiceInkHistoryDeletionPlan<Item, ID> {
        VoiceInkHistoryDeletionPolicy.offsetDeletionPlan(
            atOffsets: offsets,
            from: displayedItems,
            id: id
        )
    }
}

public enum VoiceInkNoteListPresentation {
    public static let sectionTitle = "Recent"
    public static let settingsSystemImageName = "gearshape"
    public static let startRecordingButtonTitle = "Start Recording"
    public static let startRecordingSystemImageName = "mic.fill"
}

public enum VoiceInkHelpResourceKind: String, Equatable, Hashable, Sendable {
    case commonIssues
    case recommendedModels
    case videoGuides
    case documentation
    case supportEmail
}

public enum VoiceInkHelpResourceDestination: Equatable, Sendable {
    case url(URL)
    case supportEmail
}

public struct VoiceInkHelpResourcePresentation: Equatable, Sendable, Identifiable {
    public let id: VoiceInkHelpResourceKind
    public let systemImageName: String
    public let title: String
    public let destination: VoiceInkHelpResourceDestination

    public init(
        id: VoiceInkHelpResourceKind,
        systemImageName: String,
        title: String,
        destination: VoiceInkHelpResourceDestination
    ) {
        self.id = id
        self.systemImageName = systemImageName
        self.title = title
        self.destination = destination
    }
}

public enum VoiceInkHelpResourcesPresentation {
    public static let title = "Help & Resources"
    public static let externalLinkSystemImageName = "arrow.up.right"
    public static let recommendedModelsURLString = "https://tryvoiceink.com/recommended-models"
    public static let videoGuidesURLString = "https://www.youtube.com/@tryvoiceink/videos"
    public static let documentationURLString = "https://tryvoiceink.com/docs"

    public static var resources: [VoiceInkHelpResourcePresentation] {
        [
            VoiceInkHelpResourcePresentation(
                id: .recommendedModels,
                systemImageName: "sparkles",
                title: "Recommended Models",
                destination: .url(URL(string: recommendedModelsURLString)!)
            ),
            VoiceInkHelpResourcePresentation(
                id: .videoGuides,
                systemImageName: "video.fill",
                title: "YouTube Videos & Guides",
                destination: .url(URL(string: videoGuidesURLString)!)
            ),
            VoiceInkHelpResourcePresentation(
                id: .documentation,
                systemImageName: "book.fill",
                title: "Documentation",
                destination: .url(URL(string: documentationURLString)!)
            ),
            VoiceInkHelpResourcePresentation(
                id: .supportEmail,
                systemImageName: "exclamationmark.bubble.fill",
                title: "Feedback or Issues?",
                destination: .supportEmail
            )
        ]
    }
}

public enum VoiceInkDashboardPromotionKind: String, Equatable, Hashable, Sendable {
    case upgrade
    case affiliate
}

public struct VoiceInkDashboardPromotionCardPresentation: Equatable, Sendable, Identifiable {
    public let id: VoiceInkDashboardPromotionKind
    public let badge: String
    public let title: String
    public let message: String
    public let actionTitle: String
    public let actionSystemImageName: String
    public let actionURL: URL
    public let dismissHelpText: String?

    public init(
        id: VoiceInkDashboardPromotionKind,
        badge: String,
        title: String,
        message: String,
        actionTitle: String,
        actionSystemImageName: String,
        actionURL: URL,
        dismissHelpText: String? = nil
    ) {
        self.id = id
        self.badge = badge
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionSystemImageName = actionSystemImageName
        self.actionURL = actionURL
        self.dismissHelpText = dismissHelpText
    }

    public var isDismissible: Bool {
        dismissHelpText != nil
    }

    public var badgeDisplayText: String {
        badge.uppercased()
    }
}

public enum VoiceInkDashboardPromotionPresentation {
    public static let affiliateDismissedKey = "VoiceInkAffiliatePromotionDismissed"
    public static let defaultIsAffiliateDismissed = false
    public static let socialShareURLString = "https://tryvoiceink.com/social-share"
    public static let affiliateURLString = "https://tryvoiceink.com/affiliate"
    public static let dismissHelpText = "Dismiss this promotion"
    public static let dismissSystemImageName = "xmark.circle.fill"

    public static var socialShareURL: URL {
        URL(string: socialShareURLString)!
    }

    public static var affiliateURL: URL {
        URL(string: affiliateURLString)!
    }

    public static func cards(
        for licenseState: VoiceInkLicenseState,
        isAffiliateDismissed: Bool
    ) -> [VoiceInkDashboardPromotionCardPresentation] {
        switch licenseState {
        case .trial(let daysRemaining) where daysRemaining <= 3:
            return [upgradeCard]
        case .trialExpired:
            return [upgradeCard]
        case .licensed where !isAffiliateDismissed:
            return [affiliateCard]
        case .trial, .licensed:
            return []
        }
    }

    public static let upgradeCard = VoiceInkDashboardPromotionCardPresentation(
        id: .upgrade,
        badge: "30% OFF",
        title: "Unlock VoiceInk Pro For Less",
        message: "Share VoiceInk on your socials, and instantly unlock a 30% discount on VoiceInk Pro.",
        actionTitle: "Share & Unlock",
        actionSystemImageName: "arrow.up.right",
        actionURL: socialShareURL
    )

    public static let affiliateCard = VoiceInkDashboardPromotionCardPresentation(
        id: .affiliate,
        badge: "AFFILIATE 30%",
        title: "Earn With The VoiceInk Affiliate Program",
        message: "Share VoiceInk with friends or your audience and receive 30% on every referral that upgrades.",
        actionTitle: "Explore Affiliate",
        actionSystemImageName: "arrow.up.right",
        actionURL: affiliateURL,
        dismissHelpText: dismissHelpText
    )
}
