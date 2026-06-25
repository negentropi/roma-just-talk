import Foundation

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

public enum VoiceInkNoteListPresentation {
    public static let sectionTitle = "Recent"
    public static let settingsSystemImageName = "gearshape"
    public static let startRecordingButtonTitle = "Start Recording"
    public static let startRecordingSystemImageName = "mic.fill"
}

public enum VoiceInkHelpResourceKind: String, Equatable, Hashable, Sendable {
    case recommendedModels
    case videoGuides
    case documentation
    case supportEmail
}

public struct VoiceInkHelpResourcePresentation: Equatable, Sendable, Identifiable {
    public let id: VoiceInkHelpResourceKind
    public let systemImageName: String
    public let title: String
    public let url: URL?

    public init(
        id: VoiceInkHelpResourceKind,
        systemImageName: String,
        title: String,
        url: URL? = nil
    ) {
        self.id = id
        self.systemImageName = systemImageName
        self.title = title
        self.url = url
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
                url: URL(string: recommendedModelsURLString)!
            ),
            VoiceInkHelpResourcePresentation(
                id: .videoGuides,
                systemImageName: "video.fill",
                title: "YouTube Videos & Guides",
                url: URL(string: videoGuidesURLString)!
            ),
            VoiceInkHelpResourcePresentation(
                id: .documentation,
                systemImageName: "book.fill",
                title: "Documentation",
                url: URL(string: documentationURLString)!
            ),
            VoiceInkHelpResourcePresentation(
                id: .supportEmail,
                systemImageName: "exclamationmark.bubble.fill",
                title: "Feedback or Issues?"
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
