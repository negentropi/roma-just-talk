import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @available(macOS 15, *)
    @Test(.enabled(if: DictationMetadataStoreCheck.isEnabled), .timeLimit(.minutes(2)))
    @MainActor func liveDictationMetadataPersistentStoreUpgrade() async throws {
        let inputs = try DictationStoreSeedInputs()
        var observation = inputs.observation
        observation["testName"] = "liveDictationMetadataPersistentStoreUpgrade"
        observation["sourcePath"] = #filePath
        try inputs.write(observation, named: "observation.json")
        print("RJT metadata store started phase=\(inputs.phase.rawValue) hostPID=\(inputs.hostPID) sourceSHA=\(inputs.sourceSHA)")
        do {
            try await inputs.waitForHostObservation()
            try DictationMetadataStoreCheck.run(inputs: inputs)
            observation["classification"] = "passed"
            observation["scope"] = "Actual VoiceInk metadata scalar persistence in the closed predecessor-store clone; no profile activation, provider, audio, CloudKit or UI proof."
            try inputs.write(observation, named: "observation.json")
            print("RJT metadata store passed phase=\(inputs.phase.rawValue) hostPID=\(inputs.hostPID)")
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
private enum DictationMetadataStoreCheck {
    nonisolated static var isEnabled: Bool {
        DictationStoreSeedInputs.value("RJT_DICTATION_METADATA_STORE_CHECKS") == "1"
            && DictationStoreSeedInputs.value("GITHUB_ACTIONS") == "true"
    }

    private static let constructorID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    private static let appliedID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    private static let unknownID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
    private static let additionalIDs: Set<UUID> = [constructorID, appliedID, unknownID]
    private static let constructorDate = Date(timeIntervalSince1970: 1_700_000_100.125)
    private static let appliedDate = Date(timeIntervalSince1970: 1_700_000_101.25)
    private static let unknownDate = Date(timeIntervalSince1970: 1_700_000_102.5)
    private static let noneRecognition = " Cafe\u{301} 🧪 \"recognition\"\r\nSecond line\n"
    private static let customRecognition = "Um, Cafe\u{301} 🧪 \"recognizer\"\r\nSecond line\n"
    private static let preparedText = "Prepared Cafe\u{301} 🧪.\r\nKeep \"quoted\".\n"
    private static let enhancedText = "Polished Cafe\u{301} 🧪.\r\nLiteral <tag>."
    private static let failureRecognition = "Future Cafe\u{301} 🧪 \"verbatim\"\r\nPreserve this.\n"
    private static let failureReason = "Processing failed: \"fixture\"\r\nCafe\u{301} 🧪"

    static func run(inputs: DictationStoreSeedInputs) throws {
        try #require(inputs.phase == .metadataWrite || inputs.phase == .metadataReopen)
        let fixture = try DictationStoreSeedFixture(inputs: inputs)
        if inputs.phase == .metadataWrite {
            try fixture.run()
            let historical = try fixture.context.fetch(FetchDescriptor<Transcription>())
            try verifyHistoricalMetadata(historical)
            try verifyCanceledDraftClearsMetadata()
            try insertRows(into: fixture.context)
            try fixture.context.save()
        }

        try fixture.run(allowedAdditionalTranscriptionIDs: additionalIDs)
        let allRows = try fixture.context.fetch(FetchDescriptor<Transcription>())
        let historical = allRows.filter { !additionalIDs.contains($0.id) }
        try verifyHistoricalMetadata(historical)
        let newRows = allRows.filter { additionalIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
        try #require(newRows.count == 3 && Set(newRows.map(\.id)) == additionalIDs)
        let historicalStore = try #require(historical.first?.persistentModelID.storeIdentifier)
        try #require(newRows.allSatisfy { $0.persistentModelID.storeIdentifier == historicalStore },
                     "New transcription rows must use the same actual default store as the preserved historical rows.")
        let snapshots = newRows.map(snapshot)
        try inputs.write(snapshots, named: "metadata-records.json")
        try inputs.write(expectedRows, named: "expected-metadata-records.json")
        let actualBytes = try JSONSerialization.data(withJSONObject: snapshots, options: [.sortedKeys])
        let expectedBytes = try JSONSerialization.data(withJSONObject: expectedRows, options: [.sortedKeys])
        try #require(actualBytes == expectedBytes, "All 20 persisted fields on every new metadata record must survive exactly.")
        let constructor = try #require(newRows.first { $0.id == constructorID })
        let applied = try #require(newRows.first { $0.id == appliedID })
        let unknown = try #require(newRows.first { $0.id == unknownID })
        try #require(constructor.dictationProfile == VoiceInkDictationProfile.none && constructor.clarityStyle == nil)
        try #require(applied.dictationProfile == .custom && applied.clarityStyle == .formal)
        try #require(unknown.dictationProfile == nil && unknown.clarityStyle == nil,
                     "Unknown captured values must stay unknown; current preference defaults do not relabel stored metadata.")
        let identifiers = try newRows.map { row in
            var identifier = try DictationStoreSeedFixture.persistentIdentity(row)
            identifier["recordID"] = row.id.uuidString
            return identifier
        }
        try inputs.write(identifiers, named: "metadata-identifiers.json")
        try #require(!fixture.context.hasChanges, "Reopen verification must not change either historical or new rows.")
        try inputs.write([
            "version": 1, "phase": inputs.phase.rawValue, "hostPID": inputs.hostPID,
            "historicalRowCount": historical.count, "additionalRecordCount": newRows.count,
            "historicalMetadataNil": true, "exactNewFieldValues": true,
            "explicitSavePerformed": inputs.phase == .metadataWrite,
            "readNilBeforeWrite": inputs.phase == .metadataWrite,
            "canceledDraftMetadataCleared": inputs.phase == .metadataWrite,
            "unknownRawValuesPreservedWithoutRelabeling": true,
            "scope": "Scalar and draft-adapter persistence fixture; values do not activate dictation profiles."
        ], named: "metadata-observation.json")
    }

    private static func verifyHistoricalMetadata(_ rows: [Transcription]) throws {
        try #require(rows.count == 2)
        for row in rows {
            try #require(row.recognitionText == nil && row.dictationProfileRawValue == nil
                         && row.clarityStyleRawValue == nil && row.processingFailureReason == nil,
                         "Old records must not acquire invented recognition or profile metadata.")
            try #require(row.dictationProfile == nil && row.clarityStyle == nil)
        }
    }

    private static func insertRows(into context: ModelContext) throws {
        let constructor = Transcription(completedDraft: VoiceInkCompletedTranscriptionDraft(
            cleanedText: noneRecognition, duration: 4.5,
            audioFileURL: "https://example.com/rjt-metadata-none.wav",
            transcriptionModelName: "fixture-recognizer-none", transcriptionDuration: 0.5,
            recognitionText: noneRecognition, dictationProfile: VoiceInkDictationProfile.none
        ))
        constructor.id = constructorID
        constructor.timestamp = constructorDate
        context.insert(constructor)

        let applied = Transcription(text: "pending", duration: 0)
        applied.id = appliedID
        applied.timestamp = appliedDate
        applied.applyCompletedDraft(successfulDraft())
        context.insert(applied)

        let unknown = Transcription(completedDraft: VoiceInkCompletedTranscriptionDraft(
            cleanedText: failureRecognition, duration: 2.75, audioFileURL: nil,
            transcriptionModelName: "fixture-future-recognizer", transcriptionDuration: 0.25,
            recognitionText: failureRecognition, dictationProfile: .custom, clarityStyle: .formal,
            processingFailureReason: failureReason
        ))
        unknown.id = unknownID
        unknown.timestamp = unknownDate
        try #require(unknown.dictationProfile == .custom && unknown.clarityStyle == .formal)
        unknown.dictationProfileRawValue = "future-profile"
        unknown.clarityStyleRawValue = "future-style"
        context.insert(unknown)
    }

    private static func successfulDraft(processingFailureReason: String? = nil) -> VoiceInkCompletedTranscriptionDraft {
        VoiceInkCompletedTranscriptionDraft(
            cleanedText: preparedText, duration: 7.25,
            audioFileURL: "https://example.com/rjt-metadata-custom.wav",
            transcriptionModelName: "fixture-recognizer-custom", transcriptionDuration: 1.125,
            powerModeName: "Fixture capture", powerModeEmoji: "🧪",
            enhancementResult: VoiceInkAIEnhancementResult(
                text: enhancedText, duration: 0.375, modelName: "fixture-polisher", promptName: "Fixture cleanup",
                requestSystemMessage: "Fixed system\r\n🧪", requestUserMessage: "User \"Cafe\u{301}\"\r\nSecond line"
            ),
            recognitionText: customRecognition, dictationProfile: .custom, clarityStyle: .formal,
            processingFailureReason: processingFailureReason
        )
    }

    private static func verifyCanceledDraftClearsMetadata() throws {
        let canceled = Transcription(text: "pending", duration: 0)
        canceled.applyCompletedDraft(successfulDraft(processingFailureReason: failureReason))
        let capturedReason = try #require(canceled.processingFailureReason)
        try #require(Array(capturedReason.utf8) == Array(failureReason.utf8)
                     && Array(capturedReason.utf16) == Array(failureReason.utf16))
        try #require(canceled.recognitionText != nil && canceled.dictationProfile == .custom
                     && canceled.clarityStyle == .formal && canceled.enhancedText != nil
                     && canceled.aiEnhancementModelName != nil && canceled.promptName != nil
                     && canceled.aiRequestSystemMessage != nil && canceled.aiRequestUserMessage != nil)
        canceled.markAsCanceledTranscription()
        try #require(canceled.transcriptionState == .canceled)
        try #require(canceled.recognitionText == nil && canceled.dictationProfileRawValue == nil
                     && canceled.clarityStyleRawValue == nil && canceled.processingFailureReason == nil)
        try #require(canceled.enhancedText == nil && canceled.aiEnhancementModelName == nil
                     && canceled.promptName == nil && canceled.transcriptionDuration == nil
                     && canceled.enhancementDuration == nil && canceled.aiRequestSystemMessage == nil
                     && canceled.aiRequestUserMessage == nil)
    }

    private static func snapshot(_ row: Transcription) -> [String: Any] {
        var value = DictationStoreSeedFixture.transcriptionSnapshot(row)
        value["recognitionText"] = DictationStoreSeedFixture.optionalString(row.recognitionText)
        value["dictationProfileRawValue"] = DictationStoreSeedFixture.optionalString(row.dictationProfileRawValue)
        value["clarityStyleRawValue"] = DictationStoreSeedFixture.optionalString(row.clarityStyleRawValue)
        value["processingFailureReason"] = DictationStoreSeedFixture.optionalString(row.processingFailureReason)
        return value
    }

    private static var expectedRows: [[String: Any]] {
        [
            ["id": constructorID.uuidString, "text": DictationStoreSeedFixture.string(noneRecognition), "enhancedText": NSNull(),
             "timestamp": constructorDate.timeIntervalSince1970, "duration": 4.5,
             "audioFileURL": DictationStoreSeedFixture.string("https://example.com/rjt-metadata-none.wav"),
             "transcriptionModelName": DictationStoreSeedFixture.string("fixture-recognizer-none"),
             "aiEnhancementModelName": NSNull(), "promptName": NSNull(), "transcriptionDuration": 0.5,
             "enhancementDuration": NSNull(), "aiRequestSystemMessage": NSNull(), "aiRequestUserMessage": NSNull(),
             "powerModeName": NSNull(), "powerModeEmoji": NSNull(), "transcriptionStatus": DictationStoreSeedFixture.string("completed"),
             "recognitionText": DictationStoreSeedFixture.string(noneRecognition),
             "dictationProfileRawValue": DictationStoreSeedFixture.string("none"),
             "clarityStyleRawValue": NSNull(), "processingFailureReason": NSNull()],
            ["id": appliedID.uuidString, "text": DictationStoreSeedFixture.string(preparedText),
             "enhancedText": DictationStoreSeedFixture.string(enhancedText), "timestamp": appliedDate.timeIntervalSince1970,
             "duration": 7.25, "audioFileURL": DictationStoreSeedFixture.string("https://example.com/rjt-metadata-custom.wav"),
             "transcriptionModelName": DictationStoreSeedFixture.string("fixture-recognizer-custom"),
             "aiEnhancementModelName": DictationStoreSeedFixture.string("fixture-polisher"),
             "promptName": DictationStoreSeedFixture.string("Fixture cleanup"), "transcriptionDuration": 1.125,
             "enhancementDuration": 0.375, "aiRequestSystemMessage": DictationStoreSeedFixture.string("Fixed system\r\n🧪"),
             "aiRequestUserMessage": DictationStoreSeedFixture.string("User \"Cafe\u{301}\"\r\nSecond line"),
             "powerModeName": DictationStoreSeedFixture.string("Fixture capture"), "powerModeEmoji": DictationStoreSeedFixture.string("🧪"),
             "transcriptionStatus": DictationStoreSeedFixture.string("completed"),
             "recognitionText": DictationStoreSeedFixture.string(customRecognition),
             "dictationProfileRawValue": DictationStoreSeedFixture.string("custom"),
             "clarityStyleRawValue": DictationStoreSeedFixture.string("formal"), "processingFailureReason": NSNull()],
            ["id": unknownID.uuidString, "text": DictationStoreSeedFixture.string(failureRecognition), "enhancedText": NSNull(),
             "timestamp": unknownDate.timeIntervalSince1970, "duration": 2.75, "audioFileURL": NSNull(),
             "transcriptionModelName": DictationStoreSeedFixture.string("fixture-future-recognizer"),
             "aiEnhancementModelName": NSNull(), "promptName": NSNull(), "transcriptionDuration": 0.25,
             "enhancementDuration": NSNull(), "aiRequestSystemMessage": NSNull(), "aiRequestUserMessage": NSNull(),
             "powerModeName": NSNull(), "powerModeEmoji": NSNull(), "transcriptionStatus": DictationStoreSeedFixture.string("completed"),
             "recognitionText": DictationStoreSeedFixture.string(failureRecognition),
             "dictationProfileRawValue": DictationStoreSeedFixture.string("future-profile"),
             "clarityStyleRawValue": DictationStoreSeedFixture.string("future-style"),
             "processingFailureReason": DictationStoreSeedFixture.string(failureReason)]
        ]
    }
}
