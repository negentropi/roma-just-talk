#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
if [[ "$mode" != self-test ]]; then
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo "Run the writing-target probe only on a disposable GitHub-hosted Mac." >&2
  exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
  echo "The probe must own the logged-in desktop session." >&2
  exit 2
fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
out="${RUNNER_TEMP:-/tmp}/writing-target-probe"
baseline_sha=479fa1768e554433467b1355e4c8ded962b01627
candidate_sha="$(git rev-parse HEAD)"
if [[ "$mode" == all ]]; then
  bash "$0" prepare
  for lane in candidate baseline; do
    bash "$0" run "$lane" || true
  done
  bash "$0" verify
  exit
fi
phase="$mode"
mkdir -p "$(dirname "$out")"
trap 'exit_code=$?; if [[ "$exit_code" != 0 && "$mode" != self-test ]]; then printf "{\"classification\":\"invalid-or-failed\",\"boundary\":\"%s\",\"exit_code\":%s}\n" "$phase" "$exit_code" > "$out/failure.json"; fi' EXIT

if [[ "$mode" == prepare || "$mode" == self-test ]]; then
if [[ "$mode" == prepare ]]; then
test ! -e "$out"
mkdir -p "$out"
git fetch --no-tags origin "$baseline_sha"
fi
python3 - "$repo" "$out" "$baseline_sha" "$candidate_sha" "$mode" <<'PY'
import hashlib
import io
import json
import re
import subprocess
import sys
import tarfile
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
baseline_sha, candidate_sha, mode = sys.argv[3:]
def source(revision, path):
    return subprocess.check_output(["git", "-C", str(repo), "show", revision + ":" + path])

def delivery_adapter(native):
    # Adapt only the public delivery result; target validation and writes stay native.
    replaces = len(re.findall(rb"\bfunc replace\(with text: String(?:\)|,)", native))
    delivers = len(re.findall(rb"\bfunc deliver\(\s*with text: String,", native))
    if (replaces, delivers) == (1, 0):
        api = "historical-throwing-replace"
        body = "        try await target.replace(with: text)"
    elif (replaces, delivers) == (0, 1):
        api = "delivery-outcome"
        body = """        switch await target.deliver(with: text) {
        case .confirmed: return
        case .notAttempted(let error), .attemptedUnconfirmed(let error): throw error
        }"""
    else:
        raise ValueError("Expected exactly one recognized native delivery API")
    adapter = """@MainActor
private enum ProbeDelivery {
    static func perform(_ target: WritingTarget, with text: String) async throws {
""" + body + """
    }
}

"""
    return api, adapter.encode()

if mode == "self-test":
    historical = source(baseline_sha, "VoiceInk/Services/WritingTarget.swift")
    assert delivery_adapter(historical)[0] == "historical-throwing-replace"
    current = source(candidate_sha, "VoiceInk/Services/WritingTarget.swift")
    api, adapter = delivery_adapter(current)
    assert (b"target.replace(" in adapter) is (api == "historical-throwing-replace")
    assert (b"target.deliver(" in adapter) is (api == "delivery-outcome")
    outcome = b"func deliver(\n        with text: String,"
    assert delivery_adapter(outcome)[0] == "delivery-outcome"
    for invalid in [b"", historical + outcome, historical + historical, outcome + outcome]:
        try:
            delivery_adapter(invalid)
        except ValueError:
            continue
        raise AssertionError("An ambiguous or missing native API was accepted")
    print("PASS: source-bound native delivery adapters; four invalid API shapes rejected; no native execution")
    raise SystemExit(0)

native_paths = [
    "VoiceInk/Services/WritingTarget.swift", "VoiceInk/Paste/CursorPaster.swift",
    "VoiceInk/Services/CursorTextContextReader.swift", "VoiceInk/Paste/ClipboardManager.swift"
]
fixture_path = "VoiceInkTests/WritingTargetLiveTests.swift"
fixture = source(candidate_sha, fixture_path)
marker = b"private enum LiveWritingFailure:"
if fixture.count(marker) != 1:
    raise SystemExit("The editor helper extraction boundary changed")
