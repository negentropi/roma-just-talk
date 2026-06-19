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

    public static func clampedTime(
        _ time: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        guard duration > 0, time.isFinite, duration.isFinite else {
            return 0
        }

        return min(max(time, 0), duration)
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

public enum VoiceInkAudioPlaybackRate {
    public static let defaultRate: Float = 1.0
    public static let controlTitle = "Playback speed"

    public static func current(from defaults: UserDefaults = .standard) -> Float {
        restoredRate(defaults.float(forKey: VoiceInkUserDefaultsKey.audioPlaybackRate))
    }

    public static func restoredRate(_ savedRate: Float) -> Float {
        savedRate > 0 ? savedRate : defaultRate
    }

    public static func save(_ rate: Float, to defaults: UserDefaults = .standard) {
        defaults.set(rate, forKey: VoiceInkUserDefaultsKey.audioPlaybackRate)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.audioPlaybackRate)
    }

    public static func next(after rate: Float) -> Float {
        switch rate {
        case 1.0:
            return 1.5
        case 1.5:
            return 2.0
        default:
            return 1.0
        }
    }

    public static func label(for rate: Float) -> String {
        switch rate {
        case 1.0:
            return "1×"
        case 1.5:
            return "1.5×"
        default:
            return "2×"
        }
    }

    public static func isDefault(_ rate: Float) -> Bool {
        rate == defaultRate
    }
}

public enum VoiceInkAudioPlaybackPresentation {
    public static let loadingText = "Loading..."
    public static let timestampSystemImageName = "calendar"
    public static let durationSystemImageName = "waveform"

    public static func playPauseSystemImageName(isPlaying: Bool) -> String {
        isPlaying ? "pause.fill" : "play.fill"
    }
}
