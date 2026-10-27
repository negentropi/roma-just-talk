import Foundation
import SwiftData

@Model
final class ProbeTranscription {
    var text: String
    init(text: String) { self.text = text }
}

@Model
final class ProbeWord {
    var text: String
    init(text: String) { self.text = text }
}

@main
struct OwnedSaveCleanupProbe {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw ProbeError(message: "Usage: probe <private-output-directory>")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let environment = ProcessInfo.processInfo.environment
        emit(["event": "probe-start", "headSHA": environment["PROBE_HEAD_SHA"] ?? "unprovided",
              "sourceSHA256": environment["PROBE_SOURCE_SHA256"] ?? "unprovided",
              "swiftCompiler": environment["PROBE_SWIFT_VERSION"] ?? "unprovided",
              "pid": ProcessInfo.processInfo.processIdentifier])
        let recipes = [
            Recipe(name: "old-ui-first-dirty", cleanup: .delete, uiFirst: true, dirtyWord: true, releaseWriter: false),
            Recipe(name: "old-write-first-dirty", cleanup: .delete, uiFirst: false, dirtyWord: true, releaseWriter: false),
            Recipe(name: "pending-ui-first-dirty", cleanup: .processPending, uiFirst: true, dirtyWord: true, releaseWriter: false),
            Recipe(name: "pending-write-first-dirty", cleanup: .processPending, uiFirst: false, dirtyWord: true, releaseWriter: false),
            Recipe(name: "isolated-ui-first-dirty", cleanup: .isolatedRollback, uiFirst: true, dirtyWord: true, releaseWriter: false),
            Recipe(name: "isolated-write-first-dirty", cleanup: .isolatedRollback, uiFirst: false, dirtyWord: true, releaseWriter: false),
            Recipe(name: "isolated-ui-first-unchanged", cleanup: .isolatedRollback, uiFirst: true, dirtyWord: false, releaseWriter: false),
            Recipe(name: "isolated-ui-first-dirty-release-writer", cleanup: .isolatedRollback, uiFirst: true, dirtyWord: true, releaseWriter: true)
        ]
        var observations: [[String: Any]] = []
        for recipe in recipes {
            emit(["event": "case-start", "recipe": recipe.description])
            let observation: [String: Any]
            do {
                observation = try observe(recipe: recipe, root: root)
            } catch {
                let cocoa = error as NSError
                observation = ["recipe": recipe.description, "caseAborted": true,
                               "errorDomain": cocoa.domain, "errorCode": cocoa.code,
                               "error": cocoa.localizedDescription]
                emit(observation)
            }
            observations.append(observation)
            let data = try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: root.appendingPathComponent("\(recipe.name).json"), options: .atomic)
        }
        let report: [String: Any] = [
            "version": 2,
            "headSHA": environment["PROBE_HEAD_SHA"] ?? "unprovided",
            "sourceSHA256": environment["PROBE_SOURCE_SHA256"] ?? "unprovided",
            "swiftCompiler": environment["PROBE_SWIFT_VERSION"] ?? "unprovided",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "schema": ["ProbeTranscription", "ProbeWord"],
            "observations": observations,
            "limits": [
                "Minimal two-model SDK probe; not the application schema or an app regression result.",
                "Every mode has its own newly seeded private store; CloudKit is disabled and autosave is off.",
                "Counts and states are observations. No mode is required to reproduce the application failure.",
                "Only the isolated owned write context is rolled back; the unrelated UI edit is never rolled back.",
                "No SDK state getters or other fetch run between cleanup and the selected first fetch.",
                "State getters after the first fetch may affect later queries; compare first-query results across fresh cases.",
                "The unchanged-word case matches that part of the app fixture; dirty-word cases add preservation stress.",
                "Swift reference identity is recorded without reading persistent model identifiers after invalidation."
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("report.json"), options: .atomic)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    @MainActor
    static func seedStore(at url: URL, schema: Schema) throws {
        let configuration = ModelConfiguration("probe", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(ProbeWord(text: "saved-word"))
        try context.save()
    }

    @MainActor
    static func observe(recipe: Recipe, root: URL) throws -> [String: Any] {
        let directory = root.appendingPathComponent("stores", isDirectory: true)
            .appendingPathComponent("\(recipe.name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appendingPathComponent("read-only.store")
        let schema = Schema([ProbeTranscription.self, ProbeWord.self])
        try seedStore(at: store, schema: schema)
        let configuration = ModelConfiguration("probe", schema: schema, url: store, allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let uiContext = ModelContext(container)
        uiContext.autosaveEnabled = false
        let words = try uiContext.fetch(FetchDescriptor<ProbeWord>())
        guard words.count == 1 else { throw ProbeError(message: "Seed must contain exactly one word") }
        let bystander = words[0]
        let expectedWord = recipe.dirtyWord ? "unsaved-bystander-\(recipe.name)" : "saved-word"
        if recipe.dirtyWord { bystander.text = expectedWord }
        var writeContext: ModelContext? = recipe.cleanup == .isolatedRollback ? ModelContext(container) : uiContext
        weak var weakWriteContext = writeContext
        writeContext!.autosaveEnabled = false
        let owned = ProbeTranscription(text: "owned-probe-transcription")
        var snapshots: [[String: Any]] = []
        snapshots.append(state("before-insert", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
        writeContext!.insert(owned)
        snapshots.append(state("after-insert-before-save", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
        var saveError: [String: Any] = [:]
        var saveSucceeded = false
        do {
            try writeContext!.save()
            saveSucceeded = true
            emit(["event": "save-succeeded", "recipe": recipe.name])
        } catch {
            let cocoa = error as NSError
            saveError = ["domain": cocoa.domain, "code": cocoa.code, "description": cocoa.localizedDescription]
            emit(["event": "save-error-before-cleanup", "recipe": recipe.name, "error": saveError])
            switch recipe.cleanup {
            case .delete:
                writeContext!.delete(owned)
            case .processPending:
                writeContext!.delete(owned)
                writeContext!.processPendingChanges()
            case .isolatedRollback:
                writeContext!.rollback()
            }
        }
        if recipe.releaseWriter { writeContext = nil }
        let weakWriterAliveBeforeFirstFetch = weakWriteContext != nil
        // Keep this first query adjacent to cleanup: SDK state inspection can itself settle changes.
        let firstRows = try (recipe.uiFirst ? uiContext : writeContext!).fetch(FetchDescriptor<ProbeTranscription>())
        let firstQuery: [String: Any] = ["target": recipe.uiFirst ? "ui" : "write", "count": firstRows.count,
                                       "includesOwnedSwiftObjectReference": firstRows.contains { $0 === owned }]
        emit(["event": "first-fetch", "recipe": recipe.name, "observation": firstQuery])
        snapshots.append(state("after-first-fetch", ui: uiContext, write: writeContext,
                               owned: recipe.releaseWriter ? nil : owned, bystander: bystander))
        let secondRows: [ProbeTranscription]?
        if recipe.uiFirst {
            secondRows = try writeContext?.fetch(FetchDescriptor<ProbeTranscription>())
        } else {
            secondRows = try uiContext.fetch(FetchDescriptor<ProbeTranscription>())
        }
        snapshots.append(state("after-second-fetch", ui: uiContext, write: writeContext,
                               owned: recipe.releaseWriter ? nil : owned, bystander: bystander))
        let freshContext = ModelContext(container)
        freshContext.autosaveEnabled = false
        let freshRows = try freshContext.fetch(FetchDescriptor<ProbeTranscription>())
        let freshWords = try freshContext.fetch(FetchDescriptor<ProbeWord>())
        snapshots.append(state("after-fresh-context-fetch", ui: uiContext, write: writeContext,
                               owned: recipe.releaseWriter ? nil : owned, bystander: bystander))
        return [
            "recipe": recipe.description,
            "storeURL": store.path,
            "explicitPrivateStoreURL": true,
            "allowsSave": configuration.allowsSave,
            "isolatedWriteContext": recipe.cleanup == .isolatedRollback,
            "writeContextWeaklyAliveBeforeFirstFetch": weakWriterAliveBeforeFirstFetch,
            "noSDKStateInspectionBetweenCleanupAndFirstFetch": true,
            "saveSucceeded": saveSucceeded,
            "saveError": saveError,
            "firstQuery": firstQuery,
            "secondQueryTarget": recipe.uiFirst ? "write" : "ui",
            "secondQueryCount": secondRows.map { $0.count as Any } ?? NSNull(),
            "freshContextCount": freshRows.count,
            "freshContextWordValues": freshWords.map(\.text),
            "uiBystanderValue": bystander.text,
            "uiBystanderValueUnchanged": bystander.text == expectedWord,
            "snapshots": snapshots
        ]
    }

    @MainActor
    static func state(_ phase: String, ui: ModelContext, write: ModelContext?, owned: ProbeTranscription?, bystander: ProbeWord) -> [String: Any] {
        func describe(_ models: [any PersistentModel]) -> [[String: Any]] {
            models.map { model in
                ["type": String(describing: type(of: model)), "owned": owned.map { (model as AnyObject) === $0 } ?? false,
                 "bystander": (model as AnyObject) === bystander, "isDeleted": model.isDeleted]
            }
        }
        func contextState(_ context: ModelContext) -> [String: Any] {
            ["hasChanges": context.hasChanges,
             "inserted": describe(context.insertedModelsArray),
             "deleted": describe(context.deletedModelsArray),
             "changed": describe(context.changedModelsArray)]
        }
        let result: [String: Any] = ["event": "snapshot", "phase": phase,
                                    "ui": contextState(ui), "write": write.map(contextState) as Any? ?? NSNull(),
                                    "ownedFlagsSkippedAfterWriterRelease": owned == nil,
                                    "ownedIsDeleted": owned.map { $0.isDeleted as Any } ?? NSNull(),
                                    "ownedHasModelContext": owned.map { ($0.modelContext != nil) as Any } ?? NSNull(),
                                    "bystanderIsDeleted": bystander.isDeleted, "bystanderValue": bystander.text]
        emit(result)
        return result
    }

    @MainActor
    static func emit(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    struct ProbeError: Error { let message: String }

    enum Cleanup: String { case delete, processPending, isolatedRollback }
    struct Recipe {
        let name: String
        let cleanup: Cleanup
        let uiFirst: Bool
        let dirtyWord: Bool
        let releaseWriter: Bool
        var description: [String: Any] {
            ["name": name, "cleanup": cleanup.rawValue, "firstQuery": uiFirst ? "ui" : "write",
             "dirtyBystander": dirtyWord, "releasePrivateWriterBeforeFirstQuery": releaseWriter,
             "transcriptionFetchBeforeAttemptedSave": false]
        }
    }
}
