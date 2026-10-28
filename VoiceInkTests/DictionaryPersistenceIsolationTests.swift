import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct DictionaryPersistenceIsolationTests {
        @Test @MainActor func successfulRuleMutationsRefreshTheRegisteredRowWithoutSavingBystanders() throws {
            let fixture = try DictionaryIsolationFixture()
            try fixture.expectBystandersRemainUnsaved()
            let inserted = try DictionaryService.addWordReplacement(
                originalText: "owned phrase", replacementText: "initial", context: fixture.caller
            )
            let id = inserted.id
            let retained = try fixture.callerRow(id)
            let initial = try retained.record
            #expect(try initial == inserted.record)
            #expect(try fixture.persistedRecord(id) == initial)
            try fixture.expectBystandersRemainUnsaved()

            let editedText = "$5.00\\Temp\r\n e\u{301} 🧪"
            try DictionaryService.updateWordReplacement(
                retained, expectedRecord: initial, originalText: initial.originalText,
                replacementText: editedText, context: fixture.caller
            )
            #expect(retained.replacementText.utf16.elementsEqual(editedText.utf16))
            #expect(try fixture.callerRow(id) === retained)
            #expect(try fixture.persistedRecord(id) == retained.record)
            try fixture.expectBystandersRemainUnsaved()

            try DictionaryService.setWordReplacementEnabled(retained, isEnabled: false, context: fixture.caller)
            #expect(!retained.isEnabled)
            #expect(try fixture.callerRow(id) === retained)
            #expect(try !fixture.persistedRecord(id).isEnabled)
            try fixture.expectBystandersRemainUnsaved()
            try DictionaryService.setWordReplacementEnabled(retained, isEnabled: true, context: fixture.caller)
            #expect(retained.isEnabled)
            #expect(try fixture.persistedRecord(id).isEnabled)
            try fixture.expectBystandersRemainUnsaved()

            let lastEnabledState = retained.isEnabled
            #expect(DictionaryService.removeWordReplacement(retained, context: fixture.caller) == nil)
            #expect(try !fixture.caller.fetch(FetchDescriptor<WordReplacement>()).contains { $0.id == id })
            #expect(try !fixture.freshContext().fetch(FetchDescriptor<WordReplacement>()).contains { $0.id == id })
            try fixture.expectBystandersRemainUnsaved()
            do {
                try DictionaryService.setWordReplacementEnabled(retained, isEnabled: lastEnabledState, context: fixture.caller)
                Issue.record("A no-op enable request accepted a deleted retained row.")
            } catch let error as DictionaryService.LibraryEntryError {
                #expect(error == .unavailable)
            }
            #expect(try !fixture.caller.fetch(FetchDescriptor<WordReplacement>()).contains { $0.id == id })
            #expect(try !fixture.freshContext().fetch(FetchDescriptor<WordReplacement>()).contains { $0.id == id })
            try fixture.expectBystandersRemainUnsaved()
        }

        @Test @MainActor func approvalAndBulkImportCommitExactRecordsWithoutSavingBystanders() throws {
            let fixture = try DictionaryIsolationFixture()
            try fixture.expectBystandersRemainUnsaved()
            let text = "Send this to Hills, Inc tomorrow."
            let sourceRow = Transcription(text: "processed text", duration: 1, recognitionText: text)
            fixture.library.context.insert(sourceRow)
            try fixture.library.context.save()
            try fixture.expectBystandersRemainUnsaved()
            let source = try HistoryCorrectionApprovalService.capture(
                transcriptionID: sourceRow.id, variant: .recognition, expectedText: text, using: fixture.caller
            )
            let range = try #require(HistoryCorrectionApprovalService.occurrences(of: "Hills, Inc", in: source).first)
            let preview = try HistoryCorrectionApprovalService.preview(
                source: source, range: range, replacementText: " $5.00\\Temp\r\n e\u{301} 🧪 ", using: fixture.caller
            )
            guard case .inserted(let approved) = try HistoryCorrectionApprovalService.approve(preview, using: fixture.caller) else {
                Issue.record("New approval did not create its one literal record."); return
            }
            #expect(try approved.record == preview.record)
            #expect(try fixture.callerRow(preview.record.id).record == preview.record)
            #expect(try fixture.persistedRecord(preview.record.id) == preview.record)
            #expect(try fixture.callerRow(preview.record.id).originalText.isEmpty)
            try fixture.expectBystandersRemainUnsaved()

            let imported = try VoiceInkWordReplacementRecord(
                id: UUID(), originalText: "Another, Inc", replacementText: "\tLiteral e\u{301} 🧪\r\n",
                dateAdded: Date(timeIntervalSince1970: 1_700_000_123.125), isEnabled: false, matchingKind: .literal,
                provenance: .init(sourceTranscriptionID: sourceRow.id, sourceVariant: .processed)
            )
            let backup = VoiceInkSettingsBackupFile<ShortcutBackup>(
                version: "1.95.2", customPrompts: [], powerModeConfigs: [], powerModeShortcuts: nil,
                vocabularyWords: [.init(word: "Imported vocabulary")], wordReplacements: ["ignored": "legacy"],
                generalSettings: nil, customEmojis: nil, customCloudModels: nil,
                wordReplacementLibrary: .init(records: [imported])
            )
            try DictionaryBackup.prepareImport(backup, using: fixture.caller).apply(using: fixture.caller)
            #expect(try fixture.callerRow(imported.id).record == imported)
            #expect(try fixture.persistedRecord(imported.id) == imported)
            let persisted = fixture.freshContext()
            #expect(try persisted.fetch(FetchDescriptor<WordReplacement>()).count == 3)
            #expect(try fixture.caller.fetch(FetchDescriptor<WordReplacement>()).count == 3)
            #expect(try persisted.fetch(FetchDescriptor<VocabularyWord>()).contains { $0.word == "Imported vocabulary" })
            #expect(try fixture.caller.fetch(FetchDescriptor<VocabularyWord>()).contains { $0.word == "Imported vocabulary" })
            try fixture.expectBystandersRemainUnsaved()
        }

        @Test @MainActor func staleExpectedRuleCannotOverwriteAnExternalCommittedRevision() throws {
            enum Action: Equatable { case sameStateToggle, unchangedSave, changedSave }
            for action in [Action.sameStateToggle, .unchangedSave, .changedSave] {
                let fixture = try DictionaryIsolationFixture()
                try fixture.expectBystandersRemainUnsaved()
                let created = try DictionaryService.addWordReplacement(
                    originalText: "owned phrase", replacementText: "initial", context: fixture.caller
                )
                let retained = try fixture.callerRow(created.id)
                let expected = try retained.record
                try fixture.expectBystandersRemainUnsaved()
                let writer = fixture.freshContext()
                let external = try #require(writer.fetch(FetchDescriptor<WordReplacement>()).first { $0.id == created.id })
                external.replacementText = "External e\u{301} 🧪"
                try writer.save()
                let committed = try external.record

                // Each branch's product call is the first caller read after the external save.
                switch action {
                case .sameStateToggle:
                    do {
                        try DictionaryService.setWordReplacementEnabled(
                            retained, isEnabled: expected.isEnabled, context: fixture.caller
                        )
                        Issue.record("A stale no-op enable request accepted an externally changed retained row.")
                    } catch let error as DictionaryService.LibraryEntryError {
                        #expect(error == .changed)
                    }
                case .unchangedSave, .changedSave:
                    let replacement = action == .unchangedSave ? expected.replacementText : "must not overwrite"
                    do {
                        try DictionaryService.updateWordReplacement(
                            retained, expectedRecord: expected, originalText: expected.originalText,
                            replacementText: replacement, context: fixture.caller
                        )
                        Issue.record("Stale caller revision was accepted, including an unchanged Save.")
                    } catch let error as DictionaryService.LibraryRevisionError {
                        #expect(error.expected == expected)
                        #expect(error.current == committed)
                    }
                }
                #expect(try fixture.persistedRecord(created.id) == committed)
                #expect(try fixture.freshContext().fetch(FetchDescriptor<WordReplacement>()).count == 2)
                try fixture.expectBystandersRemainUnsaved()
            }
        }

        @Test @MainActor func staleHistoryPreviewRejectsAnExternalCodeUnitRevision() throws {
            for withDuplicate in [false, true] {
                let fixture = try DictionaryIsolationFixture()
                try fixture.expectBystandersRemainUnsaved()
                let original = "e\u{301} Hills, Inc"
                let sourceRow = Transcription(text: "processed", duration: 1, recognitionText: original)
                fixture.library.context.insert(sourceRow)
                try fixture.library.context.save()
                try fixture.expectBystandersRemainUnsaved()
                let source = try HistoryCorrectionApprovalService.capture(
                    transcriptionID: sourceRow.id, variant: .recognition, expectedText: original, using: fixture.caller
                )
                let range = try #require(HistoryCorrectionApprovalService.occurrences(of: "Hills, Inc", in: source).first)
                let preview = try HistoryCorrectionApprovalService.preview(
                    source: source, range: range, replacementText: "RJT", using: fixture.caller
                )
                let writer = fixture.freshContext()
                let changed = try #require(writer.fetch(FetchDescriptor<Transcription>()).first { $0.id == sourceRow.id })
                let newer = "é Hills, Inc"
                changed.recognitionText = newer
                if withDuplicate {
                    writer.insert(WordReplacement(record: try .init(
                        id: UUID(), originalText: "Hills, Inc", replacementText: "RJT", dateAdded: Date(),
                        isEnabled: false, matchingKind: .literal
                    )))
                }
                try writer.save()
                try fixture.expectBystandersRemainUnsaved()
                let currentPlan = VoiceInkWordReplacementLibrary(records: [preview.record]).preflightImport(
                    existingRecords: try DictionaryService.snapshotWordReplacementRecords(using: fixture.caller)
                )
                #expect(currentPlan.canApply)
                #expect(currentPlan.duplicates.count == (withDuplicate ? 1 : 0))

                do {
                    _ = try HistoryCorrectionApprovalService.approve(preview, using: fixture.caller)
                    Issue.record("Approval ignored a committed external source revision; duplicate: \(withDuplicate).")
                } catch let error as HistoryCorrectionApprovalService.ApprovalError {
                    #expect(error == .sourceChanged)
                }
                let observer = fixture.freshContext()
                let current = try #require(observer.fetch(FetchDescriptor<Transcription>()).first { $0.id == sourceRow.id })
                #expect(current.recognitionText?.utf16.elementsEqual(newer.utf16) == true)
                let persistedRules = try observer.fetch(FetchDescriptor<WordReplacement>())
                #expect(persistedRules.count == (withDuplicate ? 2 : 1))
                #expect(!persistedRules.contains { $0.id == preview.record.id })
                #expect(try fixture.caller.fetch(FetchDescriptor<WordReplacement>()).count == (withDuplicate ? 2 : 1))
                try fixture.expectBystandersRemainUnsaved()
            }
        }
    }
}

