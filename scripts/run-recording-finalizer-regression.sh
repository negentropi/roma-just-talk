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
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/recording-finalizer-proof" "${1:-}" <<'PY'
import contextlib
import hashlib
import json
import os
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
engine_path = "VoiceInk/Transcription/Engine/VoiceInkEngine.swift"
oracle_path = "VoiceInkTests/DictationPolishPipelineTests.swift"
fixture_path = "scripts/fixtures/recording-finalizers-before-guard.patch"
driver_path = "scripts/run-recording-finalizer-regression.sh"
workflow_path = ".github/workflows/voiceink-recording-finalizer-check.yml"
lock_path = "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
lock_sha = "bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f"
candidate_engine_sha = "eeb60b103e4c270935f8cac05d1734b0bfcfc6bc047601d47da908dbf8a8dd3c"
baseline_engine_sha = "4f9723565f85e6ae9ea7b7ae1ebb6b539626f95533d0fb44cc4cd8120c545a0f"
oracle_sha = "5a51d639ac380bb3b0a4dcc2d7f8a9e97a1a6c94b96809df3f2fe68248fc0a43"
baseline = output.parent / "recording-finalizer-baseline"
package_checkouts = repo / ".local-build/SourcePackages"
bundle_id = "com.negentropi.RomaJustTalk"
cases = [
    "heldCancellationCannotClearContextCapturedByANewerAcceptedRun",
    "resetCleanupCannotClearContextCapturedByANewerAcceptedRun"
]
expressions = ["fixture.enhancement.capturedContextMarker == context", "fixture.enhancement.clearContextCalls == clears"]
helper_paths = [driver_path, workflow_path, fixture_path, "scripts/run-writing-feature-regression.sh",
    "scripts/verify-static-whisper-xcframework.sh", "scripts/verify-static-whisper-app.sh",
    "scripts/verify-adhoc-macos-test-host.sh", "scripts/tests/verify-adhoc-macos-test-host.test.sh", "Makefile", "LocalBuild.xcconfig",
    "VoiceInk/Services/KeychainService.swift"]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    data = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if path.exists():
        require(path.read_text() == data, "Immutable evidence changed: " + str(path))
    else:
        with path.open("x") as stream:
            stream.write(data)


def git(checkout, *args):
    return subprocess.check_output(["git", "-C", str(checkout), *args])


def manifest(checkout):
    paths = git(checkout, "ls-files", "-z").split(b"\0")
    return {path.decode(): digest((checkout / path.decode()).read_bytes()) for path in paths if path}


def contract():
    return json.loads((output / "contract.json").read_text())


def verify_sources(lane, restored=False):
    checkout = baseline if lane == "baseline" else repo
    value = contract()
    require(git(checkout, "rev-parse", "HEAD").decode().strip() == value["source_sha"], "Pinned checkout revision changed")
    require(not git(checkout, "ls-files", "--others", "--exclude-standard", "-z"), "Unexpected untracked source exists")
    expected = json.loads((output / ("candidate-source.json" if restored else lane + "-source.json")).read_text())
    require(manifest(checkout) == expected, lane + " source closure changed")
    require(digest((checkout / oracle_path).read_bytes()) == oracle_sha, "The identical native oracle changed")
    require(digest((checkout / lock_path).read_bytes()) == lock_sha, "Canonical package lock changed")
    require({path: digest((repo / path).read_bytes()) for path in helper_paths} == value["helper_sha256"], "Verification helper changed")


