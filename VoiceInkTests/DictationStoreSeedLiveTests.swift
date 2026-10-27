import CryptoKit
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @available(macOS 15, *)
    @Test(.enabled(if: DictationStoreSeedInputs.isEnabled), .timeLimit(.minutes(2)))
    @MainActor func liveDictationPersistentStoreSeedControl() async throws {
        let inputs = try DictationStoreSeedInputs()
        var observation = inputs.observation
        try inputs.write(observation, named: "observation.json")
        print("RJT store control started phase=\(inputs.phase.rawValue) hostPID=\(inputs.hostPID) sourceSHA=\(inputs.sourceSHA) fixture=\(inputs.fixture.path)")
        do {
            try await inputs.waitForHostObservation()
            let fixture = try DictationStoreSeedFixture(inputs: inputs)
            try fixture.run()
            observation["classification"] = "passed"
            observation["scope"] = "Actual VoiceInk model classes, unchanged-schema local persistent-store seed/control; no new metadata or migration proof."
            try inputs.write(observation, named: "observation.json")
            print("RJT store control passed phase=\(inputs.phase.rawValue) hostPID=\(inputs.hostPID)")
        } catch {
            observation["classification"] = "failed"
            observation["failure"] = String(describing: error)
            try inputs.write(observation, named: "observation.json")
            throw error
        }
    }
}

struct DictationStoreSeedInputs {
    enum Phase: String {
        case seed
        case oldReopen = "old-reopen"
        case currentRead = "current-read"
        case metadataWrite = "metadata-write"
        case metadataReopen = "metadata-reopen"
        case correctionWrite = "correction-write"
        case correctionReopen = "correction-reopen"
    }

    static var isEnabled: Bool {
        value("RJT_DICTATION_STORE_SEED_CHECKS") == "1" && value("GITHUB_ACTIONS") == "true"
    }

    let phase: Phase
    let fixture: URL
    let evidence: URL
    let sourceSHA: String
    let executablePath: String
    let hostPID = ProcessInfo.processInfo.processIdentifier

