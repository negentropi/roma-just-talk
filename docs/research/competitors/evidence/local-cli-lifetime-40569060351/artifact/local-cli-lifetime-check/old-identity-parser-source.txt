#!/usr/bin/env bash
set -euo pipefail

proof() {
  python3 - "$@" <<'PY'
import copy
import hashlib
import io
import json
import os
import plistlib
import re
import subprocess
import sys
import tarfile
import time
import uuid
from pathlib import Path

BASELINE = 'aaaa286a794ac6f60773ef5149a30f214c586f23'
SERVICE = 'VoiceInk/Services/AIEnhancement/LocalCLIService.swift'
OLD_HASH = '3cd0a32d213f3650c33e7c62c8e10d0c6957078442f7feceffa5f8c7d5e6ec8c'
DRIVER = 'scripts/run-local-cli-lifetime-check.sh'
WORKFLOW = '.github/workflows/voiceink-local-cli-lifetime-check.yml'
CASES = ['pre-cancelled', 'cancel-blocked-stdin', 'dual-pipe', 'timeout-blocked-stdin', 'exit-races', 'later-control']
RAW_CASES = ['captured-configuration', 'raw-literal', 'legacy-trim']
digest = lambda data: hashlib.sha256(data).hexdigest()
def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])
def source(root, revision, path):
    return git(root, 'show', revision + ':' + path)
def snapshot(root, revision, paths):
    names = git(root, 'ls-tree', '-r', '--name-only', '-z', revision, '--', *paths).split(b'\0')
    return {name.decode(): digest(source(root, revision, name.decode())) for name in names if name}
def case_valid(case):
    processes = case.get('processes', [])
    return case.get('cleanupCompleted') is True and not case.get('invalidReason') and len({value.get('pid') for value in processes}) == len(processes) and all(
        value.get('verified') is True and isinstance(value.get('pid'), int) and value['pid'] > 0
        and value.get('ppid') == case.get('probePID') and value.get('executable') == '/bin/zsh'
        and value.get('arguments') == '/bin/zsh -f ' + value.get('script', '') + ' ' + value.get('token', '')
        for value in processes)
def output_is(outcome, text):
    return outcome.get('completed') is True and outcome.get('errorKind') == 'none' and outcome.get('stdoutBytes') == len(text.encode()) and outcome.get('stdoutSHA256') == digest(text.encode())
def error_is(outcome, kind, timeout=None):
    return outcome.get('completed') is True and outcome.get('errorKind') == kind and (timeout is None or outcome.get('timeoutSeconds') == timeout)
def boundaries_valid(cases, lane):
    by_id = {case['id']: case for case in cases}
    if lane == 'raw':
        captured, raw, legacy = [by_id[name] for name in RAW_CASES]
        literal = '  <think>literal e\u0301 日本語</think>\n{"literal":true}\n  '
        return captured['boundary'].get('capturedTimeoutSeconds') == 5 and captured['boundary'].get('newCommandUnlaunched') is True and output_is(captured['outcomes'][0], 'CAPTURED_EXACT') and output_is(raw['outcomes'][0], literal) and output_is(legacy['outcomes'][0], literal.strip())
    pre, cancel, pipe, timeout, race, later = [by_id[name] for name in CASES]
    cb, pb, tb = cancel['boundary'], pipe['boundary'], timeout['boundary']
    controls = cancel['boundary'].get('survivorExactAfterRelease') is True and output_is(cancel['outcomes'][1], 'SURVIVOR_EXACT') and race.get('passed') is True and race['boundary'].get('iterations') == 3 and all(error_is(value, 'cancellation') or output_is(value, 'RACE_EXACT') for value in race['outcomes']) and later.get('passed') is True and output_is(later['outcomes'][0], 'LATER_CONTROL_EXACT')
    shared = cb.get('deadlineSeconds') == 1.5 and cb.get('stdinBytes', 0) >= 80 * 1024 and cb.get('survivorAliveAtBoundary') is True and pb.get('stdinBytes', 0) >= 80 * 1024 and pb.get('stdinSHA256') == pb.get('expectedStdinSHA256') and bool(re.fullmatch('[0-9a-f]{64}', str(pb.get('stdinSHA256')))) and pb.get('expectedStdoutSHA256') == digest(b'X' * (128 * 1024)) and tb.get('configuredTimeoutSeconds') == 5 and tb.get('stdinBytes', 0) >= 80 * 1024
    if lane == 'baseline':
        allowed_failures = {'pre-cancelled', 'cancel-blocked-stdin', 'dual-pipe', 'timeout-blocked-stdin'}
        named_failures = all(case.get('passed') is True or case['id'] in allowed_failures for case in cases)
        pre_valid = (pre['boundary'].get('commandLaunched') is True and output_is(pre['outcomes'][0], 'PRE')) or (pre['boundary'].get('commandLaunched') is False and error_is(pre['outcomes'][0], 'cancellation'))
        cancel_valid = cb.get('completedWithinDeadline') is False and cb.get('childAliveAtBoundary') is True and cb.get('typedCancellation') is False and output_is(cancel['outcomes'][0], 'CANCEL_FINISHED')
        pipe_valid = (pipe.get('passed') is True and output_is(pipe['outcomes'][0], 'X' * (128 * 1024))) or error_is(pipe['outcomes'][0], 'timeout', 5)
        timeout_valid = (timeout.get('passed') is True and error_is(timeout['outcomes'][0], 'timeout', 5)) or (tb.get('completedWithinDeadline') is False and tb.get('childAliveAtBoundary') is True and output_is(timeout['outcomes'][0], 'TIMEOUT_RELEASED'))
        return controls and shared and named_failures and pre_valid and cancel_valid and pipe_valid and timeout_valid
    return controls and shared and pre['boundary'].get('completedWithinDeadline') is True and pre['boundary'].get('commandLaunched') is False and pre['boundary'].get('typedCancellation') is True and error_is(pre['outcomes'][0], 'cancellation') and cb.get('completedWithinDeadline') is True and cb.get('childAliveAtBoundary') is False and cb.get('typedCancellation') is True and cb.get('elapsedSeconds', 99) <= 1.5 and error_is(cancel['outcomes'][0], 'cancellation') and pb.get('completedWithinDeadline') is True and pb.get('stdoutBytes') == 128 * 1024 and pb.get('stdoutSHA256') == pb.get('expectedStdoutSHA256') and pb.get('stderrWrittenBytes') == 128 * 1024 and output_is(pipe['outcomes'][0], 'X' * (128 * 1024)) and tb.get('completedWithinDeadline') is True and tb.get('typedTimeout') is True and tb.get('childAliveAtBoundary') is False and 5 <= tb.get('elapsedSeconds', 99) <= 8 and error_is(timeout['outcomes'][0], 'timeout', 5)
