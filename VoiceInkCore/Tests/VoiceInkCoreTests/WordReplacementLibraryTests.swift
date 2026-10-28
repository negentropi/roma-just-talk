import Foundation
import VoiceInkCore

// This whole class uses existing codec APIs so the same oracle can run on the old reader.
final class WordReplacementLibraryCodecCompatibilityTests: XCTestCase {
    func testSettingsCodecRoundTripsFullLibraryWithoutLosingMetadata() throws {
        let record = fixtureRecord()
        let object = try roundTrip([
            "wordReplacements": ["old, legacy": "kept"],
            "wordReplacementLibrary": ["version": 1, "records": [record]]
        ])
        guard let library = object["wordReplacementLibrary"] as? [String: Any] else {
            XCTFail("The full replacement library must survive the existing settings codec.")
            return
        }
        XCTAssertEqual(library["version"] as? Int, 1)
        let records = try XCTUnwrap(library["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        let saved = try XCTUnwrap(records.first)
        for key in ["id", "matchingKind", "originalText", "replacementText"] {
            let actual = try XCTUnwrap(saved[key] as? String)
            let expected = try XCTUnwrap(record[key] as? String)
            XCTAssertEqual(Array(actual.utf8), Array(expected.utf8))
            XCTAssertEqual(Array(actual.utf16), Array(expected.utf16))
        }
        XCTAssertEqual(saved["dateAdded"] as? Double, 1234.25)
        XCTAssertEqual(saved["isEnabled"] as? Bool, false)
        let provenance = try XCTUnwrap(saved["provenance"] as? [String: String])
        XCTAssertEqual(provenance, record["provenance"] as? [String: String])
        XCTAssertEqual(object["wordReplacements"] as? [String: String], ["old, legacy": "kept"])
    }

    func testSettingsCodecRetainsPresentEmptyLibraryAlongsideLegacyMap() throws {
        let object = try roundTrip([
            "wordReplacements": ["old": "legacy"],
            "wordReplacementLibrary": ["version": 1, "records": []]
        ])
        guard let library = object["wordReplacementLibrary"] as? [String: Any] else {
            XCTFail("An explicitly empty full library must not become absent and select the legacy map.")
            return
        }
        XCTAssertEqual(library["version"] as? Int, 1)
        XCTAssertEqual((library["records"] as? [Any])?.count, 0)
    }

    func testSettingsCodecRejectsInvalidPresentLibraryBeforeLegacyFallback() throws {
        var invalid: [Any] = [
            NSNull(), "wrong", [:], ["version": NSNull(), "records": []],
            ["version": 0, "records": []], ["version": 2, "records": []],
            ["version": "1", "records": []], ["version": 1],
            ["version": 1, "records": NSNull()], ["version": 1, "records": "wrong"]
        ]
        for kind in [NSNull(), "future", 1] as [Any] {
            var record = fixtureRecord()
            record["matchingKind"] = kind
            invalid.append(["version": 1, "records": [record]])
        }
        var missingKind = fixtureRecord()
        missingKind.removeValue(forKey: "matchingKind")
        invalid.append(["version": 1, "records": [missingKind]])
        for payload in invalid {
            do {
                _ = try roundTrip(["wordReplacements": ["a,b": "legacy"], "wordReplacementLibrary": payload])
                XCTFail("A present invalid full library must reject, even when a valid legacy map exists.")
            } catch {}
        }
    }

    func testSettingsCodecLeavesOldMapOnlyShapeUntouched() throws {
        for map in [[" Flow, Voice Ink ": " roma "], [:]] {
            let object = try roundTrip(["wordReplacements": map])
            XCTAssertNil(object["wordReplacementLibrary"])
            XCTAssertEqual(object["wordReplacements"] as? [String: String], map)
        }
        let absent = try roundTrip([:])
        XCTAssertNil(absent["wordReplacementLibrary"])
        XCTAssertNil(absent["wordReplacements"])
        XCTAssertEqual(absent["version"] as? String, "0.0.0")
        let nullMap = try roundTrip(["wordReplacements": NSNull()])
        XCTAssertNil(nullMap["wordReplacements"])
    }

    private func fixtureRecord() -> [String: Any] {
        ["id": "00000000-0000-0000-0000-000000000101", "originalText": " a,b e\u{301} 👩🏽‍💻 ",
         "replacementText": " $1\\Temp\r\n é e\u{301} ", "dateAdded": 1234.25, "isEnabled": false,
         "matchingKind": "literal", "provenance": ["origin": "historyManual",
            "sourceTranscriptionID": "00000000-0000-0000-0000-000000000102", "sourceVariant": "processed"]]
    }

    private func roundTrip(_ object: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: object)
        let backup: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: data)
        let encoded = try VoiceInkSettingsBackupFileCodec.encode(backup)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    }
}

