import Foundation

public enum VoiceInkAudioPlaybackTimeline {
    public static func progress(
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0, currentTime.isFinite, duration.isFinite else {
            return 0
        }

        return clampedProgress(currentTime / duration)
    }

    public static func progress(
        locationX: Double,
        width: Double
    ) -> Double {
        guard width > 0, locationX.isFinite, width.isFinite else {
            return 0
        }

        return clampedProgress(locationX / width)
    }

    public static func time(
        atLocationX locationX: Double,
        width: Double,
        duration: TimeInterval
    ) -> TimeInterval {
        guard duration > 0, duration.isFinite else {
            return 0
        }

        return progress(locationX: locationX, width: width) * duration
    }

    public static func sampleProgress(index: Int, sampleCount: Int) -> Double {
        guard sampleCount > 0 else {
            return 0
        }

        return clampedProgress(Double(index) / Double(sampleCount))
    }

    private static func clampedProgress(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
    }
}
