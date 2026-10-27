#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
if [[ "$mode" != prepare && "$mode" != build ]]; then
  echo "Use prepare or build on a disposable GitHub-hosted Mac. Neither mode calls an AI provider." >&2
  exit 2
fi
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin || "$(id -u)" == 0 ]]; then
  echo "Build this probe only on a disposable GitHub-hosted Mac." >&2
  exit 2
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
out="$RUNNER_TEMP/writing-local-cli-service-probe"
package="$out/package"
cd "$repo"
mkdir -p "$out"
trap 'exit_code=$?; if [[ "$exit_code" != 0 ]]; then printf "{\"classification\":\"invalid-or-failed\",\"phase\":\"%s\",\"exit_code\":%s}\n" "$mode" "$exit_code" > "$out/failure.json"; fi' EXIT

if [[ "$mode" == prepare ]]; then
test ! -e "$package"
python3 - "$repo" "$out" "$(git rev-parse HEAD)" <<'PY'
import hashlib
import io
import json
import plistlib
import subprocess
import sys
import tarfile
import uuid
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
revision = sys.argv[3]
def source(path):
    return subprocess.check_output(["git", "-C", str(repo), "show", revision + ":" + path])

digest = lambda data: hashlib.sha256(data).hexdigest()
paths = [
    "VoiceInk/Services/AIEnhancement/AIService.swift",
    "VoiceInk/Services/AIEnhancement/AIEnhancementService.swift",
    "VoiceInk/Services/AIEnhancement/LocalCLIService.swift",
    "VoiceInk/Services/OllamaService.swift",
    "VoiceInk/Services/APIKeyManager.swift",
    "VoiceInk/Services/KeychainService.swift",
    "VoiceInk/Services/CustomVocabularyService.swift",
    "VoiceInk/Services/ScreenCaptureService.swift",
    "VoiceInk/Services/SelectedTextService.swift",
    "VoiceInk/Models/VocabularyWord.swift",
    "VoiceInk/Notifications/AppNotifications.swift"
]
fixture_path = "VoiceInkTests/WritingActionProviderTests.swift"
fixture = source(fixture_path)
begin, end = b"private struct WritingProviderFixture:", b"private struct WritingProviderReceipt:"
if fixture.count(begin) != 1 or fixture.count(end) != 1:
    raise SystemExit("The existing semantic fixture extraction boundary changed")
