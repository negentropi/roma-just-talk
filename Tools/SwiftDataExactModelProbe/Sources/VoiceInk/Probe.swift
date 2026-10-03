import CoreData
import Darwin
import Foundation
import SwiftData
import VoiceInkCore

private enum Layout: Equatable {
    case combined, separateStats, separateDomains, fullSchemaControl
}

private enum Execution {
    case main, mainContext, detached, modelActor
}

private enum Mode: String, CaseIterable {
    case combinedMain = "combined-main"
    case combinedMainContext = "combined-main-context"
    case combinedBackground = "combined-background"
    case combinedModelActor = "combined-model-actor"
    case separateStatsMain = "separate-stats-main"
    case separateStatsBackground = "separate-stats-background"
    case separateDomainsMain = "separate-domains-main"
    case separateDomainsBackground = "separate-domains-background"
    case fullSchemaControlBackground = "full-schema-control-background"

    var layout: Layout {
        switch self {
        case .combinedMain, .combinedMainContext, .combinedBackground, .combinedModelActor: .combined
        case .separateStatsMain, .separateStatsBackground: .separateStats
        case .separateDomainsMain, .separateDomainsBackground: .separateDomains
        case .fullSchemaControlBackground: .fullSchemaControl
        }
    }

    var execution: Execution {
        switch self {
        case .combinedMain, .separateStatsMain, .separateDomainsMain: .main
        case .combinedMainContext: .mainContext
        case .combinedBackground, .separateStatsBackground, .separateDomainsBackground, .fullSchemaControlBackground: .detached
        case .combinedModelActor: .modelActor
        }
    }
}

private enum ProductionMode: String, CaseIterable {
    case persistentReopen = "production-persistent-reopen"
    case memory = "production-memory"
    case writer = "production-writer"
    case upgrade = "production-upgrade"
    case legacySeedHosted = "legacy-seed-hosted"

    static var automaticCases: [ProductionMode] { [.persistentReopen, .memory, .writer] }
}

private struct Containers {
    let transcript: ModelContainer
    let dictionary: ModelContainer
    let stats: ModelContainer
}

private func emit(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

private func observeStore(_ configuration: ModelConfiguration) throws {
    var record: [String: Any] = [
        "event": "store-metadata",
        "name": configuration.name,
        "url": configuration.url.path,
        "declaredEntities": configuration.schema?.entities.map(\.name).sorted() ?? []
    ]
    if FileManager.default.fileExists(atPath: configuration.url.path) {
        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: configuration.url,
                options: [NSReadOnlyPersistentStoreOption: true]
            )
            let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] ?? [:]
            record["versionHashEntities"] = hashes.keys.sorted()
            record["versionHashes"] = hashes.mapValues { $0.map { String(format: "%02x", $0) }.joined() }
            record["storeUUID"] = metadata[NSStoreUUIDKey]
        } catch {
            record["metadataReadError"] = String(describing: error)
        }
    } else {
        record["fileExists"] = false
    }
    try emit(record)
}

@MainActor
private func makeContainers(layout: Layout, directory: URL) throws -> Containers {
    let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
    let schemas = [Schema([Transcription.self]), Schema([VocabularyWord.self, WordReplacement.self]), Schema([SessionMetric.self])]
    let names = ["default", "dictionary", "stats"]
    let configurations = zip(names, schemas).map { name, subset in
        ModelConfiguration(
            name,
            schema: layout == .fullSchemaControl ? schema : subset,
            url: directory.appendingPathComponent(name + ".store"),
            cloudKitDatabase: .none
        )
    }
    let containers: Containers
    switch layout {
    case .combined, .fullSchemaControl:
        let container = try ModelContainer(for: schema, configurations: configurations)
        containers = Containers(transcript: container, dictionary: container, stats: container)
    case .separateStats:
        let legacySchema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self])
        let legacy = try ModelContainer(for: legacySchema, configurations: Array(configurations.prefix(2)))
        let stats = try ModelContainer(for: schemas[2], configurations: configurations[2])
        containers = Containers(transcript: legacy, dictionary: legacy, stats: stats)
    case .separateDomains:
        containers = try Containers(
            transcript: ModelContainer(for: schemas[0], configurations: configurations[0]),
            dictionary: ModelContainer(for: schemas[1], configurations: configurations[1]),
            stats: ModelContainer(for: schemas[2], configurations: configurations[2])
        )
    }
    try emit([
        "event": "container-created",
        "statsDeclaredEntities": containers.stats.schema.entities.map(\.name).sorted(),
        "mainThread": Thread.isMainThread,
        "cloudKit": "none"
    ])
    for configuration in configurations { try observeStore(configuration) }
    return containers
}

