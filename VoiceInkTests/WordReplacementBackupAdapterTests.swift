import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct WordReplacementBackupAdapterTests {
        @Test @MainActor func fullBackupRoundTripsExactIdentityKindEnabledStateAndProvenance() throws {
            let source = try DictionaryBackupFixture()
            let destination = try DictionaryBackupFixture()
            let records = [
                try Self.record("Hills, Inc", " $5.00\\Temp\r\n e\u{301} 🧪 \t", enabled: false,
                                provenance: .init(sourceTranscriptionID: UUID(), sourceVariant: .recognition)),
                try Self.record("first, second", "third", kind: .legacyCommaAlternatives)
            ]
            for record in records { source.context.insert(WordReplacement(record: record)) }
            source.context.insert(VocabularyWord(word: " e\u{301} 🧪 "))
            try source.context.save()

            let exported = try DictionaryBackup.export(using: source.context)
            #expect(exported.legacyWordReplacements == ["first, second": "third"])
            #expect(exported.wordReplacementLibrary.records.count == 2)
            let encoded = try VoiceInkSettingsBackupFileCodec.encode(Self.backup(
                vocabulary: exported.vocabularyWords,
                legacy: exported.legacyWordReplacements,
                library: exported.wordReplacementLibrary
            ))
            let decoded: VoiceInkSettingsBackupFile<ShortcutBackup> = try VoiceInkSettingsBackupFileCodec.decode(from: encoded)
            try DictionaryBackup.prepareImport(decoded, using: destination.context).apply(using: destination.context)
            let reopened = ModelContext(destination.container)
            let restored = try DictionaryService.snapshotWordReplacementRecords(using: reopened)
            #expect(Self.sorted(restored) == Self.sorted(records))
            let literal = try #require(restored.first { $0.matchingKind == .literal })
            #expect(literal.originalText.utf16.elementsEqual(records[0].originalText.utf16))
            #expect(literal.replacementText.utf8.elementsEqual(records[0].replacementText.utf8))
            #expect(literal.replacementText.utf16.elementsEqual(records[0].replacementText.utf16))
            #expect(!literal.isEnabled)
            #expect(try reopened.fetch(FetchDescriptor<VocabularyWord>()).count == 1)
        }

        @Test @MainActor func presentEmptyFullLibraryWinsOverLegacyMapAndStillImportsVocabulary() throws {
            let fixture = try DictionaryBackupFixture()
            let original = WordReplacement(originalText: "keep", replacementText: "saved", isEnabled: false)
            fixture.context.insert(original)
            try fixture.context.save()
            let backup = Self.backup(
                vocabulary: [.init(word: "new term")], legacy: ["unsafe, literal": "wrong"],
                library: .init(records: [])
            )
            try DictionaryBackup.prepareImport(backup, using: fixture.context).apply(using: fixture.context)
            let rows = try fixture.context.fetch(FetchDescriptor<WordReplacement>())
            #expect(rows.count == 1)
            #expect(rows.first?.id == original.id)
            #expect(rows.first?.isEnabled == false)
            #expect(try fixture.context.fetch(FetchDescriptor<VocabularyWord>()).map(\.word) == ["new term"])
        }

        @Test @MainActor func fullLibraryConflictsBlockAllReplacementAndVocabularyInsertions() throws {
            let fixture = try DictionaryBackupFixture()
            let existing = try Self.record("Roma", "RJT", enabled: false)
            fixture.context.insert(WordReplacement(record: existing))
            try fixture.context.save()
            let conflicting = try Self.record("roma", "Different")
            let unrelated = try Self.record("new phrase", "New result")
            let backup = Self.backup(
                vocabulary: [.init(word: "must not appear")], library: .init(records: [unrelated, conflicting])
            )
            do {
                _ = try DictionaryBackup.prepareImport(backup, using: fixture.context)
                Issue.record("Conflicting full-record import was accepted.")
            } catch let error as DictionaryService.LibraryConflictError {
                #expect(error.conflicts.count == 1)
                #expect(error.conflicts.first?.incoming == conflicting)
                #expect(error.conflicts.first?.existing == existing)
            }
            #expect(try DictionaryService.snapshotWordReplacementRecords(using: fixture.context) == [existing])
            #expect(try fixture.context.fetch(FetchDescriptor<VocabularyWord>()).isEmpty)
            #expect(!fixture.context.hasChanges)
        }

        @Test @MainActor func preparedImportRechecksNewConflictsBeforeWritingAnything() throws {
            let fixture = try DictionaryBackupFixture()
            let incoming = try Self.record("Roma", "RJT")
            let prepared = try DictionaryBackup.prepareImport(
                Self.backup(vocabulary: [.init(word: "must not appear")], library: .init(records: [incoming])),
                using: fixture.context
            )
            let later = try Self.record("ROMA", "Newer entry")
            fixture.context.insert(WordReplacement(record: later))
            try fixture.context.save()
            do {
                try prepared.apply(using: fixture.context)
                Issue.record("A stale import applied over a new conflict.")
            } catch let error as DictionaryService.LibraryConflictError {
                #expect(error.conflicts.first?.existing == later)
                #expect(error.conflicts.first?.incoming == incoming)
            }
            #expect(try DictionaryService.snapshotWordReplacementRecords(using: fixture.context) == [later])
            #expect(try fixture.context.fetch(FetchDescriptor<VocabularyWord>()).isEmpty)
        }

        @Test @MainActor func repeatedFullImportIsIdempotentAndSuccessfulImportAffectsTheNextOperation() throws {
            let fixture = try DictionaryBackupFixture()
            #expect(DictionaryService.applyWordReplacements(to: "Roma, Inc", using: fixture.context) == "Roma, Inc")
            let record = try Self.record("Roma, Inc", "$5.00\\Temp")
            let prepared = try DictionaryBackup.prepareImport(Self.backup(library: .init(records: [record])), using: fixture.context)
            try prepared.apply(using: fixture.context)
            #expect(DictionaryService.applyWordReplacements(to: "Roma, Inc", using: fixture.context) == "$5.00\\Temp")
            try prepared.apply(using: fixture.context)
            #expect(try DictionaryService.snapshotWordReplacementRecords(using: fixture.context) == [record])
        }

        @Test @MainActor func legacyMapOnlyImportPreservesAdditiveTrimAndCommaContract() throws {
            let fixture = try DictionaryBackupFixture()
            let existing = WordReplacement(originalText: "Keep", replacementText: "existing", isEnabled: false)
            fixture.context.insert(existing)
            try fixture.context.save()
            let existingID = existing.id
            let existingDate = existing.dateAdded
            let backup = Self.backup(legacy: [
                "keep": "must not replace", "  first, second  ": "  result  ", "   ": "invalid"
            ])
            try DictionaryBackup.prepareImport(backup, using: fixture.context).apply(using: fixture.context)
            let rows = try fixture.context.fetch(FetchDescriptor<WordReplacement>())
            #expect(rows.count == 2)
            #expect(existing.id == existingID && existing.dateAdded == existingDate)
            #expect(existing.replacementText == "existing" && !existing.isEnabled)
            let added = try #require(rows.first { $0.id != existingID })
            #expect(added.originalText == "first, second")
            #expect(added.replacementText == "result" && added.isEnabled)
            #expect(try added.record.matchingKind == .legacyCommaAlternatives)
            #expect(DictionaryService.applyWordReplacements(to: "first second Keep", using: fixture.context) == "result result Keep")
        }

        @Test @MainActor func legacyMapImportUsesCanonicalNamesOfLiteralRowsWithoutOverwritingThem() throws {
            let fixture = try DictionaryBackupFixture()
            let literal = try Self.record("Acme, Inc.", "RJT-482", enabled: false)
            let existing = WordReplacement(record: literal)
            fixture.context.insert(existing)
            try fixture.context.save()
            #expect(existing.originalText.isEmpty && existing.replacementText.isEmpty)
            let backup = Self.backup(legacy: [
                "acme, inc.": "must not replace", "first, second": "result"
            ])
            try DictionaryBackup.prepareImport(backup, using: fixture.context).apply(using: fixture.context)
            let rows = try DictionaryService.snapshotWordReplacementRecords(using: fixture.context)
            #expect(rows.count == 2)
            #expect(rows.contains(literal))
            #expect(!rows.contains { $0.replacementText == "must not replace" })
            let added = try #require(rows.first { $0.id != literal.id })
            #expect(added.originalText == "first, second" && added.replacementText == "result")
            #expect(added.matchingKind == .legacyCommaAlternatives)
            #expect(DictionaryService.applyWordReplacements(to: "first second Acme, Inc.", using: fixture.context) == "result result Acme, Inc.")
        }

        @Test @MainActor func unsupportedStoredKindCannotSilentlyDisappearIntoLegacyExport() throws {
            let fixture = try DictionaryBackupFixture()
            let unsupported = WordReplacement(originalText: "Roma, Inc", replacementText: "must not reinterpret")
            unsupported.matchingKindRawValue = "future-kind"
            fixture.context.insert(unsupported)
            try fixture.context.save()
            do {
                _ = try DictionaryBackup.export(using: fixture.context)
                Issue.record("Unsupported stored matching kind was exported.")
            } catch let error as WordReplacement.StoredValueError {
                #expect(error == .unsupportedMatchingKind("future-kind"))
                #expect(unsupported.matchingKindRawValue == "future-kind")
                #expect(try fixture.context.fetch(FetchDescriptor<WordReplacement>()).count == 1)
            }
        }

        @Test @MainActor func malformedFullPayloadRejectsBeforeAnyDictionaryMutation() throws {
            let fixture = try DictionaryBackupFixture()
            let encoded = try VoiceInkSettingsBackupFileCodec.encode(Self.backup(
                vocabulary: [.init(word: "must not appear")], legacy: ["must not": "appear"]
            ))
            var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            object["wordReplacementLibrary"] = NSNull()
            let malformed = try JSONSerialization.data(withJSONObject: object)
            do {
                let decoded: VoiceInkSettingsBackupFile<ShortcutBackup> = try VoiceInkSettingsBackupFileCodec.decode(from: malformed)
                try DictionaryBackup.prepareImport(decoded, using: fixture.context).apply(using: fixture.context)
                Issue.record("Explicit null full library was accepted.")
            } catch is DecodingError {}
            #expect(try fixture.context.fetch(FetchDescriptor<WordReplacement>()).isEmpty)
            #expect(try fixture.context.fetch(FetchDescriptor<VocabularyWord>()).isEmpty)
            #expect(!fixture.context.hasChanges)
        }

        @Test @MainActor func failedSaveRemovesOnlyImportInsertionsAndPreservesUnrelatedDirtyEdits() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Dictionary-Backup-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storeURL = directory.appendingPathComponent("read-only.store")
            try Self.seedReadOnlyStore(at: storeURL)
            let schema = Schema([WordReplacement.self, VocabularyWord.self])
            let configuration = ModelConfiguration("DictionaryBackupReadOnly", schema: schema, url: storeURL, allowsSave: false, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            #expect(!configuration.allowsSave && !configuration.isStoredInMemoryOnly)
            let existing = try #require(context.fetch(FetchDescriptor<WordReplacement>()).first)
            existing.replacementText = "unrelated unsaved edit"
            let incoming = try Self.record("new phrase", "new replacement")
            let prepared = try DictionaryBackup.prepareImport(
                Self.backup(vocabulary: [.init(word: "new vocabulary")], library: .init(records: [incoming])),
                using: context
            )
            do {
                try prepared.apply(using: context)
                Issue.record("Read-only dictionary save unexpectedly succeeded.")
            } catch is VoiceInkSettingsBackupImportError {}
            #expect(existing.replacementText == "unrelated unsaved edit")
            #expect(context.hasChanges)
            #expect(try context.fetch(FetchDescriptor<WordReplacement>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<VocabularyWord>()).isEmpty)
        }

        @MainActor private static func seedReadOnlyStore(at url: URL) throws {
            let schema = Schema([WordReplacement.self, VocabularyWord.self])
            let configuration = ModelConfiguration("DictionaryBackupReadOnly", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(WordReplacement(originalText: "existing", replacementText: "saved"))
            try context.save()
        }

        private static func record(
            _ original: String, _ replacement: String,
            kind: VoiceInkWordReplacementMatchingKind = .literal, enabled: Bool = true,
            provenance: VoiceInkWordReplacementProvenance? = nil
        ) throws -> VoiceInkWordReplacementRecord {
            try VoiceInkWordReplacementRecord(
                id: UUID(), originalText: original, replacementText: replacement,
                dateAdded: Date(timeIntervalSince1970: 1_700_000_000.125), isEnabled: enabled,
                matchingKind: kind, provenance: provenance
            )
        }

        private static func backup(
            vocabulary: [VoiceInkVocabularyWordBackup]? = nil,
            legacy: [String: String]? = nil,
            library: VoiceInkWordReplacementLibrary? = nil
        ) -> VoiceInkSettingsBackupFile<ShortcutBackup> {
            .init(
                version: "1.95.2", customPrompts: [], powerModeConfigs: [], powerModeShortcuts: nil,
                vocabularyWords: vocabulary, wordReplacements: legacy, generalSettings: nil,
                customEmojis: nil, customCloudModels: nil, wordReplacementLibrary: library
            )
        }

        private static func sorted(_ records: [VoiceInkWordReplacementRecord]) -> [VoiceInkWordReplacementRecord] {
            records.sorted { $0.id.uuidString < $1.id.uuidString }
        }
    }
}

@MainActor
private final class DictionaryBackupFixture {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let schema = Schema([WordReplacement.self, VocabularyWord.self])
        let configuration = ModelConfiguration("DictionaryBackup-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }
}
