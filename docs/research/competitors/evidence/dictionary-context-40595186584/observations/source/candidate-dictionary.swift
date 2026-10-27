import Foundation
import SwiftData
import VoiceInkCore
import os

@MainActor
enum DictionaryService {
    private static let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "DictionaryService")

    struct LibraryConflictError: LocalizedError {
        let conflicts: [VoiceInkWordReplacementLibraryConflict]

        var errorDescription: String? {
            "The replacement conflicts with \(conflicts.count) saved rule(s). Review the conflicting entries before saving."
        }
    }

    struct LibraryDuplicateError: LocalizedError {
        let duplicates: [VoiceInkWordReplacementLibraryDuplicate]

        var errorDescription: String? { "This replacement is already saved." }
    }

    struct LibraryRevisionError: LocalizedError {
        let expected: VoiceInkWordReplacementRecord
        let current: VoiceInkWordReplacementRecord

        var errorDescription: String? { "This replacement changed while it was open. Reopen it to review the current values." }
    }

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

    static func addWordReplacement(
        originalText: String,
        replacementText: String,
        context: ModelContext
    ) throws -> WordReplacement {
        // Manual Dictionary entries retain their comma-alternative and trimming contract.
        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: originalText, replacement: replacementText, existingOriginalTexts: []
        )
        let record = try VoiceInkWordReplacementRecord(
            id: UUID(), originalText: plan.originalText, replacementText: plan.replacementText,
            dateAdded: Date(), isEnabled: true, matchingKind: .legacyCommaAlternatives
        )
        return try insertWordReplacement(record, context: context)
    }

    static func updateWordReplacement(
        _ entry: WordReplacement,
        expectedRecord: VoiceInkWordReplacementRecord,
        originalText: String,
        replacementText: String,
        context: ModelContext
    ) throws {
        let previous = try entry.record
        guard previous == expectedRecord else { throw LibraryRevisionError(expected: expectedRecord, current: previous) }
        let source: String
        let replacement: String
        switch previous.matchingKind {
        case .literal:
            source = originalText
            replacement = replacementText
        case .legacyCommaAlternatives:
            let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
                original: originalText, replacement: replacementText, existingOriginalTexts: []
            )
            source = plan.originalText
            replacement = plan.replacementText
        }
        let updated = try VoiceInkWordReplacementRecord(
            id: previous.id, originalText: source, replacementText: replacement,
            dateAdded: previous.dateAdded, isEnabled: previous.isEnabled,
            matchingKind: previous.matchingKind, provenance: previous.provenance
        )
        guard updated != previous else { return }
        try validateInsertion(updated, excluding: entry.id, context: context)
        setText(of: entry, from: updated)

        do {
            try context.save()
        } catch {
            setText(of: entry, from: previous)
            throw error
        }
    }

    static func setWordReplacementEnabled(
        _ entry: WordReplacement,
        isEnabled: Bool,
        context: ModelContext
    ) throws {
        guard entry.isEnabled != isEnabled else { return }
        if isEnabled { try validateInsertion(entry.record, excluding: entry.id, context: context) }
        let previous = entry.isEnabled
        entry.isEnabled = isEnabled
        do {
            try context.save()
        } catch {
            entry.isEnabled = previous
            throw error
        }
    }

    static func removeWordReplacement(
        _ replacement: WordReplacement,
        context: ModelContext
    ) -> VoiceInkDictionaryAlertPresentation? {
        context.delete(replacement)

        do {
            try context.save()
            return nil
        } catch {
            // Undo only this pending deletion; another editor may have unsaved changes.
            context.insert(replacement)
            return .wordReplacement(
                message: VoiceInkDictionaryAlertPresentation.failedToRemoveWordReplacement(
                    localizedDescription: error.localizedDescription
                )
            )
        }
    }

    static func applyWordReplacements(to text: String, using context: ModelContext) -> String {
        do {
            return VoiceInkWordReplacementEngine.apply(try snapshotEnabledReplacementRules(using: context), to: text)
        } catch {
            logger.error("Word replacement library unavailable; leaving text unchanged.")
            return text
        }
    }

    static func snapshotEnabledReplacementRules(using context: ModelContext) throws -> [VoiceInkWordReplacementRule] {
        try context.fetch(FetchDescriptor<WordReplacement>())
            .filter(\.isEnabled)
            .map { try $0.voiceInkRule }
    }

    static func snapshotWordReplacementRecords(using context: ModelContext) throws -> [VoiceInkWordReplacementRecord] {
        try context.fetch(FetchDescriptor<WordReplacement>()).map { try $0.record }
    }

    private static func validateInsertion(
        _ record: VoiceInkWordReplacementRecord,
        excluding id: UUID?,
        context: ModelContext
    ) throws {
        let existing = try snapshotWordReplacementRecords(using: context).filter { $0.id != id }
        let plan = VoiceInkWordReplacementLibrary(records: [record]).preflightImport(existingRecords: existing)
        guard plan.canApply else { throw LibraryConflictError(conflicts: plan.conflicts) }
        guard plan.duplicates.isEmpty else { throw LibraryDuplicateError(duplicates: plan.duplicates) }
    }

    private static func setText(of entry: WordReplacement, from record: VoiceInkWordReplacementRecord) {
        switch record.matchingKind {
        case .legacyCommaAlternatives:
            entry.originalText = record.originalText
            entry.replacementText = record.replacementText
        case .literal:
            entry.literalOriginalText = record.originalText
            entry.literalReplacementText = record.replacementText
        }
    }

    static func insertWordReplacement(
        _ record: VoiceInkWordReplacementRecord,
        context: ModelContext
    ) throws -> WordReplacement {
        try validateInsertion(record, excluding: nil, context: context)
        let entry = WordReplacement(record: record)
        context.insert(entry)
        do {
            try context.save()
            return entry
        } catch {
            context.delete(entry)
            throw error
        }
    }
}