def classify(receipt, lane, supervisor, contract):
    cases = receipt.get('cases', [])
    expected = RAW_CASES if lane == 'raw' else CASES
    source_hash = contract.get('baseline_service_sha256') if lane == 'baseline' else contract.get('candidate_service_sha256')
    valid = receipt.get('version') == 1 and receipt.get('lane') == lane and receipt.get('sourceSHA256') == source_hash and receipt.get('bundleIdentifier') == contract.get('bundles', {}).get(lane) and receipt.get('setupPassed') is True and receipt.get('preferencesUnchanged') is True and not receipt.get('invalidReasons') and [case.get('id') for case in cases] == expected and all(case_valid(case) and case.get('probePID') == receipt.get('probePID') for case in cases)
    valid = valid and supervisor.get('completed') is True and supervisor.get('watchdogFired') is False and supervisor.get('cleanupVerified') is True and supervisor.get('rootIdentityVerified') is True and supervisor.get('rootPID') == receipt.get('probePID') and not supervisor.get('errors') and supervisor.get('exitCode') == (1 if lane == 'baseline' else 0) and supervisor.get('executable') == contract.get('executables', {}).get(lane)
    observed = {(value.get('pid'), value.get('script'), value.get('token')) for value in supervisor.get('children', []) if value.get('verified') is True}
    required = {(value.get('pid'), value.get('script'), value.get('token')) for case in cases for value in case.get('processes', [])}
    valid = valid and required <= observed
    counts = {'captured-configuration': 1, 'raw-literal': 1, 'legacy-trim': 1} if lane == 'raw' else {'cancel-blocked-stdin': 2, 'dual-pipe': 1, 'timeout-blocked-stdin': 1, 'exit-races': 3, 'later-control': 0}
    valid = valid and all(len(case.get('processes', [])) == counts[case['id']] for case in cases if case.get('id') in counts)
    if lane != 'raw':
        precancel = next((case for case in cases if case.get('id') == 'pre-cancelled'), {})
        launched = precancel.get('boundary', {}).get('commandLaunched')
        valid = valid and isinstance(launched, bool) and len(precancel.get('processes', [])) == int(launched) and (lane != 'candidate' or launched is False)
    try:
        counts = [1, 1, 1] if lane == 'raw' else [1, 2, 1, 1, 3, 1]
        valid = valid and all(len(case.get('outcomes', [])) == count for case, count in zip(cases, counts)) and boundaries_valid(cases, lane)
    except (KeyError, TypeError, IndexError):
        valid = False
    if lane == 'baseline':
        boundary = next((case.get('boundary', {}) for case in cases if case.get('id') == 'cancel-blocked-stdin'), {})
        intended = boundary.get('completedWithinDeadline') is False and boundary.get('childAliveAtBoundary') is True and boundary.get('survivorAliveAtBoundary') is True and boundary.get('deadlineSeconds') == 1.5 and boundary.get('stdinBytes', 0) >= 80 * 1024
        valid = valid and intended and next((case.get('passed') for case in cases if case.get('id') == 'cancel-blocked-stdin'), None) is False
    else:
        valid = valid and all(case.get('passed') is True for case in cases)
    return {'valid': bool(valid), 'classification': ('intended-cancellation-lifetime-failure' if lane == 'baseline' else 'passed') if valid else 'invalid-or-failed', 'lane': lane, 'caseIDs': [case.get('id') for case in cases], 'failedCases': [case.get('id') for case in cases if case.get('passed') is not True], 'supervisor': supervisor, 'receipt': receipt}