private func fetchAll(statsContext: ModelContext, containers: Containers) throws {
    try emit(["event": "fetch-begin", "entity": "SessionMetric", "mainThread": Thread.isMainThread])
    let metricCount = try statsContext.fetch(FetchDescriptor<SessionMetric>()).count
    try emit(["event": "fetch-completed", "entity": "SessionMetric", "count": metricCount])
    let transcriptContext = ModelContext(containers.transcript)
    let dictionaryContext = ModelContext(containers.dictionary)
    try emit(["event": "fetch-begin", "entity": "Transcription"])
    let transcriptCount = try transcriptContext.fetch(FetchDescriptor<Transcription>()).count
    try emit(["event": "fetch-completed", "entity": "Transcription", "count": transcriptCount])
    try emit(["event": "fetch-begin", "entity": "VocabularyWord"])
    let wordCount = try dictionaryContext.fetch(FetchDescriptor<VocabularyWord>()).count
    try emit(["event": "fetch-completed", "entity": "VocabularyWord", "count": wordCount])
    try emit(["event": "fetch-begin", "entity": "WordReplacement"])
    let replacementCount = try dictionaryContext.fetch(FetchDescriptor<WordReplacement>()).count
    try emit(["event": "fetch-completed", "entity": "WordReplacement", "count": replacementCount])
    guard [metricCount, transcriptCount, wordCount, replacementCount].allSatisfy({ $0 == 0 }) else {
        throw ProbeError.nonemptyFreshStore
    }
}

@ModelActor
private actor FetchWorker {
    func fetch(containers: Containers) throws {
        try fetchAll(statsContext: modelContext, containers: containers)
    }
}

private enum ProbeError: Error {
    case usage, nonemptyDirectory, nonemptyFreshStore, unexpectedValues, readOnlySaveAccepted, storeIdentityChanged, nonAPFSDirectory
}

private func requireAPFS(_ directory: URL) throws {
    var filesystem = statfs()
    guard directory.path.withCString({ statfs($0, &filesystem) }) == 0 else { throw ProbeError.nonAPFSDirectory }
    let capacity = MemoryLayout.size(ofValue: filesystem.f_fstypename)
    let name = withUnsafePointer(to: &filesystem.f_fstypename) {
        $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
    }
    guard name == "apfs" else { throw ProbeError.nonAPFSDirectory }
    try emit(["event": "store-filesystem", "type": name, "path": directory.path])
}

private struct StoreIdentity: Equatable {
    let uuid: String
    let versionHashes: [String: Data]
}

private let ownedEntitiesByStore: [String: Set<String>] = [
    "default": ["Transcription"],
    "dictionary": ["VocabularyWord", "WordReplacement"],
    "stats": ["SessionMetric"]
]

private func verifyUpgradeIdentities(before: [String: StoreIdentity], after: [String: StoreIdentity]) throws {
    let names = Set(ownedEntitiesByStore.keys)
    guard Set(before.keys) == names, Set(after.keys) == names else { throw ProbeError.storeIdentityChanged }
    for (name, entities) in ownedEntitiesByStore {
        guard let original = before[name], let current = after[name], original.uuid == current.uuid,
              Set(current.versionHashes.keys) == entities else { throw ProbeError.storeIdentityChanged }
        for entity in entities {
            guard let originalHash = original.versionHashes[entity],
                  current.versionHashes[entity] == originalHash else { throw ProbeError.storeIdentityChanged }
        }
    }
}

