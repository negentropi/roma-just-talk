#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run this store control only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
    echo "The store control must own the disposable console user." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/dictation-store-seed-proof" "${1:-}" <<'PY'
import copy
import ctypes
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

repo, output = map(Path, sys.argv[1:3])
mode = sys.argv[3]
old_sha = "ebc92f1e60fdabbb9e26b2817f414d154865a9d5"
tag_sha = "846d05df04d5821a7b5dc8588304cb58e3bd8368"
lock_path = "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
lock_sha = "bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f"
oracle_path = "VoiceInkTests/DictationStoreSeedLiveTests.swift"
helper_paths = ["scripts/run-dictation-store-seed-check.sh", "scripts/tests/dictation-store-source-inventory.test.py", ".github/workflows/voiceink-dictation-store-seed-check.yml"]
product_roots = ["VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "VoiceInkTests", "VoiceInkUITests", "iOS", "Makefile", "LocalBuild.xcconfig"]
model_names = ["Transcription", "VocabularyWord", "WordReplacement", "SessionMetric"]
model_paths = ["VoiceInk/Models/" + name + ".swift" for name in model_names]
test_name = "liveDictationPersistentStoreSeedControl"
test_id = "VoiceInkTests/VoiceInkTests/" + test_name + "()"
selector = "-only-testing:" + test_id
bundle_id = "com.negentropi.RomaJustTalk"
predecessor = output.parent / "dictation-store-seed-predecessor"
packages = output.parent / "dictation-store-seed-packages"
whisper = Path.home() / "VoiceInk-Dependencies/whisper.cpp"
framework = whisper / "build-apple/whisper.xcframework"
normal_support = Path.home() / "Library/Application Support" / bundle_id


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_text())


def write(path, value):
    data = json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + "\n"
    if path.exists():
        require(path.read_text() == data, "Evidence already exists with different bytes: " + str(path))
    else:
        path.write_text(data)


def git(checkout, *args):
    return subprocess.check_output(["git", "-C", str(checkout), *args])


def gitlink_source(path, object_id):
    if not os.path.lexists(path):
        return {"kind": "gitlink", "state": "uninitialized"}
    require(stat.S_ISDIR(path.lstat().st_mode), "Tracked gitlink changed filesystem kind: " + str(path))
    metadata = path / ".git"
    if not os.path.lexists(metadata):
        require(not any(path.iterdir()), "Uninitialized gitlink contains unversioned source: " + str(path))
        return {"kind": "gitlink", "state": "uninitialized"}
    require(not metadata.is_symlink(), "Gitlink Git metadata must not be a symlink: " + str(path))
    top_level = Path(os.fsdecode(git(path, "rev-parse", "--show-toplevel")).removesuffix("\n"))
    require(top_level.resolve() == path.resolve(), "Gitlink must own its initialized checkout: " + str(path))
    revision = git(path, "rev-parse", "HEAD").decode().strip()
    require(revision == object_id, "Gitlink checkout revision differs from its pinned object: " + str(path))
    require(not git(path, "status", "--porcelain", "--untracked-files=no", "--ignore-submodules=none"), "Gitlink checkout has tracked changes: " + str(path))
    return {"kind": "gitlink", "state": "initialized", "revision": revision, "tracked_sources": tracked_sources(path)}


def tracked_sources(checkout, *roots):
    result = {}
    entries = git(checkout, "ls-files", "--stage", "-z", "--", *roots).split(b"\0")
    for entry in entries:
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, object_id, stage = (value.decode("ascii") for value in metadata.split())
        relative = os.fsdecode(raw_path)
        require(stage == "0" and relative not in result, "Unmerged or duplicate tracked source entry: " + relative)
        require(mode in {"100644", "100755", "120000", "160000"}, "Unsupported tracked source Git mode " + mode + ": " + relative)
        path = checkout / relative
        identity = {"git_mode": mode, "git_object": object_id}
        if mode == "160000":
            head_entry = git(checkout, "--literal-pathspecs", "ls-tree", "-z", "HEAD", "--", relative).split(b"\0")
            expected = b"160000 commit " + object_id.encode("ascii") + b"\t" + raw_path
            require(head_entry == [expected, b""], "Gitlink index differs from its pinned parent revision: " + relative)
            result[relative] = dict(identity, **gitlink_source(path, object_id))
            continue
        information = path.lstat()
        if mode == "120000":
            require(stat.S_ISLNK(information.st_mode), "Tracked symlink changed filesystem kind: " + relative)
            result[relative] = dict(identity, kind="symlink", target=os.readlink(path))
        else:
            require(stat.S_ISREG(information.st_mode), "Tracked regular source changed filesystem kind: " + relative)
            require(bool(information.st_mode & stat.S_IXUSR) == (mode == "100755"), "Tracked source executable mode changed: " + relative)
            result[relative] = dict(identity, kind="file", bytes=information.st_size, sha256=digest(path.read_bytes()))
    return result


