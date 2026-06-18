import Foundation
import SwiftData
import VoiceInkCore

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func getCustomVocabulary(from context: ModelContext) -> String {
        let customWords = rawCustomVocabularyTerms(from: context)
        guard !customWords.isEmpty else {
            return ""
        }

        return VoiceInkAIEnhancementVocabularyContext.formatted(from: customWords)
    }

    func getCustomVocabularyTerms(from context: ModelContext, for use: VoiceInkCustomVocabularyUse) -> [String] {
        VoiceInkCustomVocabularyTerms.normalized(rawCustomVocabularyTerms(from: context), for: use)
    }

    func rawCustomVocabularyTerms(from context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\VocabularyWord.word)])

        do {
            let items = try context.fetch(descriptor)
            return items.map { $0.word }
        } catch {
            return []
        }
    }
}