fixture_types = fixture[fixture.index(begin):fixture.index(end)]
bundle_id = "com.negentropi.RomaJustTalk.WritingLocalCLIProbe." + uuid.uuid4().hex
driver = r'''
import AppKit
import Darwin
import Foundation
import SwiftData
import VoiceInkCore

private enum ProbeMode: String { case deterministic, semantic }
private enum ProbeFailure: Error { case invalid(String) }

private struct ProbeCheck: Encodable {
    let requirement: String
    let passed: Bool
}

private struct ProbeObservation: Encodable {
    let id: String
    let output: String?
    let checks: [ProbeCheck]
}

private struct ProbeReceipt: Encodable {
    let classification: String
    let mode: String
    let sourceSHA: String
    let bundleIdentifier: String
    let observations: [ProbeObservation]
    let persistentProbePreferencesUnchanged: Bool
    let error: String?
    let scope = "Real AIService, AIEnhancementService and LocalCLIService; no app lifecycle, recording, ASR, editor delivery, or physical shortcut proof."
    let credentials = "Local CLI is selected before production initialization. No connected-provider enumeration or provider switching. CLI authentication belongs to its child process."
}

@main
private enum ProbeMain {
    static let sourceSHA = "__SOURCE_SHA__"
    static let expectedBundleIdentifier = "__BUNDLE_ID__"

    @MainActor static func require(_ condition: Bool, _ reason: String) throws {
        if !condition { throw ProbeFailure.invalid(reason) }
    }

    @MainActor static func installCommand(_ command: String) throws {
        UserDefaults.standard.setVolatileDomain([
            VoiceInkUserDefaultsKey.selectedAIProvider: VoiceInkAIEnhancementProviderKind.localCLI.rawValue,
            VoiceInkUserDefaultsKey.isAIEnhancementEnabled: false,
            VoiceInkUserDefaultsKey.useClipboardContext: false,
            VoiceInkUserDefaultsKey.useScreenCaptureContext: false,
            VoiceInkUserDefaultsKey.customPrompts: Data("[]".utf8),
            VoiceInkUserDefaultsKey.selectedPromptId: "RJT-PROBE-NO-SELECTED-PROMPT",
            VoiceInkUserDefaultsKey.enhancementTimeoutSeconds: 45,
            VoiceInkUserDefaultsKey.enhancementRetryOnTimeout: false,
            VoiceInkLocalCLIPreference.commandTemplateKey: command,
            VoiceInkLocalCLIPreference.selectedTemplateKey: VoiceInkLocalCLITemplate.claude.rawValue,
            VoiceInkLocalCLIPreference.timeoutSecondsKey: 45
        ], forName: UserDefaults.argumentDomain)
        try require(VoiceInkAIEnhancementProviderPreference.selectedProvider() == .localCLI,
                    "Volatile Local CLI selection must precede every production initializer")
        try require(VoiceInkLocalCLIPreference.commandTemplate() == command, "Volatile command was not selected")
    }

    @MainActor static func request(_ fixture: WritingProviderFixture) throws -> VoiceInkWritingActionRequest {
        try VoiceInkWritingActionRequest(
            kind: fixture.kind, transcript: fixture.transcript,
            selectedText: fixture.selectedText, targetLanguage: fixture.targetLanguage
        )
    }

    @MainActor static func deterministic(
        _ service: AIEnhancementService, ai: AIService
    ) async throws -> [ProbeObservation] {
        let input = try request(.japaneseToEnglish)
        let expected = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: input.systemMessage, userPrompt: input.userMessage)
        var observations: [ProbeObservation] = []
        let original = try service.writingActionProviderSnapshot()
        try installCommand("/bin/cat >/dev/null; /usr/bin/printf 'RJT_EXPECTED_NONZERO' >&2; exit 23")
        let result = try await service.performWritingAction(input, using: original)
        let snapshotChecks = [
            ProbeCheck(requirement: "Original snapshot command receives exact stdin", passed: result.text == expected),
            ProbeCheck(requirement: "Captured model is Local CLI", passed: result.modelName == "local-cli"),
            ProbeCheck(requirement: "Exact system request is retained", passed: result.requestSystemMessage == input.systemMessage),
            ProbeCheck(requirement: "Exact user request is retained", passed: result.requestUserMessage == input.userMessage),
            ProbeCheck(requirement: "Ordinary enhancement remains disabled", passed: !service.isEnhancementEnabled),
            ProbeCheck(requirement: "Provider remains Local CLI without a key", passed: ai.selectedProvider == .localCLI && ai.apiKey.isEmpty)
        ]
        observations.append(.init(id: "captured-command-and-stdin", output: result.text, checks: snapshotChecks))
        try require(snapshotChecks.allSatisfy { $0.passed }, "Captured command or request transport changed")
        let changed = try service.writingActionProviderSnapshot()
        var changedFailed = false
        do { _ = try await service.performWritingAction(input, using: changed) }
        catch {
            changedFailed = error as? VoiceInkAIEnhancementError == .localCLIExecutionFailure(
                VoiceInkLocalCLIExecutionError.nonZeroExit(status: 23, stderr: "RJT_EXPECTED_NONZERO")
            )
        }
        try require(changedFailed, "A new snapshot did not observe the changed command and exact nonzero error")
        observations.append(.init(id: "new-snapshot-nonzero", output: nil, checks: [
            .init(requirement: "New snapshot propagates the controlled nonzero error", passed: changedFailed)
        ]))
        try installCommand("/bin/cat >/dev/null; /usr/bin/printf '%s\\n%s' \"$VOICEINK_SYSTEM_PROMPT\" \"$VOICEINK_USER_PROMPT\"")
        let environment = try await service.performWritingAction(input, using: service.writingActionProviderSnapshot())
        let environmentMatches = environment.text == input.systemMessage + "\n" + input.userMessage
        try require(environmentMatches, "The real command did not receive the exact prompt environment")
        observations.append(.init(id: "prompt-environment", output: environment.text, checks: [
            .init(requirement: "Exact system and user prompts reach command environment", passed: environmentMatches)
        ]))
        try installCommand("/bin/cat >/dev/null")
        let empty = try service.writingActionProviderSnapshot()
        var emptyFailed = false
        do { _ = try await service.performWritingAction(input, using: empty) }
        catch { emptyFailed = error as? VoiceInkAIEnhancementError == .localCLIExecutionFailure(VoiceInkLocalCLIExecutionError.emptyOutput) }
        try require(emptyFailed, "Empty command output did not fail through the real service")
        observations.append(.init(id: "empty-output", output: nil, checks: [
            .init(requirement: "Empty output propagates the controlled error", passed: emptyFailed)
        ]))
        return observations
    }

    static func shellQuoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @MainActor static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 || arguments.count == 5,
              let mode = ProbeMode(rawValue: String(arguments[1].dropFirst(2))),
              arguments[1] == "--" + mode.rawValue, arguments[2] == "--evidence",
              arguments[3].hasPrefix("/"),
              (mode == .deterministic && arguments.count == 4) || (mode == .semantic && arguments.count == 5) else {
            print("Use --deterministic --evidence /new/directory, or --semantic --evidence /new/directory /absolute/claude")
            Darwin.exit(2)
        }
        let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
        var observations: [ProbeObservation] = []
        var failure: String?
        var preferencesUnchanged = false
        var ownsOutput = false
        do {
            try require(Bundle.main.bundleIdentifier == expectedBundleIdentifier, "Unique probe bundle identity was not loaded")
            try require(getuid() != 0, "Do not run this probe as root")
            try require(output.path.withCString { Darwin.mkdir($0, mode_t(0o700)) } == 0,
                        "A new evidence directory with an existing parent is required")
            ownsOutput = true
            let original = UserDefaults.standard.persistentDomain(forName: expectedBundleIdentifier) ?? [:]
            try require(original.isEmpty, "The unique probe already has persistent preferences")
            defer { UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
            let command: String
            if mode == .semantic {
                try require(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != "true", "Authenticated mode is excluded from CI")
                let cli = arguments[4]
                try require(cli.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: cli), "Claude executable must be an absolute executable path")
                command = shellQuoted(cli) + " --bare --print --tools '' --disable-slash-commands --strict-mcp-config --mcp-config '{\"mcpServers\":{}}' --setting-sources user --no-session-persistence --max-budget-usd 0.50 --output-format text"
            } else { command = "/bin/cat" }
            try installCommand(command)
            let ai = AIService()
            try require(ai.selectedProvider == .localCLI && ai.apiKey.isEmpty && ai.isAPIKeyValid,
                        "Real AIService did not initialize as configured Local CLI")
            let schema = Schema([VocabularyWord.self])
            let configuration = ModelConfiguration(
                "WritingLocalCLIProbe-" + UUID().uuidString, schema: schema,
                isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            try installCommand(command)
            let service = AIEnhancementService(aiService: ai, modelContext: container.mainContext)
            try require(!service.isEnhancementEnabled && !service.useClipboardContext && !service.useScreenCaptureContext,
                        "The probe must disable ordinary enhancement and live context")
            if mode == .deterministic {
                observations = try await deterministic(service, ai: ai)
            } else {
                for fixture in [WritingProviderFixture.japaneseToEnglish, .englishToTraditionalChinese, .conciseSelection] {
                    try installCommand(command)
                    let captured = try service.writingActionProviderSnapshot()
                    try installCommand("/bin/cat >/dev/null; exit 23")
                    let input = try request(fixture)
                    let result = try await service.performWritingAction(input, using: captured)
                    var checks = fixture.checks(result.text).map { ProbeCheck(requirement: $0.requirement, passed: $0.passed) }
                    checks.append(.init(requirement: "Source-bound request metadata is retained", passed: result.requestSystemMessage == input.systemMessage && result.requestUserMessage == input.userMessage))
                    checks.append(.init(requirement: "Ordinary enhancement remains disabled", passed: !service.isEnhancementEnabled))
                    observations.append(.init(id: fixture.id, output: result.text, checks: checks))
                    try require(checks.allSatisfy { $0.passed }, "A bounded semantic requirement failed for " + fixture.id)
                }
            }
            preferencesUnchanged = (UserDefaults.standard.persistentDomain(forName: expectedBundleIdentifier) ?? [:]).isEmpty
            try require(preferencesUnchanged, "A production initializer wrote persistent probe preferences")
        } catch {
            failure = mode == .semantic ? "Authenticated service check failed with " + String(reflecting: type(of: error)) : String(describing: error)
        }
        let passed = failure == nil && preferencesUnchanged && observations.count == (mode == .deterministic ? 4 : 3)
        let receipt = ProbeReceipt(
            classification: passed ? "passed" : "invalid-or-failed", mode: mode.rawValue,
            sourceSHA: sourceSHA, bundleIdentifier: expectedBundleIdentifier,
            observations: observations, persistentProbePreferencesUnchanged: preferencesUnchanged, error: failure
        )
        guard ownsOutput else { print("The probe did not acquire a new evidence directory"); Darwin.exit(EXIT_FAILURE) }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipt).write(to: output.appendingPathComponent("result.json"), options: .atomic)
        } catch { print("Could not retain probe evidence"); Darwin.exit(EXIT_FAILURE) }
        print(passed ? "PASS: " + mode.rawValue + " Local CLI service checks" : "FAIL: Local CLI service checks")
        Darwin.exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
'''.replace("__SOURCE_SHA__", revision).replace("__BUNDLE_ID__", bundle_id)
package = output / "package"
sources = package / "Sources/WritingLocalCLIProbe"
sources.mkdir(parents=True)
dependency_root = package / "Dependencies"
dependency_root.mkdir()
archive = subprocess.check_output(["git", "-C", str(repo), "archive", revision, "VoiceInkCore", "VoiceInkNVIDIA"])
with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
    members = stream.getmembers()
    for member in members:
        relative = Path(member.name)
        if relative.is_absolute() or ".." in relative.parts or relative.parts[0] not in {"VoiceInkCore", "VoiceInkNVIDIA"} or not (member.isdir() or member.isfile()):
            raise SystemExit("Unexpected dependency snapshot member")
    stream.extractall(dependency_root, members=members)