@MainActor
private final class DictionaryIsolationFixture {
    let library: CorrectionLibraryFixture
    let caller: ModelContext
    private let bystander: WordReplacement
    private let vocabulary: VocabularyWord
    private let savedRecord: VoiceInkWordReplacementRecord
    private let savedWord = "Saved vocabulary"
    private let dirtyReplacement = "Unrelated unsaved e\u{301} 🧪"
    private let dirtyWord = "Unrelated unsaved vocabulary"

    init() throws {
        let library = try CorrectionLibraryFixture()
        let caller = library.container.mainContext
        caller.autosaveEnabled = false
        let bystander = WordReplacement(originalText: "bystander phrase", replacementText: "Saved replacement")
        let vocabulary = VocabularyWord(word: "Saved vocabulary", dateAdded: Date(timeIntervalSince1970: 1_600_000_000.125))
        caller.insert(bystander)
        caller.insert(vocabulary)
        try caller.save()
        self.library = library
        self.caller = caller
        self.bystander = bystander
        self.vocabulary = vocabulary
        savedRecord = try bystander.record
        bystander.replacementText = dirtyReplacement
        vocabulary.word = dirtyWord
        try #require(caller.hasChanges)
    }

    func freshContext() -> ModelContext {
        let context = ModelContext(library.container)
        context.autosaveEnabled = false
        return context
    }

