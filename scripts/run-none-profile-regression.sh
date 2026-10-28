#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run this comparison only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
    echo "The comparison must own the logged-in desktop session." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/none-profile-proof" "${1:-}" <<'PY'
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import uuid
import wave
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
baseline_sha = "ebc92f1e60fdabbb9e26b2817f414d154865a9d5"
oracle_path = "VoiceInkTests/DictationProfilePipelineTests.swift"
import_oracle_path = "VoiceInkTests/DictationProfileImportLiveTests.swift"
import_test_name = "liveNoneProfileImportQueueUsesRealWhisperRecognition"
lock_path = "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
lock_sha = "bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f"
production_paths = ["VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "iOS", "VoiceInkTests"]
baseline = output.parent / "none-profile-baseline"
package_checkouts = repo / ".local-build/SourcePackages"
cases = {
    "dictationNonePreservesSnippetTriggersAndReplacementWordsLiterally": [
        "None snippet-trigger dictation must deliver exact UTF-8 recognition text.",
        "None snippet-trigger dictation must deliver exact UTF-16 recognition text.",
        "None snippet-trigger dictation must not store an expanded result.",
        "Saved None snippet-trigger dictation must not store an expanded result."
    ],
    "dictationNoneDoesNotActivatePromptTriggersOrAI": [
        "None prompt-trigger dictation must deliver exact UTF-8 recognition text.",
        "None prompt-trigger dictation must deliver exact UTF-16 recognition text.",
        "None prompt-trigger dictation must save exact recognition text.",
        "None prompt-trigger dictation must not store AI output.",
        "None prompt-trigger dictation must not analyze prompt triggers.",
        "None prompt-trigger dictation must not request AI output."
    ],
    "dictationCustomRetainsItsExistingCleanupPath": [],
    "canceledQueuedDictationPasteDoesNotWriteTheTarget": [
        "A canceled queued dictation paste must return commandNotPosted.",
        "A canceled queued dictation paste must not call the target inserter."
    ]
}
selectors = ["-only-testing:VoiceInkTests/VoiceInkTests/" + name + "()" for name in cases]


class InvalidFixture(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    data = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if path.exists():
        require(path.read_text() == data, "Existing evidence differs: " + str(path))
    else:
        path.write_text(data)


def git(checkout, *arguments):
    return subprocess.check_output(["git", "-C", str(checkout), *arguments])


def manifest(checkout):
    paths = git(checkout, "ls-files", "-z", "--", *production_paths).split(b"\0")
    return {path.decode(): digest((checkout / path.decode()).read_bytes()) for path in paths if path}


def declarations(checkout):
    paths = git(checkout, "ls-files", "-z").split(b"\0")
    return {path.decode(): digest((checkout / path.decode()).read_bytes()) for path in paths if path and (path.endswith(b"/Package.swift") or path in (b"Package.swift", b"VoiceInk.xcodeproj/project.pbxproj", b"LocalBuild.xcconfig"))}


def run(command, log, checkout=repo, allow_failure=False, environment=None):
    print("Running " + command[0] + "; log " + str(log), flush=True)
    with log.open("xb") as stream:
        process = subprocess.Popen(command, cwd=checkout, env=environment, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait()
        except BaseException:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
    if code and not allow_failure:
        print("\n".join(log.read_text(errors="replace").splitlines()[-80:]), file=sys.stderr)
        raise RuntimeError("Command failed with exit " + str(code) + "; inspect " + str(log))
    return code


def failure_sites(source):
    lines = source.splitlines()
    sites = {}
    for name, labels in cases.items():
        require(len(re.findall(r"\bfunc " + name + r"\(\)", source)) == 1, "The shared test is missing or duplicated: " + name)
        for label in labels:
            matches = [i + 1 for i, line in enumerate(lines) if "#expect(" in line and json.dumps(label) in line]
            require(len(matches) == 1, "The named failure assertion is missing or duplicated: " + label)
            sites[matches[0]] = {"test": name, "message": label}
    require(len(sites) == sum(map(len, cases.values())), "Each named assertion requires a distinct source location")
    return sites


def classify(text, exit_code, lane, sites, selected_cases=cases):
    expected = {name: "failed" if lane == "baseline" and labels else "passed" for name, labels in selected_cases.items()}
    observations = {}
    errors = []
    for name in selected_cases:
        starts = re.findall(r"\bTest " + re.escape(name) + r"\(\) started\.", text)
        results = re.findall(r"\bTest " + re.escape(name) + r"\(\) (passed|failed|skipped) after ", text)
        observations[name] = {"starts": len(starts), "results": results}
        if len(starts) != 1 or results != [expected[name]]:
            errors.append(name + " did not execute exactly once with its expected result")
    all_starts = re.findall(r"\bTest (\w+)\(\) started\.", text)
    if sorted(all_starts) != sorted(selected_cases):
        errors.append("Unexpected or missing test starts")
    expected_summary = "failed" if lane == "baseline" else "passed"
    summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
    if summaries != [(str(len(selected_cases)), expected_summary)] or exit_code != (65 if lane == "baseline" else 0):
        errors.append("The exact test count, summary and exit code are required")
    issues = re.findall(r"^.*\brecorded an issue\b[^\n]*", text, re.M)
    locations = [re.search(r"\bTest (\w+)\(\) recorded an issue at (.+):(\d+):\d+:.*Expectation failed:", issue) for issue in issues]
    observed_lines = [int(value[3]) for value in locations if value and Path(value[2]).name == Path(oracle_path).name and sites.get(int(value[3]), {}).get("test") == value[1]]
    expected_lines = sorted(sites) if lane == "baseline" else []
    if len(issues) != len(expected_lines) or sorted(observed_lines) != expected_lines:
        errors.append("Issues must exclusively identify the named None and cancellation assertions")
    return {"valid": not errors, "errors": errors, "lane": lane, "exit_code": exit_code, "tests": observations, "summary": [list(value) for value in summaries], "issues": issues, "failure_lines": observed_lines}


def contract():
    return json.loads((output / "contract.json").read_text())


def verify_sources(lane):
    checkout = baseline if lane == "baseline" else repo
    value = contract()
    expected_sha = value["baseline_reference_sha"] if lane == "baseline" else value["candidate_source_sha"]
    require(git(checkout, "rev-parse", "HEAD").decode().strip() == expected_sha, "The pinned checkout revision changed")
    untracked = {path.decode() for path in git(checkout, "ls-files", "--others", "--exclude-standard", "-z", "--", *production_paths).split(b"\0") if path}
    require(untracked == ({oracle_path} if lane == "baseline" else set()), "Unexpected untracked product/test sources exist")
    require(all(digest((repo / path).read_bytes()) == expected for path, expected in value["verification_helper_sha256"].items()), "Verification helper bytes changed")
    require(manifest(checkout) == json.loads((output / (lane + "-production.json")).read_text()), lane + " production bytes changed")
    require(digest((checkout / oracle_path).read_bytes()) == value["oracle_sha256"], "The unchanged shared oracle differs")
    require(digest((checkout / lock_path).read_bytes()) == lock_sha, "Canonical package lock changed")
    require(declarations(checkout) == value["declarations"], "Dependency or build declarations changed")


def build_arguments(lane):
    checkout = baseline if lane == "baseline" else repo
    derived = output.parent / ("none-profile-derived-" + lane)
    arguments = [
        "-project", str(checkout / "VoiceInk.xcodeproj"), "-scheme", "VoiceInk", "-configuration", "Debug",
        "-destination", "platform=macOS", "-parallel-testing-enabled", "NO",
        "-derivedDataPath", str(derived), "-xcconfig", str(checkout / "LocalBuild.xcconfig"),
        "-clonedSourcePackagesDirPath", str(package_checkouts),
        "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
        "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=YES", "DEVELOPMENT_TEAM=",
        "CODE_SIGN_ENTITLEMENTS=" + str(checkout / "VoiceInk/VoiceInk.local.entitlements"),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD"
    ]
    return checkout, derived, arguments


def identity(derived):
    products = derived / "Build/Products/Debug"
    app = products / "roma just talk.app"
    require(subprocess.check_output(["plutil", "-extract", "CFBundleIdentifier", "raw", "-o", "-", str(app / "Contents/Info.plist")], text=True).strip() == "com.negentropi.RomaJustTalk", "Unexpected test-host identity")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    signing = subprocess.run(["codesign", "-dr", "-", str(app)], capture_output=True, text=True, check=True)
    matches = re.findall(r"^(?:# )?designated => (.+)$", signing.stdout + signing.stderr, re.M)
    require(len(matches) == 1, "The exact signed host requirement is unavailable")
    bundles = sorted(products.rglob("VoiceInkTests.xctest"))
    require(bool(bundles), "The built unit-test bundle is missing")
    tests = {}
    for bundle in bundles:
        name = subprocess.check_output(["plutil", "-extract", "CFBundleExecutable", "raw", "-o", "-", str(bundle / "Contents/Info.plist")], text=True).strip()
        tests[str(bundle.relative_to(products))] = digest((bundle / "Contents/MacOS" / name).read_bytes())
    return {"app_path": str(app), "executable_sha256": digest((app / "Contents/MacOS/roma just talk").read_bytes()), "designated_requirement": matches[0], "test_bundle_sha256": tests}


def provision(directory, derived):
    value = identity(derived)
    requirement = directory / "host-requirement.txt"
    requirement.write_text(value["designated_requirement"] + "\n")
    csreq = directory / "host.csreq"
    subprocess.run(["csreq", "-r", str(requirement), "-b", str(csreq)], check=True)
    requirement_hex = csreq.read_bytes().hex().upper()
    rows = []
    for service, database, prefix in [
        ("kTCCServiceAccessibility", "/Library/Application Support/com.apple.TCC/TCC.db", ["sudo"]),
        ("kTCCServiceMicrophone", str(Path.home() / "Library/Application Support/com.apple.TCC/TCC.db"), [])
    ]:
        statement = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('" + service + "','com.negentropi.RomaJustTalk',0,2,4,1,X'" + requirement_hex + "',0,'UNUSED',0);"
        subprocess.run([*prefix, "sqlite3", database], input=statement, text=True, check=True)
        query = "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='com.negentropi.RomaJustTalk' AND service='" + service + "';"
        rows.extend(json.loads(subprocess.check_output([*prefix, "sqlite3", "-json", database, query])))
    require(len(rows) == 2 and {row["service"] for row in rows} == {"kTCCServiceAccessibility", "kTCCServiceMicrophone"} and all(row["auth_value"] == 2 and row["requirement"] == requirement_hex for row in rows), "Fresh TCC rows do not match the signed host")
    write_json(directory / "tcc.json", rows)
    for command in [["killall", "tccd"], ["sudo", "killall", "tccd"]]:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sleep", "2"], check=True)
    return value


def enumerate_tests(directory, checkout, arguments, selected, environment=None):
    selection = directory / "selection"
    selection.mkdir()
    run(["xcodebuild", "test-without-building", *arguments, *selected, "-enumerate-tests", "-test-enumeration-style", "flat", "-test-enumeration-format", "json", "-test-enumeration-output-path", str(selection / "selected-tests.json")], selection / "enumeration.log", checkout, environment=environment)
    enumeration = json.loads((selection / "selected-tests.json").read_text())
    enabled = [test["identifier"] for plan in enumeration.get("values", []) for test in plan.get("enabledTests", [])]
    disabled = [test.get("identifier") for plan in enumeration.get("values", []) for test in plan.get("disabledTests", [])]
    expected = [value.removeprefix("-only-testing:") for value in selected]
    valid = not enumeration.get("errors") and sorted(enabled) == sorted(expected) and not set(expected).intersection(disabled)
    write_json(selection / "receipt.json", {"valid": valid, "requested": expected, "enabled": enabled, "disabled": disabled})
    require(valid, "The exact enabled test selection did not resolve")


def execute_lane(lane):
    directory = output / lane
    checkout, derived, arguments = build_arguments(lane)
    verify_sources(lane)
    build_selection = ["-only-testing:VoiceInkTests"] if lane == "candidate" else selectors
    run(["xcodebuild", "build-for-testing", *arguments, *build_selection], directory / "build.log", checkout)
    verify_sources(lane)
    before = provision(directory, derived)
    write_json(directory / "identity-before.json", before)
    enumerate_tests(directory, checkout, arguments, selectors)
    code = run(["xcodebuild", "test-without-building", *arguments, *selectors, "-resultBundlePath", str(directory / "Pipeline.xcresult")], directory / "tests.log", checkout, True)
    (directory / "test-exit.txt").write_text(str(code) + "\n")
    after = identity(derived)
    write_json(directory / "identity-after.json", after)
    require(before == after, "The app or compiled test bundle changed during execution")
    verify_sources(lane)
    write_json(output / (lane + "-production-after.json"), manifest(checkout))
    sites = {int(key): value for key, value in contract()["expected_baseline_assertions"].items()}
    result = classify((directory / "tests.log").read_text(errors="replace"), code, lane, sites)
    write_json(directory / "result.json", result)
    require(result["valid"], lane + " did not satisfy the matched contract: " + "; ".join(result["errors"]))


def import_inputs(directory):
    inputs = output.parent / "none-profile-inputs"
    inputs.mkdir(exist_ok=False)
    model = inputs / "ggml-base.bin"
    model_url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
    model_hash = "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
    run(["curl", "--location", "--fail", "--retry", "3", "--max-time", "600", "--output", str(model), model_url], directory / "model-download.log")
    if digest(model.read_bytes()) != model_hash:
        raise InvalidFixture("Downloaded Whisper base differs from the existing pinned model")
    aiff = inputs / "input.aiff"
    audio = inputs / "input.wav"
    phrase = "The quick brown fox confirms this local speech to text test for Roma just talk."
    run(["say", "-v", "Samantha", "-r", "135", "-o", str(aiff), phrase], directory / "speech-generation.log")
    run(["afconvert", str(aiff), str(audio), "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"], directory / "audio-conversion.log")
    run(["afinfo", str(audio)], directory / "audio-info.txt")
    with wave.open(str(audio), "rb") as decoded:
        format = {"sample_rate": decoded.getframerate(), "channels": decoded.getnchannels(), "sample_width": decoded.getsampwidth(), "frames": decoded.getnframes()}
    if not (format["sample_rate"] == 16000 and format["channels"] == 1 and format["sample_width"] == 2 and format["frames"] > 0):
        raise InvalidFixture("The generated WAV is not nonempty 16-kHz mono PCM16")
    retained_audio = directory / "input.wav"
    retained_audio.write_bytes(audio.read_bytes())
    write_json(directory / "inputs.json", {
        "model": {"path": str(model), "source": model_url, "sha256": model_hash, "bytes": model.stat().st_size},
        "audio": dict(format, path=str(audio), retained_path="import/input.wav", sha256=digest(audio.read_bytes()), bytes=audio.stat().st_size, phrase=phrase, voice="Samantha", rate=135),
        "setup_reference": "scripts/run-ios-remote-stt-e2e.sh",
        "setup_reference_sha256": digest((repo / "scripts/run-ios-remote-stt-e2e.sh").read_bytes()),
        "scope": "Synthetic speech WAV and hash-pinned local Whisper weights; no microphone or provider credentials"
    })
    return model, audio


def validate_import_observation(observed, inputs, executable_path, processed_bytes):
    errors = []
    if not isinstance(observed, dict):
        return ["The actual import observation must be a JSON object"]
    if observed.get("version") != 1 or type(observed.get("version")) is not int or observed.get("testName") != import_test_name or observed.get("classification") != "passed":
        errors.append("The actual import observation is missing or did not pass")
    if observed.get("modelSHA256") != inputs["model"]["sha256"] or observed.get("audioSHA256") != inputs["audio"]["sha256"]:
        errors.append("The actual import observation does not bind the verified input bytes")
    if observed.get("bundleIdentifier") != "com.negentropi.RomaJustTalk" or observed.get("executablePath") != executable_path or type(observed.get("processIdentifier")) is not int or observed.get("processIdentifier", 0) <= 0:
        errors.append("The actual import observation does not identify the signed test host")
    recognition = observed.get("sameContextRecognition")
    stored = observed.get("storedText")
    if not isinstance(recognition, str) or not isinstance(stored, str) or not recognition.strip() or len(recognition) > 10000:
        errors.append("Actual nonempty recognition and stored text are required")
    else:
        if recognition.encode("utf-8") != stored.encode("utf-8") or recognition.encode("utf-16-le") != stored.encode("utf-16-le") or observed.get("utf8Equal") is not True or observed.get("utf16Equal") is not True:
            errors.append("The stored transcript does not exactly preserve the same-context recognition")
        if not {"quick", "brown", "fox"}.issubset(set(re.findall(r"[a-z]+", recognition.lower()))):
            errors.append("Recognition does not contain the synthetic fixture's sanity words")
    if observed.get("completed") is not True or observed.get("ownedCleanupCompleted") is not True or "enhancedText" not in observed or observed["enhancedText"] is not None:
        errors.append("The actual queue must complete without an enhanced result and finish owned cleanup")
    for key in ["recordID", "queueItemID"]:
        try:
            uuid.UUID(observed.get(key, ""))
        except (ValueError, AttributeError, TypeError):
            errors.append("The actual import observation has no valid " + key)
    processed_hash = observed.get("permanentAudioSHA256")
    if processed_bytes is None or not isinstance(processed_hash, str) or digest(processed_bytes) != processed_hash or not isinstance(observed.get("permanentAudioURL"), str) or not observed["permanentAudioURL"].startswith("file:"):
        errors.append("The retained processed WAV does not match the actual queue's permanent audio")
    return errors


def execute_import():
    require(json.loads((output / "result.json").read_text())["classification"] == "matched-red-green", "Matched comparison must pass before actual ASR setup")
    directory = output / "import"
    directory.mkdir()
    verify_sources("candidate")
    try:
        model, audio = import_inputs(directory)
    except (RuntimeError, OSError, wave.Error) as error:
        raise InvalidFixture("Actual ASR fixture setup failed: " + str(error)) from error
    checkout, derived, arguments = build_arguments("candidate")
    before = provision(directory, derived)
    require(before == json.loads((output / "candidate/identity-after.json").read_text()), "Actual import must use the exact matched candidate app and test bundle")
    write_json(directory / "identity-before.json", before)
    observations = directory / "observations"
    observations.mkdir()
    test_name = import_test_name
    selected = ["-only-testing:VoiceInkTests/VoiceInkTests/" + test_name + "()"]
    settings = {
        "RJT_NONE_IMPORT_LIVE_CHECKS": "1",
        "RJT_NONE_IMPORT_MODEL": str(model),
        "RJT_NONE_IMPORT_AUDIO": str(audio),
        "RJT_NONE_IMPORT_EVIDENCE": str(observations),
        "GITHUB_ACTIONS": "true",
        "RUNNER_ENVIRONMENT": "github-hosted"
    }
    environment = dict(os.environ, **settings, **{"TEST_RUNNER_" + key: value for key, value in settings.items()})
    enumerate_tests(directory, checkout, arguments, selected, environment)
    code = run(["xcodebuild", "test-without-building", *arguments, *selected, "-resultBundlePath", str(directory / "Import.xcresult")], directory / "tests.log", checkout, True, environment)
    (directory / "test-exit.txt").write_text(str(code) + "\n")
    after = identity(derived)
    write_json(directory / "identity-after.json", after)
    require(before == after, "The actual-import app or compiled test bundle changed")
    verify_sources("candidate")
    observed_path = observations / "import-observation.json"
    observed = json.loads(observed_path.read_text()) if observed_path.is_file() else {}
    inputs = json.loads((directory / "inputs.json").read_text())
    result = classify((directory / "tests.log").read_text(errors="replace"), code, "candidate", {}, {test_name: []})
    processed = observations / "processed-input.wav"
    result["errors"].extend(validate_import_observation(
        observed, inputs,
        str(derived / "Build/Products/Debug/roma just talk.app/Contents/MacOS/roma just talk"),
        processed.read_bytes() if processed.is_file() else None
    ))
    errors = result["errors"]
    if digest(model.read_bytes()) != inputs["model"]["sha256"] or digest(audio.read_bytes()) != inputs["audio"]["sha256"]:
        raise InvalidFixture("Actual ASR changed its fixture inputs")
    result.update(valid=not errors, observation=observed, inputs=inputs, scope="Actual synthetic-WAV decoding, Whisper inference and import queue; no microphone, real speaker, provider semantics, editor insertion or physical-key proof")
    write_json(directory / "result.json", result)
    require(result["valid"], "Actual import verification failed: " + "; ".join(errors))
    write_json(output / "complete-result.json", {
        "classification": "passed",
        "candidate_source_sha": contract()["candidate_source_sha"],
        "matched_result_sha256": digest((output / "result.json").read_bytes()),
        "actual_import_result_sha256": digest((directory / "result.json").read_bytes()),
        "matched_and_import_use_same_candidate_identity": True,
        "limits": ["Model and synthetic input are public remote fixtures; no credentials moved.", "Full shared core, Mac units, native editor, UI and Release gates run separately."]
    })


def self_test():
    sites = failure_sites((repo / oracle_path).read_text())
    def log(lane):
        text = ""
        for name, labels in cases.items():
            result = "failed" if lane == "baseline" and labels else "passed"
            text += "Test " + name + "() started.\nTest " + name + "() " + result + " after 0.1 seconds.\n"
        if lane == "baseline":
            for line in sites:
                text += "Test " + sites[line]["test"] + "() recorded an issue at DictationProfilePipelineTests.swift:" + str(line) + ":1: Expectation failed: source-bound assertion\n"
        return text + "Test run with " + str(len(cases)) + " tests in 1 suite " + ("failed" if lane == "baseline" else "passed") + "\n"
    good = log("candidate")
    bad = log("baseline")
    require(classify(good, 0, "candidate", sites)["valid"], "Valid candidate rejected")
    require(classify(bad, 65, "baseline", sites)["valid"], "Valid baseline rejected")
    for text, code, lane in [(good, 0, "candidate"), (bad, 65, "baseline")]:
        result = classify(text, code, lane, sites)
        require(json.loads(json.dumps(result)) == result, "A valid verdict changed through JSON persistence")
    single_cases = {"liveImportFixture": []}
    single_log = "Test liveImportFixture() started.\nTest liveImportFixture() passed after 0.1 seconds.\nTest run with 1 test in 1 suite passed\n"
    require(classify(single_log, 0, "candidate", {}, single_cases)["valid"], "Valid single import test rejected")
    for text, code in [
        (single_log.replace("started.", "not started."), 0),
        (single_log.replace("passed after", "skipped after"), 0),
        (single_log.replace("1 test in", "0 tests in"), 0),
        (single_log + "Test liveImportFixture() recorded an issue: setup failed\n", 0),
        (single_log, 65)
    ]:
        require(not classify(text, code, "candidate", {}, single_cases)["valid"], "Invalid single import test accepted")
    first = next(iter(cases))
    issue = next(line for line in bad.splitlines() if "recorded an issue" in line)
    invalid = [
        (good, 65, "candidate"), (bad, 0, "baseline"), (good, 0, "baseline"),
        (good.replace("Test " + first + "() started.\n", ""), 0, "candidate"),
        (good + "Test " + first + "() started.\n", 0, "candidate"),
        (good.replace(first + "() passed", first + "() skipped"), 0, "candidate"),
        (good.replace("4 tests", "0 tests"), 0, "candidate"),
        (good.replace("Test run with 4 tests in 1 suite passed\n", ""), 0, "candidate"),
        (good + "Test unrelated() started.\n", 0, "candidate"),
        (good + issue + "\n", 0, "candidate"),
        (bad.replace(issue + "\n", ""), 65, "baseline"),
        (bad + issue + "\n", 65, "baseline"),
        (bad.replace("DictationProfilePipelineTests.swift", "Setup.swift"), 65, "baseline"),
        (bad.replace(issue, "Test selected() recorded an issue: setup failed"), 65, "baseline"),
        (bad.replace("Expectation failed:", "Caught error:"), 65, "baseline"),
        (bad.replace(issue, issue.replace("Test " + first, "Test unrelated")), 65, "baseline"),
        (bad.replace("dictationCustomRetainsItsExistingCleanupPath() passed", "dictationCustomRetainsItsExistingCleanupPath() failed"), 65, "baseline"),
        (bad.replace("Test run with 4 tests", "Test run with 5 tests"), 65, "baseline"),
        (bad + "Test other() recorded an issue at Fixture.swift:1:1: Expectation failed: setup\n", 65, "baseline")
    ]
    require(all(not classify(text, code, lane, sites)["valid"] for text, code, lane in invalid), "An invalid classifier fixture was accepted")
    processed = b"synthetic processed-audio classifier fixture"
    inputs = {"model": {"sha256": "a" * 64}, "audio": {"sha256": "b" * 64}}
    observed = {
        "version": 1, "testName": import_test_name, "classification": "passed",
        "modelSHA256": "a" * 64, "audioSHA256": "b" * 64,
        "bundleIdentifier": "com.negentropi.RomaJustTalk", "executablePath": "/fixture/app", "processIdentifier": 123,
        "sameContextRecognition": "The quick brown fox.", "storedText": "The quick brown fox.",
        "utf8Equal": True, "utf16Equal": True, "enhancedText": None, "completed": True, "ownedCleanupCompleted": True,
        "recordID": "5b16a4b6-e87a-4f06-96ec-81e5a7cc8b09", "queueItemID": "7c8fd831-1bfd-4c9b-903d-f072fa2acba4",
        "permanentAudioURL": "file:///fixture/input.wav", "permanentAudioSHA256": digest(processed)
    }
    require(not validate_import_observation(observed, inputs, "/fixture/app", processed), "Valid import observation rejected")
    mutations = [
        {"version": True}, {"classification": "started"}, {"testName": "wrong"},
        {"modelSHA256": "c" * 64}, {"audioSHA256": "c" * 64}, {"processIdentifier": False},
        {"executablePath": "/other/app"}, {"bundleIdentifier": "other"}, {"sameContextRecognition": ""},
        {"sameContextRecognition": "Silence.", "storedText": "Silence."}, {"storedText": "changed"},
        {"sameContextRecognition": "The quick brown fox Café.", "storedText": "The quick brown fox Cafe\u0301."},
        {"utf8Equal": False}, {"utf16Equal": 1}, {"completed": False}, {"ownedCleanupCompleted": False}, {"enhancedText": "AI output"},
        {"recordID": "wrong"}, {"queueItemID": None}, {"permanentAudioSHA256": "c" * 64}, {"permanentAudioURL": "https://example.test/audio"}
    ]
    for mutation in mutations:
        require(validate_import_observation(dict(observed, **mutation), inputs, "/fixture/app", processed), "Invalid import observation accepted: " + str(mutation))
    missing = dict(observed)
    del missing["enhancedText"]
    require(validate_import_observation(missing, inputs, "/fixture/app", processed), "Missing enhancedText accepted")
    require(validate_import_observation(observed, inputs, "/fixture/app", None), "Missing processed audio accepted")
    require(validate_import_observation([], inputs, "/fixture/app", processed), "Non-object observation accepted")
    print(json.dumps({"classification": "offline-classifier-passed", "valid_cases": 4, "invalid_cases": len(invalid) + 5 + len(mutations) + 3, "scope": "Classifier only; no Mac or product execution"}))


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    if mode == "self-test":
        self_test()
    elif mode == "prepare":
        output.mkdir(exist_ok=False)
        for lane in ["candidate", "baseline"]:
            (output / lane).mkdir()
        subprocess.run(["git", "-C", str(repo), "diff", "--quiet", "HEAD", "--", *production_paths, oracle_path], check=True)
        require(not git(repo, "ls-files", "--others", "--exclude-standard", "-z", "--", *production_paths), "Candidate product/test sources must be committed")
        candidate_sha = git(repo, "rev-parse", "HEAD").decode().strip()
        require(digest((repo / lock_path).read_bytes()) == lock_sha, "The reviewed package lock changed")
        subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "origin", baseline_sha], check=True)
        subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(baseline), baseline_sha], check=True)
        require(not (baseline / oracle_path).exists(), "The common oracle would overwrite historical source")
        (baseline / oracle_path).write_bytes((repo / oracle_path).read_bytes())
        require(declarations(baseline) == declarations(repo), "The two products have different dependency/build declarations")
        require((baseline / lock_path).read_bytes() == (repo / lock_path).read_bytes(), "The pinned baseline must already use the exact canonical lock")
        for lane, checkout in [("candidate", repo), ("baseline", baseline)]:
            write_json(output / (lane + "-production.json"), manifest(checkout))
        source = (repo / oracle_path).read_text()
        import_source = (repo / import_oracle_path).read_text()
        require(len(re.findall(r"\bfunc " + import_test_name + r"\(\)", import_source)) == 1, "The actual import test is missing or duplicated")
        write_json(output / "contract.json", {
            "driver_sha": candidate_sha,
            "candidate_source_sha": candidate_sha,
            "baseline_reference_sha": baseline_sha,
            "oracle_path": oracle_path,
            "oracle_sha256": digest(source.encode()),
            "candidate_import_oracle": {"path": import_oracle_path, "sha256": digest(import_source.encode()), "test": import_test_name},
            "verification_helper_sha256": {path: digest((repo / path).read_bytes()) for path in [
                "scripts/run-none-profile-regression.sh", "scripts/run-writing-feature-regression.sh", "scripts/run-ios-remote-stt-e2e.sh", "Makefile"
            ]},
            "source_roots": production_paths,
            "expected_baseline_assertions": failure_sites(source),
            "declarations": declarations(repo),
            "canonical_lock_sha256": lock_sha,
            "canonical_package_pins": 41,
            "changed_production_paths": git(repo, "diff", "--name-only", baseline_sha, candidate_sha, "--", *production_paths).decode().splitlines(),
            "scope": "One unchanged pipeline and queued-paste oracle on pinned products; controlled recognition/AI and target interception, not ASR, microphone, native editor or physical keyboard proof"
        })
        (output / "common-oracle.swift").write_text(source)
        run(["bash", "scripts/run-writing-feature-regression.sh", "packages", str(output / "packages"), "", "", str(package_checkouts)], output / "packages.log")
        _, _, arguments = build_arguments("baseline")
        run(["xcodebuild", "-resolvePackageDependencies", *arguments, "-skipPackageUpdates"], output / "packages/baseline-strict-resolve.log", baseline)
        verify_sources("candidate")
        verify_sources("baseline")
        write_json(output / "packages/baseline-strict-resolve.json", {"exit_code": 0, "canonical_lock_unchanged": True})
        for key, flag, value in [("CurrentTranscriptionModel", "-string", "whisper-large-v3-turbo"), ("PrewarmModelOnWake", "-bool", "false"), ("selectedAIProvider", "-string", "Local CLI"), ("isAIEnhancementEnabled", "-bool", "false")]:
            subprocess.run(["defaults", "write", "com.negentropi.RomaJustTalk", key, flag, value], check=True)
    elif mode in {"candidate", "baseline"}:
        execute_lane(mode)
    elif mode == "import":
        execute_import()
    elif mode == "verify":
        for lane in ["candidate", "baseline"]:
            verify_sources(lane)
            result = json.loads((output / lane / "result.json").read_text())
            sites = {int(key): value for key, value in contract()["expected_baseline_assertions"].items()}
            expected = classify((output / lane / "tests.log").read_text(errors="replace"), int((output / lane / "test-exit.txt").read_text()), lane, sites)
            require(result == expected and result["valid"], "Retained lane verdict is invalid: " + lane)
            before = json.loads((output / lane / "identity-before.json").read_text())
            after = json.loads((output / lane / "identity-after.json").read_text())
            require(before == after == identity(build_arguments(lane)[1]), "Retained app/test identity changed: " + lane)
        require((baseline / oracle_path).read_bytes() == (repo / oracle_path).read_bytes(), "The shared oracle differs between products")
        write_json(output / "result.json", dict(contract(), classification="matched-red-green", candidate=json.loads((output / "candidate/result.json").read_text()), baseline=json.loads((output / "baseline/result.json").read_text()), candidate_sources_unchanged=True, baseline_instrumentation="none"))
    else:
        raise RuntimeError("usage: run-none-profile-regression.sh prepare | baseline | candidate | verify | import | self-test")
except BaseException as error:
    if output.is_dir() and mode != "self-test":
        (output / ("failure-" + mode + ".json")).write_text(json.dumps({"mode": mode, "error": str(error), "classification": "invalid-fixture" if isinstance(error, InvalidFixture) else "invalid-or-failed"}, indent=2) + "\n")
    raise
PY
