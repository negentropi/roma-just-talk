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
}
