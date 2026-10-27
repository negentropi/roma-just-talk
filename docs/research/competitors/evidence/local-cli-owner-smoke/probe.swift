import Foundation
import Darwin
private enum VoiceInkAppIdentity { static let loggingSubsystem = "rjt.cli.foundation-smoke" }
public enum VoiceInkLocalCLIExecutionError: Error, LocalizedError, Equatable, Sendable {
    case commandNotConfigured
    case commandNotFound(String)
    case timeout(seconds: Double)
    case nonZeroExit(status: Int, stderr: String)
    case emptyOutput
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotConfigured:
            return "Local CLI command is not configured. Load a template or enter a command first."
        case .commandNotFound(let details):
            return "Local CLI command was not found. Use an absolute path or fix your shell PATH. Details: \(details)"
        case .timeout(let seconds):
            return "Local CLI command timed out after \(Int(seconds)) seconds."
        case .nonZeroExit(let status, let stderr):
            if stderr.isEmpty {
                return "Local CLI command failed with exit code \(status)."
            }

            return "Local CLI command failed with exit code \(status): \(stderr)"
        case .emptyOutput:
            return "Local CLI command returned empty output."
        case .executionFailed(let message):
            return "Failed to execute Local CLI command: \(message)"
        }
    }
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
@main private enum Smoke {
 static func main() async throws {
  func childOwnershipDisposition() -> (Bool, Bool) {
   var disposition = sigaction()
   precondition(sigaction(SIGCHLD, nil, &disposition) == 0)
   let isDefault = unsafeBitCast(disposition.__sigaction_u.__sa_handler, to: UInt.self) == unsafeBitCast(SIG_DFL, to: UInt.self)
   return (isDefault, disposition.sa_flags & SA_NOCLDWAIT != 0)
  }
  let before = childOwnershipDisposition()
  let priorFoundationChild = Process()
  priorFoundationChild.executableURL = URL(fileURLWithPath: "/usr/bin/true")
  try priorFoundationChild.run()
  priorFoundationChild.waitUntilExit()
  let after = childOwnershipDisposition()
  precondition(before.0 && !before.1 && after.0 && !after.1)
  print("PASS: SIGCHLD default/no-auto-reap before and after real Foundation Process")
  let input=Data(repeating:65,count:131072)
  let environment=["PATH":"/usr/bin:/bin"]
  let output=try await CommandRun(arguments:["-c","/bin/cat; printf err >&2"],environment:environment,input:input,timeout:2).run()
  precondition(output.stdout==input && output.stderr==Data("err".utf8) && output.exitStatus==0)
  let early=try await CommandRun(arguments:["-c","printf early"],environment:environment,input:input,timeout:2).run()
  precondition(early.stdout==Data("early".utf8) && early.exitStatus==0)
  let waiting=Task { try await CommandRun(arguments:["-c","exec /bin/sleep 2"],environment:environment,input:input,timeout:3).run() }
  try await Task.sleep(for:.milliseconds(50))
  waiting.cancel()
  do { _=try await waiting.value; fatalError("Cancellation returned output") } catch is CancellationError {}
  print("PASS: exact owner 128KiB stdin/stdout, stderr, early closed input, canceled child")
 }
}
