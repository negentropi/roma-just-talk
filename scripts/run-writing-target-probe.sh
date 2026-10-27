#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo "Run the writing-target probe only on a disposable GitHub-hosted Mac." >&2
  exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
  echo "The probe must own the logged-in desktop session." >&2
  exit 2
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
out="$RUNNER_TEMP/writing-target-probe"
test ! -e "$out"
mkdir -p "$out/source" "$out/observations"
phase=source
trap 'exit_code=$?; if [[ "$exit_code" != 0 ]]; then printf "{\"classification\":\"invalid-or-failed\",\"boundary\":\"%s\",\"exit_code\":%s}\n" "$phase" "$exit_code" > "$out/failure.json"; fi' EXIT

python3 - "$repo" "$out" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

repo, output = map(Path, sys.argv[1:])
target_path = "VoiceInk/Services/WritingTarget.swift"
fixture_path = "VoiceInkTests/WritingTargetLiveTests.swift"
target = (repo / target_path).read_bytes()
fixture = (repo / fixture_path).read_bytes()
for path, data in [(target_path, target), (fixture_path, fixture)]:
    committed = subprocess.check_output(["git", "-C", str(repo), "show", "HEAD:" + path])
    if data != committed:
        raise SystemExit("The probe requires committed source: " + path)
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

@MainActor
private enum ProbeRun {
    static var phase = ProbePhase.launch
    static var checks: [String: Bool] = [:]

    static func require(_ condition: Bool, _ name: String) throws {
        checks[name] = condition
        if !condition { throw ProbeFailure.expectation(name) }
    }

    static func exercise() async throws {
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
            try captured.replace(with: "MUST NOT BE INSERTED")
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
        try target.replace(with: replacement)
        let expected = LiveWritingEditor.prefix + replacement + LiveWritingEditor.suffix
        try await editor.waitForValue(expected)
        try require(editor.value?.utf16.elementsEqual(expected.utf16) == true,
                    "replacement-exact-prefix-suffix")
        editor.record("standalone-safari-replacement", expected: expected)
        phase = .cleanup
    }

    static func run(output: URL) async -> Int32 {
        var failure: String?
        do { try await exercise() }
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
            "scope": "Production WritingTarget plus the extracted live Safari helper; not full app E2E",
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
(output / "source/WritingTarget.swift").write_bytes(target)
(output / "source/Probe.swift").write_bytes(imports + helper + driver.encode())
digest = lambda value: hashlib.sha256(value).hexdigest()
manifest = {
    "source_sha": subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip(),
    "production_source": {"path": target_path, "sha256": digest(target)},
    "fixture_source": {"path": fixture_path, "sha256": digest(fixture)},
    "extracted_helper_sha256": digest(helper),
    "generated_probe_sha256": digest(imports + helper + driver.encode()),
    "driver_sha256": digest(driver.encode()),
    "extraction": "The byte-identical suffix beginning private enum LiveWritingFailure; production WritingTarget is copied unchanged",
    "testing_adapter": "Issue.record collects helper diagnostics as failures; no Testing module, AX mock, helper predicate or target behavior substitution",
    "boundary": "Native production-class and live-fixture diagnosis only; full application gates remain required"
}
(output / "source-contract.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY

phase=build
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
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-name WritingTargetProbe "$out/source/WritingTarget.swift" "$out/source/Probe.swift" \
  -o "$executable" > "$out/build.log" 2>&1
codesign --force --sign - "$app" > "$out/signing.log" 2>&1
codesign --verify --deep --strict "$app"
codesign -dr - "$app" 2>&1 | sed -n \
  -e 's/^# designated => //p' -e 's/^designated => //p' > "$out/host-requirement.txt"
test -s "$out/host-requirement.txt"
csreq -r "$out/host-requirement.txt" -b "$out/host.csreq"
shasum -a 256 "$executable" > "$out/identity-before.txt"

phase=permissions
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

phase=run
python3 - "$out" "$app" "$executable" <<'PY'
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

output, app, executable = map(Path, sys.argv[1:])
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
expected = {"captured-selection-exact", "selected-range-drift-refused", "drift-left-original-untouched", "replacement-exact-prefix-suffix"}
if result.get("classification") != "passed" or set(result.get("checks", {})) != expected or not all(result["checks"].values()) or result.get("fixtureIssues"):
    raise SystemExit("The native production-class probe failed; inspect result.json and observations")
if result.get("bundleIdentifier") != "com.negentropi.RomaJustTalk.WritingTargetProbe" or Path(result.get("executablePath", "")).resolve() != executable.resolve() or result.get("processIdentifier") != int((output / "process-id.txt").read_text()):
    raise SystemExit("The observed probe identity does not match the built application")
print("PASS: four native Safari checks with production target and unchanged live helper")
PY
phase=identity
shasum -a 256 "$executable" > "$out/identity-after.txt"
cmp "$out/identity-before.txt" "$out/identity-after.txt"
codesign --verify --deep --strict "$app"