private func verifyUpgradeIdentityRejections(before: [String: StoreIdentity], after: [String: StoreIdentity]) throws {
    var rejected: [String] = []
    func requireRejection(_ name: String, original: [String: StoreIdentity], current: [String: StoreIdentity]) throws {
        do { try verifyUpgradeIdentities(before: original, after: current) }
        catch ProbeError.storeIdentityChanged {
            rejected.append(name)
            return
        }
        throw ProbeError.unexpectedValues
    }
    for name in ownedEntitiesByStore.keys.sorted() {
        let original = before[name]!
        let current = after[name]!
        var changed = after
        changed[name] = StoreIdentity(uuid: "changed-" + current.uuid, versionHashes: current.versionHashes)
        try requireRejection(name + "-changed-uuid", original: before, current: changed)
        var hashes = current.versionHashes
        hashes["UnexpectedEntity"] = Data([1])
        changed[name] = StoreIdentity(uuid: current.uuid, versionHashes: hashes)
        try requireRejection(name + "-extra-entity", original: before, current: changed)
        for entity in ownedEntitiesByStore[name]!.sorted() {
            hashes = current.versionHashes
            hashes[entity] = current.versionHashes[entity]! + Data([0])
            changed[name] = StoreIdentity(uuid: current.uuid, versionHashes: hashes)
            try requireRejection(name + "-" + entity + "-changed-hash", original: before, current: changed)
            hashes.removeValue(forKey: entity)
            changed[name] = StoreIdentity(uuid: current.uuid, versionHashes: hashes)
            try requireRejection(name + "-" + entity + "-missing-entity", original: before, current: changed)
            var missingOriginal = before
            hashes = original.versionHashes
            hashes.removeValue(forKey: entity)
            missingOriginal[name] = StoreIdentity(uuid: original.uuid, versionHashes: hashes)
            try requireRejection(name + "-" + entity + "-missing-original-hash", original: missingOriginal, current: after)
        }
    }
    var missing = after
    missing.removeValue(forKey: "stats")
    try requireRejection("missing-store", original: before, current: missing)
    var extra = after
    extra["unexpected"] = after["stats"]!
    try requireRejection("extra-store", original: before, current: extra)
    try emit(["event": "upgrade-identity-rejections-verified", "cases": rejected])
}

private func storeIdentities(directory: URL) throws -> [String: StoreIdentity] {
    var identities: [String: StoreIdentity] = [:]
    for name in ["default", "dictionary", "stats"] {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: directory.appendingPathComponent(name + ".store"),
            options: [NSReadOnlyPersistentStoreOption: true]
        )
        guard let uuid = metadata[NSStoreUUIDKey] as? String,
              let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] else {
            throw ProbeError.storeIdentityChanged
        }
        identities[name] = StoreIdentity(uuid: uuid, versionHashes: hashes)
    }
    return identities
}

private let fixtureID = UUID(uuidString: "E74051A6-A777-45B1-8574-8B1C9A719740")!

private func fixtureTranscript() -> Transcription {
    let transcript = Transcription(
        text: "legacy three words", duration: 6, transcriptionModelName: "fixture model",
        transcriptionDuration: 2, transcriptionStatus: .completed
    )
    transcript.id = fixtureID
    transcript.timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    return transcript
}

private func fixtureDraft(id: UUID = fixtureID) -> VoiceInkSessionMetricDraft {
    let transcript = fixtureTranscript()
    return VoiceInkSessionMetricPolicy.recorderDraft(
        transcriptionId: id, timestamp: transcript.timestamp, source: transcript,
        transcriptionModelName: transcript.transcriptionModelName,
        powerModeName: nil, aiEnhancementModelName: nil
    )
}

@MainActor
private func verifyValues(_ containers: Containers) throws {
    let transcriptions = try ModelContext(containers.transcript).fetch(FetchDescriptor<Transcription>())
    let vocabulary = try ModelContext(containers.dictionary).fetch(FetchDescriptor<VocabularyWord>())
    let replacements = try ModelContext(containers.dictionary).fetch(FetchDescriptor<WordReplacement>())
    let metrics = try ModelContext(containers.stats).fetch(FetchDescriptor<SessionMetric>())
    try emit([
        "event": "stored-values", "transcripts": transcriptions.map { ["id": $0.id.uuidString, "text": $0.text] },
        "vocabulary": vocabulary.map(\.word),
        "replacements": replacements.map { ["original": $0.originalText, "replacement": $0.replacementText] },
        "metrics": metrics.map { ["id": $0.transcriptionId.uuidString, "words": $0.wordCount, "duration": $0.audioDuration] as [String: Any] }
    ])
    guard transcriptions.count == 1, vocabulary.count == 1, replacements.count == 1, metrics.count == 1,
          transcriptions[0].id == fixtureID, transcriptions[0].text == "legacy three words",
          transcriptions[0].duration == 6, transcriptions[0].transcriptionState == .completed,
          vocabulary[0].word == "RJT Sonoma", replacements[0].originalText == "r j t",
          replacements[0].replacementText == "Roma Just Talk", metrics[0].transcriptionId == fixtureID,
          metrics[0].wordCount == 3, metrics[0].audioDuration == 6, metrics[0].speedFactor == 3,
          metrics[0].transcriptionModelName == "fixture model" else {
        throw ProbeError.unexpectedValues
    }
}

