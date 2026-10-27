import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @available(macOS 15, *)
    @Test(.enabled(if: CorrectionLibraryStoreCheck.isEnabled), .timeLimit(.minutes(2)))
    @MainActor func liveCorrectionLibraryPersistentStoreUpgrade() async throws {
        let inputs = try DictationStoreSeedInputs()
        var observation = inputs.observation
        observation["testName"] = "liveCorrectionLibraryPersistentStoreUpgrade"
        observation["sourcePath"] = #filePath
        try inputs.write(observation, named: "observation.json")
        print("RJT correction store started phase=\(inputs.phase.rawValue) hostPID=\(inputs.hostPID) sourceSHA=\(inputs.sourceSHA)")
        do {
            try await inputs.waitForHostObservation()
            try CorrectionLibraryStoreCheck.run(inputs: inputs)
            observation["classification"] = "passed"
            observation["scope"] = "Actual local correction scalar upgrade and explicit backend approval fixture; no human approval, UI or CloudKit sync proof."
            try inputs.write(observation, named: "observation.json")
        } catch {
            observation["classification"] = "failed"
            observation["failure"] = String(describing: error)
            try inputs.write(observation, named: "observation.json")
            throw error
        }
    }
}

@available(macOS 15, *)
@MainActor
private enum CorrectionLibraryStoreCheck {
    nonisolated static var isEnabled: Bool {
        DictationStoreSeedInputs.value("RJT_CORRECTION_LIBRARY_STORE_CHECKS") == "1"
            && DictationStoreSeedInputs.value("GITHUB_ACTIONS") == "true"
    }

    private static let manualID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    private static let disabledID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
    private static let unknownID = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
    private static let sourceID = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
    private static let manualDate = Date(timeIntervalSince1970: 1_700_000_200.125)
    private static let disabledDate = Date(timeIntervalSince1970: 1_700_000_201.25)
    private static let unknownDate = Date(timeIntervalSince1970: 1_700_000_202.5)
    private static let manualOriginal = "Manual, Cafe\u{301} $1\r\n\"literal\" 🧪"
    private static let manualReplacement = "Manual fixed $2\r\n🧪"
    private static let disabledOriginal = "Disabled, Cafe\u{301} $3 \"literal\""
    private static let disabledReplacement = "Disabled fixed $4"
    private static let historyOriginal = "History, Cafe\u{301} $5\r\n\"literal\" 🧪"
    private static let historyReplacement = "History fixed $6\r\n\"approval fixture\" 🧪"
    private static let unknownOriginal = "Unknown, Cafe\u{301} $7"
    private static let unknownReplacement = "Unsafe $8"
    private static let unknownKind = "future-kind"
    private static let historicalIDs = Set([
        "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222",
        "33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444",
        "55555555-5555-4555-8555-555555555555", "66666666-6666-4666-8666-666666666666"
    ].map { UUID(uuidString: $0)! })
    private static let sourceRecognition = "Before [History, Cafe\u{301} $5\r\n\"literal\" 🧪] after."
    private static let compatibilityInput = "Manual, Cafe\u{301} $1\r\n\"literal\" 🧪\nHistory, Cafe\u{301} $5\r\n\"literal\" 🧪\nAcme, Inc."

