import Foundation

public enum VoiceInkDurationPresentation {
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
