import Foundation

public enum VoiceInkAudioMeterLevel {
    public static let defaultMinimumDecibels: Float = -60
    public static let defaultMaximumDecibels: Float = 0
    public static let defaultPreviousLevelWeight: Float = 0.6
    public static let defaultLevelHistoryLimit = 40
    public static let macOSUpdateIntervalMilliseconds = 17
    public static let iOSUpdateInterval: TimeInterval = 0.1
    public static let macOSVisualizerAnimationMinimumInterval: TimeInterval = 0.016
    public static let macOSVisualizerBarCount = 15
    public static let macOSVisualizerBarWidth: Double = 3
    public static let macOSVisualizerBarSpacing: Double = 2
    public static let macOSVisualizerMinimumBarHeight: Double = 4
    public static let macOSVisualizerMaximumBarHeight: Double = 28
    public static let macOSVisualizerPhaseStep: Double = 0.4
    public static let macOSVisualizerWaveFrequency: Double = 8
    public static let macOSVisualizerAmplitudeExponent: Double = 0.7
    public static let macOSVisualizerCenterBoostDropoff: Double = 0.4
    public static let iOSVisualizerBarCount = 8
    public static let iOSVisualizerBarSpacing: Double = 3
    public static let iOSVisualizerBarMinimumWidth: Double = 2
    public static let iOSVisualizerHorizontalPadding: Double = 2
    public static let iOSVisualizerWidthInset: Double = 16
    public static let iOSVisualizerFrameHeight: Double = 48
    public static let iOSVisualizerMinimumBarHeight: Double = 4
    public static let iOSVisualizerAnimationDuration: TimeInterval = 0.12
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

    public static func iOSVisualizerBarWidth(
        containerWidth: Double,
        barCount: Int = iOSVisualizerBarCount,
        spacing: Double = iOSVisualizerBarSpacing,
        widthInset: Double = iOSVisualizerWidthInset,
        minimumWidth: Double = iOSVisualizerBarMinimumWidth
    ) -> Double {
        guard barCount > 0 else { return minimumWidth }
        return max(minimumWidth, (containerWidth - widthInset) / Double(barCount) - spacing)
    }

    public static func iOSVisualizerBarHeight(
        forBarAt index: Int,
        levels: [Float],
        containerHeight: Double,
        barCount: Int = iOSVisualizerBarCount,
        minimumHeight: Double = iOSVisualizerMinimumBarHeight
    ) -> Double {
        let level = Double(visualizerLevel(forBarAt: index, levels: levels, barCount: barCount))
        return minimumHeight + (containerHeight - minimumHeight) * level
    }

    public static func macOSVisualizerBarHeight(
        forBarAt index: Int,
        time: TimeInterval,
        averagePower: Double,
        isActive: Bool,
        barCount: Int = macOSVisualizerBarCount,
        minimumHeight: Double = macOSVisualizerMinimumBarHeight,
        maximumHeight: Double = macOSVisualizerMaximumBarHeight
    ) -> Double {
        guard isActive, index >= 0, index < barCount, barCount > 1, maximumHeight > minimumHeight else {
            return minimumHeight
        }

        let amplitude = max(0, min(1, pow(averagePower, macOSVisualizerAmplitudeExponent)))
        let phase = Double(index) * macOSVisualizerPhaseStep
        let wave = sin(time * macOSVisualizerWaveFrequency + phase) * 0.5 + 0.5
        let centerDistance = abs(Double(index) - Double(barCount) / 2) / Double(barCount / 2)
        let centerBoost = 1.0 - centerDistance * macOSVisualizerCenterBoostDropoff

        return max(minimumHeight, minimumHeight + amplitude * wave * centerBoost * (maximumHeight - minimumHeight))
    }
}
