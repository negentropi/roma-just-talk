import Foundation

/// Decides when a recording that produced no words should ask the user to check their microphone:
/// a wrong, muted, or virtual input looks exactly like "Roma did nothing".
public enum VoiceInkMicrophoneCheck {
    public enum Finding: Equatable, Sendable {
        /// The input carried no sound at all, like a muted or virtual device.
        case silent
        /// There was sound, but no words were recognized in it.
        case noWords
    }

    /// Peaks below this are digital silence or a disconnected input, never a quiet room, which
    /// still peaks around -60 dBFS from its noise floor.
    public static let silencePeakDecibels: Float = -75
    /// Shorter holds are usually accidental taps of the shortcut, not attempts to dictate.
    public static let minimumSeconds: Double = 1.0
    public static let promptDuration: TimeInterval = 10

    /// For a recording whose transcript came back empty.
    public static func finding(durationSeconds: Double, peakDecibels: Float) -> Finding? {
        guard durationSeconds >= minimumSeconds else { return nil }
        return peakDecibels < silencePeakDecibels ? .silent : .noWords
    }

    public static func message(for finding: Finding, deviceName: String) -> String {
        switch finding {
        case .silent:
            return "No sound is coming from \(deviceName). Is that the right microphone?"
        case .noWords:
            return "Roma heard no words from \(deviceName). Is that the right microphone?"
        }
    }

    public static let changeMicrophoneLabel = "Change Mic"
    public static let systemDefaultTitle = "System Default"
}
