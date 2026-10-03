import Foundation
import SwiftData

@Model final class Transcription {
    var text: String = ""
    init() {}
}
@Model final class VocabularyWord {
    var word: String = ""
    init() {}
}
@Model final class WordReplacement {
    var originalText: String = ""
    var replacementText: String = ""
    init() {}
}
@Model final class SessionMetric {
    var wordCount: Int = 0
    init() {}
}

@main struct SchemaProbe {
    @MainActor
    static func main() async throws {
        let modes = ["combined-main", "combined-background", "separate-main", "separate-background", "full-background"]
        guard CommandLine.arguments.count == 3, modes.contains(CommandLine.arguments[1]) else {
            fputs("usage: schema-probe <mode> <fresh-store-directory>\n", stderr)
            exit(2)
        }
        let mode = CommandLine.arguments[1]
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let schemas = [Schema([Transcription.self]), Schema([VocabularyWord.self, WordReplacement.self]), Schema([SessionMetric.self])]
        let names = ["default", "dictionary", "stats"]
        let configurations = zip(names, schemas).map { name, subset in
            ModelConfiguration(name, schema: mode.hasPrefix("full") ? schema : subset,
                url: directory.appendingPathComponent(name + ".store"), cloudKitDatabase: .none)
        }
        let container: ModelContainer
        if mode.hasPrefix("separate") {
            container = try ModelContainer(for: schemas[2], configurations: configurations[2])
        } else {
            container = try ModelContainer(for: schema, configurations: configurations)
        }
        print("constructed \(mode) mainThread=\(Thread.isMainThread) entities \(container.schema.entities.map(\.name).sorted())")
        fflush(stdout)
        if mode.hasSuffix("background") {
            try await Task.detached {
                print("background mainThread=\(Thread.isMainThread)")
                let context = ModelContext(container)
                print("fetched SessionMetric \(try context.fetch(FetchDescriptor<SessionMetric>()).count)")
                fflush(stdout)
            }.value
        } else {
            let context = ModelContext(container)
            print("fetched SessionMetric \(try context.fetch(FetchDescriptor<SessionMetric>()).count)")
            fflush(stdout)
        }
        print("completed \(mode)")
    }
}
