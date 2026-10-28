import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct WordReplacementLibraryAdapterTests {
        @Test @MainActor func storedKindsAndProvenanceRoundTripWithoutReinterpretingUnknownData() throws {
            let fixture = try CorrectionLibraryFixture()
            let legacy = WordReplacement(originalText: "first, second", replacementText: "result")
            fixture.context.insert(legacy)
            try fixture.context.save()
            #expect(legacy.matchingKindRawValue == nil)
            #expect(try legacy.voiceInkRule.matchingKind == .legacyCommaAlternatives)
            let record = try Self.record("Hills, Inc", " $5.00\\Temp\r\n e\u{301} 🧪 ", enabled: false)
            fixture.context.insert(WordReplacement(record: record))
            try fixture.context.save()
            let fresh = ModelContext(fixture.container)
            let rows = try DictionaryService.snapshotWordReplacementRecords(using: fresh)
            #expect(rows.contains(record))
            let restored = try #require(rows.first { $0.id == record.id })
            #expect(restored.originalText.utf16.elementsEqual(record.originalText.utf16))
            #expect(restored.replacementText.utf8.elementsEqual(record.replacementText.utf8))
            let literalRow = try #require(fresh.fetch(FetchDescriptor<WordReplacement>()).first { $0.id == record.id })
            #expect(literalRow.originalText.isEmpty && literalRow.replacementText.isEmpty)
            #expect(literalRow.literalOriginalText?.utf16.elementsEqual(record.originalText.utf16) == true)
            #expect(literalRow.literalReplacementText?.utf8.elementsEqual(record.replacementText.utf8) == true)
            literalRow.originalText = "an older client edited the raw pair"
            do { _ = try literalRow.record; Issue.record("Mixed matching representations were accepted.") }
            catch let error as WordReplacement.StoredValueError { #expect(error == .invalidMatchingRepresentation) }
            literalRow.originalText = ""
            literalRow.literalReplacementText = nil
            do { _ = try literalRow.record; Issue.record("Incomplete literal payload was accepted.") }
            catch let error as WordReplacement.StoredValueError { #expect(error == .invalidMatchingRepresentation) }

            legacy.matchingKindRawValue = "future-rule"
            do { _ = try legacy.record; Issue.record("Unknown stored kind was reinterpreted.") }
            catch let error as WordReplacement.StoredValueError {
                #expect(error == .unsupportedMatchingKind("future-rule"))
            }
            #expect(legacy.matchingKind == nil)
            legacy.matchingKindRawValue = nil
            legacy.literalOriginalText = "unexpected payload"
            do { _ = try legacy.record; Issue.record("Legacy row accepted a literal payload.") }
            catch let error as WordReplacement.StoredValueError { #expect(error == .invalidMatchingRepresentation) }
            legacy.literalOriginalText = nil
            legacy.sourceTranscriptionID = UUID()
            do { _ = try legacy.voiceInkRule; Issue.record("Incomplete provenance was accepted.") }
            catch let error as WordReplacement.StoredValueError { #expect(error == .invalidProvenance) }
        }

        @Test @MainActor func successfulMutationsAreVisibleToTheNextOperation() throws {
            let fixture = try CorrectionLibraryFixture()
            #expect(DictionaryService.applyWordReplacements(to: "first second", using: fixture.context) == "first second")
            let entry = try DictionaryService.addWordReplacement(
                originalText: " first, second ", replacementText: " result ", context: fixture.context
            )
            #expect(DictionaryService.applyWordReplacements(to: "first second", using: fixture.context) == "result result")
            try DictionaryService.updateWordReplacement(
                entry, expectedRecord: entry.record, originalText: "first, second", replacementText: "updated", context: fixture.context
            )
            #expect(DictionaryService.applyWordReplacements(to: "first second", using: fixture.context) == "updated updated")
            try DictionaryService.setWordReplacementEnabled(entry, isEnabled: false, context: fixture.context)
            #expect(DictionaryService.applyWordReplacements(to: "first second", using: fixture.context) == "first second")
            try DictionaryService.setWordReplacementEnabled(entry, isEnabled: true, context: fixture.context)
            #expect(DictionaryService.applyWordReplacements(to: "first", using: fixture.context) == "updated")
            #expect(DictionaryService.removeWordReplacement(entry, context: fixture.context) == nil)
            #expect(DictionaryService.applyWordReplacements(to: "first second", using: fixture.context) == "first second")
        }

        @Test @MainActor func literalEditKeepsExactStringsIdentityKindAndProvenance() throws {
            let fixture = try CorrectionLibraryFixture()
            let initial = try Self.record("Hills, Inc", "Original")
            let row = WordReplacement(record: initial)
            fixture.context.insert(row)
            try fixture.context.save()
            let source = " Hills, Inc "
            let replacement = "\t$5.00\\Temp\r\n e\u{301} 🧪 "
            try DictionaryService.updateWordReplacement(row, expectedRecord: initial, originalText: source, replacementText: replacement, context: fixture.context)
            let result = try row.record
            #expect(result.id == initial.id)
            #expect(result.dateAdded == initial.dateAdded)
            #expect(result.matchingKind == .literal)
            #expect(result.provenance == initial.provenance)
            #expect(row.originalText.isEmpty && row.replacementText.isEmpty)
            #expect(result.originalText.utf8.elementsEqual(source.utf8))
            #expect(result.replacementText.utf16.elementsEqual(replacement.utf16))
            #expect(DictionaryService.applyWordReplacements(to: "Hills, Inc", using: fixture.context) == "Hills, Inc")
            #expect(DictionaryService.applyWordReplacements(to: source, using: fixture.context).utf16.elementsEqual(replacement.utf16))
        }

        @Test @MainActor func unknownEnabledRulesFailClosedAndLaterCallsReadCurrentData() throws {
            let fixture = try CorrectionLibraryFixture()
            let valid = WordReplacement(originalText: "Roma", replacementText: "RJT")
            let unknown = WordReplacement(originalText: "Hills, Inc", replacementText: "unsafe")
            unknown.matchingKindRawValue = "future-rule"
            fixture.context.insert(valid)
            fixture.context.insert(unknown)
            try fixture.context.save()
            do {
                _ = try DictionaryService.snapshotEnabledReplacementRules(using: fixture.context)
                Issue.record("Enabled unknown rule did not fail strict capture.")
            } catch let error as WordReplacement.StoredValueError { #expect(error == .unsupportedMatchingKind("future-rule")) }
            #expect(DictionaryService.applyWordReplacements(to: "Roma Hills, Inc", using: fixture.context) == "Roma Hills, Inc")
            // A failed read must not hide later valid data from the next operation.
            unknown.isEnabled = false
            try fixture.context.save()
            let expected = try valid.voiceInkRule
            #expect(try DictionaryService.snapshotEnabledReplacementRules(using: fixture.context) == [expected])
            #expect(DictionaryService.applyWordReplacements(to: "Roma Hills, Inc", using: fixture.context) == "RJT Hills, Inc")
            do {
                _ = try DictionaryService.snapshotWordReplacementRecords(using: fixture.context)
                Issue.record("Unsupported disabled record was silently omitted from full records.")
            } catch let error as WordReplacement.StoredValueError { #expect(error == .unsupportedMatchingKind("future-rule")) }
            do {
                try DictionaryService.setWordReplacementEnabled(unknown, isEnabled: true, context: fixture.context)
                Issue.record("Unsupported record was enabled.")
            } catch let error as WordReplacement.StoredValueError { #expect(error == .unsupportedMatchingKind("future-rule")) }
            #expect(!unknown.isEnabled)
            unknown.matchingKindRawValue = VoiceInkWordReplacementMatchingKind.literal.rawValue
            unknown.literalOriginalText = unknown.originalText
            unknown.literalReplacementText = unknown.replacementText
            unknown.originalText = ""
            unknown.replacementText = ""
            try fixture.context.save()
            try DictionaryService.setWordReplacementEnabled(unknown, isEnabled: true, context: fixture.context)
            #expect(DictionaryService.applyWordReplacements(to: "Roma Hills, Inc", using: fixture.context) == "RJT unsafe")
        }

        @Test @MainActor func editConflictsExposeCompleteRecordsAndChangeNothing() throws {
            let fixture = try CorrectionLibraryFixture()
            let first = try Self.record("Roma", "First")
            let second = try Self.record("Another", "Second")
            let row = WordReplacement(record: second)
            fixture.context.insert(WordReplacement(record: first))
            fixture.context.insert(row)
            try fixture.context.save()
            do {
                try DictionaryService.updateWordReplacement(row, expectedRecord: second, originalText: "ROMA", replacementText: "Changed", context: fixture.context)
                Issue.record("A conflicting edit was applied.")
            } catch let error as DictionaryService.LibraryConflictError {
                #expect(error.conflicts.count == 1)
                #expect(error.conflicts.first?.existing == first)
                #expect(error.conflicts.first?.incoming.id == second.id)
                #expect(error.conflicts.first?.incoming.originalText == "ROMA")
                #expect(error.conflicts.first?.incoming.replacementText == "Changed")
            }
            #expect(try row.record == second)
            #expect(!fixture.context.hasChanges)
            row.literalReplacementText = "Newer edit"
            try fixture.context.save()
            let latest = try row.record
            do {
                try DictionaryService.updateWordReplacement(row, expectedRecord: second, originalText: "Another", replacementText: "Old sheet", context: fixture.context)
                Issue.record("A stale editor overwrote a newer revision.")
            } catch let error as DictionaryService.LibraryRevisionError {
                #expect(error.expected == second)
                #expect(error.current == latest)
            }
            #expect(try row.record == latest)
            #expect(!fixture.context.hasChanges)
        }

        @Test @MainActor func failedEditToggleAndDeleteRestoreOnlyTheirOwnEntry() throws {
            let fixture = try CorrectionLibraryFixture(readOnly: true)
            let rows = try fixture.context.fetch(FetchDescriptor<WordReplacement>())
            #expect(rows.count == 2)
            let unrelated = try #require(fixture.context.fetch(FetchDescriptor<VocabularyWord>()).first)
            unrelated.word = "keep this unsaved change"
            for row in rows {
                let initial = try row.record
                do {
                    try DictionaryService.updateWordReplacement(row, expectedRecord: initial, originalText: "changed", replacementText: "Changed", context: fixture.context)
                    Issue.record("Read-only store accepted an edit.")
                } catch { #expect(try row.record == initial) }
                #expect(unrelated.word == "keep this unsaved change")
                do {
                    try DictionaryService.setWordReplacementEnabled(row, isEnabled: false, context: fixture.context)
                    Issue.record("Read-only store accepted an enable-state change.")
                } catch { #expect(row.isEnabled == initial.isEnabled) }
                #expect(unrelated.word == "keep this unsaved change")
                #expect(DictionaryService.removeWordReplacement(row, context: fixture.context) != nil)
                #expect(try fixture.context.fetch(FetchDescriptor<WordReplacement>()).contains { $0.id == initial.id })
                #expect(try row.record == initial)
                #expect(unrelated.word == "keep this unsaved change")
                if initial.matchingKind == .literal {
                    #expect(row.originalText.isEmpty && row.replacementText.isEmpty)
                }
            }
        }

        private static func record(_ source: String, _ replacement: String, enabled: Bool = true) throws -> VoiceInkWordReplacementRecord {
            try .init(
                id: UUID(), originalText: source, replacementText: replacement,
                dateAdded: Date(timeIntervalSince1970: 1_700_000_000.125), isEnabled: enabled, matchingKind: .literal,
                provenance: .init(sourceTranscriptionID: UUID(), sourceVariant: .recognition)
            )
        }
    }
}

@MainActor
final class CorrectionLibraryFixture {
    let directory: URL?
    let container: ModelContainer
    let context: ModelContext

    init(readOnly: Bool = false) throws {
        let schema = Schema([Transcription.self, WordReplacement.self, VocabularyWord.self, SessionMetric.self])
        if readOnly {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Correction-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            self.directory = directory
            let url = directory.appendingPathComponent("library.store")
            try Self.seed(schema: schema, url: url)
            let configuration = ModelConfiguration("CorrectionReadOnly", schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
            try #require(!configuration.allowsSave && configuration.groupAppContainerIdentifier == nil)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } else {
            directory = nil
            let configuration = ModelConfiguration("Correction-\(UUID().uuidString)", schema: schema,
                isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [configuration])
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    deinit {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private static func seed(schema: Schema, url: URL) throws {
        let configuration = ModelConfiguration("CorrectionReadOnly", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(WordReplacement(originalText: "existing", replacementText: "saved"))
        context.insert(WordReplacement(record: try .init(
            id: UUID(), originalText: "Hills, Inc", replacementText: " $5.00\\Temp e\u{301} 🧪 ",
            dateAdded: Date(), isEnabled: true, matchingKind: .literal,
            provenance: .init(sourceTranscriptionID: UUID(), sourceVariant: .recognition)
        )))
        context.insert(VocabularyWord(word: "saved word"))
        context.insert(Transcription(text: "source phrase", duration: 1, recognitionText: "source phrase"))
        try context.save()
    }
}
