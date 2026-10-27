#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo "Run this regression only on a disposable GitHub-hosted Mac." >&2
  exit 2
fi
if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
  echo "The regression must own the logged-in desktop session." >&2
  exit 2
fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/writing-startup-context-proof" "${1:-}" <<'PY'
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
historical_runtime_sha = "ebc92f1e60fdabbb9e26b2817f414d154865a9d5"
historical_oracle_sha = "2a76c4ca7dc7870bd48d19f3244a16ad5454c2ef41b9605df94ba5d0a89ccee3"
historical_engine_sha = "df05d81e5d2ff4a06604d5116a6bd50b4be22dcbe366731396f37abab0e0f12b"
historical = output.parent / "writing-startup-context-historical"
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
def build_arguments(checkout):
    return [
    "-project", str(checkout / "VoiceInk.xcodeproj"), "-scheme", "VoiceInk", "-configuration", "Debug",
    "-destination", "platform=macOS", "-parallel-testing-enabled", "NO",
    "-derivedDataPath", str(checkout / ".local-build"), "-xcconfig", str(checkout / "LocalBuild.xcconfig"),
    "-clonedSourcePackagesDirPath", str(derived / "SourcePackages"),
    "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
    "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=YES", "DEVELOPMENT_TEAM=",
    "CODE_SIGN_ENTITLEMENTS=" + str(checkout / "VoiceInk/VoiceInk.local.entitlements"),
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


def production_manifest(checkout=repo):
    paths = subprocess.check_output(["git", "-C", str(checkout), "ls-files", "-z", "--", *production_paths]).split(b"\0")
    return {path.decode(): digest((checkout / path.decode()).read_bytes()) for path in paths if path}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def selected_method(oracle):
    anchor = "@MainActor func " + test_name + "() async throws {"
    text = oracle.decode()
    require(text.count(anchor) == 1, "Exactly one selected startup method is required")
    start = text.index(anchor)
    opening = text.index("{", start)
    depth = 1
    for index in range(opening + 1, len(text)):
        depth += (text[index] == "{") - (text[index] == "}")
        if depth == 0:
            return text[start:index + 1].encode()
    raise RuntimeError("The selected startup method is incomplete")


def historical_sources():
    oracle = git("show", historical_runtime_sha + ":" + oracle_path)
    engine = git("show", historical_runtime_sha + ":" + engine_path)
    require(digest(oracle) == historical_oracle_sha and digest(engine) == historical_engine_sha,
            "Frozen historical runtime/oracle bytes changed")
    changed = git("diff", "--name-only", baseline_sha, historical_runtime_sha, "--", *production_paths).decode().splitlines()
    require(changed == [engine_path], "Historical products differ outside the reviewed Engine correction")
    return oracle, engine


def context_assertion_lines(oracle):
    lines = oracle.decode().splitlines()
    markers = ["Canceled writing startup must not capture clipboard context", "Canceled writing startup must not capture screen context", "Canceled ordinary startup must not capture clipboard context", "Canceled ordinary startup must not capture screen context"]
    result = []
    for marker in markers:
        matches = [i + 1 for i, line in enumerate(lines) if marker in line and "#expect(" in line]
        require(len(matches) == 1, "The four named context assertions must remain unambiguous")
        result.extend(matches)
    require(len(set(result)) == 4, "Each context assertion must have its own source location")
    return sorted(result)


def instrument_historical_engine():
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
    return instrumented.encode(), patch, {"reference_sha": baseline_sha, "original_engine_sha256": digest(old.encode()), "effective_engine_sha256": digest(instrumented.encode()), "patch_sha256": digest(patch.encode()), "added_lines": added, "removed_lines": removed, "scope": "Observe the original late Task completion only; no cancellation, guards or changed await behavior"}


def run(command, log, *, environment=None, allow_failure=False, checkout=repo):
    print("Running " + command[0] + "; log " + str(log), flush=True)
    with log.open("xb") as stream:
        process = subprocess.Popen(command, cwd=checkout, env=environment, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
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
    checkout = historical if lane == "baseline" else repo
    expected = json.loads((output / (lane + "-production.json")).read_text())
    require(production_manifest(checkout) == expected, lane + " production source bytes changed")
    current = contract()
    require(digest((checkout / oracle_path).read_bytes()) == current["oracles"][lane]["sha256"], lane + " native oracle changed")
    require(digest((checkout / lock_path).read_bytes()) == lock_sha256, "Canonical package lock changed")
    expected_sha = historical_runtime_sha if lane == "baseline" else current["candidate_source_sha"]
    actual_sha = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    require(actual_sha == expected_sha, lane + " checkout revision changed")
    if lane == "baseline":
        changed = subprocess.check_output(["git", "-C", str(checkout), "diff", "--name-only", "HEAD"], text=True).splitlines()
        require(changed == [engine_path], "Historical tracked bytes changed outside the named Engine instrumentation")
        untracked = subprocess.check_output(["git", "-C", str(checkout), "ls-files", "--others", "--exclude-standard", "-z"])
        require(not untracked, "Historical checkout contains an unexpected untracked source")


def native_environment(directory):
    return dict(os.environ, **{
        "RJT_LIVE_WRITING_TARGET_CHECKS": "1", "TEST_RUNNER_RJT_LIVE_WRITING_TARGET_CHECKS": "1",
        "TEST_RUNNER_GITHUB_ACTIONS": "true", "TEST_RUNNER_RUNNER_ENVIRONMENT": "github-hosted",
        "RJT_LIVE_WRITING_TARGET_EVIDENCE": str(directory),
        "TEST_RUNNER_RJT_LIVE_WRITING_TARGET_EVIDENCE": str(directory)
    })


def provision(directory, app):
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
    checkout = historical if lane == "baseline" else repo
    executable = checkout / ".local-build/Build/Products/Debug/roma just talk.app/Contents/MacOS/roma just talk"
    text = (directory / "tests.log").read_text(errors="replace")
    exit_code = int((directory / "test-exit.txt").read_text())
    expected = "passed" if lane == "candidate" else "failed"
    starts = re.findall(r"\bTest " + test_name + r"\(\) started\.", text)
    finishes = re.findall(r"\bTest " + test_name + r"\(\) (passed|failed) after ", text)
    summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
    errors = []
    if len(starts) != 1 or finishes != [expected] or summaries != [("1", expected)] or exit_code != (0 if lane == "candidate" else 65):
        errors.append("Exactly one executed native test and its expected result/exit are required")
    require(digest((directory / "oracle.swift").read_bytes()) == contract()["oracles"][lane]["sha256"], lane + " retained oracle changed")
    expected_failure_lines = context_assertion_lines((directory / "oracle.swift").read_bytes())
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


def identity(app=app):
    executable = app / "Contents/MacOS/roma just talk"
    signature = subprocess.run(["codesign", "-dr", "-", str(app)], text=True, capture_output=True, check=True)
    return {"executable_sha256": digest(executable.read_bytes()), "requirement": signature.stdout + signature.stderr}


def native(lane):
    directory = output / lane
    checkout = historical if lane == "baseline" else repo
    app = checkout / ".local-build/Build/Products/Debug/roma just talk.app"
    arguments = build_arguments(checkout)
    observations = directory / "observations"
    observations.mkdir()
    require_sources(lane)
    provision(directory, app)
    environment = native_environment(observations)
    selection = directory / "selection"
    selection.mkdir()
    run(["xcodebuild", "test-without-building", *arguments, selector, "-enumerate-tests", "-test-enumeration-style", "flat", "-test-enumeration-format", "json", "-test-enumeration-output-path", str(selection / "selected-tests.json")], selection / "enumeration.log", environment=environment, checkout=checkout)
    enumeration = json.loads((selection / "selected-tests.json").read_text())
    enabled = [test["identifier"] for plan in enumeration.get("values", []) for test in plan.get("enabledTests", [])]
    disabled = [test.get("identifier") for plan in enumeration.get("values", []) for test in plan.get("disabledTests", [])]
    expected = selector.removeprefix("-only-testing:")
    valid = not enumeration.get("errors") and enabled == [expected] and expected not in disabled
    write_json(selection / "receipt.json", {"valid": valid, "requested": expected, "enabled": enabled, "disabled": disabled})
    require(valid, "The exact enabled native test did not resolve")
    write_json(directory / "identity-before.json", identity(app))
    result = run(["xcodebuild", "test-without-building", *arguments, selector, "-resultBundlePath", str(directory / "Native.xcresult")], directory / "tests.log", environment=environment, allow_failure=True, checkout=checkout)
    (directory / "test-exit.txt").write_text(str(result) + "\n")
    write_json(directory / "identity-after.json", identity(app))
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    require_sources(lane)
    write_json(output / (lane + "-production-after.json"), production_manifest(checkout))
    validate_lane(lane)


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)

try:
    if mode == "self-test":
        old_oracle, _ = historical_sources()
        current_oracle = git("show", "HEAD:" + oracle_path)
        require(selected_method(old_oracle) == selected_method(current_oracle), "Current and historical selected test orchestration differs")
        for value in [old_oracle, current_oracle]:
            require(len(context_assertion_lines(value)) == 4, "Each lane must use its own four assertion sites")
        instrumented, _, receipt = instrument_historical_engine()
        require(digest(instrumented) == receipt["effective_engine_sha256"], "Historical instrumentation receipt differs")
        require(b"target.replace(" in old_oracle, "The frozen historical oracle no longer exercises its native API")
        print("PASS: historical source/oracle pins, identical selected method and observation-only instrumentation; no native execution")
    elif mode == "prepare":
        output.mkdir(exist_ok=False)
        for lane in ["candidate", "baseline"]:
            (output / lane).mkdir()
        subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "origin", baseline_sha], check=True)
        subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "origin", historical_runtime_sha], check=True)
        candidate_sha = git("rev-parse", "HEAD").decode().strip()
        subprocess.run(["git", "-C", str(repo), "diff", "--quiet", "HEAD", "--", *production_paths, oracle_path], check=True)
        changed = git("diff", "--name-only", historical_runtime_sha, "HEAD", "--", *production_paths).decode().splitlines()
        oracle = (repo / oracle_path).read_bytes()
        old_oracle, old_engine = historical_sources()
        require(selected_method(oracle) == selected_method(old_oracle), "The selected current and historical test orchestration must remain identical")
        require(digest((repo / lock_path).read_bytes()) == lock_sha256, "The reviewed package lock changed")
        require(not historical.exists(), "Historical runtime path already exists; refusing to reuse another checkout")
        subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(historical), historical_runtime_sha], check=True)
        subprocess.run(["git", "-C", str(historical), "diff", "--quiet", "HEAD"], check=True)
        require((historical / oracle_path).read_bytes() == old_oracle, "Historical checkout does not contain its exact frozen oracle")
        require(digest((historical / lock_path).read_bytes()) == lock_sha256, "Historical canonical package lock differs")
        (output / "historical-engine.swift").write_bytes(old_engine)
        (output / "candidate/oracle.swift").write_bytes(oracle)
        (output / "baseline/oracle.swift").write_bytes(old_oracle)
        write_json(output / "candidate-production.json", production_manifest())
        write_json(output / "historical-production.json", production_manifest(historical))
        write_json(output / "contract.json", {"schema_version": 2, "driver_sha": candidate_sha, "candidate_source_sha": candidate_sha, "historical_runtime_sha": historical_runtime_sha, "baseline_reference_sha": baseline_sha, "candidate_engine_sha256": digest((repo / engine_path).read_bytes()), "oracles": {"candidate": {"path": oracle_path, "source_sha": candidate_sha, "sha256": digest(oracle)}, "baseline": {"path": oracle_path, "source_sha": historical_runtime_sha, "sha256": digest(old_oracle)}}, "selected_method_sha256": digest(selected_method(oracle)), "canonical_lock_sha256": lock_sha256, "intervening_production_paths": changed, "scope": "Current full Mac units and native startup acceptance, plus a separately frozen historical red control. Historical runtime changes only Engine to the original baseline plus observation-only task handle. Shared selected orchestration and observed cases/counts; different whole oracles and intervening product changes. No guard-only causal comparison, provider, model-weight, real context read or physical-key proof"})
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
        require(production_manifest(historical) == json.loads((output / "historical-production.json").read_text()), "Historical runtime changed before instrumentation")
        subprocess.run(["git", "-C", str(historical), "diff", "--quiet", "HEAD"], check=True)
        instrumented, patch, receipt = instrument_historical_engine()
        (output / "baseline/engine-instrumentation.patch").write_text(patch)
        write_json(output / "baseline/engine-instrumentation.json", receipt)
        try:
            (historical / engine_path).write_bytes(instrumented)
            expected = json.loads((output / "historical-production.json").read_text())
            expected[engine_path] = digest(instrumented)
            write_json(output / "baseline-production.json", expected)
            require_sources("baseline")
            run(["xcodebuild", "build-for-testing", *build_arguments(historical), "-only-testing:VoiceInkTests"], output / "baseline/build.log", checkout=historical)
            require_sources("baseline")
            build_log = (output / "baseline/build.log").read_text(errors="replace")
            require(re.search(r"(?:SwiftCompile|CompileSwiftSources)[^\n]*VoiceInkEngine\.swift", build_log) is not None, "The historical build did not record Engine compilation")
            candidate_identity = json.loads((output / "candidate/identity-before.json").read_text())
            require(identity(historical / ".local-build/Build/Products/Debug/roma just talk.app")["executable_sha256"] != candidate_identity["executable_sha256"], "Historical and current executable bytes unexpectedly match")
            native("baseline")
        finally:
            (historical / engine_path).write_bytes((output / "historical-engine.swift").read_bytes())
            restored = production_manifest(historical) == json.loads((output / "historical-production.json").read_text())
            current_unchanged = production_manifest() == json.loads((output / "candidate-production.json").read_text())
            write_json(output / "baseline/source-restoration.json", {"historical_sources_restored": restored, "current_sources_unchanged": current_unchanged})
            require(restored and current_unchanged, "Historical restoration or current source fidelity failed")
    elif mode == "verify":
        require_sources("candidate")
        require(json.loads((output / "candidate/archive-identity.json").read_text()) == json.loads((output / "candidate/identity-before.json").read_text()), "The archived candidate differs from the native test host")
        require((output / "candidate/tested-app.tar.gz").stat().st_size > 0, "The exact candidate app archive is missing")
        for lane in ["candidate", "baseline"]:
            validate_lane(lane)
            require(json.loads((output / (lane + "-production.json")).read_text()) == json.loads((output / (lane + "-production-after.json")).read_text()), lane + " source manifests differ before and after native testing")
        restoration = json.loads((output / "baseline/source-restoration.json").read_text())
        require(restoration == {"historical_sources_restored": True, "current_sources_unchanged": True}, "Historical/current source fidelity receipt is missing")
        require(production_manifest(historical) == json.loads((output / "historical-production.json").read_text()), "Restored historical source changed")
        write_json(output / "result.json", {"classification": "current-native-pass-with-historical-red-control", **contract(), "candidate": json.loads((output / "candidate/result.json").read_text()), "historical_control": json.loads((output / "baseline/result.json").read_text()), "full_candidate_units": json.loads((output / "candidate/unit-result.json").read_text())})
    else:
        raise RuntimeError("Use prepare, units, candidate, baseline, verify, or self-test")
except BaseException as error:
    if output.is_dir():
        write_json(output / ("failure-" + mode + ".json"), {"classification": "invalid-or-failed", "phase": mode, "error": str(error)})
    raise
PY