SWIFT = r'''
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
'''

def self_test():
    contract = {'baseline_service_sha256': OLD_HASH, 'candidate_service_sha256': 'new', 'bundles': {x: 'unique.' + x for x in ['baseline', 'candidate', 'raw']}, 'executables': {x: '/tmp/' + x for x in ['baseline', 'candidate', 'raw']}}
    def outcome(text='', kind='none', timeout=None):
        return {'completed': True, 'errorKind': kind, 'timeoutSeconds': timeout, 'stdoutBytes': len(text.encode()), 'stdoutSHA256': digest(text.encode())}
    def sample(lane):
        names = RAW_CASES if lane == 'raw' else CASES
        counts = {'pre-cancelled': 1 if lane == 'baseline' else 0, 'cancel-blocked-stdin': 2, 'dual-pipe': 1, 'timeout-blocked-stdin': 1, 'exit-races': 3, 'later-control': 0}
        children, cases = [], []
        for name in names:
            processes = []
            for _ in range(1 if lane == 'raw' else counts[name]):
                pid = len(children) + 42
                script, token = '/tmp/owned-' + str(pid) + '.zsh', 'owned-' + str(pid)
                value = {'pid': pid, 'ppid': 20, 'executable': '/bin/zsh', 'script': script, 'token': token, 'arguments': '/bin/zsh -f ' + script + ' ' + token, 'verified': True}
                processes.append(value)
                children.append(value.copy())
            cases.append({'id': name, 'passed': True, 'cleanupCompleted': True, 'probePID': 20, 'processes': processes, 'boundary': {}, 'outcomes': []})
        by_id = {case['id']: case for case in cases}
        if lane == 'raw':
            literal = '  <think>literal e\u0301 日本語</think>\n{"literal":true}\n  '
            by_id['captured-configuration'].update(boundary={'capturedTimeoutSeconds': 5, 'newCommandUnlaunched': True}, outcomes=[outcome('CAPTURED_EXACT')])
            by_id['raw-literal']['outcomes'] = [outcome(literal)]
            by_id['legacy-trim']['outcomes'] = [outcome(literal.strip())]
        else:
            by_id['pre-cancelled'].update(boundary={'completedWithinDeadline': True, 'commandLaunched': False, 'typedCancellation': True}, outcomes=[outcome(kind='cancellation')])
            by_id['cancel-blocked-stdin'].update(boundary={'completedWithinDeadline': True, 'childAliveAtBoundary': False, 'survivorAliveAtBoundary': True, 'survivorExactAfterRelease': True, 'typedCancellation': True, 'deadlineSeconds': 1.5, 'elapsedSeconds': 1.02, 'stdinBytes': 82000}, outcomes=[outcome(kind='cancellation'), outcome('SURVIVOR_EXACT')])
            by_id['dual-pipe'].update(boundary={'completedWithinDeadline': True, 'stdinBytes': 82000, 'stdinSHA256': 'f' * 64, 'expectedStdinSHA256': 'f' * 64, 'stdoutBytes': 131072, 'stdoutSHA256': digest(b'X' * 131072), 'expectedStdoutSHA256': digest(b'X' * 131072), 'stderrWrittenBytes': 131072}, outcomes=[outcome('X' * 131072)])
            by_id['timeout-blocked-stdin'].update(boundary={'completedWithinDeadline': True, 'configuredTimeoutSeconds': 5, 'elapsedSeconds': 6.02, 'typedTimeout': True, 'childAliveAtBoundary': False, 'stdinBytes': 82000}, outcomes=[outcome(kind='timeout', timeout=5)])
            by_id['exit-races'].update(boundary={'iterations': 3}, outcomes=[outcome('RACE_EXACT') for _ in range(3)])
            by_id['later-control'].update(boundary={'completedWithinDeadline': True}, outcomes=[outcome('LATER_CONTROL_EXACT')])
            if lane == 'baseline':
                by_id['pre-cancelled'].update(passed=False, outcomes=[outcome('PRE')])
                by_id['pre-cancelled']['boundary'].update(completedWithinDeadline=False, commandLaunched=True, typedCancellation=False)
                by_id['cancel-blocked-stdin'].update(passed=False, outcomes=[outcome('CANCEL_FINISHED'), outcome('SURVIVOR_EXACT')])
                by_id['cancel-blocked-stdin']['boundary'].update(completedWithinDeadline=False, childAliveAtBoundary=True, typedCancellation=False, elapsedSeconds=1.51)
                by_id['dual-pipe'].update(passed=False, outcomes=[outcome(kind='timeout', timeout=5)])
                by_id['dual-pipe']['boundary'].update(stdoutBytes=0, stdoutSHA256=digest(b''), stderrWrittenBytes=0)
                by_id['timeout-blocked-stdin'].update(passed=False, outcomes=[outcome('TIMEOUT_RELEASED')])
                by_id['timeout-blocked-stdin']['boundary'].update(completedWithinDeadline=False, childAliveAtBoundary=True, typedTimeout=False, elapsedSeconds=8.01)
        receipt = {'version': 1, 'lane': lane, 'sourceSHA256': OLD_HASH if lane == 'baseline' else 'new', 'bundleIdentifier': contract['bundles'][lane], 'probePID': 20, 'setupPassed': True, 'preferencesUnchanged': True, 'invalidReasons': [], 'cases': cases}
        supervisor = {'completed': True, 'watchdogFired': False, 'cleanupVerified': True, 'rootIdentityVerified': True, 'rootPID': 20, 'errors': [], 'exitCode': 1 if lane == 'baseline' else 0, 'executable': contract['executables'][lane], 'children': children}
        return receipt, supervisor
    results = {}
    for lane in ['baseline', 'candidate', 'raw']:
        receipt, supervisor = sample(lane)
        results[lane] = classify(receipt, lane, supervisor, contract)['valid']
    mutations = {
        'old-green': lambda r, s: (r['cases'][1].update(passed=True), s.update(exitCode=0)),
        'cancel-case-not-red': lambda r, s: r['cases'][1].update(passed=True),
        'setup-failure': lambda r, s: r.update(setupPassed=False),
        'setup-exit': lambda r, s: s.update(exitCode=2),
        'missing-case': lambda r, s: r['cases'].pop(),
        'wrong-pid': lambda r, s: s.update(rootPID=999),
        'wrong-case-pid': lambda r, s: r['cases'][1].update(probePID=999),
        'uncleaned-child': lambda r, s: r['cases'][1].update(cleanupCompleted=False),
        'source-mismatch': lambda r, s: r.update(sourceSHA256='wrong'),
        'watchdog': lambda r, s: s.update(watchdogFired=True),
        'unverified-supervisor-cleanup': lambda r, s: s.update(cleanupVerified=False),
        'unobserved-child': lambda r, s: s.update(children=[]),
        'missing-boundary-child': lambda r, s: r['cases'][1].update(processes=[]),
        'duplicate-boundary-child': lambda r, s: r['cases'][1].update(processes=[r['cases'][1]['processes'][0]] * 2),
        'wrong-executable': lambda r, s: s.update(executable='/tmp/foreign'),
        'wrong-script-args': lambda r, s: r['cases'][1]['processes'][0].update(arguments='/bin/zsh foreign'),
        'persistent-write': lambda r, s: r.update(preferencesUnchanged=False),
        'invalid-cleanup': lambda r, s: s.update(errors=['cleanup identity mismatch']),
        'corrupt-later-control': lambda r, s: r['cases'][5]['outcomes'][0].update(stdoutSHA256='wrong'),
        'later-control-red': lambda r, s: r['cases'][5].update(passed=False),
        'survivor-false': lambda r, s: r['cases'][1]['boundary'].update(survivorExactAfterRelease=False),
        'survivor-wrong-output': lambda r, s: r['cases'][1]['outcomes'][1].update(stdoutSHA256='wrong'),
        'race-red': lambda r, s: r['cases'][4].update(passed=False),
        'unrelated-pipe-error': lambda r, s: r['cases'][2]['outcomes'][0].update(errorKind='unexpected'),
    }
    for name, mutate in mutations.items():
        receipt, supervisor = copy.deepcopy(sample('baseline'))
        mutate(receipt, supervisor)
        results[name] = classify(receipt, 'baseline', supervisor, contract)['valid']
    candidate_mutations = {
        'candidate-cancel-not-typed': lambda r: r['cases'][1]['boundary'].update(typedCancellation=False),
        'candidate-timeout-not-five': lambda r: r['cases'][3]['boundary'].update(configuredTimeoutSeconds=.25),
        'candidate-timeout-too-late': lambda r: r['cases'][3]['boundary'].update(elapsedSeconds=8.1),
        'candidate-pipe-bytes': lambda r: r['cases'][2]['boundary'].update(stdoutBytes=1),
        'candidate-stderr-not-written': lambda r: r['cases'][2]['boundary'].update(stderrWrittenBytes=0)
    }
    for name, mutate in candidate_mutations.items():
        receipt, supervisor = copy.deepcopy(sample('candidate'))
        mutate(receipt)
        results[name] = classify(receipt, 'candidate', supervisor, contract)['valid']
    assert all(results[x] for x in ['baseline', 'candidate', 'raw']) and not any(results[x] for x in [*mutations, *candidate_mutations]), results
    print(json.dumps({'valid': True, 'fixtures': results}, indent=2))

