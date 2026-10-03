import CoreData
import Foundation
import SwiftData

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
    case usage, nonemptyDirectory, nonemptyFreshStore
}

@main
private struct Probe {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments == [CommandLine.arguments[0], "--list-modes"] {
            let data = try JSONEncoder().encode(Mode.allCases.map(\.rawValue))
            FileHandle.standardOutput.write(data + Data([10]))
            return
        }
        guard CommandLine.arguments.count == 3, let mode = Mode(rawValue: CommandLine.arguments[1]) else {
            throw ProbeError.usage
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path),
              try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
            throw ProbeError.nonemptyDirectory
        }
        try emit([
            "event": "start", "mode": mode.rawValue, "diagnosticOnly": true, "directory": directory.path,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "absent",
            "bundleName": Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "absent"
        ])
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
        try emit(["event": "completed", "mode": mode.rawValue])
    }
}
