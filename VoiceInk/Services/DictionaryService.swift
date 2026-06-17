import SwiftData
import VoiceInkCore

enum DictionaryService {

    // MARK: - Vocabulary

    /// Adds one or more comma-separated words to vocabulary.
    /// Returns an error message string if something went wrong, nil on success.
    @discardableResult
    static func addVocabularyWords(
        _ input: String,
        existing: [VocabularyWord],
        context: ModelContext
    ) -> String? {
        let plan = VoiceInkDictionaryPolicy.vocabularyInsertPlan(
            input: input,
            existingWords: existing.map(\.word)
        )

        if let errorMessage = plan.errorMessage {
            return errorMessage
        }

        guard plan.shouldInsert else { return nil }

        var errors = [String]()
        for word in plan.wordsToInsert {
            if let error = insertVocabularyWord(word, context: context) {
                errors.append(error)
            }
        }
        return errors.isEmpty ? nil : errors.joined(separator: "; ")
    }

    @discardableResult
    private static func insertVocabularyWord(_ word: String, context: ModelContext) -> String? {
        let entry = VocabularyWord(word: word)
        context.insert(entry)
        do {
            try context.save()
            return nil
        } catch {
            context.delete(entry)
            return "Failed to add '\(word)': \(error.localizedDescription)"
        }
    }

    // MARK: - Word Replacement

    /// Adds a word replacement entry (original may be comma-separated).
    /// Returns an error message string if something went wrong, nil on success.
    @discardableResult
    static func addWordReplacement(
        original: String,
        replacement: String,
        existing: [WordReplacement],
        context: ModelContext
    ) -> String? {
        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existing.map(\.originalText)
        )

        if let errorMessage = plan.errorMessage {
            return errorMessage
        }

        guard plan.shouldInsert else { return nil }

        let entry = WordReplacement(originalText: plan.originalText, replacementText: plan.replacementText)
        context.insert(entry)
        do {
            try context.save()
            WordReplacementService.shared.invalidateCache()
            return nil
        } catch {
            context.delete(entry)
            return "Failed to add replacement: \(error.localizedDescription)"
        }
    }

    @discardableResult
    static func updateWordReplacement(
        _ entry: WordReplacement,
        original: String,
        replacement: String,
        context: ModelContext
    ) -> String? {
        let descriptor = FetchDescriptor<WordReplacement>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingOriginalTexts = existing
            .filter { $0.id != entry.id }
            .map(\.originalText)

        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existingOriginalTexts
        )

        if let errorMessage = plan.errorMessage {
            return errorMessage
        }

        guard plan.shouldInsert else { return nil }

        entry.originalText = plan.originalText
        entry.replacementText = plan.replacementText

        do {
            try context.save()
            WordReplacementService.shared.invalidateCache()
            return nil
        } catch {
            return "Failed to save changes: \(error.localizedDescription)"
        }
    }

    static func canSaveWordReplacement(original: String, replacement: String) -> Bool {
        VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: []
        ).shouldInsert
    }
}