command, *args = sys.argv[1:]
if command == 'self-test':
    self_test()
elif command == 'prepare':
    repo, out = map(Path, args)
    revision = git(repo, 'rev-parse', 'HEAD').decode().strip()
    if revision != os.environ.get('GITHUB_SHA'): raise SystemExit('Candidate HEAD must equal GITHUB_SHA')
    git(repo, 'cat-file', '-e', BASELINE + '^{commit}')
    relevant = [SERVICE, 'VoiceInkCore', 'VoiceInkNVIDIA', DRIVER, WORKFLOW]
    subprocess.run(['git', '-C', str(repo), 'diff', '--exit-code', 'HEAD', '--', *relevant], check=True)
    if git(repo, 'ls-files', '--others', '--exclude-standard', '--', *relevant).strip(): raise SystemExit('Untracked relevant source is forbidden')
    git(repo, 'ls-files', '--error-unmatch', DRIVER)
    baseline = source(repo, BASELINE, SERVICE)
    current = source(repo, revision, SERVICE)
    if digest(baseline) != OLD_HASH or baseline == current: raise SystemExit('Known-bad service bytes are wrong or candidate is unchanged')
    closure = snapshot(repo, revision, ['VoiceInkCore', 'VoiceInkNVIDIA'])
    old_closure = snapshot(repo, BASELINE, ['VoiceInkCore', 'VoiceInkNVIDIA'])
    write(out / 'baseline-dependencies.json', old_closure)
    write(out / 'candidate-dependencies.json', closure)
    if closure != old_closure: raise SystemExit('Actual Core/NVIDIA source closure differs between lanes')
    lock = source(repo, revision, 'VoiceInkCore/Package.resolved')
    if len(json.loads(lock)['pins']) != 22: raise SystemExit('Expected the real22pinCorelock')
    package = out / 'package'
    package.mkdir()
    archive = git(repo, 'archive', revision, 'VoiceInkCore', 'VoiceInkNVIDIA')
    dependencies = package / 'Dependencies'
    dependencies.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
        members = stream.getmembers()
        if any(Path(x.name).is_absolute() or '..' in Path(x.name).parts or not (x.isfile() or x.isdir()) for x in members): raise SystemExit('Unexpected dependency archive entry')
        stream.extractall(dependencies, members=members)
    names = {'baseline': 'OldLocalCLIProbe', 'candidate': 'NewLocalCLIProbe', 'raw': 'RawLocalCLIProbe'}
    bundles, executables = {}, {}
    for lane, name in names.items():
        target = package / 'Sources' / name
        target.mkdir(parents=True)
        (target / 'LocalCLIService.swift').write_bytes(baseline if lane == 'baseline' else current)
        (target / 'CommonProbe.swift').write_text(SWIFT)
        app = out / (name + '.app')
        (app / 'Contents/MacOS').mkdir(parents=True)
        bundles[lane] = 'com.negentropi.RomaJustTalk.CLILifetime.' + lane + '.' + uuid.uuid4().hex
        executables[lane] = str(app / 'Contents/MacOS' / name)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundles[lane], 'CFBundleExecutable': name, 'CFBundleName': name, 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0'}))
    manifest = '// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: "LocalCLILifetime", platforms: [.macOS(.v14)], dependencies: [.package(path: "Dependencies/VoiceInkCore")], targets: [\n'
    manifest += ',\n'.join('.executableTarget(name: "' + name + '", dependencies: [.product(name: "VoiceInkCore", package: "VoiceInkCore")]' + (', swiftSettings: [.define("RAW_PROBE")]' if lane == 'raw' else '') + ')' for lane, name in names.items())
    manifest += '\n], swiftLanguageVersions: [.v5])\n'
    (package / 'Package.swift').write_text(manifest)
    (package / 'Package.resolved').write_bytes(lock)
    target_sources = {str(path.relative_to(package)): digest(path.read_bytes()) for path in sorted((package / 'Sources').rglob('*')) if path.is_file()}
    contract = {'version': 1, 'baseline_sha': BASELINE, 'candidate_sha': revision, 'baseline_service_sha256': OLD_HASH, 'candidate_service_sha256': digest(current), 'driver_sha256': digest(source(repo, revision, DRIVER)), 'workflow_sha256': digest(source(repo, revision, WORKFLOW)), 'common_probe_sha256': digest(SWIFT.encode()), 'target_sources': target_sources, 'package_manifest_sha256': digest(manifest.encode()), 'package_lock_sha256': digest(lock), 'dependency_manifest': closure, 'bundles': bundles, 'executables': executables, 'targets': names, 'scope': 'Unchanged production LocalCLIService and complete real Core/NVIDIA dependencies. Direct child lifetime only. No app lifecycle, descendants, provider credentials, Keychain or TCC.'}
    write(out / 'contract.json', contract)
    write(out / 'source-before.json', {**closure, SERVICE: digest(current), DRIVER: contract['driver_sha256'], WORKFLOW: contract['workflow_sha256']})
