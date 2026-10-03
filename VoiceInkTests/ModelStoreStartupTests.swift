import CoreData
import Darwin
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

struct ModelStoreStartupTests {
    @Test @MainActor
    func dedicatedStoresPersistAndReopenAllFourModels() async throws {
        let directory = try ModelStoreTestDirectory()
        defer { directory.remove() }
        let stores = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        let transcript = Transcription(text: "three persisted words", duration: 4, transcriptionStatus: .completed)
        let transcriptionID = transcript.id
        stores.transcription.mainContext.insert(transcript)
        try stores.transcription.mainContext.save()
        stores.dictionary.mainContext.insert(VocabularyWord(word: "Sonoma"))
        stores.dictionary.mainContext.insert(WordReplacement(originalText: "rjt", replacementText: "Roma Just Talk"))
        try stores.dictionary.mainContext.save()
        let writer = await stores.metricWriter.value
        #expect(try await writer.record([modelStoreTestDraft(id: transcriptionID)]) == 1)

        let reopened = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        #expect(try reopened.transcription.mainContext.fetch(FetchDescriptor<Transcription>()).map(\.text) == ["three persisted words"])
        #expect(try reopened.dictionary.mainContext.fetch(FetchDescriptor<VocabularyWord>()).map(\.word) == ["Sonoma"])
        #expect(try reopened.dictionary.mainContext.fetch(FetchDescriptor<WordReplacement>()).map(\.replacementText) == ["Roma Just Talk"])
        #expect(try reopened.metrics.mainContext.fetch(FetchDescriptor<SessionMetric>()).map(\.transcriptionId) == [transcriptionID])
        try expectStoreEntities(at: directory.url.appendingPathComponent("default.store"), expected: ["Transcription"])
        try expectStoreEntities(at: directory.url.appendingPathComponent("dictionary.store"), expected: ["VocabularyWord", "WordReplacement"])
        try expectStoreEntities(at: directory.url.appendingPathComponent("stats.store"), expected: ["SessionMetric"])
    }

    @Test @MainActor
    func factoryAdoptsExistingNamedStores() async throws {
        let directory = try ModelStoreTestDirectory()
        defer { directory.remove() }
        let transcriptionSchema = Schema([Transcription.self])
        let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
        let metricsSchema = Schema([SessionMetric.self])
        let transcript = Transcription(text: "existing transcript", duration: 2, transcriptionStatus: .completed)
        let transcriptionID = transcript.id
        do {
            let container = try ModelContainer(for: transcriptionSchema, configurations: ModelConfiguration(
                "default", schema: transcriptionSchema, url: directory.url.appendingPathComponent("default.store"), cloudKitDatabase: .none
            ))
            container.mainContext.insert(transcript)
            try container.mainContext.save()
        }
        do {
            let container = try ModelContainer(for: dictionarySchema, configurations: ModelConfiguration(
                "dictionary", schema: dictionarySchema, url: directory.url.appendingPathComponent("dictionary.store"), cloudKitDatabase: .none
            ))
            container.mainContext.insert(VocabularyWord(word: "existing vocabulary"))
            container.mainContext.insert(WordReplacement(originalText: "old", replacementText: "retained"))
            try container.mainContext.save()
        }
        do {
            let container = try ModelContainer(for: metricsSchema, configurations: ModelConfiguration(
                "stats", schema: metricsSchema, url: directory.url.appendingPathComponent("stats.store"), cloudKitDatabase: .none
            ))
            container.mainContext.insert(SessionMetric(draft: modelStoreTestDraft(id: transcriptionID)))
            try container.mainContext.save()
        }

        let stores = try VoiceInkModelStores.persistent(at: directory.url, dictionaryCloudKit: .none)
        #expect(try stores.transcription.mainContext.fetch(FetchDescriptor<Transcription>()).map(\.text) == ["existing transcript"])
        #expect(try stores.dictionary.mainContext.fetch(FetchDescriptor<VocabularyWord>()).map(\.word) == ["existing vocabulary"])
        #expect(try stores.dictionary.mainContext.fetch(FetchDescriptor<WordReplacement>()).map(\.replacementText) == ["retained"])
        #expect(try stores.metrics.mainContext.fetch(FetchDescriptor<SessionMetric>()).map(\.transcriptionId) == [transcriptionID])
        #expect(try await stores.metricWriter.value.record([modelStoreTestDraft(id: transcriptionID)]) == 0)
    }

    @Test @MainActor
    func inMemoryStoresUseTheSameDomainMapping() throws {
        let stores = try VoiceInkModelStores.inMemory()
        #expect(stores.transcription.schema.entities.map(\.name).sorted() == ["Transcription"])
        #expect(stores.dictionary.schema.entities.map(\.name).sorted() == ["VocabularyWord", "WordReplacement"])
        #expect(stores.metrics.schema.entities.map(\.name).sorted() == ["SessionMetric"])
        #expect(try stores.transcription.mainContext.fetchCount(FetchDescriptor<Transcription>()) == 0)
        #expect(try stores.dictionary.mainContext.fetchCount(FetchDescriptor<VocabularyWord>()) == 0)
        #expect(try stores.dictionary.mainContext.fetchCount(FetchDescriptor<WordReplacement>()) == 0)
        #expect(try stores.metrics.mainContext.fetchCount(FetchDescriptor<SessionMetric>()) == 0)
    }

    private func expectStoreEntities(at url: URL, expected: [String]) throws {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: [NSReadOnlyPersistentStoreOption: true]
        )
        let hashes = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        #expect(hashes.keys.sorted() == expected)
    }
}

struct ModelStoreTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("rjt-model-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var filesystem = statfs()
        let result = url.path.withCString { statfs($0, &filesystem) }
        try #require(result == 0)
        let capacity = MemoryLayout.size(ofValue: filesystem.f_fstypename)
        let filesystemName = withUnsafePointer(to: &filesystem.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        try #require(filesystemName == "apfs")
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
func modelStoreTestDraft(id: UUID = UUID()) -> VoiceInkSessionMetricDraft {
    let transcript = Transcription(text: "one two three", duration: 6, transcriptionDuration: 2, transcriptionStatus: .completed)
    return VoiceInkSessionMetricPolicy.recorderDraft(
        transcriptionId: id, timestamp: Date(timeIntervalSince1970: 1_700_000_000), source: transcript,
        transcriptionModelName: "fixture model", powerModeName: nil, aiEnhancementModelName: nil
    )
}