hashes = {}
for path in paths:
    data = source(path)
    (sources / Path(path).name).write_bytes(data)
    hashes[path] = digest(data)
probe = driver.encode() + b"\n" + fixture_types
(sources / "Probe.swift").write_bytes(probe)
canonical = source("VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
pins = {pin["identity"]: pin for pin in json.loads(canonical)["pins"]}
identities = {pin["identity"] for pin in json.loads(source("VoiceInkNVIDIA/Package.resolved"))["pins"]}
identities |= {"llmkit", "selectedtextkit", "axswift", "keysender"}
if len(identities) != 26 or identities - pins.keys():
    raise SystemExit("The reviewed 26-package service closure changed")
retained = [pins[key] for key in sorted(identities)]
dependencies = ['.package(path: "Dependencies/VoiceInkCore")']
for pin in retained:
    state = pin["state"]
    if "branch" in state:
        requirement = "branch: " + json.dumps(state["branch"])
    elif "version" in state:
        requirement = "exact: " + json.dumps(state["version"])
    else:
        requirement = "revision: " + json.dumps(state["revision"])
    dependencies.append(".package(url: " + json.dumps(pin["location"]) + ", " + requirement + ")")
manifest = '''// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WritingLocalCLIProbe", platforms: [.macOS(.v14)],
    dependencies: [
        ''' + ",\n        ".join(dependencies) + '''
    ],
    targets: [.executableTarget(
        name: "WritingLocalCLIProbe",
        dependencies: [
            .product(name: "VoiceInkCore", package: "VoiceInkCore"),
            .product(name: "LLMkit", package: "LLMkit"),
            .product(name: "SelectedTextKit", package: "SelectedTextKit")
        ]
    )], swiftLanguageVersions: [.v5]
)
'''
(package / "Package.swift").write_text(manifest)
(package / "Package.resolved").write_text(json.dumps({"pins": retained, "version": 2}, indent=2, sort_keys=True) + "\n")
app = output / "WritingLocalCLIProbe.app"
(app / "Contents/MacOS").mkdir(parents=True)
(app / "Contents/Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": bundle_id, "CFBundleExecutable": "WritingLocalCLIProbe",
    "CFBundleName": "WritingLocalCLIProbe", "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0", "LSUIElement": True
}))
contract = {
    "source_sha": revision, "bundle_identifier": bundle_id, "app_sources": hashes,
    "dependency_sources": {str(path.relative_to(dependency_root)): digest(path.read_bytes()) for path in sorted(dependency_root.rglob("*")) if path.is_file()},
    "oracle_fixture_path": fixture_path, "oracle_fixture_sha256": digest(fixture),
    "extracted_fixture_sha256": digest(fixture_types), "generated_probe_sha256": digest(probe),
    "package_manifest_sha256": digest(manifest.encode()), "canonical_lock_sha256": digest(canonical),
    "expected_pins": {pin["identity"]: pin for pin in retained},
    "omitted_identities": sorted(pins.keys() - identities),
    "boundary": "Eleven unchanged app files and real dependencies. No app lifecycle or credential behavior substitution. CI executes deterministic shell commands only."
}
(output / "source-contract.json").write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
PY
exit
fi