elif command == 'verify':
    repo, out = map(Path, args)
    contract = json.loads((out / 'contract.json').read_text())
    expected = json.loads((out / 'source-before.json').read_text())
    actual = {path: digest((repo / path).read_bytes()) for path in expected}
    if actual != expected or git(repo, 'rev-parse', 'HEAD').decode().strip() != contract['candidate_sha']: raise SystemExit('Committed source changed during proof')
    package = out / 'package'
    for lane, name in contract['targets'].items():
        folder = package / 'Sources' / name
        expected_service = contract['baseline_service_sha256'] if lane == 'baseline' else contract['candidate_service_sha256']
        if digest((folder / 'LocalCLIService.swift').read_bytes()) != expected_service or digest((folder / 'CommonProbe.swift').read_bytes()) != contract['common_probe_sha256']: raise SystemExit('Probe/service source bytes changed')
    generated = {str(path.relative_to(package)): digest(path.read_bytes()) for path in sorted((package / 'Sources').rglob('*')) if path.is_file()}
    if generated != contract['target_sources']: raise SystemExit('Generated target source census or bytes changed')
    dependencies = package / 'Dependencies'
    closure = {str(path.relative_to(dependencies)): digest(path.read_bytes()) for path in sorted(dependencies.rglob('*')) if path.is_file()}
    if closure != contract['dependency_manifest']: raise SystemExit('Dependency snapshot census or bytes changed')
    if digest((package / 'Package.resolved').read_bytes()) != contract['package_lock_sha256'] or digest((package / 'Package.swift').read_bytes()) != contract['package_manifest_sha256']: raise SystemExit('Frozen root manifest or lock changed')
    write(out / 'source-after.json', actual)
    write(out / 'source-verification.json', {'valid': True, 'candidate_sha': contract['candidate_sha'], 'baseline_sha': BASELINE, 'common_probe_sha256': contract['common_probe_sha256']})
