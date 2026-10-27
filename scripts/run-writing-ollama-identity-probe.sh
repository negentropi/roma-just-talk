#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"
case "$mode" in prepare|build|run|self-test) ;; *) echo 'Use prepare, build, run, or self-test.' >&2; exit 2 ;; esac
if [[ "$mode" != self-test && ( "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin || "$(id -u)" == 0 ) ]]; then
  echo 'Run the native probe only on a disposable GitHub-hosted Mac.' >&2
  exit 2
fi
repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$mode" "$repo" <<'PY'
import copy
import hashlib
import http.server
import io
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tarfile
import threading
import time
import uuid
from pathlib import Path

MODE, REPO = sys.argv[1], Path(sys.argv[2])
BASELINE = '830d45210816a36c2db70b09d1329a0ef8b7ddf6'
OUT = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'writing-ollama-identity-probe'
RESPONSE = 'RJT ollama identity receipt.'
CASES = {'no-keys': ('llama2', 'mistral'), 'divergent-keys': ('new-model', 'old-model'), 'coherent-keys': ('chosen-model', 'chosen-model')}
SCRIPT_PATH = REPO / 'scripts/run-writing-ollama-identity-probe.sh'
APP_PATHS = [
    'VoiceInk/Services/AIEnhancement/AIService.swift',
    'VoiceInk/Services/AIEnhancement/AIEnhancementService.swift',
    'VoiceInk/Services/AIEnhancement/LocalCLIService.swift',
    'VoiceInk/Services/OllamaService.swift',
    'VoiceInk/Services/APIKeyManager.swift',
    'VoiceInk/Services/KeychainService.swift',
    'VoiceInk/Services/CustomVocabularyService.swift',
    'VoiceInk/Services/ScreenCaptureService.swift',
    'VoiceInk/Services/SelectedTextService.swift',
    'VoiceInk/Models/VocabularyWord.swift',
    'VoiceInk/Notifications/AppNotifications.swift',
]
SDK_BLOBS = {
    'Sources/LLMkit/LLM/OllamaClient.swift': '341c5d0d38edd79733a2da47f412e3ab540c82fb',
    'Sources/LLMkit/HTTPClient.swift': '81db783f7ab47c2b2174a4f2367c1e0f5ac1509d',
    'Sources/LLMkit/HTTPHelpers.swift': '7b2a095d066260e194a6b6c1026807e601aaae10',
    'Sources/LLMkit/LLMKitError.swift': '5db3d14e020e3bc3daba752d289aeae530f7b56e',
}
DRIVER = r'''
import AppKit
import Darwin
import Foundation
import SwiftData
import VoiceInkCore

private enum ProbeFailure: Error { case invalid(String) }
private struct PreferenceCheck: Encodable {
    let operation: String
    let deliberateWrite: Bool
    let before: [String: String]
    let after: [String: String]
    let passed: Bool
}
private struct ResultObservation: Encodable {
    let text: String
    let modelName: String?
    let requestMetadataUTF8Equal: Bool
}
private struct Receipt: Encodable {
    let caseID: String
    let sourceSHA: String
    let bundleIdentifier: String
    let expectedModel: String
    var snapshotModel: String?
    var retainedSnapshotModel: String?
    var freshSnapshotModel: String?
    var systemMessage: String?
    var userMessage: String?
    var held: ResultObservation?
    var fresh: ResultObservation?
    var preferenceChecks: [PreferenceCheck] = []
    var error: String?
}

@main private enum ProbeMain {
    @MainActor static func require(_ condition: Bool, _ reason: String) throws {
        if !condition { throw ProbeFailure.invalid(reason) }
    }
    @MainActor static func persistent(_ bundle: String) throws -> [String: String] {
        let domain = UserDefaults.standard.persistentDomain(forName: bundle) ?? [:]
        let allowed = Set(["selectedAIProvider", "OllamaSelectedModel", "ollamaSelectedModel"])
        try require(Set(domain.keys).isSubset(of: allowed), "Unexpected persistent preference key")
        var result: [String: String] = [:]
        for (key, value) in domain {
            guard let text = value as? String else { throw ProbeFailure.invalid("Unexpected persistent preference type") }
            result[key] = text
        }
        return result
    }
    @MainActor static func checkpoint(_ name: String, bundle: String, before: [String: String], receipt: inout Receipt) throws {
        let after = try persistent(bundle)
        receipt.preferenceChecks.append(.init(operation: name, deliberateWrite: false, before: before, after: after, passed: before == after))
        try require(before == after, "Persistent preferences changed during " + name)
    }
    @MainActor static func defaults(caseID: String, endpoint: String, later: Bool) {
        var values: [String: Any] = [
            VoiceInkUserDefaultsKey.selectedAIProvider: VoiceInkAIEnhancementProviderKind.localCLI.rawValue,
            VoiceInkUserDefaultsKey.isAIEnhancementEnabled: false,
            VoiceInkUserDefaultsKey.useClipboardContext: false,
            VoiceInkUserDefaultsKey.useScreenCaptureContext: false,
            VoiceInkUserDefaultsKey.customPrompts: Data("[]".utf8),
            VoiceInkUserDefaultsKey.selectedPromptId: "RJT-PROBE-NO-SELECTED-PROMPT",
            VoiceInkUserDefaultsKey.enhancementTimeoutSeconds: 15,
            VoiceInkUserDefaultsKey.enhancementRetryOnTimeout: false,
            VoiceInkLocalCLIPreference.commandTemplateKey: "/bin/cat",
            VoiceInkLocalCLIPreference.selectedTemplateKey: VoiceInkLocalCLITemplate.claude.rawValue,
            VoiceInkLocalCLIPreference.timeoutSecondsKey: 15,
            VoiceInkUserDefaultsKey.ollamaBaseURL: endpoint
        ]
        if later {
            values["OllamaSelectedModel"] = "later-model"
            values["ollamaSelectedModel"] = "later-model"
        } else if caseID == "divergent-keys" {
            values["OllamaSelectedModel"] = "old-model"
            values["ollamaSelectedModel"] = "new-model"
        } else if caseID == "coherent-keys" {
            values["OllamaSelectedModel"] = "chosen-model"
            values["ollamaSelectedModel"] = "chosen-model"
        }
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    }
    @MainActor static func waitForDiscovery(_ evidence: URL) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let data = try Data(contentsOf: evidence.appendingPathComponent("http.json"))
            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            let completed = rows.filter { ($0["endpoint"] as? String) == "A" && ($0["responseCompleted"] as? Bool) == true }
            if completed.contains(where: { ($0["method"] as? String) == "GET" && ($0["path"] as? String) == "/" }) && completed.contains(where: { ($0["method"] as? String) == "GET" && ($0["path"] as? String) == "/api/tags" }) {
                await Task.yield()
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw ProbeFailure.invalid("Connection and empty-model discovery did not complete at A")
    }
    @MainActor static func observation(_ result: VoiceInkAIEnhancementResult, request: VoiceInkWritingActionRequest) -> ResultObservation {
        .init(text: result.text, modelName: result.modelName,
              requestMetadataUTF8Equal: result.requestSystemMessage?.utf8.elementsEqual(request.systemMessage.utf8) == true && result.requestUserMessage?.utf8.elementsEqual(request.userMessage.utf8) == true)
    }
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 8, ["no-keys", "divergent-keys", "coherent-keys"].contains(args[1]) else { Darwin.exit(2) }
        let caseID = args[1], endpointA = args[2], endpointB = args[3], bundle = args[4], sourceSHA = args[5]
        let evidence = URL(fileURLWithPath: args[6], isDirectory: true), expected = args[7]
        var receipt = Receipt(caseID: caseID, sourceSHA: sourceSHA, bundleIdentifier: bundle, expectedModel: expected)
        do {
            try require(getuid() != 0 && Bundle.main.bundleIdentifier == bundle, "Isolated signed bundle identity required")
            try require(try persistent(bundle).isEmpty, "Fresh probe identity has persistent preferences")
            defaults(caseID: caseID, endpoint: endpointA, later: false)
            defer { UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
            try require(VoiceInkAIEnhancementProviderPreference.selectedProvider() == .localCLI, "Local CLI must precede production initialization")
            let beforeInit = try persistent(bundle)
            let ai = AIService()
            try require(ai.selectedProvider == .localCLI && ai.apiKey.isEmpty && ai.isAPIKeyValid, "Key-free Local CLI initialization failed")
            let schema = Schema([VocabularyWord.self])
            let config = ModelConfiguration("WritingOllamaProbe-" + UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let service = AIEnhancementService(aiService: ai, modelContext: container.mainContext)
            try require(!service.isEnhancementEnabled && !service.useClipboardContext && !service.useScreenCaptureContext, "Ordinary enhancement and live context must be disabled")
            try checkpoint("initialization", bundle: bundle, before: beforeInit, receipt: &receipt)
            let beforeProvider = try persistent(bundle)
            ai.selectedProvider = .ollama
            let afterProvider = try persistent(bundle)
            let providerWriteValid = beforeProvider.isEmpty && afterProvider == ["selectedAIProvider": VoiceInkAIEnhancementProviderKind.ollama.rawValue]
            receipt.preferenceChecks.append(.init(operation: "select-ollama", deliberateWrite: true, before: beforeProvider, after: afterProvider, passed: providerWriteValid))
            try require(providerWriteValid && ai.apiKey.isEmpty && ai.isAPIKeyValid, "Ollama selection wrote unexpected state")
            try await waitForDiscovery(evidence)
            try checkpoint("discovery", bundle: bundle, before: afterProvider, receipt: &receipt)
            let input = try VoiceInkWritingActionRequest(kind: .rewriteSelection, transcript: "Make this concise; preserve Cafe\u{301} and 東京.\r\nQuote: \"ready\".", selectedText: "Cafe\u{301} 東京\nPublic synthetic text.\t42")
            receipt.systemMessage = input.systemMessage
            receipt.userMessage = input.userMessage
            let beforeCapture = try persistent(bundle)
            let held = try service.writingActionProviderSnapshot()
            receipt.snapshotModel = held.modelName
            try checkpoint("held-capture", bundle: bundle, before: beforeCapture, receipt: &receipt)
            defaults(caseID: caseID, endpoint: endpointB, later: true)
            let beforeModel = try persistent(bundle)
            ai.selectModel("later-model")
            let afterModel = try persistent(bundle)
            var expectedModelWrite = beforeModel
            expectedModelWrite["OllamaSelectedModel"] = "later-model"
            expectedModelWrite["ollamaSelectedModel"] = "later-model"
            let modelWriteValid = afterModel == expectedModelWrite
            receipt.preferenceChecks.append(.init(operation: "select-later-model", deliberateWrite: true, before: beforeModel, after: afterModel, passed: modelWriteValid))
            try require(modelWriteValid, "Menu model selection did not persist exactly the two known model keys")
            receipt.held = observation(try await service.performWritingAction(input, using: held), request: input)
            try checkpoint("held-execution", bundle: bundle, before: afterModel, receipt: &receipt)
            let fresh = try service.writingActionProviderSnapshot()
            receipt.freshSnapshotModel = fresh.modelName
            try checkpoint("fresh-capture", bundle: bundle, before: afterModel, receipt: &receipt)
            receipt.fresh = observation(try await service.performWritingAction(input, using: fresh), request: input)
            receipt.retainedSnapshotModel = held.modelName
            try checkpoint("fresh-execution", bundle: bundle, before: afterModel, receipt: &receipt)
            await Task.yield()
            try checkpoint("final", bundle: bundle, before: afterModel, receipt: &receipt)
        } catch { receipt.error = String(describing: error) }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipt).write(to: evidence.appendingPathComponent("result.json"), options: .atomic)
        } catch { print("Could not retain probe result"); Darwin.exit(2) }
        Darwin.exit(receipt.error == nil && receipt.held != nil && receipt.fresh != nil ? 0 : 1)
    }
}
'''.encode()

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + '\n')

def git(*arguments):
    return subprocess.check_output(['git', '-C', str(REPO), *arguments])

def source(revision, path):
    return git('show', revision + ':' + path)

def logged(command, log, timeout=1200):
    print('RUN ' + ' '.join(map(str, command)), flush=True)
    with log.open('wb') as stream:
        result = subprocess.run(list(map(str, command)), stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        print(log.read_text(errors='replace')[-16000:], flush=True)
        raise RuntimeError('Command failed; see ' + str(log))

def tree_hashes(root):
    return {str(p.relative_to(root)): digest(p.read_bytes()) for p in sorted(root.rglob('*')) if p.is_file()}

def prepare():
    require(not (OUT / 'contract.json').exists(), 'Evidence contract already exists')
    candidate = git('rev-parse', 'HEAD').decode().strip()
    require(candidate != BASELINE, 'Candidate must differ from the exact known-bad baseline')
    canonical_path = 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    canonical = source(BASELINE, canonical_path)
    require(source(candidate, canonical_path) == canonical, 'Candidate changed canonical dependencies')
    pins = {pin['identity']: pin for pin in json.loads(canonical)['pins']}
    require(len(pins) == 41, 'Expected exact canonical 41-pin graph')
    require(pins['llmkit']['state']['revision'] == 'adc2239e2a3c586fd442a8ec1d96dec8e9ae8917', 'Unreviewed LLMkit revision')
    nvidia_lock = source(BASELINE, 'VoiceInkNVIDIA/Package.resolved')
    require(source(candidate, 'VoiceInkNVIDIA/Package.resolved') == nvidia_lock, 'Candidate changed service closure')
    identities = {pin['identity'] for pin in json.loads(nvidia_lock)['pins']} | {'llmkit', 'selectedtextkit', 'axswift', 'keysender'}
    require(len(identities) == 26 and identities <= pins.keys(), 'Expected exact 26-package service closure')
    retained = [pins[key] for key in sorted(identities)]
    dependencies = ['.package(path: "Dependencies/VoiceInkCore")']
    for pin in retained:
        state = pin['state']
        kind, value = ('branch', state['branch']) if 'branch' in state else ('exact', state['version']) if 'version' in state else ('revision', state['revision'])
        dependencies.append('.package(url: ' + json.dumps(pin['location']) + ', ' + kind + ': ' + json.dumps(value) + ')')
    manifest = '''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WritingOllamaProbe", platforms: [.macOS(.v14)],
    dependencies: [\n        ''' + ',\n        '.join(dependencies) + '''
    ], targets: [.executableTarget(name: "WritingOllamaProbe", dependencies: [
        .product(name: "VoiceInkCore", package: "VoiceInkCore"),
        .product(name: "LLMkit", package: "LLMkit"),
        .product(name: "SelectedTextKit", package: "SelectedTextKit")
    ])], swiftLanguageVersions: [.v5])
'''
    contract = {'baseline_sha': BASELINE, 'candidate_sha': candidate, 'driver_sha256': digest(DRIVER), 'oracle_script_sha256': digest(SCRIPT_PATH.read_bytes()), 'manifest_sha256': digest(manifest.encode()), 'canonical_lock_sha256': digest(canonical), 'canonical_pins': pins, 'expected_pins': {p['identity']: p for p in retained}, 'versions': {}, 'scope': 'Actual eleven app files, VoiceInkCore, LLMkit and 26 pinned external packages. Public loopback synthetic responses. No app lifecycle, real Ollama inference, TCC, microphone, or editor-delivery claim.'}
    for version, revision in [('baseline', BASELINE), ('candidate', candidate)]:
        root = OUT / version
        package = root / 'package'
        src = package / 'Sources/WritingOllamaProbe'
        src.mkdir(parents=True)
        dep = package / 'Dependencies'
        dep.mkdir()
        with tarfile.open(fileobj=io.BytesIO(git('archive', revision, 'VoiceInkCore', 'VoiceInkNVIDIA')), mode='r:') as archive:
            members = archive.getmembers()
            require(all(not Path(m.name).is_absolute() and '..' not in Path(m.name).parts and Path(m.name).parts[0] in {'VoiceInkCore', 'VoiceInkNVIDIA'} and (m.isdir() or m.isfile()) for m in members), 'Unsafe archive member')
            archive.extractall(dep, members=members)
        app_hashes = {}
        for path in APP_PATHS:
            data = source(revision, path)
            (src / Path(path).name).write_bytes(data)
            app_hashes[path] = digest(data)
        (src / 'Probe.swift').write_bytes(DRIVER)
        (package / 'Package.swift').write_text(manifest)
        write_json(package / 'Package.resolved', {'pins': retained, 'version': 2})
        contract['versions'][version] = {'source_sha': revision, 'app_sources': app_hashes, 'dependency_sources': tree_hashes(dep), 'bundles': {case: 'com.negentropi.RomaJustTalk.WritingOllamaProbe.' + uuid.uuid4().hex for case in CASES}}
    write_json(OUT / 'contract.json', contract)
    print('PREPARED exact baseline, candidate, unchanged oracle, 41 canonical pins, 26 service pins', flush=True)

def validate_sources(version, contract):
    require(digest(SCRIPT_PATH.read_bytes()) == contract['oracle_script_sha256'], 'Oracle script changed')
    root = OUT / version
    package = root / 'package'
    item = contract['versions'][version]
    require(all(digest((package / 'Sources/WritingOllamaProbe' / Path(path).name).read_bytes()) == expected for path, expected in item['app_sources'].items()), 'App sources changed')
    require(tree_hashes(package / 'Dependencies') == item['dependency_sources'], 'Local dependency sources changed')
    require(digest((package / 'Sources/WritingOllamaProbe/Probe.swift').read_bytes()) == contract['driver_sha256'] == digest(DRIVER), 'Unchanged driver hash failed')
    require(digest((package / 'Package.swift').read_bytes()) == contract['manifest_sha256'], 'Package manifest changed')
    observed = {p['identity']: p for p in json.loads((package / 'Package.resolved').read_text())['pins']}
    require(observed == contract['expected_pins'], 'Resolved service pins changed')

def dependency_receipt(package, contract):
    rows = {}
    checkouts = package / '.build/checkouts'
    for checkout in sorted(checkouts.iterdir()):
        if not checkout.is_dir():
            continue
        run = lambda *args: subprocess.check_output(['git', '-C', str(checkout), *args])
        revision = run('rev-parse', 'HEAD').decode().strip()
        matches = [name for name, pin in contract['expected_pins'].items() if pin['state']['revision'] == revision]
        require(len(matches) == 1, 'Unrecognized checkout ' + checkout.name)
        require(not run('status', '--porcelain', '--untracked-files=no').strip(), 'Modified dependency checkout ' + checkout.name)
        files = run('ls-files', '-z').split(b'\0')
        hashes = {os.fsdecode(p): digest((checkout / os.fsdecode(p)).read_bytes()) for p in files if p and (checkout / os.fsdecode(p)).is_file()}
        identity = matches[0]
        require(identity not in rows, 'Duplicate dependency identity')
        rows[identity] = {'revision': revision, 'tracked_sources': hashes}
        if identity == 'llmkit':
            for path, expected in SDK_BLOBS.items():
                require(run('hash-object', path).decode().strip() == expected, 'Pinned SDK source blob mismatch ' + path)
    require(rows.keys() == contract['expected_pins'].keys(), 'Actual checkout closure differs from exact 26 pins')
    return rows

def build():
    contract = json.loads((OUT / 'contract.json').read_text())
    for version in ['baseline', 'candidate']:
        root, package = OUT / version, OUT / version / 'package'
        validate_sources(version, contract)
        logged(['xcrun', 'swift', 'package', '--package-path', package, '--skip-update', 'resolve'], root / 'resolve.log')
        validate_sources(version, contract)
        before = dependency_receipt(package, contract)
        write_json(root / 'dependencies-before-build.json', before)
        resolved = (package / 'Package.resolved').read_bytes()
        logged(['xcrun', 'swift', 'package', '--package-path', package, '--skip-update', 'show-dependencies', '--format', 'json'], root / 'package-graph.json', timeout=120)
        logged(['xcrun', 'swift', 'build', '--package-path', package, '--force-resolved-versions', '--configuration', 'release', '--product', 'WritingOllamaProbe', '--jobs', '3'], root / 'build.log', timeout=1800)
        require((package / 'Package.resolved').read_bytes() == resolved, 'Build rewrote lock file')
        validate_sources(version, contract)
        after = dependency_receipt(package, contract)
        require(before == after, 'Build changed dependency tracked sources')
        write_json(root / 'dependencies-after-build.json', after)
        binary = Path(subprocess.check_output(['xcrun', 'swift', 'build', '--package-path', str(package), '--force-resolved-versions', '--configuration', 'release', '--show-bin-path']).decode().strip())
        for case, bundle in contract['versions'][version]['bundles'].items():
            app = root / (case + '.app')
            (app / 'Contents/MacOS').mkdir(parents=True)
            shutil.copy2(binary / 'WritingOllamaProbe', app / 'Contents/MacOS/WritingOllamaProbe')
            resources = app / 'Contents/Resources'
            resources.mkdir()
            for resource in binary.glob('*.bundle'):
                shutil.copytree(resource, resources / resource.name)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'WritingOllamaProbe', 'CFBundleName': 'WritingOllamaProbe', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0', 'LSUIElement': True}))
            logged(['codesign', '--force', '--sign', '-', app], root / (case + '-signing.log'), timeout=60)
            logged(['codesign', '--verify', '--deep', '--strict', app], root / (case + '-signature-verification.log'), timeout=60)
            logged(['codesign', '-dvvv', app], root / (case + '-signature.txt'), timeout=60)
            write_json(root / (case + '-bundle-before.json'), tree_hashes(app))
        print('BUILT signed ' + version + ' with verified unchanged sources and package closure', flush=True)

class HTTPPair:
    def __init__(self, evidence):
        self.evidence, self.lock, self.rows, self.servers, self.threads = evidence, threading.Lock(), [], [], []
        write_json(evidence / 'http.json', [])
    def __enter__(self):
        pair = self
        for endpoint in ['A', 'B']:
            class Handler(http.server.BaseHTTPRequestHandler):
                protocol_version = 'HTTP/1.1'
                def log_message(self, *args):
                    pass
                def setup(self):
                    super().setup()
                    self.connection.settimeout(10)
                def handle_request(self):
                    length = int(self.headers.get('Content-Length', '0'))
                    require(0 <= length <= 1048576, 'Unexpected request size')
                    body = self.rfile.read(length).decode('utf-8', errors='strict')
                    status, response = (200, b'OK') if self.command == 'GET' and self.path == '/' else (200, b'{"models":[]}') if self.command == 'GET' and self.path == '/api/tags' else (200, json.dumps({'response': RESPONSE}).encode()) if self.command == 'POST' and self.path == '/api/generate' else (404, b'Unexpected request')
                    row = {'endpoint': self.server.endpoint, 'port': self.server.server_port, 'method': self.command, 'path': self.path, 'body': body, 'contentType': self.headers.get('Content-Type'), 'authorizationPresent': 'Authorization' in self.headers, 'status': status, 'responseCompleted': False}
                    with pair.lock:
                        pair.rows.append(row)
                        pair.persist()
                    try:
                        self.send_response(status)
                        self.send_header('Content-Type', 'application/json')
                        self.send_header('Content-Length', str(len(response)))
                        self.send_header('Connection', 'close')
                        self.end_headers()
                        self.wfile.write(response)
                        self.wfile.flush()
                        with pair.lock:
                            row['responseCompleted'] = True
                            pair.persist()
                    except Exception as error:
                        with pair.lock:
                            row['serverError'] = type(error).__name__
                            pair.persist()
                    self.close_connection = True
                do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = handle_request
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            server.endpoint, server.daemon_threads = endpoint, True
            thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.05}, daemon=True)
            self.servers.append(server)
            self.threads.append(thread)
            thread.start()
        return self
    def persist(self):
        temporary = self.evidence / 'http.pending.json'
        write_json(temporary, self.rows)
        temporary.replace(self.evidence / 'http.json')
    @property
    def urls(self):
        return ['http://127.0.0.1:' + str(server.server_port) for server in self.servers]
    def __exit__(self, *args):
        for server in self.servers:
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(timeout=2)
            require(not thread.is_alive(), 'Owned HTTP listener did not stop')
        with self.lock:
            self.persist()

def classify(case, result, rows, exit_code, identity):
    runtime_model, old_metadata = CASES[case]
    invalid = []
    def check(condition, name):
        if not condition:
            invalid.append(name)
    check(exit_code == 0 and result.get('error') is None, 'service-execution')
    check(result.get('caseID') == case and result.get('sourceSHA') == identity['source_sha'] and result.get('bundleIdentifier') == identity['bundle_identifier'] and result.get('expectedModel') == runtime_model, 'source-case-bundle-binding')
    checks = result.get('preferenceChecks', [])
    required = ['initialization', 'select-ollama', 'discovery', 'held-capture', 'select-later-model', 'held-execution', 'fresh-capture', 'fresh-execution', 'final']
    check([row.get('operation') for row in checks] == required and all(row.get('passed') is True for row in checks), 'preference-isolation-and-explicit-writes')
    for row in checks:
        check(row.get('deliberateWrite') is (row.get('operation') in {'select-ollama', 'select-later-model'}), 'preference-write-classification')
        if row.get('deliberateWrite') is False:
            check(row.get('before') == row.get('after'), 'preference-domain-equality')
    check(bool(result.get('systemMessage')) and bool(result.get('userMessage')), 'request-messages-present')
    check(all(row.get('status') == 200 and row.get('responseCompleted') is True and row.get('authorizationPresent') is False and (row.get('method'), row.get('path')) in {('GET', '/'), ('GET', '/api/tags'), ('POST', '/api/generate')} for row in rows), 'all-http-paths-completed-without-credential')
    check(all(any(row.get('endpoint') == 'A' and row.get('method') == 'GET' and row.get('path') == path for row in rows) for path in ['/', '/api/tags']), 'discovery-observed')
    generates = [row for row in rows if row.get('method') == 'POST' and row.get('path') == '/api/generate']
    check([row.get('endpoint') for row in generates] == ['A', 'B'], 'exact-held-A-then-fresh-B-routing')
    for index, model in enumerate([runtime_model, 'later-model']):
        if index >= len(generates):
            break
        row = generates[index]
        try:
            body = json.loads(row['body'])
            check(set(body) == {'model', 'prompt', 'system', 'temperature', 'stream', 'think'}, 'exact-sdk-wire-field-set')
            check(body.get('model') == model, 'wire-model')
            check(isinstance(body.get('prompt'), str) and body['prompt'].encode() == result.get('userMessage', '').encode() and isinstance(body.get('system'), str) and body['system'].encode() == result.get('systemMessage', '').encode(), 'decoded-prompt-system-UTF8')
            check(body.get('stream') is False and body.get('think') is False and type(body.get('temperature')) in {int, float} and body.get('temperature') == 0.3, 'generation-policy')
            check(row.get('contentType') == 'application/json', 'generation-content-type')
        except (ValueError, KeyError, AttributeError, TypeError):
            invalid.append('generation-json')
    for name in ['held', 'fresh']:
        observation = result.get(name) or {}
        check(observation.get('text') == RESPONSE and observation.get('requestMetadataUTF8Equal') is True, name + '-successful-real-decode-and-request-metadata')
    check((result.get('fresh') or {}).get('modelName') == 'later-model' and result.get('freshSnapshotModel') == 'later-model', 'fresh-model-metadata')
    check(result.get('retainedSnapshotModel') == result.get('snapshotModel'), 'held-snapshot-retained')
    if invalid:
        return {'classification': 'invalid-or-failed', 'failures': sorted(set(invalid))}
    observed = (result.get('held') or {}).get('modelName')
    if observed == runtime_model and result.get('snapshotModel') == runtime_model:
        return {'classification': 'passed', 'failures': []}
    if case != 'coherent-keys' and observed == old_metadata and result.get('snapshotModel') == old_metadata:
        return {'classification': 'expected-metadata-mismatch', 'failures': ['held-result-model-metadata'], 'wire_model': runtime_model, 'result_model': observed}
    return {'classification': 'invalid-or-failed', 'failures': ['unexpected-held-metadata']}

def run():
    contract = json.loads((OUT / 'contract.json').read_text())
    classifications = {}
    for version in ['baseline', 'candidate']:
        validate_sources(version, contract)
        root = OUT / version
        expected = dependency_receipt(root / 'package', contract)
        require(expected == json.loads((root / 'dependencies-after-build.json').read_text()), 'Dependencies changed before execution')
        classifications[version] = {}
        for case, (runtime_model, _) in CASES.items():
            evidence = root / case
            evidence.mkdir(mode=0o700)
            app = root / (case + '.app')
            before = json.loads((root / (case + '-bundle-before.json')).read_text())
            require(tree_hashes(app) == before, 'Signed probe bundle changed before execution')
            logged(['codesign', '--verify', '--deep', '--strict', app], evidence / 'signature-before.log', timeout=60)
            identity = {'source_sha': contract['versions'][version]['source_sha'], 'bundle_identifier': contract['versions'][version]['bundles'][case]}
            write_json(evidence / 'identity.json', identity)
            with HTTPPair(evidence) as pair:
                command = [str(app / 'Contents/MacOS/WritingOllamaProbe'), case, *pair.urls, identity['bundle_identifier'], identity['source_sha'], str(evidence), runtime_model]
                write_json(evidence / 'invocation.json', {'command': command, 'driver_sha256': contract['driver_sha256']})
                with (evidence / 'process.log').open('wb') as stream:
                    try:
                        process = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=50)
                        exit_code = process.returncode
                    except subprocess.TimeoutExpired:
                        exit_code = 124
                write_json(evidence / 'process-exit.json', {'exit_code': exit_code})
            after = tree_hashes(app)
            write_json(evidence / 'bundle-after.json', after)
            require(after == before, 'Signed probe bundle changed during execution')
            logged(['codesign', '--verify', '--deep', '--strict', app], evidence / 'signature-after.log', timeout=60)
            result_path = evidence / 'result.json'
            result = json.loads(result_path.read_text()) if result_path.exists() else {}
            classification = classify(case, result, json.loads((evidence / 'http.json').read_text()), exit_code, identity)
            write_json(evidence / 'classification.json', classification)
            classifications[version][case] = classification
            print(version + ' ' + case + ' ' + classification['classification'], flush=True)
        validate_sources(version, contract)
        require(dependency_receipt(root / 'package', contract) == expected, 'Dependencies changed during execution')
    expected_baseline = {'no-keys': 'expected-metadata-mismatch', 'divergent-keys': 'expected-metadata-mismatch', 'coherent-keys': 'passed'}
    require(digest(SCRIPT_PATH.read_bytes()) == contract['oracle_script_sha256'], 'Oracle script changed during comparison')
    valid = all(classifications['baseline'][case]['classification'] == outcome for case, outcome in expected_baseline.items()) and all(classifications['candidate'][case]['classification'] == 'passed' for case in CASES)
    write_json(OUT / 'comparison.json', {'classification': 'passed-red-green' if valid else 'invalid-or-failed', 'baseline_sha': BASELINE, 'candidate_sha': contract['candidate_sha'], 'driver_sha256': contract['driver_sha256'], 'expected_baseline': expected_baseline, 'cases': classifications, 'scope': contract['scope']})
    require(valid, 'Known-bad metadata red and candidate green were not both proved')

