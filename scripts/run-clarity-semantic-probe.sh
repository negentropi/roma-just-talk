#!/usr/bin/env bash
set -euo pipefail

python3 - "${1:-}" "$0" "${@:2}" <<'PY'
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid
from pathlib import Path

MODE, SCRIPT, *ARGS = sys.argv[1:]
SCRIPT = Path(SCRIPT).resolve()
GENERATOR = 'scripts/run-writing-local-cli-service-probe.sh'
WORKFLOW = '.github/workflows/voiceink-clarity-semantic-probe.yml'
INPUT = 'docs/research/competitors/fixtures/clarity-inputs.json'
RUBRIC = 'docs/research/competitors/fixtures/clarity-private-rubric.json'
LOCK = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
STYLES = ['natural', 'casual', 'formal']
CASE_IDS = ['C%02d' % value for value in range(1, 10)]
EXPECTED = [case + '-' + style for case in CASE_IDS for style in STYLES]
SCOPE = 'Twenty-seven synthetic inputs through actual AIEnhancementService.performClarity and LocalCLIService. No app lifecycle, ASR, microphone, storage, UI, editor delivery or general model-quality proof. Semantic grading remains independent.'

DRIVER = r'''
import AppKit
import CryptoKit
import Darwin
import Foundation
import SwiftData
import VoiceInkCore

private enum ProbeFailure: Error { case invalid(String) }
private struct Sample: Decodable { let id: String; let transcript: String }
private struct RunConfiguration: Decodable {
    let evidencePath: String
    let generationPath: String
    let inputsPath: String
    let commandTemplate: String
    let manifestSHA256: String
}

@main private enum ClaritySemanticProbe {
    static let sourceSHA = "__SOURCE_SHA__"
    static let bundleIdentifier = "__BUNDLE_ID__"
    static let inputSHA256 = "__INPUT_SHA256__"
    static let timeout: Double = 120

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func text(_ value: String) -> [String: Any] {
        let utf16 = Data(value.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] })
        return ["text": value, "utf8SHA256": hash(Data(value.utf8)), "utf16LESHA256": hash(utf16),
                "utf8Count": value.utf8.count, "utf16Count": value.utf16.count]
    }
    static func write(_ value: Any, to path: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: path, options: .atomic)
    }
    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
    static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw ProbeFailure.invalid(reason) }
    }
    @MainActor static func install(_ command: String) throws {
        UserDefaults.standard.setVolatileDomain([
            VoiceInkUserDefaultsKey.selectedAIProvider: VoiceInkAIEnhancementProviderKind.localCLI.rawValue,
            VoiceInkUserDefaultsKey.isAIEnhancementEnabled: false,
            VoiceInkUserDefaultsKey.useClipboardContext: false,
            VoiceInkUserDefaultsKey.useScreenCaptureContext: false,
            VoiceInkUserDefaultsKey.customPrompts: Data("[]".utf8),
            VoiceInkUserDefaultsKey.selectedPromptId: "RJT-CLARITY-PROBE-NO-PROMPT",
            VoiceInkUserDefaultsKey.enhancementTimeoutSeconds: timeout,
            VoiceInkUserDefaultsKey.enhancementRetryOnTimeout: false,
            VoiceInkLocalCLIPreference.commandTemplateKey: command,
            VoiceInkLocalCLIPreference.selectedTemplateKey: VoiceInkLocalCLITemplate.claude.rawValue,
            VoiceInkLocalCLIPreference.timeoutSecondsKey: timeout
        ], forName: UserDefaults.argumentDomain)
        try require(VoiceInkAIEnhancementProviderPreference.selectedProvider() == .localCLI,
                    "Local CLI must be selected before production initialization")
        try require(VoiceInkLocalCLIPreference.commandTemplate().utf8.elementsEqual(command.utf8)
                    && VoiceInkLocalCLIPreference.timeoutSeconds() == timeout,
                    "Exact command and CLI timeout must precede production initialization")
    }
    static func stream(_ path: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: path) else { return ["present": false] }
        var value: [String: Any] = ["present": true, "byteCount": data.count, "sha256": hash(data)]
        if let decoded = String(data: data, encoding: .utf8) { value["utf8"] = text(decoded) }
        else { value["validUTF8"] = false }
        return value
    }
    static func launches(_ directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("launch.") }.sorted { $0.path < $1.path }
    }
    static func generationCensus(_ directory: URL) -> [String: String] {
        guard let paths = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return ["directory": "unreadable"]
        }
        return Dictionary(uniqueKeysWithValues: paths.map { path in
            (path.lastPathComponent, (try? Data(contentsOf: path)).map(hash) ?? "not-a-readable-file")
        })
    }
    static func waitForCaptures(_ directory: URL) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            let values = launches(directory)
            if !values.isEmpty && values.allSatisfy({ launch in
                ["stdin.complete", "stdout.complete", "stderr.complete"].allSatisfy {
                    FileManager.default.fileExists(atPath: launch.appendingPathComponent($0).path)
                }
            }) { return }
            do { try await Task.sleep(nanoseconds: 10_000_000) }
            catch { return }
        }
    }
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 2 else { Darwin.exit(2) }
        var rows: [[String: Any]] = []
        var fatal: String?
        var root: URL?
        do {
            try require(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != "true" && getuid() != 0,
                        "Semantic calls require an explicitly selected non-CI, non-root host")
            try require(Bundle.main.bundleIdentifier == bundleIdentifier, "Unique signed probe identity mismatch")
            let config = try JSONDecoder().decode(RunConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let evidence = URL(fileURLWithPath: config.evidencePath, isDirectory: true)
            root = evidence
            let original = UserDefaults.standard.persistentDomain(forName: bundleIdentifier) ?? [:]
            try require(original.isEmpty, "Fresh probe identity has persistent preferences")
            let data = try Data(contentsOf: URL(fileURLWithPath: config.inputsPath))
            try require(hash(data) == inputSHA256, "Generation input bytes changed")
            let samples = try JSONDecoder().decode([Sample].self, from: data)
            try require(samples.map(\.id) == (1...9).map { String(format: "C%02d", $0) }, "Nine input identities changed")
            try install(config.commandTemplate)
            defer { UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
            let ai = AIService()
            try require(ai.selectedProvider == .localCLI && ai.apiKey.isEmpty && ai.isAPIKeyValid, "Key-free Local CLI initialization failed")
            let schema = Schema([VocabularyWord.self])
            let memory = ModelConfiguration("ClaritySemantic-" + UUID().uuidString, schema: schema,
                isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [memory])
            let service = AIEnhancementService(aiService: ai, modelContext: container.mainContext)
            try require(!service.isEnhancementEnabled && !service.useClipboardContext && !service.useScreenCaptureContext,
                        "Ordinary enhancement and live context must be disabled")
            let snapshot = try service.providerSnapshot()
            try require(snapshot.modelName == "local-cli" && snapshot.timeoutSeconds == timeout && !snapshot.retryOnTimeout,
                        "Captured provider metadata differs from the configured Local CLI route")
            for sample in samples {
                for style in VoiceInkClarityStyle.allCases {
                    let id = sample.id + "-" + style.rawValue
                    let cwd = URL(fileURLWithPath: config.generationPath, isDirectory: true).appendingPathComponent(id, isDirectory: true)
                    let attempts = evidence.appendingPathComponent("attempts/" + id, isDirectory: true)
                    try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    try FileManager.default.createDirectory(at: attempts, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let request = try VoiceInkClarityRequest(transcript: sample.transcript, style: style)
                    try write(["id": sample.id, "transcript": sample.transcript, "style": style.rawValue], to: cwd.appendingPathComponent("input.json"))
                    try Data(request.systemMessage.utf8).write(to: cwd.appendingPathComponent("system-message.txt"))
                    try Data(request.userMessage.utf8).write(to: cwd.appendingPathComponent("user-message.txt"))
                    let generationBefore = generationCensus(cwd)
                    try require(Set(generationBefore.keys) == Set(["input.json", "system-message.txt", "user-message.txt"]),
                                "Generation directory must contain only this input and its production request messages")
                    try require(FileManager.default.changeCurrentDirectoryPath(cwd.path), "Could not select isolated generation directory")
                    let start = ProcessInfo.processInfo.systemUptime
                    var row: [String: Any] = ["id": id, "caseID": sample.id, "style": style.rawValue,
                        "sourceSHA": sourceSHA, "runManifestSHA256": config.manifestSHA256,
                        "startedUTC": timestamp(), "requestSystemMessage": text(request.systemMessage),
                        "requestUserMessage": text(request.userMessage), "semanticVerdict": "pending-independent-grading",
                        "appModelLabel": snapshot.modelName, "servedModel": "unavailable-text-mode",
                        "endpoint": "unavailable-local-cli", "timeoutSeconds": snapshot.timeoutSeconds, "appRetryOnTimeout": snapshot.retryOnTimeout,
                        "cliTimeoutSeconds": VoiceInkLocalCLIPreference.timeoutSeconds(),
                        "generationDirectory": cwd.path, "generationCensusBefore": generationBefore,
                        "providerSnapshotCaptureCount": 1, "fallback": "not-performed", "canceled": false]
                    var result: VoiceInkAIEnhancementResult?
                    do {
                        result = try await service.performClarity(request: request, using: snapshot)
                        row["serviceOutcome"] = "decoded-result"
                        row["nativeExitStatus"] = 0
                        row["nativeExitStatusSource"] = "successful-real-LocalCLIService-return"
                    } catch {
                        row["serviceOutcome"] = "error"
                        row["serviceError"] = String(describing: error)
                        row["serviceErrorType"] = String(reflecting: type(of: error))
                        row["nativeExitStatus"] = "unavailable-after-service-error-mapping"
                        row["canceled"] = error is CancellationError || Task.isCancelled
                    }
                    row["endedUTC"] = timestamp()
                    row["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - start
                    await waitForCaptures(attempts)
                    let actualLaunches = launches(attempts)
                    let expectedInput = Data(VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: request.systemMessage, userPrompt: request.userMessage).utf8)
                    row["expectedStdinSHA256"] = hash(expectedInput)
                    var observations: [[String: Any]] = []
                    for (index, launch) in actualLaunches.enumerated() {
                        let input = try? Data(contentsOf: launch.appendingPathComponent("stdin.bin"))
                        observations.append(["attemptNumber": index + 1, "directory": launch.path,
                            "stdin": stream(launch.appendingPathComponent("stdin.bin")),
                            "stdout": stream(launch.appendingPathComponent("stdout.bin")),
                            "stderr": stream(launch.appendingPathComponent("stderr.bin")),
                            "stdinUTF8Exact": input == expectedInput,
                            "stdinCaptureComplete": FileManager.default.fileExists(atPath: launch.appendingPathComponent("stdin.complete").path),
                            "stdoutCaptureComplete": FileManager.default.fileExists(atPath: launch.appendingPathComponent("stdout.complete").path),
                            "stderrCaptureComplete": FileManager.default.fileExists(atPath: launch.appendingPathComponent("stderr.complete").path)])
                    }
                    row["launches"] = observations
                    row["observedExecutorLaunchCount"] = actualLaunches.count
                    row["sdkInternalAttempts"] = "unavailable"
                    row["rawDecodeOutcome"] = "unavailable"
                    if actualLaunches.count == 1,
                       let raw = try? Data(contentsOf: actualLaunches[0].appendingPathComponent("stdout.bin")),
                       let response = String(data: raw, encoding: .utf8) {
                        do {
                            let decoded = try request.decodeResponse(response)
                            row["rawDecodeOutcome"] = "decoded"
                            row["decodedProviderText"] = text(decoded)
                            if let result {
                                row["decodedTextUTF8Exact"] = result.text.utf8.elementsEqual(decoded.utf8)
                                row["decodedTextUTF16Exact"] = result.text.utf16.elementsEqual(decoded.utf16)
                            }
                        } catch {
                            row["rawDecodeOutcome"] = "error"
                            row["rawDecodeError"] = String(describing: error)
                        }
                    }
                    if let result {
                        row["appResult"] = text(result.text)
                        if let message = result.requestSystemMessage { row["returnedRequestSystemMessage"] = text(message) }
                        if let message = result.requestUserMessage { row["returnedRequestUserMessage"] = text(message) }
                        row["actualResultModelLabel"] = result.modelName ?? "unavailable"
                        row["requestSystemMetadataUTF8Exact"] = result.requestSystemMessage?.utf8.elementsEqual(request.systemMessage.utf8) == true
                        row["requestSystemMetadataUTF16Exact"] = result.requestSystemMessage?.utf16.elementsEqual(request.systemMessage.utf16) == true
                        row["requestUserMetadataUTF8Exact"] = result.requestUserMessage?.utf8.elementsEqual(request.userMessage.utf8) == true
                        row["requestUserMetadataUTF16Exact"] = result.requestUserMessage?.utf16.elementsEqual(request.userMessage.utf16) == true
                    }
                    let generationAfter = generationCensus(cwd)
                    row["generationCensusAfter"] = generationAfter
                    row["generationInputsUnchanged"] = generationBefore == generationAfter
                    row["persistentProbePreferencesUnchanged"] = (UserDefaults.standard.persistentDomain(forName: bundleIdentifier) ?? [:]).isEmpty
                    try write(row, to: attempts.appendingPathComponent("result.json"))
                    rows.append(row)
                    try write(["sourceSHA": sourceSHA, "bundleIdentifier": bundleIdentifier, "observations": rows,
                               "semanticVerdict": "pending-independent-grading"], to: evidence.appendingPathComponent("results.json"))
                }
            }
        } catch { fatal = String(describing: error) }
        if let root {
            do {
                var summary: [String: Any] = ["sourceSHA": sourceSHA, "bundleIdentifier": bundleIdentifier,
                    "observations": rows, "completedCallCount": rows.count, "semanticVerdict": "pending-independent-grading",
                    "persistentProbePreferencesUnchanged": (UserDefaults.standard.persistentDomain(forName: bundleIdentifier) ?? [:]).isEmpty,
                    "scope": "Synthetic actual Clarity service observations only. No pipeline, microphone, editor or general quality claim."]
                if let fatal { summary["fatalError"] = fatal }
                try write(summary, to: root.appendingPathComponent("results.json"))
            } catch { Darwin.exit(2) }
        }
        Darwin.exit(fatal == nil && rows.count == 27 ? 0 : 1)
    }
}
'''