def run(command, log, checkout=repo, *, allow_failure=False, environment=None, timeout=1800, stderr_log=None):
    print("Running " + command[0] + "; log " + str(log), flush=True)
    with log.open("xb") as stream, (stderr_log.open("xb") if stderr_log else contextlib.nullcontext(stream)) as errors:
        process = subprocess.Popen(command, cwd=checkout, env=environment, stdout=stream, stderr=errors, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            raise
    if code and not allow_failure:
        print("\n".join(line[:1000] for line in log.read_text(errors="replace").splitlines()[-25:]), file=sys.stderr)
        raise RuntimeError("Command failed with exit " + str(code) + "; inspect " + str(log))
    return code


def failure_sites(source):
    sites = {}
    for name in cases:
        matches = list(re.finditer(r"@Test\s+@MainActor\s+func " + name + r"\(\) async throws \{", source))
        require(len(matches) == 1, "Shared native test is missing or duplicated: " + name)
        start = matches[0].end()
        end = source.find("@Test", start)
        block = source[start:end if end >= 0 else len(source)]
        for expression in expressions:
            assertion = "#expect(" + expression + ")"
            require(block.count(assertion) == 1, "The intended ownership assertion is missing or ambiguous: " + name)
            line = source.count("\n", 0, start + block.index(assertion)) + 1
            sites[line] = {"test": name, "expression": expression}
    require(len(sites) == 4, "Four distinct baseline assertion sites are required")
    return sites


def classify(text, code, lane, sites):
    expected = "failed" if lane == "baseline" else "passed"
    errors, observations = [], {}
    starts = re.findall(r"\bTest (\w+)\(\) started\.", text)
    if sorted(starts) != sorted(cases):
        errors.append("Each selected method must start exactly once, with no other test starts")
    for name in cases:
        results = re.findall(r"\bTest " + name + r"\(\) (passed|failed|skipped) after ", text)
        observations[name] = {"starts": starts.count(name), "results": results}
        if results != [expected]:
            errors.append(name + " did not finish once with the expected result")
    summaries = re.findall(r"Test run with (\d+) tests? in (\d+) suites? (passed|failed)", text)
    if len(summaries) != 1 or summaries[0][0] != "2" or int(summaries[0][1]) <= 0 or summaries[0][2] != expected or code != (65 if lane == "baseline" else 0):
        errors.append("The exact two-test summary and expected process exit are required")
    issues = re.findall(r"^.*\brecorded an issue\b[^\n]*", text, re.M)
    observed = []
    for issue in issues:
        match = re.search(r"\bTest (\w+)\(\) recorded an issue at (.+):(\d+):\d+:.*Expectation failed:", issue)
        if match and Path(match[2]).name == Path(oracle_path).name and sites.get(int(match[3]), {}).get("test") == match[1]:
            observed.append(int(match[3]))
    expected_lines = sorted(sites) if lane == "baseline" else []
    if len(issues) != len(expected_lines) or sorted(observed) != expected_lines:
        errors.append("Only the four source-bound context ownership assertions may fail")
    fatal = re.search(r"\b(?:crashed|crash report|unexpected exit|Testing cancelled|Test session ended prematurely|failed to launch|fatal error:)", text, re.I)
    diagnostics = re.search(r"^\s*(?:(?:xcodebuild|swiftc|clang|ld)(?:\[[^\]\n]+\])?:\s*)?(?:fatal\s+)?error:", text, re.M | re.I)
    source_errors = re.search(r"^\s*[^\n]+\.(?:swift|c|cc|cpp|cxx|m|mm|h|hpp):\d+(?::\d+)?:\s*(?:fatal\s+)?error:", text, re.M | re.I)
    if fatal or diagnostics or source_errors:
        errors.append("Crash, launch, compiler or session errors cannot count as regression evidence")
    return {"valid": not errors, "classification": ("intended-context-clear-failures" if lane == "baseline" else "passed") if not errors else "invalid-or-failed",
        "lane": lane, "exit_code": code, "tests": observations, "summaries": [list(value) for value in summaries],
        "issues": issues, "failure_lines": observed, "errors": errors}


def package_identity():
    pins = json.loads((repo / lock_path).read_text())["pins"]
    require(len(pins) == 41 and len({pin["identity"] for pin in pins}) == 41, "Reviewed 41-pin graph is required")
    expected = {pin["identity"]: pin["state"]["revision"] for pin in pins}
    workspace = json.loads((package_checkouts / "workspace-state.json").read_text())
    actual, trees = {}, {}
    for dependency in workspace["object"]["dependencies"]:
        identity = dependency["packageRef"]["identity"]
        if identity not in expected:
            continue
        subpath = dependency["subpath"]
        require(Path(subpath).name == subpath and subpath not in (".", ".."), "Unsafe package checkout path")
        revision = dependency["state"]["checkoutState"]["revision"]
        checkout = package_checkouts / "checkouts" / subpath
        head = git(checkout, "rev-parse", "HEAD").decode().strip()
        require(revision == head == expected[identity] and identity not in actual, "Resolved package differs from its reviewed pin: " + identity)
        require(subprocess.run(["git", "-C", str(checkout), "diff", "--quiet", "HEAD"], capture_output=True).returncode == 0,
            "Tracked package source differs from its reviewed commit: " + identity)
        require(not git(checkout, "ls-files", "--others", "--exclude-standard", "-z"), "Untracked package source exists: " + identity)
        actual[identity] = head
        trees[identity] = git(checkout, "rev-parse", "HEAD^{tree}").decode().strip()
    require(actual == expected, "Actual package checkouts do not close the reviewed graph")
    return {"canonical_lock_sha256": lock_sha, "revisions": actual, "clean_tracked_source_trees": trees}


def static_identity():
    framework = Path.home() / "VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework"
    require(framework.is_dir(), "Static Whisper framework is missing")
    return {str(path.relative_to(framework)): digest(path.read_bytes()) for path in sorted(framework.rglob("*")) if path.is_file()}


def build_arguments(lane):
    checkout = baseline if lane == "baseline" else repo
    derived = output.parent / ("recording-finalizer-derived-" + lane)
    arguments = ["-project", str(checkout / "VoiceInk.xcodeproj"), "-scheme", "VoiceInk", "-configuration", "Debug",
        "-destination", "platform=macOS", "-parallel-testing-enabled", "NO", "-derivedDataPath", str(derived),
        "-xcconfig", str(checkout / "LocalBuild.xcconfig"), "-clonedSourcePackagesDirPath", str(package_checkouts),
        "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile", "-skipPackageUpdates",
        "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=YES", "DEVELOPMENT_TEAM=",
        "ENABLE_HARDENED_RUNTIME=YES",
        "ENABLE_DEBUG_DYLIB=NO", "ENABLE_PREVIEWS=NO",
        "CODE_SIGN_ENTITLEMENTS=" + str(checkout / "VoiceInk/VoiceInk.local.entitlements"),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD"]
    return checkout, derived, arguments


def identity(derived):
    products = derived / "Build/Products/Debug"
    app = products / "roma just talk.app"
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info["CFBundleIdentifier"] == bundle_id, "Unexpected native host bundle identity")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True)
    signature = subprocess.run(["codesign", "-dr", "-", str(app)], check=True, text=True, capture_output=True)
    requirements = re.findall(r"^(?:# )?designated => (.+)$", signature.stdout + signature.stderr, re.M)
    require(len(requirements) == 1, "The exact signed host requirement is unavailable")
    tests = sorted(products.rglob("VoiceInkTests.xctest"))
    require(len(tests) == 1, "Exactly one native unit-test bundle is required")
    with (tests[0] / "Contents/Info.plist").open("rb") as stream:
        test_info = plistlib.load(stream)
    return {"app_path": str(app), "bundle_identifier": info["CFBundleIdentifier"], "designated_requirement": requirements[0],
        "app_files_sha256": {str(path.relative_to(app)): digest(path.read_bytes()) for path in sorted(app.rglob("*")) if path.is_file()},
        "test_bundle_sha256": digest((tests[0] / "Contents/MacOS" / test_info["CFBundleExecutable"]).read_bytes())}


