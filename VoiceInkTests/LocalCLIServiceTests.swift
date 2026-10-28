import Darwin
import Foundation
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
@Suite(.serialized)
struct LocalCLIServiceLifetimeTests {
    @Test @MainActor func canceledBeforeInvocationDoesNotLaunchACommand() async throws {
        try await withLocalCLIFixture { fixture in
            try await fixture.warmPATH()
            let command = try fixture.command("never-launched", body: "/bin/cat >/dev/null; printf '%s' unexpected")
            let service = fixture.service(command, timeout: 5)
            let gate = LocalCLITestStartGate()
            let work = fixture.request {
                await gate.wait()
                return try await service.enhance(systemPrompt: "system", userPrompt: "user")
            }
            defer { work.cancel(); gate.release() }
            try await gate.waitUntilEntered()
            work.cancel()
            gate.release()
            let result = await work.result
            #expect(localCLICanceled(result))
            #expect(!FileManager.default.fileExists(atPath: command.pidURL.path))
        }
    }

    @Test @MainActor func cancellationDuringBlockedInputStopsOnlyItsOwnedRequest() async throws {
        try await withLocalCLIFixture { fixture in
            try await fixture.warmPATH()
            let blocked = try fixture.command("blocked-input", body: """
            /bin/sleep 4
            /bin/cat >/dev/null
            printf '%s' unexpected
            """)
            let survivorRelease = fixture.releaseGate("survivor.release")
            let survivor = try fixture.command("survivor", body: """
            /bin/cat >/dev/null
            count=0
            while [ ! -f \(fixture.quote(survivorRelease.path)) ] && [ "$count" -lt 800 ]; do
                /bin/sleep 0.01
                count=$((count + 1))
            done
            printf '%s' survivor-output
            """)
            let first = fixture.service(blocked, timeout: 6)
            let firstWork = fixture.request {
                try await first.enhance(systemPrompt: "system", userPrompt: String(repeating: "x", count: 80 * 1_024))
            }
            defer { firstWork.cancel() }
            let firstPID = try await fixture.waitForOwnedPID(blocked)
            let second = fixture.service(survivor, timeout: 9)
            let secondWork = fixture.request { try await second.enhance(systemPrompt: "system", userPrompt: "keep running") }
            defer { secondWork.cancel() }
            let secondPID = try await fixture.waitForOwnedPID(survivor)
            let cancellationStarted = ProcessInfo.processInfo.systemUptime
            firstWork.cancel()
            let firstExited = await fixture.waitUntil(timeout: 1.5) { !fixture.processExists(firstPID) }
            #expect(firstExited, "Cancellation must end the exact blocked-input child before its four-second natural release.")
            #expect(fixture.ownsRunningProcess(secondPID, command: survivor), "Canceling one request must leave the other child running.")
            try Data().write(to: survivorRelease)
            let firstResult = await firstWork.result
            let cancellationElapsed = ProcessInfo.processInfo.systemUptime - cancellationStarted
            let secondResult = await secondWork.result
            #expect(localCLICanceled(firstResult))
            #expect(cancellationElapsed < 2, "The canceled request must resolve without waiting for its child's natural release.")
            let survivorOutput = try? secondResult.get()
            #expect(survivorOutput == "survivor-output")
            let secondExited = await fixture.waitUntil(timeout: 1) { !fixture.processExists(secondPID) }
            #expect(secondExited)
        }
    }

