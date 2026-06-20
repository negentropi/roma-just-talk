import Foundation
import VoiceInkCore

class FillerWordManager: ObservableObject {
    static let shared = FillerWordManager()

    @Published var fillerWords: [String] {
        didSet {
            VoiceInkFillerWordPreference.saveWords(fillerWords)
        }
    }

    var isEnabled: Bool {
        VoiceInkTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords()
    }

    private init() {
        self.fillerWords = VoiceInkFillerWordPreference.words()
    }

    @discardableResult
    func submitWordDraft(_ draft: String) -> VoiceInkFillerWordSubmissionPlan {
        let plan = VoiceInkFillerWords.submissionPlan(draft, existingWords: fillerWords)
        if fillerWords != plan.updatedWords {
            fillerWords = plan.updatedWords
        }
        return plan
    }

    func removeWord(_ word: String) {
        fillerWords = VoiceInkFillerWords.removing(word, from: fillerWords)
    }

}
