import Foundation

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

public struct VoiceInkPerformanceAnalysis: Equatable, Sendable {
    public let totalTranscripts: Int
    public let totalWithTranscriptionData: Int
    public let totalAudioDuration: TimeInterval
    public let totalEnhancedFiles: Int
    public let transcriptionModels: [VoiceInkPerformanceModelStat]
    public let enhancementModels: [VoiceInkPerformanceModelStat]
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
