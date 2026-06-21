import SwiftData
import VoiceInkCore

enum DictionaryService {

    // MARK: - Vocabulary

    @discardableResult
    static func submitVocabularyDraft(
        _ input: String,
        existing: [VocabularyWord],
        context: ModelContext
    ) -> VoiceInkVocabularySubmissionPlan {
        let submission = VoiceInkVocabularyDraftState(draft: input).submitting(
            existingWords: existing.map(\.word)
        )
        return applyVocabularySubmission(submission, context: context).plan
    }

    @discardableResult
    static func applyVocabularySubmission(
        _ submission: VoiceInkVocabularyDraftSubmission,
        context: ModelContext
    ) -> VoiceInkVocabularyDraftSubmission {
        let plan = submission.plan
        guard plan.shouldInsert else { return submission }

        var errors = [String]()
        for word in plan.wordsToInsert {
            if let error = insertVocabularyWord(word, context: context) {
                errors.append(error)
            }
        }

        guard !errors.isEmpty else { return submission }

        let failurePlan = VoiceInkVocabularySubmissionPlan(
            wordsToInsert: plan.wordsToInsert,
            draftAfterSubmit: submission.submittedDraft,
            alertPresentation: .vocabulary(message: errors.joined(separator: "; "))
        )
        return VoiceInkVocabularyDraftSubmission(
            submittedDraft: submission.submittedDraft,
            plan: failurePlan,
            draftStateAfterSubmit: VoiceInkVocabularyDraftState(draft: failurePlan.draftAfterSubmit)
        )
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
            return VoiceInkDictionaryAlertPresentation.failedToAddVocabularyWord(
                word,
                localizedDescription: error.localizedDescription
            )
        }
    }

    // MARK: - Word Replacement

    @discardableResult
    static func submitWordReplacementDraft(
        original: String,
        replacement: String,
        existing: [WordReplacement],
        context: ModelContext
    ) -> VoiceInkWordReplacementSubmissionPlan {
        let plan = VoiceInkDictionaryPolicy.wordReplacementSubmissionPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: existing.map(\.originalText)
        )

        guard let rule = plan.ruleToInsert else { return plan }

        let entry = WordReplacement(originalText: rule.originalText, replacementText: rule.replacementText)
        context.insert(entry)
        do {
            try context.save()
            WordReplacementService.shared.invalidateCache()
            return plan
        } catch {
            context.delete(entry)
            return VoiceInkWordReplacementSubmissionPlan(
                ruleToInsert: rule,
                originalDraftAfterSubmit: original,
                replacementDraftAfterSubmit: replacement,
                alertPresentation: .wordReplacement(
                    message: VoiceInkDictionaryAlertPresentation.failedToAddWordReplacement(
                        localizedDescription: error.localizedDescription
                    )
                )
            )
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
            return VoiceInkDictionaryAlertPresentation.failedToSaveWordReplacementChanges(
                localizedDescription: error.localizedDescription
            )
        }
    }
}