    func callerRow(_ id: UUID) throws -> WordReplacement {
        let rows = try caller.fetch(FetchDescriptor<WordReplacement>()).filter { $0.id == id }
        try #require(rows.count == 1)
        return try #require(rows.first)
    }

    func persistedRecord(_ id: UUID) throws -> VoiceInkWordReplacementRecord {
        let observer = freshContext()
        return try withExtendedLifetime(observer) {
            let rows = try observer.fetch(FetchDescriptor<WordReplacement>()).filter { $0.id == id }
            try #require(rows.count == 1)
            return try #require(rows.first).record
        }
    }

    func expectBystandersRemainUnsaved() throws {
        #expect(caller.hasChanges)
        #expect(bystander.replacementText.utf16.elementsEqual(dirtyReplacement.utf16))
        #expect(vocabulary.word.utf16.elementsEqual(dirtyWord.utf16))
        let observer = freshContext()
        let rules = try observer.fetch(FetchDescriptor<WordReplacement>()).filter { $0.id == savedRecord.id }
        #expect(rules.count == 1)
        let storedBystander = try #require(rules.first)
        #expect(try storedBystander.record == savedRecord)
        let words = try observer.fetch(FetchDescriptor<VocabularyWord>())
        #expect(words.contains { $0.word == savedWord && $0.dateAdded == vocabulary.dateAdded })
        #expect(!words.contains { $0.word == dirtyWord })
    }
}
