import SwiftData
import VoiceInkCore

enum DictionaryService {

    // MARK: - Vocabulary

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
            alertPresentation: VoiceInkDictionaryAlertPresentation.failedToAddVocabularyWords(errors)
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
    static func applyWordReplacementSubmission(
        _ submission: VoiceInkWordReplacementDraftSubmission,
        context: ModelContext
    ) -> VoiceInkWordReplacementDraftSubmission {
        let plan = submission.plan
        guard let rule = plan.ruleToInsert else { return submission }

        let entry = WordReplacement(originalText: rule.originalText, replacementText: rule.replacementText)
        context.insert(entry)
        do {
            try context.save()
            WordReplacementService.shared.invalidateCache()
            return submission
        } catch {
            context.delete(entry)
            let failurePlan = VoiceInkWordReplacementSubmissionPlan(
                ruleToInsert: rule,
                originalDraftAfterSubmit: submission.submittedOriginal,
                replacementDraftAfterSubmit: submission.submittedReplacement,
                alertPresentation: .wordReplacement(
                    message: VoiceInkDictionaryAlertPresentation.failedToAddWordReplacement(
                        localizedDescription: error.localizedDescription
                    )
                )
            )
            return VoiceInkWordReplacementDraftSubmission(
                submittedOriginal: submission.submittedOriginal,
                submittedReplacement: submission.submittedReplacement,
                plan: failurePlan,
                draftStateAfterSubmit: VoiceInkWordReplacementDraftState(
                    original: failurePlan.originalDraftAfterSubmit,
                    replacement: failurePlan.replacementDraftAfterSubmit
                )
            )
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