def provision(directory, value):
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
        statement = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('" + service + "','" + bundle_id + "',0,2,4,1,X'" + requirement_hex + "',0,'UNUSED',0);"
        subprocess.run([*prefix, "sqlite3", database], input=statement, text=True, check=True)
        query = "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='" + bundle_id + "' AND service='" + service + "';"
        rows.extend(json.loads(subprocess.check_output([*prefix, "sqlite3", "-json", database, query])))
    require(len(rows) == 2 and {row["service"] for row in rows} == {"kTCCServiceAccessibility", "kTCCServiceMicrophone"}
        and all(row["auth_value"] == 2 and row["requirement"] == requirement_hex for row in rows), "Fresh TCC grants differ from the exact signed host")
    write_json(directory / "tcc.json", rows)
    for command in [["killall", "tccd"], ["sudo", "killall", "tccd"]]:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sleep", "2"], check=True)


def isolated_configuration(directory, derived):
    candidates = sorted((derived / "Build/Products").glob("*.xctestrun"))
    require(len(candidates) == 1, "Exactly one generated native test configuration is required")
    original = candidates[0].read_bytes()
    value = plistlib.loads(original)
    if "TestConfigurations" in value:
        targets = [target for config in value["TestConfigurations"] for target in config.get("TestTargets", [])
            if target.get("BlueprintName") == "VoiceInkTests"]
        for config in value["TestConfigurations"]:
            config["TestTargets"] = [target for target in config.get("TestTargets", []) if target.get("BlueprintName") == "VoiceInkTests"]
    else:
        targets = [target for name, target in value.items() if name == "VoiceInkTests" and isinstance(target, dict)]
        value = {name: target for name, target in value.items() if name == "VoiceInkTests" or name.startswith("__")}
    require(len(targets) == 1, "The unit host configuration must resolve to one target")
    target = targets[0]
    require("VoiceInkTests.xctest" in target.get("TestBundlePath", "") and "roma just talk.app" in target.get("TestHostPath", ""), "Native configuration identifies the wrong host or oracle bundle")
    isolated_user_home = directory / "isolated-user"
    preferences = isolated_user_home / "Library/Preferences"
    preferences.mkdir(parents=True)
    seed = {"selectedAIProvider": "Local CLI", "CurrentTranscriptionModel": "whisper-large-v3-turbo", "PrewarmModelOnWake": False,
        "hasCompletedOnboarding": True, "isAIEnhancementEnabled": False, "IsAudioCleanupEnabled": False,
        "IsTranscriptionCleanupEnabled": False, "enableAnnouncements": False}
    (preferences / (bundle_id + ".plist")).write_bytes(plistlib.dumps(seed))
    environment = target.setdefault("EnvironmentVariables", {})
    environment.update({"CFFIXED_USER_HOME": str(isolated_user_home), "GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"})
    # Xcode split the spaced provider value in argv; the plist and fixture own it.
    arguments = [item for key, value in seed.items() if key != "selectedAIProvider"
        for item in ["-" + key, "YES" if value is True else "NO" if value is False else value]]
    target["CommandLineArguments"] = arguments
    target["ParallelizationEnabled"] = False
    # Relocation changes __TESTROOT__; expand it before writing the isolated copy.
    def expand(node):
        if isinstance(node, str):
            return node.replace("__TESTROOT__", str(candidates[0].parent))
        if isinstance(node, list):
            return [expand(item) for item in node]
        if isinstance(node, dict):
            return {key: expand(item) for key, item in node.items()}
        return node
    path = directory / "isolated.xctestrun"
    path.write_bytes(plistlib.dumps(expand(value)))
    write_json(directory / "configuration.json", {"original_sha256": digest(original), "isolated_sha256": digest(path.read_bytes()),
        "isolated_user_home": str(isolated_user_home), "command_line_arguments": arguments, "seed_preferences": seed,
        "credential_contract": "LOCAL_BUILD routes app KeychainService to the fresh lane UserDefaults; no saved Keychain credential queries. This is source/configuration assurance, not SecItem tracing."})
    return path


