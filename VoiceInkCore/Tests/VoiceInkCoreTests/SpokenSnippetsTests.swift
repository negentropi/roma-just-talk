import Foundation
import VoiceInkCore

final class SpokenSnippetsTests: XCTestCase {
    func testEntireSnippetRecognizesOnlyCompleteEnabledTriggerAndRecognitionPunctuation() {
        let signature = VoiceInkSpokenSnippet(trigger: "my signature", content: "\nFelix\nRome \n")
        let disabled = VoiceInkSpokenSnippet(trigger: "my link", content: "https://example.com", enabled: false)
        let snippets = [signature, disabled]

        for text in ["my signature", " MY\tSIGNATURE . ", "my signature？！", "my signature。"] {
            XCTAssertEqual(VoiceInkSpokenSnippets.entireSnippet(for: text, using: snippets), signature)
        }
        for text in ["my link", "send my signature", "my signature please", "my signature2", ""] {
            XCTAssertNil(VoiceInkSpokenSnippets.entireSnippet(for: text, using: snippets))
        }
    }

    func testExpansionReportsMatchesEvenWhenSavedContentEqualsTrigger() {
        let unchanged = VoiceInkSpokenSnippet(trigger: "My Link", content: "My Link")
        let address = VoiceInkSpokenSnippet(trigger: "address", content: "First line\n\nSecond line ")

        let bare = VoiceInkSpokenSnippets.expansion(of: "My Link", using: [unchanged])
        XCTAssertTrue(bare.didExpand)
        XCTAssertEqual(bare.text, "My Link")
        let inline = VoiceInkSpokenSnippets.expansion(of: "Send My Link and address.", using: [unchanged, address])
        XCTAssertTrue(inline.didExpand)
        XCTAssertEqual(inline.text, "Send My Link and First line\n\nSecond line .")
        let ordinary = VoiceInkSpokenSnippets.expansion(of: "Unrelated text.", using: [unchanged, address])
        XCTAssertFalse(ordinary.didExpand)
        XCTAssertEqual(ordinary.text, "Unrelated text.")
    }

    func testBareTriggerPreservesExactMultilineContentWithoutRecognitionPunctuation() {
        let content = "\nFelix C. Order\nhttps://example.com/?a=1&b=2\n\n"
        let snippet = VoiceInkSpokenSnippet(trigger: "my signature", content: content)

        for input in ["my signature", " MY SIGNATURE. ", "my signature!", "my signature。", "my  signature", "my\t signature"] {
            XCTAssertEqual(VoiceInkSpokenSnippets.expand(input, using: [snippet]), content)
        }
    }

    func testInlineExpansionUsesLongestMatchWithoutExpandingSavedContentAgain() {
        let snippets = [
            VoiceInkSpokenSnippet(trigger: "address", content: "SHORT"),
            VoiceInkSpokenSnippet(trigger: "home address", content: "123 Long Road\nSecond floor"),
            VoiceInkSpokenSnippet(trigger: "signature", content: "home address"),
        ]

        XCTAssertEqual(
            VoiceInkSpokenSnippets.expand("Send home address, then ADDRESS and signature.", using: snippets),
            "Send 123 Long Road\nSecond floor, then SHORT and home address."
        )
        XCTAssertEqual(
            VoiceInkSpokenSnippets.expand("red green blue", using: [
                VoiceInkSpokenSnippet(trigger: "red green", content: "SHORT"),
                VoiceInkSpokenSnippet(trigger: "green blue", content: "LONG"),
            ]),
            "red LONG"
        )
    }

    func testLatinAndUnicodeWordBoundariesPreventSubstringExpansion() {
        let snippets = [
            VoiceInkSpokenSnippet(trigger: "cat", content: "ANIMAL"),
            VoiceInkSpokenSnippet(trigger: "café", content: "COFFEE"),
        ]

        XCTAssertEqual(
            VoiceInkSpokenSnippets.expand("cat scatter cat2 _cat café caféine décaféiné", using: snippets),
            "ANIMAL scatter cat2 _cat COFFEE caféine décaféiné"
        )
    }

    func testCJKAndThaiTriggersExpandInsideUnspacedWriting() {
        let snippets = [
            VoiceInkSpokenSnippet(trigger: "地址", content: "台北市"),
            VoiceInkSpokenSnippet(trigger: "ที่อยู่", content: "กรุงเทพฯ"),
        ]

        XCTAssertEqual(VoiceInkSpokenSnippets.expand("我的地址在這裡", using: snippets), "我的台北市在這裡")
        XCTAssertEqual(VoiceInkSpokenSnippets.expand("ส่งที่อยู่ให้ฉัน", using: snippets), "ส่งกรุงเทพฯให้ฉัน")
    }

