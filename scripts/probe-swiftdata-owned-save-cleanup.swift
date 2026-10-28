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
        if CommandLine.arguments.count == 4, CommandLine.arguments[2] == "--rule-case" {
            try RuleTransactionProbe.run(
                specification: CommandLine.arguments[3],
                root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            )
            return
        }
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

// Same eleven stored scalar types as WordReplacement; no application service or UI code.
@Model
final class ProbeRule {
    var id: UUID = UUID()
    var originalText: String = ""
    var replacementText: String = ""
    var dateAdded: Date = Date()
    var isEnabled: Bool = true
    var matchingKindRawValue: String?
    var approvalOriginRawValue: String?
    var sourceTranscriptionID: UUID?
    var sourceVariantRawValue: String?
    var literalOriginalText: String?
    var literalReplacementText: String?

    init(id: UUID, text: String) {
        self.id = id
        originalText = text
        replacementText = "replacement-" + text
        dateAdded = Date(timeIntervalSince1970: 1_700_000_000)
    }
}

private final class SaveNotificationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [[String: Any]] = []

    func record(_ notification: Notification) {
        // Notification payload only: never inspect a context or model before the selected query.
        let values = (notification.userInfo ?? [:]).map { key, value -> [String: Any] in
            var row: [String: Any] = ["key": String(describing: key), "type": String(describing: type(of: value))]
            if let identifiers = value as? [PersistentIdentifier] {
                row["identifiersBase64"] = identifiers.map { identifier in
                    (try? JSONEncoder().encode(identifier).base64EncodedString()) ?? "encoding-failed"
                }.sorted()
            } else {
                row["description"] = String(describing: value)
            }
            return row
        }.sorted { ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "") }
        lock.lock()
        observations.append(["name": notification.name.rawValue, "userInfo": values])
        lock.unlock()
    }

    func snapshot() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return observations
    }
}

private enum RuleTransactionProbe {
    static let aID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    static let bID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
    static let cID = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!

