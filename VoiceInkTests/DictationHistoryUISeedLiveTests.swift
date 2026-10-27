import CryptoKit
import Foundation
import os
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @available(macOS 15, *)
    @Test(.enabled(if: DictationHistoryUISeedInputs.isEnabled), .timeLimit(.minutes(2)))
    @MainActor func liveDictationHistoryUISeed() async throws {
        let inputs = try DictationHistoryUISeedInputs()
        var observation = inputs.observation
        try inputs.write(observation, named: "observation.json")
        do {
            try await inputs.requireStartupStoreObservation()
            try await inputs.requireStatsMigrationQuiescence()
            let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
            let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "HistoryUISeed")
            let container = try #require(VoiceInkApp.createPersistentContainer(schema: schema, logger: logger),
                                         "The actual normal-store factory must succeed without in-memory fallback.")
            let fixture = try DictationHistoryUISeedFixture(inputs: inputs, container: container)
            try fixture.run()
            observation["classification"] = "passed"
            observation["explicitSaveCompleted"] = inputs.phase == .seed
            observation["verificationReadOnly"] = inputs.phase == .verify
            observation["scope"] = "Synthetic row creation and normal-store History rendering input; no ASR, provider, migration or editor-delivery proof."
            try inputs.write(observation, named: "observation.json")
        } catch {
            observation["classification"] = "failed"
            observation["failure"] = String(describing: error)
            try inputs.write(observation, named: "observation.json")
            throw error
        }
    }
}

private struct DictationHistoryUISeedInputs {
    enum Phase: String {
        case seed
        case verify
    }

    static var isEnabled: Bool {
        value("RJT_HISTORY_UI_SEED_CHECKS") == "1" && value("GITHUB_ACTIONS") == "true"
    }

    let sourceSHA: String
    let phase: Phase
    let executablePath: String
    let evidence: URL
    let seedEvidence: URL?
    let support = VoiceInkMacOSStorageDirectories.appSupportDirectory.standardizedFileURL
    let hostPID = ProcessInfo.processInfo.processIdentifier