elif command == 'bundle-manifests':
    out, phase = Path(args[0]), args[1]
    contract = json.loads((out / 'contract.json').read_text())
    values = {}
    for lane, name in contract['targets'].items():
        app = out / (name + '.app')
        metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        if metadata.get('CFBundleIdentifier') != contract['bundles'][lane] or metadata.get('CFBundleExecutable') != name: raise SystemExit('Signed wrapper identity mismatch')
        values[lane] = {str(path.relative_to(app)): digest(path.read_bytes()) for path in sorted(app.rglob('*')) if path.is_file()}
    write(out / ('wrapper-' + phase + '.json'), values)
    if phase == 'after':
        if values != json.loads((out / 'wrapper-before.json').read_text()): raise SystemExit('Signed wrapper contents changed')
        write(out / 'identity-verification.json', {'valid': True, 'wrappers': values})
elif command == 'supervise':
    out, lane = Path(args[0]), args[1]
    contract = json.loads((out / 'contract.json').read_text())
    folder = out / lane
    folder.mkdir()
    executable = contract['executables'][lane]
    source_hash = contract['baseline_service_sha256'] if lane == 'baseline' else contract['candidate_service_sha256']
    errors, children, verified, actions = [], {}, False, []
    def identity(pid):
        try:
            result = subprocess.run(['/bin/ps', '-ww', '-p', str(pid), '-o', 'ppid=,comm=,args='], capture_output=True, text=True, timeout=2)
            fields = result.stdout.strip().split(None, 2)
            return (int(fields[0]), fields[1], fields[2]) if result.returncode == 0 and len(fields) == 3 else None
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            errors.append('Bounded process identity observation failed: ' + str(error))
            return None
    def registry():
        path = folder / 'registry.json'
        if not path.exists(): return []
        try:
            result = json.loads(path.read_text())
            for item in result:
                script, ready, release = [Path(item[name]) for name in ['script', 'ready', 'release']]
                if not script.is_relative_to(folder) or script.parent != ready.parent or script.parent != release.parent or script.name != 'command.zsh' or ready.name != 'ready' or release.name != 'release' or not re.fullmatch('[0-9A-Fa-f-]{36}', item['token']): raise ValueError('Registry path/token is not owned')
            return result
        except (ValueError, OSError, KeyError, TypeError) as error:
            errors.append('Invalid owned registry: ' + str(error))
            return []
    def observe(item):
        ready = Path(item['ready'])
        if not ready.exists(): return
        try:
            pid, parent = map(int, ready.read_text().split())
            key = (pid, item['script'], item['token'])
            if key in children: return
            current = identity(pid)
            if current is None: return
            expected_args = '/bin/zsh -f ' + item['script'] + ' ' + item['token']
            correct = parent == process.pid and current == (process.pid, '/bin/zsh', expected_args)
            if not correct:
                errors.append('READY child PID/PPID/executable/script identity mismatch')
                return
            children[key] = {'pid': pid, 'ppid': parent, 'executable': current[1], 'arguments': current[2], 'script': item['script'], 'token': item['token'], 'verified': True}
            temporary = ready.parent / 'supervisor-verified.tmp'
            write(temporary, {'pid': pid, 'token': item['token']})
            temporary.replace(ready.parent / 'supervisor-verified')
        except (ValueError, OSError, KeyError) as error:
            errors.append('Malformed owned READY record: ' + str(error))
    def release_gates():
        for item in registry():
            ready = Path(item['ready'])
            if not ready.exists(): continue
            try:
                pid, original_parent = map(int, ready.read_text().split())
                current = identity(pid)
                expected_args = '/bin/zsh -f ' + item['script'] + ' ' + item['token']
                if current is None: continue
                if original_parent != process.pid or current[1:] != ('/bin/zsh', expected_args) or current[0] not in [process.pid, 1]:
                    errors.append('Gate release refused a foreign process identity')
                    continue
                Path(item['release']).touch()
                actions.append({'action': 'fixture-gate-release', 'pid': pid, 'script': item['script'], 'scope': 'Harness cleanup after native boundary. Never production-service cleanup.'})
            except (ValueError, OSError) as error:
                errors.append('Gate cleanup failed: ' + str(error))
    def living_owned():
        live = []
        for item in registry():
            ready = Path(item['ready'])
            if not ready.exists(): continue
            try:
                pid, parent = map(int, ready.read_text().split())
                current = identity(pid)
                if current is not None: live.append({'pid': pid, 'originalPPID': parent, 'current': current, 'script': item['script']})
            except (ValueError, OSError) as error: errors.append('Cleanup identity read failed: ' + str(error))
        return live
    with (folder / 'stdout.log').open('wb') as stdout, (folder / 'stderr.log').open('wb') as stderr:
        try:
            process = subprocess.Popen([executable, str(folder), lane, contract['bundles'][lane], source_hash], stdout=stdout, stderr=stderr)
        except OSError as error:
            write(folder / 'supervisor.json', {'completed': False, 'watchdogFired': False, 'cleanupVerified': True, 'rootIdentityVerified': False, 'executable': executable, 'errors': ['Probe launch failed: ' + str(error)]})
            raise SystemExit(1)
        started, watchdog = time.monotonic(), False
        try:
            while process.poll() is None and time.monotonic() - started < 120:
                root = identity(process.pid)
                if root:
                    if root[0] != os.getpid() or root[1] != executable:
                        errors.append('Probe root PID/PPID/executable identity mismatch')
                        break
                    verified = True
                for item in registry(): observe(item)
                time.sleep(.02)
        except Exception as error:
            errors.append('Probe observation failed: ' + str(error))
        finally:
            if process.poll() is None:
                watchdog = True
                errors.append('Probe watchdog or root identity guard fired')
            release_gates()
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline and (process.poll() is None or living_owned()):
                time.sleep(.02)
            if process.poll() is None:
                watchdog = True
                errors.append('Owned probe root required watchdog termination')
                try:
                    process.kill()
                    process.wait(timeout=3)
                except (OSError, subprocess.TimeoutExpired) as error:
                    errors.append('Owned root watchdog cleanup failed: ' + str(error))
            release_gates()
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and living_owned(): time.sleep(.02)
            remaining = living_owned()
            if remaining: errors.append('Owned fixture children did not exit naturally; no grandchild signals were sent')
    result = {'completed': process.poll() is not None, 'watchdogFired': watchdog, 'cleanupVerified': not remaining, 'cleanupActions': actions, 'remainingChildren': remaining, 'rootIdentityVerified': verified, 'rootPID': process.pid, 'executable': executable, 'exitCode': process.poll(), 'children': list(children.values()), 'errors': sorted(set(errors)), 'scope': 'Runtime PID/PPID/executable and exact owned script arguments. Fixture gate release and outer watchdog cleanup never count as service cleanup. Only the unreaped direct Popen root may be signaled.'}
    write(folder / 'supervisor.json', result)
    if not result['completed'] or errors: raise SystemExit(1)