    func testDisabledSnippetsDoNotExpandOrChangeUnmatchedText() {
        let disabled = VoiceInkSpokenSnippet(trigger: "my link", content: "https://example.com", enabled: false)
        let original = "Please send my link.\nKeep this line."

        XCTAssertEqual(VoiceInkSpokenSnippets.expand(original, using: [disabled]), original)
        XCTAssertEqual(VoiceInkSpokenSnippets.expand(original, using: []), original)
    }

    func testValidationRejectsBlankOversizedAndCanonicalDuplicateTriggers() {
        let existing = VoiceInkSpokenSnippet(trigger: "My Link", content: "existing")
        for snippet in [
            VoiceInkSpokenSnippet(trigger: " \t\n", content: "text"),
            VoiceInkSpokenSnippet(trigger: "valid", content: " \n\t"),
            VoiceInkSpokenSnippet(trigger: String(repeating: "a", count: 61), content: "text"),
            VoiceInkSpokenSnippet(trigger: "valid", content: String(repeating: "a", count: 4_001)),
            VoiceInkSpokenSnippet(trigger: "  MY\t LINK  ", content: "different"),
        ] {
            XCTAssertTrue(VoiceInkSpokenSnippets.validate(snippet, among: [existing]) != nil)
        }
        XCTAssertNil(VoiceInkSpokenSnippets.validate(existing, among: [existing]))
        XCTAssertNil(VoiceInkSpokenSnippets.validate(
            VoiceInkSpokenSnippet(trigger: String(repeating: "a", count: 60), content: String(repeating: "b", count: 4_000)),
            among: []
        ))
    }

    func testPersistenceKeepsIDsAndExactContentAcrossReload() throws {
        let suite = "VoiceInkCore.SpokenSnippets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snippet = VoiceInkSpokenSnippet(trigger: "  my\t link  ", content: " first\n\nlast \n", enabled: false)

        try VoiceInkSpokenSnippets.save([snippet], to: defaults)
        let restored = try XCTUnwrap(VoiceInkSpokenSnippets.load(from: defaults).first)

        XCTAssertEqual(restored.id, snippet.id)
        XCTAssertEqual(restored.trigger, "my link")
        XCTAssertEqual(restored.content, snippet.content)
        XCTAssertFalse(restored.enabled)
    }

    func testInvalidSaveLeavesExistingPreferencesUntouched() throws {
        let suite = "VoiceInkCore.SpokenSnippets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = VoiceInkSpokenSnippet(trigger: "address", content: "Original")
        try VoiceInkSpokenSnippets.save([existing], to: defaults)
        let stored = defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey)

