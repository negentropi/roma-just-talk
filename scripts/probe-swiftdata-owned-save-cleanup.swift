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
        var observations: [[String: Any]] = []
        for mode in ["old-delete", "delete-process-pending", "isolated-write-rollback"] {
            emit(["event": "case-start", "mode": mode])
            let observation = try observe(mode: mode, root: root)
            observations.append(observation)
            let data = try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: root.appendingPathComponent("\(mode).json"), options: .atomic)
        }
        let environment = ProcessInfo.processInfo.environment
        let report: [String: Any] = [
            "version": 1,
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
                "Only the isolated owned write context is rolled back; the unrelated UI edit is never rolled back."
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
    static func observe(mode: String, root: URL) throws -> [String: Any] {
        let directory = root.appendingPathComponent("stores", isDirectory: true)
            .appendingPathComponent("\(mode)-\(UUID().uuidString)", isDirectory: true)
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
        guard try uiContext.fetch(FetchDescriptor<ProbeTranscription>()).isEmpty else {
            throw ProbeError(message: "Seed unexpectedly contains a transcription")
        }
        let bystander = words[0]
        let dirtyText = "unsaved-bystander-\(mode)"
        bystander.text = dirtyText
        let writeContext = mode == "isolated-write-rollback" ? ModelContext(container) : uiContext
        writeContext.autosaveEnabled = false
        let owned = ProbeTranscription(text: "owned-probe-transcription")
        var snapshots: [[String: Any]] = []
        snapshots.append(state("before-insert", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
        writeContext.insert(owned)
        snapshots.append(state("after-insert-before-save", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
        var saveError: [String: Any] = [:]
        var saveSucceeded = false
        do {
            try writeContext.save()
            saveSucceeded = true
            snapshots.append(state("save-unexpectedly-succeeded", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
        } catch {
            let cocoa = error as NSError
            saveError = ["domain": cocoa.domain, "code": cocoa.code, "description": cocoa.localizedDescription]
            snapshots.append(state("save-threw-before-cleanup", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
            if mode == "isolated-write-rollback" {
                writeContext.rollback()
            } else {
                writeContext.delete(owned)
            }
            snapshots.append(state("after-delete-or-owned-rollback-before-fetch", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
            if mode == "delete-process-pending" {
                writeContext.processPendingChanges()
                snapshots.append(state("after-process-pending-before-fetch", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
            }
        }
        let sameContextRows = try writeContext.fetch(FetchDescriptor<ProbeTranscription>())
        snapshots.append(state("after-immediate-write-context-fetch", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
        let uiRows = try uiContext.fetch(FetchDescriptor<ProbeTranscription>())
        snapshots.append(state("after-ui-context-fetch", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
        let freshContext = ModelContext(container)
        freshContext.autosaveEnabled = false
        let freshRows = try freshContext.fetch(FetchDescriptor<ProbeTranscription>())
        let freshWords = try freshContext.fetch(FetchDescriptor<ProbeWord>())
        snapshots.append(state("after-fresh-context-fetch", ui: uiContext, write: writeContext, owned: owned, bystander: bystander))
        return [
            "mode": mode,
            "storeURL": store.path,
            "explicitPrivateStoreURL": true,
            "allowsSave": configuration.allowsSave,
            "isolatedWriteContext": writeContext !== uiContext,
            "saveSucceeded": saveSucceeded,
            "saveError": saveError,
            "immediateWriteContextCount": sameContextRows.count,
            "immediateWriteContextIncludesOwnedObject": sameContextRows.contains { $0 === owned },
            "uiContextCount": uiRows.count,
            "freshContextCount": freshRows.count,
            "freshContextWordValues": freshWords.map(\.text),
            "uiBystanderValue": bystander.text,
            "uiBystanderValueUnchanged": bystander.text == dirtyText,
            "snapshots": snapshots
        ]
    }

    @MainActor
    static func state(_ phase: String, ui: ModelContext, write: ModelContext, owned: ProbeTranscription, bystander: ProbeWord) -> [String: Any] {
        func describe(_ models: [any PersistentModel]) -> [[String: Any]] {
            models.map { model in
                ["type": String(describing: type(of: model)), "owned": (model as AnyObject) === owned,
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
                                    "ui": contextState(ui), "write": contextState(write),
                                    "ownedIsDeleted": owned.isDeleted, "ownedHasModelContext": owned.modelContext != nil,
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
}
