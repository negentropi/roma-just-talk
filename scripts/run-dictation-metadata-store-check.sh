#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run this metadata store check only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
    echo "The metadata store check must own the disposable console user." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/dictation-metadata-store-proof" "${1:-}" <<'PY'
import ast
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
baseline = "f25fc0ff38b5ca20a686b2eb359e76ea6e7f8626"
baseline_path = "scripts/run-dictation-store-seed-check.sh"
baseline_hash = "5847555fe80cf6fb3740e562b919882cb9f0541c3bf497d6f16997c98fd42fc5"
old_sha = "ebc92f1e60fdabbb9e26b2817f414d154865a9d5"
tag_sha = "846d05df04d5821a7b5dc8588304cb58e3bd8368"
lock_path = "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
lock_sha = "bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f"
oracle_path = "VoiceInkTests/DictationStoreSeedLiveTests.swift"
metadata_oracle_path = "VoiceInkTests/DictationMetadataStoreLiveTests.swift"
helper_paths = ["scripts/run-dictation-metadata-store-check.sh", ".github/workflows/voiceink-dictation-metadata-store-check.yml"]
product_roots = ["VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "VoiceInkTests", "VoiceInkUITests", "iOS", "Makefile", "LocalBuild.xcconfig"]
model_names = ["Transcription", "VocabularyWord", "WordReplacement", "SessionMetric"]
model_paths = ["VoiceInk/Models/" + name + ".swift" for name in model_names]
new_fields = {"recognitionText", "dictationProfileRawValue", "clarityStyleRawValue", "processingFailureReason"}
new_ids = ["77777777-7777-4777-8777-777777777777", "88888888-8888-4888-8888-888888888888", "99999999-9999-4999-8999-999999999999"]
bundle_id = "com.negentropi.RomaJustTalk"
predecessor = output.parent / "dictation-metadata-store-predecessor"
packages = output.parent / "dictation-metadata-store-packages"
whisper = Path.home() / "VoiceInk-Dependencies/whisper.cpp"
framework = whisper / "build-apple/whisper.xcframework"
normal_support = Path.home() / "Library/Application Support" / bundle_id
common_test = "liveDictationPersistentStoreSeedControl"
metadata_test = "liveDictationMetadataPersistentStoreUpgrade"
phases = ["seed", "old-reopen", "metadata-write", "metadata-reopen"]

shared_names = {
    "require", "digest", "load", "write", "git", "gitlink_source", "tracked_sources", "run", "tree", "store_tree",
    "manifest", "declarations", "whisper_source", "dependency_state", "package_state", "verify_dependencies",
    "identity", "provision", "inventory", "seed_defaults", "live_executable", "alive", "wait_closed", "run_host",
    "seed_unchanged", "clone_seed", "normalized_identity", "metadata_rows", "dependencies"
}
shared_source = subprocess.check_output(["git", "-C", str(repo), "show", baseline + ":" + baseline_path])
if hashlib.sha256(shared_source).hexdigest() != baseline_hash:
    raise RuntimeError("The proven shared runtime source changed")
shared_block = shared_source.decode().split("<<'PY'\n", 1)[1].rsplit("\nPY\n", 1)[0]
shared_ast = ast.parse(shared_block, filename=baseline + ":" + baseline_path)
shared_nodes = [node for node in shared_ast.body if isinstance(node, ast.FunctionDef) and node.name in shared_names]
if sorted(node.name for node in shared_nodes) != sorted(shared_names):
    raise RuntimeError("A shared runtime owner function is missing or duplicated")
shared_receipt = {"commit": baseline, "path": baseline_path, "sha256": baseline_hash,
                  "functions": {node.name: hashlib.sha256(ast.get_source_segment(shared_block, node).encode()).hexdigest() for node in shared_nodes}}
exec(compile(ast.Module(body=shared_nodes, type_ignores=[]), baseline + ":" + baseline_path, "exec"), globals())


def spec(name):
    require(name in phases, "Unknown metadata store phase")
    candidate = name.startswith("metadata-")
    test_name = metadata_test if candidate else common_test
    return {"name": name, "lane": "candidate" if candidate else "predecessor", "test_name": test_name,
            "test_id": "VoiceInkTests/VoiceInkTests/" + test_name + "()",
            "source_path": metadata_oracle_path if candidate else oracle_path}


def classify(text, exit_code, test_name):
    starts = re.findall(r"\bTest (\w+)\(\) started\.", text)
    results = re.findall(r"\bTest (\w+)\(\) (passed|failed|skipped) after ", text)
    summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
    issues = re.findall(r"^.*\brecorded an issue\b[^\n]*", text, re.M)
    valid = exit_code == 0 and starts == [test_name] and results == [(test_name, "passed")] and summaries == [("1", "passed")] and not issues
    return {"valid": valid, "exit_code": exit_code, "starts": starts, "results": [list(row) for row in results], "summaries": [list(row) for row in summaries], "issues": issues}


def build_arguments(lane):
    checkout = predecessor if lane == "predecessor" else repo
    derived = output.parent / ("dictation-metadata-store-derived-" + lane)
    return checkout, derived, [
        "-project", str(checkout / "VoiceInk.xcodeproj"), "-scheme", "VoiceInk", "-configuration", "Debug",
        "-destination", "platform=macOS", "-parallel-testing-enabled", "NO", "-derivedDataPath", str(derived),
        "-xcconfig", str(checkout / "LocalBuild.xcconfig"), "-clonedSourcePackagesDirPath", str(packages),
        "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile", "-skipPackageUpdates",
        "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=YES", "DEVELOPMENT_TEAM=",
        "ENABLE_PREVIEWS=NO", "ENABLE_XOJIT_PREVIEWS=NO", "ENABLE_HARDENED_RUNTIME=YES",
        "CODE_SIGN_ENTITLEMENTS=" + str(checkout / "VoiceInk/VoiceInk.local.entitlements"),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD"
    ]


def source_bridge():
    require(git(repo, "rev-parse", "v1.95.1^{commit}").decode().strip() == tag_sha, "Historical tag moved")
    values = {}
    for revision in [tag_sha, old_sha, "HEAD"]:
        sources = {path: git(repo, "show", revision + ":" + path) for path in model_paths}
        app = git(repo, "show", revision + ":VoiceInk/VoiceInk.swift").decode()
        start = "    private static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {"
        end = "    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {"
        require(app.count(start) == app.count(end) == 1, "Persistent factory anchors changed")
        factory = app[app.index(start):app.index(end)]
        schemas = list(re.finditer(r"let schema = Schema\(\[([^\]]+)\]\)", app))
        require(len(schemas) == 1 and re.findall(r"(\w+)\.self", schemas[0].group(1)) == model_names, "Global schema order changed")
        project = git(repo, "show", revision + ":VoiceInk.xcodeproj/project.pbxproj").decode()
        require(project.count("PRODUCT_MODULE_NAME = VoiceInk;") == 2, "Actual product module changed")
        declarations = re.findall(r"^    var (\w+): ([^\n{]+)$", sources[model_paths[0]].decode(), re.M)
        values[revision] = {"models": {path: digest(data) for path, data in sources.items()}, "factory_sha256": digest(factory.encode()),
                            "global_schema_constructor_sha256": digest(schemas[0].group(0).encode()), "module": "VoiceInk", "transcription_stored_declarations": [list(row) for row in declarations]}
        (output / ("factory-" + revision.replace("HEAD", "candidate") + ".swift")).write_text(factory)
    require(values[tag_sha] == values[old_sha], "Historical tag and predecessor model/factory/module bridge differs")
    old, current = values[old_sha], values["HEAD"]
    require(all(current[key] == old[key] for key in ["factory_sha256", "global_schema_constructor_sha256", "module"]), "Current factory/schema order/module changed")
    require(all(current["models"][path] == old["models"][path] for path in model_paths[1:]), "An unrelated stored model changed")
    added = [[name, "String?"] for name in ["recognitionText", "dictationProfileRawValue", "clarityStyleRawValue", "processingFailureReason"]]
    require(current["transcription_stored_declarations"] == old["transcription_stored_declarations"] + added, "Current stored declaration delta must be exactly four optional String fields")
    return values


def verify_sources(lane):
    contract = load(output / "contract.json")
    checkout = predecessor if lane == "predecessor" else repo
    require(git(checkout, "rev-parse", "HEAD").decode().strip() == contract["source_sha"][lane], "Pinned source revision changed")
    require(manifest(checkout) == load(output / (lane + "-source.json")), "Actual product/test source bytes changed")
    untracked = {os.fsdecode(path) for path in git(checkout, "ls-files", "--others", "--exclude-standard", "-z", "--", *product_roots).split(b"\0") if path}
    require(untracked == ({oracle_path} if lane == "predecessor" else set()), "Unexpected untracked product/test source")
    require(digest((checkout / oracle_path).read_bytes()) == contract["oracle_sha256"], "Common source-compatible oracle changed")
    require(digest((checkout / lock_path).read_bytes()) == lock_sha and declarations(checkout) == contract["declarations"], "Pinned package/build declarations changed")
    require(shared_receipt == contract["shared_runtime"], "Shared runtime owner functions changed")
    require(all(digest((repo / path).read_bytes()) == value for path, value in contract["helpers"].items()), "Metadata verification helper changed")


def prepare():
    require(not output.exists() and not predecessor.exists() and not packages.exists(), "Refusing to reuse a prior metadata run")
    output.mkdir()
    (output / "stores").mkdir()
    require(not normal_support.exists() and not (Path.home() / "Library/Preferences" / (bundle_id + ".plist")).exists(), "Fresh disposable app support and preferences required")
    write(output / "disposable-user.json", {"uid": os.getuid(), "username": subprocess.check_output(["id", "-un"], text=True).strip(), "console_uid": int(subprocess.check_output(["stat", "-f", "%u", "/dev/console"], text=True)), "home": str(Path.home()), "run_id": os.environ.get("GITHUB_RUN_ID"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"), "normal_support_before_any_host": inventory()})
    subprocess.run(["git", "-C", str(repo), "diff", "--quiet", "HEAD", "--", *product_roots, *helper_paths], check=True)
    require(not git(repo, "ls-files", "--others", "--exclude-standard", "-z", "--", *product_roots, *helper_paths), "Product/oracles/helpers must be committed")
    for revision in [old_sha, tag_sha, baseline]:
        subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "origin", revision], check=True)
    bridge = source_bridge()
    subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(predecessor), old_sha], check=True)
    require(not (predecessor / oracle_path).exists(), "Refusing to overwrite historical oracle source")
    (predecessor / oracle_path).write_bytes((repo / oracle_path).read_bytes())
    require(declarations(predecessor) == declarations(repo), "Actual build/dependency declarations differ between products")
    for lane, checkout in [("predecessor", predecessor), ("candidate", repo)]:
        require(digest((checkout / lock_path).read_bytes()) == lock_sha, "Canonical lock bytes changed")
        pins = load(checkout / lock_path)["pins"]
        require(len(pins) == len({pin["identity"] for pin in pins}) == 41, "Canonical graph must contain 41 unique pins")
        write(output / (lane + "-source.json"), manifest(checkout))
    write(output / "contract.json", {"version": 1, "source_sha": {"predecessor": old_sha, "candidate": git(repo, "rev-parse", "HEAD").decode().strip()}, "tag_sha": tag_sha, "source_bridge": bridge, "shared_runtime": shared_receipt,
          "oracle_sha256": digest((repo / oracle_path).read_bytes()), "metadata_oracle_sha256": digest((repo / metadata_oracle_path).read_bytes()), "helpers": {path: digest((repo / path).read_bytes()) for path in helper_paths}, "declarations": declarations(repo), "canonical_lock_sha256": lock_sha, "canonical_package_pins": 41,
          "phases": [spec(name) for name in phases], "new_fields": sorted(new_fields), "new_record_ids": new_ids, "scope": "Fresh actual old seed/reopen, candidate four-optional-field upgrade and explicit new-row save, separate candidate reopen of the same clone. No profile activation, CloudKit, real user store or provider proof."})
    (output / "common-oracle.swift").write_bytes((repo / oracle_path).read_bytes())
    (output / "metadata-oracle.swift").write_bytes((repo / metadata_oracle_path).read_bytes())
    (output / "canonical.Package.resolved").write_bytes((repo / lock_path).read_bytes())
    write(output / "toolchain.json", {"xcode": subprocess.check_output(["xcodebuild", "-version"], text=True), "swift": subprocess.check_output(["swift", "--version"], text=True), "macOS": subprocess.check_output(["sw_vers"], text=True), "sdk_path": subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip(), "sdk_version": subprocess.check_output(["xcrun", "--show-sdk-version"], text=True).strip(), "metal": subprocess.check_output(["xcrun", "metal", "--version"], text=True, stderr=subprocess.STDOUT), "runner_arch": os.environ.get("RUNNER_ARCH")})
    seed_defaults()
    for lane in ["predecessor", "candidate"]:
        verify_sources(lane)