helper = fixture[fixture.index(marker):]
driver = r'''
@MainActor
private enum Issue {
    static var messages: [String] = []

    static func record(_ message: String) {
        messages.append(message)
        print("Fixture issue: \(message)")
    }
}

private enum ProbePhase: String {
    case launch, editorSetup, selection, capture, drift, replacement, cleanup, completed
}

private enum ProbeFailure: Error {
    case expectation(String)
}

private struct ProbeSelectionRange: Encodable {
    let location: Int
    let length: Int
}

private struct ProbeReadbackSample: Encodable {
    let startedMilliseconds: Double
    let valueReadMilliseconds: Double
    let elapsedMilliseconds: Double
    let observedValue: String?
    let observedUTF16Count: Int?
    let selectedText: String?
    let selectedRange: ProbeSelectionRange?
    let exactExpectedUTF16: Bool
    let canonicalExpectedEqual: Bool
    let exactOriginalUTF16: Bool
    let firstDifferentExpectedUTF16Offset: Int?
    let contentState: String
}

@MainActor
private enum ProbeRun {
    static var phase = ProbePhase.launch
    static var checks: [String: Bool] = [:]

    static func require(_ condition: Bool, _ name: String) throws {
        checks[name] = condition
        if !condition { throw ProbeFailure.expectation(name) }
    }

    static func observeFailedReplacement(
        _ editor: LiveWritingEditor, expected: String, error: Error, output: URL
    ) async {
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + 2
        var samples: [ProbeReadbackSample] = []
        repeat {
            let sampleStarted = ProcessInfo.processInfo.systemUptime
            let value = editor.value
            let valueRead = ProcessInfo.processInfo.systemUptime
            var rawText: CFTypeRef?
            let textResult = AXUIElementCopyAttributeValue(editor.editor, kAXSelectedTextAttribute as CFString, &rawText)
            let selection = editor.selectedRange.map { ProbeSelectionRange(location: $0.location, length: $0.length) }
            let exactExpected = value?.utf16.elementsEqual(expected.utf16) == true
            let exactOriginal = value?.utf16.elementsEqual(LiveWritingEditor.original.utf16) == true
            let mismatch: Int?
            if let value {
                let currentUnits = Array(value.utf16)
                let expectedUnits = Array(expected.utf16)
                mismatch = zip(currentUnits, expectedUnits).enumerated()
                    .first { $0.element.0 != $0.element.1 }?.offset
                    ?? (currentUnits.count == expectedUnits.count ? nil : min(currentUnits.count, expectedUnits.count))
            } else { mismatch = nil }
            samples.append(ProbeReadbackSample(
                startedMilliseconds: (sampleStarted - started) * 1_000,
                valueReadMilliseconds: (valueRead - started) * 1_000,
                elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1_000,
                observedValue: value, observedUTF16Count: value?.utf16.count,
                selectedText: textResult == .success ? rawText as? String : nil,
                selectedRange: selection, exactExpectedUTF16: exactExpected,
                canonicalExpectedEqual: value == expected, exactOriginalUTF16: exactOriginal,
                firstDifferentExpectedUTF16Offset: mismatch,
                contentState: exactExpected ? "expected" : exactOriginal ? "original" : value == nil ? "unavailable" : "changed-unexpectedly"
            ))
            guard ProcessInfo.processInfo.systemUptime < deadline, samples.count < 41 else { break }
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { break }
        } while ProcessInfo.processInfo.systemUptime < deadline
        do {
            let sampleData = try JSONEncoder().encode(samples)
            let receipt: [String: Any] = [
                "productionError": String(describing: error), "phase": phase.rawValue,
                "expectedValue": expected, "expectedUTF16Count": expected.utf16.count,
                "originalValue": LiveWritingEditor.original,
                "pollingStartBudgetMilliseconds": 2_000, "maximumSamples": 41,
                "actualPollingDurationMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1_000,
                "diagnosticAXReadTimeoutSource": "LiveWritingEditor.value and selectedRange",
                "automaticWriteRetry": false,
                "expectedAppearedAfterError": samples.contains { $0.exactExpectedUTF16 },
                "finalContentState": samples.last?.contentState ?? "unobserved",
                "samples": try JSONSerialization.jsonObject(with: sampleData)
            ]
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("replacement-failure.json"), options: .atomic)
        } catch { Issue.record("Could not retain failed replacement observations: \(error)") }
        editor.recordOperationFailure("standalone-safari-replacement-failure", expected: expected)
    }

    static func exercise(output: URL) async throws {
        phase = .editorSetup
        let editor = try await LiveWritingEditor.open(.safari)
        defer { editor.close() }
        phase = .selection
        try await editor.selectOriginalPassage()
        phase = .capture
        let captured = try WritingTarget.capture(requiresSelection: true)
        try require(captured.selectedText.utf16.elementsEqual(LiveWritingEditor.passage.utf16),
                    "captured-selection-exact")
        phase = .drift
        try await editor.select(NSRange(location: 0, length: 3))
        var refused = false
        do {
            try await ProbeDelivery.perform(captured, with: "MUST NOT BE INSERTED")
        } catch {
            refused = error as? WritingTarget.Failure == .targetChanged
        }
        try require(refused, "selected-range-drift-refused")
        try require(editor.value?.utf16.elementsEqual(LiveWritingEditor.original.utf16) == true,
                    "drift-left-original-untouched")
        try await editor.selectOriginalPassage()
        let target = try WritingTarget.capture(requiresSelection: true)
        phase = .replacement
        let replacement = "Translated 日本語\nNext paragraph"
        let expected = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
        do { try await ProbeDelivery.perform(target, with: replacement) }
        catch {
            await observeFailedReplacement(editor, expected: expected, error: error, output: output)
            throw error
        }
        try await editor.waitForValue(expected)
        try require(editor.value?.utf16.elementsEqual(expected.utf16) == true,
                    "replacement-exact-prefix-suffix")
        editor.record("standalone-safari-replacement", expected: expected)
        phase = .cleanup
    }

    static func run(output: URL) async -> Int32 {
        var failure: String?
        do { try await exercise(output: output) }
        catch { failure = String(describing: error) }
        let expected = Set([
            "captured-selection-exact", "selected-range-drift-refused",
            "drift-left-original-untouched", "replacement-exact-prefix-suffix"
        ])
        let passed = failure == nil && Issue.messages.isEmpty
            && Set(checks.keys) == expected && checks.values.allSatisfy { $0 }
        if passed { phase = .completed }
        let result: [String: Any] = [
            "classification": passed ? "passed" : "invalid-or-failed",
            "scope": "Real native delivery files and Core/NVIDIA packages plus the shared live Safari helper; not full app E2E",
            "phase": phase.rawValue, "checks": checks,
            "error": failure as Any? ?? NSNull(), "fixtureIssues": Issue.messages,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "<missing>",
            "executablePath": Bundle.main.executableURL?.path ?? "<missing>",
            "processIdentifier": ProcessInfo.processInfo.processIdentifier,
            "accessibilityTrusted": AXIsProcessTrusted(),
            "screenCaptureGranted": CGPreflightScreenCaptureAccess()
        ]
        do {
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("result.json"), options: .atomic)
        } catch {
            print("Could not retain the probe result: \(error)")
            return EXIT_FAILURE
        }
        print(passed ? "PASS: production Safari target checks" : "FAIL: \(failure ?? "fixture issue")")
        return passed ? EXIT_SUCCESS : EXIT_FAILURE
    }
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let output: URL
    init(output: URL) { self.output = output }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            Darwin.exit(await ProbeRun.run(output: output))
        }
    }
}

@main
private enum ProbeMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, arguments[1] == "--output" else {
            print("Expected --output and an evidence directory")
            Darwin.exit(EXIT_FAILURE)
        }
        let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
        setenv("RJT_LIVE_WRITING_TARGET_EVIDENCE", output.appendingPathComponent("observations").path, 1)
        do {
            try String(ProcessInfo.processInfo.processIdentifier)
                .write(to: output.appendingPathComponent("process-id.txt"), atomically: true, encoding: .utf8)
        } catch { Darwin.exit(EXIT_FAILURE) }
        let application = NSApplication.shared
        let delegate = ProbeDelegate(output: output)
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
'''
imports = b"import AppKit\nimport Carbon.HIToolbox\nimport Darwin\nimport Foundation\n\n"
digest = lambda value: hashlib.sha256(value).hexdigest()
lock_path = "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
canonical_bytes = source(candidate_sha, lock_path)
if source(baseline_sha, lock_path) != canonical_bytes:
    raise SystemExit("The reviewed app lock differs between comparison revisions")
