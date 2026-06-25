import SwiftData
import VoiceInkCore

enum DictionaryService {

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
                WordReplacementService.shared.invalidateCache()
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
            WordReplacementService.shared.invalidateCache()
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
}