def run(command, log, checkout=repo, environment=None, allow_failure=False):
    print("Running " + command[0] + "; log " + str(log), flush=True)
    with log.open("xb") as stream:
        result = subprocess.run(command, cwd=checkout, env=environment, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode and not allow_failure:
        print("\n".join(log.read_text(errors="replace").splitlines()[-70:]), file=sys.stderr)
        raise RuntimeError("Command failed; inspect " + str(log))
    return result.returncode


def tree(root):
    require(root.is_dir() and not root.is_symlink(), "Missing real directory: " + str(root))
    result = {}
    for path in sorted(root.rglob("*")):
        key = path.relative_to(root).as_posix()
        if path.is_symlink():
            result[key] = {"kind": "symlink", "target": os.readlink(path)}
        elif path.is_file():
            result[key] = {"kind": "file", "bytes": path.stat().st_size, "sha256": digest(path.read_bytes())}
        elif path.is_dir():
            result[key] = {"kind": "directory"}
        else:
            raise RuntimeError("Unexpected filesystem entry: " + str(path))
    return result


def store_tree(root):
    value = tree(root)
    require(all(entry["kind"] != "symlink" for entry in value.values()), "Store fixture cannot contain symlinks")
    require(all(value.get(name + ".store", {}).get("bytes", 0) > 0 for name in ["default", "dictionary", "stats"]), "All three nonempty persistent stores are required")
    return value


def manifest(checkout):
    return tracked_sources(checkout, *product_roots)


def declarations(checkout):
    values = git(checkout, "ls-files", "-z", "--", *product_roots).split(b"\0")
    return {path.decode(): digest((checkout / path.decode()).read_bytes()) for path in values if path and (path.endswith((b"/Package.swift", b"/project.pbxproj")) or path in [b"Package.swift", b"Makefile", b"LocalBuild.xcconfig"])}


def source_bridge():
    require(git(repo, "rev-parse", "v1.95.1^{commit}").decode().strip() == tag_sha, "Historical tag moved")
    values = {}
    for revision in [tag_sha, old_sha, "HEAD"]:
        sources = {path: git(repo, "show", revision + ":" + path) for path in model_paths}
        app = git(repo, "show", revision + ":VoiceInk/VoiceInk.swift").decode()
        factory_start = "    private static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {"
        factory_end = "    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {"
        require(app.count(factory_start) == app.count(factory_end) == 1, "Persistent factory anchors changed")
        factory = app[app.index(factory_start):app.index(factory_end)]
        global_schemas = list(re.finditer(r"let schema = Schema\(\[([^\]]+)\]\)", app))
        require(len(global_schemas) == 1, "Global schema declaration is ambiguous")
        order = re.findall(r"(\w+)\.self", global_schemas[0].group(1))
        require(order == model_names, "Global model order changed")
        project = git(repo, "show", revision + ":VoiceInk.xcodeproj/project.pbxproj").decode()
        require(project.count("PRODUCT_MODULE_NAME = VoiceInk;") == 2, "Actual product module changed")
        values[revision] = {"models": {path: digest(data) for path, data in sources.items()}, "factory_sha256": digest(factory.encode()), "global_schema_order": order, "global_schema_constructor_sha256": digest(global_schemas[0].group(0).encode()), "module": "VoiceInk"}
        (output / ("factory-" + revision.replace("HEAD", "candidate") + ".swift")).write_text(factory)
    require(values[tag_sha] == values[old_sha] == values["HEAD"], "Tag, predecessor and current schema/factory/module bridge differs")
    return values


def verify_sources(lane):
    contract = load(output / "contract.json")
    checkout = predecessor if lane == "predecessor" else repo
    require(git(checkout, "rev-parse", "HEAD").decode().strip() == contract["source_sha"][lane], "Pinned source revision changed")
    require(manifest(checkout) == load(output / (lane + "-source.json")), "Product or test source bytes changed: " + lane)
    untracked = {path.decode() for path in git(checkout, "ls-files", "--others", "--exclude-standard", "-z", "--", *product_roots).split(b"\0") if path}
    require(untracked == ({oracle_path} if lane == "predecessor" else set()), "Unexpected untracked product or test sources: " + lane)
    require(digest((checkout / oracle_path).read_bytes()) == contract["oracle_sha256"], "The source-compatible oracle changed")
    require(digest((checkout / lock_path).read_bytes()) == lock_sha, "Canonical package lock changed")
    require(declarations(checkout) == contract["declarations"], "Dependency/build declarations changed")
    require(all(digest((repo / path).read_bytes()) == value for path, value in contract["helpers"].items()), "Verification helper changed")


def whisper_source():
    if not whisper.exists():
        return {"exists": False}
    require((whisper / ".git").exists(), "Whisper dependency must retain Git provenance")
    return {"exists": True, "revision": git(whisper, "rev-parse", "HEAD").decode().strip(), "tracked_sources": tracked_sources(whisper), "tracked_diff_sha256": digest(git(whisper, "diff", "HEAD", "--"))}


def dependency_state():
    return {"whisper_source": whisper_source(), "framework": tree(framework), "setup_source": {path: digest((repo / path).read_bytes()) for path in ["Makefile", "scripts/verify-static-whisper-xcframework.sh", "scripts/verify-static-whisper-app.sh", "scripts/verify-adhoc-library-validation.sh"]}}


def package_state():
    state = load(packages / "workspace-state.json")
    pins = {pin["identity"]: pin for pin in load(repo / lock_path)["pins"]}
    result = {}
    for dependency in state.get("object", {}).get("dependencies", []):
        checkout_state = dependency.get("state", {}).get("checkoutState")
        if checkout_state is None:
            continue
        identity = dependency.get("packageRef", {}).get("identity")
        require(identity in pins and identity not in result, "Unexpected or duplicate resolved package checkout")
        path = packages / "checkouts" / dependency["subpath"]
        require(path.is_dir() and path.parent == packages / "checkouts", "Package checkout escaped the dedicated root")
        revision = git(path, "rev-parse", "HEAD").decode().strip()
        require(revision == checkout_state.get("revision") == pins[identity]["state"]["revision"], "Actual package revision differs from its canonical pin: " + identity)
        require(not git(path, "status", "--porcelain", "--untracked-files=no"), "Canonical package checkout has tracked changes: " + identity)
        result[identity] = {"revision": revision, "location": dependency["packageRef"].get("location"), "tracked_sources": tracked_sources(path)}
    require(set(result) == set(pins), "Every canonical pin must have an actual resolved checkout")
    return result


def verify_dependencies():
    require(dependency_state() == load(output / "dependencies-frozen.json"), "Shared static Whisper framework or setup source changed between app lanes")
    require(package_state() == load(output / "packages-frozen.json"), "Actual canonical package revisions or source bytes changed between app lanes")


def build_arguments(lane):
    checkout = predecessor if lane == "predecessor" else repo
    derived = output.parent / ("dictation-store-seed-derived-" + lane)
    return checkout, derived, [
        "-project", str(checkout / "VoiceInk.xcodeproj"), "-scheme", "VoiceInk", "-configuration", "Debug",
        "-destination", "platform=macOS", "-parallel-testing-enabled", "NO", "-derivedDataPath", str(derived),
        "-xcconfig", str(checkout / "LocalBuild.xcconfig"), "-clonedSourcePackagesDirPath", str(packages),
        "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile", "-skipPackageUpdates",
        "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=YES", "DEVELOPMENT_TEAM=",
        "CODE_SIGN_ENTITLEMENTS=" + str(checkout / "VoiceInk/VoiceInk.local.entitlements"),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD"
    ]


def identity(derived):
    products = derived / "Build/Products/Debug"
    app = products / "roma just talk.app"
    info = app / "Contents/Info.plist"
    require(subprocess.check_output(["plutil", "-extract", "CFBundleIdentifier", "raw", "-o", "-", str(info)], text=True).strip() == bundle_id, "Unexpected signed app identity")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    signed = subprocess.run(["codesign", "-dr", "-", str(app)], text=True, capture_output=True, check=True)
    matches = re.findall(r"^(?:# )?designated => (.+)$", signed.stdout + signed.stderr, re.M)
    require(len(matches) == 1, "Signed host requirement unavailable")
    bundles = sorted(products.rglob("VoiceInkTests.xctest"))
    require(bool(bundles), "Actual hosted test bundle is missing")
    for bundle in bundles:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    return {"app_path": str(app), "executable_path": str(app / "Contents/MacOS/roma just talk"), "app_tree": tree(app), "test_bundles": {str(bundle.relative_to(products)): tree(bundle) for bundle in bundles}, "designated_requirement": matches[0]}


def provision(directory, value):
    requirement = directory / "host-requirement.txt"
    requirement.write_text(value["designated_requirement"] + "\n")
    binary = directory / "host.csreq"
    subprocess.run(["csreq", "-r", str(requirement), "-b", str(binary)], check=True)
    encoded = binary.read_bytes().hex().upper()
    rows = []
    for service, database, prefix in [
        ("kTCCServiceAccessibility", "/Library/Application Support/com.apple.TCC/TCC.db", ["sudo"]),
        ("kTCCServiceMicrophone", str(Path.home() / "Library/Application Support/com.apple.TCC/TCC.db"), [])
    ]:
        statement = "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,indirect_object_identifier_type,indirect_object_identifier,flags) VALUES('" + service + "','" + bundle_id + "',0,2,4,1,X'" + encoded + "',0,'UNUSED',0);"
        subprocess.run([*prefix, "sqlite3", database], input=statement, text=True, check=True)
        query = "SELECT service,client,auth_value,hex(csreq) AS requirement FROM access WHERE client='" + bundle_id + "' AND service='" + service + "';"
        rows.extend(json.loads(subprocess.check_output([*prefix, "sqlite3", "-json", database, query])))
    require(len(rows) == 2 and all(row["auth_value"] == 2 and row["requirement"] == encoded for row in rows), "Fresh TCC grants do not match the exact signed host")
    write(directory / "tcc.json", rows)
    for prefix in [[], ["sudo"]]:
        subprocess.run([*prefix, "killall", "tccd"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)


def inventory():
    if not normal_support.exists():
        return {"path": str(normal_support), "exists": False, "entries": []}
    return {"path": str(normal_support), "exists": True, "entries": sorted(path.relative_to(normal_support).as_posix() for path in normal_support.rglob("*"))}


def seed_defaults():
    settings = [
        ("CurrentTranscriptionModel", "string", "whisper-large-v3-turbo"),
        ("selectedAIProvider", "string", "Local CLI"),
        ("hasCompletedOnboarding", "bool", "true"),
        ("DidApplyLaunchAtLoginDefault", "bool", "true"),
        ("PrewarmModelOnWake", "bool", "false"),
        ("automaticUpdatesEnabled", "bool", "false"),
        ("SUEnableAutomaticChecks", "bool", "false"),
        ("SUAutomaticallyUpdate", "bool", "false"),
        ("SUHasLaunchedBefore", "bool", "true"),
        ("isAIEnhancementEnabled", "bool", "false"),
        ("IsTranscriptionCleanupEnabled", "bool", "false"),
        ("IsAudioCleanupEnabled", "bool", "false"),
        ("isMiddleClickToggleEnabled", "bool", "false"),
        ("powerModeUIFlag", "bool", "false"),
        ("enableAnnouncements", "bool", "false")
    ]
    for key, kind, value in settings:
        subprocess.run(["defaults", "write", bundle_id, key, "-" + kind, value], check=True)
    selected = {}
    for key, kind, value in settings:
        type_output = subprocess.check_output(["defaults", "read-type", bundle_id, key], text=True).strip()
        observed = subprocess.check_output(["defaults", "read", bundle_id, key], text=True).strip()
        expected_type = "string" if kind == "string" else "boolean"
        expected_value = value if kind == "string" else ("1" if value == "true" else "0")
        require(type_output == "Type is " + expected_type and observed == expected_value, "Typed startup default did not persist: " + key)
        selected[key] = {"type": expected_type, "value": observed}
    write(output / "startup-defaults.json", {"values": selected, "recording_arguments": [], "model_selection": "Existing cloud-model descriptor prevents local model loading or download; no recognition is requested.", "scope": "Only exact injected preference keys queried on the disposable user. App initialization still opens normal Application Support stores.", "host_initialization_limit": "Actual app initialization unconditionally attempts recorder.startPreRollBuffering(). No recording command or audio fixture is supplied; this check does not establish microphone inactivity."})


def classify(text, exit_code):
    starts = re.findall(r"\bTest (\w+)\(\) started\.", text)
    results = re.findall(r"\bTest (\w+)\(\) (passed|failed|skipped) after ", text)
    summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
    issues = re.findall(r"^.*\brecorded an issue\b[^\n]*", text, re.M)
    valid = exit_code == 0 and starts == [test_name] and results == [(test_name, "passed")] and summaries == [("1", "passed")] and not issues
    return {"valid": valid, "exit_code": exit_code, "starts": starts, "results": [list(row) for row in results], "summaries": [list(row) for row in summaries], "issues": issues}


def metadata_rows(value):
    rows = []
    if isinstance(value, dict):
        if value.get("_type", {}).get("_name") == "ActionTestMetadata":
            rows.append({"identifier": value.get("identifier", {}).get("_value"), "status": value.get("testStatus", {}).get("_value")})
        for child in value.values():
            rows.extend(metadata_rows(child))
    elif isinstance(value, list):
        for child in value:
            rows.extend(metadata_rows(child))
    return rows


def xcresult(directory):
    bundle = directory / "Test.xcresult"
    def get(arguments, name):
        data = subprocess.check_output(["xcrun", "xcresulttool", "get", "object", "--legacy", "--path", str(bundle), "--format", "json", *arguments])
        (directory / name).write_bytes(data)
        return json.loads(data)
    root = get([], "xcresult-root.json")
    refs = [action.get("actionResult", {}).get("testsRef", {}).get("id", {}).get("_value") for action in root.get("actions", {}).get("_values", [])]
    require(len(refs) == 1 and isinstance(refs[0], str), "Exactly one native test action is required")
    rows = metadata_rows(get(["--id", refs[0]], "xcresult-tests.json"))
    require(len(rows) == 1 and rows[0]["identifier"] in [test_id, test_id.removeprefix("VoiceInkTests/")] and rows[0]["status"] == "Success", "Native result must contain exactly the selected successful hosted test")
    write(directory / "native-result.json", {"valid": True, "test_action_id": refs[0], "tests": rows})
    attachments = directory / "attachments"
    run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", str(attachments)], directory / "export-attachments.log")


def selected_test(directory, checkout, arguments, environment):
    selection = directory / "selection"
    selection.mkdir()
    run(["xcodebuild", "test-without-building", *arguments, selector, "-enumerate-tests", "-test-enumeration-style", "flat", "-test-enumeration-format", "json", "-test-enumeration-output-path", str(selection / "tests.json")], selection / "enumeration.log", checkout, environment)
    enumerated = load(selection / "tests.json")
    enabled = [test.get("identifier") for plan in enumerated.get("values", []) for test in plan.get("enabledTests", [])]
    disabled = [test.get("identifier") for plan in enumerated.get("values", []) for test in plan.get("disabledTests", [])]
    require(not enumerated.get("errors") and enabled == [test_id] and test_id not in disabled, "Exact enabled test selection did not resolve")
    write(selection / "receipt.json", {"valid": True, "enabled": enabled, "disabled": disabled})


def live_executable(pid):
    library = ctypes.CDLL("/usr/lib/libproc.dylib")
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096)
    count = library.proc_pidpath(pid, buffer, len(buffer))
    require(count > 0, "Cannot observe live test host executable")
    return os.fsdecode(buffer.value)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def wait_closed(directory, observed):
    pid = observed["hostPID"]
    deadline = time.monotonic() + 45
    while alive(pid) and time.monotonic() < deadline:
        time.sleep(0.1)
    require(not alive(pid), "Exact test host PID is still alive; store copy is forbidden")
    fixture = Path(observed["fixturePath"])
    result = run(["lsof", "-n", "-P", "+D", str(fixture)], directory / "closed-fixture-open-files.txt", allow_failure=True)
    require(result == 1 and not (directory / "closed-fixture-open-files.txt").read_bytes(), "Fixture still has open descriptors or could not be checked; store hash/copy forbidden")
    write(directory / "host-exit.json", {"hostPID": pid, "executablePath": observed["executablePath"], "observedExited": True, "checkedAtUnix": time.time(), "beforeAnyStoreHashOrCopy": True, "fixtureHasNoOpenDescriptors": True})


def run_host(directory, command, checkout, environment, executable):
    observed_path = directory / "observations/observation.json"
    handshake = directory / "observations/host-observed.json"
    seen = None
    started = time.monotonic()
    with (directory / "tests.log").open("xb") as stream:
        process = subprocess.Popen(command, cwd=checkout, env=environment, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while process.poll() is None:
                if seen is None and observed_path.is_file():
                    observed = load(observed_path)
                    pid = observed.get("hostPID")
                    require(type(pid) is int and pid > 0 and pid != process.pid, "Actual hosted app PID is missing")
                    require(live_executable(pid) == executable == observed.get("executablePath"), "Live host is not the pinned app executable")
                    details = subprocess.check_output(["ps", "-p", str(pid), "-ww", "-o", "pid=,ppid=,lstart=,command="], text=True)
                    seen = {"hostPID": pid, "executablePath": executable, "observedLive": True, "ps": details, "checkedAtUnix": time.time()}
                    write(directory / "host-live.json", seen)
                    write(handshake, {"hostPID": pid, "executablePath": executable})
                require(time.monotonic() - started < 600, "Hosted seed/control test exceeded its bounded deadline")
                time.sleep(0.02)
        except BaseException:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
    require(seen is not None, "No live host PID was observed; no store can be copied")
    observed = load(observed_path)
    require(observed.get("hostPID") == seen["hostPID"], "Host PID changed during the phase")
    wait_closed(directory, observed)
    return process.returncode, observed


def phase(lane, name, fixture):
    verify_sources(lane)
    verify_dependencies()
    directory = output / name
    directory.mkdir()
    observations = directory / "observations"
    observations.mkdir()
    checkout, derived, arguments = build_arguments(lane)
    before = identity(derived)
    write(directory / "identity-before.json", before)
    provision(directory, before)
    settings = {
        "RJT_DICTATION_STORE_SEED_CHECKS": "1", "GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted",
        "RJT_STORE_PHASE": name, "RJT_STORE_FIXTURE": str(fixture), "RJT_STORE_EVIDENCE": str(observations),
        "RJT_STORE_SOURCE_SHA": load(output / "contract.json")["source_sha"][lane],
        "RJT_STORE_RUN_ROOT": str(output), "RJT_STORE_EXPECTED_EXE": before["executable_path"]
    }
    environment = dict(os.environ, **settings, **{"TEST_RUNNER_" + key: value for key, value in settings.items()})
    write(directory / "normal-support-before-enumeration.json", inventory())
    selected_test(directory, checkout, arguments, environment)
    write(directory / "normal-support-after-enumeration.json", inventory())
    write(directory / "normal-support-before.json", inventory())
    command = ["xcodebuild", "test-without-building", *arguments, selector, "-resultBundlePath", str(directory / "Test.xcresult")]
    code, observed = run_host(directory, command, checkout, environment, before["executable_path"])
    write(directory / "normal-support-after.json", inventory())
    result = classify((directory / "tests.log").read_text(errors="replace"), code)
    (directory / "test-exit.txt").write_text(str(code) + "\n")
    write(directory / "result.json", result)
    require(result["valid"], "Exact hosted test did not execute once and pass: " + name)
    require(type(observed.get("version")) is int and observed["version"] == 1 and observed.get("testName") == test_name and observed.get("classification") == "passed" and observed.get("phase") == name and observed.get("sourceSHA") == settings["RJT_STORE_SOURCE_SHA"] and observed.get("sourcePath") == str(checkout / oracle_path) and observed.get("fixturePath") == str(fixture) and observed.get("bundleIdentifier") == bundle_id, "Actual observation is missing, failed or identifies the wrong phase")
    require(observed.get("normalSupportPath") == str(normal_support), "Inventory path differs from the actual app module's Application Support directory")
    for filename in ["schema-raw.json", "schema-canonical.json", "snapshots.json", "runtimeidentity.json"]:
        require((observations / filename).is_file(), "Missing actual runtime artifact: " + filename)
    after = identity(derived)
    write(directory / "identity-after.json", after)
    require(before == after, "Signed app/test bundle changed during phase")
    xcresult(directory)
    verify_sources(lane)
    verify_dependencies()
    write(directory / "closed-store-tree.json", store_tree(fixture))
    return observed


def seed_unchanged():
    seed = output / "stores/seed"
    require(store_tree(seed) == load(output / "seed-closed-tree.json"), "Original closed predecessor seed changed")
    modes = {str(path.relative_to(seed)): oct(path.stat().st_mode & 0o777) for path in [seed, *sorted(seed.rglob("*"))]}
    require(modes == load(output / "seed-readonly.json")["entries"], "Original seed read-only protection changed")


def clone_seed(destination, name):
    seed_unchanged()
    require(not destination.exists(), "Refusing to overwrite a store clone")
    source = output / "stores/seed"
    shutil.copytree(source, destination, symlinks=False)
    for path in [destination, *destination.rglob("*")]:
        path.chmod(0o700 if path.is_dir() else 0o600)
    before = store_tree(destination)
    require(before == load(output / "seed-closed-tree.json"), "Complete closed seed directory copy differs")
    write(output / (name + "-clone-before.json"), before)
    seed_unchanged()


def normalized_identity(value):
    result = copy.deepcopy(value)
    require(isinstance(result, dict), "Runtime identity must be an object")
    raw_hash = result.pop("schemaRawSHA256", None)
    require(isinstance(raw_hash, str) and re.fullmatch(r"[0-9a-f]{64}", raw_hash), "Missing raw runtime schema digest")
    require(isinstance(result.get("schemaCanonicalSHA256"), str) and re.fullmatch(r"[0-9a-f]{64}", result["schemaCanonicalSHA256"]), "Missing normalized runtime schema digest")
    require(isinstance(result.get("schemaNormalization"), str) and result["schemaNormalization"], "Schema normalization must be explicit")
    require(result.get("declaredSchemaOrder") == model_names, "Runtime declared schema order differs")
    models = result.get("models", [])
    require([value.get("reflectedType") for value in models] == ["VoiceInk." + name for name in model_names], "Runtime models are not the actual app module types")
    entities = result.get("schemaEntities", [])
    require(len(entities) == 4 and len(set(entities)) == 4 and sorted(value.get("entityName") for value in models) == sorted(entities), "Runtime entity identities do not match actual schema entities")
    configurations = result.get("configurations", [])
    require(len(configurations) == 3, "All three persistent configurations are required")
    expected = {"default": [models[0]["entityName"]], "dictionary": [models[1]["entityName"], models[2]["entityName"]], "stats": [models[3]["entityName"]]}
    for configuration in configurations:
        name = configuration.get("name")
        require(name in expected and configuration.get("isStoredInMemoryOnly") is False and configuration.get("allowsSave") is True and configuration.get("groupAppContainerIdentifier") is None and configuration.get("cloudKitContainerIdentifier") is None, "Invalid persistent configuration")
        require(sorted(configuration.get("schemaEntities", [])) == sorted(expected[name]), "Model group differs from actual factory")
        path = configuration.get("url")
        require(isinstance(path, str) and Path(path).name == name + ".store", "Wrong configured persistent store URL")
        configuration["url"] = Path(path).name
    require({value["name"] for value in configurations} == set(expected), "Duplicate or missing store group")
    identifiers = result.get("persistentIdentifiers", {})
    require(set(identifiers) == set(model_names), "Missing persisted model identifiers")
    for model, runtime in zip(model_names, models):
        rows = identifiers[model]
        require(isinstance(rows, list) and rows, "Missing saved persistent identifiers")
        require(all(value.get("entityName") == runtime["entityName"] and isinstance(value.get("storeIdentifier"), str) and value["storeIdentifier"] and isinstance(value.get("encodedBase64"), str) and value["encodedBase64"] for value in rows), "Temporary or mismatched persisted identifiers")
    return result


def compare_runtime(names):
    reference = output / names[0] / "observations"
    schema = load(reference / "schema-canonical.json")
    snapshots = load(reference / "snapshots.json")
    identity_value = normalized_identity(load(reference / "runtimeidentity.json"))
    require(set(snapshots) == set(model_names) and all(isinstance(value, list) and value for value in snapshots.values()), "Every actual old model needs persisted fixture rows")
    schema_hashes = {}
    pids = []
    for name in names:
        directory = output / name
        observed = load(directory / "observations/observation.json")
        pids.append(observed["hostPID"])
        require(load(directory / "host-exit.json")["observedExited"] is True, "Host exit evidence missing")
        actual = directory / "observations"
        require(load(actual / "schema-canonical.json") == schema, "Normalized actual runtime schema changed")
        require(load(actual / "snapshots.json") == snapshots == load(actual / "expected-snapshots.json"), "Old stored values or exact string bytes changed")
        require(load(actual / "runtimeidentity.json")["schemaRawSHA256"] == digest((actual / "schema-raw.json").read_bytes()), "Raw schema file does not match its actual runtime digest")
        require(normalized_identity(load(actual / "runtimeidentity.json")) == identity_value, "Actual module, entities, persistent identifiers or store groups changed")
        schema_hashes[name] = {"raw_sha256": digest((actual / "schema-raw.json").read_bytes()), "canonical_sha256": digest((actual / "schema-canonical.json").read_bytes()), "snapshots_sha256": digest((actual / "snapshots.json").read_bytes())}
    require(len(set(pids)) == len(names), "Each phase must run in a separate host process")
    return {"phases": names, "distinct_host_pids": pids, "runtime_schema_and_all_old_values_equal": True, "schema_hashes": schema_hashes}


def prepare():
    require(not output.exists() and not predecessor.exists() and not packages.exists(), "Refusing to reuse a prior run's evidence, predecessor or package checkout")
    output.mkdir()
    (output / "stores").mkdir()
    require(not normal_support.exists(), "Fresh disposable user required; normal app support already exists before any host initialization")
    require(not (Path.home() / "Library/Preferences" / (bundle_id + ".plist")).exists(), "Fresh disposable user required; app preferences already exist")
    write(output / "disposable-user.json", {"uid": os.getuid(), "username": subprocess.check_output(["id", "-un"], text=True).strip(), "console_uid": int(subprocess.check_output(["stat", "-f", "%u", "/dev/console"], text=True)), "home": str(Path.home()), "runner_name": os.environ.get("RUNNER_NAME"), "run_id": os.environ.get("GITHUB_RUN_ID"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"), "normal_support_before_any_host": inventory(), "limits": "Normal app Application Support will be opened by actual app initialization. No user-store isolation claim; this is a fresh disposable Actions user."})
    subprocess.run(["git", "-C", str(repo), "diff", "--quiet", "HEAD", "--", *product_roots, *helper_paths], check=True)
    require(not git(repo, "ls-files", "--others", "--exclude-standard", "-z", "--", *product_roots, *helper_paths), "All product, oracle and helper bytes must be committed")
    for revision in [old_sha, tag_sha]:
        subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "origin", revision], check=True)
    bridge = source_bridge()
    subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(predecessor), old_sha], check=True)
    require(not (predecessor / oracle_path).exists(), "Oracle would overwrite historical source")
    (predecessor / oracle_path).write_bytes((repo / oracle_path).read_bytes())
    require(declarations(predecessor) == declarations(repo), "Actual app project or dependency declarations differ")
    for checkout in [repo, predecessor]:
        require(digest((checkout / lock_path).read_bytes()) == lock_sha, "Both products must already contain the canonical package lock")
        pins = load(checkout / lock_path)["pins"]
        require(len(pins) == 41 and len({pin["identity"] for pin in pins}) == 41, "Canonical graph requires exactly 41 unique pins")
    for lane, checkout in [("predecessor", predecessor), ("candidate", repo)]:
        write(output / (lane + "-source.json"), manifest(checkout))
    write(output / "contract.json", {"version": 1, "source_sha": {"predecessor": old_sha, "candidate": git(repo, "rev-parse", "HEAD").decode().strip()}, "tag_sha": tag_sha, "source_bridge": bridge, "oracle_path": oracle_path, "oracle_sha256": digest((repo / oracle_path).read_bytes()), "helpers": {path: digest((repo / path).read_bytes()) for path in helper_paths}, "declarations": declarations(repo), "canonical_lock_sha256": lock_sha, "canonical_package_pins": 41, "product_source_roots": product_roots, "test_identifier": test_id, "scope": "Actual predecessor persistent seed, separate predecessor reopen and unchanged-schema current read. No production/schema changes, future metadata migration, CloudKit sync, user-store copy, audio, recognition or provider call."})
    (output / "common-oracle.swift").write_bytes((repo / oracle_path).read_bytes())
    (output / "canonical.Package.resolved").write_bytes((repo / lock_path).read_bytes())
    write(output / "toolchain.json", {"xcode": subprocess.check_output(["xcodebuild", "-version"], text=True), "swift": subprocess.check_output(["swift", "--version"], text=True), "macOS": subprocess.check_output(["sw_vers"], text=True), "sdk_path": subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip(), "sdk_version": subprocess.check_output(["xcrun", "--show-sdk-version"], text=True).strip(), "metal": subprocess.check_output(["xcrun", "metal", "--version"], text=True, stderr=subprocess.STDOUT), "runner_arch": os.environ.get("RUNNER_ARCH")})
    seed_defaults()
    for lane in ["predecessor", "candidate"]:
        verify_sources(lane)


def dependencies():
    for lane in ["predecessor", "candidate"]:
        verify_sources(lane)
    before = whisper_source()
    write(output / "whisper-before-setup.json", before)
    write(output / "framework-before-setup.json", {"exists": framework.exists(), "tree": tree(framework) if framework.exists() else None})
    write(output / "setup-source-before.json", {path: digest((repo / path).read_bytes()) for path in ["Makefile", "scripts/verify-static-whisper-xcframework.sh"]})
    run(["make", "setup"], output / "dependencies-setup.log")
    run(["bash", "scripts/verify-static-whisper-xcframework.sh", str(framework)], output / "dependencies-static-verification.log")
    state = dependency_state()
    write(output / "dependencies-frozen.json", state)
    write(output / "setup-source-after.json", {path: digest((repo / path).read_bytes()) for path in ["Makefile", "scripts/verify-static-whisper-xcframework.sh"]})
    require(load(output / "setup-source-before.json") == load(output / "setup-source-after.json"), "Setup source changed")
    if before["exists"]:
        require(before == state["whisper_source"], "Cached setup unexpectedly pulled or modified Whisper source; fresh run needed to review a changed dependency")
    for lane in ["predecessor", "candidate"]:
        checkout, _, arguments = build_arguments(lane)
        run(["xcodebuild", "-resolvePackageDependencies", *arguments], output / (lane + "-strict-packages.log"), checkout)
        verify_sources(lane)
    write(output / "packages-frozen.json", package_state())
    verify_dependencies()


def build(lane):
    directory = output / (lane + "-build")
    directory.mkdir()
    checkout, derived, arguments = build_arguments(lane)
    verify_sources(lane)
    verify_dependencies()
    run(["xcodebuild", "build-for-testing", *arguments, selector], directory / "build.log", checkout)
    verify_sources(lane)
    verify_dependencies()
    value = identity(derived)
    write(directory / "identity.json", value)
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", value["app_path"], str(directory / "actual-host.app.zip")], directory / "archive-host.log")
    for index, relative in enumerate(sorted(value["test_bundles"])):
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(derived / "Build/Products/Debug" / relative), str(directory / ("actual-tests-" + str(index) + ".xctest.zip"))], directory / ("archive-tests-" + str(index) + ".log"))
    write(directory / "binary-archives.json", {path.name: {"sha256": digest(path.read_bytes()), "bytes": path.stat().st_size} for path in sorted(directory.glob("*.zip"))})
    run(["bash", str(checkout / "scripts/verify-static-whisper-app.sh"), value["app_path"]], directory / "static-app.log", checkout)
    run(["bash", str(checkout / "scripts/verify-adhoc-library-validation.sh"), value["app_path"]], directory / "adhoc-app.log", checkout)