canonical = json.loads(canonical_bytes)
canonical_pins = {pin["identity"]: pin for pin in canonical["pins"]}
closure_bytes = source(candidate_sha, "VoiceInkNVIDIA/Package.resolved")
closure = {pin["identity"] for pin in json.loads(closure_bytes)["pins"]}
if not closure or closure - canonical_pins.keys():
    raise SystemExit("The declared Core/NVIDIA closure is missing from the reviewed app lock")
for path in ["VoiceInkCore/Package.swift", "VoiceInkNVIDIA/Package.swift"]:
    if source(baseline_sha, path) != source(candidate_sha, path):
        raise SystemExit("Dependency declarations differ between native comparison revisions: " + path)
retained = [canonical_pins[key] for key in sorted(closure)]
subset = {"pins": retained, "version": 2}
subset_bytes = (json.dumps(subset, indent=2, sort_keys=True) + "\n").encode()
dependencies = ['.package(path: "Dependencies/VoiceInkCore")']
for pin in retained:
    state = pin["state"]
    requirement = "exact: " + json.dumps(state["version"]) if "version" in state else "revision: " + json.dumps(state["revision"])
    dependencies.append(".package(url: " + json.dumps(pin["location"]) + ", " + requirement + ")")
package_manifest = '''// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WritingTargetProbe",
    platforms: [.macOS(.v14)],
    dependencies: [
        ''' + ",\n        ".join(dependencies) + '''
    ],
    targets: [.executableTarget(
        name: "WritingTargetProbe",
        dependencies: [.product(name: "VoiceInkCore", package: "VoiceInkCore")]
    )],
    swiftLanguageVersions: [.v5]
)
'''
shared_probe = imports + helper + driver.encode()
pin_receipt = {
    "canonical_path": lock_path, "canonical_sha256": digest(canonical_bytes),
    "canonical_pin_count": len(canonical_pins), "retained_pins": retained,
    "omitted_identities": sorted(canonical_pins.keys() - closure),
    "retained_pin_count": len(retained), "changed_retained_pins": [],
    "selection": "NVIDIA closure identities from its tracked lock; ALL pin states from the reviewed app lock",
    "resolution_policy": "Every retained version/revision is constrained exactly; reject extras, omissions or state changes before build"
}
(output / "pin-subset-before-resolution.json").write_text(json.dumps(pin_receipt, indent=2, sort_keys=True) + "\n")
(output / "canonical.Package.resolved").write_bytes(canonical_bytes)
lane_contracts = {}
for lane, revision in [("baseline", baseline_sha), ("candidate", candidate_sha)]:
    lane_root = output / lane
    package = lane_root / "package"
    sources = package / "Sources/WritingTargetProbe"
    dependencies_root = package / "Dependencies"
    sources.mkdir(parents=True)
    dependencies_root.mkdir()
    (lane_root / "observations").mkdir()
    archive = subprocess.check_output(["git", "-C", str(repo), "archive", revision, "VoiceInkCore", "VoiceInkNVIDIA"])
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
        members = stream.getmembers()
        for member in members:
            relative = Path(member.name)
            if relative.is_absolute() or ".." in relative.parts or relative.parts[0] not in {"VoiceInkCore", "VoiceInkNVIDIA"}:
                raise SystemExit("Unexpected dependency archive path")
            if not member.isdir() and not member.isfile():
                raise SystemExit("Dependency snapshots require regular files and directories")
        stream.extractall(dependencies_root, members=members)
    native_hashes = {}
    for path in native_paths:
        data = source(revision, path)
        (sources / Path(path).name).write_bytes(data)
        native_hashes[path] = digest(data)
    delivery_api, adapter = delivery_adapter(source(revision, native_paths[0]))
    generated_probe = shared_probe + adapter
    (sources / "Probe.swift").write_bytes(generated_probe)
    (package / "Package.swift").write_text(package_manifest)
    (package / "Package.resolved").write_bytes(subset_bytes)
    dependency_hashes = {
        str(path.relative_to(dependencies_root)): digest(path.read_bytes())
        for path in sorted(dependencies_root.rglob("*")) if path.is_file()
    }
    lane_contracts[lane] = {
        "source_sha": revision, "native_sources": native_hashes,
        "dependency_sources": dependency_hashes,
        "generated_probe_sha256": digest(generated_probe),
        "delivery_api": delivery_api, "delivery_adapter_sha256": digest(adapter),
        "shared_probe_sha256": digest(shared_probe),
        "package_manifest_sha256": digest(package_manifest.encode()),
        "package_seed_lock_sha256": digest(subset_bytes)
    }
    (lane_root / "source-contract.json").write_text(json.dumps(lane_contracts[lane], indent=2, sort_keys=True) + "\n")