@MainActor
private func observeProductionStores(_ stores: VoiceInkModelStores) throws {
    for container in [stores.transcription, stores.dictionary, stores.metrics] {
        for configuration in container.configurations { try observeStore(configuration) }
    }
}

@MainActor
private func productionContainers(_ stores: VoiceInkModelStores) -> Containers {
    Containers(transcript: stores.transcription, dictionary: stores.dictionary, stats: stores.metrics)
}

@MainActor
private func seedProductionStores(_ stores: VoiceInkModelStores) async throws {
    stores.transcription.mainContext.insert(fixtureTranscript())
    try stores.transcription.mainContext.save()
    stores.dictionary.mainContext.insert(VocabularyWord(word: "RJT Sonoma"))
    stores.dictionary.mainContext.insert(WordReplacement(originalText: "r j t", replacementText: "Roma Just Talk"))
    try stores.dictionary.mainContext.save()
    guard try await stores.metricWriter.value.record([fixtureDraft()]) == 1 else { throw ProbeError.unexpectedValues }
}

@MainActor
private func verifyProductionWriter(directory: URL) async throws {
    let stores = try VoiceInkModelStores.persistent(at: directory, dictionaryCloudKit: .none)
    let draft = fixtureDraft()
    let writerTask = stores.metricWriter
    let inserted = try await withThrowingTaskGroup(of: Int.self) { group in
        for _ in 0..<20 {
            group.addTask { try await writerTask.value.record([draft, draft]) }
        }
        var total = 0
        for try await count in group { total += count }
        return total
    }
    guard inserted == 1 else { throw ProbeError.unexpectedValues }
    let pending = fixtureDraft(id: UUID(uuidString: "2B182BD0-4F19-4C68-9996-C8467055F8B2")!)
    let schema = Schema([SessionMetric.self])
    let readOnly = try ModelContainer(for: schema, configurations: ModelConfiguration(
        "stats", schema: schema, url: directory.appendingPathComponent("stats.store"),
        allowsSave: false, cloudKitDatabase: .none
    ))
    let context = ModelContext(readOnly)
    context.autosaveEnabled = false
    context.insert(SessionMetric(draft: pending))
    var rejected = false
    do { try context.save() } catch {
        rejected = true
        try emit(["event": "read-only-save-rejected", "error": String(describing: error)])
    }
    guard rejected else { throw ProbeError.readOnlySaveAccepted }
    context.rollback()
    let failingWriter = await Task.detached { SessionMetricRecorder(modelContainer: readOnly) }.value
    for attempt in 1...2 {
        var writerRejected = false
        do { _ = try await failingWriter.record([draft, pending]) } catch {
            writerRejected = true
            try emit(["event": "writer-save-rejected", "attempt": attempt, "error": String(describing: error)])
        }
        guard writerRejected else { throw ProbeError.readOnlySaveAccepted }
    }
    let reopened = try VoiceInkModelStores.persistent(at: directory, dictionaryCloudKit: .none)
    guard try await reopened.metricWriter.value.record([draft, pending]) == 1,
          try await reopened.metricWriter.value.record([draft, pending]) == 0 else {
        throw ProbeError.unexpectedValues
    }
    let final = try VoiceInkModelStores.persistent(at: directory, dictionaryCloudKit: .none)
    let rows = try final.metrics.mainContext.fetch(FetchDescriptor<SessionMetric>())
    guard rows.count == 2, Set(rows.map(\.transcriptionId)) == [draft.transcriptionId, pending.transcriptionId],
          rows.reduce(0, { $0 + $1.wordCount }) == 6 else { throw ProbeError.unexpectedValues }
    try observeProductionStores(final)
    try emit(["event": "writer-verified", "concurrentInsertCount": inserted, "persistedMetricCount": rows.count, "totalWords": 6])
}

