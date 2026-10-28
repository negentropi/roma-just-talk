import Foundation
import VoiceInkCore

final class LiteralCorrectionRuleTests: XCTestCase {
    func testLiteralCommaIsOneSourcePhrase() throws {
        let rules = try decode(#"[{"originalText":"a,b","replacementText":"X","matchingKind":"literal"}]"#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(rules, to: "a,b a b A,B"), "X a b X")
        let punctuation = try decode(#"[{"originalText":",","replacementText":";","matchingKind":"literal"}]"#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(punctuation, to: " , "), " ; ")
        let escaped = try decode(#"[{"originalText":"a+b","replacementText":"X","matchingKind":"literal"}]"#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(escaped, to: "a+b aaab"), "X aaab")
    }

    func testLiteralOutputNeverFeedsAnotherReplacement() throws {
        for secondKind in ["literal", "legacyCommaAlternatives"] {
            let json = """
            [{"originalText":"alpha","replacementText":"beta","matchingKind":"literal"},
             {"originalText":"beta","replacementText":"X","matchingKind":"\(secondKind)"}]
            """
            XCTAssertEqual(VoiceInkWordReplacementEngine.apply(try decode(json), to: "alpha beta"), "beta X")
        }
        let selfMatch = try decode(#"[{"originalText":"cat","replacementText":"cat cat","matchingKind":"literal"}]"#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(selfMatch, to: "cat"), "cat cat")
    }

    func testLegacyOutputCannotCreateALiteralMatch() throws {
        let rules = try decode(#"""
        [{"originalText":"cat","replacementText":"DONE","matchingKind":"literal"},
         {"originalText":"source","replacementText":"cat"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(rules, to: "source"), "cat")
    }

    func testLiteralSourceBlocksWholeCrossingLegacyMatches() throws {
        let rules = try decode(#"""
        [{"originalText":"green","replacementText":"X","matchingKind":"literal"},
         {"originalText":"red green blue","replacementText":"Z"},
         {"originalText":"red","replacementText":"R"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(rules, to: "red green blue"), "R X blue")
    }

    func testLiteralOverlapUsesLeftmostLongestThenDeclaredOrder() throws {
        let overlap = try decode(#"""
        [{"originalText":"green blue","replacementText":"Y","matchingKind":"literal"},
         {"originalText":"red","replacementText":"Z","matchingKind":"literal"},
         {"originalText":"red green","replacementText":"X","matchingKind":"literal"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(overlap, to: "red green blue"), "X blue")
        let repeated = try decode(#"""
        [{"originalText":"ああ","replacementText":"X","matchingKind":"literal"},
         {"originalText":"あああ","replacementText":"Y","matchingKind":"literal"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(repeated, to: "あああああ"), "YX")
        let ties = try decode(#"""
        [{"originalText":"ROMA","replacementText":"first","matchingKind":"literal"},
         {"originalText":"roma","replacementText":"second","matchingKind":"literal"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(ties, to: "Roma"), "first")
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(Array(ties.reversed()), to: "Roma"), "second")
        let adjacent = try decode(#"""
        [{"originalText":"あ","replacementText":"A","matchingKind":"literal"},
         {"originalText":"い","replacementText":"B","matchingKind":"literal"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(adjacent, to: "あい"), "AB")
    }

    func testProtectedSourceRetainsFullTextBoundaryContext() throws {
        let rules = try decode(#"""
        [{"originalText":"X東京","replacementText":"Y","matchingKind":"literal"},
         {"originalText":"alpha","replacementText":"beta"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(rules, to: "alphaX東京"), "alphaY")
        let boundaries = try decode(#"""
        [{"originalText":"clair","replacementText":"clear","matchingKind":"literal"},
         {"originalText":"Roma","replacementText":"RJT","matchingKind":"literal"},
         {"originalText":"東京","replacementText":"Tokyo","matchingKind":"literal"}]
        """#)
        let input = "éclair e\u{301}clair clair Romaé Roma\u{301} Roma٣ Roma 東京都"
        let expected = "éclair e\u{301}clair clear Romaé Roma\u{301} Roma٣ RJT Tokyo都"
        let output = VoiceInkWordReplacementEngine.apply(boundaries, to: input)
        XCTAssertEqual(Array(output.utf8), Array(expected.utf8))
        XCTAssertEqual(Array(output.utf16), Array(expected.utf16))
        let mixed = try decode(#"""
        [{"originalText":"fixed","replacementText":"X","matchingKind":"literal"},
         {"originalText":"東京","replacementText":"R"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(mixed, to: "東京都 fixed"), "R都 X")
    }

    func testProtectedRangesRemapUTF16AndInsertExactLiteralOutputLast() throws {
        let replacement = " longword end a,b $5.00\\Temp\\$1\r\n e\u{301} 👩🏽‍💻 "
        let data = try JSONSerialization.data(withJSONObject: [
            ["originalText": "longword", "replacementText": "x"],
            ["originalText": "end", "replacementText": "very long tail"],
            ["originalText": "a,b", "replacementText": replacement, "matchingKind": "literal"],
        ])
        let rules = try JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: data)
        let output = VoiceInkWordReplacementEngine.apply(rules, to: "👩🏽‍💻 e\u{301} longword a,b end longword a,b end")
        let expected = "👩🏽‍💻 e\u{301} x " + replacement + " very long tail x " + replacement + " very long tail"
        XCTAssertEqual(Array(output.utf8), Array(expected.utf8))
        XCTAssertEqual(Array(output.utf16), Array(expected.utf16))
    }

    func testNonSpacedLiteralMatchesCanonicalSourceAndActualUTF16Ranges() throws {
        let rules = try decode(#"""
        [{"originalText":"é東京","replacementText":"tail e\u0301 👩🏽‍💻","matchingKind":"literal"},
         {"originalText":"source","replacementText":"👩🏽‍💻"},
         {"originalText":"tail","replacementText":"X"}]
        """#)
        let output = VoiceInkWordReplacementEngine.apply(rules, to: "source e\u{301}東京 tail É東京 e\u{301}東京")
        let expected = "👩🏽‍💻 tail e\u{301} 👩🏽‍💻 X tail e\u{301} 👩🏽‍💻 tail e\u{301} 👩🏽‍💻"
        XCTAssertEqual(Array(output.utf8), Array(expected.utf8))
        XCTAssertEqual(Array(output.utf16), Array(expected.utf16))
        let overlap = try decode(#"""
        [{"originalText":"é東京","replacementText":"SHORT","matchingKind":"literal"},
         {"originalText":"e\u0301東京é","replacementText":"LONG","matchingKind":"literal"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(overlap, to: "e\u{301}東京e\u{301}東京"), "LONG東京")
    }

    func testLegacyOnlyAndUnmatchedLiteralKeepSequentialCommaBehavior() throws {
        let chain = try decode(#"""
        [{"originalText":"alpha","replacementText":"beta"},
         {"originalText":"beta","replacementText":"X"}]
        """#)
        let unmatched = try decode(#"[{"originalText":"never","replacementText":"Y","matchingKind":"literal"}]"#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(chain, to: "alpha"), "X")
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(chain + unmatched, to: "alpha"), "X")
        let variants = try decode(#"[{"originalText":"xy, z","replacementText":"z z"}]"#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(variants, to: "xy"), "z z z z")
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(variants + unmatched, to: "xy"), "z z z z")
    }

    func testBlankLiteralSourcesAreNoOpsAndNonblankSourcesAreNotTrimmed() throws {
        let rules = try decode(#"""
        [{"originalText":"","replacementText":"BAD","matchingKind":"literal"},
         {"originalText":" \t\r\n","replacementText":"BAD","matchingKind":"literal"},
         {"originalText":"alpha","replacementText":"X"}]
        """#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(rules, to: ""), "")
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(rules, to: "alpha \t\r\n"), "X \t\r\n")
        let spaced = try decode(#"[{"originalText":" a,b ","replacementText":" X ","matchingKind":"literal"}]"#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(spaced, to: " a,b "), " X ")
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(spaced, to: "a,b"), "a,b")
        let punctuation = try decode(#"[{"originalText":"(alpha)","replacementText":"X","matchingKind":"literal"}]"#)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(punctuation, to: "(alpha) (alpha)x a(alpha)"), "X (alpha)x a(alpha)")
    }

    func testLegacyEncodingKeepsTwoKeysAndLiteralKindRoundTrips() throws {
        let legacy = try decode(#"[{"originalText":"a,b","replacementText":"X"}]"#)
        let explicitLegacy = try decode(#"[{"originalText":"a,b","replacementText":"X","matchingKind":"legacyCommaAlternatives"}]"#)
        for rules in [legacy, explicitLegacy, [VoiceInkWordReplacementRule(originalText: "a,b", replacementText: "X")]] {
            let data = try JSONEncoder().encode(rules)
            let objects = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
            XCTAssertEqual(objects, [["originalText": "a,b", "replacementText": "X"]])
        }
        let literal = try decode(#"[{"originalText":"a,b","replacementText":"X","matchingKind":"literal"}]"#)
        let data = try JSONEncoder().encode(literal)
        let objects = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        XCTAssertEqual(objects, [["originalText": "a,b", "replacementText": "X", "matchingKind": "literal"]])
        XCTAssertEqual(try JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: data), literal)
    }

    func testExplicitInvalidMatchingKindsRejectInsteadOfBecomingLegacy() {
        for value in ["null", "42", "true", "{}", "[]", "\"future-kind\"", "\"\""] {
            let json = "[{\"originalText\":\"a,b\",\"replacementText\":\"X\",\"matchingKind\":\(value)}]"
            do {
                _ = try decode(json)
                XCTFail("An explicit invalid kind must not reinterpret a comma-containing source as legacy")
            } catch {
                XCTAssertTrue(error is DecodingError)
            }
        }
    }

    func testSharedEditReconstructionPreservesLiteralKind() throws {
        let rules = try decode(#"[{"originalText":"a,b","replacementText":"old","matchingKind":"literal"}]"#)
        let snapshot = VoiceInkDictionarySettingsSnapshot(
            fillerWords: [], customVocabularyTerms: [], wordReplacements: rules,
            vocabularySortMode: .wordAscending, wordReplacementSortMode: .originalAscending
        )
        let submission = snapshot.wordReplacementEditSubmission(
            VoiceInkWordReplacementEditState(original: "a,b", replacement: "new"), replacing: rules[0]
        )
        var updated = rules
        snapshot.applyWordReplacementEditSubmission(submission, replacing: rules[0]) { updated = $0 }
        let data = try JSONEncoder().encode(updated)
        let objects = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        XCTAssertEqual(objects, [["originalText": "a,b", "replacementText": "new", "matchingKind": "literal"]])
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply(updated, to: "a,b a b"), "new a b")
    }

    func testLegacyExportMapOmitsEveryLiteralRule() throws {
        let rules = try decode(#"""
        [{"originalText":"keep","replacementText":"first"},
         {"originalText":"keep","replacementText":"last"},
         {"originalText":"a,b","replacementText":"literal comma","matchingKind":"literal"},
         {"originalText":"keep","replacementText":"literal override","matchingKind":"literal"}]
        """#)
        var records: [String: String]?
        VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(vocabularyWords: [], wordReplacementRules: rules)
            .applyRuntimeState(setVocabularyBackupRecords: { _ in }, setWordReplacementBackupRecords: { records = $0 })
        XCTAssertEqual(records, ["keep": "last"])
        VoiceInkDictionaryPolicy.dictionaryBackupExportPlan(vocabularyWords: [], wordReplacementRules: Array(rules.suffix(2)))
            .applyRuntimeState(setVocabularyBackupRecords: { _ in }, setWordReplacementBackupRecords: { records = $0 })
        XCTAssertNil(records)
    }

    private func decode(_ json: String) throws -> [VoiceInkWordReplacementRule] {
        try JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: Data(json.utf8))
    }
}
