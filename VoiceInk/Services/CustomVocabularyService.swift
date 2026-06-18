import Foundation
import SwiftData
import VoiceInkCore

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func getCustomVocabulary(from context: ModelContext) -> String {
        guard let customWords = getCustomVocabularyWords(from: context), !customWords.isEmpty else {
            return ""
        }

        return VoiceInkAIEnhancementVocabularyContext.formatted(from: customWords)
    }

    func getCustomVocabularyTerms(from context: ModelContext, limit: Int? = nil) -> [String] {
        guard let customWords = getCustomVocabularyWords(from: context) else {
            return []
        }

        return VoiceInkCustomVocabularyTerms.normalized(customWords, limit: limit)
    }

    private func getCustomVocabularyWords(from context: ModelContext) -> [String]? {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\VocabularyWord.word)])

        do {
            let items = try context.fetch(descriptor)
            let words = items.map { $0.word }
            return words.isEmpty ? nil : words
        } catch {
            return nil
        }
    }
}
