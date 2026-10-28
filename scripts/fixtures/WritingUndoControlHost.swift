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
        // Same registration-domain defaults the excluded VoiceInkApp init registers. Registration only:
        // persisted values still win, and launch-at-login/migration side effects stay out of this host.
        UserDefaults.standard.register(defaults: AppDefaults.registeredDefaults)

        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        func memoryConfiguration(_ name: String, _ models: [any PersistentModel.Type]) -> ModelConfiguration {
            ModelConfiguration(
                name,
                schema: Schema(models),
                isStoredInMemoryOnly: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }
        let container = try ModelContainer(
            for: schema,
            configurations:
                memoryConfiguration("default", [Transcription.self]),
                memoryConfiguration("dictionary", [VocabularyWord.self, WordReplacement.self]),
                memoryConfiguration("stats", [SessionMetric.self])
        )

        // Model managers are constructed only; nothing is refreshed, loaded or downloaded.
        let whisperModelManager = WhisperModelManager(
            modelsDirectory: output.appendingPathComponent("unused-models", isDirectory: true)
        )
        let fluidAudioModelManager = FluidAudioModelManager()
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: fluidAudioModelManager
        )

        let recorderUIManager = RecorderUIManager()
        let engine = VoiceInkEngine(
            modelContext: container.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager,
            qwenRuntimeResult: .failure(WritingUndoControlHostUnusedRuntime()),
            enhancementService: nil
        )
        recorderUIManager.configure(engine: engine, recorder: engine.recorder)
        engine.recorderUIManager = recorderUIManager

        self.output = output
        self.container = container
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.engine = engine
        self.recorderUIManager = recorderUIManager
        // The one shortcut manager for this process; it registers the configured global chord.
        self.shortcutManager = RecordingShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
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
            return try WritingUndoControlHostOwner(output: requireHostedOutputDirectory())
        } catch {
            FileHandle.standardError.write(Data("WritingUndoControlHost failed to start: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func requireHostedOutputDirectory() throws -> URL {
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
        _owner = StateObject(wrappedValue: WritingUndoControlHostOwner.launch())
    }

    var body: some Scene {
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
            guard owner.claimOracleRun() else { return }
            await WritingUndoControlOracle.run(owner: owner)
        }
    }
}
