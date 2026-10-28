// TEST-ONLY integration host for the hosted Undo control check.
// A remote driver copies this file into a disposable candidate source tree and
// excludes only VoiceInk/VoiceInk.swift. Every production type stays unchanged.
// It is not part of the app target and must never ship.

#if !LOCAL_BUILD
#error("WritingUndoControlHost is a test-only fixture and requires the LOCAL_BUILD condition.")
#endif

import AppKit
import Foundation
import SwiftData
import SwiftUI
import VoiceInkCore
import VoiceInkQwen

enum WritingUndoControlHostPresentation {
    static let windowTitle = "RJT Undo control check"
    static let menuTitle = "RJT Undo check"
    static let menuSymbol = "arrow.uturn.backward.circle"
    static let initialStatus = "Waiting for the check to start."

    enum AccessibilityID {
        static let setup = "undoControlHost.setup"
        static let status = "undoControlHost.status"
        static let statusItem = "undoControlHost.statusItem"
    }
}

/// The Qwen runtime is never loaded here; the engine receives this explicit failure instead.
struct WritingUndoControlHostUnusedRuntime: LocalizedError {
    var errorDescription: String? {
        "The Undo control check does not use a speech runtime."
    }
}

struct WritingUndoControlHostLaunchError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// TEST-ONLY stage breadcrumbs for diagnosing a stalled hosted run. Each call synchronously
/// writes one small JSON file `<RJT_UNDO_CONTROLS_EVIDENCE>/progress/NNNN-<stage>.json` (temp file
/// then rename in that same directory) and one unbuffered stderr line, BEFORE the caller continues.
/// A stage is a fixed code label; no user text, clipboard, preference or source data is recorded.
/// Progress is never native proof: `result.json` from the Oracle remains the only acceptance receipt.
///
/// Failure is never silent. `record` throws through the caller's existing error path.
/// `recordDeferringFailure` (for places without an error path, and for the already-failing
/// catch path) reports to stderr at once and latches the failure, so every later `record`
/// throws; the Oracle success path always passes one `record` before writing its result.
@MainActor
enum WritingUndoControlHostProgress {
    struct Failure: LocalizedError, CustomStringConvertible {
        let reason: String
        var errorDescription: String? { reason }
        var description: String { reason }
    }

    /// Prior cap 1000 plus the Oracle's pre-input readiness calibration experiment: 7 native clicks per
    /// run, each now at most 6 read-only attempts x 134 records (67 marked AX/write pairs: 13 target/frame/root,
    /// 4 ancestors x 5 separately marked parent/role/identifier/title/pid provenance reads, 13 display/hit/window,
    /// 18 menu ancestry, 2 frame recheck, 1 observation write) + 2 post marks, replacing the former 88
    /// worst-case click records. Still finite and fail-closed.
    private static let maximumRecords = 1000 + 7 * (6 * 134 + 2 - 88)
    private static var sequence = 0
    private static var directory: URL?
    private static var firstFailure: String?
    private static var recordedOnce: Set<String> = []

    static func record(_ stage: String) throws {
        recordDeferringFailure(stage)
        if let firstFailure { throw Failure(reason: "Progress diagnostics failed at \(firstFailure)") }
    }

    static func recordDeferringFailure(_ stage: String) {
        do {
            try write(stage)
        } catch {
            let reason = "\(stage): \(error.localizedDescription)"
            if firstFailure == nil { firstFailure = reason }
            fputs("WritingUndoControlHost progress failed at \(reason)\n", stderr)
        }
    }

    /// For repeatedly evaluated SwiftUI bodies: records only the first evaluation.
    static func recordOnce(_ stage: String) {
        guard recordedOnce.insert(stage).inserted else { return }
        recordDeferringFailure(stage)
    }

