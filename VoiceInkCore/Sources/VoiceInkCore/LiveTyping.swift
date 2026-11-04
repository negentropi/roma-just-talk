import Foundation

/// Typing committed transcript text into the focused field while the user is still speaking.
public enum VoiceInkLiveTypingPreference {
    public static let userDefaultsKey = "typeWhileSpeaking"
    public static let defaultIsEnabled = true
    public static let macOSSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS.liveTyping

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }
}

public enum VoiceInkLiveTyping {
    /// Consecutive live passes that must agree on a word before it is typed.
    public static let stabilityPasses = 3

    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The leading words every pass agrees on exactly, minus the last one,
    /// which can still gain punctuation when the next word arrives.
    public static func stableWords(acrossPasses passes: [[String]]) -> [String] {
        guard var agreed = passes.first else { return [] }
        for pass in passes.dropFirst() {
            agreed = Array(zip(agreed, pass).prefix { $0 == $1 }.map(\.0))
        }
        return Array(agreed.dropLast())
    }

    /// The smallest change that turns the text already typed (ending at the caret) into `desired`:
    /// remove `removedSuffix` from just before the caret, then type `insertedText`.
    public static func edit(from typed: String, to desired: String) -> (removedSuffix: String, insertedText: String) {
        let kept = zip(typed, desired).prefix { $0 == $1 }.count
        return (String(typed.dropFirst(kept)), String(desired.dropFirst(kept)))
    }
}
