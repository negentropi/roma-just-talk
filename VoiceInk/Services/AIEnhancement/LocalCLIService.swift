import Foundation
import Darwin
import VoiceInkCore

final class LocalCLIService {
    struct RequestConfiguration: Sendable {
        let commandTemplate: String
        let timeoutSeconds: Double

        static func fromPreferences() -> Self {
            Self(
                commandTemplate: VoiceInkLocalCLIPreference.commandTemplate(),
                timeoutSeconds: VoiceInkLocalCLIPreference.timeoutSeconds()
            )
        }
    }

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

    func loadTemplate(_ template: VoiceInkLocalCLITemplate) {
        selectedTemplate = template
        commandTemplate = template.commandTemplate
    }

    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        let result = try await Self.execute(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: RequestConfiguration(commandTemplate: commandTemplate, timeoutSeconds: timeoutSeconds)
        )
        let cleaned = VoiceInkLocalCLIPreference.cleanedOutput(result)
        guard !cleaned.isEmpty else { throw VoiceInkLocalCLIExecutionError.emptyOutput }
        return cleaned
    }

    static func execute(
        systemPrompt: String,
        userPrompt: String,
        configuration: RequestConfiguration
    ) async throws -> String {
        try Task.checkCancellation()
        guard VoiceInkLocalCLIPreference.isCommandConfigured(configuration.commandTemplate) else {
            throw VoiceInkLocalCLIExecutionError.commandNotConfigured
        }
        guard configuration.timeoutSeconds.isFinite, configuration.timeoutSeconds > 0 else {
            throw VoiceInkLocalCLIExecutionError.executionFailed("Local CLI timeout must be positive and finite.")
        }
        guard !configuration.commandTemplate.utf8.contains(0),
              !systemPrompt.utf8.contains(0), !userPrompt.utf8.contains(0) else {
            throw VoiceInkLocalCLIExecutionError.executionFailed("Local CLI command and prompts cannot contain NUL bytes.")
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = try await preferredPATH(fallback: environment["PATH"])
        try Task.checkCancellation()
        environment["VOICEINK_SYSTEM_PROMPT"] = systemPrompt
        environment["VOICEINK_USER_PROMPT"] = userPrompt
        let fullPrompt = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        environment["VOICEINK_FULL_PROMPT"] = fullPrompt
        let output = try await CommandRun(
            arguments: ["-lc", configuration.commandTemplate],
            environment: environment,
            input: Data(fullPrompt.utf8),
            timeout: configuration.timeoutSeconds
        ).run()
        try Task.checkCancellation()
        let stderr = VoiceInkLocalCLIPreference.cleanedOutput(String(data: output.stderr, encoding: .utf8) ?? "")
        guard output.exitStatus == 0 else {
            throw VoiceInkLocalCLIPreference.commandFailureError(
                terminationStatus: Int(output.exitStatus), stderr: stderr,
                commandTemplate: configuration.commandTemplate
            )
        }
        return String(data: output.stdout, encoding: .utf8) ?? ""
    }

    private static func preferredPATH(fallback: String?) async throws -> String {
        if let cached = shellPathQueue.sync(execute: { cachedInteractiveLoginPATH }) { return cached }
        if let discovered = try await discoverPATHFromInteractiveLoginShell() {
            shellPathQueue.sync { cachedInteractiveLoginPATH = discovered }
            return discovered
        }
        return fallback?.isEmpty == false ? fallback! : "/usr/bin:/bin:/usr/sbin:/sbin"
    }

    private static func discoverPATHFromInteractiveLoginShell() async throws -> String? {
        let result: CommandRun.Output
        do {
            result = try await CommandRun(
                arguments: ["-ilc", "echo __VOICEINK_PATH_START__; print -r -- $PATH; echo __VOICEINK_PATH_END__"],
                environment: nil, input: Data(), timeout: 3
            ).run()
        } catch is CancellationError {
            throw CancellationError()
        } catch { return nil }
        guard result.exitStatus == 0 else { return nil }
        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        let startMarker = "__VOICEINK_PATH_START__"
        let endMarker = "__VOICEINK_PATH_END__"
        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker, range: startRange.upperBound..<output.endIndex) else {
            return nil
        }
        let path = output[startRange.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private final class CommandRun: @unchecked Sendable {
        struct Output: Sendable {
            let stdout: Data
            let stderr: Data
            let exitStatus: Int32
        }

        private let queue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).localcli.run")
        private let arguments: [String]
        private let environment: [String: String]
        private let inputPipe = Pipe()
        private let outputPipe = Pipe()
        private let errorPipe = Pipe()
        private let input: Data
        private let timeout: Double
        // This queue owns all lifetime state, including cancellation before launch.
        private var continuation: CheckedContinuation<Output, Error>?
        private var result: Result<Output, Error>?
        private var pendingError: Error?
        private var childPID: pid_t?
        private var exitStatus: Int32?
        private var inputOffset = 0
        private var stdout = Data()
        private var stderr = Data()
        private var inputClosed = false
        private var outputClosed = false
        private var errorClosed = false
        private var inputSource: DispatchSourceWrite?
        private var outputSource: DispatchSourceRead?
        private var errorSource: DispatchSourceRead?
        private var timer: DispatchSourceTimer?
        private var exitTimer: DispatchSourceTimer?

        init(arguments: [String], environment: [String: String]?, input: Data, timeout: Double) {
            self.arguments = ["/bin/zsh"] + arguments
            self.environment = environment ?? ProcessInfo.processInfo.environment
            self.input = input
            self.timeout = timeout
        }

        func run() async throws -> Output {
            try await withTaskCancellationHandler {
                do {
                    try Task.checkCancellation()
                    let output = try await withCheckedThrowingContinuation { continuation in
                        queue.async { self.start(continuation) }
                    }
                    try Task.checkCancellation()
                    return output
                } catch {
                    try Task.checkCancellation()
                    throw error
                }
            } onCancel: {
                self.queue.async { self.stop(with: CancellationError()) }
            }
        }

        private func start(_ continuation: CheckedContinuation<Output, Error>) {
            if let result { continuation.resume(with: result); return }
            self.continuation = continuation
            do {
                guard !arguments.contains(where: { $0.utf8.contains(0) }),
                      !environment.contains(where: { $0.key.contains("=") || $0.key.utf8.contains(0) || $0.value.utf8.contains(0) }) else {
                    throw VoiceInkLocalCLIExecutionError.executionFailed("Local CLI arguments and environment cannot contain NUL bytes or invalid environment names.")
                }
                var disposition = sigaction()
                guard sigaction(SIGCHLD, nil, &disposition) == 0 else { throw ioError() }
                guard unsafeBitCast(disposition.__sigaction_u.__sa_handler, to: UInt.self) == unsafeBitCast(SIG_DFL, to: UInt.self),
                      disposition.sa_flags & SA_NOCLDWAIT == 0 else {
                    throw VoiceInkLocalCLIExecutionError.executionFailed("Local CLI cannot own child cleanup while the app overrides SIGCHLD handling.")
                }
                try configureIO()
                let deadline = DispatchSource.makeTimerSource(queue: queue)
                deadline.schedule(deadline: .now() + timeout)
                deadline.setEventHandler { [weak self] in
                    guard let self else { return }
                    self.stop(with: VoiceInkLocalCLIExecutionError.timeout(seconds: self.timeout))
                }
                timer = deadline
                deadline.resume()
                childPID = try spawn()
                try? inputPipe.fileHandleForReading.close()
                try? outputPipe.fileHandleForWriting.close()
                try? errorPipe.fileHandleForWriting.close()
                if input.isEmpty { closeInput() }
                let exitTimer = DispatchSource.makeTimerSource(queue: queue)
                exitTimer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(2))
                exitTimer.setEventHandler { [weak self] in self?.reapIfExited() }
                self.exitTimer = exitTimer
                exitTimer.resume()
            } catch let error as VoiceInkLocalCLIExecutionError {
                stop(with: error)
            } catch {
                stop(with: VoiceInkLocalCLIExecutionError.executionFailed(error.localizedDescription))
            }
        }

        private func spawn() throws -> pid_t {
            var actions: posix_spawn_file_actions_t?
            try checkSpawnError(posix_spawn_file_actions_init(&actions))
            defer { posix_spawn_file_actions_destroy(&actions) }
            for (handle, target) in [
                (inputPipe.fileHandleForReading, STDIN_FILENO),
                (outputPipe.fileHandleForWriting, STDOUT_FILENO),
                (errorPipe.fileHandleForWriting, STDERR_FILENO)
            ] {
                try checkSpawnError(posix_spawn_file_actions_adddup2(&actions, handle.fileDescriptor, target))
            }
            var attributes: posix_spawnattr_t?
            try checkSpawnError(posix_spawnattr_init(&attributes))
            defer { posix_spawnattr_destroy(&attributes) }
            var mask = sigset_t()
            sigemptyset(&mask)
            try checkSpawnError(posix_spawnattr_setsigmask(&attributes, &mask))
            var defaults = sigset_t()
            sigfillset(&defaults)
            try checkSpawnError(posix_spawnattr_setsigdefault(&attributes, &defaults))
            try checkSpawnError(posix_spawnattr_setflags(
                &attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
            ))
            let arguments = try cStrings(arguments)
            defer { arguments.forEach { free($0) } }
            let environment = try cStrings(environment.map { $0.key + "=" + $0.value })
            defer { environment.forEach { free($0) } }
            var argv = arguments + [nil]
            var envp = environment + [nil]
            var pid = pid_t()
            let error = argv.withUnsafeMutableBufferPointer { arguments in
                envp.withUnsafeMutableBufferPointer { environment in
                    posix_spawn(&pid, "/bin/zsh", &actions, &attributes, arguments.baseAddress!, environment.baseAddress!)
                }
            }
            try checkSpawnError(error)
            return pid
        }

        private func cStrings(_ strings: [String]) throws -> [UnsafeMutablePointer<CChar>?] {
            var result: [UnsafeMutablePointer<CChar>?] = []
            for string in strings {
                guard let copy = strdup(string) else {
                    result.forEach { free($0) }
                    throw VoiceInkLocalCLIExecutionError.executionFailed("Cannot allocate Local CLI command arguments.")
                }
                result.append(copy)
            }
            return result
        }

        private func checkSpawnError(_ error: Int32) throws {
            guard error == 0 else {
                throw VoiceInkLocalCLIExecutionError.executionFailed(String(cString: strerror(error)))
            }
        }

        private func configureIO() throws {
            for handle in [inputPipe.fileHandleForWriting, outputPipe.fileHandleForReading, errorPipe.fileHandleForReading] {
                let descriptor = handle.fileDescriptor
                let flags = fcntl(descriptor, F_GETFL)
                guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else { throw ioError() }
            }
            guard fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) >= 0 else { throw ioError() }
            let inputSource = DispatchSource.makeWriteSource(fileDescriptor: inputPipe.fileHandleForWriting.fileDescriptor, queue: queue)
            inputSource.setEventHandler { [weak self] in self?.writeInput() }
            inputSource.setCancelHandler { [handle = inputPipe.fileHandleForWriting] in try? handle.close() }
            self.inputSource = inputSource
            inputSource.resume()
            let outputSource = DispatchSource.makeReadSource(fileDescriptor: outputPipe.fileHandleForReading.fileDescriptor, queue: queue)
            outputSource.setEventHandler { [weak self] in self?.readOutput(isError: false) }
            outputSource.setCancelHandler { [handle = outputPipe.fileHandleForReading] in try? handle.close() }
            self.outputSource = outputSource
            outputSource.resume()
            let errorSource = DispatchSource.makeReadSource(fileDescriptor: errorPipe.fileHandleForReading.fileDescriptor, queue: queue)
            errorSource.setEventHandler { [weak self] in self?.readOutput(isError: true) }
            errorSource.setCancelHandler { [handle = errorPipe.fileHandleForReading] in try? handle.close() }
            self.errorSource = errorSource
            errorSource.resume()
        }

        private func writeInput() {
            guard pendingError == nil, result == nil, childPID != nil, !inputClosed else { return }
            let count = input.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress, inputOffset < bytes.count else { return 0 }
                return Darwin.write(inputPipe.fileHandleForWriting.fileDescriptor, base.advanced(by: inputOffset), min(65_536, bytes.count - inputOffset))
            }
            if count > 0 { inputOffset += count }
            else if count < 0, errno != EAGAIN, errno != EINTR {
                if errno == EPIPE { closeInput(); return }
                stop(with: ioError()); return
            }
            if inputOffset == input.count { closeInput() }
        }

        private func readOutput(isError: Bool) {
            guard pendingError == nil, result == nil, !(isError ? errorClosed : outputClosed) else { return }
            let handle = isError ? errorPipe.fileHandleForReading : outputPipe.fileHandleForReading
            var buffer = [UInt8](repeating: 0, count: 32_768)
            var received = 0
            while received < 65_536 {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
                if count > 0 {
                    if isError { stderr.append(contentsOf: buffer.prefix(count)) }
                    else { stdout.append(contentsOf: buffer.prefix(count)) }
                    received += count
                } else if count == 0 {
                    closeOutput(isError: isError)
                    finishIfReady()
                    return
                } else {
                    if errno == EINTR { return }
                    if errno != EAGAIN { stop(with: ioError()) }
                    return
                }
            }
        }

        private func reapIfExited() {
            guard result == nil, let pid = childPID else { return }
            var status = Int32()
            let observed = waitpid(pid, &status, WNOHANG)
            guard observed != 0 else { return }
            if observed < 0 {
                if errno == EINTR { return }
                let error = ioError()
                childPID = nil
                exitTimer?.cancel(); exitTimer = nil
                finish(.failure(pendingError ?? error))
                return
            }
            childPID = nil
            exitTimer?.cancel(); exitTimer = nil
            exitStatus = status & 0x7f == 0 ? (status >> 8) & 0xff : status & 0x7f
            closeInput()
            if let pendingError { finish(.failure(pendingError)); return }
            readOutput(isError: false)
            readOutput(isError: true)
            finishIfReady()
        }

        private func stop(with error: Error) {
            guard result == nil else { return }
            if pendingError == nil || error is CancellationError { pendingError = error }
            timer?.cancel(); timer = nil
            closeInput()
            closeOutput(isError: false)
            closeOutput(isError: true)
            reapIfExited()
            guard result == nil else { return }
            guard let pid = childPID else { finish(.failure(pendingError ?? error)); return }
            _ = Darwin.kill(pid, SIGTERM)
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.result == nil else { return }
                self.reapIfExited()
                guard self.result == nil, let pid = self.childPID else { return }
                // Reaping and signaling share this queue; an unreaped child reserves its PID.
                _ = Darwin.kill(pid, SIGKILL)
            }
        }

        private func finishIfReady() {
            guard let exitStatus, outputClosed, errorClosed, result == nil else { return }
            finish(.success(Output(stdout: stdout, stderr: stderr, exitStatus: exitStatus)))
        }

        private func finish(_ result: Result<Output, Error>) {
            guard self.result == nil else { return }
            self.result = result
            timer?.cancel(); timer = nil
            exitTimer?.cancel(); exitTimer = nil
            closeInput()
            closeOutput(isError: false)
            closeOutput(isError: true)
            try? inputPipe.fileHandleForReading.close()
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            continuation?.resume(with: result)
            continuation = nil
        }

        private func closeInput() {
            guard !inputClosed else { return }
            inputClosed = true
            if let source = inputSource { source.cancel(); inputSource = nil }
            else { try? inputPipe.fileHandleForWriting.close() }
        }

        private func closeOutput(isError: Bool) {
            if isError {
                guard !errorClosed else { return }
                errorClosed = true
                if let source = errorSource { source.cancel(); errorSource = nil }
                else { try? errorPipe.fileHandleForReading.close() }
            } else {
                guard !outputClosed else { return }
                outputClosed = true
                if let source = outputSource { source.cancel(); outputSource = nil }
                else { try? outputPipe.fileHandleForReading.close() }
            }
        }

        private func ioError() -> VoiceInkLocalCLIExecutionError {
            .executionFailed("Local CLI pipe error: \(String(cString: strerror(errno)))")
        }
    }
}