        for invalid in [
            [existing, VoiceInkSpokenSnippet(trigger: "ADDRESS", content: "Duplicate")],
            [existing, VoiceInkSpokenSnippet(id: existing.id, trigger: "different", content: "Duplicate ID")],
            [VoiceInkSpokenSnippet(trigger: "", content: "Invalid")],
        ] {
            do {
                try VoiceInkSpokenSnippets.save(invalid, to: defaults)
                XCTFail("Invalid library must not replace saved snippets")
            } catch {}
            XCTAssertEqual(defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey), stored)
        }
    }

    func testMalformedSavedDataIsIgnoredWithoutErasingIt() {
        let suite = "VoiceInkCore.SpokenSnippets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let malformed = Data("not JSON".utf8)
        defaults.set(malformed, forKey: VoiceInkSpokenSnippets.userDefaultsKey)

        XCTAssertTrue(VoiceInkSpokenSnippets.load(from: defaults).isEmpty)
        XCTAssertEqual(defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey), malformed)
    }

    func testMutationLoadAcceptsMissingAndValidLibraries() throws {
        let suite = "VoiceInkCore.SpokenSnippets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(try VoiceInkSpokenSnippets.loadForMutation(from: defaults).isEmpty)
        XCTAssertNil(defaults.object(forKey: VoiceInkSpokenSnippets.userDefaultsKey))
        let snippet = VoiceInkSpokenSnippet(trigger: "  my\t link  ", content: " first\nCafe\u{301}\r\nlast \n", enabled: false)
        try VoiceInkSpokenSnippets.save([snippet], to: defaults)
        let stored = defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey)

        let loaded = try VoiceInkSpokenSnippets.loadForMutation(from: defaults)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, snippet.id)
        XCTAssertEqual(loaded.first?.trigger, "my link")
        XCTAssertTrue(loaded.first?.content.utf8.elementsEqual(snippet.content.utf8) == true)
        XCTAssertFalse(try XCTUnwrap(loaded.first).enabled)
        XCTAssertEqual(defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey), stored)
    }

    func testMutationLoadRejectsUnreadableLibrariesBeforeReplacingStoredBytes() throws {
        let suite = "VoiceInkCore.SpokenSnippets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = VoiceInkSpokenSnippet(trigger: "address", content: "Original")
        let unreadable = [
            Data("not JSON".utf8),
            Data("{}".utf8),
            try JSONEncoder().encode([VoiceInkSpokenSnippet(trigger: "", content: "Original")]),
            try JSONEncoder().encode([existing, VoiceInkSpokenSnippet(trigger: "ADDRESS", content: "Duplicate")]),
            try JSONEncoder().encode([existing, VoiceInkSpokenSnippet(id: existing.id, trigger: "other", content: "Duplicate ID")]),
        ]

        for stored in unreadable {
            defaults.set(stored, forKey: VoiceInkSpokenSnippets.userDefaultsKey)
            do {
                var library = try VoiceInkSpokenSnippets.loadForMutation(from: defaults)
                library.append(VoiceInkSpokenSnippet(trigger: "new", content: "Replacement"))
                try VoiceInkSpokenSnippets.save(library, to: defaults)
                XCTFail("An unreadable library must prevent a mutation from replacing saved bytes")
            } catch let issue as VoiceInkSpokenSnippets.LoadError {
                XCTAssertEqual(issue, .unreadableLibrary)
            } catch {
                XCTFail("Unreadable saved snippets must report a library error")
            }
            XCTAssertEqual(defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey), stored)
            XCTAssertTrue(VoiceInkSpokenSnippets.load(from: defaults).isEmpty)
        }
    }

    func testMutationLoadRejectsWrongStorageTypeWithoutErasingIt() {
        let suite = "VoiceInkCore.SpokenSnippets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let wrongType = "saved data with the wrong preference type"
        defaults.set(wrongType, forKey: VoiceInkSpokenSnippets.userDefaultsKey)

        do {
            _ = try VoiceInkSpokenSnippets.loadForMutation(from: defaults)
            XCTFail("A present unreadable value must not be treated as missing storage")
        } catch let issue as VoiceInkSpokenSnippets.LoadError {
            XCTAssertEqual(issue, .unreadableLibrary)
        } catch {
            XCTFail("A wrong storage type must report a library error")
        }
        XCTAssertEqual(defaults.string(forKey: VoiceInkSpokenSnippets.userDefaultsKey), wrongType)
        XCTAssertTrue(VoiceInkSpokenSnippets.load(from: defaults).isEmpty)
    }

    func testCSVExportImportRoundTripsCommasQuotesNewlinesAndEnabledState() throws {
        let snippets = [
            VoiceInkSpokenSnippet(trigger: "my address", content: "Floor 2, Room \"A\"\r\nTaipei\n", enabled: false),
            VoiceInkSpokenSnippet(trigger: "my link", content: "https://example.com?q=a,b", enabled: true),
            VoiceInkSpokenSnippet(trigger: "quote", content: "say \"hello\""),
            VoiceInkSpokenSnippet(trigger: "old line", content: "one\rtwo"),
        ]
        let csv = VoiceInkSpokenSnippets.csvString(for: snippets)
        let preview = VoiceInkSpokenSnippets.previewImport(csv, existing: [])

        XCTAssertTrue(preview.canImport)
        XCTAssertTrue(preview.rowIssues.isEmpty)
        XCTAssertEqual(preview.snippets.map(\.trigger), snippets.map(\.trigger))
        XCTAssertEqual(preview.snippets.map(\.content), snippets.map(\.content))
        XCTAssertEqual(preview.snippets.map(\.enabled), snippets.map(\.enabled))
        let merged = try VoiceInkSpokenSnippets.merged(preview, with: [], policy: .reject)
        XCTAssertEqual(merged.map(\.content), snippets.map(\.content))
    }

    func testCSVTwoColumnImportDefaultsEnabledAndSupportsBOMAndCRLF() {
        let csv = "\u{FEFF}trigger,content\r\nmy address,\"First line\r\nSecond line\"\r\n"
        let preview = VoiceInkSpokenSnippets.previewImport(csv, existing: [])

        XCTAssertTrue(preview.canImport)
        XCTAssertEqual(preview.snippets.count, 1)
        XCTAssertEqual(preview.snippets.first?.content, "First line\r\nSecond line")
        XCTAssertEqual(preview.snippets.first?.enabled, true)
    }

    func testMalformedCSVAndInvalidRowsCannotBeMergedPartially() {
        let existing = [VoiceInkSpokenSnippet(trigger: "old", content: "Preserve me")]
        let badFiles = [
            "trigger,content\nvalid,ok\nbroken,\"unclosed",
            "trigger,content,enabled\nvalid,ok,true\nbad,content,maybe\n",
            "trigger,content\nvalid,ok\nextra,columns,here\n",
            "trigger,content\nvalid,ok\n,missing trigger\n",
            "unexpected,header\nvalid,ok\n",
            "trigger,content\nvalid,ok\nbad,\"closed\"unexpected\n",
        ]
        for csv in badFiles {
            let preview = VoiceInkSpokenSnippets.previewImport(csv, existing: existing)
            XCTAssertFalse(preview.canImport)
            XCTAssertFalse(preview.rowIssues.isEmpty)
            do {
                _ = try VoiceInkSpokenSnippets.merged(preview, with: existing, policy: .keepExisting)
                XCTFail("Invalid import must not return a partial library")
            } catch {}
        }
    }

    func testCSVPreviewMakesExistingAndIncomingDuplicatesExplicit() {
        let existing = [VoiceInkSpokenSnippet(trigger: "My Link", content: "old")]
        let preview = VoiceInkSpokenSnippets.previewImport(
            "trigger,content\nmy link,new\naddress,first\nADDRESS,second\n",
            existing: existing
        )

        XCTAssertFalse(preview.duplicateTriggers.isEmpty)
        XCTAssertTrue(preview.duplicateTriggers.contains { $0.lowercased() == "my link" })
        XCTAssertTrue(preview.duplicateTriggers.contains { $0.lowercased() == "address" })
        XCTAssertTrue(preview.canImport)
        XCTAssertTrue(preview.rowIssues.isEmpty)
        do {
            let kept = try VoiceInkSpokenSnippets.merged(preview, with: existing, policy: .keepExisting)
            let replaced = try VoiceInkSpokenSnippets.merged(preview, with: existing, policy: .replaceExisting)
            XCTAssertEqual(kept.map(\.content), ["old", "first"])
            XCTAssertEqual(replaced.map(\.content), ["new", "second"])
        } catch {
            XCTFail("An explicit duplicate policy should import the whole valid file: \(error)")
        }
    }

    func testConflictPolicyKeepsReplacesOrRejectsWithoutChangingUnrelatedEntries() throws {
        let old = VoiceInkSpokenSnippet(trigger: "My Link", content: "old")
        let unrelated = VoiceInkSpokenSnippet(trigger: "address", content: "keep")
        let existing = [old, unrelated]
        let preview = VoiceInkSpokenSnippets.previewImport("trigger,content\nmy link,new\nphone,123\n", existing: existing)
        let kept = try VoiceInkSpokenSnippets.merged(preview, with: existing, policy: .keepExisting)
        let replaced = try VoiceInkSpokenSnippets.merged(preview, with: existing, policy: .replaceExisting)

        XCTAssertEqual(kept.map(\.content), ["old", "keep", "123"])
        XCTAssertEqual(kept[0].id, old.id)
        XCTAssertEqual(replaced.map(\.content), ["new", "keep", "123"])
        XCTAssertEqual(replaced[1].id, unrelated.id)
        do {
            _ = try VoiceInkSpokenSnippets.merged(preview, with: existing, policy: .reject)
            XCTFail("Conflicting import must require an explicit merge policy")
        } catch {}
        XCTAssertEqual(existing.map(\.content), ["old", "keep"])
    }

    func testImportRejectsMoreThanOneThousandEntries() {
        let rows = (0..<1_001).map { "trigger \($0),content" }.joined(separator: "\n")
        let preview = VoiceInkSpokenSnippets.previewImport("trigger,content\n" + rows, existing: [])

        XCTAssertFalse(preview.canImport)
        XCTAssertFalse(preview.rowIssues.isEmpty)
    }
}