def enumerate_tests(directory, configuration, selected=None):
    directory.mkdir()
    arguments = ["xcodebuild", "test-without-building", "-xctestrun", str(configuration), "-destination", "platform=macOS",
        "-parallel-testing-enabled", "NO", *(selected or []), "-enumerate-tests", "-test-enumeration-style", "flat",
        "-test-enumeration-format", "json", "-test-enumeration-output-path", str(directory / "selected-tests.json")]
    run(arguments, directory / "enumeration.log", timeout=180)
    value = json.loads((directory / "selected-tests.json").read_text())
    require(not value.get("errors"), "Native test enumeration reported errors")
    enabled = [test["identifier"] for plan in value.get("values", []) for test in plan.get("enabledTests", [])]
    disabled = [test.get("identifier") for plan in value.get("values", []) for test in plan.get("disabledTests", [])]
    return enabled, disabled


def execute_lane(lane):
    directory = output / lane
    checkout, derived, arguments = build_arguments(lane)
    verify_sources(lane)
    if lane == "baseline":
        require((baseline / engine_path).read_bytes() == (output / "source/baseline-engine.swift").read_bytes(), "Known-bad source differs from its immutable reconstruction")
    packages = package_identity()
    whisper = static_identity()
    write_json(directory / "packages-before.json", packages)
    write_json(directory / "static-whisper-before.json", whisper)
    write_json(directory / "build-command.json", {"arguments": arguments, "local_build_condition": "LOCAL_BUILD", "checkout": str(checkout)})
    run(["xcodebuild", "-showBuildSettings", "-json", *arguments], directory / "build-settings.json", checkout, timeout=180,
        stderr_log=directory / "build-settings-errors.log")
    settings = json.loads((directory / "build-settings.json").read_text())
    host_settings = [value["buildSettings"] for value in settings if value.get("target") == "VoiceInk"]
    require(len(host_settings) == 1 and "LOCAL_BUILD" in host_settings[0].get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split(),
        "The actual app build settings do not enable LOCAL_BUILD credential isolation")
    require(all(host_settings[0].get(key) == "NO" for key in ["ENABLE_DEBUG_DYLIB", "ENABLE_PREVIEWS"]),
        "Actual debug-dylib/preview settings differ from the matched test-host configuration")
    run(["xcodebuild", "build-for-testing", *arguments, "-only-testing:VoiceInkTests"], directory / "build.log", checkout)
    require(re.search(r"(?:SwiftCompile|CompileSwiftSources)[^\n]*VoiceInkEngine\.swift", (directory / "build.log").read_text(errors="replace")) is not None, "Native build did not record Engine compilation")
    verify_sources(lane)
    require(package_identity() == packages and static_identity() == whisper, "Dependency source or static Whisper bytes changed during build")
    host = identity(derived)
    run(["bash", "scripts/verify-static-whisper-app.sh", host["app_path"]], directory / "static-app.log", checkout)
    run(["bash", str(repo / "scripts/verify-adhoc-macos-test-host.sh"), host["app_path"], str(directory / "test-host-signature")],
        directory / "signing.log", checkout)
    provision(directory, host)
    configuration = isolated_configuration(directory, derived)
    config_sha = digest(configuration.read_bytes())
    enabled, disabled = enumerate_tests(directory / "discovery", configuration)
    requested = []
    for name in cases:
        matches = [identifier for identifier in enabled if identifier.endswith("/" + name + "()") and "DictationPolishPipelineTests" in identifier]
        require(len(matches) == 1 and matches[0] not in disabled, "Nested native test identifier did not resolve uniquely: " + name)
        requested.append(matches[0])
    selected = ["-only-testing:" + identifier for identifier in requested]
    narrow, inactive = enumerate_tests(directory / "selection", configuration, selected)
    require(sorted(narrow) == sorted(requested) and not set(requested).intersection(inactive), "The narrowed native selection differs from the two methods")
    write_json(directory / "selection/receipt.json", {"valid": True, "requested": requested, "enabled": narrow, "disabled": inactive})
    write_json(directory / "identity-before.json", host)
    code = run(["xcodebuild", "test-without-building", "-xctestrun", str(configuration), "-destination", "platform=macOS",
        "-parallel-testing-enabled", "NO", *selected, "-resultBundlePath", str(directory / "Native.xcresult")], directory / "tests.log", checkout,
        allow_failure=True, timeout=300)
    write_json(directory / "exit.json", {"test_without_building_exit_code": code})
    after = identity(derived)
    write_json(directory / "identity-after.json", after)
    require(host == after and digest(configuration.read_bytes()) == config_sha, "Native app, oracle binary, signature or launch configuration changed")
    require(package_identity() == packages and static_identity() == whisper, "Dependency bytes changed during native execution")
    verify_sources(lane)
    write_json(directory / "source-after.json", manifest(checkout))
    sites = {int(key): value for key, value in contract()["expected_baseline_assertions"].items()}
    verdict = classify((directory / "tests.log").read_text(errors="replace"), code, lane, sites)
    write_json(directory / "result.json", verdict)
    require(verdict["valid"], lane + " native result is invalid: " + "; ".join(verdict["errors"]))


