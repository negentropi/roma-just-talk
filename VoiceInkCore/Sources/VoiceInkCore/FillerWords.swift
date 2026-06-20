import Foundation

public struct VoiceInkFillerWordSubmissionPlan: Equatable, Sendable {
    public let updatedWords: [String]
    public let draftAfterSubmit: String
    public let alertPresentation: VoiceInkDictionaryAlertPresentation?
    public let didInsert: Bool

    public init(
        updatedWords: [String],
        draftAfterSubmit: String,
        alertPresentation: VoiceInkDictionaryAlertPresentation?,
        didInsert: Bool = false
    ) {
        self.updatedWords = updatedWords
        self.draftAfterSubmit = draftAfterSubmit
        self.alertPresentation = alertPresentation
        self.didInsert = didInsert
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

    public static func submissionPlan(
        _ draft: String,
        existingWords words: [String]
    ) -> VoiceInkFillerWordSubmissionPlan {
        guard let wordToInsert = normalizedWord(draft) else {
            return VoiceInkFillerWordSubmissionPlan(
                updatedWords: words,
                draftAfterSubmit: draft,
                alertPresentation: nil
            )
        }

        guard !words.contains(where: { $0.lowercased() == wordToInsert }) else {
            return VoiceInkFillerWordSubmissionPlan(
                updatedWords: words,
                draftAfterSubmit: draft,
                alertPresentation: .duplicateFillerWord(message: duplicateWordMessage)
            )
        }

        return VoiceInkFillerWordSubmissionPlan(
            updatedWords: words + [wordToInsert],
            draftAfterSubmit: "",
            alertPresentation: nil,
            didInsert: true
        )
    }

    public static func removing(_ word: String, from words: [String]) -> [String] {
        let removalKey = word.lowercased()
        return words.filter { $0.lowercased() != removalKey }
    }

    public static func removing(at offsets: IndexSet, from words: [String]) -> [String] {
        VoiceInkPreferenceList.removing(at: offsets, from: words)
    }
}