test -f "$out/source-contract.json"
xcrun swift package --package-path "$package" --skip-update resolve > "$out/resolve.log" 2>&1
python3 - "$out" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
contract = json.loads((root / "source-contract.json").read_text())
raw = (root / "package/Package.resolved").read_bytes()
observed = {pin["identity"]: pin for pin in json.loads(raw)["pins"]}
valid = observed == contract["expected_pins"]
(root / "resolved-pin-receipt.json").write_text(json.dumps({"valid": valid, "observed_pins": observed, "expected_pins": contract["expected_pins"], "resolved_sha256": hashlib.sha256(raw).hexdigest()}, indent=2, sort_keys=True) + "\n")
if not valid:
    raise SystemExit("Service probe resolution changed the reviewed package closure")
(root / "resolved-before-build.json").write_bytes(raw)
PY
xcrun swift build --package-path "$package" --force-resolved-versions --configuration release --product WritingLocalCLIProbe > "$out/build.log" 2>&1
cmp "$out/resolved-before-build.json" "$package/Package.resolved"
xcrun swift build --package-path "$package" --force-resolved-versions --configuration release --show-bin-path > "$out/bin-path.txt"
bin_path="$(cat "$out/bin-path.txt")"
app="$out/WritingLocalCLIProbe.app"
cp "$bin_path/WritingLocalCLIProbe" "$app/Contents/MacOS/WritingLocalCLIProbe"
python3 - "$out" "$bin_path" <<'PY'
import hashlib
import json
import shutil
import sys
from pathlib import Path

