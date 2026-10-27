import Foundation
import SwiftData
import Testing
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct DictionaryContextFreshnessTests {
        @Test @MainActor func applyingAnotherStoreNeverReusesThePreviousStoresRules() throws {
            let first = try DictionaryFreshnessFixture()
            let second = try DictionaryFreshnessFixture()
            try Self.deleteOwnedSetupEntry(in: first.context)
            first.context.insert(WordReplacement(originalText: "Roma", replacementText: "First store"))
            second.context.insert(WordReplacement(originalText: "Roma", replacementText: "Second store"))
            try first.context.save()
            try second.context.save()
            #expect(try first.context.fetch(FetchDescriptor<WordReplacement>()).map(\.replacementText) == ["First store"])
            #expect(try second.context.fetch(FetchDescriptor<WordReplacement>()).map(\.replacementText) == ["Second store"])
            #expect(DictionaryService.applyWordReplacements(to: "Roma", using: first.context) == "First store")
            #expect(DictionaryService.applyWordReplacements(to: "Roma", using: second.context) == "Second store")
        }

        @Test @MainActor func aFreshContextReadsChangesSavedByAnotherContext() throws {
            let fixture = try DictionaryFreshnessFixture(persistent: true)
            try Self.deleteOwnedSetupEntry(in: fixture.context)
            let initial = WordReplacement(originalText: "Roma", replacementText: "First value")
            fixture.context.insert(initial)
            try fixture.context.save()
            #expect(DictionaryService.applyWordReplacements(to: "Roma", using: fixture.context) == "First value")
            let writer = ModelContext(fixture.container)
            writer.autosaveEnabled = false
            let modified = try #require(writer.fetch(FetchDescriptor<WordReplacement>()).first)
            #expect(modified.id == initial.id)
            modified.replacementText = "Second value"
            try writer.save()
            let reader = ModelContext(fixture.container)
            reader.autosaveEnabled = false
            let observed = try #require(reader.fetch(FetchDescriptor<WordReplacement>()).first)
            #expect(observed.id == initial.id)
            #expect(observed.replacementText == "Second value")
            #expect(DictionaryService.applyWordReplacements(to: "Roma", using: reader) == "Second value")
        }

        @MainActor private static func deleteOwnedSetupEntry(in context: ModelContext) throws {
            // A real successful removal establishes the same initial app-cache boundary in old/new hosts.
            let entry = WordReplacement(originalText: "owned setup entry", replacementText: "temporary")
            context.insert(entry)
            try context.save()
            let removalAlert = DictionaryService.removeWordReplacement(entry, context: context)
            try #require(removalAlert == nil)
            try #require(context.fetch(FetchDescriptor<WordReplacement>()).isEmpty)
        }
    }
}

@MainActor
private final class DictionaryFreshnessFixture {
    let container: ModelContainer
    let context: ModelContext
    let directory: URL?

    init(persistent: Bool = false) throws {
        let schema = Schema([WordReplacement.self])
        let configuration: ModelConfiguration
        if persistent {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Dictionary-Freshness-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            self.directory = directory
            configuration = ModelConfiguration("DictionaryFreshness", schema: schema,
                url: directory.appendingPathComponent("dictionary.store"), cloudKitDatabase: .none)
            try #require(!configuration.isStoredInMemoryOnly && configuration.groupAppContainerIdentifier == nil)
        } else {
            directory = nil
            configuration = ModelConfiguration("DictionaryFreshness-\(UUID().uuidString)", schema: schema,
                isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    deinit {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}
