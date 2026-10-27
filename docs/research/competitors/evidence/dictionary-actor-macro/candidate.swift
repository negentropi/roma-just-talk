import Foundation
import Testing
final class WordReplacement { init(originalText: String, replacementText: String) {} }
struct FetchDescriptor<T> { init() {} }
final class ModelContext { func insert(_ row: WordReplacement) {}
func save() throws {}
func fetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] { [] } }
@MainActor enum DictionaryService { static func removeWordReplacement(_ row: WordReplacement, context: ModelContext) -> String? { nil } }
struct Probe {
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
