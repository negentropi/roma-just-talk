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

public struct VoiceInkNoteListSummaryPresentation: Equatable, Sendable {
    public let summary: VoiceInkDashboardMetricsSummary
    public let dashboardText: String
    public let fastestModelText: String?

    public init(
        summary: VoiceInkDashboardMetricsSummary,
        fastestModel: VoiceInkPerformanceModelStat? = nil
    ) {
        self.summary = summary
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