def build(lane):
    directory = output / (lane + "-build")
    directory.mkdir()
    checkout, derived, arguments = build_arguments(lane)
    selected = spec("seed" if lane == "predecessor" else "metadata-write")
    verify_sources(lane)
    verify_dependencies()
    run(["xcodebuild", "build-for-testing", *arguments, "-only-testing:" + selected["test_id"]], directory / "build.log", checkout)
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


def native_result(directory, selected):
    bundle = directory / "Test.xcresult"
    def get(arguments, name):
        data = subprocess.check_output(["xcrun", "xcresulttool", "get", "object", "--legacy", "--path", str(bundle), "--format", "json", *arguments])
        (directory / name).write_bytes(data)
        return json.loads(data)
    root = get([], "xcresult-root.json")
    refs = [action.get("actionResult", {}).get("testsRef", {}).get("id", {}).get("_value") for action in root.get("actions", {}).get("_values", [])]
    require(len(refs) == 1 and isinstance(refs[0], str), "Exactly one native test action required")
    rows = metadata_rows(get(["--id", refs[0]], "xcresult-tests.json"))
    require(len(rows) == 1 and rows[0]["identifier"] in [selected["test_id"], selected["test_id"].removeprefix("VoiceInkTests/")] and rows[0]["status"] == "Success", "Selected native test did not pass exactly once")
    write(directory / "native-result.json", {"valid": True, "test_action_id": refs[0], "tests": rows})
    run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", str(directory / "attachments")], directory / "export-attachments.log")


