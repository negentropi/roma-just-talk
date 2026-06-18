import Foundation

public protocol VoiceInkPerformanceRecord {
    var performanceAudioDuration: TimeInterval { get }
    var performanceTranscriptionModelName: String? { get }
    var performanceTranscriptionDuration: TimeInterval? { get }
    var performanceEnhancementModelName: String? { get }
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
            name: \.performanceTranscriptionModelName,
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
            name: \.performanceEnhancementModelName,
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
