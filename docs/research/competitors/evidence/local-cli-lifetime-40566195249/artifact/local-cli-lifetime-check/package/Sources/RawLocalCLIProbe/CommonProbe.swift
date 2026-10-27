
import Foundation
import Darwin
import CryptoKit
import VoiceInkCore

private struct Invalid: Error { let reason: String }
@MainActor private final class Outcome {
    var value: String?
    var error: Error?
    var done = false
}
@MainActor private struct Child {
    let directory: URL
    let script: URL
    let token: String
    let pid: pid_t
    let observation: [String: Any]
    var release: URL { directory.appendingPathComponent("release") }
    func alive() -> Bool { Darwin.kill(pid, 0) == 0 }
}

@main @MainActor private enum Probe {
    static var evidence = URL(fileURLWithPath: "/")
    static var lane = ""
    static var cases: [[String: Any]] = []
    static var invalid: [String] = []
    static var registry: [[String: Any]] = []
    static let fm = FileManager.default
    static let gate = "deadline=$((SECONDS + 20))\nwhile [[ ! -e \"${0:h}/release\" && $SECONDS -lt $deadline ]]; do :; done\n[[ -e \"${0:h}/release\" ]] || exit 98\n"
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Invalid(reason: message) }
    }
    static func save(_ name: String, _ value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: evidence.appendingPathComponent(name), options: .atomic)
    }
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func configured(_ command: String, timeout: Double = 5) throws -> LocalCLIService {
        UserDefaults.standard.setVolatileDomain([
            VoiceInkLocalCLIPreference.commandTemplateKey: command,
            VoiceInkLocalCLIPreference.selectedTemplateKey: VoiceInkLocalCLITemplate.pi.rawValue,
            VoiceInkLocalCLIPreference.timeoutSecondsKey: timeout
        ], forName: UserDefaults.argumentDomain)
        let service = LocalCLIService()
        try require(service.commandTemplate == command && service.timeoutSeconds == timeout && timeout >= 5, "Configured command or real minimum timeout was not read")
        return service
    }
    static func begin(_ service: LocalCLIService, user: String = "user") -> (Task<Void, Never>, Outcome) {
        let outcome = Outcome()
        let task = Task {
            do { outcome.value = try await service.enhance(systemPrompt: "system", userPrompt: user) }
            catch { outcome.error = error }
            outcome.done = true
        }
        return (task, outcome)
    }
    static func wait(_ seconds: Double, until predicate: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
        return predicate()
    }
    static func ps(_ pid: pid_t) throws -> (pid_t, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-p", String(pid), "-o", "ppid=,comm=,args="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let fields = (String(data: data, encoding: .utf8) ?? "").split(maxSplits: 2, whereSeparator: { $0.isWhitespace }).map(String.init)
        try require(process.terminationStatus == 0 && fields.count == 3, "Owned ready process was not present in ps")
        guard let parent = pid_t(fields[0]) else { throw Invalid(reason: "Invalid ready PPID") }
        return (parent, fields[1], fields[2])
    }
    static func fixture(_ name: String, body: String, ignoreTERM: Bool = false) throws -> (URL, String) {
        let directory = evidence.appendingPathComponent(name + "-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        let script = directory.appendingPathComponent("command.zsh")
        let token = UUID().uuidString
        let ready = directory.appendingPathComponent("ready")
        let text = "#!/bin/zsh\n" + (ignoreTERM ? "trap '' TERM\n" : "") +
            "[[ \"$1\" == " + quote(token) + " ]] || exit 97\n" +
            "print -r -- \"$$ $PPID\" > " + quote(ready.path) + "\n" + body + "\n"
        try Data(text.utf8).write(to: script)
        registry.append(["script": script.path, "token": token, "ready": ready.path, "release": directory.appendingPathComponent("release").path])
        try save("registry.json", registry)
        return (directory, "exec /bin/zsh -f " + quote(script.path) + " " + quote(token))
    }
    static func child(_ directory: URL) async throws -> Child {
        let ready = directory.appendingPathComponent("ready")
        try require(await wait(3) { fm.fileExists(atPath: ready.path) }, "Command did not acknowledge READY")
        let fields = try String(contentsOf: ready, encoding: .utf8).split(whereSeparator: { $0.isWhitespace })
        try require(fields.count == 2, "Malformed READY PID and PPID")
        guard let pid = pid_t(fields[0]), let parent = pid_t(fields[1]), let item = registry.first(where: { ($0["ready"] as? String) == ready.path }), let script = item["script"] as? String, let token = item["token"] as? String else { throw Invalid(reason: "Unowned READY identity") }
        let identity = try ps(pid)
        let arguments = "/bin/zsh -f " + script + " " + token
        try require(parent == getpid() && identity.0 == getpid() && identity.1 == "/bin/zsh" && identity.2 == arguments, "READY PID/PPID/executable/script arguments did not identify the direct child")
        let acknowledgment = directory.appendingPathComponent("supervisor-verified")
        try require(await wait(2) { fm.fileExists(atPath: acknowledgment.path) }, "Independent supervisor did not acknowledge the exact child identity")
        let acknowledged = try JSONSerialization.jsonObject(with: Data(contentsOf: acknowledgment)) as? [String: Any]
        try require(acknowledged?["pid"] as? Int == Int(pid) && acknowledged?["token"] as? String == token, "Independent READY acknowledgment identified another child")
        let observation: [String: Any] = ["pid": Int(pid), "ppid": Int(parent), "executable": identity.1, "arguments": identity.2, "script": script, "token": token, "verified": true]
        try save("identity-" + directory.lastPathComponent + ".json", observation)
        return Child(directory: directory, script: URL(fileURLWithPath: script), token: token, pid: pid, observation: observation)
    }
    static func release(_ child: Child) throws { try Data().write(to: child.release, options: .atomic) }
    static func finish(_ children: [Child], outcomes: [Outcome]) async -> Bool {
        for child in children { try? release(child) }
        return await wait(10) { outcomes.allSatisfy { $0.done } && children.allSatisfy { !$0.alive() } }
    }
    static func result(_ outcome: Outcome) -> [String: Any] {
        var kind = "none"
        var seconds: Any = NSNull()
        if outcome.error is CancellationError { kind = "cancellation" }
        else if let error = outcome.error as? VoiceInkLocalCLIExecutionError {
            if case .timeout(let timeout) = error { kind = "timeout"; seconds = timeout }
            else { kind = "unexpected-local-cli" }
        } else if outcome.error != nil { kind = "unexpected" }
        return ["completed": outcome.done, "errorKind": kind, "timeoutSeconds": seconds, "errorDescription": outcome.error.map { String(describing: $0) } ?? "", "stdoutBytes": outcome.value?.utf8.count ?? 0, "stdoutSHA256": hash(outcome.value ?? "")]
    }
    static func record(_ id: String, passed: Bool, boundary: [String: Any], children: [Child], outcomes: [Outcome], cleanup: Bool) throws {
        cases.append(["id": id, "passed": passed, "boundary": boundary, "processes": children.map { $0.observation }, "outcomes": outcomes.map(result), "probePID": Int(getpid()), "cleanupCompleted": cleanup])
        try save("cases.json", cases)
        try require(cleanup, "A fixture failed natural cleanup after its boundary snapshot")
    }
    static func gated(_ name: String, output: String, ignoreTERM: Bool = false) throws -> (URL, String) {
        let tokenName = UUID().uuidString
        let body = gate + "IFS= read -r -d '' input || :\nprint -rn -- \"$input\" > \"${0:h}/stdin.txt\"\nprint -rn -- " + quote(output)
        return try fixture(name + "-" + tokenName, body: body, ignoreTERM: ignoreTERM)
    }
    static func common() async throws {
        let (preDir, preCommand) = try gated("precancel", output: "PRE")
        let preService = try configured(preCommand)
        let (preTask, preOutcome) = begin(preService)
        preTask.cancel()
        let preDone = await wait(1.5) { preOutcome.done }
        var preChildren: [Child] = []
        let launched = fm.fileExists(atPath: preDir.appendingPathComponent("ready").path)
        if launched { preChildren = [try await child(preDir)] }
        let prePassed = preDone && preOutcome.error is CancellationError && !launched
        let preCleanup = await finish(preChildren, outcomes: [preOutcome])
        try record("pre-cancelled", passed: prePassed, boundary: ["completedWithinDeadline": preDone, "typedCancellation": preOutcome.error is CancellationError, "commandLaunched": launched], children: preChildren, outcomes: [preOutcome], cleanup: preCleanup)

        let large = String(repeating: "i", count: 80 * 1024)
        let fullInput = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: "system", userPrompt: large)
        let (cancelDir, cancelCommand) = try gated("cancel", output: "CANCEL_FINISHED", ignoreTERM: true)
        let (survivorDir, survivorCommand) = try gated("survivor", output: "SURVIVOR_EXACT")
        let cancelService = try configured(cancelCommand)
        let survivorService = try configured(survivorCommand)
        let (cancelTask, cancelOutcome) = begin(cancelService, user: large)
        let (_, survivorOutcome) = begin(survivorService)
        let cancelled = try await child(cancelDir)
        let survivor = try await child(survivorDir)
        let started = ProcessInfo.processInfo.systemUptime
        cancelTask.cancel()
        let cancelDone = await wait(1.5) { cancelOutcome.done }
        let cancelElapsed = ProcessInfo.processInfo.systemUptime - started
        let childAlive = cancelled.alive()
        let survivorAlive = survivor.alive() && !survivorOutcome.done
        let typed = cancelOutcome.error is CancellationError
        let cancelBoundary: [String: Any] = ["completedWithinDeadline": cancelDone, "childAliveAtBoundary": childAlive, "survivorAliveAtBoundary": survivorAlive, "typedCancellation": typed, "deadlineSeconds": 1.5, "elapsedSeconds": cancelElapsed, "stdinBytes": fullInput.utf8.count, "stdinSHA256": hash(fullInput)]
        try save("cancellation-boundary.json", cancelBoundary)
        let cancelCleanup = await finish([cancelled, survivor], outcomes: [cancelOutcome, survivorOutcome])
        let survivorExact = survivorOutcome.value?.utf8.elementsEqual("SURVIVOR_EXACT".utf8) == true && survivorOutcome.error == nil
        try record("cancel-blocked-stdin", passed: cancelDone && typed && !childAlive && survivorAlive && survivorExact, boundary: cancelBoundary.merging(["survivorExactAfterRelease": survivorExact]) { _, new in new }, children: [cancelled, survivor], outcomes: [cancelOutcome, survivorOutcome], cleanup: cancelCleanup)

        let pipeBody = "IFS= read -r -d '' input || :\nprint -rn -- \"$input\" > \"${0:h}/stdin.txt\"\nblock=X\nfor index in {1..17}; do block=\"$block$block\"; done\nprint -rn -- \"$block\"\nprint -rn -- \"$block\" >&2\nprint -r -- ${#block} > \"${0:h}/stderr-written.txt\"\n"
        let (pipeDir, pipeCommand) = try fixture("dual-pipe", body: gate + pipeBody)
        let (_, pipeOutcome) = begin(try configured(pipeCommand), user: large)
        let pipeChild = try await child(pipeDir)
        try release(pipeChild)
        let pipeDone = await wait(8) { pipeOutcome.done }
        let expected = String(repeating: "X", count: 128 * 1024)
        let input = (try? String(contentsOf: pipeDir.appendingPathComponent("stdin.txt"), encoding: .utf8)) ?? ""
        let pipeExact = pipeOutcome.value?.utf8.elementsEqual(expected.utf8) == true
        let pipeCleanup = await finish([pipeChild], outcomes: [pipeOutcome])
        let stderrWritten = Int(((try? String(contentsOf: pipeDir.appendingPathComponent("stderr-written.txt"), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        try record("dual-pipe", passed: pipeDone && pipeExact && input.utf8.elementsEqual(fullInput.utf8) && pipeOutcome.error == nil && stderrWritten == expected.utf8.count, boundary: ["completedWithinDeadline": pipeDone, "stdinBytes": input.utf8.count, "stdinSHA256": hash(input), "expectedStdinSHA256": hash(fullInput), "stdoutBytes": pipeOutcome.value?.utf8.count ?? 0, "stdoutSHA256": hash(pipeOutcome.value ?? ""), "expectedStdoutSHA256": hash(expected), "stderrWrittenBytes": stderrWritten], children: [pipeChild], outcomes: [pipeOutcome], cleanup: pipeCleanup)

        let (timeoutDir, timeoutCommand) = try gated("timeout", output: "TIMEOUT_RELEASED", ignoreTERM: true)
        let timeoutService = try configured(timeoutCommand, timeout: 5)
        let timeoutStart = ProcessInfo.processInfo.systemUptime
        let (_, timeoutOutcome) = begin(timeoutService, user: large)
        let timeoutChild = try await child(timeoutDir)
        let timeoutDone = await wait(max(0, 8 - (ProcessInfo.processInfo.systemUptime - timeoutStart))) { timeoutOutcome.done }
        let timeoutElapsed = ProcessInfo.processInfo.systemUptime - timeoutStart
        let timeoutTyped = (timeoutOutcome.error as? VoiceInkLocalCLIExecutionError) == .timeout(seconds: 5)
        let timeoutAlive = timeoutChild.alive()
        let timeoutBoundary: [String: Any] = ["completedWithinDeadline": timeoutDone, "configuredTimeoutSeconds": 5, "elapsedSeconds": timeoutElapsed, "typedTimeout": timeoutTyped, "childAliveAtBoundary": timeoutAlive, "stdinBytes": fullInput.utf8.count]
        try save("timeout-boundary.json", timeoutBoundary)
        let timeoutCleanup = await finish([timeoutChild], outcomes: [timeoutOutcome])
        try record("timeout-blocked-stdin", passed: timeoutDone && timeoutTyped && !timeoutAlive && timeoutElapsed <= 8, boundary: timeoutBoundary, children: [timeoutChild], outcomes: [timeoutOutcome], cleanup: timeoutCleanup)

        var raceChildren: [Child] = []
        var raceOutcomes: [Outcome] = []
        var racePassed = true
        for index in 0..<3 {
            let (directory, command) = try gated("race-" + String(index), output: "RACE_EXACT")
            let (task, outcome) = begin(try configured(command))
            raceOutcomes.append(outcome)
            let current = try await child(directory)
            raceChildren.append(current)
            try release(current)
            task.cancel()
            let done = await wait(2) { outcome.done }
            let accepted = outcome.error is CancellationError || (outcome.error == nil && outcome.value == "RACE_EXACT")
            let cleanup = await finish([current], outcomes: [outcome])
            racePassed = racePassed && done && accepted && cleanup
        }
        try record("exit-races", passed: racePassed, boundary: ["iterations": 3], children: raceChildren, outcomes: raceOutcomes, cleanup: raceChildren.allSatisfy { !$0.alive() })
        let (_, laterOutcome) = begin(try configured("printf '%s' LATER_CONTROL_EXACT"))
        let laterDone = await wait(3) { laterOutcome.done }
        try record("later-control", passed: laterDone && laterOutcome.error == nil && laterOutcome.value == "LATER_CONTROL_EXACT", boundary: ["completedWithinDeadline": laterDone], children: [], outcomes: [laterOutcome], cleanup: laterDone)
    }
#if RAW_PROBE
    static func raw() async throws {
        let (capturedDir, capturedCommand) = try gated("captured", output: "CAPTURED_EXACT")
        _ = try configured(capturedCommand)
        let captured = LocalCLIService.RequestConfiguration.fromPreferences()
        let (changedDir, changedCommand) = try gated("changed", output: "WRONG_COMMAND")
        _ = try configured(changedCommand, timeout: 10)
        let captureOutcome = Outcome()
        Task {
            do { captureOutcome.value = try await LocalCLIService.execute(systemPrompt: "system", userPrompt: "user", configuration: captured) }
            catch { captureOutcome.error = error }
            captureOutcome.done = true
        }
        let capturedChild = try await child(capturedDir)
        try release(capturedChild)
        let captureDone = await wait(3) { captureOutcome.done }
        let changedUnlaunched = !fm.fileExists(atPath: changedDir.appendingPathComponent("ready").path)
        let captureCleanup = await finish([capturedChild], outcomes: [captureOutcome])
        try record("captured-configuration", passed: captureDone && captureOutcome.error == nil && captureOutcome.value == "CAPTURED_EXACT" && captured.commandTemplate == capturedCommand && captured.timeoutSeconds == 5 && changedUnlaunched, boundary: ["capturedTimeoutSeconds": captured.timeoutSeconds, "newCommandUnlaunched": changedUnlaunched], children: [capturedChild], outcomes: [captureOutcome], cleanup: captureCleanup)
        let literal = "  <think>literal e\u{301} 日本語</think>\n{\"literal\":true}\n  "
        let body = gate + "IFS= read -r -d '' input || :\nprint -rn -- " + quote(literal)
        let (rawDir, rawCommand) = try fixture("raw", body: body)
        _ = try configured(rawCommand)
        let rawConfiguration = LocalCLIService.RequestConfiguration.fromPreferences()
        let rawOutcome = Outcome()
        Task {
            do { rawOutcome.value = try await LocalCLIService.execute(systemPrompt: "system", userPrompt: "user", configuration: rawConfiguration) }
            catch { rawOutcome.error = error }
            rawOutcome.done = true
        }
        let rawChild = try await child(rawDir)
        try release(rawChild)
        let rawDone = await wait(3) { rawOutcome.done }
        let rawExact = rawOutcome.value?.utf8.elementsEqual(literal.utf8) == true
        let rawCleanup = await finish([rawChild], outcomes: [rawOutcome])
        try record("raw-literal", passed: rawDone && rawExact && rawOutcome.error == nil, boundary: ["stdoutBytes": rawOutcome.value?.utf8.count ?? 0, "stdoutSHA256": hash(rawOutcome.value ?? ""), "expectedStdoutSHA256": hash(literal)], children: [rawChild], outcomes: [rawOutcome], cleanup: rawCleanup)
        let (legacyDir, legacyCommand) = try fixture("legacy", body: body)
        let (_, legacyOutcome) = begin(try configured(legacyCommand))
        let legacyChild = try await child(legacyDir)
        try release(legacyChild)
        let legacyDone = await wait(3) { legacyOutcome.done }
        let cleaned = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyExact = legacyOutcome.value?.utf8.elementsEqual(cleaned.utf8) == true
        let legacyCleanup = await finish([legacyChild], outcomes: [legacyOutcome])
        try record("legacy-trim", passed: legacyDone && legacyExact && legacyOutcome.error == nil, boundary: ["stdoutBytes": legacyOutcome.value?.utf8.count ?? 0, "stdoutSHA256": hash(legacyOutcome.value ?? ""), "expectedStdoutSHA256": hash(cleaned)], children: [legacyChild], outcomes: [legacyOutcome], cleanup: legacyCleanup)
    }
#endif
    static func main() async {
        guard CommandLine.arguments.count == 5 else { Darwin.exit(2) }
        evidence = URL(fileURLWithPath: CommandLine.arguments[1])
        lane = CommandLine.arguments[2]
        let bundle = CommandLine.arguments[3]
        let source = CommandLine.arguments[4]
        var setupPassed = false
        var unchanged = false
        do {
            try require(getuid() != 0 && Bundle.main.bundleIdentifier == bundle, "Unique non-root CLI app identity was not loaded")
            try require((UserDefaults.standard.persistentDomain(forName: bundle) ?? [:]).isEmpty, "Unique CLI app already has persistent preferences")
            try save("probe-start.json", ["pid": Int(getpid()), "ppid": Int(getppid()), "executable": CommandLine.arguments[0], "bundleIdentifier": bundle])
            let (_, warm) = begin(try configured("printf '%s' PATH_WARM_CONTROL"))
            try require(await wait(5) { warm.done } && warm.error == nil && warm.value == "PATH_WARM_CONTROL", "Actual interactive PATH and simple command control failed")
            setupPassed = true
#if RAW_PROBE
            try await raw()
#else
            try await common()
#endif
        } catch { invalid.append((error as? Invalid)?.reason ?? String(describing: error)) }
        UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        unchanged = (UserDefaults.standard.persistentDomain(forName: bundle) ?? [:]).isEmpty
        let receipt: [String: Any] = ["version": 1, "lane": lane, "sourceSHA256": source, "bundleIdentifier": bundle, "probePID": Int(getpid()), "setupPassed": setupPassed, "preferencesUnchanged": unchanged, "cases": cases, "invalidReasons": invalid]
        do { try save("result.json", receipt) } catch { Darwin.exit(3) }
        if !invalid.isEmpty || !setupPassed || !unchanged { Darwin.exit(2) }
        Darwin.exit(cases.allSatisfy { ($0["passed"] as? Bool) == true } ? 0 : 1)
    }
}