    @Test @MainActor func largeInputAndBothOutputPipesCompleteWithoutDeadlock() async throws {
        try await withLocalCLIFixture { fixture in
            try await fixture.warmPATH()
            let input = String(repeating: "x", count: 80 * 1_024)
            let release = fixture.releaseGate("large-pipes.release")
            let command = try fixture.command("large-pipes", body: """
            count=0
            while [ ! -f \(fixture.quote(release.path)) ] && [ "$count" -lt 600 ]; do
                /bin/sleep 0.01
                count=$((count + 1))
            done
            /bin/cat > \(fixture.quote(fixture.url("large-pipes.stdin").path))
            /usr/bin/awk 'BEGIN { for (i = 0; i < 131072; i++) printf "o" }'
            /usr/bin/awk 'BEGIN { for (i = 0; i < 131072; i++) printf "e" > "/dev/stderr" }'
            """)
            let service = fixture.service(command, timeout: 5)
            let work = fixture.request { try await service.enhance(systemPrompt: "system", userPrompt: input) }
            defer { work.cancel() }
            let pid = try await fixture.waitForOwnedPID(command)
            try Data().write(to: release)
            let result = await work.result
            let output = try? result.get()
            #expect(output?.utf8.elementsEqual(String(repeating: "o", count: 131_072).utf8) == true,
                    "Concurrent drainage must return the complete large stdout rather than time out.")
            let expectedInput = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: "system", userPrompt: input)
            let inputData = try? Data(contentsOf: fixture.url("large-pipes.stdin"))
            #expect(inputData?.elementsEqual(expectedInput.utf8) == true)
            let exited = await fixture.waitUntil(timeout: 1) { !fixture.processExists(pid) }
            #expect(exited)
        }
    }

    @Test @MainActor func timeoutIncludesBlockedInputAndEndsItsOwnedChild() async throws {
        try await withLocalCLIFixture { fixture in
            try await fixture.warmPATH()
            let command = try fixture.command("timeout-input", body: """
            /bin/sleep 10
            /bin/cat >/dev/null
            /bin/sleep 2
            """)
            let service = fixture.service(command, timeout: 5)
            let started = ProcessInfo.processInfo.systemUptime
            let work = fixture.request {
                try await service.enhance(systemPrompt: "system", userPrompt: String(repeating: "x", count: 80 * 1_024))
            }
            defer { work.cancel() }
            let result = await work.result
            let pid = try #require(fixture.pid(command), "The timeout command must have entered its unique script before cancellation.")
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let timedOut: Bool
            switch result {
            case .failure(let error):
                timedOut = error as? VoiceInkLocalCLIExecutionError == .timeout(seconds: 5)
            case .success: timedOut = false
            }
            #expect(timedOut)
            #expect(elapsed < 8, "The supported five-second deadline must include stdin blocked before its ten-second natural release.")
            let exited = await fixture.waitUntil(timeout: 1) { !fixture.processExists(pid) }
            #expect(exited)
        }
    }

    @Test @MainActor func cancellationAndExitRacesLeaveLaterRequestsUsable() async throws {
        try await withLocalCLIFixture { fixture in
            try await fixture.warmPATH()
            for index in 0..<8 {
                let release = fixture.releaseGate("race-\(index).release")
                let command = try fixture.command("race-\(index)", body: """
                /bin/cat >/dev/null
                count=0
                while [ ! -f \(fixture.quote(release.path)) ] && [ "$count" -lt 300 ]; do
                    /bin/sleep 0.01
                    count=$((count + 1))
                done
                printf '%s' race-output
                """)
                let service = fixture.service(command, timeout: 5)
                let work = fixture.request { try await service.enhance(systemPrompt: "system", userPrompt: "race") }
                defer { work.cancel() }
                let pid = try await fixture.waitForOwnedPID(command)
                if index.isMultiple(of: 2) {
                    try Data().write(to: release)
                    await Task.yield()
                    work.cancel()
                } else {
                    work.cancel()
                    try Data().write(to: release)
                }
                let result = await work.result
                let valid: Bool
                switch result {
                case .success(let text): valid = text == "race-output"
                case .failure(let error): valid = error is CancellationError
                }
                #expect(valid)
                let exited = await fixture.waitUntil(timeout: 1) { !fixture.processExists(pid) }
                #expect(exited)
            }
            let control = try fixture.command("after-races", body: "/bin/cat >/dev/null; printf '%s' still-usable")
            let output = try await fixture.service(control, timeout: 5).enhance(systemPrompt: "system", userPrompt: "control")
            #expect(output == "still-usable")
        }
    }

    @Test @MainActor func cancellationEndsATermIgnoringOwnedChild() async throws {
        try await withLocalCLIFixture { fixture in
            try await fixture.warmPATH()
            let release = fixture.releaseGate("term-ignoring.release")
            let ready = fixture.url("term-ignoring.ready")
            let command = try fixture.command("term-ignoring", body: """
            trap '' TERM
            /bin/cat >/dev/null
            : > \(fixture.quote(ready.path))
            count=0
            while [ ! -f \(fixture.quote(release.path)) ] && [ "$count" -lt 1000 ]; do
                /bin/sleep 0.01
                count=$((count + 1))
            done
            printf '%s' natural-exit
            """)
            let service = fixture.service(command, timeout: 20)
            let work = fixture.request { try await service.enhance(systemPrompt: "system", userPrompt: "wait") }
            let pid = try await fixture.waitForOwnedPID(command)
            let becameReady = await fixture.waitUntil(timeout: 2) { FileManager.default.fileExists(atPath: ready.path) }
            try #require(becameReady, "The owned child did not confirm its TERM-ignore handler and input EOF.")
            let cancellationStarted = ProcessInfo.processInfo.systemUptime
            work.cancel()
            let exited = await fixture.waitUntil(timeout: 1.5) { !fixture.processExists(pid) }
            #expect(exited, "Cancellation must end the TERM-ignoring child before its finite natural release.")
            try Data().write(to: release)
            let result = await work.result
            #expect(localCLICanceled(result))
            #expect(ProcessInfo.processInfo.systemUptime - cancellationStarted < 2)
        }
    }
}
}

