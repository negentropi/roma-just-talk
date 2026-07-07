import SwiftData
import VoiceInkCore

@MainActor
enum DictionaryService {
    private static var cachedWordReplacementRules: [VoiceInkWordReplacementRule]?

    // MARK: - Vocabulary

    @discardableResult
    static func applyVocabularySubmission(
        _ submission: VoiceInkVocabularyDraftSubmission,
        context: ModelContext
    ) -> VoiceInkVocabularyDraftSubmission {
        submission.applyPersistenceRuntimeState { word in
            insertVocabularyWord(word, context: context)
        }
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
            return error.localizedDescription
        }
    }

    static func removeVocabularyWord(
        _ word: VocabularyWord,
        context: ModelContext
    ) -> VoiceInkDictionaryAlertPresentation? {
        context.delete(word)

        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return .vocabulary(
                message: VoiceInkDictionaryAlertPresentation.failedToRemoveVocabularyWord(
                    localizedDescription: error.localizedDescription
                )
            )
        }
    }

    // MARK: - Word Replacement

    @discardableResult
    static func applyWordReplacementSubmission(
        _ submission: VoiceInkWordReplacementDraftSubmission,
        context: ModelContext
    ) -> VoiceInkWordReplacementDraftSubmission {
        submission.applyPersistenceRuntimeState { rule in
            let entry = WordReplacement(originalText: rule.originalText, replacementText: rule.replacementText)
            context.insert(entry)
            do {
                try context.save()
                Self.invalidateWordReplacementCache()
                return nil
            } catch {
                context.delete(entry)
                return error.localizedDescription
            }
        }
    }

    @discardableResult
    static func updateWordReplacement(
        _ entry: WordReplacement,
        editState: VoiceInkWordReplacementEditState,
        context: ModelContext
    ) -> VoiceInkWordReplacementEditSubmission {
        let descriptor = FetchDescriptor<WordReplacement>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingRules = existing
            .filter { $0.id != entry.id }
            .map(\.voiceInkRule)

        let submission = editState.submitting(
            existingRules: existingRules
        )

        return applyWordReplacementEditSubmission(submission, to: entry, context: context)
    }

    @discardableResult
    private static func applyWordReplacementEditSubmission(
        _ submission: VoiceInkWordReplacementEditSubmission,
        to entry: WordReplacement,
        context: ModelContext
    ) -> VoiceInkWordReplacementEditSubmission {
        guard submission.shouldUpdate else { return submission }

        entry.originalText = submission.plan.originalText
        entry.replacementText = submission.plan.replacementText

        do {
            try context.save()
            Self.invalidateWordReplacementCache()
            return submission
        } catch {
            return VoiceInkWordReplacementEditSubmission(
                submittedOriginal: submission.submittedOriginal,
                submittedReplacement: submission.submittedReplacement,
                plan: submission.plan,
                alertPresentation: .wordReplacement(
                    message: VoiceInkDictionaryAlertPresentation.failedToSaveWordReplacementChanges(
                        localizedDescription: error.localizedDescription
                    )
                )
            )
        }
    }

    static func removeWordReplacement(
        _ replacement: WordReplacement,
        context: ModelContext
    ) -> VoiceInkDictionaryAlertPresentation? {
        context.delete(replacement)

        do {
            try context.save()
            Self.invalidateWordReplacementCache()
            return nil
        } catch {
            context.rollback()
            return .wordReplacement(
                message: VoiceInkDictionaryAlertPresentation.failedToRemoveWordReplacement(
                    localizedDescription: error.localizedDescription
                )
            )
        }
    }

    static func warmWordReplacementCache(using context: ModelContext) {
        _ = replacementRules(using: context)
    }

    static func invalidateWordReplacementCache() {
        cachedWordReplacementRules = nil
    }

    static func applyWordReplacements(to text: String, using context: ModelContext) -> String {
        let replacements = replacementRules(using: context)
        return VoiceInkWordReplacementEngine.apply(replacements, to: text)
    }

    private static func replacementRules(using context: ModelContext) -> [VoiceInkWordReplacementRule] {
        if let cachedWordReplacementRules {
            return cachedWordReplacementRules
        }

        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        let rules = (try? context.fetch(descriptor))?.map(\.voiceInkRule) ?? []

        cachedWordReplacementRules = rules
        return rules
    }
}
