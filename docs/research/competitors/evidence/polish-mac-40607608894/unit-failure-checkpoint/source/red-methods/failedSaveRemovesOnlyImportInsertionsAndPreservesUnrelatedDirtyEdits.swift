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