contract = {
    "baseline_sha": baseline_sha, "candidate_sha": candidate_sha,
    "oracle_fixture": {"source_sha": candidate_sha, "path": fixture_path, "sha256": digest(fixture)},
    "extracted_helper_sha256": digest(helper), "driver_sha256": digest(driver.encode()),
    "lanes": lane_contracts,
    "extraction": "Each lane uses byte-identical native and Core/NVIDIA files from its own revision; both use one shared current helper and behavioral driver",
    "testing_adapter": "Explicit source-selected native API adapters map throwing replace or deliver outcomes to the same confirmed-success/error checks. Issue.record collects helper diagnostics; no AX or dependency behavior substitution",
    "swift_language": "5, matching the app project; awaiting historical sync replace may warn without changing its body",
    "boundary": "Matched native delivery and real dependency comparison only; full application gates remain required"
}
(output / "source-contract.json").write_text(json.dumps(contract, indent=2, sort_keys=True) + "\n")
PY
exit
fi

if [[ "$mode" == verify ]]; then
phase=comparison
python3 - "$out" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected_checks = {"captured-selection-exact", "selected-range-drift-refused", "drift-left-original-untouched", "replacement-exact-prefix-suffix"}
verdicts = {}
for lane in ["baseline", "candidate"]:
    path = root / lane
    errors = []
    result = json.loads((path / "result.json").read_text()) if (path / "result.json").is_file() else {}
    checks = result.get("checks", {})
    if lane == "candidate":
        if result.get("classification") != "passed" or set(checks) != expected_checks or not all(checks.values()) or result.get("error") is not None:
            errors.append("Candidate did not pass every native check")
    else:
        if result.get("classification") != "invalid-or-failed" or result.get("phase") != "replacement" or result.get("error") != "replacementUnconfirmed" or set(checks) != expected_checks - {"replacement-exact-prefix-suffix"} or not all(checks.values()):
            errors.append("Baseline did not reproduce the precise confirmed precondition and failed replacement")
        observation_path = path / "replacement-failure.json"
        observation = json.loads(observation_path.read_text()) if observation_path.is_file() else {}
        samples = observation.get("samples", [])
        if not samples or observation.get("expectedAppearedAfterError") is not False or any(sample.get("exactOriginalUTF16") is not True or sample.get("exactExpectedUTF16") is not False or sample.get("observedValue") != observation.get("originalValue") or sample.get("contentState") != "original" for sample in samples):
            errors.append("Baseline readback did not remain readable and exactly unchanged throughout observation")
    if result.get("fixtureIssues") or (path / "failure.json").exists() or not (path / "identity-after.txt").is_file():
        errors.append("Lane setup, cleanup, source, build or identity proof failed")
    pin_receipt_path = path / "resolved-pin-receipt.json"
    pin_receipt = json.loads(pin_receipt_path.read_text()) if pin_receipt_path.is_file() else {}
    if pin_receipt.get("valid") is not True or pin_receipt.get("expected_pins") != pin_receipt.get("observed_pins"):
        errors.append("Exact resolved package proof is missing or invalid")
    source_receipt_path = path / "sources-after-build.json"
    source_receipt = json.loads(source_receipt_path.read_text()) if source_receipt_path.is_file() else {}
    if source_receipt != {"native_sources_match": True, "dependency_sources_match": True, "oracle_matches": True}:
        errors.append("Post-build source fidelity proof is missing or invalid")
    if (path / "identity-before.txt").is_file() and (path / "identity-after.txt").is_file():
        if (path / "identity-before.txt").read_bytes() != (path / "identity-after.txt").read_bytes():
            errors.append("The runtime executable identity changed")
    else:
        errors.append("Executable identity receipts are missing")
    verdicts[lane] = {"valid": not errors, "errors": errors, "observed": result}
