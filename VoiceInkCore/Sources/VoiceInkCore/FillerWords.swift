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

    public func updatedWordsIfChanged(from currentWords: [String]) -> [String]? {
        VoiceInkPreferenceList.changedElements(from: currentWords, to: updatedWords)
    }
}

public struct VoiceInkFillerWordDraftSubmission: Equatable, Sendable, VoiceInkDictionaryDraftRuntimeSubmission {
    public let plan: VoiceInkFillerWordSubmissionPlan
    public let draftStateAfterSubmit: VoiceInkFillerWordDraftState

    public init(
        plan: VoiceInkFillerWordSubmissionPlan,
        draftStateAfterSubmit: VoiceInkFillerWordDraftState
    ) {
        self.plan = plan
        self.draftStateAfterSubmit = draftStateAfterSubmit
    }

    public var alertPresentation: VoiceInkDictionaryAlertPresentation? {
        plan.alertPresentation
    }
}

public struct VoiceInkFillerWordDraftState: Equatable, Sendable {
    public var draft: String

    public init(draft: String = "") {
        self.draft = draft
    }

    public var canSubmit: Bool {
        VoiceInkFillerWords.hasDraft(draft)
    }

    public func submitting(existingWords: [String]) -> VoiceInkFillerWordDraftSubmission {
        let plan = VoiceInkFillerWords.submissionPlan(draft, existingWords: existingWords)
        return VoiceInkFillerWordDraftSubmission(
            plan: plan,
            draftStateAfterSubmit: VoiceInkFillerWordDraftState(draft: plan.draftAfterSubmit)
        )
    }
}

public struct VoiceInkFillerWordEditorPresentation: Equatable, Sendable {
    public let shouldShowEditor: Bool
    public let shouldShowWordList: Bool

    public init(
        shouldShowEditor: Bool,
        shouldShowWordList: Bool
    ) {
        self.shouldShowEditor = shouldShowEditor
        self.shouldShowWordList = shouldShowWordList
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

    public static func editorPresentation(
        isEnabled: Bool,
        words: [String]
    ) -> VoiceInkFillerWordEditorPresentation {
        VoiceInkFillerWordEditorPresentation(
            shouldShowEditor: isEnabled,
            shouldShowWordList: isEnabled && !words.isEmpty
        )
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
