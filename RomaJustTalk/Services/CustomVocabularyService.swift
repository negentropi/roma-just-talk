import Foundation
import SwiftData
import RomaCore

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func getCustomVocabulary(from context: ModelContext) -> String {
        RomaAIEnhancementVocabularyContext.formatted(from: rawCustomVocabularyTerms(from: context))
    }

    func getCustomVocabularyTerms(from context: ModelContext, for use: RomaCustomVocabularyUse) -> [String] {
        RomaCustomVocabularyTerms.normalized(rawCustomVocabularyTerms(from: context), for: use)
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