valid = all(value["valid"] for value in verdicts.values())
(root / "result.json").write_text(json.dumps({"classification": "matched-red-green" if valid else "invalid-or-failed", "scope": "Native delivery with real Core/NVIDIA dependencies, not full app E2E", "lanes": verdicts}, indent=2) + "\n")
if not valid:
    raise SystemExit("Native comparison did not prove the precise known-bad failure and candidate success")
PY
exit
fi

if [[ "$mode" != run || "${2:-}" != candidate && "${2:-}" != baseline ]]; then
  echo "Use prepare, run candidate, run baseline, verify, or all." >&2
  exit 2
fi
lane="$2"
comparison_root="$out"
out="$comparison_root/$lane"
package="$out/package"
scratch="$comparison_root/swiftpm-build"
test -f "$package/Package.swift"
phase="$lane-resolve"
xcrun swift package --package-path "$package" --scratch-path "$scratch" --cache-path "$RUNNER_TEMP/writing-target-probe-package-cache" \
  --skip-update resolve > "$out/resolve.log" 2>&1
python3 - "$comparison_root" "$out" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

comparison, lane = map(Path, sys.argv[1:])
receipt = json.loads((comparison / "pin-subset-before-resolution.json").read_text())
expected = {pin["identity"]: pin for pin in receipt["retained_pins"]}
raw = (lane / "package/Package.resolved").read_bytes()
observed = {pin["identity"]: pin for pin in json.loads(raw)["pins"]}
valid = expected == observed
(lane / "resolved-pin-receipt.json").write_text(json.dumps({"valid": valid, "expected_pins": expected, "observed_pins": observed, "resolved_sha256": hashlib.sha256(raw).hexdigest()}, indent=2, sort_keys=True) + "\n")
if not valid:
    raise SystemExit("Probe resolution changed the canonical subset; review before building")