def restore_baseline():
    value = contract()
    require(baseline.resolve() == Path(value["task_owned_baseline"]).resolve() and baseline.parent == output.parent, "Refusing to restore outside the task-owned checkout")
    require(git(baseline, "rev-parse", "HEAD").decode().strip() == value["source_sha"], "Task-owned baseline checkout revision changed")
    require((baseline / engine_path).read_bytes() == (output / "source/baseline-engine.swift").read_bytes(), "Task-owned Engine changed before restoration")
    (baseline / engine_path).write_bytes((output / "source/candidate-engine.swift").read_bytes())
    verify_sources("baseline", restored=True)
    write_json(output / "baseline/source-restoration.json", {"task_owned_checkout": str(baseline), "candidate_source_restored": True,
        "engine_sha256": candidate_engine_sha, "restoration_method": "Write only the captured Engine bytes in the newly created detached checkout; no git restore/reset."})


def self_test():
    with tempfile.TemporaryDirectory(prefix="rjt-finalizer-config-") as temporary:
        root = Path(temporary)
        derived = root / "derived"
        products = derived / "Build/Products"
        products.mkdir(parents=True)
        generated = {"TestConfigurations": [{"TestTargets": [{"BlueprintName": "VoiceInkTests",
            "TestBundlePath": "__TESTROOT__/Debug/roma just talk.app/Contents/PlugIns/VoiceInkTests.xctest",
            "TestHostPath": "__TESTROOT__/Debug/roma just talk.app/Contents/MacOS/roma just talk"}]}]}
        (products / "generated.xctestrun").write_bytes(plistlib.dumps(generated))
        evidence = root / "evidence"
        evidence.mkdir()
        configuration = plistlib.loads(isolated_configuration(evidence, derived).read_bytes())
        target = configuration["TestConfigurations"][0]["TestTargets"][0]
        seed_path = Path(target["EnvironmentVariables"]["CFFIXED_USER_HOME"]) / "Library/Preferences" / (bundle_id + ".plist")
        require(plistlib.loads(seed_path.read_bytes())["selectedAIProvider"] == "Local CLI", "The isolated preferences truncated the provider value")
        require("-selectedAIProvider" not in target["CommandLineArguments"] and "Local CLI" not in target["CommandLineArguments"],
            "The spaced provider value must not enter Xcode command-line arguments")
        require(target["CommandLineArguments"][:2] == ["-CurrentTranscriptionModel", "whisper-large-v3-turbo"],
            "The existing non-provider startup arguments changed")
    source = git(repo, "show", "HEAD:" + oracle_path).decode()
    require(digest(source.encode()) == oracle_sha, "Pinned common oracle changed")
    sites = failure_sites(source)
    def log(lane):
        result = "failed" if lane == "baseline" else "passed"
        text = "".join("Test " + name + "() started.\nTest " + name + "() " + result + " after 0.1 seconds.\n" for name in cases)
        if lane == "baseline":
            for line, site in sites.items():
                text += "Test " + site["test"] + "() recorded an issue at DictationPolishPipelineTests.swift:" + str(line) + ":1: Expectation failed: source-bound ownership assertion\n"
        return text + "Test run with 2 tests in 2 suites " + result + " after 0.1 seconds.\n"
    good, bad = log("candidate"), log("baseline")
    require(classify(good, 0, "candidate", sites)["valid"], "Valid candidate rejected")
    require(classify(bad, 65, "baseline", sites)["valid"], "Valid known-bad assertions rejected")
    benign_oslog = '2026-10-27 22:39:25.545555+0000 roma just talk[43938:131027] [Connection] Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}\n'
    require(classify(good + benign_oslog, 0, "candidate", sites)["valid"], "A nonfatal background OSLog invalidated a passing native case")
    require(classify(bad + benign_oslog, 65, "baseline", sites)["valid"], "A nonfatal background OSLog invalidated the intended source-bound failures")
    issue = next(line for line in bad.splitlines() if "recorded an issue" in line)
    invalid = [(good, 65, "candidate"), (bad, 0, "baseline"), (good, 0, "baseline"),
        (good.replace("Test " + cases[0] + "() started.\n", ""), 0, "candidate"),
        (good + "Test " + cases[0] + "() started.\n", 0, "candidate"),
        (good.replace("passed after", "skipped after"), 0, "candidate"),
        (good.replace("2 tests", "0 tests"), 0, "candidate"),
        (good + "Test unrelated() started.\n", 0, "candidate"),
        (good + issue + "\n", 0, "candidate"), (bad.replace(issue + "\n", ""), 65, "baseline"),
        (bad + issue + "\n", 65, "baseline"), (bad.replace("DictationPolishPipelineTests.swift", "Setup.swift"), 65, "baseline"),
        (bad.replace("Expectation failed:", "Caught error:"), 65, "baseline"),
        (bad.replace(issue, issue.replace(cases[0], "unrelated")), 65, "baseline"),
        (bad + "Test host crashed\n", 65, "baseline"), (bad + "error: compile failed\n", 65, "baseline"),
        (bad + "xcodebuild: error: Native launch failed\n", 65, "baseline"),
        (bad + "/fixture/Source.swift:12:4: error: compile failed\n", 65, "baseline"),
        (bad + "clang: error: link failed\n", 65, "baseline"),
        (bad.replace("2 tests", "3 tests"), 65, "baseline"), (bad.replace("2 suites", "0 suites"), 65, "baseline")]
    require(all(not classify(text, code, lane, sites)["valid"] for text, code, lane in invalid), "Invalid native result accepted")
    setup_failure = "".join("Test " + name + "() started.\nTest " + name + "() failed after 0.1 seconds.\nTest " + name
        + "() recorded an issue at DictationPolishPipelineTests.swift:586:13: Expectation failed: ai.selectedProvider == .localCLI && ai.isAPIKeyValid\n" for name in cases)
    setup_failure += "Test run with 2 tests in 2 suites failed after 0.1 seconds.\n" + benign_oslog
    require(not classify(setup_failure, 65, "baseline", sites)["valid"], "The actual pre-ownership setup failure counted as known-bad evidence")
    committed_engine = git(repo, "show", "HEAD:" + engine_path)
    require(digest(committed_engine) == candidate_engine_sha, "Pinned committed candidate Engine changed")
    with tempfile.TemporaryDirectory(prefix="rjt-finalizer-fixture-") as temporary:
        checkout = Path(temporary)
        engine = checkout / engine_path
        engine.parent.mkdir(parents=True)
        engine.write_bytes(committed_engine)
        subprocess.run(["git", "apply", "--check", str(repo / fixture_path)], cwd=checkout, check=True)
        subprocess.run(["git", "apply", str(repo / fixture_path)], cwd=checkout, check=True)
        require(digest(engine.read_bytes()) == baseline_engine_sha, "Guard fixture does not reproduce the pinned known-bad Engine")
    print(json.dumps({"classification": "offline-classifier-passed", "valid_cases": 4, "invalid_cases": len(invalid) + 1, "source_bound_assertions": len(sites),
        "scope": "Classifier/source fixture only; no native build or test execution"}))


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    if mode == "self-test":
        self_test()
    elif mode == "prepare":
        require(not output.exists() and not baseline.exists(), "Proof directories must be newly task-owned")
        subprocess.run(["git", "-C", str(repo), "diff", "--quiet", "HEAD"], check=True)
        require(not git(repo, "ls-files", "--others", "--exclude-standard", "-z"), "All candidate sources and proof helpers must be committed")
        require(digest((repo / engine_path).read_bytes()) == candidate_engine_sha and digest((repo / oracle_path).read_bytes()) == oracle_sha, "Pinned candidate Engine or common oracle changed")
        require(digest((repo / lock_path).read_bytes()) == lock_sha, "Reviewed canonical package lock changed")
        sha = git(repo, "rev-parse", "HEAD").decode().strip()
        require(not os.environ.get("GITHUB_SHA") or os.environ["GITHUB_SHA"] == sha, "Checkout differs from the triggered commit")
        output.mkdir()
        for name in ["candidate", "baseline", "source", "packages"]:
            (output / name).mkdir()
        subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(baseline), sha], check=True)
        subprocess.run(["git", "-C", str(baseline), "apply", "--check", str(repo / fixture_path)], check=True)
        subprocess.run(["git", "-C", str(baseline), "apply", str(repo / fixture_path)], check=True)
        require(digest((baseline / engine_path).read_bytes()) == baseline_engine_sha, "Fixture does not reconstruct the exact reviewed known-bad Engine")
        candidate_manifest, baseline_manifest = manifest(repo), manifest(baseline)
        changed = [path for path in sorted(set(candidate_manifest) | set(baseline_manifest)) if candidate_manifest.get(path) != baseline_manifest.get(path)]
        require(changed == [engine_path], "Known-bad fixture changed source outside the Engine guards")
        for lane, checkout in [("candidate", repo), ("baseline", baseline)]:
            (output / ("source/" + lane + "-engine.swift")).write_bytes((checkout / engine_path).read_bytes())
        for source_path in [oracle_path, fixture_path, driver_path, workflow_path,
            "scripts/verify-adhoc-macos-test-host.sh", "scripts/tests/verify-adhoc-macos-test-host.test.sh"]:
            (output / "source" / Path(source_path).name).write_bytes((repo / source_path).read_bytes())
        write_json(output / "candidate-source.json", candidate_manifest)
        write_json(output / "baseline-source.json", baseline_manifest)
        write_json(output / "contract.json", {"source_sha": sha, "candidate_engine_sha256": candidate_engine_sha,
            "baseline_engine_sha256": baseline_engine_sha, "oracle_path": oracle_path, "oracle_sha256": oracle_sha,
            "fixture_sha256": digest((repo / fixture_path).read_bytes()), "canonical_lock_sha256": lock_sha,
            "task_owned_baseline": str(baseline), "changed_paths": changed, "tests": cases,
            "expected_baseline_assertions": failure_sites((repo / oracle_path).read_text()),
            "helper_sha256": {path: digest((repo / path).read_bytes()) for path in helper_paths},
            "scope": "Actual native app-hosted unit execution with controlled recorder/registry and context marker, not microphone, physical input, real clipboard context, provider semantics or full global Mode/ASR cleanup proof."})
        run(["bash", "scripts/run-writing-feature-regression.sh", "packages", str(output / "packages"), "", "", str(package_checkouts)], output / "package-contract.log")
        verify_sources("candidate")
        verify_sources("baseline")
    elif mode in ("candidate", "baseline"):
        try:
            execute_lane(mode)
        finally:
            if mode == "baseline":
                restore_baseline()
    elif mode == "verify":
        verify_sources("candidate")
        verify_sources("baseline", restored=True)
        value = contract()
        sites = {int(key): site for key, site in value["expected_baseline_assertions"].items()}
        receipts = {}
        for lane in ["baseline", "candidate"]:
            directory = output / lane
            code = json.loads((directory / "exit.json").read_text())["test_without_building_exit_code"]
            verdict = classify((directory / "tests.log").read_text(errors="replace"), code, lane, sites)
            require(verdict == json.loads((directory / "result.json").read_text()) and verdict["valid"], "Immutable native verdict no longer validates")
            require(json.loads((directory / "identity-before.json").read_text()) == json.loads((directory / "identity-after.json").read_text()), "Native code/signature receipt changed")
            _, derived, _ = build_arguments(lane)
            require(identity(derived) == json.loads((directory / "identity-after.json").read_text()), "Built native code or signature changed after its run")
            require(digest((directory / "isolated.xctestrun").read_bytes()) == json.loads((directory / "configuration.json").read_text())["isolated_sha256"], "Isolated launch configuration changed")
            require(json.loads((directory / "source-after.json").read_text()) == json.loads((output / (lane + "-source.json")).read_text()), "Native source closure changed")
            require(json.loads((directory / "selection/receipt.json").read_text())["valid"] is True, "Exact selection receipt is missing")
            receipts[lane] = verdict
        require(json.loads((output / "baseline/source-restoration.json").read_text())["candidate_source_restored"] is True, "Task-owned source restoration is unproven")
        for suffix in ["packages-before.json", "static-whisper-before.json"]:
            require((output / "baseline" / suffix).read_bytes() == (output / "candidate" / suffix).read_bytes(), "The two native lanes used different dependencies")
        left = json.loads((output / "baseline/identity-before.json").read_text())["app_files_sha256"]
        right = json.loads((output / "candidate/identity-before.json").read_text())["app_files_sha256"]
        code_paths = [path for path in right if path.startswith("Contents/MacOS/") and not path.endswith(".dSYM")]
        require(any(left.get(path) != right[path] for path in code_paths), "Native candidate and known-bad app code did not differ")
        write_json(output / "result.json", {"classification": "matched-red-green", "source_sha": value["source_sha"],
            "contract_sha256": digest((output / "contract.json").read_bytes()), "oracle_sha256": oracle_sha, "tests": cases,
            "candidate": receipts["candidate"], "baseline": receipts["baseline"], "scope": value["scope"]})
    else:
        raise RuntimeError("Use self-test, prepare, baseline, candidate, or verify")
except BaseException as error:
    if output.is_dir() and mode != "self-test":
        write_json(output / ("failure-" + mode + ".json"), {"classification": "invalid-or-failed", "phase": mode, "error": str(error)})
    raise
PY