final class WordReplacementLibraryTests: XCTestCase {
    func testRecordsValidateBlanknessWithoutChangingExactLiteralContent() throws {
        let original = " , e\u{301} \r\n"
        let replacement = " $1\\Temp\r\n é e\u{301} "
        let value = try record(original: original, replacement: replacement)
        XCTAssertEqual(Array(value.originalText.utf8), Array(original.utf8))
        XCTAssertEqual(Array(value.originalText.utf16), Array(original.utf16))
        XCTAssertEqual(Array(value.replacementText.utf8), Array(replacement.utf8))
        XCTAssertEqual(Array(value.replacementText.utf16), Array(replacement.utf16))
        XCTAssertNil(value.provenance)
        _ = try record(original: ",")
        assertRejects { try self.record(original: " \n ") }
        assertRejects { try self.record(replacement: " \r\n ") }
        assertRejects { try self.record(original: " , ", kind: .legacyCommaAlternatives) }
        assertRejects { try self.record(date: Date(timeIntervalSinceReferenceDate: .infinity)) }
    }

    func testFullRecordsRequireEveryFieldAndCompleteKnownProvenance() throws {
        let value = try record()
        let bytes = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["id", "originalText", "replacementText", "dateAdded", "isEnabled", "matchingKind"] {
            var missing = object
            missing.removeValue(forKey: key)
            assertRejects { try self.decodeRecord(missing) }
            var null = object
            null[key] = NSNull()
            assertRejects { try self.decodeRecord(null) }
        }
        var withNullProvenance = object
        withNullProvenance["provenance"] = NSNull()
        assertRejects { try self.decodeRecord(withNullProvenance) }
        let known: [String: Any] = ["origin": "historyManual", "sourceTranscriptionID": uuid(50).uuidString,
                                    "sourceVariant": "recognition"]
        for key in ["origin", "sourceTranscriptionID", "sourceVariant"] {
            var missing = known
            missing.removeValue(forKey: key)
            var invalidRecord = object
            invalidRecord["provenance"] = missing
            assertRejects { try self.decodeRecord(invalidRecord) }
            invalidRecord["provenance"] = known.merging([key: NSNull()]) { _, new in new }
            assertRejects { try self.decodeRecord(invalidRecord) }
        }
        for (key, invalid) in [("origin", "automatic"), ("sourceVariant", "original"), ("sourceTranscriptionID", "bad")] {
            var invalidRecord = object
            invalidRecord["provenance"] = known.merging([key: invalid]) { _, new in new }
            assertRejects { try self.decodeRecord(invalidRecord) }
        }
        for variant in [VoiceInkWordReplacementSourceVariant.recognition, .processed, .enhanced] {
            let approved = try record(provenance: .init(sourceTranscriptionID: uuid(50), sourceVariant: variant))
            let decoded = try JSONDecoder().decode(VoiceInkWordReplacementRecord.self, from: JSONEncoder().encode(approved))
            XCTAssertEqual(decoded, approved)
        }
    }

    func testIdenticalIdentityIsIdempotentAndEveryChangedFieldConflicts() throws {
        let existing = try record(original: "é", replacement: "é")
        let same = VoiceInkWordReplacementLibrary(records: [existing]).preflightImport(existingRecords: [existing])
        XCTAssertTrue(same.canApply)
        XCTAssertEqual(same.recordsToInsert, [])
        XCTAssertEqual(same.duplicates.map(\.existingID), [existing.id])
        let changes = [
            try record(original: "e\u{301}", replacement: "é"),
            try record(original: "é", replacement: "e\u{301}"),
            try record(original: "é", replacement: "é", date: Date(timeIntervalSinceReferenceDate: 99)),
            try record(original: "é", replacement: "é", enabled: false),
            try record(original: "é", replacement: "é", kind: .legacyCommaAlternatives),
            try record(original: "é", replacement: "é", provenance: .init(sourceTranscriptionID: uuid(50), sourceVariant: .processed))
        ]
        for changed in changes {
            XCTAssertFalse(changed == existing)
            let plan = VoiceInkWordReplacementLibrary(records: [changed]).preflightImport(existingRecords: [existing])
            XCTAssertFalse(plan.canApply)
            XCTAssertEqual(plan.recordsToInsert, [])
            XCTAssertEqual(plan.conflicts.map(\.reason), [.identity])
            XCTAssertEqual(plan.conflicts.first?.existing, existing)
            XCTAssertEqual(plan.conflicts.first?.incoming, changed)
        }
    }

