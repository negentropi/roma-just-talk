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