    init() throws {
        try #require(Self.value("RUNNER_ENVIRONMENT") == "github-hosted", "A disposable GitHub-hosted runner is required.")
        let phaseValue = try #require(Self.value("RJT_STORE_PHASE"))
        phase = try #require(Phase(rawValue: phaseValue))
        sourceSHA = try #require(Self.value("RJT_STORE_SOURCE_SHA"))
        try #require(sourceSHA.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil)
        for key in ["RJT_STORE_RUN_ROOT", "RJT_STORE_FIXTURE", "RJT_STORE_EVIDENCE", "RJT_STORE_EXPECTED_EXE"] {
            try #require(Self.value(key)?.hasPrefix("/") == true, "The driver must supply absolute paths.")
        }
        let root = URL(fileURLWithPath: try #require(Self.value("RJT_STORE_RUN_ROOT")), isDirectory: true).standardizedFileURL
        fixture = URL(fileURLWithPath: try #require(Self.value("RJT_STORE_FIXTURE")), isDirectory: true).standardizedFileURL
        evidence = URL(fileURLWithPath: try #require(Self.value("RJT_STORE_EVIDENCE")), isDirectory: true).standardizedFileURL
        for url in [fixture, evidence] {
            try #require(url.path.hasPrefix(root.path + "/") && url != root, "All writes must stay inside the dedicated runner fixture root.")
            try #require(url.resolvingSymlinksInPath().path == url.path, "Fixture paths must not resolve through symlinks.")
        }
        try #require(fixture != evidence && !evidence.path.hasPrefix(fixture.path + "/"))
        try #require(FileManager.default.fileExists(atPath: evidence.path), "The driver must create the evidence directory.")
        executablePath = try #require(Bundle.main.executableURL).standardizedFileURL.path
        try #require(executablePath == Self.value("RJT_STORE_EXPECTED_EXE"), "The oracle must run inside the selected signed app host.")
        try #require(Bundle.main.bundleIdentifier == "com.negentropi.RomaJustTalk")
    }

    var observation: [String: Any] {
        ["version": 1, "testName": "liveDictationPersistentStoreSeedControl", "classification": "started",
         "phase": phase.rawValue, "sourceSHA": sourceSHA, "hostPID": hostPID,
         "executablePath": executablePath, "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
         "fixturePath": fixture.path, "sourcePath": #filePath,
         "normalSupportPath": VoiceInkMacOSStorageDirectories.appSupportDirectory.standardizedFileURL.path]
    }

    func waitForHostObservation() async throws {
        let url = evidence.appendingPathComponent("host-observed.json")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while !FileManager.default.fileExists(atPath: url.path) && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let receipt = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        try #require(receipt["hostPID"] as? Int == Int(hostPID))
        try #require(receipt["executablePath"] as? String == executablePath)
    }

    func write(_ value: Any, named name: String) throws {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        try bytes.write(to: evidence.appendingPathComponent(name), options: .atomic)
        Attachment.record(bytes, named: name)
    }

    static func value(_ key: String) -> String? {
        let values = ProcessInfo.processInfo.environment
        return values[key] ?? values["TEST_RUNNER_" + key]
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@available(macOS 15, *)
@MainActor
final class DictationStoreSeedFixture {
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
    private let inputs: DictationStoreSeedInputs
    private let schema: Schema
    private let configurations: [ModelConfiguration]
    private let container: ModelContainer
    let context: ModelContext

    init(inputs: DictationStoreSeedInputs) throws {
        self.inputs = inputs
        let manager = FileManager.default
        if inputs.phase == .seed {
            try #require(!manager.fileExists(atPath: inputs.fixture.path), "Refuse to overwrite any existing seed directory.")
            try manager.createDirectory(at: inputs.fixture, withIntermediateDirectories: false)
        } else {
            for group in Self.groups {
                let store = inputs.fixture.appendingPathComponent(group.fileName)
                let values = try store.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                try #require(values.isRegularFile == true && values.isSymbolicLink != true && (values.fileSize ?? 0) > 0)
            }
        }
        schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        configurations = Self.groups.map { group in
            ModelConfiguration(group.name, schema: Schema(group.types),
                               url: inputs.fixture.appendingPathComponent(group.fileName), cloudKitDatabase: .none)
        }
        for (group, config) in zip(Self.groups, configurations) {
            try #require(config.name == group.name)
            try #require(config.url.standardizedFileURL == inputs.fixture.appendingPathComponent(group.fileName).standardizedFileURL)
            try #require(!config.isStoredInMemoryOnly && config.allowsSave)
            try #require(config.groupAppContainerIdentifier == nil && config.cloudKitContainerIdentifier == nil)
        }
        container = try ModelContainer(for: schema, configurations: configurations)
        try #require(container.migrationPlan == nil)
        let actualConfigurations = container.configurations.sorted { $0.name < $1.name }
        try #require(actualConfigurations.count == Self.groups.count)
        for (group, config) in zip(Self.groups, actualConfigurations) {
            try #require(config.name == group.name && !config.isStoredInMemoryOnly && config.allowsSave)
            try #require(config.url.standardizedFileURL == inputs.fixture.appendingPathComponent(group.fileName).standardizedFileURL)
            try #require(config.groupAppContainerIdentifier == nil && config.cloudKitContainerIdentifier == nil)
            try #require(config.schema?.entities.map(\.name).sorted() == Schema(group.types).entities.map(\.name).sorted())
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func run(allowedAdditionalTranscriptionIDs: Set<UUID> = [], allowedAdditionalWordReplacementIDs: Set<UUID> = []) throws {
        if inputs.phase == .seed {
            try #require(context.fetchCount(FetchDescriptor<Transcription>()) == 0)
            try #require(context.fetchCount(FetchDescriptor<VocabularyWord>()) == 0)
            try #require(context.fetchCount(FetchDescriptor<WordReplacement>()) == 0)
            try #require(context.fetchCount(FetchDescriptor<SessionMetric>()) == 0)
            insertRows()
            try context.save()
        }
        let allTranscriptions = try context.fetch(FetchDescriptor<Transcription>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let additionalTranscriptions = allTranscriptions.filter { allowedAdditionalTranscriptionIDs.contains($0.id) }
        try #require(Set(additionalTranscriptions.map(\.id)) == allowedAdditionalTranscriptionIDs)
        try #require(additionalTranscriptions.count == allowedAdditionalTranscriptionIDs.count)
        let transcriptions = allTranscriptions.filter { !allowedAdditionalTranscriptionIDs.contains($0.id) }
        let vocabulary = try context.fetch(FetchDescriptor<VocabularyWord>()).sorted { Array($0.word.utf8).lexicographicallyPrecedes(Array($1.word.utf8)) }
        let allReplacements = try context.fetch(FetchDescriptor<WordReplacement>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let additionalReplacements = allReplacements.filter { allowedAdditionalWordReplacementIDs.contains($0.id) }
        try #require(Set(additionalReplacements.map(\.id)) == allowedAdditionalWordReplacementIDs)
        try #require(additionalReplacements.count == allowedAdditionalWordReplacementIDs.count)
        let replacements = allReplacements.filter { !allowedAdditionalWordReplacementIDs.contains($0.id) }
        let metrics = try context.fetch(FetchDescriptor<SessionMetric>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let snapshots: [String: Any] = [
            "Transcription": transcriptions.map(Self.transcriptionSnapshot),
            "VocabularyWord": vocabulary.map { ["word": Self.string($0.word), "dateAdded": $0.dateAdded.timeIntervalSince1970] },
            "WordReplacement": replacements.map(Self.replacementSnapshot),
            "SessionMetric": metrics.map(Self.metricSnapshot)
        ]
        try inputs.write(snapshots, named: "snapshots.json")
        try inputs.write(Self.expectedSnapshots, named: "expected-snapshots.json")
        let encode: (Any) throws -> Data = { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        try #require(try encode(snapshots) == encode(Self.expectedSnapshots), "Every persisted field, including exact UTF-8/UTF-16 strings and explicit nil values, must match the literal fixture.")
        try #require(!context.hasChanges, "Verification must not modify reopened records.")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let rawSchema = try encoder.encode(container.schema)
        try rawSchema.write(to: inputs.evidence.appendingPathComponent("schema-raw.json"), options: .atomic)
        Attachment.record(rawSchema, named: "schema-raw.json")
        let canonicalSchema = try Self.canonicalSchema(JSONSerialization.jsonObject(with: rawSchema))
        try inputs.write(canonicalSchema, named: "schema-canonical.json")
        let canonicalBytes = try encode(canonicalSchema)
        let models: [[String: Any]] = [
            ["reflectedType": String(reflecting: Transcription.self), "entityName": Schema.entityName(for: Transcription.self)],
            ["reflectedType": String(reflecting: VocabularyWord.self), "entityName": Schema.entityName(for: VocabularyWord.self)],
            ["reflectedType": String(reflecting: WordReplacement.self), "entityName": Schema.entityName(for: WordReplacement.self)],
            ["reflectedType": String(reflecting: SessionMetric.self), "entityName": Schema.entityName(for: SessionMetric.self)]
        ]
        try #require(models.allSatisfy { ($0["reflectedType"] as? String)?.hasPrefix("VoiceInk.") == true })
        let persistentIdentifiers: [String: Any] = [
            "Transcription": try transcriptions.map(Self.persistentIdentity),
            "VocabularyWord": try vocabulary.map(Self.persistentIdentity),
            "WordReplacement": try replacements.map(Self.persistentIdentity),
            "SessionMetric": try metrics.map(Self.persistentIdentity)
        ]
        let transcriptStores = Set(transcriptions.compactMap { $0.persistentModelID.storeIdentifier })
        let vocabularyStores = Set(vocabulary.compactMap { $0.persistentModelID.storeIdentifier })
        let replacementStores = Set(replacements.compactMap { $0.persistentModelID.storeIdentifier })
        let metricStores = Set(metrics.compactMap { $0.persistentModelID.storeIdentifier })
        try #require(transcriptStores.count == 1 && vocabularyStores.count == 1 && metricStores.count == 1)
        try #require(vocabularyStores == replacementStores)
        try #require(transcriptStores.union(vocabularyStores).union(metricStores).count == 3,
                     "The actual saved identifiers must belong to three separate stores with a shared dictionary store.")
        let configReceipt: [[String: Any]] = container.configurations.sorted { $0.name < $1.name }.map { config in
            ["name": config.name, "url": config.url.path, "isStoredInMemoryOnly": config.isStoredInMemoryOnly,
             "allowsSave": config.allowsSave, "groupAppContainerIdentifier": Self.optional(config.groupAppContainerIdentifier),
             "cloudKitContainerIdentifier": Self.optional(config.cloudKitContainerIdentifier),
             "schemaEntities": config.schema?.entities.map(\.name).sorted() ?? []]
        }
        try inputs.write([
            "models": models, "declaredSchemaOrder": ["Transcription", "VocabularyWord", "WordReplacement", "SessionMetric"],
            "schemaEntities": container.schema.entities.map(\.name).sorted(), "persistentIdentifiers": persistentIdentifiers,
            "configurations": configReceipt, "schemaRawSHA256": DictationStoreSeedInputs.sha256(rawSchema),
            "schemaCanonicalSHA256": DictationStoreSeedInputs.sha256(canonicalBytes),
            "schemaNormalization": "Sort object keys and arrays keyed entities, subentities, attributes, storedAttributes, relationships, properties, storedProperties, inheritedProperties, or options by canonical JSON bytes. Preserve every value and all other array order, including compound indices and uniqueness constraints. No defaults or runtime metadata are removed."
        ], named: "runtimeidentity.json")
    }

    private func insertRows() {
        let rich = Transcription(text: Self.richText, duration: 7.125, enhancedText: Self.enhancedText,
                                 audioFileURL: "https://example.com/rjt-public-store-fixture.wav",
                                 transcriptionModelName: "fixture-recognizer", aiEnhancementModelName: "fixture-polisher",
                                 promptName: "Fixture \"quoted\" prompt", transcriptionDuration: 1.25, enhancementDuration: 0.375,
                                 aiRequestSystemMessage: "System\r\nCafe\u{301} 🧪", aiRequestUserMessage: "User\n\"literal\" text",
                                 powerModeName: "Fixture mode", powerModeEmoji: "🧪", transcriptionStatus: .completed)
        rich.id = Self.transcriptionID
        rich.timestamp = Self.date
        context.insert(rich)
        let empty = Transcription(text: "", duration: 0)
        empty.id = Self.emptyTranscriptionID
        empty.timestamp = Self.laterDate
        empty.transcriptionStatus = nil
        context.insert(empty)
        context.insert(VocabularyWord(word: Self.vocabularyText, dateAdded: Self.date))
        context.insert(VocabularyWord(word: "", dateAdded: Self.laterDate))
        let disabled = WordReplacement(originalText: "Cafe\u{301}, café, \"tea\"", replacementText: "Disabled\r\n🧪", dateAdded: Self.date, isEnabled: false)
        disabled.id = Self.replacementID
        context.insert(disabled)
        let enabled = WordReplacement(originalText: "old", replacementText: "new", dateAdded: Self.laterDate)
        enabled.id = Self.enabledReplacementID
        context.insert(enabled)
        let metric = SessionMetric(transcriptionId: Self.transcriptionID, timestamp: Self.date, source: "fixture-recorder",
                                   wordCount: 11, audioDuration: 7.125, transcriptionModelName: "fixture-recognizer",
                                   transcriptionDuration: 1.25, speedFactor: 5.7, powerModeName: "Fixture mode",
                                   aiEnhancementModelName: "fixture-polisher", enhancementDuration: 0.375)
        metric.id = Self.metricID
        context.insert(metric)
        let emptyMetric = SessionMetric(transcriptionId: Self.emptyTranscriptionID, timestamp: Self.laterDate, source: nil,
                                        wordCount: 0, audioDuration: 0, transcriptionModelName: nil, transcriptionDuration: nil,
                                        speedFactor: nil, powerModeName: nil, aiEnhancementModelName: nil, enhancementDuration: nil)
        emptyMetric.id = Self.emptyMetricID
        context.insert(emptyMetric)
    }

    private static let transcriptionID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private static let emptyTranscriptionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private static let replacementID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private static let enabledReplacementID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private static let metricID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    private static let emptyMetricID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
    private static let date = Date(timeIntervalSince1970: 1_700_000_000.125)
    private static let laterDate = Date(timeIntervalSince1970: 1_700_000_001.5)
    private static let richText = "Cafe\u{301} 🧪 \"verbatim\"\r\nSecond line\nThird line"
    private static let enhancedText = "Existing processed text.\r\n\"Cafe\u{301}\" 🧪"
    private static let vocabularyText = "Cafe\u{301} 🧪 \"word\"\r\nline"

    private static var expectedSnapshots: [String: Any] {
        ["Transcription": expectedTranscriptions, "VocabularyWord": expectedVocabulary,
         "WordReplacement": expectedReplacements, "SessionMetric": expectedMetrics]
    }

    private static var expectedTranscriptions: [[String: Any]] {
        [
            ["id": transcriptionID.uuidString, "text": string(richText), "enhancedText": string(enhancedText),
             "timestamp": date.timeIntervalSince1970, "duration": 7.125,
             "audioFileURL": string("https://example.com/rjt-public-store-fixture.wav"),
             "transcriptionModelName": string("fixture-recognizer"), "aiEnhancementModelName": string("fixture-polisher"),
             "promptName": string("Fixture \"quoted\" prompt"), "transcriptionDuration": 1.25, "enhancementDuration": 0.375,
             "aiRequestSystemMessage": string("System\r\nCafe\u{301} 🧪"), "aiRequestUserMessage": string("User\n\"literal\" text"),
             "powerModeName": string("Fixture mode"), "powerModeEmoji": string("🧪"), "transcriptionStatus": string("completed")],
            ["id": emptyTranscriptionID.uuidString, "text": string(""), "enhancedText": NSNull(),
             "timestamp": laterDate.timeIntervalSince1970, "duration": 0.0, "audioFileURL": NSNull(),
             "transcriptionModelName": NSNull(), "aiEnhancementModelName": NSNull(), "promptName": NSNull(),
             "transcriptionDuration": NSNull(), "enhancementDuration": NSNull(), "aiRequestSystemMessage": NSNull(),
             "aiRequestUserMessage": NSNull(), "powerModeName": NSNull(), "powerModeEmoji": NSNull(), "transcriptionStatus": NSNull()]
        ]
    }

    private static var expectedVocabulary: [[String: Any]] {
        [["word": string(""), "dateAdded": laterDate.timeIntervalSince1970],
         ["word": string(vocabularyText), "dateAdded": date.timeIntervalSince1970]]
    }

    private static var expectedReplacements: [[String: Any]] {
        [
            ["id": replacementID.uuidString, "originalText": string("Cafe\u{301}, café, \"tea\""),
             "replacementText": string("Disabled\r\n🧪"), "dateAdded": date.timeIntervalSince1970, "isEnabled": false],
            ["id": enabledReplacementID.uuidString, "originalText": string("old"), "replacementText": string("new"),
             "dateAdded": laterDate.timeIntervalSince1970, "isEnabled": true]
        ]
    }

    private static var expectedMetrics: [[String: Any]] {
        [
            ["id": metricID.uuidString, "transcriptionId": transcriptionID.uuidString, "timestamp": date.timeIntervalSince1970,
             "source": string("fixture-recorder"), "wordCount": 11, "audioDuration": 7.125,
             "transcriptionModelName": string("fixture-recognizer"), "transcriptionDuration": 1.25, "speedFactor": 5.7,
             "powerModeName": string("Fixture mode"), "aiEnhancementModelName": string("fixture-polisher"), "enhancementDuration": 0.375],
            ["id": emptyMetricID.uuidString, "transcriptionId": emptyTranscriptionID.uuidString, "timestamp": laterDate.timeIntervalSince1970,
             "source": NSNull(), "wordCount": 0, "audioDuration": 0.0, "transcriptionModelName": NSNull(),
             "transcriptionDuration": NSNull(), "speedFactor": NSNull(), "powerModeName": NSNull(),
             "aiEnhancementModelName": NSNull(), "enhancementDuration": NSNull()]
        ]
    }

    static func transcriptionSnapshot(_ row: Transcription) -> [String: Any] {
        ["id": row.id.uuidString, "text": string(row.text), "enhancedText": optionalString(row.enhancedText),
         "timestamp": row.timestamp.timeIntervalSince1970, "duration": row.duration, "audioFileURL": optionalString(row.audioFileURL),
         "transcriptionModelName": optionalString(row.transcriptionModelName), "aiEnhancementModelName": optionalString(row.aiEnhancementModelName),
         "promptName": optionalString(row.promptName), "transcriptionDuration": optional(row.transcriptionDuration),
         "enhancementDuration": optional(row.enhancementDuration), "aiRequestSystemMessage": optionalString(row.aiRequestSystemMessage),
         "aiRequestUserMessage": optionalString(row.aiRequestUserMessage), "powerModeName": optionalString(row.powerModeName),
         "powerModeEmoji": optionalString(row.powerModeEmoji), "transcriptionStatus": optionalString(row.transcriptionStatus)]
    }

    static func replacementSnapshot(_ row: WordReplacement) -> [String: Any] {
        ["id": row.id.uuidString, "originalText": string(row.originalText), "replacementText": string(row.replacementText),
         "dateAdded": row.dateAdded.timeIntervalSince1970, "isEnabled": row.isEnabled]
    }

    private static func metricSnapshot(_ row: SessionMetric) -> [String: Any] {
        ["id": row.id.uuidString, "transcriptionId": row.transcriptionId.uuidString, "timestamp": row.timestamp.timeIntervalSince1970,
         "source": optionalString(row.source), "wordCount": row.wordCount, "audioDuration": row.audioDuration,
         "transcriptionModelName": optionalString(row.transcriptionModelName), "transcriptionDuration": optional(row.transcriptionDuration),
         "speedFactor": optional(row.speedFactor), "powerModeName": optionalString(row.powerModeName),
         "aiEnhancementModelName": optionalString(row.aiEnhancementModelName), "enhancementDuration": optional(row.enhancementDuration)]
    }

    static func persistentIdentity<T: PersistentModel>(_ row: T) throws -> [String: Any] {
        let identifier = row.persistentModelID
        let storeIdentifier = try #require(identifier.storeIdentifier)
        try #require(!storeIdentifier.isEmpty && identifier.entityName == Schema.entityName(for: T.self))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return ["entityName": identifier.entityName, "storeIdentifier": storeIdentifier,
                "encodedBase64": try encoder.encode(identifier).base64EncodedString()]
    }

    static func string(_ value: String) -> [String: Any] {
        ["value": value, "utf8": Array(value.utf8), "utf16": Array(value.utf16)]
    }

    static func optionalString(_ value: String?) -> Any {
        value.map(string) as Any? ?? NSNull()
    }

    private static func optional<T>(_ value: T?) -> Any {
        value as Any? ?? NSNull()
    }

    private static func canonicalSchema(_ value: Any, key: String? = nil) throws -> Any {
        if let object = value as? [String: Any] {
            return try Dictionary(uniqueKeysWithValues: object.map { name, child in
                (name, try canonicalSchema(child, key: name))
            })
        }
        if let array = value as? [Any] {
            let normalized = try array.map { try canonicalSchema($0) }
            let unorderedKeys: Set<String> = ["entities", "subentities", "attributes", "storedAttributes", "relationships", "properties",
                                              "storedProperties", "inheritedProperties", "options"]
            guard let key, unorderedKeys.contains(key) else { return normalized }
            let paired = try normalized.map { item in
                (item, try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys, .fragmentsAllowed]))
            }
            return paired.sorted { $0.1.lexicographicallyPrecedes($1.1) }.map(\.0)
        }
        return value
    }
}
