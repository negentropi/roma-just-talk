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

    enum LibraryEntryError: LocalizedError, Equatable {
        case unavailable
        case changed

        var errorDescription: String? {
            switch self {
            case .unavailable: "This replacement could not be found. Reopen the Dictionary to review the current entries."
            case .changed: "This replacement changed while it was open. Reopen it to review the current values."
            }
        }
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
        try requireOwned(entry, context: context)
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
        try validateInsertion(updated, excluding: entry.id, context: context)
        try DictionaryPersistence.commit(in: context.container) { writer in
            let stored = try storedReplacement(id: previous.id, using: writer)
            let current = try stored.record
            guard current == expectedRecord else {
                throw LibraryRevisionError(expected: expectedRecord, current: current)
            }
            guard updated != current else { return }
            try validateInsertion(updated, excluding: previous.id, context: writer)
            setText(of: stored, from: updated)
        }
        _ = try DictionaryPersistence.refresh(in: context)
    }

    static func setWordReplacementEnabled(
        _ entry: WordReplacement,
        isEnabled: Bool,
        context: ModelContext
    ) throws {
        try requireOwned(entry, context: context)
        let previous = DictionaryPersistence.StoredRevision(entry)
        if isEnabled { try validateInsertion(entry.record, excluding: entry.id, context: context) }
        try DictionaryPersistence.commit(in: context.container) { writer in
            let stored = try storedReplacement(id: previous.id, using: writer)
            guard previous.matches(stored) else { throw LibraryEntryError.changed }
            guard stored.isEnabled != isEnabled else { return }
            if isEnabled { try validateInsertion(stored.record, excluding: previous.id, context: writer) }
            stored.isEnabled = isEnabled
        }
        _ = try DictionaryPersistence.refresh(in: context)
    }

    static func removeWordReplacement(
        _ replacement: WordReplacement,
        context: ModelContext
    ) -> VoiceInkDictionaryAlertPresentation? {
        do {
            try requireOwned(replacement, context: context)
            let previous = DictionaryPersistence.StoredRevision(replacement)
            try DictionaryPersistence.commit(in: context.container) { writer in
                let stored = try storedReplacement(id: previous.id, using: writer)
                guard previous.matches(stored) else { throw LibraryEntryError.changed }
                writer.delete(stored)
            }
            _ = try DictionaryPersistence.refresh(in: context)
            return nil
        } catch let error as DictionaryPersistence.RefreshFailure {
            return .wordReplacement(message: error.localizedDescription)
        } catch {
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
        let savedID = try DictionaryPersistence.commit(in: context.container) { writer in
            try validateInsertion(record, excluding: nil, context: writer)
            let entry = WordReplacement(record: record)
            writer.insert(entry)
            // Resolve the caller's model by value identity only after the writer saves.
            return entry.id
        }
        return try savedReplacement(id: savedID, using: context)
    }

    private static func requireOwned(_ entry: WordReplacement, context: ModelContext) throws {
        guard !entry.isDeleted, entry.modelContext === context else { throw LibraryEntryError.unavailable }
    }

    private static func storedReplacement(id: UUID, using context: ModelContext) throws -> WordReplacement {
        let entries = try context.fetch(FetchDescriptor<WordReplacement>()).filter { $0.id == id }
        guard entries.count == 1, let entry = entries.first else { throw LibraryEntryError.unavailable }
        return entry
    }

    static func savedReplacement(id: UUID, using context: ModelContext) throws -> WordReplacement {
        let entries = try DictionaryPersistence.refresh(in: context).filter { $0.id == id }
        guard entries.count == 1, let entry = entries.first else {
            throw DictionaryPersistence.RefreshFailure(underlying: LibraryEntryError.unavailable)
        }
        return entry
    }
}