def old_control():
    build("predecessor")
    seed = output / "stores/seed"
    phase("predecessor", "seed", seed)
    write(output / "seed-closed-tree.json", store_tree(seed))
    for path in [*seed.rglob("*"), seed]:
        path.chmod(0o500 if path.is_dir() else 0o400)
    write(output / "seed-readonly.json", {"path": str(seed), "entries": {str(path.relative_to(seed)): oct(path.stat().st_mode & 0o777) for path in [seed, *sorted(seed.rglob("*"))]}, "closedOriginalReadOnly": True})
    clone_seed(output / "stores/old-reopen", "old-reopen")
    phase("predecessor", "old-reopen", output / "stores/old-reopen")
    seed_unchanged()
    result = compare_runtime(["seed", "old-reopen"])
    write(output / "predecessor-checkpoint.json", dict(result, classification="predecessor-seed-and-reopen-passed", original_seed_immutable=True, candidate_not_built=True))


def candidate_control():
    require(load(output / "predecessor-checkpoint.json")["classification"] == "predecessor-seed-and-reopen-passed", "Old-product seed and reopen control must pass first")
    seed_unchanged()
    build("candidate")
    clone_seed(output / "stores/current-read", "current-read")
    phase("candidate", "current-read", output / "stores/current-read")
    seed_unchanged()