def phase(name, fixture):
    selected = spec(name)
    lane = selected["lane"]
    verify_sources(lane)
    verify_dependencies()
    directory = output / name
    observations = directory / "observations"
    observations.mkdir(parents=True)
    checkout, derived, arguments = build_arguments(lane)
    before = identity(derived)
    require(before == load(output / (lane + "-build/identity.json")), "Phase host differs from frozen build")
    write(directory / "identity-before.json", before)
    provision(directory, before)
    settings = {"RJT_DICTATION_STORE_SEED_CHECKS": "1" if lane == "predecessor" else "0", "RJT_DICTATION_METADATA_STORE_CHECKS": "1" if lane == "candidate" else "0", "GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted", "RJT_STORE_PHASE": name, "RJT_STORE_FIXTURE": str(fixture), "RJT_STORE_EVIDENCE": str(observations), "RJT_STORE_SOURCE_SHA": load(output / "contract.json")["source_sha"][lane], "RJT_STORE_RUN_ROOT": str(output), "RJT_STORE_EXPECTED_EXE": before["executable_path"]}
    environment = dict(os.environ, **settings, **{"TEST_RUNNER_" + key: value for key, value in settings.items()})
    selection = directory / "selection"
    selection.mkdir()
    write(directory / "normal-support-before-enumeration.json", inventory())
    selector = "-only-testing:" + selected["test_id"]
    run(["xcodebuild", "test-without-building", *arguments, selector, "-enumerate-tests", "-test-enumeration-style", "flat", "-test-enumeration-format", "json", "-test-enumeration-output-path", str(selection / "tests.json")], selection / "enumeration.log", checkout, environment)
    enumerated = load(selection / "tests.json")
    enabled = [test.get("identifier") for plan in enumerated.get("values", []) for test in plan.get("enabledTests", [])]
    disabled = [test.get("identifier") for plan in enumerated.get("values", []) for test in plan.get("disabledTests", [])]
    require(not enumerated.get("errors") and enabled == [selected["test_id"]] and selected["test_id"] not in disabled, "Exact enabled phase selection did not resolve")
    write(selection / "receipt.json", {"valid": True, "enabled": enabled, "disabled": disabled})
    write(directory / "normal-support-after-enumeration.json", inventory())
    write(directory / "normal-support-before.json", inventory())
    code, observed = run_host(directory, ["xcodebuild", "test-without-building", *arguments, selector, "-resultBundlePath", str(directory / "Test.xcresult")], checkout, environment, before["executable_path"])
    write(directory / "normal-support-after.json", inventory())
    classified = classify((directory / "tests.log").read_text(errors="replace"), code, selected["test_name"])
    (directory / "test-exit.txt").write_text(str(code) + "\n")
    write(directory / "result.json", classified)
    require(classified["valid"], "Exact hosted phase did not execute once and pass: " + name)
    require(type(observed.get("version")) is int and observed["version"] == 1 and observed.get("classification") == "passed" and observed.get("testName") == selected["test_name"] and observed.get("phase") == name and observed.get("sourceSHA") == settings["RJT_STORE_SOURCE_SHA"] and observed.get("sourcePath") == str(checkout / selected["source_path"]) and observed.get("fixturePath") == str(fixture) and observed.get("bundleIdentifier") == bundle_id and observed.get("normalSupportPath") == str(normal_support), "Actual host observation identifies the wrong phase/source/path")
    for filename in ["schema-raw.json", "schema-canonical.json", "snapshots.json", "expected-snapshots.json", "runtimeidentity.json"] + (["metadata-records.json", "expected-metadata-records.json", "metadata-identifiers.json", "metadata-observation.json"] if lane == "candidate" else []):
        require((observations / filename).is_file(), "Missing actual phase artifact: " + filename)
    after = identity(derived)
    write(directory / "identity-after.json", after)
    require(before == after, "Signed host/test bundle changed during phase")
    native_result(directory, selected)
    verify_sources(lane)
    verify_dependencies()
    write(directory / "closed-store-tree.json", store_tree(fixture))