@MainActor
private func withLocalCLIFixture<T>(_ operation: (LocalCLITestFixture) async throws -> T) async throws -> T {
    let fixture = try LocalCLITestFixture()
    do {
        let result = try await operation(fixture)
        await fixture.close()
        return result
    } catch {
        await fixture.close()
        throw error
    }
}

@MainActor
private final class LocalCLITestStartGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var entered = false
    private var released = false
    func wait() async {
        entered = true
        if released { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func waitUntilEntered() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !entered, ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        try #require(entered, "The controlled canceled-start task did not reach its gate.")
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}

private func localCLICanceled(_ result: Result<String, Error>) -> Bool {
    if case .failure(let error) = result { return error is CancellationError }
    return false
}

@MainActor
private final class LocalCLITestFixture {
    struct Command {
        let scriptURL: URL
        let pidURL: URL
        let template: String
    }

    let directory: URL
    private let defaults = UserDefaults.standard
    private let saved: [String: Any]
    private var commands: [Command] = []
    private var releaseGates: [URL] = []
    private var requests: [(Task<String, Error>, LocalCLITestCompletion)] = []
    private var reportedProcessObservationFailure = false
    private static let keys = [
        VoiceInkLocalCLIPreference.commandTemplateKey,
        VoiceInkLocalCLIPreference.selectedTemplateKey,
        VoiceInkLocalCLIPreference.timeoutSecondsKey
    ]

    init() throws {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        saved = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in domain[key].map { (key, $0) } })
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-CLI-Lifetime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
    func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    func releaseGate(_ name: String) -> URL {
        let gate = url(name)
        releaseGates.append(gate)
        return gate
    }

    func request(_ operation: @escaping @MainActor () async throws -> String) -> Task<String, Error> {
        let work = Task { try await operation() }
        let completion = LocalCLITestCompletion()
        requests.append((work, completion))
        Task {
            _ = await work.result
            completion.finished = true
        }
        return work
    }

    func command(_ name: String, body: String) throws -> Command {
        let script = url(name + ".sh")
        let pid = url(name + ".pid")
        let content = "umask 077\nprintf '%s' \"$$\" > \(quote(pid.path))\n" + body + "\n"
        try content.write(to: script, atomically: true, encoding: .utf8)
        let result = Command(scriptURL: script, pidURL: pid, template: "exec /bin/sh " + quote(script.path))
        commands.append(result)
        return result
    }

    func service(_ command: Command, timeout: Double) -> LocalCLIService {
        defaults.set(command.template, forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
        defaults.set(VoiceInkLocalCLITemplate.claude.rawValue, forKey: VoiceInkLocalCLIPreference.selectedTemplateKey)
        defaults.set(timeout, forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey)
        return LocalCLIService()
    }

    func warmPATH() async throws {
        let command = try command("warm-\(UUID().uuidString)", body: "/bin/cat >/dev/null; printf '%s' warm")
        let output = try await service(command, timeout: 5).enhance(systemPrompt: "system", userPrompt: "warm")
        try #require(output == "warm", "The real shell/PATH fixture did not become usable.")
    }

    func pid(_ command: Command) -> pid_t? {
        guard let text = try? String(contentsOf: command.pidURL, encoding: .utf8),
              let pid = Int32(text), pid > 1, pid != getpid() else { return nil }
        return pid
    }

    func waitForOwnedPID(_ command: Command) async throws -> pid_t {
        var observed: pid_t?
        _ = await waitUntil(timeout: 2) {
            guard let candidate = self.pid(command), self.ownsRunningProcess(candidate, command: command) else { return false }
            observed = candidate
            return true
        }
        return try #require(observed, "The unique script did not expose its exact running shell process.")
    }

    func ownsRunningProcess(_ pid: pid_t, command: Command) -> Bool {
        guard self.pid(command) == pid,
              let name = processField(pid, field: "comm="),
              URL(fileURLWithPath: name).lastPathComponent == "sh",
              let arguments = processField(pid, field: "args=") else { return false }
        return arguments == "/bin/sh " + command.scriptURL.path
    }

    func processExists(_ pid: pid_t) -> Bool {
        switch lookupProcessField(pid, field: "pid=") {
        case .absent: return false
        case .value: return true
        case .failed:
            if !reportedProcessObservationFailure {
                reportedProcessObservationFailure = true
                Issue.record("CLI fixture could not observe PID liveness; exit remains unproven.")
            }
            return true
        }
    }

    func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return condition()
    }

    private enum ProcessField {
        case absent
        case value(String)
        case failed
    }

    private func processField(_ pid: pid_t, field: String) -> String? {
        if case .value(let value) = lookupProcessField(pid, field: field) { return value }
        return nil
    }

    private func lookupProcessField(_ pid: pid_t, field: String) -> ProcessField {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-p", String(pid), "-o", field]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { return .failed }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 1, data.isEmpty, errorData.isEmpty { return .absent }
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return .failed }
        return .value(value)
    }

    func close() async {
        for (work, _) in requests { work.cancel() }
        for gate in releaseGates {
            do { try Data().write(to: gate) }
            catch { Issue.record("Could not release the owned CLI fixture gate: \(error)") }
        }
        let requestsFinished = await waitUntil(timeout: 30) { self.requests.allSatisfy { $0.1.finished } }
        if requestsFinished {
            for (work, _) in requests { _ = await work.result }
        }
        let processesExited = await waitUntil(timeout: 15) {
            self.commands.allSatisfy { command in
                guard let pid = self.pid(command) else { return true }
                return !self.processExists(pid)
            }
        }
        for key in Self.keys {
            if let value = saved[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        if !requestsFinished || !processesExited { Issue.record("An owned CLI request or recorded PID did not finish within the cleanup budget; its unique files were preserved without signaling it.") }
        else {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Could not remove the owned CLI fixture files: \(error)") }
        }
    }
}

@MainActor
private final class LocalCLITestCompletion {
    var finished = false
}

extension VoiceInkTests {
@Suite(.serialized)
struct LocalCLIServiceConfigurationTests {
    @Test @MainActor func capturedConfigurationPreservesCommandAndTimeoutWithoutPreferenceWrites() async throws {
        try await withLocalCLIFixture { fixture in
            let original = try fixture.command("captured", body: "/bin/cat >/dev/null; /bin/sleep 0.1; printf '%s' captured")
            _ = fixture.service(original, timeout: 2)
            let captured = LocalCLIService.RequestConfiguration.fromPreferences()
            let changed = try fixture.command("changed", body: "/bin/cat >/dev/null; printf '%s' changed")
            _ = fixture.service(changed, timeout: 0.01)
            let output = try await LocalCLIService.execute(systemPrompt: "system", userPrompt: "user", configuration: captured)
            #expect(output == "captured")
            #expect(captured.commandTemplate == original.template)
            #expect(captured.timeoutSeconds == 2)
            #expect(UserDefaults.standard.string(forKey: VoiceInkLocalCLIPreference.commandTemplateKey) == changed.template)
            #expect(UserDefaults.standard.double(forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey) == 0.01)
            #expect(!FileManager.default.fileExists(atPath: changed.pidURL.path))
        }
    }

    @Test @MainActor func rawExecutionPreservesLiteralOutputAndLegacyEnhanceKeepsItsPolicies() async throws {
        try await withLocalCLIFixture { fixture in
            let literal = "  <think>literal で e\u{301}</think>\n{\"codex_follow_up\":true}\n  "
            try Data(literal.utf8).write(to: fixture.url("literal.txt"))
            let command = try fixture.command("literal", body: "/bin/cat >/dev/null; /bin/cat " + fixture.quote(fixture.url("literal.txt").path))
            let configuration = LocalCLIService.RequestConfiguration(commandTemplate: command.template, timeoutSeconds: 2)
            let raw = try await LocalCLIService.execute(systemPrompt: "system", userPrompt: "user", configuration: configuration)
            #expect(raw.utf8.elementsEqual(literal.utf8))
            let legacy = try await fixture.service(command, timeout: 5).enhance(systemPrompt: "system", userPrompt: "user")
            #expect(legacy.utf8.elementsEqual(literal.trimmingCharacters(in: .whitespacesAndNewlines).utf8))

            let empty = try fixture.command("empty", body: "/bin/cat >/dev/null; printf '  \\n  '")
            await #expect(throws: VoiceInkLocalCLIExecutionError.emptyOutput) {
                try await fixture.service(empty, timeout: 5).enhance(systemPrompt: "system", userPrompt: "user")
            }
            let failed = try fixture.command("failed", body: "/bin/cat >/dev/null; printf '  exact failure  \\n' >&2; exit 23")
            await #expect(throws: VoiceInkLocalCLIExecutionError.nonZeroExit(status: 23, stderr: "exact failure")) {
                try await fixture.service(failed, timeout: 5).enhance(systemPrompt: "system", userPrompt: "user")
            }
        }
    }

    @Test @MainActor func earlyChildExitWithLargeInputDoesNotBreakRawOrLegacyRequests() async throws {
        try await withLocalCLIFixture { fixture in
            try await fixture.warmPATH()
            let input = String(repeating: "x", count: 80 * 1_024)
            for raw in [true, false] {
                let command = try fixture.command(raw ? "early-raw" : "early-legacy", body: "printf '%s' early-exit")
                let service = fixture.service(command, timeout: 5)
                let configuration = LocalCLIService.RequestConfiguration.fromPreferences()
                let work = fixture.request {
                    if raw {
                        return try await LocalCLIService.execute(systemPrompt: "system", userPrompt: input, configuration: configuration)
                    }
                    return try await service.enhance(systemPrompt: "system", userPrompt: input)
                }
                let output = try await work.value
                #expect(output == "early-exit")
                let pid = try #require(fixture.pid(command), "The early-exit child must have entered the unique script.")
                let exited = await fixture.waitUntil(timeout: 1) { !fixture.processExists(pid) }
                #expect(exited)
            }
            let control = try fixture.command("after-early-exit", body: "/bin/cat >/dev/null; printf '%s' still-usable")
            let output = try await fixture.service(control, timeout: 5).enhance(systemPrompt: "system", userPrompt: "control")
            #expect(output == "still-usable")
        }
    }

    @Test @MainActor func nulCommandAndPromptsRefuseBothEntryPointsBeforeLaunch() async throws {
        try await withLocalCLIFixture { fixture in
            for field in ["command", "system", "user"] {
                let command = try fixture.command("nul-" + field, body: "/bin/cat >/dev/null; printf '%s' unexpected")
                let service = fixture.service(command, timeout: 5)
                let template = command.template + (field == "command" ? "\0" : "")
                let system = field == "system" ? "system\0suffix" : "system"
                let user = field == "user" ? "user\0suffix" : "user"
                service.commandTemplate = template
                let configuration = LocalCLIService.RequestConfiguration(commandTemplate: template, timeoutSeconds: 5)
                let failure = VoiceInkLocalCLIExecutionError.executionFailed("Local CLI command and prompts cannot contain NUL bytes.")
                await #expect(throws: failure) {
                    try await LocalCLIService.execute(systemPrompt: system, userPrompt: user, configuration: configuration)
                }
                await #expect(throws: failure) {
                    try await service.enhance(systemPrompt: system, userPrompt: user)
                }
                #expect(!FileManager.default.fileExists(atPath: command.pidURL.path))
            }
        }
    }
}
}
