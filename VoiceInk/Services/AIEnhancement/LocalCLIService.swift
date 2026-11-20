import Foundation
import VoiceInkCore

final class LocalCLIService {
    private static let shellPathQueue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).localcli.path")
    private static var cachedInteractiveLoginPATH: String?

    var commandTemplate: String {
        didSet {
            VoiceInkLocalCLIPreference.saveCommandTemplate(commandTemplate)
        }
    }

    var selectedTemplate: VoiceInkLocalCLITemplate {
        didSet {
            VoiceInkLocalCLIPreference.saveSelectedTemplate(selectedTemplate)
        }
    }

    var timeoutSeconds: Double {
        didSet {
            let clamped = VoiceInkLocalCLIPreference.boundedTimeoutSeconds(timeoutSeconds)
            if clamped != timeoutSeconds {
                timeoutSeconds = clamped
                return
            }
            VoiceInkLocalCLIPreference.saveTimeoutSeconds(timeoutSeconds)
        }
    }

    var isConfigured: Bool {
        VoiceInkLocalCLIPreference.isCommandConfigured(commandTemplate)
    }

    init() {
        selectedTemplate = VoiceInkLocalCLIPreference.selectedTemplate()
        commandTemplate = VoiceInkLocalCLIPreference.commandTemplate()
        timeoutSeconds = VoiceInkLocalCLIPreference.timeoutSeconds()
    }

    func loadTemplate(_ template: VoiceInkLocalCLITemplate, command: String? = nil) {
        selectedTemplate = template
        commandTemplate = command ?? template.commandTemplate
    }

    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        guard isConfigured else {
            throw VoiceInkLocalCLIExecutionError.commandNotConfigured
        }

        let commandTemplate = commandTemplate
        let timeout = timeoutSeconds
        return try await Self.onBlockingQueue(qos: .userInitiated) {
            try Self.runPrompt(commandTemplate: commandTemplate, systemPrompt: systemPrompt, userPrompt: userPrompt, timeout: timeout)
        }
    }

    enum SubscriptionProbe {
        case working
        case noSubscription
        /// Signed in, but the test request failed: maybe offline, a usage limit, or a CLI too old for the flags.
        case testRequestFailed
    }

    /// Whether Claude Code is signed in with a subscription and answers a real cleanup request.
    static func probeClaudeSubscription() async -> SubscriptionProbe {
        (try? await onBlockingQueue(qos: .utility) { () -> SubscriptionProbe in
            guard let status = Self.run(VoiceInkSubscriptionCleanupDefault.signInCheckCommand, environment: Self.shellEnvironment(), timeout: 10),
                  VoiceInkSubscriptionCleanupDefault.isSubscriptionSignIn(exitStatus: status.exitStatus, stdout: status.stdout)
            else {
                return .noSubscription
            }
            do {
                _ = try Self.runPrompt(
                    commandTemplate: VoiceInkSubscriptionCleanupDefault.subscriptionCommand,
                    systemPrompt: VoiceInkSubscriptionCleanupDefault.smokeTestSystemPrompt,
                    userPrompt: VoiceInkSubscriptionCleanupDefault.smokeTestUserPrompt,
                    timeout: VoiceInkSubscriptionCleanupDefault.adoptedTimeoutSeconds
                )
                return .working
            } catch {
                return .testRequestFailed
            }
        }) ?? .testRequestFailed
    }

    /// The runner blocks on semaphores for up to the timeout, so keep it off Swift's cooperative pool.
    private static func onBlockingQueue<T>(qos: DispatchQoS.QoSClass, _ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private static func runPrompt(commandTemplate: String, systemPrompt: String, userPrompt: String, timeout: Double) throws -> String {
        let fullPrompt = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        var environment = shellEnvironment()
        environment["VOICEINK_SYSTEM_PROMPT"] = systemPrompt
        environment["VOICEINK_USER_PROMPT"] = userPrompt
        environment["VOICEINK_FULL_PROMPT"] = fullPrompt

        guard let result = run(commandTemplate, environment: environment, stdin: Data(fullPrompt.utf8), timeout: timeout, requireCompleteOutput: true) else {
            throw VoiceInkLocalCLIExecutionError.timeout(seconds: timeout)
        }
        let stdout = VoiceInkLocalCLIPreference.cleanedOutput(result.stdout)
        if result.exitStatus != 0 {
            throw VoiceInkLocalCLIPreference.commandFailureError(
                terminationStatus: Int(result.exitStatus),
                stderr: VoiceInkLocalCLIPreference.cleanedOutput(result.stderr),
                commandTemplate: commandTemplate
            )
        }
        guard !stdout.isEmpty else {
            throw VoiceInkLocalCLIExecutionError.emptyOutput
        }
        return stdout
    }

    private static func shellEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = preferredPATH(fallback: environment["PATH"])
        return environment
    }

    private struct ShellResult {
        let exitStatus: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs `zsh -lc command` under one deadline. stdin is written and output read concurrently, so a full
    /// pipe can't stall the child or this caller. Returns nil if it can't launch or misses the deadline.
    private static func run(
        _ command: String,
        arguments: [String] = ["-lc"],
        environment: [String: String],
        stdin: Data? = nil,
        timeout: TimeInterval,
        requireCompleteOutput: Bool = false
    ) -> ShellResult? {
        let deadline = DispatchTime.now() + timeout
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = arguments + [command]
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let inputPipe = stdin.map { _ in Pipe() }
        process.standardInput = inputPipe ?? FileHandle.nullDevice

        let lock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()
        let drained = DispatchGroup()
        for (pipe, isStdout) in [(outputPipe, true), (errorPipe, false)] {
            drained.enter()
            var reachedEOF = false
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                lock.lock()
                defer { lock.unlock() }
                guard !reachedEOF else { return }
                if chunk.isEmpty {
                    reachedEOF = true
                    handle.readabilityHandler = nil
                    drained.leave()
                } else if isStdout {
                    stdoutData.append(chunk)
                } else {
                    stderrData.append(chunk)
                }
            }
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        if let stdin, let writer = inputPipe?.fileHandleForWriting {
            // A child that never reads stdin must not raise SIGPIPE in Roma when it exits.
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            DispatchQueue.global(qos: .utility).async {
                try? writer.write(contentsOf: stdin)
                try? writer.close()
            }
        }

        guard exited.wait(timeout: deadline) == .success else {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        // A background process the shell started can hold the pipes open. Output it may still write is lost,
        // so a rewrite counts only when complete; PATH discovery keeps what arrived (it has end markers).
        let complete = drained.wait(timeout: .now() + 1) == .success
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        guard complete || !requireCompleteOutput else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return ShellResult(
            exitStatus: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    private static func preferredPATH(fallback: String?) -> String {
        shellPathQueue.sync {
            if let cachedInteractiveLoginPATH {
                return cachedInteractiveLoginPATH
            }

            if let discovered = discoverPATHFromInteractiveLoginShell() {
                cachedInteractiveLoginPATH = discovered
                return discovered
            }

            return fallback?.isEmpty == false ? fallback! : "/usr/bin:/bin:/usr/sbin:/sbin"
        }
    }

    private static func discoverPATHFromInteractiveLoginShell() -> String? {
        guard let result = run(
            "echo __VOICEINK_PATH_START__; print -r -- $PATH; echo __VOICEINK_PATH_END__",
            arguments: ["-ilc"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 3
        ), result.exitStatus == 0 else {
            return nil
        }

        let output = result.stdout
        guard let startRange = output.range(of: "__VOICEINK_PATH_START__"),
              let endRange = output.range(of: "__VOICEINK_PATH_END__", range: startRange.upperBound..<output.endIndex)
        else {
            return nil
        }

        let pathSection = output[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pathSection.isEmpty ? nil : pathSection
    }
}