def entity_map(schema):
    require(isinstance(schema, dict) and isinstance(schema.get("entities"), list), "Schema entities missing")
    values = schema["entities"]
    require(len(values) == 4 and all(isinstance(row, dict) and isinstance(row.get("name"), str) for row in values), "Wrong schema entity shape/count")
    mapped = {row["name"]: row for row in values}
    require(set(mapped) == set(model_names), "Duplicate, missing or unexpected schema entity")
    return mapped


def attribute_map(entity, key):
    rows = entity.get(key)
    require(isinstance(rows, list) and all(isinstance(row, dict) and isinstance(row.get("name"), str) for row in rows), "Wrong attribute collection")
    mapped = {row["name"]: row for row in rows}
    require(len(rows) == len(mapped), "Duplicate attribute identity")
    return mapped


def same_json(left, right):
    encode = lambda value: json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False)
    return encode(left) == encode(right)


def schema_delta(old, current):
    old_entities, current_entities = entity_map(old), entity_map(current)
    require(same_json({key: value for key, value in old.items() if key != "entities"}, {key: value for key, value in current.items() if key != "entities"}), "Top-level schema metadata changed")
    for name in model_names:
        before, after = old_entities[name], current_entities[name]
        require({"attributes", "storedAttributes"}.issubset(before), "Historical attribute collections missing")
        old_public = attribute_map(before, "attributes")
        old_stored = attribute_map(before, "storedAttributes")
        require(same_json(old_public, old_stored) and len(old_public) == {"Transcription": 16, "VocabularyWord": 2, "WordReplacement": 5, "SessionMetric": 12}[name], "Historical schema attribute count or identity changed")
        if name != "Transcription":
            require(same_json(before, after), "Unrelated entity metadata changed: " + name)
            continue
        require(set(before) == set(after), "Transcription entity metadata keys changed")
        template = attribute_map(before, "attributes")["enhancedText"]
        require(template["isOptional"] is True and template["valueTypeName"] == "SSSg", "Historical optional String schema template changed")
        for key in before:
            if key not in ["attributes", "storedAttributes"]:
                require(same_json(before[key], after[key]), "Transcription non-attribute metadata/order changed: " + key)
                continue
            old_attributes, current_attributes = attribute_map(before, key), attribute_map(after, key)
            require(set(current_attributes) == set(old_attributes) | new_fields and not new_fields.intersection(old_attributes), "Schema delta is not exactly four new attributes")
            require(all(same_json(current_attributes[field], dict(template, name=field)) for field in new_fields), "New attributes must be exactly nullable String with unchanged default/options/hash metadata")
            require(all(same_json(current_attributes[field], value) for field, value in old_attributes.items()), "Historical attribute metadata changed")
    return {"validated_new_fields": sorted(new_fields), "type": "String?", "collections": ["attributes", "storedAttributes"], "all_other_schema_values_and_order_preserved": True}