    func testDuplicateLiteralKeepsExistingIdentityDateEnabledAndProvenance() throws {
        let existing = try record(original: "a,b é", enabled: false,
                                  provenance: .init(sourceTranscriptionID: uuid(50), sourceVariant: .enhanced))
        let incoming = try record(id: 2, original: "A,B e\u{301}", date: Date(timeIntervalSinceReferenceDate: 99))
        let plan = VoiceInkWordReplacementLibrary(records: [incoming]).preflightImport(existingRecords: [existing])
        XCTAssertTrue(plan.canApply)
        XCTAssertEqual(plan.recordsToInsert, [])
        XCTAssertEqual(plan.duplicates.map(\.incomingID), [incoming.id])
        XCTAssertEqual(plan.duplicates.map(\.existingID), [existing.id])
        XCTAssertEqual(plan.conflicts, [])
    }

    func testSourceConflictsAreExplicitAndBlockEveryInsertion() throws {
        let existing = try record(original: "é", replacement: "é")
        let unrelated = try record(id: 3, original: "unrelated")
        let incoming = try record(id: 2, original: "e\u{301}", replacement: "e\u{301}")
        let plan = VoiceInkWordReplacementLibrary(records: [unrelated, incoming]).preflightImport(existingRecords: [existing])
        XCTAssertFalse(plan.canApply)
        XCTAssertEqual(plan.recordsToInsert, [])
        XCTAssertEqual(plan.conflicts.map(\.reason), [.source])
        XCTAssertEqual(plan.conflicts.first?.existing, existing)
        XCTAssertEqual(plan.conflicts.first?.incoming, incoming)
    }

    func testLegacyAlternativesKeepCaseInsensitiveWholeTokenConflicts() throws {
        let existing = try record(original: " A , beta ", kind: .legacyCommaAlternatives)
        let same = try record(id: 2, original: "a,BETA", kind: .legacyCommaAlternatives)
        let duplicate = VoiceInkWordReplacementLibrary(records: [same]).preflightImport(existingRecords: [existing])
        XCTAssertTrue(duplicate.canApply)
        XCTAssertEqual(duplicate.duplicates.map(\.existingID), [existing.id])
        let partial = try record(id: 3, original: "beta, gamma", kind: .legacyCommaAlternatives)
        let overlap = VoiceInkWordReplacementLibrary(records: [partial]).preflightImport(existingRecords: [existing])
        XCTAssertFalse(overlap.canApply)
        XCTAssertEqual(overlap.conflicts.map(\.reason), [.source])
        let substring = try record(id: 4, original: "alphabet", kind: .legacyCommaAlternatives)
        let separate = VoiceInkWordReplacementLibrary(records: [substring]).preflightImport(existingRecords: [existing])
        XCTAssertEqual(separate.recordsToInsert, [substring])
    }

    func testLiteralCommasStayWholeAndDifferentMatchingSemanticsRequireReview() throws {
        let legacy = try record(original: "a,b", kind: .legacyCommaAlternatives)
        let literal = try record(id: 2, original: "a,b")
        let separate = VoiceInkWordReplacementLibrary(records: [literal]).preflightImport(existingRecords: [legacy])
        XCTAssertTrue(separate.canApply)
        XCTAssertEqual(separate.recordsToInsert, [literal])
        let single = try record(id: 3, original: "a")
        let overlap = VoiceInkWordReplacementLibrary(records: [single]).preflightImport(existingRecords: [legacy])
        XCTAssertFalse(overlap.canApply)
        XCTAssertEqual(overlap.conflicts.map(\.reason), [.source])
    }