(lane / "resolved-before-build.json").write_bytes(raw)
PY

phase="$lane-build"
app="$out/WritingTargetProbe.app"
executable="$app/Contents/MacOS/WritingTargetProbe"
mkdir -p "$app/Contents/MacOS"
python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "com.negentropi.RomaJustTalk.WritingTargetProbe",
    "CFBundleExecutable": "WritingTargetProbe", "CFBundleName": "WritingTargetProbe",
    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0",
    "NSPrincipalClass": "NSApplication", "LSUIElement": True
}))
PY
xcrun swift build --package-path "$package" --scratch-path "$scratch" --cache-path "$RUNNER_TEMP/writing-target-probe-package-cache" \
  --force-resolved-versions --configuration debug --product WritingTargetProbe > "$out/build.log" 2>&1
cmp "$out/resolved-before-build.json" "$package/Package.resolved"
python3 - "$out" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
contract = json.loads((root / "source-contract.json").read_text())
package = root / "package"
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
for path, expected in contract["native_sources"].items():
    if digest(package / "Sources/WritingTargetProbe" / Path(path).name) != expected:
        raise SystemExit("Build changed a native source: " + path)
for path, expected in contract["dependency_sources"].items():
    if digest(package / "Dependencies" / path) != expected:
        raise SystemExit("Build changed a Core/NVIDIA source: " + path)
if digest(package / "Sources/WritingTargetProbe/Probe.swift") != contract["generated_probe_sha256"] or digest(package / "Package.swift") != contract["package_manifest_sha256"]:
    raise SystemExit("Build changed the shared oracle or package declaration")
(root / "sources-after-build.json").write_text(json.dumps({"native_sources_match": True, "dependency_sources_match": True, "oracle_matches": True}, indent=2) + "\n")
PY
xcrun swift build --package-path "$package" --scratch-path "$scratch" --cache-path "$RUNNER_TEMP/writing-target-probe-package-cache" \
  --force-resolved-versions --configuration debug --show-bin-path > "$out/bin-path.txt"