    init() throws {
        #if !LOCAL_BUILD
        throw DictationHistoryUISeedError.localBuildRequired
        #endif
        try #require(Self.isEnabled && Self.value("RUNNER_ENVIRONMENT") == "github-hosted",
                     "History seeding requires the explicitly enabled disposable GitHub-hosted Mac.")
        let phaseValue = try #require(Self.value("RJT_HISTORY_UI_PHASE"))
        phase = try #require(Phase(rawValue: phaseValue))
        sourceSHA = try #require(Self.value("RJT_HISTORY_UI_SOURCE_SHA"))
        try #require(sourceSHA.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil)
        let executable = try #require(Bundle.main.executableURL).standardizedFileURL
        executablePath = executable.path
        try #require(executablePath == Self.value("RJT_HISTORY_UI_EXPECTED_EXE"))
        try #require(Bundle.main.bundleIdentifier == "com.negentropi.RomaJustTalk")
        let evidencePath = try #require(Self.value("RJT_HISTORY_UI_EVIDENCE"))
        let runnerTemporaryPath = try #require(Self.value("RUNNER_TEMP"))
        try #require(evidencePath.hasPrefix("/") && runnerTemporaryPath.hasPrefix("/"))
        evidence = URL(fileURLWithPath: evidencePath, isDirectory: true).standardizedFileURL
        let runnerTemporary = URL(fileURLWithPath: runnerTemporaryPath, isDirectory: true).standardizedFileURL
        try #require(evidence.path.hasPrefix(runnerTemporary.path + "/") && evidence != runnerTemporary)
        try #require(evidence.resolvingSymlinksInPath() == evidence && support.resolvingSymlinksInPath() == support)
        try #require(!evidence.path.hasPrefix(support.path + "/") && evidence != support)
        try #require(evidence.lastPathComponent == phase.rawValue)
        if phase == .verify {
            let seedPath = try #require(Self.value("RJT_HISTORY_UI_SEED_EVIDENCE"))
            try #require(seedPath.hasPrefix("/"))
            let seed = URL(fileURLWithPath: seedPath, isDirectory: true).standardizedFileURL
            try #require(seed.path.hasPrefix(runnerTemporary.path + "/") && seed.lastPathComponent == "seed")
            try #require(seed != evidence && !seed.path.hasPrefix(evidence.path + "/") && !evidence.path.hasPrefix(seed.path + "/"))
            try #require(seed.resolvingSymlinksInPath() == seed)
            for name in ["expected-rows.json", "expected-libraries.json"] {
                let url = seed.appendingPathComponent(name)
                let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                try #require(attributes.isRegularFile == true && attributes.isSymbolicLink != true)
            }
            seedEvidence = seed
        } else {
            seedEvidence = nil
        }
        for directory in [evidence, support] {
            let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            try #require(attributes.isDirectory == true && attributes.isSymbolicLink != true)
        }
        for url in storePaths {
            let attributes = try URL(fileURLWithPath: url).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            try #require(attributes.isRegularFile == true && attributes.isSymbolicLink != true,
                         "Normal app startup must create all three persistent stores before this test seeds.")
        }
    }

    var storePaths: [String] {
        ["default.store", "dictionary.store", "stats.store"].map { support.appendingPathComponent($0).path }
    }

    var observation: [String: Any] {
        ["version": 1, "testName": "liveDictationHistoryUISeed", "classification": "started", "phase": phase.rawValue,
         "sourceSHA": sourceSHA, "hostPID": hostPID, "executablePath": executablePath,
         "bundleIdentifier": Bundle.main.bundleIdentifier ?? "", "appSupportDirectory": support.path,
         "storePaths": storePaths, "sourcePath": #filePath]
    }

    func requireStartupStoreObservation() async throws {
        let receiptURL = evidence.appendingPathComponent("host-observed.json")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while !FileManager.default.fileExists(atPath: receiptURL.path) && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let receipt = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any])
        try #require(receipt["hostPID"] as? Int == Int(hostPID) && receipt["executablePath"] as? String == executablePath)
        let observed = try #require(receipt["openedStorePaths"] as? [String])
        try #require(Set(observed) == Set(storePaths), "The observed app host must already have the normal three stores open.")
    }

    @MainActor func requireStatsMigrationQuiescence() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while (SessionMetricMigrationService.shared.isRunning || !VoiceInkSessionMetricMigrationPreference.isCompleted()),
              clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(!SessionMetricMigrationService.shared.isRunning && VoiceInkSessionMetricMigrationPreference.isCompleted(),
                     "Normal startup stats migration must finish before fresh-store counts and synthetic insertion.")
    }

    func write(_ value: Any, named name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: evidence.appendingPathComponent(name), options: .atomic)
        Attachment.record(data, named: name)
    }

    static func value(_ key: String) -> String? {
        let values = ProcessInfo.processInfo.environment
        return values[key] ?? values["TEST_RUNNER_" + key]
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum DictationHistoryUISeedError: Error {
    case localBuildRequired
}

@available(macOS 15, *)
@MainActor
private struct DictationHistoryUISeedFixture {
    private struct StoreGroup {
        let name: String
        let fileName: String
        let types: [any PersistentModel.Type]
    }

    private static let groups = [
        StoreGroup(name: "default", fileName: "default.store", types: [Transcription.self]),
        StoreGroup(name: "dictionary", fileName: "dictionary.store", types: [VocabularyWord.self, WordReplacement.self]),
        StoreGroup(name: "stats", fileName: "stats.store", types: [SessionMetric.self])
    ]
    let inputs: DictationHistoryUISeedInputs
    let container: ModelContainer
    let context: ModelContext
    private let seedTimestamp = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 4)

    init(inputs: DictationHistoryUISeedInputs, container: ModelContainer) throws {
        self.inputs = inputs
        self.container = container
        try #require(Self.groups.flatMap { $0.types }.map { String(reflecting: $0) }
                     == ["VoiceInk.Transcription", "VoiceInk.VocabularyWord", "VoiceInk.WordReplacement", "VoiceInk.SessionMetric"])
        try #require(container.migrationPlan == nil && container.configurations.count == 3)
        for group in Self.groups {
            let config = try #require(container.configurations.first { $0.name == group.name })
            try #require(config.url.standardizedFileURL == inputs.support.appendingPathComponent(group.fileName))
            try #require(!config.isStoredInMemoryOnly && config.allowsSave)
            try #require(config.groupAppContainerIdentifier == nil && config.cloudKitContainerIdentifier == nil)
            try #require(config.schema?.entities.map(\.name).sorted() == Schema(group.types).entities.map(\.name).sorted())
        }
        try #require(container.schema.entities.map(\.name).sorted()
                     == Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self]).entities.map(\.name).sorted())
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func run() throws {
        if inputs.phase == .seed {
            try #require(context.fetchCount(FetchDescriptor<Transcription>()) == 0,
                     "Refuse to seed a normal History store containing any existing record.")
            try #require(context.fetchCount(FetchDescriptor<VocabularyWord>()) == 0)
            try #require(context.fetchCount(FetchDescriptor<WordReplacement>()) == 0)
            try #require(context.fetchCount(FetchDescriptor<SessionMetric>()) == 0)
            let old = Transcription(text: "RJT History legacy\r\nCafe\u{301} 👩🏽‍💻\r\n", duration: 4,
                                    enhancedText: "RJT legacy enhanced — 42", transcriptionModelName: "RJT UI seed recognizer",
                                    transcriptionStatus: .completed)
            let result = VoiceInkAIEnhancementResult(text: "RJT Clarity polished — Café 👩🏽‍💻 42\r\n", duration: 0.25,
                                                    modelName: "RJT UI seed polisher", promptName: "RJT UI seed Clarity",
                                                    requestSystemMessage: nil, requestUserMessage: nil)
            let successDraft = VoiceInkCompletedTranscriptionDraft(
                cleanedText: "RJT History recognized\r\nCafé 👩🏽‍💻\u{00A0}42\r\n", duration: 4,
                audioFileURL: nil, transcriptionModelName: "RJT UI seed recognizer", transcriptionDuration: nil,
                enhancementResult: result, recognitionText: "RJT History recognized\r\nCafe\u{301} 👩🏽‍💻\u{00A0}42\r\n",
                dictationProfile: .clarity, clarityStyle: .formal)
            let success = Transcription(completedDraft: successDraft)
            let fallback = Transcription(text: "Replaced by the completed draft", duration: 0)
            fallback.applyCompletedDraft(VoiceInkCompletedTranscriptionDraft(
                cleanedText: "RJT History fallback\r\nCafe\u{301} 👩🏽‍💻\r\n", duration: 4,
                audioFileURL: nil, transcriptionModelName: "RJT UI seed recognizer", transcriptionDuration: nil,
                recognitionText: "RJT History fallback\r\nCafe\u{301} 👩🏽‍💻\r\n", dictationProfile: .clarity,
                clarityStyle: .casual, processingFailureReason: "RJT fixture provider unavailable — raw text kept"))
            let unknown = Transcription(text: "RJT History unknown\r\nCafe\u{301} 👩🏽‍💻\r\n", duration: 4,
                                        transcriptionModelName: "RJT UI seed recognizer", transcriptionStatus: .completed)
            unknown.dictationProfileRawValue = "future-profile-v99"
            unknown.clarityStyleRawValue = "future-style-v99"
            let rows = [old, success, fallback, unknown]
            for (index, row) in rows.enumerated() {
                row.id = Self.identifiers[index]
                row.timestamp = timestamps[index]
                context.insert(row)
            }
            context.insert(VocabularyWord(word: "RJT UI vocabulary Cafe\u{301}", dateAdded: seedTimestamp))
            let replacement = WordReplacement(originalText: "RJT UI library source",
                                              replacementText: "RJT UI library target Café 👩🏽‍💻\r\n",
                                              dateAdded: seedTimestamp)
            replacement.id = Self.replacementID
            context.insert(replacement)
            try context.save()
            try #require(!context.hasChanges)
        }
        let readContext = ModelContext(container)
        readContext.autosaveEnabled = false
        let reopened = try readContext.fetch(FetchDescriptor<Transcription>()).sorted { $0.id.uuidString < $1.id.uuidString }
        try #require(reopened.count == 4)
        let snapshots = reopened.map(Self.snapshot)
        try inputs.write(snapshots, named: "rows.json")
        let expectedRows: Any
        let expectedLibraries: Any
        if let seedEvidence = inputs.seedEvidence {
            expectedRows = try JSONSerialization.jsonObject(with: Data(contentsOf: seedEvidence.appendingPathComponent("expected-rows.json")))
            expectedLibraries = try JSONSerialization.jsonObject(with: Data(contentsOf: seedEvidence.appendingPathComponent("expected-libraries.json")))
        } else {
            expectedRows = self.expectedRows
            expectedLibraries = self.expectedLibraries
        }
        try inputs.write(expectedRows, named: "expected-rows.json")
        let actualBytes = try JSONSerialization.data(withJSONObject: snapshots, options: [.sortedKeys])
        let expectedBytes = try JSONSerialization.data(withJSONObject: expectedRows, options: [.sortedKeys])
        try #require(actualBytes == expectedBytes, "All twenty persisted fields and exact UTF-8/UTF-16 units must match the independent fixture.")
        let capturedUnknown = try #require(reopened.first { $0.id == Self.identifiers[3] })
        try #require(capturedUnknown.dictationProfile == nil && capturedUnknown.clarityStyle == nil)
        let capturedSuccess = try #require(reopened.first { $0.id == Self.identifiers[1] })
        let recognition = try #require(capturedSuccess.recognitionText)
        try #require(recognition == capturedSuccess.text && !recognition.utf8.elementsEqual(capturedSuccess.text.utf8),
                     "The recognized and processed fixture strings must compare equal canonically but differ in bytes.")
        let vocabulary = try readContext.fetch(FetchDescriptor<VocabularyWord>())
        let replacements = try readContext.fetch(FetchDescriptor<WordReplacement>())
        try #require(vocabulary.count == 1 && replacements.count == 1)
        let libraries: [String: Any] = [
            "VocabularyWord": vocabulary.map { ["word": Self.string($0.word), "dateAdded": $0.dateAdded.timeIntervalSince1970] },
            "WordReplacement": replacements.map {
                ["id": $0.id.uuidString, "originalText": Self.string($0.originalText),
                 "replacementText": Self.string($0.replacementText), "dateAdded": $0.dateAdded.timeIntervalSince1970,
                 "isEnabled": $0.isEnabled]
            }
        ]
        try inputs.write(libraries, named: "libraries.json")
        try inputs.write(expectedLibraries, named: "expected-libraries.json")
        let libraryBytes = try JSONSerialization.data(withJSONObject: libraries, options: [.sortedKeys])
        let expectedLibraryBytes = try JSONSerialization.data(withJSONObject: expectedLibraries, options: [.sortedKeys])
        try #require(libraryBytes == expectedLibraryBytes, "All library sentinel fields and code units must survive the persistent save.")
        try #require(readContext.fetchCount(FetchDescriptor<SessionMetric>()) == 0)
        try #require(!readContext.hasChanges)
        try #require(!context.hasChanges)
        try writeProvenance(expectedRows: expectedRows)
    }

    private func writeProvenance(expectedRows: Any) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let rawSchema = try encoder.encode(container.schema)
        try rawSchema.write(to: inputs.evidence.appendingPathComponent("schema-raw.json"), options: .atomic)
        Attachment.record(rawSchema, named: "schema-raw.json")
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("VoiceInk/VoiceInk.swift")
        let source = try Data(contentsOf: sourceURL)
        let appSource = try #require(String(data: source, encoding: .utf8))
        let start = "static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {"
        let end = "    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {"
        try #require(appSource.components(separatedBy: start).count == 2 && appSource.components(separatedBy: end).count == 2)
        let factoryStart = try #require(appSource.range(of: start))
        let factoryEnd = try #require(appSource.range(of: end))
        let factory = Data(appSource[factoryStart.lowerBound..<factoryEnd.lowerBound].utf8)
        let groups: [[String: Any]] = container.configurations.sorted { $0.name < $1.name }.map { config in
            ["name": config.name, "url": config.url.standardizedFileURL.path,
             "entities": config.schema?.entities.map(\.name).sorted() ?? [], "isStoredInMemoryOnly": config.isStoredInMemoryOnly,
             "cloudKitContainerIdentifier": config.cloudKitContainerIdentifier.map { $0 as Any } ?? NSNull(),
             "groupAppContainerIdentifier": config.groupAppContainerIdentifier.map { $0 as Any } ?? NSNull()]
        }
        let firstExpected = try #require((expectedRows as? [[String: Any]])?.first)
        let firstTimestamp = try #require(firstExpected["timestamp"] as? Double)
        try inputs.write(["version": 1, "sourceSHA": inputs.sourceSHA, "hostPID": inputs.hostPID, "phase": inputs.phase.rawValue,
                          "executablePath": inputs.executablePath, "normalSupportDirectory": inputs.support.path,
                          "factory": "VoiceInkApp.createPersistentContainer(schema:logger:)",
                          "factorySourcePath": sourceURL.path, "factorySourceSHA256": DictationHistoryUISeedInputs.sha256(source),
                          "factoryBodySHA256": DictationHistoryUISeedInputs.sha256(factory),
                          "schemaSHA256": DictationHistoryUISeedInputs.sha256(rawSchema), "configurations": groups,
                          "modelTypes": Self.groups.flatMap { $0.types }.map { String(reflecting: $0) },
                          "freshCounts": inputs.phase == .seed ? ["Transcription": 0, "VocabularyWord": 0, "WordReplacement": 0, "SessionMetric": 0] as Any : NSNull(),
                          "savedCounts": ["Transcription": 4, "VocabularyWord": 1, "WordReplacement": 1, "SessionMetric": 0],
                          "seedTimestamp": firstTimestamp - 1,
                          "transcriptionTimestampOffsetsSeconds": [1, 2, 3, 4],
                          "startupStatsMigrationCompleted": VoiceInkSessionMetricMigrationPreference.isCompleted(),
                          "startupStatsMigrationRunning": SessionMetricMigrationService.shared.isRunning,
                          "explicitSaveCompleted": inputs.phase == .seed, "verificationReadOnly": inputs.phase == .verify,
                          "verificationContextHasChanges": false], named: "store-provenance.json")
    }

    private static let identifiers = (1...4).map {
        UUID(uuidString: String(format: "A1000000-0000-4000-8000-%012d", $0))!
    }
    private static let replacementID = UUID(uuidString: "A2000000-0000-4000-8000-000000000001")!
    private var timestamps: [Date] { (1...4).map { seedTimestamp.addingTimeInterval(Double($0)) } }

    private var expectedLibraries: [String: Any] {
        ["VocabularyWord": [["word": Self.string("RJT UI vocabulary Cafe\u{301}"), "dateAdded": seedTimestamp.timeIntervalSince1970]],
         "WordReplacement": [["id": Self.replacementID.uuidString, "originalText": Self.string("RJT UI library source"),
                              "replacementText": Self.string("RJT UI library target Café 👩🏽‍💻\r\n"),
                              "dateAdded": seedTimestamp.timeIntervalSince1970, "isEnabled": true]]]
    }

    private static func string(_ value: String?) -> Any {
        guard let value else { return NSNull() }
        return ["value": value, "utf8": Array(value.utf8), "utf16": Array(value.utf16)]
    }

    private static func snapshot(_ row: Transcription) -> [String: Any] {
        ["id": row.id.uuidString, "text": string(row.text), "enhancedText": string(row.enhancedText),
         "timestamp": row.timestamp.timeIntervalSince1970, "duration": row.duration,
         "audioFileURL": string(row.audioFileURL), "transcriptionModelName": string(row.transcriptionModelName),
         "aiEnhancementModelName": string(row.aiEnhancementModelName), "promptName": string(row.promptName),
         "transcriptionDuration": row.transcriptionDuration.map { $0 as Any } ?? NSNull(),
         "enhancementDuration": row.enhancementDuration.map { $0 as Any } ?? NSNull(),
         "aiRequestSystemMessage": string(row.aiRequestSystemMessage), "aiRequestUserMessage": string(row.aiRequestUserMessage),
         "powerModeName": string(row.powerModeName), "powerModeEmoji": string(row.powerModeEmoji),
         "transcriptionStatus": string(row.transcriptionStatus), "recognitionText": string(row.recognitionText),
         "dictationProfileRawValue": string(row.dictationProfileRawValue), "clarityStyleRawValue": string(row.clarityStyleRawValue),
         "processingFailureReason": string(row.processingFailureReason)]
    }

    private var expectedRows: [[String: Any]] {
        let texts = ["RJT History legacy\r\nCafe\u{301} 👩🏽‍💻\r\n",
                     "RJT History recognized\r\nCafé 👩🏽‍💻\u{00A0}42\r\n",
                     "RJT History fallback\r\nCafe\u{301} 👩🏽‍💻\r\n",
                     "RJT History unknown\r\nCafe\u{301} 👩🏽‍💻\r\n"]
        let enhanced: [String?] = ["RJT legacy enhanced — 42", "RJT Clarity polished — Café 👩🏽‍💻 42\r\n", nil, nil]
        let recognized: [String?] = [nil, "RJT History recognized\r\nCafe\u{301} 👩🏽‍💻\u{00A0}42\r\n",
                                    "RJT History fallback\r\nCafe\u{301} 👩🏽‍💻\r\n", nil]
        let profiles: [String?] = [nil, "clarity", "clarity", "future-profile-v99"]
        let styles: [String?] = [nil, "formal", "casual", "future-style-v99"]
        return (0..<4).map { index in
            ["id": Self.identifiers[index].uuidString, "text": Self.string(texts[index]), "enhancedText": Self.string(enhanced[index]),
             "timestamp": timestamps[index].timeIntervalSince1970, "duration": 4.0,
             "audioFileURL": NSNull(), "transcriptionModelName": Self.string("RJT UI seed recognizer"),
             "aiEnhancementModelName": index == 1 ? Self.string("RJT UI seed polisher") : NSNull(),
             "promptName": index == 1 ? Self.string("RJT UI seed Clarity") : NSNull(), "transcriptionDuration": NSNull(),
             "enhancementDuration": index == 1 ? 0.25 as Any : NSNull(), "aiRequestSystemMessage": NSNull(),
             "aiRequestUserMessage": NSNull(), "powerModeName": NSNull(), "powerModeEmoji": NSNull(),
             "transcriptionStatus": Self.string("completed"), "recognitionText": Self.string(recognized[index]),
             "dictationProfileRawValue": Self.string(profiles[index]), "clarityStyleRawValue": Self.string(styles[index]),
             "processingFailureReason": index == 2 ? Self.string("RJT fixture provider unavailable — raw text kept") : NSNull()]
        }
    }
}