def verify():
    for lane in ["predecessor", "candidate"]:
        verify_sources(lane)
        require(identity(build_arguments(lane)[1]) == load(output / (lane + "-build/identity.json")), "Retained app/test identity changed")
    verify_dependencies()
    seed_unchanged()
    for name in ["seed", "old-reopen", "current-read"]:
        directory = output / name
        retained = load(directory / "result.json")
        require(retained == classify((directory / "tests.log").read_text(errors="replace"), int((directory / "test-exit.txt").read_text())) and retained["valid"], "Retained test classifier is invalid")
        observed = load(directory / "observations/observation.json")
        require(not alive(observed["hostPID"]), "An exact phase PID is live again; final fixture access refused")
        require(store_tree(output / "stores" / name) == load(directory / "closed-store-tree.json"), "Closed fixture changed after phase")
    result = compare_runtime(["seed", "old-reopen", "current-read"])
    write(output / "result.json", dict(result, classification="unchanged-schema-seed-control-passed", source_sha=load(output / "contract.json")["source_sha"], original_seed_immutable=True, limits=["Prerequisite control only. No new fields or schema migration have been tested.", "Actual app initialization opened fresh normal Application Support stores; inventories retained.", "Explicit local fixtures disable CloudKit; no deployed CloudKit schema, real user store, audio or provider call tested."]))


