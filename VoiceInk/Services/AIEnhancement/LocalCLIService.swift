import Foundation
import VoiceInkCore

final class LocalCLIService {
    private static let shellPathQueue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).localcli.path")
    private static var cachedLoginEnvironment: [String: String]?
    /// Read from the interactive login shell, where users export them, so Claude sees the same profile and proxy.
    private static let loginEnvironmentNames = ["PATH"] + VoiceInkSubscriptionCleanupDefault.passthroughEnvironmentNames

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
        // Read together on the main actor, where Settings changes them, so a template switch can't pair
        // one template's route with another's policy.
        let request: (isConfigured: Bool, command: String?, adoptedAutomatically: Bool, timeout: Double) = await MainActor.run {
            (
                self.isConfigured,
                self.selectedTemplate == .claudeSubscription ? nil : self.commandTemplate,
                UserDefaults.standard.bool(forKey: VoiceInkSubscriptionCleanupDefault.adoptedAutomaticallyKey),
                self.timeoutSeconds
            )
        }
        guard request.isConfigured else {
            throw VoiceInkLocalCLIExecutionError.commandNotConfigured
        }
        return try await Self.onBlockingQueue(qos: .userInitiated) {
            try Self.runPrompt(
                commandTemplate: request.command,
                adoptedAutomatically: request.adoptedAutomatically,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                timeout: request.timeout
            )
        }
    }

    enum SubscriptionProbe {
        case working
        case noSubscription
        /// Team, Enterprise or MDM/server-managed Claude: the organization's hooks could receive dictation.
        case organizationManaged
        /// No answer yet: offline, a usage limit, a slow login shell, or a CLI too old for the flags.
        case retryLater
    }

    /// Whether Claude Code is signed in with a personal subscription and answers a real cleanup request.
    static func probeClaudeSubscription() async -> SubscriptionProbe {
        (try? await onBlockingQueue(qos: .utility) { () -> SubscriptionProbe in
            // Without the user's own PATH a missing `claude` proves nothing (nvm and ~/.local/bin live there).
            guard let login = Self.loginEnvironment() else {
                return .retryLater
            }
            guard let claude = Self.claudeLaunch(login: login) else {
                return .noSubscription
            }
            if claude.organizationPolicyExists {
                return .organizationManaged
            }
            switch Self.signIn(claude) {
            case .notSubscription:
                return .noSubscription
            case .organizationSubscription:
                return .organizationManaged
            case .unknown, .otherSubscription:
                return .retryLater
            case .personalSubscription:
                break
            }
            do {
                _ = try Self.runPrompt(
                    commandTemplate: nil,
                    adoptedAutomatically: true,
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

    /// The runner blocks on semaphores for up to the timeout, so keep it off Swift's cooperative pool.
    private static func onBlockingQueue<T>(qos: DispatchQoS.QoSClass, _ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// The user's `claude`, resolved on their login PATH, with the only environment the subscription template gives it.
    private struct ClaudeLaunch {
        let executable: URL
        let environment: [String: String]

        var organizationPolicyExists: Bool {
            let configDirectory = environment["CLAUDE_CONFIG_DIR"] ?? "\(environment["HOME"] ?? NSHomeDirectory())/.claude"
            return VoiceInkSubscriptionCleanupDefault.managedSettingsPaths().contains(where: FileManager.default.fileExists(atPath:)) ||
                VoiceInkSubscriptionCleanupDefault.remoteSettingsHavePolicy(
                    FileManager.default.contents(atPath: "\(configDirectory)/remote-settings.json")
                )
        }
    }

    private static func claudeLaunch(login: [String: String]) -> ClaudeLaunch? {
        guard let path = login["PATH"],
              let directory = path.split(separator: ":").first(where: {
                  FileManager.default.isExecutableFile(atPath: "\($0)/claude")
              })
        else {
            return nil
        }
        let base = ProcessInfo.processInfo.environment
        var environment = VoiceInkSubscriptionCleanupDefault.fixedEnvironment
        for name in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG"] {
            environment[name] = base[name]
        }
        environment["PATH"] = path
        for name in VoiceInkSubscriptionCleanupDefault.passthroughEnvironmentNames {
            environment[name] = login[name]
        }
        return ClaudeLaunch(executable: URL(fileURLWithPath: "\(directory)/claude"), environment: environment)
    }

    private static func signIn(_ claude: ClaudeLaunch) -> VoiceInkSubscriptionCleanupDefault.SignIn {
        guard let status = run(
            claude.executable,
            arguments: VoiceInkSubscriptionCleanupDefault.authStatusArguments,
            environment: claude.environment,
            timeout: 10
        ) else {
            return .unknown
        }
        return VoiceInkSubscriptionCleanupDefault.signIn(exitStatus: status.exitStatus, stdout: status.stdout)
    }

    /// `commandTemplate` nil runs the subscription template: the user's `claude`, launched directly with checks.
    private static func runPrompt(
        commandTemplate: String?,
        adoptedAutomatically: Bool,
        systemPrompt: String,
        userPrompt: String,
        timeout: Double
    ) throws -> String {
        let fullPrompt = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        guard let commandTemplate else {
            guard let login = loginEnvironment() else {
                throw VoiceInkLocalCLIExecutionError.subscriptionRefused(VoiceInkSubscriptionCleanupDefault.shellPathUnavailableMessage)
            }
            // The PATH is cached per launch; re-read it once in case claude moved since. Suggest reinstalling only
            // when a fresh read still has no claude.
            let claude: ClaudeLaunch
            if let cached = claudeLaunch(login: login) {
                claude = cached
            } else if let refreshed = refreshedLoginEnvironment() {
                guard let found = claudeLaunch(login: refreshed) else {
                    throw VoiceInkLocalCLIExecutionError.subscriptionRefused(VoiceInkSubscriptionCleanupDefault.claudeNotFoundMessage)
                }
                claude = found
            } else {
                throw VoiceInkLocalCLIExecutionError.subscriptionRefused(VoiceInkSubscriptionCleanupDefault.shellPathUnavailableMessage)
            }
            // Checked every run: the sign-in or organization policy can change after the template was chosen.
            if let refusal = VoiceInkSubscriptionCleanupDefault.runRefusal(
                signIn: signIn(claude),
                adoptedAutomatically: adoptedAutomatically,
                organizationPolicyExists: claude.organizationPolicyExists
            ) {
                throw VoiceInkLocalCLIExecutionError.subscriptionRefused(refusal)
            }
            let result = run(
                claude.executable,
                arguments: VoiceInkSubscriptionCleanupDefault.cleanupArguments,
                environment: claude.environment,
                stdin: Data(fullPrompt.utf8),
                timeout: timeout,
                requireCompleteOutput: true
            )
            return try output(of: result, timeout: timeout, command: "claude", errorsOnStdout: true)
        }

        var environment = shellEnvironment()
        // Custom commands are promised these; the stock Claude and Codex templates read stdin only, and
        // leaving the variables out keeps dictation out of same-user ps listings.
        let stdinOnlyTemplates = [VoiceInkLocalCLITemplate.claude, .codex].map(\.commandTemplate)
        if !stdinOnlyTemplates.contains(commandTemplate) {
            environment["VOICEINK_SYSTEM_PROMPT"] = systemPrompt
            environment["VOICEINK_USER_PROMPT"] = userPrompt
            environment["VOICEINK_FULL_PROMPT"] = fullPrompt
        }
        let result = run(
            URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", commandTemplate],
            environment: environment,
            stdin: Data(fullPrompt.utf8),
            timeout: timeout,
            requireCompleteOutput: true
        )
        return try output(of: result, timeout: timeout, command: commandTemplate, errorsOnStdout: false)
    }

    /// `claude -p` prints API errors such as a usage limit on stdout, so that is the message to show.
    private static func output(of result: ShellResult?, timeout: Double, command: String, errorsOnStdout: Bool) throws -> String {
        guard let result else {
            throw VoiceInkLocalCLIExecutionError.timeout(seconds: timeout)
        }
        let stdout = VoiceInkLocalCLIPreference.cleanedOutput(result.stdout)
        if result.exitStatus != 0 {
            let stderr = VoiceInkLocalCLIPreference.cleanedOutput(result.stderr)
            throw VoiceInkLocalCLIPreference.commandFailureError(
                terminationStatus: Int(result.exitStatus),
                stderr: (errorsOnStdout && !stdout.isEmpty) || stderr.isEmpty ? stdout : stderr,
                commandTemplate: command
            )
        }
        guard !stdout.isEmpty else {
            throw VoiceInkLocalCLIExecutionError.emptyOutput
        }
        return stdout
    }

    /// Custom commands get the app environment plus only the user's PATH, as before.
    private static func shellEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let path = loginEnvironment()?["PATH"] {
            environment["PATH"] = path
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

    /// Runs `executable` under one deadline. stdin is written and output read concurrently, so a full
    /// pipe can't stall the child or this caller. Returns nil if it misses the deadline; a launch failure is exit 127.
    private static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        stdin: Data? = nil,
        timeout: TimeInterval,
        requireCompleteOutput: Bool = false
    ) -> ShellResult? {
        let deadline = DispatchTime.now() + timeout
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
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
            // Reported like a missing command, not as a timeout.
            return ShellResult(exitStatus: 127, stdout: "", stderr: "Could not start \(executable.path): \(error.localizedDescription)")
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

    /// Reads the login environment again; nil if that read fails, and then the last good one stays cached.
    private static func refreshedLoginEnvironment() -> [String: String]? {
        shellPathQueue.sync {
            guard let refreshed = discoverLoginEnvironment() else { return nil }
            cachedLoginEnvironment = refreshed
            return refreshed
        }
    }

    /// PATH and the `loginEnvironmentNames` values from the user's interactive login shell (or zsh for shells
    /// that reject `-ilc`), or nil if it fails or is too slow. `/usr/bin/env` prints them the same way everywhere.
    private static func discoverLoginEnvironment() -> [String: String]? {
        let loginShell = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_shell) } ?? "/bin/zsh"
        // Shells known to accept `-ilc` are read directly; a known shell that fails or is slow means "ask again
        // later", not a PATH without claude. Others (csh, tcsh, pwsh, nushell…) get zsh, which still loads the
        // system profile, as before.
        let acceptsILC = ["zsh", "bash", "sh", "dash", "ksh", "fish"].contains(URL(fileURLWithPath: loginShell).lastPathComponent)
        return discoverLoginEnvironment(shell: acceptsILC ? loginShell : "/bin/zsh")
    }

    private static func discoverLoginEnvironment(shell: String) -> [String: String]? {
        guard let result = run(
            URL(fileURLWithPath: shell),
            arguments: ["-ilc", "echo __VOICEINK_ENV_START__; /usr/bin/env; echo __VOICEINK_ENV_END__"],
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