def runtime_comparison(names):
    old = output / "seed/observations"
    old_schema = load(old / "schema-canonical.json")
    old_snapshots = load(old / "snapshots.json")
    old_identity = normalized_identity(load(old / "runtimeidentity.json"))
    old_identity.pop("schemaCanonicalSHA256")
    pids, hashes = [], {}
    candidate_schema = None
    for name in names:
        directory = output / name
        actual = directory / "observations"
        observation = load(actual / "observation.json")
        pids.append(observation["hostPID"])
        require(load(directory / "host-exit.json")["observedExited"] is True, "Exact host exit evidence missing")
        schema = load(actual / "schema-canonical.json")
        require(same_json(load(actual / "snapshots.json"), old_snapshots) and same_json(old_snapshots, load(actual / "expected-snapshots.json")), "Historical 35 stored field values or exact string bytes changed")
        identity_value = load(actual / "runtimeidentity.json")
        require(identity_value["schemaRawSHA256"] == digest((actual / "schema-raw.json").read_bytes()), "Actual raw schema digest mismatch")
        normalized = normalized_identity(identity_value)
        normalized.pop("schemaCanonicalSHA256")
        require(same_json(normalized, old_identity), "Actual legacy persistent identifiers/module/entities/store groups changed")
        if name in ["seed", "old-reopen"]:
            require(same_json(schema, old_schema), "Same-old-app schema control changed")
        else:
            schema_delta(old_schema, schema)
            if candidate_schema is None:
                candidate_schema = schema
            require(same_json(schema, candidate_schema), "Candidate schema changed between write and reopen")
        hashes[name] = {"raw_schema_sha256": digest((actual / "schema-raw.json").read_bytes()), "canonical_schema_sha256": digest((actual / "schema-canonical.json").read_bytes()), "legacy_snapshots_sha256": digest((actual / "snapshots.json").read_bytes())}
    require(len(pids) == len(set(pids)), "Every phase must have a separate actual host PID")
    return {"phases": names, "distinct_host_pids": pids, "legacy_values_and_identifiers_equal": True, "schema_hashes": hashes}


