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
        if let updatedWords = plan.updatedWordsIfChanged(from: fillerWords) {
            fillerWords = updatedWords
        }
    }

    func removeWord(_ word: String) {
        fillerWords = VoiceInkFillerWords.removing(word, from: fillerWords)
    }

}