    private static func write(_ stage: String) throws {
        let allowed = stage.utf8.allSatisfy { (0x61...0x7a).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2d || $0 == 0x2e }
        guard !stage.isEmpty, stage.utf8.count <= 120, allowed else {
            throw Failure(reason: "Invalid progress stage label.")
        }
        guard sequence < maximumRecords else { throw Failure(reason: "Progress record limit exceeded.") }
        sequence += 1
        let progress: URL
        if let directory {
            progress = directory
        } else {
            // The same validated hosted output the owner uses; the subdirectory must be new.
            progress = try WritingUndoControlHostOwner.requireHostedOutputDirectory()
                .appendingPathComponent("progress", isDirectory: true)
            try FileManager.default.createDirectory(at: progress, withIntermediateDirectories: false)
            directory = progress
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        let name = String(format: "%04ld-", sequence) + stage + ".json"
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "diagnosticOnly": true, "sequence": sequence, "stage": stage,
            "pid": Int(ProcessInfo.processInfo.processIdentifier), "systemUptime": uptime,
            "unixTime": Date().timeIntervalSince1970, "mainThread": Thread.isMainThread
        ] as [String: Any], options: [.sortedKeys])
        let temporary = progress.appendingPathComponent("." + name + ".tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.moveItem(at: temporary, to: progress.appendingPathComponent(name))
        guard fputs("RJT undo progress \(String(format: "%04ld", sequence)) \(stage) uptime=\(uptime)\n", stderr) >= 0 else {
            throw Failure(reason: "Progress stderr write failed.")
        }
    }
}

@MainActor
final class WritingUndoControlHostOwner: ObservableObject {
    let engine: VoiceInkEngine
    let recorderUIManager: RecorderUIManager
    let shortcutManager: RecordingShortcutManager
    let output: URL
    /// Fixture status only. It reports the check's progress and never product state.
    @Published var status = WritingUndoControlHostPresentation.initialStatus

    let container: ModelContainer
    let whisperModelManager: WhisperModelManager
    let fluidAudioModelManager: FluidAudioModelManager
    let transcriptionModelManager: TranscriptionModelManager
    private var didClaimOracleRun = false

    init(output: URL) throws {
        try WritingUndoControlHostProgress.record("owner.init.entry")
        // Same registration-domain defaults the excluded VoiceInkApp init registers. Registration only:
        // persisted values still win, and launch-at-login/migration side effects stay out of this host.
        try WritingUndoControlHostProgress.record("owner.register-defaults.before")
        UserDefaults.standard.register(defaults: AppDefaults.registeredDefaults)
        try WritingUndoControlHostProgress.record("owner.register-defaults.after")

        try WritingUndoControlHostProgress.record("owner.schema.before")
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        try WritingUndoControlHostProgress.record("owner.schema.after")
        func memoryConfiguration(_ name: String, _ models: [any PersistentModel.Type]) -> ModelConfiguration {
            ModelConfiguration(
                name,
                schema: Schema(models),
                isStoredInMemoryOnly: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }
        try WritingUndoControlHostProgress.record("owner.container.before")
        let container = try ModelContainer(
            for: schema,
            configurations:
                memoryConfiguration("default", [Transcription.self]),
                memoryConfiguration("dictionary", [VocabularyWord.self, WordReplacement.self]),
                memoryConfiguration("stats", [SessionMetric.self])
        )
        try WritingUndoControlHostProgress.record("owner.container.after")

        // Model managers are constructed only; nothing is refreshed, loaded or downloaded.
        try WritingUndoControlHostProgress.record("owner.whisper-model-manager.before")
        let whisperModelManager = WhisperModelManager(
            modelsDirectory: output.appendingPathComponent("unused-models", isDirectory: true)
        )
        try WritingUndoControlHostProgress.record("owner.whisper-model-manager.after")
        try WritingUndoControlHostProgress.record("owner.fluid-audio-model-manager.before")
        let fluidAudioModelManager = FluidAudioModelManager()
        try WritingUndoControlHostProgress.record("owner.fluid-audio-model-manager.after")
        try WritingUndoControlHostProgress.record("owner.transcription-model-manager.before")
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: fluidAudioModelManager
        )
        try WritingUndoControlHostProgress.record("owner.transcription-model-manager.after")

        try WritingUndoControlHostProgress.record("owner.recorder-ui-manager.before")
        let recorderUIManager = RecorderUIManager()
        try WritingUndoControlHostProgress.record("owner.recorder-ui-manager.after")
        try WritingUndoControlHostProgress.record("owner.engine.before")
        let engine = VoiceInkEngine(
            modelContext: container.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager,
            qwenRuntimeResult: .failure(WritingUndoControlHostUnusedRuntime()),
            enhancementService: nil
        )
        try WritingUndoControlHostProgress.record("owner.engine.after")
        try WritingUndoControlHostProgress.record("owner.configure.before")
        recorderUIManager.configure(engine: engine, recorder: engine.recorder)
        engine.recorderUIManager = recorderUIManager
        try WritingUndoControlHostProgress.record("owner.configure.after")

        self.output = output
        self.container = container
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.engine = engine
        self.recorderUIManager = recorderUIManager
        // The one shortcut manager for this process; it registers the configured global chord.
        try WritingUndoControlHostProgress.record("owner.shortcut-manager.before")
        self.shortcutManager = RecordingShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
        try WritingUndoControlHostProgress.record("owner.shortcut-manager.after")
        try WritingUndoControlHostProgress.record("owner.init.exit")
    }

