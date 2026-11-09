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
    public static let stabilityPasses = 2

    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Words safe to type: those every recent pass agrees on, except the newest word of the latest
    /// pass, which may still be mid-word. Passes are compared ignoring case and punctuation, because
    /// each pass ends its text with a period that becomes a comma or nothing once speech continues.
    /// Spelled as the latest pass spells them; the last one drops trailing punctuation, which only
    /// settles once the next word does.
    public static func stableWords(acrossPasses passes: [[String]]) -> [String] {
        guard let latest = passes.last, !latest.isEmpty else { return [] }
        var count = latest.count - 1
        for pass in passes.dropLast() {
            count = min(count, zip(pass, latest).prefix { key($0) == key($1) }.count)
        }
        var stable = Array(latest.prefix(count))
        if let last = stable.popLast() {
            let bare = String(last.reversed().drop(while: isTrailingPunctuation).reversed())
            if !bare.isEmpty { stable.append(bare) }
        }
        return stable
    }

    /// `typed` extended by the new words in `stable`, without rewriting what is already typed: typed
    /// words keep their spelling, except that the last one may gain trailing punctuation. Release
    /// reconciles any remaining case or punctuation difference. Nil when a typed word was revised.
    public static func extend(_ typed: [String], with stable: [String]) -> [String]? {
        guard zip(typed, stable).allSatisfy({ key($0) == key($1) }) else { return nil }
        guard stable.count > typed.count else { return typed }
        var extended = typed
        if let last = extended.last, stable[typed.count - 1].hasPrefix(last) {
            extended[typed.count - 1] = stable[typed.count - 1]
        }
        return extended + stable[typed.count...]
    }

    private static func key(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func isTrailingPunctuation(_ character: Character) -> Bool {
        ".,;:!?".contains(character)
    }

    /// The smallest change that turns the text already typed (ending at the caret) into `desired`:
    /// remove `removedSuffix` from just before the caret, then type `insertedText`.
    public static func edit(from typed: String, to desired: String) -> (removedSuffix: String, insertedText: String) {
        let kept = zip(typed, desired).prefix { $0 == $1 }.count
        return (String(typed.dropFirst(kept)), String(desired.dropFirst(kept)))
    }
}