    @MainActor
    static func run(specification: String, root: URL) throws {
        let parts = specification.split(separator: "/").map(String.init)
        guard parts.count == 4,
              ["update", "toggle", "delete", "create", "batch"].contains(parts[0]),
              ["writable", "readonly"].contains(parts[1]),
              ["main", "explicit"].contains(parts[2]),
              ["fetch", "persisted", "pending-fetch", "pending-persisted", "model", "runloop-fetch"].contains(parts[3]) else {
            throw OwnedSaveCleanupProbe.ProbeError(message: "Unknown rule probe recipe")
        }
        let name = "rule-" + parts.joined(separator: "-")
        let output = root.appendingPathComponent(name + ".json")
        let directory = root.appendingPathComponent("stores", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("rule.store")
        let schema = Schema([ProbeRule.self, ProbeWord.self])
        try seed(url: url, schema: schema)
        let configuration = ModelConfiguration("rule", schema: schema, url: url,
                                               allowsSave: parts[1] == "writable", cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let caller = parts[2] == "main" ? container.mainContext : ModelContext(container)
        caller.autosaveEnabled = false
        let warm = try caller.fetch(FetchDescriptor<ProbeRule>())
        guard let a = warm.first(where: { $0.id == aID }), let b = warm.first(where: { $0.id == bID }), warm.count == 2,
              let word = try caller.fetch(FetchDescriptor<ProbeWord>()).first else {
            throw OwnedSaveCleanupProbe.ProbeError(message: "Rule caller did not warm exactly A+B and a word")
        }
        let aPersistentID = a.persistentModelID
        let bPersistentID = b.persistentModelID
        b.originalText = "caller-unsaved-B"
        word.text = "caller-unsaved-word"
        var report: [String: Any] = [
            "version": 1, "recipe": specification, "headSHA": ProcessInfo.processInfo.environment["PROBE_HEAD_SHA"] ?? "unprovided",
            "sourceSHA256": ProcessInfo.processInfo.environment["PROBE_SOURCE_SHA256"] ?? "unprovided",
            "pid": ProcessInfo.processInfo.processIdentifier, "storeURL": url.path,
            "allowsSave": configuration.allowsSave, "callerKind": parts[2], "autosaveEnabled": caller.autosaveEnabled,
            "ruleStoredFieldCount": 11, "callerWarmedRuleIDs": [aID.uuidString, bID.uuidString],
            "callerBeforeWrite": ["hasChanges": caller.hasChanges, "A": rule(a), "B": rule(b), "word": word.text],
            "callerSaveOrRollbackPerformed": false, "writerLocalStrongReferenceDroppedBeforeFirstObservation": true,
            "selectedFirstObservation": parts[3], "noSDKStateInspectionAfterWriterCleanupBeforeFirstObservation": true,
            "stage": "before-writer",
            "limits": ["Standalone same-scalar-shape SDK probe, not application services or UI regression proof.",
                       "A fresh store and separate process for every operation/save/reader/first-query combination.",
                       "Retained deleted-object property reads may abort a process; stage receipts and subprocess exit remain evidence.",
                       "No caller save/rollback, KVC, Core Data unwrapping or private refresh API."]
        ]
        try write(report, to: output)
        let notifications = SaveNotificationLog()
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) {
            notifications.record($0)
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let writeResult = try performWrite(operation: parts[0], container: container)
        // No context/model state getters here: make the chosen caller operation the first SDK observation.
        let firstRows: [ProbeRule]
        if parts[3] == "model" {
            let value = caller.model(for: aPersistentID)
            firstRows = (value as? ProbeRule).map { [$0] } ?? []
        } else {
            if parts[3].hasPrefix("pending-") { caller.processPendingChanges() }
            if parts[3] == "runloop-fetch" { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
            var descriptor = FetchDescriptor<ProbeRule>()
            descriptor.includePendingChanges = !parts[3].hasSuffix("persisted")
            firstRows = try caller.fetch(descriptor)
        }
        report["writer"] = writeResult
        report["writerDeallocatedBeforeFirstObservation"] = !(writeResult["weakWriterAliveAfterRelease"] as? Bool ?? true)
        report["didSaveNotifications"] = notifications.snapshot()
        report["firstQuery"] = ["count": firstRows.count, "includesRetainedAReference": firstRows.contains { $0 === a },
                                "includesRetainedBReference": firstRows.contains { $0 === b }]
        report["stage"] = "first-query-returned-before-model-property-reads"
        try write(report, to: output)
        report["retainedAAfterFirstQuery"] = rule(a)
        report["retainedBAfterFirstQuery"] = rule(b)
        report["firstQueryRows"] = firstRows.map(rule).sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        report["callerAfterFirstQuery"] = ["hasChanges": caller.hasChanges, "B": b.originalText, "word": word.text,
                                            "AIdentifierUnchanged": a.persistentModelID == aPersistentID,
                                            "BIdentifierUnchanged": b.persistentModelID == bPersistentID]
        report["stage"] = "retained-models-read"
        try write(report, to: output)
        // Persisted predicate membership and cached values are separate observations.
        var old = FetchDescriptor<ProbeRule>(predicate: #Predicate { $0.originalText == "saved-A" })
        old.includePendingChanges = false
        var updated = FetchDescriptor<ProbeRule>(predicate: #Predicate { $0.originalText == "writer-updated-A" })
        updated.includePendingChanges = false
        report["laterPersistedPredicateMembership"] = ["oldA": try caller.fetch(old).map { $0.id.uuidString }.sorted(),
                                                      "updatedA": try caller.fetch(updated).map { $0.id.uuidString }.sorted()]
        report["callerAfterLaterQueries"] = ["A": rule(a), "B": rule(b), "word": word.text, "hasChanges": caller.hasChanges]
        let fresh = ModelContext(container)
        fresh.autosaveEnabled = false
        report["freshContextRules"] = try fresh.fetch(FetchDescriptor<ProbeRule>()).map(rule).sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        report["freshContextWords"] = try fresh.fetch(FetchDescriptor<ProbeWord>()).map(\.text)
        let reopenedContainer = try ModelContainer(for: schema, configurations: [configuration])
        let reopened = ModelContext(reopenedContainer)
        reopened.autosaveEnabled = false
        report["separateContainerRules"] = try reopened.fetch(FetchDescriptor<ProbeRule>()).map(rule).sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        report["separateContainerWords"] = try reopened.fetch(FetchDescriptor<ProbeWord>()).map(\.text)
        report["stage"] = "completed"
        try write(report, to: output)
    }

    @MainActor
    private static func seed(url: URL, schema: Schema) throws {
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("rule", schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(ProbeRule(id: aID, text: "saved-A"))
        context.insert(ProbeRule(id: bID, text: "saved-B"))
        context.insert(ProbeWord(text: "saved-word"))
        try context.save()
    }

    @MainActor
    private static func performWrite(operation: String, container: ModelContainer) throws -> [String: Any] {
        var writer: ModelContext? = ModelContext(container)
        weak var weakWriter = writer
        writer!.autosaveEnabled = false
        try mutate(operation: operation, writer: writer!)
        var result: [String: Any] = ["operation": operation, "saveAttempted": true, "rollbackPerformed": false]
        do {
            try writer!.save()
            result["saveSucceeded"] = true
        } catch {
            let cocoa = error as NSError
            result["saveSucceeded"] = false
            result["saveError"] = ["domain": cocoa.domain, "code": cocoa.code, "description": cocoa.localizedDescription]
            writer!.rollback()
            result["rollbackPerformed"] = true
        }
        writer = nil
        result["weakWriterAliveAfterRelease"] = weakWriter != nil
        return result
    }

    @MainActor
    private static func mutate(operation: String, writer: ModelContext) throws {
        let rows = try writer.fetch(FetchDescriptor<ProbeRule>())
        guard let a = rows.first(where: { $0.id == aID }), rows.count == 2 else {
            throw OwnedSaveCleanupProbe.ProbeError(message: "Private writer did not fetch persisted A+B")
        }
        switch operation {
        case "update": a.originalText = "writer-updated-A"
        case "toggle": a.isEnabled = false
        case "delete": writer.delete(a)
        case "create": writer.insert(ProbeRule(id: cID, text: "writer-created-C"))
        case "batch":
            writer.delete(a)
            writer.insert(ProbeRule(id: cID, text: "writer-created-C"))
        default: throw OwnedSaveCleanupProbe.ProbeError(message: "Unknown operation")
        }
    }

    @MainActor
    private static func rule(_ value: ProbeRule) -> [String: Any] {
        func optional<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        return ["id": value.id.uuidString, "originalText": value.originalText, "replacementText": value.replacementText,
                "dateAdded": value.dateAdded.timeIntervalSince1970, "isEnabled": value.isEnabled,
                "matchingKindRawValue": optional(value.matchingKindRawValue), "approvalOriginRawValue": optional(value.approvalOriginRawValue),
                "sourceTranscriptionID": optional(value.sourceTranscriptionID?.uuidString), "sourceVariantRawValue": optional(value.sourceVariantRawValue),
                "literalOriginalText": optional(value.literalOriginalText), "literalReplacementText": optional(value.literalReplacementText),
                "isDeleted": value.isDeleted, "hasModelContext": value.modelContext != nil,
                "persistentIDBase64": (try? JSONEncoder().encode(value.persistentModelID).base64EncodedString()) ?? "encoding-failed"]
    }

    private static func write(_ report: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