elif command == 'classify':
    out = Path(args[0])
    contract = json.loads((out / 'contract.json').read_text())
    lanes = {}
    for lane in ['baseline', 'candidate', 'raw']:
        folder = out / lane
        receipt = json.loads((folder / 'result.json').read_text()) if (folder / 'result.json').exists() else {}
        supervisor = json.loads((folder / 'supervisor.json').read_text()) if (folder / 'supervisor.json').exists() else {}
        lanes[lane] = classify(receipt, lane, supervisor, contract)
        write(folder / 'classification.json', lanes[lane])
    valid = all(value['valid'] for value in lanes.values()) and all(json.loads((out / name).read_text()).get('valid') is True for name in ['source-verification.json', 'identity-verification.json'])
    result = {'valid': valid, 'classification': 'matched-old-red-new-green' if valid else 'invalid-or-failed', 'candidate_sha': contract['candidate_sha'], 'baseline_sha': BASELINE, 'common_probe_sha256': contract['common_probe_sha256'], 'lanes': {lane: {'valid': value['valid'], 'classification': value['classification'], 'failedCases': value['failedCases']} for lane, value in lanes.items()}, 'scope': contract['scope']}
    write(out / 'comparison-result.json', result)
    print(json.dumps(result, indent=2))
    if not valid: raise SystemExit(1)
