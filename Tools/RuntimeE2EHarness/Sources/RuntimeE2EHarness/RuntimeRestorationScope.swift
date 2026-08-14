import Darwin
import Foundation

struct RuntimeRestorationScope: Equatable {
    private static let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("roma-runtime-e2e-restoration", isDirectory: true)
    private static let journalNames = [
        "voiceink.json",
        "system-output.json",
        "false-trigger-side-effects.json"
    ]

    let id: String
    let directoryURL: URL

    var voiceInkJournalURL: URL {
        directoryURL.appendingPathComponent("voiceink.json")
    }

    var systemOutputJournalURL: URL {
        directoryURL.appendingPathComponent("system-output.json")
    }

    var falseTriggerSideEffectJournalURL: URL {
        directoryURL.appendingPathComponent("false-trigger-side-effects.json")
    }

    static func create() throws -> Self {
        let id = UUID().uuidString
        let directoryURL = rootURL.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return Self(id: id, directoryURL: directoryURL)
    }

    static func pending() throws -> [Self] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            guard isDirectory,
                  journalNames.contains(where: {
                      FileManager.default.fileExists(
                          atPath: url.appendingPathComponent($0).path
                      )
                  }) else {
                return nil
            }
            return Self(id: url.lastPathComponent, directoryURL: url)
        }.sorted { $0.id < $1.id }
    }

    static func verifyIsolation() throws {
        let first = try create()
        defer { try? first.finish() }
        let second = try create()
        defer { try? second.finish() }
        guard first.id != second.id,
              first.voiceInkJournalURL != second.voiceInkJournalURL,
              first.systemOutputJournalURL != second.systemOutputJournalURL,
              first.falseTriggerSideEffectJournalURL
                != second.falseTriggerSideEffectJournalURL else {
            throw RuntimeRestorationError.namespaceSelfCheckFailed
        }
    }

    func finish() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        guard remaining.isEmpty else {
            throw RuntimeRestorationError.pendingJournals(id, remaining.sorted())
        }
        try FileManager.default.removeItem(at: directoryURL)
    }
}

final class RuntimeHarnessMutationLock {
    private static let lockURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("roma-runtime-e2e.lock")
    private var descriptor: Int32?

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        release()
    }

    static func acquire() throws -> RuntimeHarnessMutationLock {
        try acquire(at: lockURL)
    }

    func release() {
        guard let descriptor else { return }
        _ = Darwin.lockf(descriptor, F_ULOCK, 0)
        _ = Darwin.close(descriptor)
        self.descriptor = nil
    }

    static func verifyExclusivity() throws {
        let checkURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "roma-runtime-e2e-lock-check-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: checkURL) }
        let first = try acquire(at: checkURL)
        if try lockCommandSucceeded(at: checkURL) {
            first.release()
            throw RuntimeRestorationError.lockSelfCheckFailed
        }
        first.release()
        guard try lockCommandSucceeded(at: checkURL) else {
            throw RuntimeRestorationError.lockSelfCheckFailed
        }
    }

    private static func acquire(at url: URL) throws -> RuntimeHarnessMutationLock {
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw RuntimeRestorationError.lockUnavailable(errno)
        }
        guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
            let failure = errno
            _ = Darwin.close(descriptor)
            if failure == EACCES || failure == EAGAIN {
                throw RuntimeRestorationError.anotherRunIsActive
            }
            throw RuntimeRestorationError.lockUnavailable(failure)
        }
        return RuntimeHarnessMutationLock(descriptor: descriptor)
    }

    private static func lockCommandSucceeded(at url: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lockf")
        process.arguments = ["-t", "0", url.path, "/usr/bin/true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

enum RuntimeRestorationCoordinator {
    static func restorePendingRun() throws -> [String] {
        let pending = try RuntimeRestorationScope.pending()
        guard pending.count <= 1 else {
            throw RuntimeRestorationError.multiplePendingRuns(pending.map(\.id))
        }
        guard let scope = pending.first else { return [] }

        var restored: [String] = []
        if FileManager.default.fileExists(atPath: scope.voiceInkJournalURL.path) {
            try RuntimeVoiceInkSession.restoreFromJournal(in: scope)
            restored.append("VoiceInk preferences, running state, and false-trigger artifacts")
        } else if FileManager.default.fileExists(
            atPath: scope.falseTriggerSideEffectJournalURL.path
        ) {
            try RuntimeVoiceInkSession.restoreOrphanedFalseTriggerArtifacts(in: scope)
            restored.append("false-trigger recording and history artifacts")
        }
        if FileManager.default.fileExists(atPath: scope.systemOutputJournalURL.path) {
            try RuntimeSystemOutputSession.restoreFromJournal(in: scope)
            restored.append("system output device and loopback controls")
        }
        try scope.finish()
        return restored
    }
}

enum RuntimeRestorationError: Error, CustomStringConvertible {
    case anotherRunIsActive
    case lockUnavailable(Int32)
    case multiplePendingRuns([String])
    case pendingJournals(String, [String])
    case lockSelfCheckFailed
    case namespaceSelfCheckFailed

    var description: String {
        switch self {
        case .anotherRunIsActive:
            return "Another state-mutating Runtime E2E process is active"
        case .lockUnavailable(let code):
            return "Could not acquire the Runtime E2E process lock (errno \(code))"
        case .multiplePendingRuns(let ids):
            return "Multiple interrupted Runtime E2E runs need manual inspection: \(ids.joined(separator: ", "))"
        case .pendingJournals(let id, let names):
            return "Runtime E2E run \(id) still has pending recovery files: \(names.joined(separator: ", "))"
        case .lockSelfCheckFailed:
            return "Runtime E2E process lock allowed concurrent ownership"
        case .namespaceSelfCheckFailed:
            return "Runtime E2E recovery namespaces reused a journal path"
        }
    }
}
