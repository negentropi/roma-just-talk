import Foundation
import VoiceInkCore

final class LocalCLIService {
    private static let shellPathQueue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).localcli.path")
    private static var cachedLoginEnvironment: [String: String]?
    /// Read from the interactive login shell, where users export them, so Claude sees the same profile and proxy.
    private static let loginEnvironmentNames = ["PATH", "CLAUDE_CONFIG_DIR", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS"]

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

    func loadTemplate(_ template: VoiceInkLocalCLITemplate, adoptedAutomatically: Bool = false) {
        selectedTemplate = template
        commandTemplate = template.commandTemplate
        UserDefaults.standard.set(adoptedAutomatically, forKey: VoiceInkSubscriptionCleanupDefault.adoptedAutomaticallyKey)
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
        /// Team, Enterprise or MDM-managed Claude: the organization's hooks could receive dictation.
        case organizationManaged
        /// No answer yet: offline, a usage limit, a slow login shell, or a CLI too old for the flags.
        case retryLater
    }

    /// Whether Claude Code is signed in with a subscription and answers a real cleanup request.
    static func probeClaudeSubscription() async -> SubscriptionProbe {
        if managedClaudeSettingsExist() {
            return .organizationManaged
        }
        return (try? await onBlockingQueue(qos: .utility) { () -> SubscriptionProbe in
            // Without the user's own PATH a missing `claude` proves nothing (nvm and ~/.local/bin live there).
            guard Self.loginEnvironment() != nil else {
                return .retryLater
            }
            guard let status = Self.run(
                VoiceInkSubscriptionCleanupDefault.signInCheckCommand,
                arguments: ["-c"],
                environment: Self.shellEnvironment(),
                timeout: 10
            ) else {
                return .retryLater
            }
            switch VoiceInkSubscriptionCleanupDefault.signIn(exitStatus: status.exitStatus, stdout: status.stdout) {
            case .notSubscription:
                return .noSubscription
            case .organizationSubscription:
                return .organizationManaged
            case .unknown:
                return .retryLater
            case .personalSubscription:
                break
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
                return .retryLater
            }
        }) ?? .retryLater
    }

    private static func managedClaudeSettingsExist() -> Bool {
        VoiceInkSubscriptionCleanupDefault.managedSettingsPaths().contains(where: FileManager.default.fileExists(atPath:))
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
        let isSubscriptionCommand = commandTemplate == VoiceInkSubscriptionCleanupDefault.subscriptionCommand
        // Organization policy can appear after automatic adoption; its hooks would receive every dictation.
        // A user who picked the template by hand chose that.
        if isSubscriptionCommand,
           UserDefaults.standard.bool(forKey: VoiceInkSubscriptionCleanupDefault.adoptedAutomaticallyKey),
           managedClaudeSettingsExist() {
            throw VoiceInkLocalCLIExecutionError.executionFailed(VoiceInkSubscriptionCleanupDefault.organizationManagedMessage)
        }
        let fullPrompt = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        var environment = shellEnvironment()
        // Custom commands are promised these. The subscription command strips them with env -i anyway, and
        // skipping them keeps dictation out of same-user ps listings and under the argument size limit.
        if !isSubscriptionCommand {
            environment["VOICEINK_SYSTEM_PROMPT"] = systemPrompt
            environment["VOICEINK_USER_PROMPT"] = userPrompt
            environment["VOICEINK_FULL_PROMPT"] = fullPrompt
        }
        // The subscription command passes everything it needs itself; a login shell could only add a banner to stdout.
        let arguments = isSubscriptionCommand ? ["-c"] : ["-lc"]

        guard let result = run(
            commandTemplate,
            arguments: arguments,
            environment: environment,
            stdin: Data(fullPrompt.utf8),
            timeout: timeout,
            requireCompleteOutput: true
        ) else {
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
        if let loginEnvironment = loginEnvironment() {
            environment.merge(loginEnvironment) { _, login in login }
        } else if environment["PATH"]?.isEmpty != false {
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        }
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
        let stdoutDrained = DispatchGroup()
        let stderrDrained = DispatchGroup()
        for (pipe, isStdout) in [(outputPipe, true), (errorPipe, false)] {
            let drained = isStdout ? stdoutDrained : stderrDrained
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
            DispatchQueue.global(qos: .utility).async {
                writeAll(stdin, to: writer, until: deadline)
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
        // so a rewrite counts only when stdout is complete; PATH discovery keeps what arrived (it has end
        // markers). stderr is diagnostics only and never decides.
        let grace = DispatchTime.now() + 1
        let complete = stdoutDrained.wait(timeout: grace) == .success
        _ = stderrDrained.wait(timeout: grace)
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

    /// Non-blocking, so a child that holds stdin open without reading can't strand this thread past the
    /// deadline, and no SIGPIPE when the child exits first.
    private static func writeAll(_ data: Data, to writer: FileHandle, until deadline: DispatchTime) {
        let descriptor = writer.fileDescriptor
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count, DispatchTime.now() < deadline {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EAGAIN || errno == EINTR {
                    usleep(5_000)
                } else {
                    break
                }
            }
        }
        try? writer.close()
    }

    private static func loginEnvironment() -> [String: String]? {
        shellPathQueue.sync {
            if cachedLoginEnvironment == nil {
                cachedLoginEnvironment = discoverLoginEnvironment()
            }
            return cachedLoginEnvironment
        }
    }

    /// PATH and the `loginEnvironmentNames` values from an interactive login shell, or nil if it fails or is too slow.
    private static func discoverLoginEnvironment() -> [String: String]? {
        let prints = loginEnvironmentNames.map { "print -r -- \"\($0)=${\($0)}\"" }.joined(separator: "; ")
        guard let result = run(
            "echo __VOICEINK_ENV_START__; \(prints); echo __VOICEINK_ENV_END__",
            arguments: ["-ilc"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 3
        ), result.exitStatus == 0 else {
            return nil
        }

        let output = result.stdout
        guard let startRange = output.range(of: "__VOICEINK_ENV_START__\n"),
              let endRange = output.range(of: "__VOICEINK_ENV_END__", range: startRange.upperBound..<output.endIndex)
        else {
            return nil
        }

        var environment: [String: String] = [:]
        for line in output[startRange.upperBound..<endRange.lowerBound].split(separator: "\n") {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            if loginEnvironmentNames.contains(name), !value.isEmpty {
                environment[name] = value
            }
        }
        return environment["PATH"] == nil ? nil : environment
    }
}