else:
    raise SystemExit('Unknown proof operation')
PY
}

if [[ "${1:-}" == --self-test ]]; then
  proof self-test
  exit
fi
if [[ "$#" != 0 || "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin || "$(id -u)" == 0 ]]; then
  echo "Use --self-test locally. Native proof requires a fresh non-root GitHub-hosted Mac." >&2
  exit 2
fi
repo="$(cd "$(dirname "$0")/.." && pwd)"
out="$RUNNER_TEMP/local-cli-lifetime-check"
test ! -e "$out"
mkdir -m 700 "$out"
phase=prepare
trap 'code=$?; if [[ "$code" != 0 ]]; then printf "{\"valid\":false,\"phase\":\"%s\",\"exitCode\":%s}\n" "$phase" "$code" > "$out/failure.json"; fi' EXIT
{
  xcodebuild -version
  swift --version
  sw_vers
  uname -m
} > "$out/toolchain.txt" 2>&1
proof prepare "$repo" "$out"
phase=build
xcrun swift build --package-path "$out/package" --configuration debug --force-resolved-versions --skip-update > "$out/build.log" 2>&1
xcrun swift build --package-path "$out/package" --configuration debug --force-resolved-versions --skip-update --show-bin-path > "$out/bin-path.txt" 2>> "$out/build.log"
bin="$(cat "$out/bin-path.txt")"
for name in OldLocalCLIProbe NewLocalCLIProbe RawLocalCLIProbe; do
  app="$out/$name.app"
  cp "$bin/$name" "$app/Contents/MacOS/$name"
  mkdir -p "$app/Contents/Resources"
  for resource in "$bin/"*.bundle; do
    [[ -d "$resource" ]] || continue
    ditto "$resource" "$app/Contents/Resources/$(basename "$resource")"
  done
  codesign --force --sign - --identifier "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" "$app" > "$out/$name-sign.log" 2>&1
  codesign --verify --deep --strict "$app"
  codesign --display --verbose=4 "$app" > "$out/$name-signature-before.txt" 2>&1
  shasum -a 256 "$app/Contents/MacOS/$name" "$app/Contents/Info.plist" > "$out/$name-binary-before.txt"
done
proof bundle-manifests "$out" before
proof verify "$repo" "$out"
phase=probes
for lane in baseline candidate raw; do
  proof supervise "$out" "$lane" || true
done
phase=verify
for name in OldLocalCLIProbe NewLocalCLIProbe RawLocalCLIProbe; do
  app="$out/$name.app"
  codesign --verify --deep --strict "$app"
  codesign --display --verbose=4 "$app" > "$out/$name-signature-after.txt" 2>&1
  shasum -a 256 "$app/Contents/MacOS/$name" "$app/Contents/Info.plist" > "$out/$name-binary-after.txt"
  cmp "$out/$name-signature-before.txt" "$out/$name-signature-after.txt"
  cmp "$out/$name-binary-before.txt" "$out/$name-binary-after.txt"
done
proof bundle-manifests "$out" after
proof verify "$repo" "$out"
phase=classify
proof classify "$out"
