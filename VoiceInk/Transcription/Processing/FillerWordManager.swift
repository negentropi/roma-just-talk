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
    func addWord(_ word: String) -> String? {
        let plan = VoiceInkFillerWords.insertPlan(word, existingWords: fillerWords)

        if let errorMessage = plan.errorMessage {
            return errorMessage
        }

        guard let wordToInsert = plan.wordToInsert else {
            return nil
        }

        fillerWords = fillerWords + [wordToInsert]
        return nil
    }

    func removeWord(_ word: String) {
        fillerWords = VoiceInkFillerWords.removing(word, from: fillerWords)
    }

}