root, binary = map(Path, sys.argv[1:])
contract = json.loads((root / "source-contract.json").read_text())
package = root / "package"
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
for path, expected in contract["app_sources"].items():
    if digest(package / "Sources/WritingLocalCLIProbe" / Path(path).name) != expected:
        raise SystemExit("Build changed an app source: " + path)
for path, expected in contract["dependency_sources"].items():
    if digest(package / "Dependencies" / path) != expected:
        raise SystemExit("Build changed a dependency source: " + path)
if digest(package / "Sources/WritingLocalCLIProbe/Probe.swift") != contract["generated_probe_sha256"] or digest(package / "Package.swift") != contract["package_manifest_sha256"]:
    raise SystemExit("Build changed the shared oracle or package manifest")
(root / "sources-after-build.json").write_text(json.dumps({"app_sources_match": True, "dependency_sources_match": True, "oracle_matches": True}, indent=2) + "\n")
resources = root / "WritingLocalCLIProbe.app/Contents/Resources"
resources.mkdir()
for bundle in binary.glob("*.bundle"):
    shutil.copytree(bundle, resources / bundle.name)
PY
codesign --force --sign - "$app" > "$out/signing.log" 2>&1
codesign --verify --deep --strict "$app"
shasum -a 256 "$app/Contents/MacOS/WritingLocalCLIProbe" > "$out/identity-before.txt"
codesign -dvvv "$app" > "$out/signature.txt" 2>&1
"$app/Contents/MacOS/WritingLocalCLIProbe" --deterministic --evidence "$out/deterministic"
shasum -a 256 "$app/Contents/MacOS/WritingLocalCLIProbe" > "$out/identity-after.txt"
cmp "$out/identity-before.txt" "$out/identity-after.txt"
codesign --verify --deep --strict "$app"
python3 - "$out" <<'PY'
import json
import sys
import tarfile
from pathlib import Path

root = Path(sys.argv[1])
result = json.loads((root / "deterministic/result.json").read_text())
contract = json.loads((root / "source-contract.json").read_text())
required = {"captured-command-and-stdin", "new-snapshot-nonzero", "prompt-environment", "empty-output"}
if result.get("classification") != "passed" or result.get("mode") != "deterministic" or result.get("sourceSHA") != contract["source_sha"] or result.get("bundleIdentifier") != contract["bundle_identifier"] or result.get("persistentProbePreferencesUnchanged") is not True or result.get("error") is not None:
    raise SystemExit("The real service deterministic proof failed")
if {row["id"] for row in result["observations"]} != required or len(result["observations"]) != 4 or any(not row["checks"] or any(check["passed"] is not True for check in row["checks"]) for row in result["observations"]):
    raise SystemExit("The real service proof did not execute every required case")
with tarfile.open(root / "signed-probe.tar.gz", "w:gz") as archive:
    archive.add(root / "WritingLocalCLIProbe.app", arcname="WritingLocalCLIProbe.app")
    for name in ["source-contract.json", "identity-before.txt", "signature.txt", "resolved-pin-receipt.json", "sources-after-build.json"]:
        archive.add(root / name, arcname=name)
PY
