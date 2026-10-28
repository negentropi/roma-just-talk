import Foundation
import SwiftData
import VoiceInkCore

@MainActor
enum DictionaryBackup {
    struct Export {
        let vocabularyWords: [VoiceInkVocabularyWordBackup]?
        let legacyWordReplacements: [String: String]?
        let wordReplacementLibrary: VoiceInkWordReplacementLibrary
    }

    @MainActor
    struct PreparedImport {
        private let vocabularyWords: [VoiceInkVocabularyWordBackup]?
        private let legacyWordReplacements: [String: String]?
        private let wordReplacementLibrary: VoiceInkWordReplacementLibrary?

        fileprivate init<Shortcut: Codable>(_ backup: VoiceInkSettingsBackupFile<Shortcut>) {
            vocabularyWords = backup.vocabularyWords
            legacyWordReplacements = backup.wordReplacements
            wordReplacementLibrary = backup.wordReplacementLibrary
        }

        fileprivate func rows(using context: ModelContext) throws -> Rows {
            let existingWords = vocabularyWords == nil ? [] : try context.fetch(FetchDescriptor<VocabularyWord>()).map(\.word)
            let words = vocabularyWords.map {
                VoiceInkDictionaryPolicy.vocabularyWordsToInsert(from: $0, existingWords: existingWords)
            } ?? []

            if let wordReplacementLibrary {
                let existing = try DictionaryService.snapshotWordReplacementRecords(using: context)
                let plan = wordReplacementLibrary.preflightImport(existingRecords: existing)
                guard plan.canApply else { throw DictionaryService.LibraryConflictError(conflicts: plan.conflicts) }
                return Rows(vocabulary: words, replacements: plan.recordsToInsert, skippedInvalid: 0)
            }

            guard let legacyWordReplacements else {
                return Rows(vocabulary: words, replacements: [], skippedInvalid: 0)
            }
            let existingOriginals = try DictionaryService.snapshotWordReplacementRecords(using: context).map(\.originalText)
            let plan = VoiceInkDictionaryPolicy.wordReplacementBackupImportPlan(
                from: legacyWordReplacements, existingOriginalTexts: existingOriginals
            )
            let records = try plan.rulesToInsert.map { rule in
                try VoiceInkWordReplacementRecord(
                    id: UUID(), originalText: rule.originalText, replacementText: rule.replacementText,
                    dateAdded: Date(), isEnabled: true, matchingKind: .legacyCommaAlternatives
                )
            }
            return Rows(vocabulary: words, replacements: records, skippedInvalid: plan.skippedInvalidReplacementCount)
        }

        func apply(using context: ModelContext) throws {
            // Review and application may be separated by UI; recheck conflicts before any insertion.
            let rows = try rows(using: context)
            if vocabularyWords == nil { print(VoiceInkSettingsBackupImportDiagnostics.noVocabularyWordsMessage) }
            if wordReplacementLibrary == nil && legacyWordReplacements == nil {
                print(VoiceInkSettingsBackupImportDiagnostics.noWordReplacementsMessage)
            }
            guard !rows.vocabulary.isEmpty || !rows.replacements.isEmpty else {
                print(VoiceInkSettingsBackupImportDiagnostics.noDictionaryEntriesImportedMessage)
                if rows.skippedInvalid > 0 {
                    print(VoiceInkSettingsBackupImportDiagnostics.skippedInvalidReplacementsMessage(count: rows.skippedInvalid))
                }
                return
            }

            let insertedWords = rows.vocabulary.map { VocabularyWord(word: $0) }
            let insertedReplacements = rows.replacements.map { WordReplacement(record: $0) }
            insertedWords.forEach(context.insert)
            insertedReplacements.forEach(context.insert)
            do {
                try context.save()
            } catch {
                // A failed import owns these insertions, not unrelated unsaved work in this context.
                insertedWords.forEach(context.delete)
                insertedReplacements.forEach(context.delete)
                throw VoiceInkSettingsBackupImportError.saveFailed(
                    item: "dictionary entries", localizedDescription: error.localizedDescription
                )
            }
            print(VoiceInkSettingsBackupImportDiagnostics.dictionaryEntriesImportedMessage(
                vocabularyWordCount: insertedWords.count, wordReplacementCount: insertedReplacements.count
            ))
            if rows.skippedInvalid > 0 {
                print(VoiceInkSettingsBackupImportDiagnostics.skippedInvalidReplacementsMessage(count: rows.skippedInvalid))
            }
        }
    }

    fileprivate struct Rows {
        let vocabulary: [String]
        let replacements: [VoiceInkWordReplacementRecord]
        let skippedInvalid: Int
    }

    static func prepareImport<Shortcut: Codable>(
        _ backup: VoiceInkSettingsBackupFile<Shortcut>, using context: ModelContext
    ) throws -> PreparedImport {
        let prepared = PreparedImport(backup)
        _ = try prepared.rows(using: context)
        return prepared
    }

    static func export(using context: ModelContext) throws -> Export {
        let words = try context.fetch(FetchDescriptor<VocabularyWord>()).map(\.word)
        let records = try DictionaryService.snapshotWordReplacementRecords(using: context)
        let rules = records.map {
            VoiceInkWordReplacementRule(
                originalText: $0.originalText, replacementText: $0.replacementText, matchingKind: $0.matchingKind
            )
        }
        let plan = VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(vocabularyWords: words, wordReplacementRules: rules)
        var vocabulary: [VoiceInkVocabularyWordBackup]?
        var legacy: [String: String]?
        plan.applyRuntimeState(
            setVocabularyBackupRecords: { vocabulary = $0 }, setWordReplacementBackupRecords: { legacy = $0 }
        )
        return Export(
            vocabularyWords: vocabulary, legacyWordReplacements: legacy,
            wordReplacementLibrary: VoiceInkWordReplacementLibrary(records: records)
        )
    }
}

extension VoiceInkCustomCloudModelBackup {
    init(model: CustomCloudModel) {
        self.init(
            id: model.id,
            name: model.name,
            displayName: model.displayName,
            description: model.description,
            apiEndpoint: model.apiEndpoint,
            modelName: model.modelName,
            isMultilingualModel: model.isMultilingualModel,
            supportedLanguages: model.supportedLanguages,
            apiKey: nil
        )
    }

    func makeModel() -> CustomCloudModel {
        return importPlan.applyRuntimeState(
            makeModel: { id, name, displayName, description, apiEndpoint, modelName, isMultilingualModel, supportedLanguages in
                CustomCloudModel(
                    id: id,
                    name: name,
                    displayName: displayName,
                    description: description,
                    apiEndpoint: apiEndpoint,
                    modelName: modelName,
                    isMultilingual: isMultilingualModel,
                    supportedLanguages: supportedLanguages
                )
            },
            restoreAPIKey: { apiKey, modelId in
                APIKeyManager.shared.saveCustomModelAPIKey(apiKey, forModelId: modelId)
            }
        )
    }
}