def verify_metadata():
    reference = None
    legacy = load(output / "seed/observations/runtimeidentity.json")
    default_store = legacy["persistentIdentifiers"]["Transcription"][0]["storeIdentifier"]
    entity = legacy["models"][0]["entityName"]
    for name in ["metadata-write", "metadata-reopen"]:
        actual = output / name / "observations"
        records = load(actual / "metadata-records.json")
        identifiers = load(actual / "metadata-identifiers.json")
        require(same_json(records, load(actual / "expected-metadata-records.json")) and len(records) == 3 and [row["id"] for row in records] == new_ids and all(len(row) == 20 for row in records), "New metadata record values/count/identities differ")
        require(len(identifiers) == 3 and [row["recordID"] for row in identifiers] == new_ids and all(row["entityName"] == entity and row["storeIdentifier"] == default_store and isinstance(row["encodedBase64"], str) and row["encodedBase64"] for row in identifiers), "New saved identifiers are temporary or use the wrong store/entity")
        receipt = load(actual / "metadata-observation.json")
        write_phase = name == "metadata-write"
        require(type(receipt.get("version")) is int and receipt["version"] == 1 and receipt["phase"] == name and receipt["hostPID"] == load(actual / "observation.json")["hostPID"] and receipt["historicalRowCount"] == 2 and receipt["additionalRecordCount"] == 3, "Metadata receipt identifies the wrong rows/host")
        require(all(receipt[key] is True for key in ["historicalMetadataNil", "exactNewFieldValues", "unknownRawValuesPreservedWithoutRelabeling"]), "Metadata semantic checks did not pass")
        require(all(receipt[key] is write_phase for key in ["explicitSavePerformed", "readNilBeforeWrite", "canceledDraftMetadataCleared"]), "Metadata phase save/reopen boundary is wrong")
        value = {"records": records, "identifiers": identifiers}
        if reference is None:
            reference = value
        require(same_json(value, reference), "Fresh candidate reopen changed any new field or persistent identifier")
    return {"new_record_count": 3, "fields_per_new_record": 20, "new_values_and_identifiers_equal_after_reopen": True, "historical_new_metadata_nil": True}


def old_control():
    build("predecessor")
    seed = output / "stores/seed"
    phase("seed", seed)
    write(output / "seed-closed-tree.json", store_tree(seed))
    for path in [*seed.rglob("*"), seed]:
        path.chmod(0o500 if path.is_dir() else 0o400)
    write(output / "seed-readonly.json", {"path": str(seed), "entries": {str(path.relative_to(seed)): oct(path.stat().st_mode & 0o777) for path in [seed, *sorted(seed.rglob("*"))]}, "closedOriginalReadOnly": True})
    clone_seed(output / "stores/old-reopen", "old-reopen")
    phase("old-reopen", output / "stores/old-reopen")
    seed_unchanged()
    write(output / "predecessor-checkpoint.json", dict(runtime_comparison(["seed", "old-reopen"]), classification="predecessor-seed-and-reopen-passed", original_seed_immutable=True, candidate_not_built=True))


def candidate_control():
    require(load(output / "predecessor-checkpoint.json")["classification"] == "predecessor-seed-and-reopen-passed", "Actual old seed/reopen must pass first")
    build("candidate")
    fixture = output / "stores/metadata"
    clone_seed(fixture, "metadata-write")
    phase("metadata-write", fixture)
    checkpoint = store_tree(fixture)
    write(output / "metadata-write-closed-tree.json", checkpoint)
    retained = output / "stores/metadata-write-checkpoint"
    require(not retained.exists(), "Refusing to overwrite the closed metadata write checkpoint")
    shutil.copytree(fixture, retained, symlinks=False)
    require(store_tree(retained) == checkpoint == store_tree(fixture), "Complete closed metadata write copy differs")
    for path in [*retained.rglob("*"), retained]:
        path.chmod(0o500 if path.is_dir() else 0o400)
    write(output / "metadata-write-readonly.json", {"path": str(retained), "entries": {str(path.relative_to(retained)): oct(path.stat().st_mode & 0o777) for path in [retained, *sorted(retained.rglob("*"))]}, "closedCopyReadOnly": True})
    seed_unchanged()
    require(store_tree(fixture) == checkpoint, "Closed metadata write checkpoint changed before reopen")
    write(output / "metadata-reopen-before.json", store_tree(fixture))
    phase("metadata-reopen", fixture)
    seed_unchanged()


