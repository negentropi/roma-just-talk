import Foundation

public enum VoiceInkAudioMeterLevel {
    public static let defaultMinimumDecibels: Float = -60
    public static let defaultMaximumDecibels: Float = 0
    public static let defaultPreviousLevelWeight: Float = 0.6
    public static let defaultLevelHistoryLimit = 40
    public static let macOSUpdateIntervalMilliseconds = 17
    public static let iOSUpdateInterval: TimeInterval = 0.1
    public static let iOSVisualizerBarCount = 8
    public static let iOSVisualizerMinimumBarHeight: Double = 4
    public static let visualizerAccessibilityLabel = "Audio level visualizer"

    public static func normalizedLevel(
        forDecibels decibels: Float,
        minimumDecibels: Float = defaultMinimumDecibels,
        maximumDecibels: Float = defaultMaximumDecibels
    ) -> Float {
        guard maximumDecibels > minimumDecibels else {
            return decibels >= maximumDecibels ? 1 : 0
        }

        if decibels < minimumDecibels {
            return 0
        }

        if decibels >= maximumDecibels {
            return 1
        }

        return (decibels - minimumDecibels) / (maximumDecibels - minimumDecibels)
    }

    public static func smoothedLevel(
        previous: Float,
        current: Float,
        previousWeight: Float = defaultPreviousLevelWeight
    ) -> Float {
        let clampedPreviousWeight = min(max(previousWeight, 0), 1)
        return previous * clampedPreviousWeight + current * (1 - clampedPreviousWeight)
    }

    public static func boundedHistory(
        appending level: Float,
        to history: [Float],
        limit: Int = defaultLevelHistoryLimit
    ) -> [Float] {
        guard limit > 0 else {
            return []
        }

        let updatedHistory = history + [level]
        guard updatedHistory.count > limit else {
            return updatedHistory
        }

        return Array(updatedHistory.suffix(limit))
    }

    public static func visualizerLevel(
        forBarAt index: Int,
        levels: [Float],
        barCount: Int = iOSVisualizerBarCount
    ) -> Float {
        guard index >= 0, !levels.isEmpty, barCount > 0 else {
            return 0
        }

        let span = max(1, min(levels.count, barCount))
        let step = max(1, levels.count / span)
        let sourceIndex = max(0, levels.count - 1 - index * step)
        let sourceLevel = levels[sourceIndex]
        return max(0, min(1, sourceLevel))
    }
}
