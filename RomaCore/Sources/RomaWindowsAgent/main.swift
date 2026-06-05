import Foundation
import RomaCore

@main
struct RomaWindowsAgent {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        do {
            try await run(arguments: arguments)
        } catch {
            printError(error)
            exit(1)
        }
    }

    private static func run(arguments: [String]) async throws {
        switch arguments.first {
        case "doctor":
            printDoctor()
        case "dictate":
            try await runDictation(arguments: Array(arguments.dropFirst()))
        case "listen":
            try await runListener(arguments: Array(arguments.dropFirst()))
        case "save-key-from-env":
            try saveKeyFromEnvironment(arguments: Array(arguments.dropFirst()))
        case "write-config":
            try writeConfiguration(arguments: Array(arguments.dropFirst()))
        case "config-doctor":
            try printConfigurationDoctor(arguments: Array(arguments.dropFirst()))
        default:
            printUsage()
        }
    }

    private static func printDoctor() {
        print("agent=roma-windows-agent")
        print("platform=\(platformName)")
        print("runtime_available=\(WindowsDictationRuntime.isRuntimeAvailable)")
        print("dictation_runtime=WindowsDictationRuntime")
        print("recorder=miniaudio")
        print("audio_format=pcm16_16000_mono")
        print("pre_roll_seconds=\(PreRollConfiguration().durationSeconds)")
        print("toggle_hotkey=RegisterHotKey Ctrl+Shift+R")
        print("hold_hook=WH_KEYBOARD_LL Ctrl+Shift+R")
        print("paste=win32_clipboard_sendinput")
        print("clipboard_restore=text_only_after_delay")
        WindowsDoctorOutput.runtimeDefaultProofLines.forEach { print($0) }
        print("secret_store=dpapi")
        print("config_default=\(RomaWindowsAgentConfiguration.defaultURL().path)")
        WindowsPermissionSurface.minimumMVP.proofOutputLines.forEach { print($0) }
    }

    private struct DictationRunContext {
        var configuration: RomaWindowsAgentConfiguration
        var options: RomaCommandLineOptions
        var transcriptionClient: RomaTranscriptionClient
        var shouldPaste: Bool
        var clipboardRestoreConfiguration: WindowsClipboardRestoreConfiguration
        var wordReplacements: [RomaWordReplacementRule]
        var request: WindowsDictationRuntimeRequest
    }

    private static func runDictation(arguments: [String]) async throws {
        try await runDictation(arguments: arguments, listenerSessionIndex: nil)
    }

    private static func runDictation(arguments: [String], listenerSessionIndex: Int?) async throws {
        let context = try makeDictationRunContext(
            arguments: arguments,
            listenerSessionIndex: listenerSessionIndex
        )

        printDictationHeader(context)
        let result = try await WindowsDictationRuntime.run(
            context.request,
            transcriptionService: context.transcriptionClient.service
        ) { event in
            printEvent(event)
        }
        printDictationResult(result, wordReplacementCount: context.wordReplacements.count)
    }

    private static func makeDictationRunContext(
        arguments: [String],
        listenerSessionIndex: Int?
    ) throws -> DictationRunContext {
        let options = RomaCommandLineOptions(arguments)
        let configuration = try loadConfiguration(from: options)
            .applyingOverrides(from: options)
        let outputURL = resolvedOutputURL(
            configuration: configuration,
            options: options,
            listenerSessionIndex: listenerSessionIndex
        )
        let transcriptionClient = try RomaTranscriptionClient.make(from: configuration)
        let shouldPaste = configuration.resolvedShouldPaste
        let clipboardRestoreConfiguration = configuration.clipboardRestoreConfiguration()
        let wordReplacements = configuration.wordReplacements
        let request = try configuration.windowsDictationRuntimeRequest(
            outputURL: outputURL,
            model: transcriptionClient.model
        )

        return DictationRunContext(
            configuration: configuration,
            options: options,
            transcriptionClient: transcriptionClient,
            shouldPaste: shouldPaste,
            clipboardRestoreConfiguration: clipboardRestoreConfiguration,
            wordReplacements: wordReplacements,
            request: request
        )
    }

    private static func printDictationHeader(_ context: DictationRunContext) {
        print("agent=roma-windows-agent")
        context.transcriptionClient.proofOutputLines(label: "transcription_client").forEach { print($0) }
        print(context.request.trigger.recordingModeProofLine)
        print("paste_requested=\(context.shouldPaste)")
        print("restore_clipboard_after_paste=\(context.clipboardRestoreConfiguration.restoreClipboard)")
        print("clipboard_restore_delay_seconds=\(context.clipboardRestoreConfiguration.restoreDelaySeconds)")
    }

    private static func printDictationResult(
        _ result: DictationPipelineResult,
        wordReplacementCount: Int
    ) {
        WindowsDictationRuntimeResultProof.outputLines(
            for: result,
            options: WindowsDictationRuntimeResultProofOptions(
                wordReplacementCount: wordReplacementCount
            )
        ).forEach { print($0) }
    }

    private static func runListener(arguments: [String]) async throws {
        let options = RomaCommandLineOptions(arguments)
        let maxSessions = try maxListenSessions(from: options)
        let previewConfiguration = try loadConfiguration(from: options)
            .applyingOverrides(from: options)
        try previewConfiguration.validateTranscriptionSettings()

        print("agent=roma-windows-agent")
        print("mode=listen")
        print("max_sessions=\(maxSessions.map(String.init) ?? "unbounded")")
        print("listener_capture_lifecycle=shared_pre_roll_runtime")

        if maxSessions == 0 {
            print("listen_completed_sessions=0")
            return
        }

        let context = try makeDictationRunContext(arguments: arguments, listenerSessionIndex: nil)
        printDictationHeader(context)
        let completedSessions = try await WindowsDictationRuntime.runListener(
            context.request,
            maxSessions: maxSessions,
            outputURLForSession: { sessionIndex in
                print("listen_session_start=\(sessionIndex)")
                return resolvedOutputURL(
                    configuration: context.configuration,
                    options: context.options,
                    listenerSessionIndex: sessionIndex
                )
            },
            transcriptionService: context.transcriptionClient.service,
            onEvent: { event in
                printEvent(event)
            },
            onSessionCompleted: { sessionIndex, result in
                printDictationResult(result, wordReplacementCount: context.wordReplacements.count)
                print("listen_session_completed=\(sessionIndex)")
            }
        )

        print("listen_completed_sessions=\(completedSessions)")
    }

    private static func maxListenSessions(from options: RomaCommandLineOptions) throws -> Int? {
        guard let value = options.optionalValue(after: "--max-sessions") else {
            return nil
        }
        guard let sessions = Int(value), sessions >= 0 else {
            throw RomaCommandLineOptionsError.invalidOptionValue("--max-sessions")
        }
        return sessions
    }

    private static func saveKeyFromEnvironment(arguments: [String]) throws {
        let options = RomaCommandLineOptions(arguments)
        let key = try options.value(after: "--key")
        let environmentName = try options.value(after: "--value-env")
        let directoryPath = options.optionalValue(after: "--secret-dir")
            ?? WindowsDPAPISecretStore.defaultDirectoryURL().path

        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let proof = try WindowsDPAPISecretStore(directoryURL: directoryURL)
            .saveFromEnvironment(key: key, environmentName: environmentName)
        proof.proofOutputLines.forEach { print($0) }
    }

    private static func writeConfiguration(arguments: [String]) throws {
        let options = RomaCommandLineOptions(arguments)
        let url = RomaWindowsAgentConfiguration.url(from: options)
        let configuration = try loadConfiguration(from: options, allowMissing: true)
            .applyingOverrides(from: options)

        try configuration.validateTranscriptionSettings()
        try configuration.write(to: url)

        print("config=\(url.path)")
        if configuration.usesWhisperCLI {
            print("transcription_client=whisper.cpp-cli")
            print("whisper_cli=\(try configuration.requireWhisperCLIPath())")
            print("whisper_model=\(try configuration.requireWhisperModelPath())")
            print("whisper_extra_args=\(configuration.whisperExtraArguments.count)")
        } else {
            print("transcription_client=openai-compatible")
            print("endpoint=\(try configuration.requireEndpoint())")
            print("model=\(try configuration.requireModel())")
            print("api_key_source=\(try configuration.apiKeySource().kind)")
        }
        print("paste=\(configuration.resolvedShouldPaste)")
        print("restore_clipboard_after_paste=\(configuration.clipboardRestoreConfiguration().restoreClipboard)")
        print("clipboard_restore_delay_seconds=\(configuration.clipboardRestoreConfiguration().restoreDelaySeconds)")
        print(try configuration.dictationTrigger().recordingModeProofLine)
        print("word_replacements=\(configuration.wordReplacements.count)")
        print("written=true")
    }

    private static func printConfigurationDoctor(arguments: [String]) throws {
        let options = RomaCommandLineOptions(arguments)
        let url = RomaWindowsAgentConfiguration.url(from: options)
        let configuration = try loadConfiguration(from: options, allowMissing: true)
            .applyingOverrides(from: options)

        try configuration.validateTranscriptionSettings()
        let setupProofLines = try RomaTranscriptionClient.runnableSetupProofLines(for: configuration)
        let transcriptionClient = try RomaTranscriptionClient.make(from: configuration)
        let clipboardRestoreConfiguration = configuration.clipboardRestoreConfiguration()

        print("agent=roma-windows-agent")
        print("config=\(url.path)")
        print("config_exists=\(FileManager.default.fileExists(atPath: url.path))")
        print("config_valid=true")
        transcriptionClient.proofOutputLines(label: "transcription_client").forEach { print($0) }
        for line in setupProofLines {
            print(line)
        }
        print(try configuration.dictationTrigger().recordingModeProofLine)
        print("paste=\(configuration.resolvedShouldPaste)")
        print("restore_clipboard_after_paste=\(clipboardRestoreConfiguration.restoreClipboard)")
        print("clipboard_restore_delay_seconds=\(clipboardRestoreConfiguration.restoreDelaySeconds)")
        print("word_replacements=\(configuration.wordReplacements.count)")
    }

    private static func printEvent(_ event: WindowsDictationRuntimeEvent) {
        print(event.proofOutputLine)
    }

    private static func resolvedOutputURL(
        configuration: RomaWindowsAgentConfiguration,
        options: RomaCommandLineOptions,
        listenerSessionIndex: Int?
    ) -> URL {
        if options.contains("--out"), let outputPath = configuration.outputPath {
            return URL(fileURLWithPath: outputPath)
        }
        if listenerSessionIndex != nil {
            return URL(fileURLWithPath: defaultOutputPath(sessionIndex: listenerSessionIndex))
        }
        return URL(fileURLWithPath: configuration.outputPath ?? defaultOutputPath())
    }

    private static func defaultOutputPath(sessionIndex: Int? = nil) -> String {
        let timestampMilliseconds = Int(Date().timeIntervalSince1970 * 1_000)
        let sessionSuffix = sessionIndex.map { "-session-\($0)" } ?? ""
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("roma-just-talk-\(timestampMilliseconds)\(sessionSuffix)-\(UUID().uuidString).wav")
            .path
    }

    private static func loadConfiguration(
        from options: RomaCommandLineOptions,
        allowMissing: Bool = true
    ) throws -> RomaWindowsAgentConfiguration {
        let url = RomaWindowsAgentConfiguration.url(from: options)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if allowMissing {
                return RomaWindowsAgentConfiguration()
            }
            throw RomaCommandLineOptionsError.missingOption("--config")
        }
        return try RomaWindowsAgentConfiguration.load(from: url)
    }

    private static var platformName: String {
        #if os(Windows)
        return "windows"
        #elseif os(macOS)
        return "macos"
        #elseif os(Linux)
        return "linux"
        #else
        return "unknown"
        #endif
    }

    private static func printUsage() {
        print("usage:")
        print("  RomaWindowsAgent doctor")
        print("  RomaWindowsAgent save-key-from-env --key groq --value-env GROQ_API_KEY [--secret-dir C:\\tmp\\roma-secrets]")
        print("  RomaWindowsAgent write-config --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq [--config C:\\tmp\\roma-agent.json] [--hold-hook] [--paste] [--no-restore-clipboard]")
        print("  RomaWindowsAgent write-config --whisper-cli C:\\path\\whisper-cli.exe --whisper-model C:\\path\\ggml-base.en.bin [--config C:\\tmp\\roma-agent.json] [--hold-hook] [--paste]")
        print("  RomaWindowsAgent config-doctor [--config C:\\tmp\\roma-agent.json]")
        print("  RomaWindowsAgent dictate [--config C:\\tmp\\roma-agent.json] [--endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env OPENAI_API_KEY] [--out proof.wav] [--seconds 2] [--replace \"just talk=roma-just-talk\"] [--paste] [--clipboard-restore-delay 2]")
        print("  RomaWindowsAgent dictate --whisper-cli C:\\path\\whisper-cli.exe --whisper-model C:\\path\\ggml-base.en.bin [--hold-hook] [--paste]")
        print("  RomaWindowsAgent dictate --hold-hook --timeout 15 --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq [--paste] [--no-restore-clipboard]")
        print("  RomaWindowsAgent listen --config C:\\tmp\\roma-agent.json [--max-sessions 3]")
    }

    private static func printError(_ error: Error) {
        let description: String
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            description = errorDescription
        } else {
            description = String(describing: error)
        }

        let line = "error=\(RomaCommandLineText.oneLine(description))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