def require(value, message):
    if not value:
        raise RuntimeError(message)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + '\n')

def tree(root):
    return {str(path.relative_to(root)): digest(path.read_bytes()) for path in sorted(root.rglob('*')) if path.is_file()}

def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])

def source(repo, revision, path):
    return git(repo, 'show', revision + ':' + path)

def logged(command, log, cwd=None, timeout=1800):
    with Path(log).open('wb') as output:
        result = subprocess.run(list(map(str, command)), cwd=cwd, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    require(result.returncode == 0, 'Command failed; see ' + str(log))

def validate_inputs(raw):
    values = json.loads(raw)
    require(isinstance(values, list) and [value.get('id') for value in values] == CASE_IDS, 'Exact nine input identities required')
    require(all(set(value) == {'id', 'transcript'} and isinstance(value['transcript'], str) for value in values), 'Inputs must contain only IDs and transcripts')
    return values

def cli_actions(cli, requested_model):
    isolation_arguments = ['--bare', '--no-session-persistence', '--tools', '', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--setting-sources', 'user', '--settings', '{"disableAllHooks":true}']
    actions = {name: [str(cli), *isolation_arguments, *arguments] for name, arguments in {
        'version': ['--version'],
        'help': ['--help'],
        'authStatus': ['auth', 'status', '--json'],
        'print': ['--print', '--output-format', 'text', '--max-budget-usd', '0.50']
    }.items()}
    if requested_model:
        actions['print'] += ['--model', requested_model]
    return isolation_arguments, actions

def project_auth_status(raw, exit_code):
    projection = {'loggedIn': None, 'authMethod': 'unavailable', 'apiProvider': 'unavailable', 'exitCode': exit_code}
    try:
        payload = json.loads(raw)
    except (TypeError, ValueError, UnicodeDecodeError):
        return projection, False
    if not isinstance(payload, dict):
        return projection, False
    if type(payload.get('loggedIn')) is bool:
        projection['loggedIn'] = payload['loggedIn']
    if payload.get('authMethod') in ['api_key', 'none']:
        projection['authMethod'] = payload['authMethod']
    if payload.get('apiProvider') == 'firstParty':
        projection['apiProvider'] = 'firstParty'
    accepted = exit_code == 0 and projection['loggedIn'] is True and projection['authMethod'] == 'api_key' and projection['apiProvider'] == 'firstParty'
    return projection, accepted

def auth_preflight(command, cwd, receipt):
    try:
        result = subprocess.run(command, capture_output=True, cwd=cwd, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        write(receipt, project_auth_status(None, None)[0])
        raise RuntimeError('CLI authentication preflight failed.') from None
    projection, accepted = project_auth_status(result.stdout, result.returncode)
    write(receipt, projection)
    require(accepted, 'CLI authentication preflight failed.')
    return projection

def classify(value, code, contract):
    rows = value.get('observations', [])
    valid = code == 0 and value.get('completedCallCount') == 27 and [row.get('id') for row in rows] == EXPECTED and 'fatalError' not in value
    valid = valid and value.get('semanticVerdict') == 'pending-independent-grading'
    valid = valid and value.get('sourceSHA') == contract['sourceSHA'] and value.get('bundleIdentifier') == contract['bundleIdentifier'] and value.get('persistentProbePreferencesUnchanged') is True
    for row in rows:
        valid = valid and row.get('sourceSHA') == contract['sourceSHA'] and row.get('caseID') in CASE_IDS and row.get('style') in STYLES and row.get('id') == row.get('caseID', '') + '-' + row.get('style', '') and row.get('appModelLabel') == 'local-cli'
        valid = valid and row.get('generationInputsUnchanged') is True and row.get('generationCensusBefore') == row.get('generationCensusAfter') and set(row.get('generationCensusBefore', {})) == {'input.json', 'system-message.txt', 'user-message.txt'} and row.get('timeoutSeconds') == 120 and row.get('cliTimeoutSeconds') == 120
        valid = valid and row.get('semanticVerdict') == 'pending-independent-grading' and row.get('providerSnapshotCaptureCount') == 1 and row.get('appRetryOnTimeout') is False
        valid = valid and row.get('persistentProbePreferencesUnchanged') is True and row.get('observedExecutorLaunchCount') == 1
        launches = row.get('launches', [])
        valid = valid and len(launches) == 1 and all(launch.get('stdinUTF8Exact') is True and launch.get('stdinCaptureComplete') is True and launch.get('stdoutCaptureComplete') is True and launch.get('stderrCaptureComplete') is True for launch in launches)
        if row.get('serviceOutcome') == 'decoded-result':
            valid = valid and row.get('rawDecodeOutcome') == 'decoded' and all(row.get(name) is True for name in ['decodedTextUTF8Exact', 'decodedTextUTF16Exact', 'requestSystemMetadataUTF8Exact', 'requestSystemMetadataUTF16Exact', 'requestUserMetadataUTF8Exact', 'requestUserMetadataUTF16Exact'])
            valid = valid and row.get('actualResultModelLabel') == 'local-cli'
        else:
            valid = valid and row.get('serviceOutcome') == 'error' and isinstance(row.get('serviceError'), str)
    return {'validObservationSet': bool(valid), 'classification': 'completed-observations-awaiting-independent-grading' if valid else 'invalid-or-incomplete-observations', 'semanticVerdict': 'pending-independent-grading', 'completedCallCount': len(rows), 'decodedResultCount': sum(row.get('serviceOutcome') == 'decoded-result' for row in rows), 'serviceErrorCount': sum(row.get('serviceOutcome') == 'error' for row in rows)}

def self_test():
    isolation_arguments, actions = cli_actions('/synthetic/claude', 'reviewed-model')
    require(isolation_arguments[isolation_arguments.index('--setting-sources') + 1] == 'user', 'Reviewed user setting source changed')
    for arguments in actions.values():
        require(arguments[1:1 + len(isolation_arguments)] == isolation_arguments, 'CLI action isolation arguments differ')
    require(actions['authStatus'][1 + len(isolation_arguments):] == ['auth', 'status', '--json'], 'Auth status must not become a print or model request')
    require('--model' not in actions['authStatus'] and '--print' not in actions['authStatus'] and '--output-format' not in actions['authStatus'] and '--max-budget-usd' not in actions['authStatus'], 'Auth status received print-only options')
    secret = 'SYNTHETIC-DO-NOT-RETAIN'
    raw = json.dumps({'loggedIn': True, 'authMethod': 'api_key', 'apiProvider': 'firstParty', 'apiKey': secret, 'accountId': secret, 'email': secret})
    projection, accepted = project_auth_status(raw, 0)
    require(accepted and set(projection) == {'loggedIn', 'authMethod', 'apiProvider', 'exitCode'} and secret not in json.dumps(projection), 'Auth status projection retained unrelated fields')
    for raw, code in [(secret, 0), ('[]', 0), ('{}', 0), (json.dumps({'loggedIn': False, 'authMethod': 'none'}), 1), (json.dumps({'loggedIn': True, 'authMethod': secret, 'apiProvider': secret}), 0)]:
        projection, accepted = project_auth_status(raw, code)
        require(not accepted and secret not in json.dumps(projection), 'Auth status failure leaked content or was accepted')
    contract = {'sourceSHA': 'source', 'bundleIdentifier': 'bundle'}
    census = {name: 'synthetic-hash' for name in ['input.json', 'system-message.txt', 'user-message.txt']}
    row = {'sourceSHA': 'source', 'appModelLabel': 'local-cli', 'timeoutSeconds': 120, 'cliTimeoutSeconds': 120, 'generationInputsUnchanged': True, 'generationCensusBefore': census, 'generationCensusAfter': census, 'semanticVerdict': 'pending-independent-grading', 'providerSnapshotCaptureCount': 1, 'appRetryOnTimeout': False, 'persistentProbePreferencesUnchanged': True, 'observedExecutorLaunchCount': 1, 'serviceOutcome': 'error', 'serviceError': 'invalidResponse', 'launches': [{'stdinUTF8Exact': True, 'stdinCaptureComplete': True, 'stdoutCaptureComplete': True, 'stderrCaptureComplete': True}]}
    good = {'sourceSHA': 'source', 'bundleIdentifier': 'bundle', 'persistentProbePreferencesUnchanged': True, 'observations': [dict(row, id=name, caseID=name[:3], style=name[4:]) for name in EXPECTED], 'completedCallCount': 27, 'semanticVerdict': 'pending-independent-grading'}
    require(classify(good, 0, contract)['validObservationSet'], 'Complete error observations must be retained without a semantic pass')
    decoded = json.loads(json.dumps(good))
    decoded['observations'][0].update({'serviceOutcome': 'decoded-result', 'rawDecodeOutcome': 'decoded', 'actualResultModelLabel': 'local-cli', **{name: True for name in ['decodedTextUTF8Exact', 'decodedTextUTF16Exact', 'requestSystemMetadataUTF8Exact', 'requestSystemMetadataUTF16Exact', 'requestUserMetadataUTF8Exact', 'requestUserMetadataUTF16Exact']}})
    require(classify(decoded, 0, contract)['validObservationSet'], 'Complete decoded observations must remain pending semantic grading')
    decoded['observations'][0]['decodedTextUTF16Exact'] = False
    require(not classify(decoded, 0, contract)['validObservationSet'], 'Classifier accepted changed decoded code units')
    for mutation in ['missing', 'duplicate', 'graded', 'preference', 'capture', 'stdin', 'source', 'bundle', 'style', 'generation', 'final-preferences', 'exit']:
        changed = json.loads(json.dumps(good))
        code = 0
        if mutation == 'missing': changed['observations'].pop()
        if mutation == 'duplicate': changed['observations'][0]['id'] = EXPECTED[1]
        if mutation == 'graded': changed['semanticVerdict'] = 'passed'
        if mutation == 'preference': changed['observations'][0]['persistentProbePreferencesUnchanged'] = False
        if mutation == 'capture': changed['observations'][0]['launches'][0]['stdoutCaptureComplete'] = False
        if mutation == 'stdin': changed['observations'][0]['launches'][0]['stdinUTF8Exact'] = False
        if mutation == 'source': changed['observations'][0]['sourceSHA'] = 'other'
        if mutation == 'bundle': changed['bundleIdentifier'] = 'other'
        if mutation == 'style': changed['observations'][0]['style'] = 'other'
        if mutation == 'generation': changed['observations'][0]['generationCensusAfter']['rubric.json'] = 'unexpected'
        if mutation == 'final-preferences': changed['persistentProbePreferencesUnchanged'] = False
        if mutation == 'exit': code = 1
        require(not classify(changed, code, contract)['validObservationSet'], 'Classifier accepted ' + mutation)
    print('PASS pure observation classifier. No native build, CLI or model calls.')

def verify(repo, out):
    contract = json.loads((out / 'source-contract.json').read_text())
    package = out / 'generator/writing-local-cli-service-probe/package'
    require(git(repo, 'rev-parse', 'HEAD').decode().strip() == contract['sourceSHA'], 'Source HEAD changed')
    require({path: digest((repo / path).read_bytes()) for path in contract['sourceInputs']} == contract['sourceInputs'], 'Source inputs changed')
    for name in ['Sources', 'Dependencies']:
        require(tree(package / name) == contract['generated' + name], 'Generated ' + name + ' changed')
    require(digest((package / 'Package.swift').read_bytes()) == contract['packageManifestSHA256'], 'Manifest changed')
    require(digest((out / 'generator/writing-local-cli-service-probe/source-contract.json').read_bytes()) == contract['generatorContractSHA256'], 'Original generator contract changed')
    require(digest((out / 'clarity-inputs.json').read_bytes()) == contract['inputSHA256'], 'Semantic inputs changed')
    require(digest((out / 'run-clarity-semantic-probe.sh').read_bytes()) == contract['runnerSHA256'], 'Packaged runner changed')
    return contract, package

def prepare(repo, out):
    require(not out.exists(), 'Preparation output already exists')
    revision = git(repo, 'rev-parse', 'HEAD').decode().strip()
    relevant = [GENERATOR, 'VoiceInkTests/WritingActionProviderTests.swift', 'VoiceInk/Services/AIEnhancement', 'VoiceInk/Services/OllamaService.swift', 'VoiceInk/Services/APIKeyManager.swift', 'VoiceInk/Services/KeychainService.swift', 'VoiceInk/Services/CustomVocabularyService.swift', 'VoiceInk/Services/ScreenCaptureService.swift', 'VoiceInk/Services/SelectedTextService.swift', 'VoiceInk/Models/VocabularyWord.swift', 'VoiceInk/Notifications/AppNotifications.swift', 'VoiceInkCore', 'VoiceInkNVIDIA', LOCK, INPUT, RUBRIC, WORKFLOW, 'scripts/run-clarity-semantic-probe.sh']
    subprocess.run(['git', '-C', str(repo), 'diff', '--exit-code', 'HEAD', '--', *relevant], check=True)
    require(not git(repo, 'ls-files', '--others', '--exclude-standard', '--', *relevant).strip(), 'Relevant untracked source is forbidden')
    out.mkdir(mode=0o700, parents=True)
    generated = out / 'generator'
    generated.mkdir()
    environment = dict(os.environ, RUNNER_TEMP=str(generated))
    subprocess.run(['bash', str(repo / GENERATOR), 'prepare'], env=environment, check=True)
    seed = generated / 'writing-local-cli-service-probe'
    original = json.loads((seed / 'source-contract.json').read_text())
    package = seed / 'package'
    require(original['source_sha'] == revision and len(original['app_sources']) == 11 and len(original['expected_pins']) == 26, 'Generator source closure changed')
    inputs = source(repo, revision, INPUT)
    validate_inputs(inputs)
    bundle = 'com.negentropi.RomaJustTalk.ClaritySemanticProbe.' + uuid.uuid4().hex
    driver = DRIVER.replace('__SOURCE_SHA__', revision).replace('__BUNDLE_ID__', bundle).replace('__INPUT_SHA256__', digest(inputs)).encode()
    (package / 'Sources/WritingLocalCLIProbe/Probe.swift').write_bytes(driver)
    require(set(tree(package / 'Sources')) == {'WritingLocalCLIProbe/' + Path(path).name for path in original['app_sources']} | {'WritingLocalCLIProbe/Probe.swift'}, 'Generated source census contains unexpected driver, fixture or backup files')
    (out / 'clarity-inputs.json').write_bytes(inputs)
    shutil.copy2(SCRIPT, out / 'run-clarity-semantic-probe.sh')
    names = git(repo, 'ls-files', '-z', '--', *relevant).split(b'\0')
    hashes = {name.decode(): digest(source(repo, revision, name.decode())) for name in names if name}
    contract = {'version': 1, 'sourceSHA': revision, 'bundleIdentifier': bundle, 'sourceInputs': hashes,
        'generatorSHA256': hashes[GENERATOR], 'generatorContractSHA256': digest((seed / 'source-contract.json').read_bytes()),
        'driverSHA256': digest(driver), 'runnerSHA256': digest(SCRIPT.read_bytes()),
        'inputSHA256': digest(inputs), 'rubricSHA256': digest(source(repo, revision, RUBRIC)),
        'requestConstructorSourceSHA256': hashes['VoiceInkCore/Sources/VoiceInkCore/DictationPolish.swift'],
        'serviceSourceSHA256': original['app_sources']['VoiceInk/Services/AIEnhancement/AIEnhancementService.swift'],
        'generatedSources': tree(package / 'Sources'), 'generatedDependencies': tree(package / 'Dependencies'),
        'packageManifestSHA256': digest((package / 'Package.swift').read_bytes()), 'expectedPins': original['expected_pins'],
        'canonicalLockSHA256': original['canonical_lock_sha256'], 'expectedCases': EXPECTED,
        'generationInputFields': ['id', 'transcript'], 'rubricIncludedInArtifact': False, 'scope': SCOPE}
    write(out / 'source-contract.json', contract)
    app = out / 'ClaritySemanticProbe.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'ClaritySemanticProbe', 'CFBundleName': 'ClaritySemanticProbe', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0', 'LSUIElement': True}))
    verify(repo, out)