@MainActor
private func runProduction(_ mode: ProductionMode, directory: URL) async throws {
    switch mode {
    case .legacySeedHosted:
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 else { throw ProbeError.usage }
        let containers = try makeContainers(layout: .combined, directory: directory)
        let context = containers.transcript.mainContext
        context.insert(fixtureTranscript())
        context.insert(VocabularyWord(word: "RJT Sonoma"))
        context.insert(WordReplacement(originalText: "r j t", replacementText: "Roma Just Talk"))
        context.insert(SessionMetric(draft: fixtureDraft()))
        try context.save()
        try verifyValues(containers)
        for configuration in containers.transcript.configurations { try observeStore(configuration) }
        try emit(["event": "legacy-fixture-seeded", "layout": "original-three-subset-configurations"])
    case .persistentReopen:
        let stores = try VoiceInkModelStores.persistent(at: directory, dictionaryCloudKit: .none)
        try await seedProductionStores(stores)
        let reopened = try VoiceInkModelStores.persistent(at: directory, dictionaryCloudKit: .none)
        try verifyValues(productionContainers(reopened))
        try observeProductionStores(reopened)
    case .memory:
        let stores = try VoiceInkModelStores.inMemory()
        try await seedProductionStores(stores)
        try verifyValues(productionContainers(stores))
        let independent = try VoiceInkModelStores.inMemory()
        try fetchAll(statsContext: independent.metrics.mainContext, containers: productionContainers(independent))
    case .writer:
        try await verifyProductionWriter(directory: directory)
    case .upgrade:
        let before = try storeIdentities(directory: directory)
        for name in ["default", "dictionary", "stats"] {
            let configuration = ModelConfiguration(name, url: directory.appendingPathComponent(name + ".store"), cloudKitDatabase: .none)
            try observeStore(configuration)
        }
        let stores = try VoiceInkModelStores.persistent(at: directory, dictionaryCloudKit: .none)
        try verifyValues(productionContainers(stores))
        guard try await stores.metricWriter.value.record([fixtureDraft()]) == 0 else { throw ProbeError.unexpectedValues }
        try observeProductionStores(stores)
        let after = try storeIdentities(directory: directory)
        try verifyUpgradeIdentities(before: before, after: after)
        try verifyUpgradeIdentityRejections(before: before, after: after)
        try emit(["event": "legacy-store-identities-preserved", "stores": before.keys.sorted(),
                  "ownedEntities": ownedEntitiesByStore.mapValues { $0.sorted() }])
    }
}

@main
private struct Probe {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments == [CommandLine.arguments[0], "--list-modes"] {
            let data = try JSONEncoder().encode(Mode.allCases.map(\.rawValue) + ProductionMode.automaticCases.map(\.rawValue))
            FileHandle.standardOutput.write(data + Data([10]))
            return
        }
        guard CommandLine.arguments.count == 3 else {
            throw ProbeError.usage
        }
        let modeName = CommandLine.arguments[1]
        let mode = Mode(rawValue: modeName)
        let productionMode = ProductionMode(rawValue: modeName)
        guard mode != nil || productionMode != nil else { throw ProbeError.usage }
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw ProbeError.nonemptyDirectory }
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard productionMode == .upgrade || contents.isEmpty else {
            throw ProbeError.nonemptyDirectory
        }
        try requireAPFS(directory)
        try emit([
            "event": "start", "mode": modeName, "diagnosticOnly": true, "directory": directory.path,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "absent",
            "bundleName": Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "absent"
        ])
        if let productionMode {
            try await runProduction(productionMode, directory: directory)
        } else if let mode {
            let containers = try makeContainers(layout: mode.layout, directory: directory)
            switch mode.execution {
            case .main:
                try fetchAll(statsContext: ModelContext(containers.stats), containers: containers)
            case .mainContext:
                try fetchAll(statsContext: containers.stats.mainContext, containers: containers)
            case .detached:
                try await Task.detached {
                    try fetchAll(statsContext: ModelContext(containers.stats), containers: containers)
                }.value
            case .modelActor:
                try await Task.detached {
                    let worker = FetchWorker(modelContainer: containers.stats)
                    try await worker.fetch(containers: containers)
                }.value
            }
        }
        try emit(["event": "completed", "mode": modeName])
    }
}