    /// True only the first time it is called in this process's owner.
    func claimOracleRun() -> Bool {
        guard !didClaimOracleRun else { return false }
        didClaimOracleRun = true
        return true
    }

    /// Validates the hosted check environment, then builds the one owner. Any failure ends the process.
    static func launch() -> WritingUndoControlHostOwner {
        do {
            try WritingUndoControlHostProgress.record("owner.launch.entry")
            let owner = try WritingUndoControlHostOwner(output: requireHostedOutputDirectory())
            try WritingUndoControlHostProgress.record("owner.launch.exit")
            return owner
        } catch {
            FileHandle.standardError.write(Data("WritingUndoControlHost failed to start: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// File-private so only this owner and the progress recorder above reuse the one launch guard.
    fileprivate static func requireHostedOutputDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let required = [
            ("GITHUB_ACTIONS", "true"),
            ("RUNNER_ENVIRONMENT", "github-hosted"),
            ("RJT_UNDO_CONTROLS_CHECKS", "1")
        ]
        for (key, value) in required where environment[key] != value {
            throw WritingUndoControlHostLaunchError(reason: "\(key) must be \(value); this host runs only in the hosted Undo control check.")
        }

        guard let path = environment["RJT_UNDO_CONTROLS_EVIDENCE"], path.hasPrefix("/") else {
            throw WritingUndoControlHostLaunchError(reason: "RJT_UNDO_CONTROLS_EVIDENCE must be an absolute path.")
        }
        guard !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw WritingUndoControlHostLaunchError(reason: "RJT_UNDO_CONTROLS_EVIDENCE must not contain . or .. components.")
        }
        // attributesOfItem does not follow a final symbolic link.
        let type = try FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
        guard type == .typeDirectory else {
            throw WritingUndoControlHostLaunchError(reason: "RJT_UNDO_CONTROLS_EVIDENCE must be an existing directory.")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

@main
struct WritingUndoControlHostApp: App {
    @StateObject private var owner: WritingUndoControlHostOwner

    init() {
        // Earliest host code. StateObject is lazy, so owner.launch.entry may come later than app.init.exit.
        WritingUndoControlHostProgress.recordDeferringFailure("app.init.entry")
        _owner = StateObject(wrappedValue: WritingUndoControlHostOwner.launch())
        WritingUndoControlHostProgress.recordDeferringFailure("app.init.exit")
    }

    var body: some Scene {
        let _ = WritingUndoControlHostProgress.recordOnce("app.scene-body.first")
        WindowGroup(WritingUndoControlHostPresentation.windowTitle) {
            WritingUndoControlSetupView(owner: owner)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            // The only command: the unchanged product menu button.
            UndoLastWritingEditMenuButton(engine: owner.engine)
        } label: {
            Label(WritingUndoControlHostPresentation.menuTitle, systemImage: WritingUndoControlHostPresentation.menuSymbol)
                .accessibilityIdentifier(WritingUndoControlHostPresentation.AccessibilityID.statusItem)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct WritingUndoControlSetupView: View {
    @ObservedObject var owner: WritingUndoControlHostOwner

    var body: some View {
        let _ = WritingUndoControlHostProgress.recordOnce("view.body.first")
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        UndoLastWritingEditAvailabilityLabel()
                        ShortcutRecorder(action: .undoLastWritingEdit) {
                            owner.shortcutManager.updateShortcutStatus()
                        }
                        .controlSize(.small)
                    }
                } label: {
                    Text(UndoLastWritingEditPresentation.title)
                    Text(UndoLastWritingEditPresentation.scope)
                }
            }

            Section("Check") {
                Text(owner.status)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(WritingUndoControlHostPresentation.AccessibilityID.status)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 300)
        .environmentObject(owner.engine)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(WritingUndoControlHostPresentation.AccessibilityID.setup)
        .task {
            WritingUndoControlHostProgress.recordDeferringFailure("view.task.entry")
            guard owner.claimOracleRun() else {
                WritingUndoControlHostProgress.recordDeferringFailure("view.task.duplicate")
                return
            }
            WritingUndoControlHostProgress.recordDeferringFailure("view.task.claimed")
            await WritingUndoControlOracle.run(owner: owner)
        }
    }
}