def build(repo, out):
    contract, package = verify(repo, out)
    commands = [['xcrun', 'swift', 'package', '--package-path', str(package), '--skip-update', 'resolve'], ['xcrun', 'swift', 'build', '--package-path', str(package), '--force-resolved-versions', '--configuration', 'release', '--product', 'WritingLocalCLIProbe', '--jobs', '3']]
    logged(commands[0], out / 'resolve.log')
    lock = (package / 'Package.resolved').read_bytes()
    pins = {pin['identity']: pin for pin in json.loads(lock)['pins']}
    require(pins == contract['expectedPins'], 'Resolved package pins differ from canonical service closure')
    write(out / 'resolved-pin-receipt.json', {'valid': True, 'resolvedSHA256': digest(lock), 'expectedPins': pins})
    before = checkout_receipt(package, contract)
    write(out / 'checkouts-before-build.json', before)
    logged(commands[1], out / 'build.log')
    require((package / 'Package.resolved').read_bytes() == lock, 'Build changed resolved dependency metadata')
    verify(repo, out)
    after = checkout_receipt(package, contract)
    write(out / 'checkouts-after-build.json', after)
    require(before == after, 'Build changed dependency checkout revisions or tracked source cleanliness')
    binary = Path(subprocess.check_output(['xcrun', 'swift', 'build', '--package-path', str(package), '--force-resolved-versions', '--configuration', 'release', '--show-bin-path']).decode().strip())
    app = out / 'ClaritySemanticProbe.app'
    shutil.copy2(binary / 'WritingLocalCLIProbe', app / 'Contents/MacOS/ClaritySemanticProbe')
    resources = app / 'Contents/Resources'
    resources.mkdir()
    for bundle in binary.glob('*.bundle'):
        shutil.copytree(bundle, resources / bundle.name)
    logged(['codesign', '--force', '--sign', '-', app], out / 'signing.log', timeout=60)
    logged(['codesign', '--verify', '--deep', '--strict', app], out / 'signature-verification.log', timeout=60)
    logged(['codesign', '--display', '--verbose=4', app], out / 'signature.txt', timeout=60)
    write(out / 'build-receipt.json', {'sourceSHA': contract['sourceSHA'], 'commands': commands,
        'bundleIdentifier': contract['bundleIdentifier'], 'bundleManifest': tree(app),
        'binarySHA256': digest((app / 'Contents/MacOS/ClaritySemanticProbe').read_bytes()),
        'sourceContractSHA256': digest((out / 'source-contract.json').read_bytes()),
        'signatureSHA256': digest((out / 'signature.txt').read_bytes()),
        'toolchainSHA256': digest((out / 'toolchain.log').read_bytes()),
        'checkoutsBeforeBuildSHA256': digest((out / 'checkouts-before-build.json').read_bytes()),
        'checkoutsAfterBuildSHA256': digest((out / 'checkouts-after-build.json').read_bytes()), 'semanticCallsExecuted': 0,
        'scope': 'Remote build and signature only. No semantic execution.'})
    with tarfile.open(out / 'signed-probe.tar.gz', 'w:gz') as archive:
        archive.add(app, arcname=app.name)
        for name in ['clarity-inputs.json', 'source-contract.json', 'build-receipt.json', 'signature.txt', 'resolved-pin-receipt.json', 'checkouts-before-build.json', 'checkouts-after-build.json', 'run-clarity-semantic-probe.sh', 'toolchain.log']:
            archive.add(out / name, arcname=name)
        archive.add(out / 'generator/writing-local-cli-service-probe/source-contract.json', arcname='generator-source-contract.json')