    static func run(inputs: DictationStoreSeedInputs) throws {
        let fixture = try DictationStoreSeedFixture(inputs: inputs)
        #if CORRECTION_LIBRARY_CANDIDATE
        try #require(inputs.phase == .correctionWrite || inputs.phase == .correctionReopen)
        let generated: GeneratedIdentity
        if inputs.phase == .correctionWrite {
            try fixture.run()
            try historicalTranscriptionMetadata(fixture.context, inputs: inputs)
            try verifyLegacyReplacements(fixture.context, inputs: inputs)
            generated = try writeRows(context: fixture.context, inputs: inputs)
        } else {
            generated = try readGeneratedIdentity(inputs: inputs)
            try inputs.write(generated.receipt, named: "service-generated-identity.json")
        }
        let additionalIDs: Set<UUID> = [manualID, disabledID, unknownID, generated.id]
        try #require(additionalIDs.count == 4)
        try fixture.run(allowedAdditionalWordReplacementIDs: additionalIDs)
        try historicalTranscriptionMetadata(fixture.context, inputs: inputs)
        try verifyLegacyReplacements(fixture.context, excluding: additionalIDs, inputs: inputs)
        try verifyNewRows(context: fixture.context, generated: generated, inputs: inputs)
        #else
        try #require(inputs.phase == .seed || inputs.phase == .oldReopen)
        try fixture.run()
        try historicalTranscriptionMetadata(fixture.context, inputs: inputs)
        let compatibility = WordReplacement(originalText: "", replacementText: "")
        let output = VoiceInkWordReplacementEngine.apply([compatibility.voiceInkRule], to: compatibilityInput)
        try exact(output, compatibilityInput)
        try inputs.write([
            "version": 1, "phase": inputs.phase.rawValue, "hostPID": inputs.hostPID,
            "rawOriginalText": string(""), "rawReplacementText": string(""),
            "input": string(compatibilityInput), "output": string(output), "unchanged": true,
            "scope": "Actual predecessor model and engine empty-raw-pair matching boundary only. No CloudKit sync or backward store-open proof."
        ], named: "old-reader-safety.json")
        #endif
        try #require(!fixture.context.hasChanges)
    }

