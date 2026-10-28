// TEST-ONLY integration host for the hosted language selection probe.
// A remote driver copies this file into a disposable candidate source tree in place of the
// production @main entry point. It mounts the unchanged LanguageSelectionView(.full) with the
// real multilingual catalog model; a separate oracle drives the actual picker and records what
// happens. This host makes no claim about the result. It is not part of the app target and must
// never ship.

#if !LOCAL_BUILD
#error("LanguageSelectionProbeHost is a test-only fixture and requires the LOCAL_BUILD condition.")
#endif

import AppKit
import Foundation
import SwiftData
import SwiftUI
import VoiceInkCore

enum LanguageSelectionProbeHostPresentation {
    static let windowTitle = "RJT language selection probe"
    static let rootAccessibilityID = "languageSelectionProbe.root"
    static let contentWidth: CGFloat = 560
    static let contentHeight: CGFloat = 300
}

struct LanguageSelectionProbeLaunchError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

@MainActor
final class LanguageSelectionProbeOwner: ObservableObject {
    /// The catalog entry the probe selects: the real multilingual Whisper Tiny metadata.
    static let probeModelName = "ggml-tiny"

    let output: URL
    let whisperModelManager: WhisperModelManager
    let fluidAudioModelManager: FluidAudioModelManager
    let transcriptionModelManager: TranscriptionModelManager
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private var didClaimOracleRun = false

    init(output: URL) throws {
        // Registration domain only, matching the values the excluded app init registers. This is not
        // AppDefaults.registerDefaults(): no launch-at-login change and no legacy preference migration.
        UserDefaults.standard.register(defaults: AppDefaults.registeredDefaults)

        // Empty in-memory dictionary store; nothing is persisted, synced or shared.
        let schema = Schema([WordReplacement.self, VocabularyWord.self])
        let configuration = ModelConfiguration(
            "dictionary",
            schema: schema,
            isStoredInMemoryOnly: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: configuration)

        // Real managers, constructed only. The Whisper models directory is never created, scanned,
        // refreshed, loaded or downloaded into.
        let whisperModelManager = WhisperModelManager(
            modelsDirectory: output.appendingPathComponent("unused-models", isDirectory: true)
        )
        let fluidAudioModelManager = FluidAudioModelManager()
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: fluidAudioModelManager
        )

        // Select the actual catalog entry through the public product path (metadata only, no download).
        guard let model = transcriptionModelManager.allAvailableModels.first(where: {
            $0.name == Self.probeModelName && $0.provider == .whisper && $0.isMultilingualModel
        }) else {
            throw LanguageSelectionProbeLaunchError(
                reason: "The catalog has no multilingual Whisper model named \(Self.probeModelName)."
            )
        }
        transcriptionModelManager.setDefaultTranscriptionModel(model)
        guard transcriptionModelManager.currentTranscriptionModel?.name == Self.probeModelName else {
            throw LanguageSelectionProbeLaunchError(
                reason: "Selecting \(Self.probeModelName) did not make it the current transcription model."
            )
        }

        // Start with no explicit language choice so the view resolves the registered English default.
        // Only this key is removed; every other setting is left as it is.
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
        UserDefaults.standard.synchronize()

        self.output = output
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.container = container
    }

    /// True only the first time it is called on this owner.
    func claimOracleRun() -> Bool {
        guard !didClaimOracleRun else { return false }
        didClaimOracleRun = true
        return true
    }

    /// Validates the hosted probe environment, then builds the one owner. Any failure ends the process.
    static func launch() -> LanguageSelectionProbeOwner {
        do {
            return try LanguageSelectionProbeOwner(output: requireHostedOutputDirectory())
        } catch {
            FileHandle.standardError.write(
                Data("LanguageSelectionProbeHost failed to start: \(error.localizedDescription)\n".utf8)
            )
            exit(2)
        }
    }

    private static func requireHostedOutputDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let required = [
            ("GITHUB_ACTIONS", "true"),
            ("RUNNER_ENVIRONMENT", "github-hosted"),
            ("RJT_LANGUAGE_SELECTION_PROBE", "1")
        ]
        for (key, value) in required where environment[key] != value {
            throw LanguageSelectionProbeLaunchError(
                reason: "\(key) must be \(value); this host runs only in the hosted language selection probe."
            )
        }

        // The isolated home must be real before any preference is read or written.
        _ = try requireExistingDirectory(named: "CFFIXED_USER_HOME", in: environment)
        return try requireExistingDirectory(named: "RJT_LANGUAGE_SELECTION_EVIDENCE", in: environment)
    }

    private static func requireExistingDirectory(named key: String, in environment: [String: String]) throws -> URL {
        guard let path = environment[key], path.hasPrefix("/") else {
            throw LanguageSelectionProbeLaunchError(reason: "\(key) must be an absolute path.")
        }
        guard !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw LanguageSelectionProbeLaunchError(reason: "\(key) must not contain . or .. components.")
        }
        // attributesOfItem does not follow a final symbolic link, so a symlinked entry is rejected here.
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard (attributes?[.type] as? FileAttributeType) == .typeDirectory else {
            throw LanguageSelectionProbeLaunchError(
                reason: "\(key) must name an existing directory that is not a symbolic link."
            )
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

@main
struct LanguageSelectionProbeHostApp: App {
    @StateObject private var owner: LanguageSelectionProbeOwner

    init() {
        _owner = StateObject(wrappedValue: LanguageSelectionProbeOwner.launch())
    }

    var body: some Scene {
        WindowGroup(LanguageSelectionProbeHostPresentation.windowTitle) {
            LanguageSelectionProbeRootView(owner: owner)
        }
        .windowResizability(.contentSize)
        .commands {
            // One probe window only; no New Window route.
            CommandGroup(replacing: .newItem) { }
        }
    }
}

private struct LanguageSelectionProbeRootView: View {
    @ObservedObject var owner: LanguageSelectionProbeOwner

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The unchanged product view; nothing is injected into it.
            LanguageSelectionView(
                transcriptionModelManager: owner.transcriptionModelManager,
                displayMode: .full
            )
            Spacer(minLength: 0)
        }
        .padding()
        .frame(
            width: LanguageSelectionProbeHostPresentation.contentWidth,
            height: LanguageSelectionProbeHostPresentation.contentHeight,
            alignment: .topLeading
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LanguageSelectionProbeHostPresentation.rootAccessibilityID)
        .task {
            guard owner.claimOracleRun() else { return }
            await LanguageSelectionProbeOracle.run(owner: owner)
        }
    }
}