def quoted(value):
    return "'" + str(value).replace("'", "'\\''") + "'"

def checkout_receipt(package, contract):
    observed = {}
    for checkout in sorted((package / '.build/checkouts').iterdir()):
        if not checkout.is_dir():
            continue
        revision = git(checkout, 'rev-parse', 'HEAD').decode().strip()
        matches = [name for name, pin in contract['expectedPins'].items() if pin['state']['revision'] == revision]
        require(len(matches) == 1 and matches[0] not in observed, 'Unrecognized or duplicate resolved checkout')
        require(not git(checkout, 'status', '--porcelain', '--untracked-files=no').strip(), 'Dependency checkout has tracked edits: ' + matches[0])
        observed[matches[0]] = {'revision': revision, 'trackedClean': True}
    require(set(observed) == set(contract['expectedPins']), 'Actual checkout census differs from exact 26 pins')
    return observed

def capture_wrapper(cli, arguments, capture_root):
    return '#!/bin/bash\nset -euo pipefail\ncase_id="${PWD##*/}"\n[[ "$case_id" =~ ^C0[1-9]-(natural|casual|formal)$ ]]\nlaunch=$(/usr/bin/mktemp -d ' + quoted(capture_root) + '/"$case_id"/launch.XXXXXX)\nprintf "%s\\n" "$$" > "$launch/owned-exec-pid.txt"\nexec ' + ' '.join(quoted(item) for item in [cli, *arguments]) + ' < <(/usr/bin/tee "$launch/stdin.bin"; : > "$launch/stdin.complete") > >(/usr/bin/tee "$launch/stdout.bin"; : > "$launch/stdout.complete") 2> >(/usr/bin/tee "$launch/stderr.bin" >&2; : > "$launch/stderr.complete")\n'

