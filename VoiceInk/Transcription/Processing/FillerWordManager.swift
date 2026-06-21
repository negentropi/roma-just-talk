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

    func applySubmissionPlan(_ plan: VoiceInkFillerWordSubmissionPlan) {
        if fillerWords != plan.updatedWords {
            fillerWords = plan.updatedWords
        }
    }

    func removeWord(_ word: String) {
        fillerWords = VoiceInkFillerWords.removing(word, from: fillerWords)
    }

}
