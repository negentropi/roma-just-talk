#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo "Run this regression only on a disposable GitHub-hosted Mac." >&2
  exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
  echo "The regression must own the logged-in desktop session." >&2
  exit 2
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "$RUNNER_TEMP/writing-startup-context-proof" "${1:-}" <<'PY'
import difflib
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
baseline_sha = "b1161b7debb720afd41f3216b7aa85924944ae17"
engine_path = "VoiceInk/Transcription/Engine/VoiceInkEngine.swift"
oracle_path = "VoiceInkTests/WritingTargetLiveTests.swift"
lock_path = "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
lock_sha256 = "bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f"
test_name = "liveWritingStartupContextRespectsOwnerAfterCancellation"
selector = "-only-testing:VoiceInkTests/VoiceInkTests/" + test_name + "()"
production_paths = ["VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "iOS"]
derived = repo / ".local-build"
app = derived / "Build/Products/Debug/roma just talk.app"
executable = app / "Contents/MacOS/roma just talk"
arguments = [
    "-project", str(repo / "VoiceInk.xcodeproj"), "-scheme", "VoiceInk", "-configuration", "Debug",
    "-destination", "platform=macOS", "-parallel-testing-enabled", "NO",
    "-derivedDataPath", str(derived), "-xcconfig", str(repo / "LocalBuild.xcconfig"),
    "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
    "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=YES", "DEVELOPMENT_TEAM=",
    "CODE_SIGN_ENTITLEMENTS=" + str(repo / "VoiceInk/VoiceInk.local.entitlements"),
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD"
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    data = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if path.exists():
        require(path.read_text() == data, "Existing evidence differs: " + str(path))
    else:
        with path.open("x") as stream:
            stream.write(data)


def git(*args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def production_manifest():
    paths = git("ls-files", "-z", "--", *production_paths).split(b"\0")
    return {path.decode(): digest((repo / path.decode()).read_bytes()) for path in paths if path}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(command, log, *, environment=None, allow_failure=False):
    print("Running " + command[0] + "; log " + str(log), flush=True)
    with log.open("xb") as stream:
        process = subprocess.Popen(command, cwd=repo, env=environment, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            exit_code = process.wait()
        except BaseException:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
    if exit_code and not allow_failure:
        print("\n".join(log.read_text(errors="replace").splitlines()[-80:]), file=sys.stderr)
        raise RuntimeError("Command failed with exit " + str(exit_code) + "; inspect " + str(log))
    return exit_code


def contract():
    return json.loads((output / "contract.json").read_text())


def require_sources(lane):
    expected = json.loads((output / (lane + "-production.json")).read_text())
    require(production_manifest() == expected, lane + " production source bytes changed")
    current = contract()
    require(digest((repo / oracle_path).read_bytes()) == current["oracle_sha256"], "The common native oracle changed")
    require(digest((repo / lock_path).read_bytes()) == lock_sha256, "Canonical package lock changed")


def native_environment(directory):
    return dict(os.environ, **{
        "RJT_LIVE_WRITING_TARGET_CHECKS": "1", "TEST_RUNNER_RJT_LIVE_WRITING_TARGET_CHECKS": "1",
        "TEST_RUNNER_GITHUB_ACTIONS": "true", "TEST_RUNNER_RUNNER_ENVIRONMENT": "github-hosted",
        "RJT_LIVE_WRITING_TARGET_EVIDENCE": str(directory),
        "TEST_RUNNER_RJT_LIVE_WRITING_TARGET_EVIDENCE": str(directory)
    })


def provision(directory):
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    info = subprocess.check_output(["plutil", "-extract", "CFBundleIdentifier", "raw", "-o", "-", str(app / "Contents/Info.plist")], text=True).strip()
    require(info == "com.negentropi.RomaJustTalk", "Unexpected test-host bundle identity")
    identity = subprocess.run(["codesign", "-dr", "-", str(app)], text=True, capture_output=True, check=True)
    matches = re.findall(r"^(?:# )?designated => (.+)$", identity.stdout + identity.stderr, re.M)
    require(len(matches) == 1, "Exact app signing requirement is unavailable")
    requirement = directory / "host-requirement.txt"
    requirement.write_text(matches[0] + "\n")
    csreq = directory / "host.csreq"
    subprocess.run(["csreq", "-r", str(requirement), "-b", str(csreq)], check=True)
    requirement_hex = csreq.read_bytes().hex().upper()
    rows = []
    for service, database, prefix in [
        ("kTCCServiceAccessibility", Path("/Library/Application Support/com.apple.TCC/TCC.db"), ["sudo"]),
        ("kTCCServiceMicrophone", Path.home() / "Library/Application Support/com.apple.TCC/TCC.db", [])
    ]:
        statement = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('" + service + "','com.negentropi.RomaJustTalk',0,2,4,1,X'" + requirement_hex + "',0,'UNUSED',0);"
        subprocess.run([*prefix, "sqlite3", str(database)], input=statement, text=True, check=True)
        query = "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='" + service + "';"
        rows.extend(json.loads(subprocess.check_output([*prefix, "sqlite3", "-json", str(database), query])))
    require(len(rows) == 2 and {row["service"] for row in rows} == {"kTCCServiceAccessibility", "kTCCServiceMicrophone"} and all(row["auth_value"] == 2 and row["requirement"] == requirement_hex for row in rows), "Fresh TCC rows do not match the exact signed test host")
    write_json(directory / "tcc.json", rows)
    for command in [["killall", "tccd"], ["sudo", "killall", "tccd"]]:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sleep", "2"], check=True)


def validate_lane(lane):
    directory = output / lane
    text = (directory / "tests.log").read_text(errors="replace")
    exit_code = int((directory / "test-exit.txt").read_text())
    expected = "passed" if lane == "candidate" else "failed"
    starts = re.findall(r"\bTest " + test_name + r"\(\) started\.", text)
    finishes = re.findall(r"\bTest " + test_name + r"\(\) (passed|failed) after ", text)
    summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
    errors = []
    if len(starts) != 1 or finishes != [expected] or summaries != [("1", expected)] or exit_code != (0 if lane == "candidate" else 65):
        errors.append("Exactly one executed native test and its expected result/exit are required")
    oracle_lines = (repo / oracle_path).read_text().splitlines()
    markers = ["Canceled writing startup must not capture clipboard context", "Canceled writing startup must not capture screen context", "Canceled ordinary startup must not capture clipboard context", "Canceled ordinary startup must not capture screen context"]
    expected_failure_lines = []
    for marker in markers:
        matches = [i + 1 for i, line in enumerate(oracle_lines) if marker in line and "#expect(" in line]
        require(len(matches) == 1, "The four named context assertions must remain unambiguous")
        expected_failure_lines.extend(matches)
    issues = re.findall(r"^.*\brecorded an issue\b[^\n]*", text, re.M)
    locations = [re.search(r"recorded an issue at (.+):(\d+):\d+:", issue) for issue in issues]
    failures = [int(location[2]) for location in locations if location and Path(location[1]).name == Path(oracle_path).name]
    expected_failures = sorted(expected_failure_lines) if lane == "baseline" else []
    if len(issues) != len(expected_failures) or sorted(failures) != expected_failures:
        errors.append("Native issues did not exclusively identify the four canceled-startup context reads")
    observed_path = directory / "observations/startup-context-ownership.json"
    observed = json.loads(observed_path.read_text()) if observed_path.is_file() else {}
    if observed.get("checkpoint") != "startup-context-ownership" or type(observed.get("version")) is not int or observed.get("version") != 2 or observed.get("test") != test_name or observed.get("noSetupFailure") is not True or "error" not in observed or observed.get("error") is not None:
        errors.append("Actual startup observation is missing or setup failed")
    if observed.get("bundleIdentifier") != "com.negentropi.RomaJustTalk" or observed.get("executablePath") != str(executable) or type(observed.get("processIdentifier")) is not int or observed.get("processIdentifier", 0) <= 0:
        errors.append("Observed test-host identity differs from the built app")
    cases = observed.get("cases", {})
    if set(cases) != {"canceled-writing", "canceled-ordinary", "active-ordinary"}:
        errors.append("All three real startup cases must complete exactly once")
    for label, value in cases.items():
        if any(value.get(key) is not True for key in ["gateEntered", "taskCompleted", "ownerEnded", "recordingCanceled", "actualAudioFileCreated"]) or type(value.get("modelLoadCalls")) is not int or value.get("modelLoadCalls") != 1:
            errors.append(label + " did not complete the real gated model-load and recording lifecycle")
        canceled = label != "active-ordinary"
        count = 0 if canceled and lane == "candidate" else 1
        states = [] if count == 0 else [not canceled, not canceled]
        observed_states = value.get("captureStatesWereRecording")
        if any(type(value.get(key)) is not int or value.get(key) != count for key in ["clipboardReads", "screenReads"]) or not isinstance(observed_states, list) or any(type(state) is not bool for state in observed_states) or observed_states != states or value.get("wasRecordingAtTaskCompletion") is not (not canceled):
            errors.append(label + " did not observe the exact context reads at the required recording state")
        if canceled and value.get("taskDetachedOnCancellation") is not (lane == "candidate"):
            errors.append(label + " task ownership was not observed as expected")
    if not (directory / "identity-after.json").is_file() or json.loads((directory / "identity-before.json").read_text()) != json.loads((directory / "identity-after.json").read_text()):
        errors.append("App binary or signature changed during native execution")
    receipt = {"valid": not errors, "errors": errors, "exit_code": exit_code, "test": test_name, "starts": len(starts), "results": finishes, "summary": summaries, "issues": issues, "failure_lines": failures, "observed": observed}
    write_json(directory / "result.json", receipt)
    require(not errors, lane + " did not satisfy the matched native contract: " + "; ".join(errors))


def identity():
    signature = subprocess.run(["codesign", "-dr", "-", str(app)], text=True, capture_output=True, check=True)
    return {"executable_sha256": digest(executable.read_bytes()), "requirement": signature.stdout + signature.stderr}


def native(lane):
    directory = output / lane
    observations = directory / "observations"
    observations.mkdir()
    require_sources(lane)
    provision(directory)
    environment = native_environment(observations)
    selection = directory / "selection"
    selection.mkdir()
    run(["xcodebuild", "test-without-building", *arguments, selector, "-enumerate-tests", "-test-enumeration-style", "flat", "-test-enumeration-format", "json", "-test-enumeration-output-path", str(selection / "selected-tests.json")], selection / "enumeration.log", environment=environment)
    enumeration = json.loads((selection / "selected-tests.json").read_text())
    enabled = [test["identifier"] for plan in enumeration.get("values", []) for test in plan.get("enabledTests", [])]
    disabled = [test.get("identifier") for plan in enumeration.get("values", []) for test in plan.get("disabledTests", [])]
    expected = selector.removeprefix("-only-testing:")
    valid = not enumeration.get("errors") and enabled == [expected] and expected not in disabled
    write_json(selection / "receipt.json", {"valid": valid, "requested": expected, "enabled": enabled, "disabled": disabled})
    require(valid, "The exact enabled native test did not resolve")
    write_json(directory / "identity-before.json", identity())
    result = run(["xcodebuild", "test-without-building", *arguments, selector, "-resultBundlePath", str(directory / "Native.xcresult")], directory / "tests.log", environment=environment, allow_failure=True)
    (directory / "test-exit.txt").write_text(str(result) + "\n")
    write_json(directory / "identity-after.json", identity())
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    require_sources(lane)
    write_json(output / (lane + "-production-after.json"), production_manifest())
    validate_lane(lane)


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)

try:
    if mode == "prepare":
        output.mkdir(exist_ok=False)
        for lane in ["candidate", "baseline"]:
            (output / lane).mkdir()
        subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "origin", baseline_sha], check=True)
        candidate_sha = git("rev-parse", "HEAD").decode().strip()
        subprocess.run(["git", "-C", str(repo), "diff", "--quiet", "HEAD", "--", *production_paths, oracle_path], check=True)
        changed = git("diff", "--name-only", baseline_sha, "HEAD", "--", *production_paths).decode().splitlines()
        require(changed == [engine_path], "The matched products differ outside the Engine ownership correction")
        oracle = (repo / oracle_path).read_bytes()
        require(test_name.encode() in oracle, "The common real-engine oracle is missing")
        marker = b"private enum LiveWritingFailure:"
        require(oracle.count(marker) == 1, "The shared native helper boundary changed")
        require(digest((repo / lock_path).read_bytes()) == lock_sha256, "The reviewed package lock changed")
        (output / "candidate-engine.swift").write_bytes((repo / engine_path).read_bytes())
        (output / "common-oracle.swift").write_bytes(oracle)
        write_json(output / "candidate-production.json", production_manifest())
        write_json(output / "contract.json", {"driver_sha": candidate_sha, "candidate_source_sha": candidate_sha, "baseline_reference_sha": baseline_sha, "candidate_engine_sha256": digest((repo / engine_path).read_bytes()), "oracle_path": oracle_path, "oracle_sha256": digest(oracle), "shared_native_helper_sha256": digest(oracle[oracle.index(marker):]), "canonical_lock_sha256": lock_sha256, "changed_production_paths": changed, "scope": "Real native engine/recorder with one shared oracle; baseline adds only a task handle for observing completion; no provider, model-weight, real context read or physical-key proof"})
        run(["bash", "scripts/run-writing-feature-regression.sh", "packages", str(output / "packages")], output / "package-contract.log")
    elif mode == "units":
        require_sources("candidate")
        run(["defaults", "write", "com.negentropi.RomaJustTalk", "CurrentTranscriptionModel", "-string", "whisper-large-v3-turbo"], output / "candidate/default-model.log")
        run(["defaults", "write", "com.negentropi.RomaJustTalk", "PrewarmModelOnWake", "-bool", "false"], output / "candidate/default-prewarm.log")
        run(["bash", "scripts/run-macos-ci-unit-tests.sh"], output / "candidate/units.log")
        require_sources("candidate")
        text = (output / "candidate/units.log").read_text(errors="replace")
        summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
        require(len(summaries) == 1 and int(summaries[0][0]) > 0 and summaries[0][1] == "passed", "The full Mac unit gate did not execute a passing Swift Testing suite")
        names = re.findall(r"@Test\s+func\s+(\w+)\(", (repo / "VoiceInkTests/CapturedWritingPasteTests.swift").read_text())
        require(len(names) == 17 and all(len(re.findall(r"\bTest " + name + r"\(\) passed after ", text)) == 1 for name in names), "Full units did not execute all seventeen captured-paste cases")
        write_json(output / "candidate/unit-result.json", {"valid": True, "exit_code": 0, "swift_testing_summary": summaries, "captured_paste_cases": names, "scope": "Existing full Mac unit runner, not just the new filtered native case"})
    elif mode == "candidate":
        require(json.loads((output / "candidate/unit-result.json").read_text())["valid"] is True, "Full candidate units must pass first")
        write_json(output / "candidate/archive-identity.json", identity())
        run(["tar", "-czf", str(output / "candidate/tested-app.tar.gz"), "-C", str(app.parent), app.name], output / "candidate/archive.log")
        native("candidate")
        require(json.loads((output / "candidate/archive-identity.json").read_text()) == json.loads((output / "candidate/identity-before.json").read_text()), "The archived candidate differs from the native test host")
    elif mode == "baseline":
        require_sources("candidate")
        old = git("show", baseline_sha + ":" + engine_path).decode()
        property_anchor = "    private var activeRecordingStartID: UUID?\n"
        task_anchor = "                            Task { @MainActor [weak self] in\n                                guard let self else { return }\n\n                                if let model = self.transcriptionModelManager.currentTranscriptionModel {"
        property_line = "    private(set) var recordingStartupTask: Task<Void, Never>?\n"
        require(old.count(property_anchor) == 1 and old.count(task_anchor) == 1, "Pinned baseline task observation anchors changed")
        instrumented = old.replace(property_anchor, property_anchor + property_line).replace(task_anchor, task_anchor.replace("Task {", "recordingStartupTask = Task {", 1))
        patch = "".join(difflib.unified_diff(old.splitlines(keepends=True), instrumented.splitlines(keepends=True), fromfile="a/" + engine_path, tofile="b/" + engine_path))
        added = [line[1:] for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++")]
        removed = [line[1:] for line in patch.splitlines() if line.startswith("-") and not line.startswith("---")]
        require(added == [property_line.rstrip("\n"), "                            recordingStartupTask = Task { @MainActor [weak self] in"] and removed == ["                            Task { @MainActor [weak self] in"], "Baseline instrumentation exceeded the observation-only property and assignment")
        (output / "baseline/engine-instrumentation.patch").write_text(patch)
        write_json(output / "baseline/engine-instrumentation.json", {"reference_sha": baseline_sha, "original_engine_sha256": digest(old.encode()), "effective_engine_sha256": digest(instrumented.encode()), "patch_sha256": digest(patch.encode()), "added_lines": added, "removed_lines": removed, "scope": "Observe the original late Task completion only; no cancellation, guards or changed await behavior"})
        try:
            (repo / engine_path).write_text(instrumented)
            expected = json.loads((output / "candidate-production.json").read_text())
            expected[engine_path] = digest(instrumented.encode())
            write_json(output / "baseline-production.json", expected)
            require_sources("baseline")
            run(["xcodebuild", "build-for-testing", *arguments, "-only-testing:VoiceInkTests"], output / "baseline/build.log")
            require_sources("baseline")
            build_log = (output / "baseline/build.log").read_text(errors="replace")
            require(re.search(r"(?:SwiftCompile|CompileSwiftSources)[^\n]*VoiceInkEngine\.swift", build_log) is not None, "The incremental build did not record Engine compilation")
            candidate_identity = json.loads((output / "candidate/identity-before.json").read_text())
            require(identity()["executable_sha256"] != candidate_identity["executable_sha256"], "The baseline build did not change the candidate executable")
            native("baseline")
        finally:
            (repo / engine_path).write_bytes((output / "candidate-engine.swift").read_bytes())
            restored = production_manifest() == json.loads((output / "candidate-production.json").read_text())
            write_json(output / "baseline/source-restoration.json", {"candidate_sources_restored": restored})
            require(restored, "Candidate source restoration did not match its original manifest")
    elif mode == "verify":
        require_sources("candidate")
        require(json.loads((output / "candidate/archive-identity.json").read_text()) == json.loads((output / "candidate/identity-before.json").read_text()), "The archived candidate differs from the native test host")
        require((output / "candidate/tested-app.tar.gz").stat().st_size > 0, "The exact candidate app archive is missing")
        for lane in ["candidate", "baseline"]:
            validate_lane(lane)
            require(json.loads((output / (lane + "-production.json")).read_text()) == json.loads((output / (lane + "-production-after.json")).read_text()), lane + " source manifests differ before and after native testing")
        require(json.loads((output / "baseline/source-restoration.json").read_text())["candidate_sources_restored"] is True, "Candidate source restoration receipt is missing")
        write_json(output / "result.json", {"classification": "matched-red-green", **contract(), "candidate": json.loads((output / "candidate/result.json").read_text()), "baseline": json.loads((output / "baseline/result.json").read_text()), "full_candidate_units": json.loads((output / "candidate/unit-result.json").read_text())})
    else:
        raise RuntimeError("Use prepare, units, candidate, baseline, or verify")
except BaseException as error:
    if output.is_dir():
        write_json(output / ("failure-" + mode + ".json"), {"classification": "invalid-or-failed", "phase": mode, "error": str(error)})
    raise
PY