def capture_self_test():
    with tempfile.TemporaryDirectory(prefix='rjt-clarity-capture-') as path:
        root = Path(path)
        cwd = root / 'generation/C01-natural'
        capture = root / 'attempts/C01-natural'
        cwd.mkdir(parents=True)
        capture.mkdir(parents=True)
        wrapper = root / 'capture.sh'
        wrapper.write_text(capture_wrapper('/bin/sh', ['-c', '/bin/cat; printf synthetic-stderr >&2; exit 23'], root / 'attempts'))
        payload = 'synthetic e\u0301 て\u3099\n'.encode()
        result = subprocess.run(['/bin/bash', str(wrapper)], input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd, timeout=3)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            launches = list(capture.glob('launch.*'))
            if len(launches) == 1 and all((launches[0] / (name + '.complete')).is_file() for name in ['stdin', 'stdout', 'stderr']):
                break
            time.sleep(0.01)
        require(result.returncode == 23 and result.stdout == payload and result.stderr == b'synthetic-stderr', 'Synthetic capture changed exit or byte streams')
        require(len(launches) == 1 and all((launches[0] / (name + '.bin')).read_bytes() == expected for name, expected in [('stdin', payload), ('stdout', payload), ('stderr', b'synthetic-stderr')]), 'Synthetic recorded streams differ')
        require(all((launches[0] / (name + '.complete')).is_file() for name in ['stdin', 'stdout', 'stderr']), 'Synthetic capture completion missing')
    print('PASS finite shell capture including exact Unicode bytes and nonzero exit. No CLI or model calls.')

