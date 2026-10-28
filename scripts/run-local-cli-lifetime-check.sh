#!/usr/bin/env bash
set -euo pipefail

proof() {
  python3 - "$@" <<'PY'
import copy
import ast
import ctypes
import errno
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
from types import SimpleNamespace

BASELINE = 'aaaa286a794ac6f60773ef5149a30f214c586f23'
SERVICE = 'VoiceInk/Services/AIEnhancement/LocalCLIService.swift'
OLD_HASH = '3cd0a32d213f3650c33e7c62c8e10d0c6957078442f7feceffa5f8c7d5e6ec8c'
DRIVER = 'scripts/run-local-cli-lifetime-check.sh'
WORKFLOW = '.github/workflows/voiceink-local-cli-lifetime-check.yml'
IDENTITY_FIXTURE = 'docs/research/competitors/evidence/local-cli-lifetime-40566195249/darwin-ps-shape-observation.json'
OLD_PARSER = '919670ae5b918afbfad6f4d88982a481c1c4b532'
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
def parse_ps_fields(parent_stdout, arguments_stdout):
    parent = parent_stdout.strip()
    if not re.fullmatch('[0-9]+', parent): raise ValueError('Expected exactly one numeric PPID field')
    return {'ppid': int(parent), 'arguments': arguments_stdout.rstrip('\r\n')}
def identity_differences(expected, actual):
    differences = []
    if actual.get('pid') != expected.get('pid'): differences.append('pid')
    if actual.get('ppid') not in expected.get('allowedPPIDs', []): differences.append('ppid')
    if actual.get('arguments') != expected.get('arguments'): differences.append('arguments')
    if not expected.get('realpath') or actual.get('realpath') != expected['realpath']: differences.append('image-realpath')
    wanted, observed = expected.get('fileIdentity', {}), actual.get('fileIdentity', {})
    if not wanted or any(not isinstance(wanted.get(key), int) or wanted.get(key) != observed.get(key) for key in ['device', 'inode']): differences.append('image-device-inode')
    if actual.get('captureErrors'): differences.append('capture-errors')
    return differences
def parser_regression(repo):
    captured = json.loads((repo / IDENTITY_FIXTURE).read_text())
    old_source = source(repo, OLD_PARSER, DRIVER).decode()
    old_python = old_source.split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
    functions = [node for node in ast.walk(ast.parse(old_python)) if isinstance(node, ast.FunctionDef) and node.name == 'identity']
    if len(functions) != 1: raise ValueError('Pinned old parser extraction is not unique')
    results = []
    for row in captured['observations']:
        def old_ps(command, **kwargs):
            if command != ['/bin/ps', '-ww', '-p', str(row['pid']), '-o', 'ppid=,comm=,args=']: raise ValueError('Unexpected old parser command')
            return SimpleNamespace(returncode=0, stdout=row['rows']['ppid=,comm=,args='], stderr='')
        namespace = {'subprocess': SimpleNamespace(run=old_ps, SubprocessError=subprocess.SubprocessError), 'errors': []}
        exec(compile(ast.Module(body=functions, type_ignores=[]), '<pinned-old-identity>', 'exec'), namespace)
        old_actual = namespace['identity'](row['pid'])
        expected = {'pid': row['pid'], 'allowedPPIDs': [row['expected_ppid']], 'arguments': ' '.join(row['argv']), 'realpath': row['expected_realpath'], 'fileIdentity': row['expected_file_identity']}
        actual = {'pid': row['pid'], **parse_ps_fields(row['rows']['ppid='], row['rows']['args=']), 'realpath': row['observed_realpath'], 'fileIdentity': row['observed_file_identity'], 'kernelImage': row['kernel_image']}
        differences = identity_differences(expected, actual)
        old_valid = old_actual == (row['expected_ppid'], row['executable'], ' '.join(row['argv']))
        assert not old_valid and not differences, (old_actual, differences)
        for field, value in [('ppid', row['expected_ppid'] + 1), ('arguments', 'foreign'), ('realpath', '/foreign'), ('fileIdentity', {'device': -1, 'inode': -1})]:
            assert identity_differences(expected, {**actual, field: value}), field
        results.append({'pid': row['pid'], 'old_parser_rejected': not old_valid, 'old_actual': old_actual, 'new_identity_accepted': not differences, 'expected': expected, 'actual': actual, 'differences': differences})
    if len(results) != 2: raise ValueError('Expected both captured native long-path and spaces observations')
    return {'valid': True, 'fixture_sha256': digest((repo / IDENTITY_FIXTURE).read_bytes()), 'old_parser_revision': OLD_PARSER, 'old_parser_source_sha256': digest(old_source.encode()), 'observations': results}
def observed_identity_valid(value):
    identity = value.get('identity', {})
    expected, actual, rows = [identity.get(name, {}) for name in ['expected', 'actual', 'rawPS']]
    return identity.get('verified') is True and not identity.get('differences') and not identity_differences(expected, actual) and expected.get('pid') == value.get('pid') and expected.get('allowedPPIDs') == [value.get('ppid')] and expected.get('executable') == value.get('executable') and actual.get('kernelReturnCode', 0) > 0 and all(rows.get(field, {}).get('exitCode') == 0 and rows.get(field, {}).get('timedOut') is False for field in ['ppid', 'args'])
def case_valid(case):
    processes = case.get('processes', [])
    return case.get('cleanupCompleted') is True and not case.get('invalidReason') and len({value.get('pid') for value in processes}) == len(processes) and all(
        value.get('verified') is True and isinstance(value.get('pid'), int) and value['pid'] > 0
        and value.get('ppid') == case.get('probePID') and value.get('executable') == '/bin/zsh'
        and value.get('arguments') == '/bin/zsh -f ' + value.get('script', '') + ' ' + value.get('token', '')
        and observed_identity_valid(value)
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
    static func fileIdentity(_ path: String) -> [String: Any] {
        guard let attributes = try? fm.attributesOfItem(atPath: path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return [:] }
        return ["device": device.uint64Value, "inode": inode.uint64Value]
    }
    static func psField(_ pid: pid_t, field: String) -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        let arguments = ["-ww", "-p", String(pid), "-o", field + "="]
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        var captureErrors: [String] = []
        for handle in [output.fileHandleForReading, errors.fileHandleForReading] {
            let flags = fcntl(handle.fileDescriptor, F_GETFL)
            if flags < 0 || fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) < 0 { captureErrors.append("Could not make ps capture nonblocking") }
        }
        var finished = false
        do {
            try process.run()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            finished = ended.wait(timeout: .now() + 2) == .success
            if !finished { captureErrors.append("ps observation exceeded two seconds") }
        } catch { captureErrors.append("ps launch failed: " + String(describing: error)) }
        func read(_ handle: FileHandle) -> String {
            var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = bytes.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, 4096) }
                if count > 0 { data.append(contentsOf: bytes.prefix(count)) }
                else if count < 0 && errno == EINTR { continue }
                else {
                    if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK { captureErrors.append("ps capture read failed: " + String(errno)) }
                    break
                }
            }
            try? handle.close()
            return String(decoding: data, as: UTF8.self)
        }
        let stdout = read(output.fileHandleForReading), stderr = read(errors.fileHandleForReading)
        return ["command": ["/bin/ps"] + arguments, "stdout": stdout, "stderr": stderr, "exitCode": finished ? Int(process.terminationStatus) : NSNull(), "timedOut": !finished, "captureErrors": captureErrors]
    }
    static func processIdentity(_ pid: pid_t, arguments: String) -> [String: Any] {
        var buffer = [CChar](repeating: 0, count: 4096)
        let capacity = UInt32(buffer.count)
        let count = proc_pidpath(pid, &buffer, capacity)
        let kernelErrno = count > 0 ? 0 : errno
        let image = count > 0 ? String(cString: buffer) : ""
        let expectedPath = URL(fileURLWithPath: "/bin/zsh").resolvingSymlinksInPath().path
        let observedPath = image.isEmpty ? "" : URL(fileURLWithPath: image).resolvingSymlinksInPath().path
        let parent = psField(pid, field: "ppid"), argv = psField(pid, field: "args")
        let parentText = (parent["stdout"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let observedParent = Int(parentText)
        let observedArguments = (argv["stdout"] as? String ?? "").trimmingCharacters(in: .newlines)
        let expectedFile = fileIdentity(expectedPath), actualFile = fileIdentity(observedPath)
        var differences: [String] = []
        if observedParent != Int(getpid()) { differences.append("ppid") }
        if observedArguments != arguments { differences.append("arguments") }
        if count <= 0 { differences.append("kernel-image") }
        if expectedPath != observedPath { differences.append("image-realpath") }
        if expectedFile.isEmpty || (expectedFile["device"] as? UInt64) != (actualFile["device"] as? UInt64) || (expectedFile["inode"] as? UInt64) != (actualFile["inode"] as? UInt64) { differences.append("image-device-inode") }
        let captureErrors = (parent["captureErrors"] as? [String] ?? []) + (argv["captureErrors"] as? [String] ?? [])
        if (parent["exitCode"] as? Int) != 0 || (argv["exitCode"] as? Int) != 0 || !captureErrors.isEmpty { differences.append("ps-capture") }
        let expected: [String: Any] = ["pid": Int(pid), "allowedPPIDs": [Int(getpid())], "arguments": arguments, "executable": "/bin/zsh", "realpath": expectedPath, "fileIdentity": expectedFile]
        let actual: [String: Any] = ["pid": Int(pid), "ppid": observedParent.map { $0 as Any } ?? NSNull(), "arguments": observedArguments, "kernelImage": image, "kernelReturnCode": Int(count), "kernelErrno": Int(kernelErrno), "realpath": observedPath, "fileIdentity": actualFile, "captureErrors": captureErrors]
        return ["expected": expected, "actual": actual, "rawPS": ["ppid": parent, "args": argv], "differences": differences, "verified": differences.isEmpty]
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
        let arguments = "/bin/zsh -f " + script + " " + token
        var identity = processIdentity(pid, arguments: arguments)
        if parent != getpid() {
            identity["differences"] = (identity["differences"] as? [String] ?? []) + ["ready-ppid"]
            identity["verified"] = false
        }
        let observation: [String: Any] = ["pid": Int(pid), "ppid": Int(parent), "executable": "/bin/zsh", "arguments": arguments, "script": script, "token": token, "verified": identity["verified"] as? Bool ?? false, "identity": identity]
        try save("identity-" + directory.lastPathComponent + ".json", observation)
        try require(identity["verified"] as? Bool == true, "READY PID/PPID/kernel-image/device-inode/script arguments did not identify the direct child")
        let acknowledgment = directory.appendingPathComponent("supervisor-verified")
        try require(await wait(2) { fm.fileExists(atPath: acknowledgment.path) }, "Independent supervisor did not acknowledge the exact child identity")
        let acknowledged = try JSONSerialization.jsonObject(with: Data(contentsOf: acknowledgment)) as? [String: Any]
        try require(acknowledged?["pid"] as? Int == Int(pid) && acknowledged?["token"] as? String == token, "Independent READY acknowledgment identified another child")
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

def self_test(repo):
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
                expected = {'pid': pid, 'allowedPPIDs': [20], 'executable': '/bin/zsh', 'arguments': value['arguments'], 'realpath': '/bin/zsh', 'fileIdentity': {'device': 1, 'inode': 2}}
                value['identity'] = {'verified': True, 'differences': [], 'expected': expected, 'actual': {'pid': pid, 'ppid': 20, 'arguments': value['arguments'], 'kernelReturnCode': 9, 'realpath': '/bin/zsh', 'fileIdentity': {'device': 1, 'inode': 2}}, 'rawPS': {field: {'exitCode': 0, 'timedOut': False} for field in ['ppid', 'args']}}
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
        'wrong-kernel-inode': lambda r, s: r['cases'][1]['processes'][0]['identity']['actual']['fileIdentity'].update(inode=999),
        'wrong-kernel-realpath': lambda r, s: r['cases'][1]['processes'][0]['identity']['actual'].update(realpath='/foreign'),
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
    regression = parser_regression(repo)
    print(json.dumps({'valid': True, 'fixtures': results, 'recorded_native_parser_regression': regression}, indent=2))

command, *args = sys.argv[1:]
if command == 'self-test':
    self_test(Path(args[0]))
elif command == 'prepare':
    repo, out = map(Path, args)
    revision = git(repo, 'rev-parse', 'HEAD').decode().strip()
    if revision != os.environ.get('GITHUB_SHA'): raise SystemExit('Candidate HEAD must equal GITHUB_SHA')
    git(repo, 'cat-file', '-e', BASELINE + '^{commit}')
    relevant = [SERVICE, 'VoiceInkCore', 'VoiceInkNVIDIA', DRIVER, WORKFLOW, IDENTITY_FIXTURE]
    subprocess.run(['git', '-C', str(repo), 'diff', '--exit-code', 'HEAD', '--', *relevant], check=True)
    if git(repo, 'ls-files', '--others', '--exclude-standard', '--', *relevant).strip(): raise SystemExit('Untracked relevant source is forbidden')
    git(repo, 'ls-files', '--error-unmatch', DRIVER)
    parser_proof = parser_regression(repo)
    write(out / 'identity-parser-regression.json', parser_proof)
    (out / 'darwin-ps-shape-observation.json').write_bytes((repo / IDENTITY_FIXTURE).read_bytes())
    (out / 'old-identity-parser-source.txt').write_bytes(source(repo, OLD_PARSER, DRIVER))
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
    contract = {'version': 1, 'baseline_sha': BASELINE, 'candidate_sha': revision, 'baseline_service_sha256': OLD_HASH, 'candidate_service_sha256': digest(current), 'driver_sha256': digest(source(repo, revision, DRIVER)), 'workflow_sha256': digest(source(repo, revision, WORKFLOW)), 'identity_fixture_sha256': parser_proof['fixture_sha256'], 'old_parser_revision': OLD_PARSER, 'old_parser_source_sha256': parser_proof['old_parser_source_sha256'], 'common_probe_sha256': digest(SWIFT.encode()), 'target_sources': target_sources, 'package_manifest_sha256': digest(manifest.encode()), 'package_lock_sha256': digest(lock), 'dependency_manifest': closure, 'bundles': bundles, 'executables': executables, 'targets': names, 'scope': 'Unchanged production LocalCLIService and complete real Core/NVIDIA dependencies. Direct child lifetime only. No app lifecycle, descendants, provider credentials, Keychain or TCC.'}
    write(out / 'contract.json', contract)
    write(out / 'source-before.json', {**closure, SERVICE: digest(current), DRIVER: contract['driver_sha256'], WORKFLOW: contract['workflow_sha256'], IDENTITY_FIXTURE: contract['identity_fixture_sha256']})
elif command == 'verify':
    repo, out = map(Path, args)
    contract = json.loads((out / 'contract.json').read_text())
    expected = json.loads((out / 'source-before.json').read_text())
    actual = {path: digest((repo / path).read_bytes()) for path in expected}
    if actual != expected or git(repo, 'rev-parse', 'HEAD').decode().strip() != contract['candidate_sha']: raise SystemExit('Committed source changed during proof')
    if digest((out / 'darwin-ps-shape-observation.json').read_bytes()) != contract['identity_fixture_sha256'] or digest((out / 'old-identity-parser-source.txt').read_bytes()) != contract['old_parser_source_sha256']: raise SystemExit('Retained native shape fixture or pinned old parser source changed')
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
    library = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    kernel_path = library.proc_pidpath
    kernel_path.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    kernel_path.restype = ctypes.c_int
    def identity(pid, image, arguments, parents, phase):
        buffer = ctypes.create_string_buffer(4096)
        ctypes.set_errno(0)
        count = kernel_path(pid, buffer, len(buffer))
        kernel_errno = ctypes.get_errno() if count <= 0 else 0
        kernel_image = os.fsdecode(buffer.value) if count > 0 else ''
        if count <= 0 and kernel_errno != errno.ESRCH:
            errors.append('Kernel process image observation failed with errno ' + str(kernel_errno))
        raw, capture_errors = {}, []
        for field in ['ppid', 'args']:
            command = ['/bin/ps', '-ww', '-p', str(pid), '-o', field + '=']
            try:
                value = subprocess.run(command, capture_output=True, text=True, timeout=2)
                raw[field] = {'command': command, 'stdout': value.stdout, 'stderr': value.stderr, 'exitCode': value.returncode, 'timedOut': False}
            except (OSError, subprocess.SubprocessError) as error:
                stdout, stderr = getattr(error, 'stdout', '') or '', getattr(error, 'stderr', '') or ''
                raw[field] = {'command': command, 'stdout': stdout.decode(errors='replace') if isinstance(stdout, bytes) else stdout, 'stderr': stderr.decode(errors='replace') if isinstance(stderr, bytes) else stderr, 'exitCode': None, 'timedOut': isinstance(error, subprocess.TimeoutExpired), 'error': str(error)}
                capture_errors.append(field + ': ' + str(error))
                errors.append('Bounded process observation failed: ' + str(error))
        expected_path, actual_path = os.path.realpath(image), os.path.realpath(kernel_image) if kernel_image else ''
        def file_identity(path):
            if not path: return {}
            try:
                value = os.stat(path)
                return {'device': value.st_dev, 'inode': value.st_ino}
            except OSError as error:
                capture_errors.append('stat ' + path + ': ' + str(error))
                return {}
        expected = {'pid': pid, 'allowedPPIDs': parents, 'executable': image, 'arguments': arguments, 'realpath': expected_path, 'fileIdentity': file_identity(expected_path)}
        actual = {'pid': pid, 'kernelImage': kernel_image, 'kernelReturnCode': count, 'kernelErrno': kernel_errno, 'realpath': actual_path, 'fileIdentity': file_identity(actual_path), 'captureErrors': capture_errors}
        try: actual.update(parse_ps_fields(raw['ppid']['stdout'], raw['args']['stdout']))
        except ValueError as error:
            actual.update(ppid=None, arguments=raw['args']['stdout'].rstrip('\r\n'))
            capture_errors.append(str(error))
        ps_ok = all(value.get('exitCode') == 0 for value in raw.values())
        if not ps_ok: capture_errors.append('A separate ps field did not return zero')
        gone = count <= 0 and kernel_errno == errno.ESRCH and all(value.get('exitCode') == 1 and not value.get('stdout') and not value.get('stderr') and not value.get('timedOut') for value in raw.values())
        state = 'gone' if gone else 'running' if count > 0 and ps_ok else 'changing'
        differences = identity_differences(expected, actual)
        result = {'phase': phase, 'state': state, 'expected': expected, 'actual': actual, 'rawPS': raw, 'differences': differences, 'verified': state == 'running' and not differences}
        with (folder / 'process-observations.jsonl').open('a') as stream:
            stream.write(json.dumps(result, sort_keys=True) + '\n')
        return result
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
            expected_args = '/bin/zsh -f ' + item['script'] + ' ' + item['token']
            current = identity(pid, '/bin/zsh', expected_args, [process.pid], 'child-ready')
            if current['state'] != 'running': return
            correct = parent == process.pid and current['verified']
            if not correct:
                errors.append('READY child PID/PPID/executable/script identity mismatch')
                return
            children[key] = {'pid': pid, 'ppid': parent, 'executable': '/bin/zsh', 'arguments': expected_args, 'script': item['script'], 'token': item['token'], 'verified': True, 'identity': current}
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
                expected_args = '/bin/zsh -f ' + item['script'] + ' ' + item['token']
                current = identity(pid, '/bin/zsh', expected_args, [process.pid, 1], 'gate-cleanup')
                if current['state'] == 'gone': continue
                if original_parent != process.pid or not current['verified']:
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
                arguments = '/bin/zsh -f ' + item['script'] + ' ' + item['token']
                current = identity(pid, '/bin/zsh', arguments, [process.pid, 1], 'child-cleanup-readback')
                if current['state'] != 'gone': live.append({'pid': pid, 'originalPPID': parent, 'current': current, 'script': item['script']})
            except (ValueError, OSError) as error: errors.append('Cleanup identity read failed: ' + str(error))
        return live
    with (folder / 'stdout.log').open('wb') as stdout, (folder / 'stderr.log').open('wb') as stderr:
        try:
            launch_arguments = [executable, str(folder), lane, contract['bundles'][lane], source_hash]
            process = subprocess.Popen(launch_arguments, stdout=stdout, stderr=stderr)
        except OSError as error:
            write(folder / 'supervisor.json', {'completed': False, 'watchdogFired': False, 'cleanupVerified': True, 'rootIdentityVerified': False, 'executable': executable, 'errors': ['Probe launch failed: ' + str(error)]})
            raise SystemExit(1)
        started, watchdog = time.monotonic(), False
        try:
            while process.poll() is None and time.monotonic() - started < 120:
                root = identity(process.pid, executable, ' '.join(launch_arguments), [os.getpid()], 'probe-root')
                if root['state'] == 'running':
                    if not root['verified']:
                        errors.append('Probe root PID/PPID/kernel-image/device-inode/arguments identity mismatch')
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
  proof self-test "$(cd "$(dirname "$0")/.." && pwd)"
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