    func testBatchPreflightReportsEveryConflictingRecordWithoutMutatingInputs() throws {
        let first = try record(original: "same")
        let second = try record(id: 2, original: "SAME", replacement: "second")
        let third = try record(id: 3, original: "same", replacement: "third")
        let library = VoiceInkWordReplacementLibrary(records: [first, first, second, third])
        let plan = library.preflightImport(existingRecords: [])
        XCTAssertFalse(plan.canApply)
        XCTAssertEqual(plan.recordsToInsert, [])
        XCTAssertEqual(plan.duplicates.map(\.incomingID), [first.id])
        XCTAssertEqual(plan.conflicts.map(\.incoming.id), [second.id, third.id])
        XCTAssertEqual(plan.conflicts.map(\.existing.id), [first.id, first.id])
        XCTAssertEqual(library.records, [first, first, second, third])
        XCTAssertEqual(library.preflightImport(existingRecords: []), plan)
    }

    func testRepeatedDuplicatesAlwaysReferToTheRetainedIdentity() throws {
        let existing = try record()
        let incoming = try record(id: 2)
        let fromExisting = VoiceInkWordReplacementLibrary(records: [incoming, incoming])
            .preflightImport(existingRecords: [existing])
        XCTAssertTrue(fromExisting.canApply)
        XCTAssertEqual(fromExisting.recordsToInsert, [])
        XCTAssertEqual(fromExisting.duplicates.map(\.existingID), [existing.id, existing.id])
        let inBatch = VoiceInkWordReplacementLibrary(records: [existing, incoming, incoming])
            .preflightImport(existingRecords: [])
        XCTAssertTrue(inBatch.canApply)
        XCTAssertEqual(inBatch.recordsToInsert, [existing])
        XCTAssertEqual(inBatch.duplicates.map(\.existingID), [existing.id, existing.id])
        let changed = try record(id: 2, original: "other")
        let collision = VoiceInkWordReplacementLibrary(records: [incoming, changed])
            .preflightImport(existingRecords: [existing])
        XCTAssertFalse(collision.canApply)
        XCTAssertEqual(collision.conflicts.map(\.reason), [.identity])
    }

    func testLegacyAlternativeMultiplicityAndOrderRequireReview() throws {
        let existing = try record(original: "a", replacement: "a a", kind: .legacyCommaAlternatives)
        let repeated = try record(id: 2, original: "a,a", replacement: "a a", kind: .legacyCommaAlternatives)
        let existingRule = VoiceInkWordReplacementRule(originalText: existing.originalText, replacementText: existing.replacementText)
        let repeatedRule = VoiceInkWordReplacementRule(originalText: repeated.originalText, replacementText: repeated.replacementText)
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply([existingRule], to: "a"), "a a")
        XCTAssertEqual(VoiceInkWordReplacementEngine.apply([repeatedRule], to: "a"), "a a a a")
        let plan = VoiceInkWordReplacementLibrary(records: [repeated]).preflightImport(existingRecords: [existing])
        XCTAssertFalse(plan.canApply)
        XCTAssertEqual(plan.conflicts.map(\.reason), [.source])
        let ordered = try record(original: "a,b", kind: .legacyCommaAlternatives)
        let reordered = try record(id: 3, original: "b,a", kind: .legacyCommaAlternatives)
        let orderReview = VoiceInkWordReplacementLibrary(records: [reordered]).preflightImport(existingRecords: [ordered])
        XCTAssertFalse(orderReview.canApply)
        XCTAssertEqual(orderReview.conflicts.map(\.reason), [.source])
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    private func record(
        id: Int = 1, original: String = "source", replacement: String = "output",
        date: Date = Date(timeIntervalSinceReferenceDate: 1234.25), enabled: Bool = true,
        kind: VoiceInkWordReplacementMatchingKind = .literal,
        provenance: VoiceInkWordReplacementProvenance? = nil
    ) throws -> VoiceInkWordReplacementRecord {
        try .init(id: uuid(id), originalText: original, replacementText: replacement, dateAdded: date,
                  isEnabled: enabled, matchingKind: kind, provenance: provenance)
    }

    private func decodeRecord(_ object: [String: Any]) throws -> VoiceInkWordReplacementRecord {
        try JSONDecoder().decode(VoiceInkWordReplacementRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func assertRejects<T>(_ operation: () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try operation()
            XCTFail("Expected invalid full replacement data to reject.", file: file, line: line)
        } catch {}
    }
}
