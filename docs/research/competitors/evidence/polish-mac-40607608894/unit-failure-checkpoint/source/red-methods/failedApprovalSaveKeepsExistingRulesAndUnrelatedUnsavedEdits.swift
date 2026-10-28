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