def verify():
    for lane in ["predecessor", "candidate"]:
        verify_sources(lane)
        require(identity(build_arguments(lane)[1]) == load(output / (lane + "-build/identity.json")), "Frozen signed app/test identity changed")
    verify_dependencies()
    seed_unchanged()
    for name in phases:
        directory = output / name
        selected = spec(name)
        require(load(directory / "result.json") == classify((directory / "tests.log").read_text(errors="replace"), int((directory / "test-exit.txt").read_text()), selected["test_name"]) and load(directory / "result.json")["valid"], "Retained phase classifier changed")
        observed = load(directory / "observations/observation.json")
        require(not alive(observed["hostPID"]), "An exact test host PID is live again")
        if name != "metadata-write":
            require(store_tree(Path(observed["fixturePath"])) == load(directory / "closed-store-tree.json"), "Closed phase fixture changed after completion")
    require(load(output / "metadata-reopen-before.json") == load(output / "metadata-write-closed-tree.json") == load(output / "metadata-write/closed-store-tree.json"), "Fresh reopen did not receive the complete exact closed write checkpoint")
    retained = output / "stores/metadata-write-checkpoint"
    require(store_tree(retained) == load(output / "metadata-write-closed-tree.json"), "Retained complete metadata write checkpoint changed")
    require({str(path.relative_to(retained)): oct(path.stat().st_mode & 0o777) for path in [retained, *sorted(retained.rglob("*"))]} == load(output / "metadata-write-readonly.json")["entries"], "Metadata write checkpoint read-only protection changed")
    require(load(output / "metadata-write/observations/observation.json")["fixturePath"] == load(output / "metadata-reopen/observations/observation.json")["fixturePath"], "Candidate reopen must read the same upgraded store clone")
    result = runtime_comparison(phases)
    result.update(verify_metadata())
    write(output / "result.json", dict(result, classification="actual-dictation-metadata-store-upgrade-passed", source_sha=load(output / "contract.json")["source_sha"], original_seed_immutable=True, limits=["Four local optional String attributes and explicit draft-adapter scalar persistence only.", "No profile activation, provider call, CloudKit sync, real user store, microphone inactivity or UI proof.", "Actual app initialization opened fresh normal Application Support and attempted recorder pre-roll on the disposable runner."]))