def self_test():
    subprocess.run(["python3", str(repo / "scripts/tests/dictation-store-source-inventory.test.py")], check=True)
    good = "Test " + test_name + "() started.\nTest " + test_name + "() passed after 0.1 seconds.\nTest run with 1 test in 1 suite passed\n"
    require(classify(good, 0)["valid"], "Valid exact selected test rejected")
    invalid = [good.replace("started.", "not started."), good.replace("passed after", "skipped after"), good.replace("1 test in", "0 tests in"), good + "Test other() started.\n", good + "Test " + test_name + "() recorded an issue: setup failed\n", good.replace("1 suite passed", "1 suite failed"), good + good]
    require(all(not classify(value, 0)["valid"] for value in invalid) and not classify(good, 65)["valid"], "Invalid exact test classification accepted")
    metadata = {"_type": {"_name": "ActionTestMetadata"}, "identifier": {"_value": "VoiceInkTests/" + test_name + "()"}, "testStatus": {"_value": "Success"}}
    require(metadata_rows({"summaries": {"_values": [metadata]}}) == [{"identifier": "VoiceInkTests/" + test_name + "()", "status": "Success"}], "Native result recursion failed")
    with tempfile.TemporaryDirectory(prefix="rjt-store-seed-self-test-") as temporary:
        root = Path(temporary)
        seed = root / "seed"
        seed.mkdir()
        for name in ["default", "dictionary", "stats"]:
            (seed / (name + ".store")).write_bytes((name + " fixture").encode())
            (seed / (name + ".store-wal")).write_bytes(b"closed WAL fixture")
            (seed / (name + ".store-shm")).write_bytes(b"closed SHM fixture")
        before = store_tree(seed)
        destination = root / "clone"
        shutil.copytree(seed, destination)
        require(store_tree(destination) == before, "Whole-directory copy lost a WAL/SHM entry")
        (destination / "default.store-wal").write_bytes(b"changed")
        require(store_tree(destination) != before and store_tree(seed) == before, "Manifest failed to detect changed clone or preserve seed")
    print(json.dumps({"classification": "offline-driver-self-test-passed", "invalid_log_cases": len(invalid) + 1, "scope": "Classifier, native-result traversal and whole-directory checksum/copy only. No app, SwiftData or runtime proof."}))


try:
    if mode == "self-test":
        self_test()
    elif mode == "prepare":
        prepare()
    elif mode == "dependencies":
        dependencies()
    elif mode == "predecessor":
        old_control()
    elif mode == "candidate":
        candidate_control()
    elif mode == "verify":
        verify()
    else:
        raise RuntimeError("usage: run-dictation-store-seed-check.sh prepare | dependencies | predecessor | candidate | verify | self-test")
except BaseException as error:
    if output.is_dir() and mode != "self-test":
        (output / ("failure-" + mode + ".json")).write_text(json.dumps({"classification": "invalid-or-failed", "mode": mode, "error": str(error)}, indent=2) + "\n")
    raise
PY