    private static func historicalTranscriptionMetadata(_ context: ModelContext, inputs: DictationStoreSeedInputs) throws {
        let rows = try context.fetch(FetchDescriptor<Transcription>()).sorted { $0.id.uuidString < $1.id.uuidString }
        try #require(rows.count == 2)
        let actual = rows.map { row in
            ["id": row.id.uuidString, "recognitionText": optionalString(row.recognitionText),
             "dictationProfileRawValue": optionalString(row.dictationProfileRawValue),
             "clarityStyleRawValue": optionalString(row.clarityStyleRawValue),
             "processingFailureReason": optionalString(row.processingFailureReason)] as [String: Any]
        }
        let expected = ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"].map { id in
            ["id": id, "recognitionText": NSNull(), "dictationProfileRawValue": NSNull(),
             "clarityStyleRawValue": NSNull(), "processingFailureReason": NSNull()] as [String: Any]
        }
        try equalJSON(actual, expected)
        try inputs.write(actual, named: "historical-transcription-metadata.json")
        try inputs.write(expected, named: "expected-historical-transcription-metadata.json")
    }

    private static func string(_ value: String) -> [String: Any] { DictationStoreSeedFixture.string(value) }
    private static func optionalString(_ value: String?) -> Any { DictationStoreSeedFixture.optionalString(value) }
    private static func optionalUUID(_ value: UUID?) -> Any { value?.uuidString as Any? ?? NSNull() }

    private static func equalJSON(_ actual: Any, _ expected: Any) throws {
        let actualBytes = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys])
        let expectedBytes = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
        try #require(actualBytes == expectedBytes, "Persisted values must retain their exact fields, nils and string code units.")
    }

    private static func exact(_ actual: String, _ expected: String) throws {
        try #require(Array(actual.utf8) == Array(expected.utf8) && Array(actual.utf16) == Array(expected.utf16))
    }

    #if CORRECTION_LIBRARY_CANDIDATE
    @MainActor
    private struct GeneratedIdentity {
        let id: UUID
        let dateAdded: Date
        let hostPID: Int

        var receipt: [String: Any] {
            ["version": 1, "id": id.uuidString, "dateAdded": dateAdded.timeIntervalSince1970,
             "sourceTranscriptionID": sourceID.uuidString, "sourceVariant": "recognition",
             "originalText": string(historyOriginal), "replacementText": string(historyReplacement),
             "createdInPhase": "correction-write", "generatedByServicePreview": true, "hostPID": hostPID]
        }
    }

    private static func verifyLegacyReplacements(_ context: ModelContext, excluding ids: Set<UUID> = [], inputs: DictationStoreSeedInputs) throws {
        let rows = try context.fetch(FetchDescriptor<WordReplacement>()).filter { !ids.contains($0.id) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        try #require(rows.count == 2)
        for row in rows {
            try #require(row.matchingKindRawValue == nil && row.approvalOriginRawValue == nil
                         && row.sourceTranscriptionID == nil && row.sourceVariantRawValue == nil
                         && row.literalOriginalText == nil && row.literalReplacementText == nil)
            try #require(row.matchingKind == .legacyCommaAlternatives)
            let record = try row.record
            try #require(record.matchingKind == .legacyCommaAlternatives && record.provenance == nil)
            let rule = try row.voiceInkRule
            try #require(rule.matchingKind == .legacyCommaAlternatives)
        }
        let actual = rows.map { row in
            ["id": row.id.uuidString, "matchingKindRawValue": optionalString(row.matchingKindRawValue),
             "approvalOriginRawValue": optionalString(row.approvalOriginRawValue), "sourceTranscriptionID": optionalUUID(row.sourceTranscriptionID),
             "sourceVariantRawValue": optionalString(row.sourceVariantRawValue), "literalOriginalText": optionalString(row.literalOriginalText),
             "literalReplacementText": optionalString(row.literalReplacementText)] as [String: Any]
        }
        let expected = ["33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444"].map { id in
            ["id": id, "matchingKindRawValue": NSNull(), "approvalOriginRawValue": NSNull(), "sourceTranscriptionID": NSNull(),
             "sourceVariantRawValue": NSNull(), "literalOriginalText": NSNull(), "literalReplacementText": NSNull()] as [String: Any]
        }
        try equalJSON(actual, expected)
        try inputs.write(actual, named: "historical-word-replacement-metadata.json")
        try inputs.write(expected, named: "expected-historical-word-replacement-metadata.json")
    }

    private static func writeRows(context: ModelContext, inputs: DictationStoreSeedInputs) throws -> GeneratedIdentity {
        let manual = try VoiceInkWordReplacementRecord(
            id: manualID, originalText: manualOriginal, replacementText: manualReplacement,
            dateAdded: manualDate, isEnabled: true, matchingKind: .literal
        )
        let disabled = try VoiceInkWordReplacementRecord(
            id: disabledID, originalText: disabledOriginal, replacementText: disabledReplacement,
            dateAdded: disabledDate, isEnabled: false, matchingKind: .literal
        )
        context.insert(WordReplacement(record: manual))
        context.insert(WordReplacement(record: disabled))
        let history = Transcription(text: "Processed fixture", duration: 3.25, enhancedText: "Enhanced fixture", recognitionText: sourceRecognition)
        history.id = sourceID
        history.timestamp = Date(timeIntervalSince1970: 1_700_000_203.75)
        context.insert(history)
        try context.save()

        let source = try HistoryCorrectionApprovalService.capture(
            transcriptionID: sourceID, variant: .recognition, expectedText: sourceRecognition, using: context
        )
        let occurrences = try HistoryCorrectionApprovalService.occurrences(of: historyOriginal, in: source)
        try #require(occurrences.count == 1)
        let range = try #require(occurrences.first)
        let windowStart = Date()
        let preview = try HistoryCorrectionApprovalService.preview(source: source, range: range, replacementText: historyReplacement, using: context)
        let windowEnd = Date()
        let generated = GeneratedIdentity(id: preview.record.id, dateAdded: preview.record.dateAdded, hostPID: Int(inputs.hostPID))
        try #require(![manualID, disabledID, unknownID, sourceID].contains(generated.id))
        try #require(!historicalIDs.contains(generated.id))
        try #require(generated.dateAdded >= windowStart && generated.dateAdded <= windowEnd)
        try equalJSON(canonicalSnapshot(preview.record), expectedCanonical(
            id: generated.id, date: generated.dateAdded, enabled: true, original: historyOriginal,
            replacement: historyReplacement, source: sourceID, variant: "recognition"
        ))
        try #require(preview.importPlan.canApply && preview.importPlan.duplicates.isEmpty)
        try inputs.write(generated.receipt, named: "service-generated-identity.json")
        guard case .inserted(let approved) = try HistoryCorrectionApprovalService.approve(preview, using: context) else {
            try #require(false, "The fresh explicit approval fixture must insert one rule.")
            return generated
        }
        try #require(approved.id == generated.id && approved.dateAdded == generated.dateAdded)
        let provenance = try #require(try approved.record.provenance)
        let existed = try HistoryCorrectionApprovalService.sourceExists(for: provenance, using: context)
        try #require(existed)
        context.delete(history)
        try context.save()
        let remains = try HistoryCorrectionApprovalService.sourceExists(for: provenance, using: context)
        try #require(!remains)

        let unknown = WordReplacement(originalText: unknownOriginal, replacementText: unknownReplacement, dateAdded: unknownDate, isEnabled: false)
        unknown.id = unknownID
        unknown.matchingKindRawValue = unknownKind
        context.insert(unknown)
        try context.save()
        return generated
    }

    private static func readGeneratedIdentity(inputs: DictationStoreSeedInputs) throws -> GeneratedIdentity {
        let rootPath = try #require(DictationStoreSeedInputs.value("RJT_STORE_RUN_ROOT"))
        try #require(rootPath.hasPrefix("/"))
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let url = root.appendingPathComponent("correction-write/observations/service-generated-identity.json").standardizedFileURL
        try #require(url.path.hasPrefix(root.path + "/") && url.resolvingSymlinksInPath().path == url.path)
        let value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let idValue = try #require(value["id"] as? String)
        let id = try #require(UUID(uuidString: idValue))
        let timestamp = try #require(value["dateAdded"] as? Double)
        let hostPID = try #require(value["hostPID"] as? Int)
        try #require(timestamp.isFinite && hostPID > 0 && hostPID != Int(inputs.hostPID))
        try #require(![manualID, disabledID, unknownID, sourceID].contains(id))
        try #require(!historicalIDs.contains(id))
        let generated = GeneratedIdentity(id: id, dateAdded: Date(timeIntervalSince1970: timestamp), hostPID: hostPID)
        try equalJSON(value, generated.receipt)
        return generated
    }

    private static func verifyNewRows(context: ModelContext, generated: GeneratedIdentity, inputs: DictationStoreSeedInputs) throws {
        let newIDs: Set<UUID> = [manualID, disabledID, unknownID, generated.id]
        let allRows = try context.fetch(FetchDescriptor<WordReplacement>())
        let rows = allRows.filter { newIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
        let historical = allRows.filter { !newIDs.contains($0.id) }
        try #require(rows.count == 4 && historical.count == 2)
        let dictionaryStore = try #require(historical.first?.persistentModelID.storeIdentifier)
        try #require(rows.allSatisfy { $0.persistentModelID.storeIdentifier == dictionaryStore })
        let actual = rows.map(storedSnapshot)
        try equalJSON(actual, expectedStoredRows(generated: generated))
        try inputs.write(actual, named: "correction-records.json")
        try inputs.write(expectedStoredRows(generated: generated), named: "expected-correction-records.json")
        let unknown = try #require(rows.first { $0.id == unknownID })
        try #require(unknown.matchingKind == nil && !unknown.isEnabled)
        try requireUnknownFailure { try unknown.record }
        try requireUnknownFailure { try unknown.voiceInkRule }
        try requireUnknownFailure { try DictionaryService.setWordReplacementEnabled(unknown, isEnabled: true, context: context) }
        try #require(!unknown.isEnabled)
        try requireUnknownFailure { try DictionaryService.snapshotWordReplacementRecords(using: context) }

        let valid = rows.filter { $0.id != unknownID }
        let canonical = try valid.map { canonicalSnapshot(try $0.record) }
        try equalJSON(canonical, expectedCanonicalRows(generated: generated))
        try inputs.write(canonical, named: "correction-canonical-records.json")
        try inputs.write(expectedCanonicalRows(generated: generated), named: "expected-correction-canonical-records.json")
        for row in valid {
            try #require(row.originalText.isEmpty && row.replacementText.isEmpty && row.matchingKind == .literal)
            let rule = try row.voiceInkRule
            try #require(rule.matchingKind == .literal)
        }
        let history = try #require(valid.first { $0.id == generated.id })
        let historyRecord = try history.record
        let provenance = try #require(historyRecord.provenance)
        try #require(provenance.sourceTranscriptionID == sourceID && provenance.sourceVariant == .recognition)
        let sourceExists = try HistoryCorrectionApprovalService.sourceExists(for: provenance, using: context)
        try #require(!sourceExists)
        let transcripts = try context.fetch(FetchDescriptor<Transcription>())
        try #require(transcripts.count == 2 && !transcripts.contains { $0.id == sourceID })

        let enabled = try DictionaryService.snapshotEnabledReplacementRules(using: context)
        try #require(enabled.count == 3)
        let input = manualOriginal + "\n" + historyOriginal + "\n" + disabledOriginal + "\n" + unknownOriginal
        let expected = manualReplacement + "\n" + historyReplacement + "\n" + disabledOriginal + "\n" + unknownOriginal
        let output = VoiceInkWordReplacementEngine.apply(enabled, to: input)
        try exact(output, expected)
        let serviceOutput = DictionaryService.applyWordReplacements(to: input, using: context)
        try exact(serviceOutput, expected)
        let legacyProjection = valid.map { VoiceInkWordReplacementRule(originalText: $0.originalText, replacementText: $0.replacementText) }
        try exact(VoiceInkWordReplacementEngine.apply(legacyProjection, to: compatibilityInput), compatibilityInput)
        let identifiers = try rows.map { row in
            var result = try DictationStoreSeedFixture.persistentIdentity(row)
            result["recordID"] = row.id.uuidString
            return result
        }
        try inputs.write(identifiers, named: "correction-identifiers.json")
        try #require(!context.hasChanges)
        try inputs.write([
            "version": 1, "phase": inputs.phase.rawValue, "hostPID": inputs.hostPID,
            "historicalRowCount": 2, "additionalRecordCount": 4, "storedFieldsPerNewRecord": 11,
            "historicalStoredFieldCount": 39, "historicalNewFieldsNil": true,
            "historicalNilKindMeansLegacy": true, "literalRawPairsEmpty": true,
            "exactStoredAndCanonicalValues": true, "unknownRawPreserved": true,
            "unknownExecutionRejected": true, "unknownEnableRejected": true, "unknownRemainsDisabled": true,
            "sourceHistoryAbsent": true, "sourceScalarProvenancePreserved": true,
            "explicitSavePerformed": inputs.phase == .correctionWrite,
            "sourceHistoryDeleted": inputs.phase == .correctionWrite,
            "approvalServiceInvoked": inputs.phase == .correctionWrite,
            "literalEngineOutput": string(output), "literalEngineExpected": string(expected),
            "literalServiceOutput": string(serviceOutput),
            "scope": "Programmatic explicit backend approval and scalar persistence fixture. No actual human approval, UI, CloudKit sync or older-client store-open proof."
        ], named: "correction-observation.json")
    }

    private static func requireUnknownFailure<T>(_ operation: () throws -> T) throws {
        do {
            _ = try operation()
        } catch let error as WordReplacement.StoredValueError {
            try #require(error == .unsupportedMatchingKind(unknownKind))
            return
        }
        try #require(false, "Unknown matching kinds must fail before conversion, enabling or execution.")
    }

    private static func storedSnapshot(_ row: WordReplacement) -> [String: Any] {
        var result = DictationStoreSeedFixture.replacementSnapshot(row)
        result["matchingKindRawValue"] = optionalString(row.matchingKindRawValue)
        result["approvalOriginRawValue"] = optionalString(row.approvalOriginRawValue)
        result["sourceTranscriptionID"] = optionalUUID(row.sourceTranscriptionID)
        result["sourceVariantRawValue"] = optionalString(row.sourceVariantRawValue)
        result["literalOriginalText"] = optionalString(row.literalOriginalText)
        result["literalReplacementText"] = optionalString(row.literalReplacementText)
        return result
    }

    private static func canonicalSnapshot(_ row: VoiceInkWordReplacementRecord) -> [String: Any] {
        ["id": row.id.uuidString, "originalText": string(row.originalText), "replacementText": string(row.replacementText),
         "dateAdded": row.dateAdded.timeIntervalSince1970, "isEnabled": row.isEnabled,
         "matchingKind": string(row.matchingKind.rawValue), "approvalOrigin": optionalString(row.provenance?.origin.rawValue),
         "sourceTranscriptionID": optionalUUID(row.provenance?.sourceTranscriptionID),
         "sourceVariant": optionalString(row.provenance?.sourceVariant.rawValue)]
    }

    private static func expectedStoredRows(generated: GeneratedIdentity) -> [[String: Any]] {
        [
            expectedStored(id: manualID, date: manualDate, enabled: true, kind: "literal", original: manualOriginal, replacement: manualReplacement),
            expectedStored(id: disabledID, date: disabledDate, enabled: false, kind: "literal", original: disabledOriginal, replacement: disabledReplacement),
            expectedStored(id: generated.id, date: generated.dateAdded, enabled: true, kind: "literal", original: historyOriginal, replacement: historyReplacement, source: sourceID, variant: "recognition"),
            expectedStored(id: unknownID, date: unknownDate, enabled: false, kind: unknownKind, original: unknownOriginal, replacement: unknownReplacement)
        ].sorted { ($0["id"] as! String) < ($1["id"] as! String) }
    }

    private static func expectedStored(id: UUID, date: Date, enabled: Bool, kind: String, original: String, replacement: String, source: UUID? = nil, variant: String? = nil) -> [String: Any] {
        let literal = kind == "literal"
        return ["id": id.uuidString, "originalText": string(literal ? "" : original), "replacementText": string(literal ? "" : replacement),
                "dateAdded": date.timeIntervalSince1970, "isEnabled": enabled, "matchingKindRawValue": string(kind),
                "approvalOriginRawValue": optionalString(source == nil ? nil : "historyManual"), "sourceTranscriptionID": optionalUUID(source),
                "sourceVariantRawValue": optionalString(variant), "literalOriginalText": optionalString(literal ? original : nil),
                "literalReplacementText": optionalString(literal ? replacement : nil)]
    }

    private static func expectedCanonicalRows(generated: GeneratedIdentity) -> [[String: Any]] {
        [
            expectedCanonical(id: manualID, date: manualDate, enabled: true, original: manualOriginal, replacement: manualReplacement),
            expectedCanonical(id: disabledID, date: disabledDate, enabled: false, original: disabledOriginal, replacement: disabledReplacement),
            expectedCanonical(id: generated.id, date: generated.dateAdded, enabled: true, original: historyOriginal, replacement: historyReplacement, source: sourceID, variant: "recognition")
        ].sorted { ($0["id"] as! String) < ($1["id"] as! String) }
    }

    private static func expectedCanonical(id: UUID, date: Date, enabled: Bool, original: String, replacement: String, source: UUID? = nil, variant: String? = nil) -> [String: Any] {
        ["id": id.uuidString, "originalText": string(original), "replacementText": string(replacement), "dateAdded": date.timeIntervalSince1970,
         "isEnabled": enabled, "matchingKind": string("literal"), "approvalOrigin": optionalString(source == nil ? nil : "historyManual"),
         "sourceTranscriptionID": optionalUUID(source), "sourceVariant": optionalString(variant)]
    }
    #endif
}
