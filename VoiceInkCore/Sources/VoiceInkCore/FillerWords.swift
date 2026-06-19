import Foundation

public struct VoiceInkFillerWordInsertPlan: Equatable, Sendable {
    public let wordToInsert: String?
    public let errorMessage: String?

    public var shouldInsert: Bool {
        wordToInsert != nil && errorMessage == nil
    }

    public init(wordToInsert: String?, errorMessage: String?) {
        self.wordToInsert = wordToInsert
        self.errorMessage = errorMessage
    }
}

public enum VoiceInkFillerWords {
    public static let duplicateWordMessage = "This filler word is already in the list."

    public static let defaultWords = [
        "uh", "um", "uhm", "umm", "uhh", "uhhh",
        "hmm", "hm", "mmm", "mm", "mh", "ehh"
    ]

    public static func normalizedWord(_ word: String) -> String? {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    public static func hasDraft(_ word: String) -> Bool {
        normalizedWord(word) != nil
    }

    public static func insertPlan(
        _ word: String,
        existingWords words: [String]
    ) -> VoiceInkFillerWordInsertPlan {
        guard let normalized = normalizedWord(word) else {
            return VoiceInkFillerWordInsertPlan(wordToInsert: nil, errorMessage: nil)
        }

        guard !words.contains(where: { $0.lowercased() == normalized }) else {
            return VoiceInkFillerWordInsertPlan(wordToInsert: nil, errorMessage: duplicateWordMessage)
        }

        return VoiceInkFillerWordInsertPlan(wordToInsert: normalized, errorMessage: nil)
    }

    public static func adding(_ word: String, to words: [String]) -> [String]? {
        var updatedWords = words
        let errorMessage = add(word, to: &updatedWords)
        guard errorMessage == nil, updatedWords != words else {
            return nil
        }

        return updatedWords
    }

    @discardableResult
    public static func add(_ word: String, to words: inout [String]) -> String? {
        let plan = insertPlan(word, existingWords: words)

        if let errorMessage = plan.errorMessage {
            return errorMessage
        }

        guard let wordToInsert = plan.wordToInsert else {
            return nil
        }

        words.append(wordToInsert)
        return nil
    }

    public static func removing(_ word: String, from words: [String]) -> [String] {
        let removalKey = word.lowercased()
        return words.filter { $0.lowercased() != removalKey }
    }

    public static func removing(at offsets: IndexSet, from words: [String]) -> [String] {
        VoiceInkPreferenceList.removing(at: offsets, from: words)
    }
}
