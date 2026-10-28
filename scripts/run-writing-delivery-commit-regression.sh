#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test && "${1:-}" != compare ]]; then
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
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/writing-delivery-commit-proof" "${1:-}" "${2:-${RJT_DELIVERY_COMMIT_LANE:-baseline}}" <<'PY'
import contextlib
import hashlib
import json
import os
import plistlib
import re
import signal
import subprocess
import sys
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
lane = sys.argv[4] if len(sys.argv) > 4 else os.environ.get("RJT_DELIVERY_COMMIT_LANE", "baseline")
if lane not in ("baseline", "candidate"):
    raise RuntimeError("Select the baseline or candidate lane")
session_path = "VoiceInk/Services/WritingActionSession.swift"
writing_oracle = "VoiceInkTests/WritingActionDeliveryCommitTests.swift"
audio_oracle = "VoiceInkTests/DictationPolishAudioFileTests.swift"
oracle_hashes = {writing_oracle: "43933722762e49b156387907dcf0631be35154745b14b8d0ac5393ed81e12506",
    audio_oracle: "365bc7f2b3b019ba2dd9284d8901b8b18fc4c82db1827cd7e134c109f95ab1e9"}
driver_path = "scripts/run-writing-delivery-commit-regression.sh"
workflow_path = ".github/workflows/voiceink-writing-delivery-commit-check.yml"
lock_path = "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
lock_sha = "bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f"
baseline_sha = "c29ac2d7c6fa7690ea3bd0d5a38697b44a37d182"
session_original_sha = "10fc37409284b6c5bc4d60986bfd7b030046c08654c639781061c5b7058c6596"
session_bridged_sha = "a04c539eb86d85ffb22f9a3fab46ceabbd69c297b8cfd63af8d3257a704b561e"
bridge_sha = "1b6048e13f973dc7cc8aae5ab13ff90a586396c7e7bffdeadca9a162e4ae2bea"
bridge_patch = r"""diff --git a/VoiceInk/Services/WritingActionSession.swift b/VoiceInk/Services/WritingActionSession.swift
index 9f539f8d..ef4b9daf 100644
--- a/VoiceInk/Services/WritingActionSession.swift
+++ b/VoiceInk/Services/WritingActionSession.swift
@@ -10,6 +10,18 @@ final class WritingActionSession {
     let target: WritingTarget
     let provider: AIEnhancementProviderSnapshot
 
+    init(
+        kind: VoiceInkWritingActionKind,
+        targetLanguage: String,
+        target: WritingTarget,
+        provider: AIEnhancementProviderSnapshot
+    ) {
+        self.kind = kind
+        self.targetLanguage = targetLanguage
+        self.target = target
+        self.provider = provider
+    }
+
     init(kind: VoiceInkWritingActionKind, provider: AIEnhancementProviderSnapshot) throws {
         self.kind = kind
         self.provider = provider
"""
baseline = output.parent / "writing-delivery-commit-baseline"
package_checkouts = repo / ".local-build/SourcePackages"
bundle_id = "com.negentropi.RomaJustTalk"
cases = {
    "cancellationAfterConfirmedWritingMutationKeepsGeneratedMetadata": {"source": writing_oracle, "suite": "WritingActionDeliveryCommitTests", "expected_state": ".completed"},
    "cancellationAfterUnconfirmedWritingMutationKeepsRecoveryMetadata": {"source": writing_oracle, "suite": "WritingActionDeliveryCommitTests", "expected_state": ".failed"},
    "importReadOnlyStoreSaveFailureDoesNotExposeAPendingRow": {"source": audio_oracle, "suite": "DictationPolishAudioFileTests"}
}
helper_paths = [driver_path, workflow_path, "scripts/run-writing-feature-regression.sh",
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


def verify_sources(selected_lane):
    checkout = baseline if selected_lane == "baseline" else repo
    value = contract()
    require(git(checkout, "rev-parse", "HEAD").decode().strip() == (baseline_sha if selected_lane == "baseline" else value["source_sha"]), "Pinned checkout revision changed")
    untracked = {p.decode() for p in git(checkout, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if p}
    require(untracked == ({writing_oracle} if selected_lane == "baseline" else set()), "Unexpected untracked source exists")
    require(manifest(checkout) == json.loads((output / (selected_lane + "-source.json")).read_text()), "Tracked source closure changed")
    for path, expected in oracle_hashes.items():
        require(digest((checkout / path).read_bytes()) == expected, "Common oracle changed: " + path)
    require(digest((checkout / lock_path).read_bytes()) == lock_sha, "Canonical package lock changed")
    require({path: digest((repo / path).read_bytes()) for path in helper_paths} == value["helper_sha256"], "Verification helper changed")
    if selected_lane == "baseline":
        actual = {p for p in git(checkout, "diff", "--name-only", "HEAD").decode().splitlines() if p}
        require(actual == {session_path, audio_oracle}, "Only the initializer bridge and common Audio test replacement may alter historical tracked bytes")
        require(digest((checkout / session_path).read_bytes()) == session_bridged_sha, "Initializer-only bridge changed")


def declarations(checkout):
    roots = ["Package.swift", "VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "iOS", "LocalBuild.xcconfig", "Makefile"]
    paths = git(checkout, "ls-files", "-z", "--", *roots).split(b"\0")
    return {path.decode(): digest((checkout / path.decode()).read_bytes()) for path in paths if path and
        (path in (b"Package.swift", b"LocalBuild.xcconfig", b"Makefile") or path.endswith((b"/Package.swift", b"/project.pbxproj")))}


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


def failure_sites():
    sites = {}
    for name, case in cases.items():
        source = (repo / case["source"]).read_text()
        matches = list(re.finditer(r"@Test\s+@MainActor\s+func " + name + r"\(\) async throws \{", source))
        require(len(matches) == 1, "Common native method is missing/duplicated: " + name)
        start = matches[0].end()
        end = source.find("@Test", start)
        block = source[start:end if end >= 0 else len(source)]
        if "expected_state" in case:
            expressions = {"record.transcriptionState == " + case["expected_state"]: "canceled-state",
                "record.text == fixture.instruction": "The transcription was canceled.",
                "record.enhancedText?.utf16.elementsEqual(fixture.enhancement.output.utf16) == true" if "Confirmed" in name else "record.enhancedText?.utf8.elementsEqual(fixture.enhancement.output.utf8) == true": "nil",
                'record.aiEnhancementModelName == "owned-writing-model"': "nil",
                'record.aiRequestSystemMessage == "owned system request"': "nil",
                'record.aiRequestUserMessage == "owned user request"': "nil",
                "fixture.cancellations == 0": "one-cancellation",
                "saved.transcriptionState == " + case["expected_state"]: "canceled-state",
                "saved.text == fixture.instruction": "The transcription was canceled.",
                "saved.enhancedText?.utf16.elementsEqual(fixture.enhancement.output.utf16) == true": "nil",
                'saved.aiRequestSystemMessage == "owned system request"': "nil",
                'saved.aiRequestUserMessage == "owned user request"': "nil"}
        else:
            expressions = {"firstVisibleRows.isEmpty": "nonempty-first-query"}
        for expression, observed in expressions.items():
            needle = "#expect(" + expression
            require(block.count(needle) == 1, "Source-bound final assertion is missing/duplicated: " + expression)
            line = source.count("\n", 0, start + block.index(needle)) + 1
            key = Path(case["source"]).name + ":" + str(line)
            require(key not in sites, "Duplicate failure site")
            sites[key] = {"test": name, "file": Path(case["source"]).name, "line": line, "expression": expression, "observed": observed}
    require(len(sites) == 25, "Exactly 24 post-mutation metadata failures and one first-query ghost failure are required")
    return sites


def classify(text, code, selected_lane, sites):
    expected = "failed" if selected_lane == "baseline" else "passed"
    errors, observations = [], {}
    starts = re.findall(r"\bTest (\w+)\(\) started\.", text)
    if sorted(starts) != sorted(cases): errors.append("Exactly the three selected methods must start once")
    for name in cases:
        results = re.findall(r"\bTest " + name + r"\(\) (passed|failed|skipped) after ", text)
        observations[name] = {"starts": starts.count(name), "results": results}
        if results != [expected]: errors.append("Unexpected method outcome: " + name)
    summaries = re.findall(r"Test run with (\d+) tests? in (\d+) suites? (passed|failed)", text)
    if len(summaries) != 1 or summaries[0][0] != "3" or int(summaries[0][1]) <= 0 or summaries[0][2] != expected or code != (65 if selected_lane == "baseline" else 0):
        errors.append("Exact three-test summary/process exit required")
    issues = re.findall(r"^.*\brecorded an issue\b[^\n]*", text, re.M)
    observed = []
    for issue in issues:
        match = re.search(r"\bTest (\w+)\(\) recorded an issue at (.+):(\d+):\d+:.*Expectation failed:", issue)
        if not match: continue
        key = Path(match[2]).name + ":" + match[3]
        site = sites.get(key)
        if not site or site["test"] != match[1]: continue
        kind = site["observed"]
        valid_value = bool(re.search(r"→\s*1\)?\s*==\s*0", issue)) if kind == "one-cancellation" else (
            bool(re.search(r"→\s*(?:Optional\((?:[A-Za-z_]\w*\.)*\.?canceled\)|(?:[A-Za-z_]\w*\.)*\.?canceled)(?=[\s),]|$)", issue)) if kind == "canceled-state" else (
            ("firstVisibleRows" in issue and ".isEmpty" in issue and not re.search(r"firstVisibleRows\s*→\s*\[\s*\]", issue)) if kind == "nonempty-first-query" else kind in issue))
        if valid_value: observed.append(key)
    expected_sites = sorted(sites) if selected_lane == "baseline" else []
    if len(issues) != len(expected_sites) or sorted(observed) != expected_sites:
        errors.append("Only the exact post-mutation metadata and first-caller-query failures with actual wrong values may fail")
    # The read-only import intentionally exercises Cocoa 513. Keep that exact diagnostic, rejecting other errors.
    expected_storage_errors = re.findall(r"^.*SwiftData\.DefaultStore save failed with error: Error Domain=NSCocoaErrorDomain Code=513\b[^\n]*", text, re.M)
    if len(expected_storage_errors) != 1:
        errors.append("Exactly one actual read-only save diagnostic is required")
    unexpected_diagnostics = "\n".join(line for line in text.splitlines() if line not in expected_storage_errors)
    compiler_error = re.search(r"^(?:[^\n]*[\/][^\n:]+\.(?:swift|m|mm|c|cc|cpp|h):\d+(?::\d+)?:\s*(?:fatal\s+)?error:|\s*(?:xcodebuild|swiftc|clang):\s*(?:fatal\s+)?error:|\s*error:)", unexpected_diagnostics, re.M | re.I)
    session_failure = re.search(r"\b(?:crashed|crash report|unexpected exit|Testing cancelled|Testing failed:|Test session ended prematurely|failed to launch|fatal error:)|\*\* TEST (?:BUILD |LAUNCH )FAILED \*\*", unexpected_diagnostics, re.I)
    if compiler_error or session_failure or (selected_lane == "candidate" and re.search(r"\*\* TEST(?: EXECUTE)? FAILED \*\*", unexpected_diagnostics)):
        errors.append("Compile/setup/launch/session failures cannot count as red proof")
    return {"valid": not errors, "classification": ("intended-post-delivery-and-first-query-failures" if selected_lane == "baseline" else "passed") if not errors else "invalid-or-failed",
        "lane": selected_lane, "exit_code": code, "tests": observations, "summaries": [list(v) for v in summaries], "issues": issues, "failure_sites": observed, "errors": errors}


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
    derived = output.parent / ("writing-delivery-commit-derived-" + lane)
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
    # xctestrun splits spaced argv values. Keep the provider in the isolated preference plist.
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
    require(re.search(r"(?:SwiftCompile|CompileSwiftSources)[^\n]*TranscriptionPipeline\.swift", (directory / "build.log").read_text(errors="replace")) is not None, "Native build did not record the actual pipeline receiver compilation")
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
    for name, case in cases.items():
        matches = [identifier for identifier in enabled if identifier.endswith("/" + name + "()") and case["suite"] in identifier]
        require(len(matches) == 1 and matches[0] not in disabled, "Nested native test identifier did not resolve uniquely: " + name)
        requested.append(matches[0])
    selected = ["-only-testing:" + identifier for identifier in requested]
    narrow, inactive = enumerate_tests(directory / "selection", configuration, selected)
    require(sorted(narrow) == sorted(requested) and not set(requested).intersection(inactive), "The narrowed native selection differs from the three methods")
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
    sites = contract()["expected_baseline_assertions"]
    verdict = classify((directory / "tests.log").read_text(errors="replace"), code, lane, sites)
    write_json(directory / "result.json", verdict)
    require(verdict["valid"], lane + " native result is invalid: " + "; ".join(verdict["errors"]))


def verify_baseline_preserved():
    value = contract()
    require(baseline.resolve() == Path(value["task_owned_baseline"]).resolve() and baseline.parent == output.parent, "Baseline is outside its task-owned checkout")
    verify_sources("baseline")
    original = json.loads((output / "baseline-original-source.json").read_text())
    current = manifest(baseline)
    require({p: h for p, h in original.items() if p not in {session_path, audio_oracle}} ==
        {p: h for p, h in current.items() if p not in {session_path, audio_oracle}}, "Historical runtime source outside the initializer bridge changed")
    write_json(output / "baseline/source-preservation.json", {"task_owned_checkout": str(baseline), "runtime_sources_preserved_except_initializer_bridge": True,
        "replaced_tracked_oracle": audio_oracle, "added_oracle": writing_oracle, "session_original_sha256": session_original_sha,
        "session_bridged_sha256": session_bridged_sha, "bridge_sha256": bridge_sha,
        "scope": "Tracked test replacement and new test source are explicit instrumentation. Production source differs only by the captured-value initializer; no delivery or import fix is injected."})


def check_isolated_provider_configuration():
    import tempfile
    with tempfile.TemporaryDirectory(prefix="rjt-isolated-provider-") as temporary:
        root = Path(temporary)
        for modern in [False, True]:
            derived = root / ("modern" if modern else "legacy")
            products = derived / "Build/Products"
            products.mkdir(parents=True)
            target = {"BlueprintName": "VoiceInkTests", "TestBundlePath": "__TESTROOT__/VoiceInkTests.xctest",
                "TestHostPath": "__TESTROOT__/roma just talk.app"}
            original = {"TestConfigurations": [{"TestTargets": [target]}]} if modern else {"VoiceInkTests": target}
            (products / "Host.xctestrun").write_bytes(plistlib.dumps(original))
            directory = derived / "evidence"
            directory.mkdir()
            configuration = isolated_configuration(directory, derived)
            value = plistlib.loads(configuration.read_bytes())
            result = value["TestConfigurations"][0]["TestTargets"][0] if modern else value["VoiceInkTests"]
            receipt = json.loads((directory / "configuration.json").read_text())
            preference_path = Path(receipt["isolated_user_home"]) / "Library/Preferences" / (bundle_id + ".plist")
            preferences = plistlib.loads(preference_path.read_bytes())
            require(preferences == receipt["seed_preferences"] and preferences["selectedAIProvider"] == "Local CLI",
                "The isolated plist must retain the complete provider name")
            arguments = result["CommandLineArguments"]
            expected = [item for key, item_value in preferences.items() if key != "selectedAIProvider"
                for item in ["-" + key, "YES" if item_value is True else "NO" if item_value is False else item_value]]
            # Plist serialization may reorder keys; compare each key/value pair, preserving all other options.
            require(len(arguments) % 2 == 0 and dict(zip(arguments[::2], arguments[1::2])) ==
                dict(zip(expected[::2], expected[1::2])) and "-selectedAIProvider" not in arguments,
                "Only the spaced provider option may be omitted from argv")
            require(result["EnvironmentVariables"]["CFFIXED_USER_HOME"] == receipt["isolated_user_home"],
                "The launched target must use the seeded preference home")
            require(receipt["isolated_sha256"] == digest(configuration.read_bytes()), "Configuration identity changed")


def self_test():
    check_isolated_provider_configuration()
    for path, sha in oracle_hashes.items(): require(digest((repo / path).read_bytes()) == sha, "Frozen common oracle changed: " + path)
    sites = failure_sites()
    def log(selected_lane):
        result = "failed" if selected_lane == "baseline" else "passed"
        text = "".join("Test " + name + "() started.\nTest " + name + "() " + result + " after 0.1 seconds.\n" for name in cases)
        if selected_lane == "baseline":
            for site in sites.values():
                value = '(fixture.cancellations → 1) == 0' if site["observed"] == "one-cancellation" else ('(record.transcriptionState → .canceled) == .completed: Confirmed external delivery must not become a canceled recording.' if site["observed"] == "canceled-state" else ('(firstVisibleRows → [VoiceInk.Transcription]).isEmpty' if site["observed"] == "nonempty-first-query" else site["observed"]))
                text += "Test " + site["test"] + "() recorded an issue at " + site["file"] + ":" + str(site["line"]) + ":1: Expectation failed: " + value + "\n"
        return text + 'SwiftData.DefaultStore save failed with error: Error Domain=NSCocoaErrorDomain Code=513 "The file could not be saved."\n' + "Test run with 3 tests in 3 suites " + result + " after 0.1 seconds.\n" + ("** TEST EXECUTE FAILED **\n" if selected_lane == "baseline" else "** TEST SUCCEEDED **\n")
    good, bad = log("candidate"), log("baseline")
    require(classify(good, 0, "candidate", sites)["valid"], "Valid candidate rejected")
    require(classify(bad, 65, "baseline", sites)["valid"], "Valid exact red fixture rejected")
    nonfatal_oslog = '2026-10-27 22:29:36.457568+0000 roma just talk[23555:73809] [Connection] Unable to re-register with Process Instance Registry, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut"\n'
    require(classify(bad + nonfatal_oslog, 65, "baseline", sites)["valid"] and classify(good + nonfatal_oslog, 0, "candidate", sites)["valid"], "Nonfatal OSLog noise was misclassified as a compiler or launch failure")
    issue = next(line for line in bad.splitlines() if "recorded an issue" in line)
    invalid = [(good, 65, "candidate"), (bad, 0, "baseline"), (good, 0, "baseline"),
        (good.replace("Test " + next(iter(cases)) + "() started.\n", ""), 0, "candidate"),
        (good + "Test " + next(iter(cases)) + "() started.\n", 0, "candidate"),
        (good.replace("passed after", "skipped after"), 0, "candidate"),
        (good.replace("3 tests", "0 tests"), 0, "candidate"), (good + "Test unrelated() started.\n", 0, "candidate"),
        (good + issue + "\n", 0, "candidate"), (bad.replace(issue + "\n", ""), 65, "baseline"),
        (bad + issue + "\n", 65, "baseline"), (bad.replace("WritingActionDeliveryCommitTests.swift", "Setup.swift"), 65, "baseline"),
        (bad.replace("Expectation failed:", "Caught error:"), 65, "baseline"), (bad + "Test host crashed\n", 65, "baseline"),
        (bad + "error: compile failed\n", 65, "baseline"), (bad.replace("3 suites", "0 suites"), 65, "baseline"),
        (bad.replace('→ [VoiceInk.Transcription]', '→ []'), 65, "baseline"),
        (bad.replace('(fixture.cancellations → 1)', '(fixture.cancellations → 0)'), 65, "baseline"),
        (bad.replace('→ .canceled', '→ .failed'), 65, "baseline"),
        (good.replace('Code=513', 'Code=999'), 0, "candidate"),
        (good.replace('Code=513', 'Code=5130'), 0, "candidate"),
        (bad + 'xcodebuild: error: failed to build\n', 65, "baseline"),
        (bad + '/tmp/Receiver.swift:32:9: error: invalid source\n', 65, "baseline"),
        (bad + 'Testing failed: test host could not launch\n', 65, "baseline"),
        (bad + '** TEST BUILD FAILED **\n', 65, "baseline"),
        (good + '** TEST EXECUTE FAILED **\n', 0, "candidate"),
        (bad + 'SwiftData.DefaultStore save failed with error: Error Domain=NSCocoaErrorDomain Code=513\n', 65, "baseline")]
    require(all(not classify(text, code, lane, sites)["valid"] for text, code, lane in invalid), "Invalid result accepted")
    require(digest(bridge_patch.encode()) == bridge_sha and digest(git(repo, "show", baseline_sha + ":" + session_path)) == session_original_sha, "Historical bridge contract changed")
    print(json.dumps({"classification": "offline-classifier-passed", "valid_cases": 4, "invalid_cases": len(invalid), "source_bound_failures": len(sites), "scope": "Classifier/source only; no native execution"}))


def compare_runs():
    paths = [os.environ.get("RJT_DELIVERY_BASELINE_PROOF"), os.environ.get("RJT_DELIVERY_CANDIDATE_PROOF")]
    require(all(paths), "Set absolute extracted baseline/candidate proof directories")
    left, right = map(Path, paths)
    require(all(p.is_absolute() and p.is_dir() and p.resolve() == p for p in [left, right]), "Comparison inputs must be real absolute directories")
    def read(root, path): return json.loads((root / path).read_text())
    contracts = [read(p, "contract.json") for p in [left, right]]
    for selected_lane, path, value in [("baseline", left, contracts[0]), ("candidate", right, contracts[1])]:
        require(value["lane"] == selected_lane and value["baseline_reference_sha"] == baseline_sha, "Wrong proof lane/baseline")
        require(value["oracle_sha256"] == oracle_hashes and value["session_original_sha256"] == session_original_sha
            and value["session_bridged_sha256"] == session_bridged_sha and value["bridge_sha256"] == bridge_sha, "Common oracle/initializer bridge differs")
        for name, expected_hash in oracle_hashes.items():
            require(digest((path / "source" / name).read_bytes()) == expected_hash, "Retained common oracle bytes changed")
        native = read(path, selected_lane + "/result.json")
        code = read(path, selected_lane + "/exit.json")["test_without_building_exit_code"]
        actual = classify((path / selected_lane / "tests.log").read_text(), code, selected_lane, value["expected_baseline_assertions"])
        require(actual == native and actual["valid"], "Actual log no longer reproduces the exact verdict")
        result = read(path, "result.json")
        require(result["lane"] == selected_lane and result["source_sha"] == value["source_sha"] and result["result"] == native
            and result["contract_sha256"] == digest((path / "contract.json").read_bytes()), "Final result no longer binds its contract")
        require(read(path, selected_lane + "/identity-before.json") == read(path, selected_lane + "/identity-after.json"), "Lane binary/signature changed")
        require(read(path, selected_lane + "/source-after.json") == read(path, selected_lane + "-source.json"), "Lane tracked sources changed")
        preserved = read(path, "baseline/source-preservation.json")
        require(preserved["runtime_sources_preserved_except_initializer_bridge"] is True and preserved["bridge_sha256"] == bridge_sha, "Historical runtime source preservation missing")
    for key in ["baseline_reference_sha", "oracle_sha256", "canonical_lock_sha256", "session_original_sha256", "session_bridged_sha256", "bridge_sha256", "instrumentation", "tests", "expected_baseline_assertions", "live_build_declarations", "helper_sha256"]:
        require(contracts[0][key] == contracts[1][key], "Cross-run proof contract differs: " + key)
    require(read(left, "baseline-original-source.json") == read(right, "baseline-original-source.json"), "Historical original source inventory differs")
    for name in ["toolchain.json"]:
        require(read(left, name) == read(right, name), "Selected toolchain/OS/architecture differs")
    for name in ["packages-before.json", "static-whisper-before.json"]:
        require(read(left, "baseline/" + name) == read(right, "candidate/" + name), "Cross-run dependency state differs: " + name)
    require(read(left, "baseline/configuration.json")["seed_preferences"] == read(right, "candidate/configuration.json")["seed_preferences"], "Fresh host preference seeds differ")
    before = read(left, "baseline/identity-before.json")["app_files_sha256"]
    after = read(right, "candidate/identity-before.json")["app_files_sha256"]
    require(before.get("Contents/MacOS/roma just talk") != after.get("Contents/MacOS/roma just talk"), "Known-bad and candidate receiver code did not differ")
    print(json.dumps({"classification": "matched-red-green", "baseline_reference_sha": baseline_sha,
        "baseline_run_source_sha": contracts[0]["source_sha"], "candidate_run_source_sha": contracts[1]["source_sha"],
        "oracle_sha256": oracle_hashes, "tests": list(cases), "cross_run_graph_toolchain_static_whisper_equal": True,
        "baseline_expected_issues": 25, "candidate_expected_issues": 0,
        "scope": "Matched controlled native post-mutation metadata and first-context-query boundary only; no physical input, CloudKit or Undo gesture proof."}, indent=2))


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    if mode == "self-test":
        self_test()
    elif mode == "compare":
        compare_runs()
    elif mode == "prepare":
        require(not output.exists() and not baseline.exists(), "Proof/checkouts must be new task-owned paths")
        subprocess.run(["git", "-C", str(repo), "diff", "--quiet", "HEAD"], check=True)
        require(not git(repo, "ls-files", "--others", "--exclude-standard", "-z"), "Commit all proof sources before dispatch")
        for path, sha in oracle_hashes.items(): require(digest((repo / path).read_bytes()) == sha, "Frozen common oracle changed")
        require(digest((repo / lock_path).read_bytes()) == lock_sha, "Canonical lock changed")
        sha = git(repo, "rev-parse", "HEAD").decode().strip()
        require(not os.environ.get("GITHUB_SHA") or os.environ["GITHUB_SHA"] == sha, "Triggered commit differs from source")
        require(digest(bridge_patch.encode()) == bridge_sha and digest(git(repo, "show", baseline_sha + ":" + session_path)) == session_original_sha, "Bridge contract changed")
        output.mkdir()
        for name in ["candidate", "baseline", "source", "packages"]: (output / name).mkdir()
        subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(baseline), baseline_sha], check=True)
        historical = manifest(baseline)
        require(audio_oracle in historical and writing_oracle not in historical, "Unexpected historical test inventory")
        (output / "source/baseline-original-audio-tests.swift").write_bytes((baseline / audio_oracle).read_bytes())
        (output / "source/baseline-original-session.swift").write_bytes((baseline / session_path).read_bytes())
        for path in oracle_hashes: (baseline / path).write_bytes((repo / path).read_bytes())
        bridge = output / "source/session-value-initializer.patch"; bridge.write_text(bridge_patch)
        subprocess.run(["git", "-C", str(baseline), "apply", "--check", str(bridge)], check=True)
        subprocess.run(["git", "-C", str(baseline), "apply", str(bridge)], check=True)
        require(digest((baseline / session_path).read_bytes()) == session_bridged_sha, "Only the exact initializer bridge is allowed")
        (output / "source/baseline-instrumentation.diff").write_bytes(git(baseline, "diff", "--binary", "HEAD"))
        require(declarations(repo) == declarations(baseline), "Live build declarations differ from historical baseline")
        for path in [*oracle_hashes, *helper_paths]:
            destination = output / "source" / path
            destination.parent.mkdir(parents=True, exist_ok=True); destination.write_bytes((repo / path).read_bytes())
        for selected_lane, checkout in [("candidate", repo), ("baseline", baseline)]:
            write_json(output / (selected_lane + "-source.json"), manifest(checkout))
        write_json(output / "baseline-original-source.json", historical)
        toolchain = {name: subprocess.check_output(command, stderr=subprocess.STDOUT).decode() for name, command in
            [("xcode", ["xcodebuild", "-version"]), ("swift", ["swift", "--version"]), ("macos", ["sw_vers"]), ("architecture", ["uname", "-m"])]}
        write_json(output / "toolchain.json", toolchain)
        write_json(output / "contract.json", {"source_sha": sha, "lane": lane, "baseline_reference_sha": baseline_sha,
            "oracle_sha256": oracle_hashes, "canonical_lock_sha256": lock_sha, "task_owned_baseline": str(baseline),
            "session_original_sha256": session_original_sha, "session_bridged_sha256": session_bridged_sha, "bridge_sha256": bridge_sha,
            "instrumentation": {"replaced_tracked_test": audio_oracle, "added_test": writing_oracle, "production_bridge_only": session_path},
            "tests": list(cases), "expected_baseline_assertions": failure_sites(), "live_build_declarations": declarations(repo),
            "helper_sha256": {path: digest((repo / path).read_bytes()) for path in helper_paths},
            "scope": "Actual app pipeline post-mutation metadata and importer first-caller-context fetch. Synthetic controlled fixtures; no physical input, Clipboard Undo, CloudKit or runtime review-UI proof."})
        run(["bash", "scripts/run-writing-feature-regression.sh", "packages", str(output / "packages"), "", "", str(package_checkouts)], output / "package-contract.log")
        verify_sources("candidate"); verify_sources("baseline"); verify_baseline_preserved()
    elif mode == "run":
        require(contract()["lane"] == lane, "Selected proof lane changed")
        try: execute_lane(lane)
        finally: verify_baseline_preserved()
    elif mode == "verify":
        require(contract()["lane"] == lane, "Selected proof lane changed")
        verify_sources("candidate"); verify_sources("baseline"); verify_baseline_preserved()
        directory = output / lane
        value = contract(); sites = value["expected_baseline_assertions"]
        code = json.loads((directory / "exit.json").read_text())["test_without_building_exit_code"]
        verdict = classify((directory / "tests.log").read_text(errors="replace"), code, lane, sites)
        require(verdict == json.loads((directory / "result.json").read_text()) and verdict["valid"], "Exact lane result no longer validates")
        require(json.loads((directory / "identity-before.json").read_text()) == json.loads((directory / "identity-after.json").read_text()), "Native identities changed")
        _, derived, _ = build_arguments(lane)
        require(identity(derived) == json.loads((directory / "identity-after.json").read_text()), "Actual native code/signature changed after execution")
        require(digest((directory / "isolated.xctestrun").read_bytes()) == json.loads((directory / "configuration.json").read_text())["isolated_sha256"], "Launch configuration changed")
        require(json.loads((directory / "source-after.json").read_text()) == json.loads((output / (lane + "-source.json")).read_text()), "Source closure changed")
        write_json(output / "result.json", {"classification": "matched-baseline-valid" if lane == "baseline" else "candidate-passed", "source_sha": value["source_sha"], "lane": lane,
            "contract_sha256": digest((output / "contract.json").read_bytes()), "oracle_sha256": oracle_hashes,
            "tests": list(cases), "result": verdict,
            "scope": value["scope"], "cross_run_match_required": "Compare exact common oracle, initializer bridge, original baseline runtime, toolchain, canonical package checkout/tree and static Whisper receipts before claiming matched red/green across these lane runs."})
    else:
        raise RuntimeError("Use self-test, prepare, run or verify with baseline/candidate lane; compare uses absolute proof paths from environment")
except BaseException as error:
    if output.is_dir() and mode not in ("self-test", "compare"):
        write_json(output / ("failure-" + mode + ".json"), {"classification": "invalid-or-failed", "phase": mode, "error": str(error)})
    raise
PY