def self_test():
    identity = {'source_sha': 'source', 'bundle_identifier': 'bundle'}
    for case, (runtime_model, old_metadata) in CASES.items():
        prefs = [{'operation': name, 'deliberateWrite': name in {'select-ollama', 'select-later-model'}, 'before': {}, 'after': {}, 'passed': True} for name in ['initialization', 'select-ollama', 'discovery', 'held-capture', 'select-later-model', 'held-execution', 'fresh-capture', 'fresh-execution', 'final']]
        result = {'caseID': case, 'sourceSHA': 'source', 'bundleIdentifier': 'bundle', 'expectedModel': runtime_model, 'systemMessage': 'system 東京', 'userMessage': 'user Cafe\u0301', 'snapshotModel': runtime_model, 'retainedSnapshotModel': runtime_model, 'freshSnapshotModel': 'later-model', 'preferenceChecks': prefs, 'held': {'text': RESPONSE, 'modelName': runtime_model, 'requestMetadataUTF8Equal': True}, 'fresh': {'text': RESPONSE, 'modelName': 'later-model', 'requestMetadataUTF8Equal': True}}
        rows = [{'endpoint': 'A', 'method': 'GET', 'path': path, 'status': 200, 'responseCompleted': True, 'authorizationPresent': False} for path in ['/', '/api/tags']]
        rows += [{'endpoint': endpoint, 'method': 'POST', 'path': '/api/generate', 'status': 200, 'responseCompleted': True, 'authorizationPresent': False, 'contentType': 'application/json', 'body': json.dumps({'model': model, 'system': result['systemMessage'], 'prompt': result['userMessage'], 'stream': False, 'think': False, 'temperature': 0.3})} for endpoint, model in [('A', runtime_model), ('B', 'later-model')]]
        require(classify(case, result, rows, 0, identity)['classification'] == 'passed', 'Classifier rejected candidate')
        old = copy.deepcopy(result)
        old['snapshotModel'] = old['retainedSnapshotModel'] = old['held']['modelName'] = old_metadata
        expected = 'passed' if case == 'coherent-keys' else 'expected-metadata-mismatch'
        require(classify(case, old, rows, 0, identity)['classification'] == expected, 'Classifier accepted wrong baseline outcome')
        for mutation in ['response', 'missing', 'wire', 'exit', 'preferences', 'unknown-path', 'extra-generate']:
            bad_result, bad_rows, bad_exit = copy.deepcopy(old), copy.deepcopy(rows), 0
            if mutation == 'response': bad_result['held']['text'] = ''
            if mutation == 'missing': bad_result.pop('fresh')
            if mutation == 'wire': bad_rows[2]['body'] = '{}'
            if mutation == 'exit': bad_exit = 1
            if mutation == 'preferences': bad_result['preferenceChecks'][0]['after'] = {'unexpected': 'write'}
            if mutation == 'unknown-path': bad_rows[0]['path'] = '/unknown'
            if mutation == 'extra-generate': bad_rows.append(copy.deepcopy(bad_rows[2]))
            require(classify(case, bad_result, bad_rows, bad_exit, identity)['classification'] == 'invalid-or-failed', 'Classifier confused setup/transport failure with regression red ' + mutation)
    print('PASS classifier self-test. Synthetic classifier checks only; no native regression claim.')

try:
    if MODE == 'self-test':
        self_test()
    else:
        OUT.mkdir(parents=True, exist_ok=True)
        {'prepare': prepare, 'build': build, 'run': run}[MODE]()
except Exception as error:
    if MODE != 'self-test':
        write_json(OUT / ('failure-' + MODE + '.json'), {'classification': 'invalid-or-failed', 'phase': MODE, 'error': str(error)})
    raise
PY