def verify_retained_evidence(out, value):
    failures = []
    manifest = json.loads((out / 'run-manifest.json').read_text())
    manifest_hash = digest((out / 'run-manifest.json').read_bytes())
    def check_text(observation):
        value = observation['text']
        require(isinstance(value, str), 'Text observation must contain a string')
        utf8, utf16 = value.encode('utf-8'), value.encode('utf-16-le')
        require(observation['utf8SHA256'] == digest(utf8) and observation['utf16LESHA256'] == digest(utf16) and observation['utf8Count'] == len(utf8) and observation['utf16Count'] == len(utf16) // 2, 'Retained text hashes/counts differ')
    for row in value.get('observations', []):
        try:
            require(row.get('id') in EXPECTED, 'Unknown retained case identity')
            require(row.get('runManifestSHA256') == manifest_hash, 'Case run manifest identity changed')
            expected_parent = (out / 'attempts' / row['id']).resolve(strict=True)
            generation = Path(row['generationDirectory']).resolve(strict=True)
            require(generation.parent == Path(manifest['generationRoot']).resolve(strict=True) and generation.name == row['id'], 'Generation directory escapes its fresh run root')
            require(tree(generation) == row['generationCensusBefore'] == row['generationCensusAfter'], 'Retained generation input census changed')
            for name in ['requestSystemMessage', 'requestUserMessage', 'decodedProviderText', 'appResult', 'returnedRequestSystemMessage', 'returnedRequestUserMessage']:
                if name in row:
                    check_text(row[name])
            if row.get('serviceOutcome') == 'decoded-result':
                require(row['returnedRequestSystemMessage']['text'].encode() == row['requestSystemMessage']['text'].encode() and row['returnedRequestUserMessage']['text'].encode() == row['requestUserMessage']['text'].encode(), 'Returned request metadata differs from captured messages')
                require(row['decodedProviderText']['text'].encode() == row['appResult']['text'].encode(), 'Retained decoded provider and app text differ')
            for launch in row.get('launches', []):
                directory = Path(launch['directory']).resolve(strict=True)
                require(directory.parent == expected_parent and directory.name.startswith('launch.'), 'Launch path escapes its owned case directory')
                for name in ['stdin', 'stdout', 'stderr']:
                    raw = (directory / (name + '.bin')).read_bytes()
                    require((directory / (name + '.complete')).is_file(), 'Retained completion marker missing')
                    observation = launch[name]
                    require(observation.get('present') is True and observation['byteCount'] == len(raw) and observation['sha256'] == digest(raw), 'Retained stream bytes differ')
                    if name == 'stdin':
                        require(digest(raw) == row['expectedStdinSHA256'], 'Retained stdin differs from actual Core fullPrompt hash')
                    try:
                        decoded = raw.decode('utf-8')
                    except UnicodeDecodeError:
                        require(observation.get('validUTF8') is False and 'utf8' not in observation, 'Invalid stream UTF-8 was mislabeled')
                    else:
                        check_text(observation['utf8'])
                        require(observation['utf8']['text'].encode() == raw, 'Retained stream text differs from raw bytes')
        except (KeyError, TypeError, ValueError, OSError, RuntimeError) as error:
            failures.append({'id': row.get('id'), 'error': str(error)})
    result = {'valid': not failures and len(value.get('observations', [])) == 27, 'failures': failures, 'scope': 'Retained stream and text bytes only. No prompt reconstruction, JSON decoding or semantic grading.'}
    write(out / 'retained-evidence-verification.json', result)
    return result['valid']

def run(artifact, executable, out, requested_model):
    require(sys.platform == 'darwin' and os.getuid() != 0 and os.environ.get('GITHUB_ACTIONS') != 'true', 'Semantic execution requires a selected non-root Mac outside CI')
    require(artifact.is_absolute() and executable.is_absolute() and out.is_absolute(), 'Artifact, CLI and new evidence paths must be absolute')
    require(requested_model is None or (requested_model != '' and not requested_model.startswith('-') and not any(character in requested_model for character in ['\0', '\n', '\r'])), 'Requested model must be a nonempty value without option, NUL or newline syntax')
    require(not out.exists() and out.parent.is_dir(), 'New evidence directory with existing parent required')
    contract = json.loads((artifact / 'source-contract.json').read_text())
    receipt = json.loads((artifact / 'build-receipt.json').read_text())
    app = artifact / 'ClaritySemanticProbe.app'
    require(digest((artifact / 'source-contract.json').read_bytes()) == receipt['sourceContractSHA256'], 'Source contract identity changed')
    require(digest((artifact / 'signature.txt').read_bytes()) == receipt['signatureSHA256'] and digest((artifact / 'toolchain.log').read_bytes()) == receipt['toolchainSHA256'], 'Build signature or toolchain evidence changed')
    require(all(digest((artifact / name).read_bytes()) == receipt[key] for name, key in [('checkouts-before-build.json', 'checkoutsBeforeBuildSHA256'), ('checkouts-after-build.json', 'checkoutsAfterBuildSHA256')]), 'Build dependency checkout evidence changed')
    require(tree(app) == receipt['bundleManifest'], 'Signed bundle bytes changed')
    require(digest(SCRIPT.read_bytes()) == contract['runnerSHA256'], 'Run the exact packaged runner')
    require(digest((artifact / 'clarity-inputs.json').read_bytes()) == contract['inputSHA256'], 'Generation input bytes changed')
    require(plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier'] == contract['bundleIdentifier'], 'Bundle identity mismatch')
    cli = executable.resolve(strict=True)
    require(cli.is_file() and os.access(cli, os.X_OK), 'Selected CLI executable is unavailable')
    out.mkdir(mode=0o700)
    preflight = out / 'preflight'
    preflight.mkdir()
    logged(['codesign', '--verify', '--deep', '--strict', app], out / 'signature-before.log', timeout=60)
    isolation_arguments, actions = cli_actions(cli, requested_model)
    logged(actions['version'], out / 'cli-version.txt', cwd=preflight, timeout=20)
    logged(actions['help'], out / 'cli-help.txt', cwd=preflight, timeout=20)
    help_text = (out / 'cli-help.txt').read_text()
    flags = ['--bare', '--print', '--no-session-persistence', '--tools', '--strict-mcp-config', '--mcp-config', '--setting-sources', '--settings', '--output-format', '--max-budget-usd']
    if requested_model:
        flags.append('--model')
    require(all(flag in help_text for flag in flags), 'Current CLI no longer exposes every required isolation/budget flag')
    auth_preflight(actions['authStatus'], preflight, out / 'cli-auth-status.json')
    cli_arguments = actions['print'][1:]
    (out / 'attempts').mkdir()
    wrapper = out / 'capture-command.sh'
    wrapper.write_text(capture_wrapper(cli, cli_arguments, out / 'attempts'))
    command = 'exec /bin/bash ' + quoted(wrapper)
    generation = Path(tempfile.mkdtemp(prefix='RJT-Clarity-Generation-', dir='/tmp'))
    manifest = {'sourceSHA': contract['sourceSHA'], 'sourceContractSHA256': receipt['sourceContractSHA256'],
        'inputSHA256': contract['inputSHA256'], 'rubricSHA256': contract['rubricSHA256'],
        'requestConstructorSourceSHA256': contract['requestConstructorSourceSHA256'], 'serviceSourceSHA256': contract['serviceSourceSHA256'],
        'bundleIdentifier': contract['bundleIdentifier'], 'binarySHA256': receipt['binarySHA256'],
        'buildReceiptSHA256': digest((artifact / 'build-receipt.json').read_bytes()),
        'cliPath': str(cli), 'cliSHA256': digest(cli.read_bytes()), 'cliVersion': (out / 'cli-version.txt').read_text().strip(),
        'cliIsolationArguments': isolation_arguments,
        'cliArguments': cli_arguments, 'commandTemplate': command, 'requestedModel': requested_model or 'default-not-overridden',
        'authStatusReceiptSHA256': digest((out / 'cli-auth-status.json').read_bytes()),
        'servedModel': 'unavailable-text-mode', 'endpoint': 'unavailable-local-cli',
        'timeoutSeconds': 120, 'appRetryOnTimeout': False, 'maxBudgetUSDPerCall': '0.50', 'scheduledCalls': 27,
        'isolatedSettings': {'bare': True, 'tools': [], 'mcpServers': {}, 'settingSources': ['user'], 'disableAllHooks': True, 'sessionPersistence': False},
        'generationContext': 'One transcript/style through production VoiceInkClarityRequest only; no rubric, repository, history or earlier outputs supplied',
        'generationRoot': str(generation),
        'semanticVerdict': 'pending-independent-grading', 'scope': SCOPE}
    write(out / 'run-manifest.json', manifest)
    write(out / 'run-configuration.json', {'evidencePath': str(out), 'generationPath': str(generation), 'inputsPath': str(artifact / 'clarity-inputs.json'), 'commandTemplate': command, 'manifestSHA256': digest((out / 'run-manifest.json').read_bytes())})
    code = subprocess.run([app / 'Contents/MacOS/ClaritySemanticProbe', out / 'run-configuration.json'], cwd=preflight, stdout=(out / 'probe.stdout').open('wb'), stderr=(out / 'probe.stderr').open('wb')).returncode
    unchanged = tree(app) == receipt['bundleManifest'] and digest(cli.read_bytes()) == manifest['cliSHA256']
    logged(['codesign', '--verify', '--deep', '--strict', app], out / 'signature-after.log', timeout=60)
    observations = json.loads((out / 'results.json').read_text()) if (out / 'results.json').is_file() else {}
    retained = verify_retained_evidence(out, observations)
    result = classify(observations, code, contract)
    result.update({'sourceSHA': contract['sourceSHA'], 'binaryAndCLIUnchanged': unchanged, 'probeExitCode': code, 'scope': SCOPE})
    result['retainedEvidenceValid'] = retained
    result['validObservationSet'] = result['validObservationSet'] and unchanged and retained
    if not result['validObservationSet']:
        result['classification'] = 'invalid-or-incomplete-observations'
    write(out / 'observation-receipt.json', result)
    print(json.dumps(result, indent=2))
    require(result['validObservationSet'], 'Observation set incomplete or artifact identity changed; retain every recorded attempt')

if MODE == '--self-test' and not ARGS:
    self_test()
elif MODE == '--capture-self-test' and not ARGS:
    capture_self_test()
elif MODE in ['prepare', 'build'] and not ARGS:
    require(os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted' and sys.platform == 'darwin' and os.getuid() != 0, 'Build only on a fresh non-root GitHub-hosted Mac')
    repo = SCRIPT.parent.parent
    out = Path(os.environ['RUNNER_TEMP']) / 'clarity-semantic-probe'
    if MODE == 'prepare':
        prepare(repo, out)
    else:
        build(repo, out)
elif MODE == 'run' and len(ARGS) in [3, 4]:
    run(Path(ARGS[0]), Path(ARGS[1]), Path(ARGS[2]), ARGS[3] if len(ARGS) == 4 else None)
else:
    raise SystemExit('Use --self-test, --capture-self-test, CI-only prepare/build, or run /artifact/root /absolute/claude /new/evidence [requested-model]. Run makes 27 real model calls and requires coordinator authorization.')
PY
