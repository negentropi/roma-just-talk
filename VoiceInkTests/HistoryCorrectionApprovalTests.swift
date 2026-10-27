import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct HistoryCorrectionApprovalTests {
        @Test @MainActor func captureBindsTheDisplayedVariantAndExactRevision() throws {
            let fixture = try CorrectionLibraryFixture()
            let row = Transcription(text: "processed", duration: 1, enhancedText: "enhanced", recognitionText: " e\u{301} 🧪 ")
            fixture.context.insert(row)
            try fixture.context.save()
            for (variant, value) in [
                (VoiceInkWordReplacementSourceVariant.recognition, " e\u{301} 🧪 "),
                (.processed, "processed"), (.enhanced, "enhanced")
            ] {
                let source = try HistoryCorrectionApprovalService.capture(
                    transcriptionID: row.id, variant: variant, expectedText: value, using: fixture.context
                )
                #expect(source.transcriptionID == row.id)
                #expect(source.variant == variant)
                #expect(source.text.utf8.elementsEqual(value.utf8))
                #expect(source.text.utf16.elementsEqual(value.utf16))
            }
            do {
                _ = try HistoryCorrectionApprovalService.capture(
                    transcriptionID: row.id, variant: .recognition, expectedText: " é 🧪 ", using: fixture.context
                )
                Issue.record("Canonical equality silently advanced the displayed revision.")
            } catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .sourceChanged) }
            row.recognitionText = nil
            do {
                _ = try HistoryCorrectionApprovalService.capture(
                    transcriptionID: row.id, variant: .recognition, expectedText: "processed", using: fixture.context
                )
                Issue.record("Missing recognition was replaced by processed text.")
            } catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .variantUnavailable) }
        }

        @Test @MainActor func occurrencesRetainExactSpellingAndAllOverlappingChoices() throws {
            let fixture = try CorrectionLibraryFixture()
            let row = Transcription(text: "aaaa é e\u{301} e\u{301} 🧪🧪", duration: 1)
            fixture.context.insert(row)
            try fixture.context.save()
            let source = try HistoryCorrectionApprovalService.capture(
                transcriptionID: row.id, variant: .processed, expectedText: row.text, using: fixture.context
            )
            #expect(try HistoryCorrectionApprovalService.occurrences(of: "aa", in: source) == [
                NSRange(location: 0, length: 2), NSRange(location: 1, length: 2), NSRange(location: 2, length: 2)
            ])
            let decomposed = try HistoryCorrectionApprovalService.occurrences(of: "e\u{301}", in: source)
            #expect(decomposed == [NSRange(location: 7, length: 2), NSRange(location: 10, length: 2)])
            #expect(try HistoryCorrectionApprovalService.occurrences(of: "é", in: source) == [NSRange(location: 5, length: 1)])
            #expect(try HistoryCorrectionApprovalService.occurrences(of: "🧪", in: source) == [
                NSRange(location: 13, length: 2), NSRange(location: 15, length: 2)
            ])
            #expect(try HistoryCorrectionApprovalService.occurrences(of: "absent", in: source).isEmpty)
            do { _ = try HistoryCorrectionApprovalService.occurrences(of: " \n", in: source); Issue.record("Blank phrase accepted.") }
            catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .blankPhrase) }
        }

        @Test @MainActor func reviewDoesNotMutateAndApprovedLiteralSurvivesHistoryDeletion() throws {
            let fixture = try CorrectionLibraryFixture()
            let recognition = "Send it to Hills, Inc tomorrow."
            let row = Transcription(text: "a different processed transcript", duration: 1, recognitionText: recognition)
            fixture.context.insert(row)
            try fixture.context.save()
            let source = try HistoryCorrectionApprovalService.capture(
                transcriptionID: row.id, variant: .recognition, expectedText: recognition, using: fixture.context
            )
            let range = try #require(HistoryCorrectionApprovalService.occurrences(of: "Hills, Inc", in: source).first)
            let replacement = "\t$5.00\\Temp\r\n e\u{301} 🧪 "
            let preview = try HistoryCorrectionApprovalService.preview(
                source: source, range: range, replacementText: replacement, using: fixture.context
            )
            #expect(preview.importPlan.canApply)
            #expect(preview.importPlan.recordsToInsert == [preview.record])
            #expect(try fixture.context.fetch(FetchDescriptor<WordReplacement>()).isEmpty)
            #expect(!fixture.context.hasChanges)
            guard case .inserted(let entry) = try HistoryCorrectionApprovalService.approve(preview, using: fixture.context) else {
                Issue.record("Approval did not insert a new rule."); return
            }
            #expect(try entry.record == preview.record)
            let provenance = try #require(preview.record.provenance)
            #expect(provenance.sourceTranscriptionID == row.id)
            #expect(provenance.sourceVariant == .recognition)
            #expect(try HistoryCorrectionApprovalService.sourceExists(for: provenance, using: fixture.context))
            let expected = "Send it to \(replacement) tomorrow."
            #expect(DictionaryService.applyWordReplacements(to: recognition, using: fixture.context).utf16.elementsEqual(expected.utf16))
            fixture.context.delete(row)
            try fixture.context.save()
            #expect(try !HistoryCorrectionApprovalService.sourceExists(for: provenance, using: fixture.context))
            let fresh = ModelContext(fixture.container)
            #expect(try DictionaryService.snapshotWordReplacementRecords(using: fresh) == [preview.record])
            #expect(DictionaryService.applyWordReplacements(to: recognition, using: fixture.context).utf8.elementsEqual(expected.utf8))
        }

        @Test @MainActor func invalidRangesAndBlankPairsCannotCreateAnApproval() throws {
            let fixture = try CorrectionLibraryFixture()
            let row = Transcription(text: "A🧪 e\u{301} Z", duration: 1)
            fixture.context.insert(row)
            try fixture.context.save()
            let source = try HistoryCorrectionApprovalService.capture(
                transcriptionID: row.id, variant: .processed, expectedText: row.text, using: fixture.context
            )
            for range in [
                NSRange(location: -1, length: 1), NSRange(location: 0, length: 0),
                NSRange(location: 2, length: 1), NSRange(location: 1, length: 1),
                NSRange(location: Int.max, length: Int.max), NSRange(location: 0, length: Int.max)
            ] {
                do {
                    _ = try HistoryCorrectionApprovalService.preview(source: source, range: range, replacementText: "replacement", using: fixture.context)
                    Issue.record("Invalid UTF-16 range accepted: \(range).")
                } catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .invalidRange) }
            }
            do {
                _ = try HistoryCorrectionApprovalService.preview(source: source, range: NSRange(location: 3, length: 1), replacementText: "replacement", using: fixture.context)
                Issue.record("Blank source selection accepted.")
            } catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .blankPhrase) }
            do {
                _ = try HistoryCorrectionApprovalService.preview(source: source, range: NSRange(location: 0, length: 1), replacementText: " \n", using: fixture.context)
                Issue.record("Blank replacement accepted.")
            } catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .blankReplacement) }
            #expect(try fixture.context.fetch(FetchDescriptor<WordReplacement>()).isEmpty)
        }

        @Test @MainActor func approvalRevalidatesFullRevisionVariantAndSourceExistence() throws {
            let fixture = try CorrectionLibraryFixture()
            let row = Transcription(text: "processed", duration: 1, recognitionText: "e\u{301} Roma")
            fixture.context.insert(row)
            try fixture.context.save()
            let source = try HistoryCorrectionApprovalService.capture(
                transcriptionID: row.id, variant: .recognition, expectedText: "e\u{301} Roma", using: fixture.context
            )
            let range = try #require(HistoryCorrectionApprovalService.occurrences(of: "Roma", in: source).first)
            let preview = try HistoryCorrectionApprovalService.preview(source: source, range: range, replacementText: "RJT", using: fixture.context)
            row.recognitionText = "é Roma"
            do { _ = try HistoryCorrectionApprovalService.approve(preview, using: fixture.context); Issue.record("Changed revision approved.") }
            catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .sourceChanged) }
            row.recognitionText = nil
            do { _ = try HistoryCorrectionApprovalService.approve(preview, using: fixture.context); Issue.record("Missing variant approved.") }
            catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .variantUnavailable) }
            fixture.context.delete(row)
            try fixture.context.save()
            do { _ = try HistoryCorrectionApprovalService.approve(preview, using: fixture.context); Issue.record("Deleted source approved.") }
            catch let error as HistoryCorrectionApprovalService.ApprovalError { #expect(error == .sourceUnavailable) }
            #expect(try fixture.context.fetch(FetchDescriptor<WordReplacement>()).isEmpty)
        }

        @Test @MainActor func approvalRechecksNewConflictsAndDuplicatesWithoutOverwritingOrEnabling() throws {
            let fixture = try CorrectionLibraryFixture()
            let row = Transcription(text: "Roma", duration: 1)
            fixture.context.insert(row)
            try fixture.context.save()
            let source = try HistoryCorrectionApprovalService.capture(
                transcriptionID: row.id, variant: .processed, expectedText: row.text, using: fixture.context
            )
            let preview = try HistoryCorrectionApprovalService.preview(source: source, range: NSRange(location: 0, length: 4), replacementText: "RJT", using: fixture.context)
            let conflicting = try VoiceInkWordReplacementRecord(
                id: UUID(), originalText: "ROMA", replacementText: "Other", dateAdded: Date(), isEnabled: true, matchingKind: .literal
            )
            let entry = WordReplacement(record: conflicting)
            fixture.context.insert(entry)
            try fixture.context.save()
            do { _ = try HistoryCorrectionApprovalService.approve(preview, using: fixture.context); Issue.record("Late conflict overwritten.") }
            catch let error as DictionaryService.LibraryConflictError {
                #expect(error.conflicts.first?.incoming == preview.record)
                #expect(error.conflicts.first?.existing == conflicting)
            }
            #expect(try entry.record == conflicting)
            #expect(DictionaryService.removeWordReplacement(entry, context: fixture.context) == nil)
            let duplicate = try VoiceInkWordReplacementRecord(
                id: UUID(), originalText: "Roma", replacementText: "RJT", dateAdded: Date(), isEnabled: false, matchingKind: .literal
            )
            let disabled = WordReplacement(record: duplicate)
            fixture.context.insert(disabled)
            try fixture.context.save()
            guard case .alreadyExists(let id) = try HistoryCorrectionApprovalService.approve(preview, using: fixture.context) else {
                Issue.record("Existing literal was duplicated."); return
            }
            #expect(id == duplicate.id)
            #expect(!disabled.isEnabled)
            #expect(try DictionaryService.snapshotWordReplacementRecords(using: fixture.context) == [duplicate])
        }

        @Test @MainActor func failedApprovalSaveKeepsExistingRulesAndUnrelatedUnsavedEdits() throws {
            let fixture = try CorrectionLibraryFixture(readOnly: true)
            let row = try #require(fixture.context.fetch(FetchDescriptor<Transcription>()).first)
            let before = try DictionaryService.snapshotWordReplacementRecords(using: fixture.context)
            let unrelated = try #require(fixture.context.fetch(FetchDescriptor<VocabularyWord>()).first)
            unrelated.word = "keep this unsaved change"
            let source = try HistoryCorrectionApprovalService.capture(
                transcriptionID: row.id, variant: .recognition, expectedText: "source phrase", using: fixture.context
            )
            let preview = try HistoryCorrectionApprovalService.preview(
                source: source, range: NSRange(location: 0, length: 13), replacementText: "Replacement", using: fixture.context
            )
            #expect(preview.importPlan.recordsToInsert == [preview.record])
            do {
                _ = try HistoryCorrectionApprovalService.approve(preview, using: fixture.context)
                Issue.record("Read-only store accepted an approved rule.")
            } catch is DictionaryService.LibraryConflictError {
                Issue.record("The intended storage failure was replaced by a conflict.")
            } catch is DictionaryService.LibraryDuplicateError {
                Issue.record("The intended storage failure was replaced by a duplicate.")
            } catch is WordReplacement.StoredValueError {
                Issue.record("The intended storage failure was replaced by invalid fixture data.")
            } catch is HistoryCorrectionApprovalService.ApprovalError {
                Issue.record("The intended storage failure was replaced by an approval setup error.")
            } catch {
                let after = try DictionaryService.snapshotWordReplacementRecords(using: fixture.context)
                #expect(after.count == before.count)
                #expect(before.allSatisfy { after.contains($0) })
                #expect(!after.contains { $0.id == preview.record.id })
                #expect(unrelated.word == "keep this unsaved change")
            }
        }
    }
}