def self_test():
    source = repo / "docs/research/competitors/evidence/store-seed-40575066549/seed/observations/schema-canonical.json"
    old = load(source)
    candidate = copy.deepcopy(old)
    transcription = entity_map(candidate)["Transcription"]
    template = attribute_map(transcription, "attributes")["enhancedText"]
    for key in ["attributes", "storedAttributes"]:
        transcription[key].extend(dict(template, name=name) for name in sorted(new_fields))
    schema_delta(old, candidate)
    old_compare_nodes = [node for node in shared_ast.body if isinstance(node, ast.FunctionDef) and node.name == "compare_runtime"]
    require(len(old_compare_nodes) == 1, "Actual baseline schema comparator is missing")
    with tempfile.TemporaryDirectory(prefix="rjt-metadata-schema-controls-") as temporary:
        control = Path(temporary)
        actual = source.parents[2]
        for name in ["seed", "old-reopen"]:
            directory = control / name
            (directory / "observations").mkdir(parents=True)
            for filename in ["observation.json", "schema-canonical.json", "schema-raw.json", "snapshots.json", "expected-snapshots.json", "runtimeidentity.json"]:
                (directory / "observations" / filename).write_bytes((actual / name / "observations" / filename).read_bytes())
            (directory / "host-exit.json").write_bytes((actual / name / "host-exit.json").read_bytes())
        namespace = dict(globals(), output=control)
        exec(compile(ast.Module(body=old_compare_nodes, type_ignores=[]), baseline + ":" + baseline_path, "exec"), namespace)
        namespace["compare_runtime"](["seed", "old-reopen"])
        (control / "old-reopen/observations/schema-canonical.json").write_text(json.dumps(candidate))
        try:
            namespace["compare_runtime"](["seed", "old-reopen"])
        except RuntimeError as error:
            require(str(error) == "Normalized actual runtime schema changed", "Known-bad control failed at an unrelated boundary")
        else:
            raise RuntimeError("Actual old comparator accepted the four-field schema addition")
    try:
        schema_delta(old, old)
    except RuntimeError:
        pass
    else:
        raise RuntimeError("Missing new schema fields were accepted")
    mutations = {}
    def altered(name, operation):
        value = copy.deepcopy(candidate)
        operation(value)
        mutations[name] = value
    def field(value):
        return attribute_map(entity_map(value)["Transcription"], "storedAttributes")["recognitionText"]
    altered("unknown-field", lambda value: entity_map(value)["Transcription"]["storedAttributes"].append(dict(template, name="unknownField")))
    altered("missing-field", lambda value: entity_map(value)["Transcription"]["storedAttributes"].remove(field(value)))
    altered("wrong-type", lambda value: field(value).update(valueTypeName="SdSg"))
    altered("non-optional", lambda value: field(value).update(isOptional=False))
    altered("numeric-instead-of-bool", lambda value: field(value).update(isOptional=1))
    altered("new-default", lambda value: field(value).update(defaultValue="invented"))
    altered("old-field-default", lambda value: attribute_map(entity_map(value)["Transcription"], "attributes")["text"].update(defaultValue="invented"))
    altered("old-field-type", lambda value: attribute_map(entity_map(value)["Transcription"], "attributes")["text"].update(valueTypeName="Si"))
    altered("old-entity-metadata", lambda value: entity_map(value)["VocabularyWord"].update(hashModifier="changed"))
    altered("duplicate-field", lambda value: entity_map(value)["Transcription"]["attributes"].append(dict(template, name="recognitionText")))
    for name, value in mutations.items():
        try:
            schema_delta(old, value)
        except RuntimeError:
            continue
        raise RuntimeError("Invalid schema mutation accepted: " + name)
    for key in ["indices", "uniquenessConstraints", "futureOrderedMetadata"]:
        before, after = copy.deepcopy(old), copy.deepcopy(candidate)
        entity_map(before)["Transcription"][key] = [["text", "timestamp"], ["id", "duration"]]
        entity_map(after)["Transcription"][key] = copy.deepcopy(entity_map(before)["Transcription"][key])
        schema_delta(before, after)
        for inner in [False, True]:
            changed = copy.deepcopy(after)
            array = entity_map(changed)["Transcription"][key]
            (array[0] if inner else array).reverse()
            try:
                schema_delta(before, changed)
            except RuntimeError:
                continue
            raise RuntimeError("Ordered schema metadata change accepted")
    for test_name in [common_test, metadata_test]:
        text = "Test " + test_name + "() started.\nTest " + test_name + "() passed after 0.1 seconds.\nTest run with 1 test in 1 suite passed\n"
        require(classify(text, 0, test_name)["valid"], "Valid exact selected phase rejected")
        for changed in [text.replace("passed after", "skipped after"), text + text, text.replace("1 test in", "0 tests in"), text + "Test other() started.\n", text + "Test " + test_name + "() recorded an issue: failed\n"]:
            require(not classify(changed, 0, test_name)["valid"], "Invalid hosted phase log accepted")
        require(not classify(text, 65, test_name)["valid"], "Nonzero native test exit accepted")
    print(json.dumps({"classification": "offline-metadata-driver-controls-passed", "actual_old_comparator_accepts_native_control": True, "actual_old_comparator_rejects_synthetic_four_field_addition": True, "candidate_comparator_accepts_same_synthetic_addition": True, "invalid_schema_cases": len(mutations) + 1, "ordered_array_cases": 6, "shared_runtime": shared_receipt, "scope": "Actual pinned old comparator on retained native control files and synthetic four-field additions; rejected schema mutations and exact log classifiers. No native upgrade or persistence proof."}, sort_keys=True))


try:
    actions = {"self-test": self_test, "prepare": prepare, "dependencies": dependencies, "predecessor": old_control, "candidate": candidate_control, "verify": verify}
    require(mode in actions, "usage: run-dictation-metadata-store-check.sh self-test | prepare | dependencies | predecessor | candidate | verify")
    actions[mode]()
except BaseException as error:
    if output.is_dir() and mode != "self-test":
        (output / ("failure-" + mode + ".json")).write_text(json.dumps({"classification": "invalid-or-failed", "mode": mode, "error": str(error)}, indent=2) + "\n")
    raise
PY