bin_path="$(cat "$out/bin-path.txt")"
test -x "$bin_path/WritingTargetProbe"
cp "$bin_path/WritingTargetProbe" "$executable"
python3 - "$bin_path" "$app" <<'PY'
import shutil
import sys
from pathlib import Path

binary, app = map(Path, sys.argv[1:])
resources = app / "Contents/Resources"
resources.mkdir()
for bundle in binary.glob("*.bundle"):
    shutil.copytree(bundle, resources / bundle.name)
PY
cmp "$out/resolved-before-build.json" "$package/Package.resolved"
codesign --force --sign - "$app" > "$out/signing.log" 2>&1
codesign --verify --deep --strict "$app"
codesign -dr - "$app" 2>&1 | sed -n \
  -e 's/^# designated => //p' -e 's/^designated => //p' > "$out/host-requirement.txt"
test -s "$out/host-requirement.txt"
csreq -r "$out/host-requirement.txt" -b "$out/host.csreq"
shasum -a 256 "$executable" > "$out/identity-before.txt"

phase="$lane-permissions"
requirement_hex="$(xxd -p "$out/host.csreq" | tr -d '\n')"
test -n "$requirement_hex"
for service in kTCCServiceAccessibility kTCCServiceScreenCapture; do
  printf '%s\n' "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('$service','com.negentropi.RomaJustTalk.WritingTargetProbe',0,2,4,1,X'$requirement_hex',0,'UNUSED',0);" \
    | sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db'
done
sudo sqlite3 -json '/Library/Application Support/com.apple.TCC/TCC.db' \
  "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='com.negentropi.RomaJustTalk.WritingTargetProbe' AND service IN ('kTCCServiceAccessibility','kTCCServiceScreenCapture');" > "$out/tcc.json"
python3 - "$out" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
rows = json.loads((root / "tcc.json").read_text())
requirement = (root / "host.csreq").read_bytes().hex().upper()
if len(rows) != 2 or {row["service"] for row in rows} != {"kTCCServiceAccessibility", "kTCCServiceScreenCapture"} or any(row["auth_value"] != 2 or row["requirement"] != requirement for row in rows):
    raise SystemExit("Fresh TCC grants do not match the exact signed probe")
PY
killall tccd 2>/dev/null || true
sudo killall tccd 2>/dev/null || true
sleep 2

phase="$lane-run"
python3 - "$out" "$app" "$executable" "$lane" <<'PY'
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

output, app, executable = map(Path, sys.argv[1:4])
lane = sys.argv[4]
command = ["/usr/bin/open", "-n", "-W", "-o", str(output / "process.stdout.log"), "--stderr", str(output / "process.stderr.log"), str(app), "--args", "--output", str(output)]
with (output / "launcher.log").open("w") as log:
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    try:
        code = process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait(timeout=10)
        pid_file = output / "process-id.txt"
        if pid_file.is_file():
            pid = int(pid_file.read_text())
            observed = subprocess.run(["ps", "-ww", "-p", str(pid), "-o", "comm="], text=True, capture_output=True).stdout.strip()
            if observed == str(executable):
                os.kill(pid, signal.SIGTERM)
        raise SystemExit("The owned native probe exceeded 90 seconds")
if code != 0:
    raise SystemExit(f"LaunchServices failed with exit {code}")
result_path = output / "result.json"
if not result_path.is_file():
    raise SystemExit("The native probe did not produce a result")
result = json.loads(result_path.read_text())
if result.get("bundleIdentifier") != "com.negentropi.RomaJustTalk.WritingTargetProbe" or Path(result.get("executablePath", "")).resolve() != executable.resolve() or result.get("processIdentifier") != int((output / "process-id.txt").read_text()):
    raise SystemExit("The observed probe identity does not match the built application")
print(f"Retained {lane} native result: {result.get('classification')}; final comparison owns the verdict")
PY
phase="$lane-identity"
shasum -a 256 "$executable" > "$out/identity-after.txt"
cmp "$out/identity-before.txt" "$out/identity-after.txt"
codesign --verify --deep --strict "$app"
