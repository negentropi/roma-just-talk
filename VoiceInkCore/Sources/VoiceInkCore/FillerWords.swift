import Foundation

public enum VoiceInkFillerWords {
    public static let defaultWords = [
        "uh", "um", "uhm", "umm", "uhh", "uhhh",
        "hmm", "hm", "mmm", "mm", "mh", "ehh"
    ]

    public static func normalizedWord(_ word: String) -> String? {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    public static func adding(_ word: String, to words: [String]) -> [String]? {
        guard let normalized = normalizedWord(word) else {
            return nil
        }

        guard !words.contains(where: { $0.lowercased() == normalized }) else {
            return nil
        }

        return words + [normalized]
    }

    public static func removing(_ word: String, from words: [String]) -> [String] {
        let removalKey = word.lowercased()
        return words.filter { $0.lowercased() != removalKey }
    }

    public static func removing(at offsets: IndexSet, from words: [String]) -> [String] {
        VoiceInkPreferenceList.removing(at: offsets, from: words)
    }
}
