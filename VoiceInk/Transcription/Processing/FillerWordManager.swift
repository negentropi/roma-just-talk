import Foundation
import VoiceInkCore

class FillerWordManager: ObservableObject {
    static let shared = FillerWordManager()

    private let removeFillerWordsKey = VoiceInkUserDefaultsKey.removeFillerWords

    @Published var fillerWords: [String] {
        didSet {
            VoiceInkFillerWordPreference.saveWords(fillerWords)
        }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: removeFillerWordsKey)
    }

    private init() {
        self.fillerWords = VoiceInkFillerWordPreference.words()
    }

    func addWord(_ word: String) -> Bool {
        guard let updatedWords = VoiceInkFillerWords.adding(word, to: fillerWords) else {
            return false
        }

        fillerWords = updatedWords
        return true
    }

    func removeWord(_ word: String) {
        fillerWords = VoiceInkFillerWords.removing(word, from: fillerWords)
    }

}
