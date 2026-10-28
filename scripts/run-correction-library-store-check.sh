#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run this correction library store check only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" ]]; then
    echo "The correction library store check must own the disposable console user." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${RUNNER_TEMP:-/tmp}/correction-library-store-proof" "${1:-}" <<'PY'
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
old_sha = "ebf629b4cf109f7a36109ccac7b20ac70f9f48ab"
lock_path = "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
lock_sha = "bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f"
oracle_path = "VoiceInkTests/CorrectionLibraryStoreUpgradeLiveTests.swift"
common_oracle_path = "VoiceInkTests/DictationStoreSeedLiveTests.swift"
helper_paths = ["scripts/run-correction-library-store-check.sh", ".github/workflows/voiceink-correction-library-store-check.yml"]
product_roots = ["VoiceInk", "VoiceInkCore", "VoiceInkNVIDIA", "VoiceInkQwen", "VoiceInk.xcodeproj", "VoiceInkTests", "VoiceInkUITests", "iOS", "Makefile", "LocalBuild.xcconfig"]
model_names = ["Transcription", "VocabularyWord", "WordReplacement", "SessionMetric"]
model_paths = ["VoiceInk/Models/" + name + ".swift" for name in model_names]
new_field_types = {"matchingKindRawValue": "SSSg", "approvalOriginRawValue": "SSSg", "sourceTranscriptionID": "10Foundation4UUIDVSg", "sourceVariantRawValue": "SSSg", "literalOriginalText": "SSSg", "literalReplacementText": "SSSg"}
new_fields = set(new_field_types)
fixed_ids = ["AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB", "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"]
source_history_id = "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD"
old_field_counts = {"Transcription": 20, "VocabularyWord": 2, "WordReplacement": 5, "SessionMetric": 12}
bundle_id = "com.negentropi.RomaJustTalk"
predecessor = output.parent / "correction-library-store-predecessor"
packages = output.parent / "correction-library-store-packages"
whisper = Path.home() / "VoiceInk-Dependencies/whisper.cpp"
framework = whisper / "build-apple/whisper.xcframework"
normal_support = Path.home() / "Library/Application Support" / bundle_id
test_name = "liveCorrectionLibraryPersistentStoreUpgrade"
phases = ["seed", "old-reopen", "correction-write", "correction-reopen"]

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


metadata_baseline = "ebf629b4cf109f7a36109ccac7b20ac70f9f48ab"
metadata_path = "scripts/run-dictation-metadata-store-check.sh"
metadata_hash = "d3514de2d76b7163b3424bff4bd95580885cddc49ae5fcec5a999a063ca247a0"
metadata_source = subprocess.check_output(["git", "-C", str(repo), "show", metadata_baseline + ":" + metadata_path])
require(digest(metadata_source) == metadata_hash, "The proven neutral metadata runtime source changed")
metadata_block = metadata_source.decode().split("<<'PY'\n", 1)[1].rsplit("\nPY\n", 1)[0]
metadata_ast = ast.parse(metadata_block, filename=metadata_baseline + ":" + metadata_path)
neutral_names = {"classify", "native_result", "entity_map", "attribute_map", "same_json"}
neutral_nodes = [node for node in metadata_ast.body if isinstance(node, ast.FunctionDef) and node.name in neutral_names]
require(sorted(node.name for node in neutral_nodes) == sorted(neutral_names), "A neutral metadata owner function is missing or duplicated")
neutral_receipt = {"commit": metadata_baseline, "path": metadata_path, "sha256": metadata_hash,
                   "functions": {node.name: digest(ast.get_source_segment(metadata_block, node).encode()) for node in neutral_nodes}}
exec(compile(ast.Module(body=neutral_nodes, type_ignores=[]), metadata_baseline + ":" + metadata_path, "exec"), globals())


def spec(name):
    require(name in phases, "Unknown correction store phase")
    return {"name": name, "lane": "candidate" if name.startswith("correction-") else "predecessor",
            "test_name": test_name, "test_id": "VoiceInkTests/VoiceInkTests/" + test_name + "()", "source_path": oracle_path}


def build_arguments(lane):
    checkout = predecessor if lane == "predecessor" else repo
    derived = output.parent / ("correction-library-store-derived-" + lane)
    conditions = "$(inherited) LOCAL_BUILD" + (" CORRECTION_LIBRARY_CANDIDATE" if lane == "candidate" else "")
    return checkout, derived, [
        "-project", str(checkout / "VoiceInk.xcodeproj"), "-scheme", "VoiceInk", "-configuration", "Debug",
        "-destination", "platform=macOS", "-parallel-testing-enabled", "NO", "-derivedDataPath", str(derived),
        "-xcconfig", str(checkout / "LocalBuild.xcconfig"), "-clonedSourcePackagesDirPath", str(packages),
        "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile", "-skipPackageUpdates",
        "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=YES", "DEVELOPMENT_TEAM=",
        "ENABLE_PREVIEWS=NO", "ENABLE_XOJIT_PREVIEWS=NO", "ENABLE_HARDENED_RUNTIME=YES",
        "CODE_SIGN_ENTITLEMENTS=" + str(checkout / "VoiceInk/VoiceInk.local.entitlements"),
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=" + conditions
    ]


def source_bridge():
    values = {}
    for revision in [old_sha, "HEAD"]:
        sources = {path: git(repo, "show", revision + ":" + path) for path in model_paths}
        app = git(repo, "show", revision + ":VoiceInk/VoiceInk.swift").decode()
        start = "static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {"
        end = "    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {"
        require(app.count(start) == app.count(end) == 1, "Persistent factory anchors changed")
        factory = app[app.index(start):app.index(end)]
        schemas = list(re.finditer(r"let schema = Schema\(\[([^\]]+)\]\)", app))
        require(len(schemas) == 1 and re.findall(r"(\w+)\.self", schemas[0].group(1)) == model_names, "Global schema order changed")
        project = git(repo, "show", revision + ":VoiceInk.xcodeproj/project.pbxproj").decode()
        require(project.count("PRODUCT_MODULE_NAME = VoiceInk;") == 2, "Actual product module changed")
        stored = re.findall(r"^    var (\w+): ([^\n{]+)$", sources[model_paths[2]].decode(), re.M)
        values[revision] = {"models": {path: digest(data) for path, data in sources.items()}, "factory_sha256": digest(factory.encode()),
                            "global_schema_constructor_sha256": digest(schemas[0].group(0).encode()), "module": "VoiceInk", "word_replacement_stored_declarations": [list(row) for row in stored]}
        (output / ("factory-" + revision.replace("HEAD", "candidate") + ".swift")).write_text(factory)
    old, current = values[old_sha], values["HEAD"]
    require(all(current[key] == old[key] for key in ["factory_sha256", "global_schema_constructor_sha256", "module"]), "Current factory/schema order/module changed")
    require(all(current["models"][path] == old["models"][path] for path in [model_paths[0], model_paths[1], model_paths[3]]), "Transcription20 or an unrelated stored model changed")
    added = [[name, "UUID?" if name == "sourceTranscriptionID" else "String?"] for name in new_field_types]
    require(current["word_replacement_stored_declarations"] == old["word_replacement_stored_declarations"] + added, "Stored declaration delta must be exactly six optional WordReplacement fields")
    require(len(old["word_replacement_stored_declarations"]) == 5, "Actual predecessor WordReplacement must retain five stored fields")
    return values


def verify_sources(lane):
    contract = load(output / "contract.json")
    checkout = predecessor if lane == "predecessor" else repo
    require(git(checkout, "rev-parse", "HEAD").decode().strip() == contract["source_sha"][lane], "Pinned source revision changed")
    require(manifest(checkout) == load(output / (lane + "-source.json")), "Actual product/test source bytes changed")
    untracked = {os.fsdecode(path) for path in git(checkout, "ls-files", "--others", "--exclude-standard", "-z", "--", *product_roots).split(b"\0") if path}
    require(untracked == ({oracle_path} if lane == "predecessor" else set()), "Unexpected untracked product/test source")
    require(digest((checkout / oracle_path).read_bytes()) == contract["oracle_sha256"], "Source-compatible correction oracle changed")
    require(digest((checkout / common_oracle_path).read_bytes()) == contract["common_oracle_sha256"][lane], "Actual lane's tracked common oracle changed")
    require(digest((checkout / lock_path).read_bytes()) == lock_sha and declarations(checkout) == contract["declarations"], "Pinned package/build declarations changed")
    require(shared_receipt == contract["shared_runtime"] and neutral_receipt == contract["neutral_runtime"], "Pinned helper owner functions changed")
    require(all(digest((repo / path).read_bytes()) == value for path, value in contract["helpers"].items()), "Correction verification helper changed")


def prepare():
    require(not output.exists() and not predecessor.exists() and not packages.exists(), "Refusing to reuse a prior correction run")
    output.mkdir()
    (output / "stores").mkdir()
    require(not normal_support.exists() and not (Path.home() / "Library/Preferences" / (bundle_id + ".plist")).exists(), "Fresh disposable app support and preferences required")
    write(output / "disposable-user.json", {"uid": os.getuid(), "username": subprocess.check_output(["id", "-un"], text=True).strip(), "console_uid": int(subprocess.check_output(["stat", "-f", "%u", "/dev/console"], text=True)), "home": str(Path.home()), "run_id": os.environ.get("GITHUB_RUN_ID"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"), "normal_support_before_any_host": inventory()})
    subprocess.run(["git", "-C", str(repo), "diff", "--quiet", "HEAD", "--", *product_roots, *helper_paths], check=True)
    require(not git(repo, "ls-files", "--others", "--exclude-standard", "-z", "--", *product_roots, *helper_paths), "Product/oracles/helpers must be committed")
    for revision in [old_sha, baseline]:
        subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "origin", revision], check=True)
    bridge = source_bridge()
    subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(predecessor), old_sha], check=True)
    require(not (predecessor / oracle_path).exists(), "Refusing to overwrite historical oracle source")
    require((predecessor / common_oracle_path).is_file(), "Actual predecessor's tracked common oracle is missing")
    (predecessor / oracle_path).write_bytes((repo / oracle_path).read_bytes())
    require(declarations(predecessor) == declarations(repo), "Actual build/dependency declarations differ between products")
    common_hashes = {}
    for lane, checkout in [("predecessor", predecessor), ("candidate", repo)]:
        require(digest((checkout / lock_path).read_bytes()) == lock_sha, "Canonical lock bytes changed")
        pins = load(checkout / lock_path)["pins"]
        require(len(pins) == len({pin["identity"] for pin in pins}) == 41, "Canonical graph must contain 41 unique pins")
        common_hashes[lane] = digest((checkout / common_oracle_path).read_bytes())
        write(output / (lane + "-source.json"), manifest(checkout))
        (output / (lane + "-common-oracle.swift")).write_bytes((checkout / common_oracle_path).read_bytes())
    write(output / "contract.json", {"version": 1, "source_sha": {"predecessor": old_sha, "candidate": git(repo, "rev-parse", "HEAD").decode().strip()}, "source_bridge": bridge, "shared_runtime": shared_receipt, "neutral_runtime": neutral_receipt,
          "oracle_sha256": digest((repo / oracle_path).read_bytes()), "common_oracle_sha256": common_hashes, "helpers": {path: digest((repo / path).read_bytes()) for path in helper_paths}, "declarations": declarations(repo), "canonical_lock_sha256": lock_sha, "canonical_package_pins": 41,
          "phases": [spec(name) for name in phases], "new_field_types": new_field_types, "fixed_record_ids": fixed_ids, "source_history_id": source_history_id, "scope": "Actual ebf predecessor seed/reopen, candidate six-optional-field WordReplacement upgrade and backend approval scalar save, then fresh candidate reopen of the same clone. No human approval, UI, CloudKit sync, backward store-open or real user-store proof."})
    (output / "correction-oracle.swift").write_bytes((repo / oracle_path).read_bytes())
    (output / "canonical.Package.resolved").write_bytes((repo / lock_path).read_bytes())
    write(output / "toolchain.json", {"xcode": subprocess.check_output(["xcodebuild", "-version"], text=True), "swift": subprocess.check_output(["swift", "--version"], text=True), "macOS": subprocess.check_output(["sw_vers"], text=True), "sdk_path": subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip(), "sdk_version": subprocess.check_output(["xcrun", "--show-sdk-version"], text=True).strip(), "metal": subprocess.check_output(["xcrun", "metal", "--version"], text=True, stderr=subprocess.STDOUT), "runner_arch": os.environ.get("RUNNER_ARCH")})
    seed_defaults()
    for lane in ["predecessor", "candidate"]:
        verify_sources(lane)


def build(lane):
    directory = output / (lane + "-build")
    directory.mkdir()
    checkout, derived, arguments = build_arguments(lane)
    selected = spec("seed" if lane == "predecessor" else "correction-write")
    verify_sources(lane)
    verify_dependencies()
    selector = "-only-testing:" + selected["test_id"]
    settings = subprocess.check_output(["xcodebuild", "build-for-testing", "-showBuildSettings", "-json", *arguments, selector], cwd=checkout)
    rows = [row for row in json.loads(settings) if row.get("target") in ["VoiceInk", "VoiceInkTests"]]
    require(len(rows) == 2 and {row["target"] for row in rows} == {"VoiceInk", "VoiceInkTests"}, "Actual app/test build settings are missing")
    flags = {}
    for row in rows:
        active = str(row["buildSettings"].get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", ""))
        enabled = "CORRECTION_LIBRARY_CANDIDATE" in active.split()
        require(enabled is (lane == "candidate"), "Actual candidate-only compile condition is wrong")
        flags[row["target"]] = {"active_conditions": active, "candidate_condition": enabled}
    write(directory / "compile-condition.json", {"lane": lane, "targets": flags})
    run(["xcodebuild", "build-for-testing", *arguments, selector], directory / "build.log", checkout)
    log = (directory / "build.log").read_text(errors="replace")
    compiled_candidate = bool(re.search(r"(?:^|\s)-D(?:\s+)?CORRECTION_LIBRARY_CANDIDATE(?:\s|$)", log))
    require(compiled_candidate is (lane == "candidate"), "Actual compiler invocation does not match the candidate-only oracle branch")
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
    settings = {"RJT_CORRECTION_LIBRARY_STORE_CHECKS": "1", "RJT_DICTATION_STORE_SEED_CHECKS": "0", "RJT_DICTATION_METADATA_STORE_CHECKS": "0", "GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted", "RJT_STORE_PHASE": name, "RJT_STORE_FIXTURE": str(fixture), "RJT_STORE_EVIDENCE": str(observations), "RJT_STORE_SOURCE_SHA": load(output / "contract.json")["source_sha"][lane], "RJT_STORE_RUN_ROOT": str(output), "RJT_STORE_EXPECTED_EXE": before["executable_path"]}
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
    required = ["schema-raw.json", "schema-canonical.json", "snapshots.json", "expected-snapshots.json", "runtimeidentity.json", "historical-transcription-metadata.json", "expected-historical-transcription-metadata.json"]
    required += ["correction-records.json", "expected-correction-records.json", "correction-canonical-records.json", "expected-correction-canonical-records.json", "correction-identifiers.json", "correction-observation.json", "service-generated-identity.json", "historical-word-replacement-metadata.json", "expected-historical-word-replacement-metadata.json"] if lane == "candidate" else ["old-reader-safety.json"]
    for filename in required:
        require((observations / filename).is_file(), "Missing actual phase artifact: " + filename)
    after = identity(derived)
    write(directory / "identity-after.json", after)
    require(before == after, "Signed host/test bundle changed during phase")
    native_result(directory, selected)
    verify_sources(lane)
    verify_dependencies()
    write(directory / "closed-store-tree.json", store_tree(fixture))


def schema_delta(old, current):
    before_entities, after_entities = entity_map(old), entity_map(current)
    require(same_json({key: value for key, value in old.items() if key != "entities"}, {key: value for key, value in current.items() if key != "entities"}), "Top-level schema metadata changed")
    template = attribute_map(before_entities["Transcription"], "attributes")["enhancedText"]
    require(template["isOptional"] is True and template["valueTypeName"] == "SSSg", "Historical optional String template changed")
    for name in model_names:
        before, after = before_entities[name], after_entities[name]
        public, stored = attribute_map(before, "attributes"), attribute_map(before, "storedAttributes")
        require(same_json(public, stored) and len(public) == old_field_counts[name], "Historical schema field count or identity changed: " + name)
        if name != "WordReplacement":
            require(same_json(before, after), "Transcription20 or unrelated entity metadata changed: " + name)
            continue
        require(set(before) == set(after), "WordReplacement entity metadata keys changed")
        for key in before:
            if key not in ["attributes", "storedAttributes"]:
                require(same_json(before[key], after[key]), "WordReplacement non-attribute metadata/order changed: " + key)
                continue
            original, actual = attribute_map(before, key), attribute_map(after, key)
            require(not new_fields.intersection(original) and set(actual) == set(original) | new_fields, "Schema delta is not exactly six new WordReplacement attributes")
            for field, type_name in new_field_types.items():
                require(same_json(actual[field], dict(template, name=field, valueTypeName=type_name)), "New field type/default/options/nullability changed: " + field)
            require(all(same_json(actual[field], value) for field, value in original.items()), "Historical WordReplacement attribute metadata changed")
    return {"validated_new_field_types": new_field_types, "collections": ["attributes", "storedAttributes"], "historical_stored_fields": 39, "new_word_replacement_stored_fields": 11, "all_other_schema_values_and_order_preserved": True}


def check_string_bytes(value):
    if isinstance(value, dict):
        if set(value) == {"value", "utf8", "utf16"}:
            require(isinstance(value["value"], str) and same_json(list(value["value"].encode("utf-8")), value["utf8"]), "String UTF-8 bytes differ")
            data = value["value"].encode("utf-16-le")
            require(same_json([int.from_bytes(data[index:index+2], "little") for index in range(0, len(data), 2)], value["utf16"]), "String UTF-16 code units differ")
        for child in value.values():
            check_string_bytes(child)
    elif isinstance(value, list):
        for child in value:
            check_string_bytes(child)


def historical_metadata(actual):
    values = load(actual / "historical-transcription-metadata.json")
    expected = [{"id": value, "recognitionText": None, "dictationProfileRawValue": None, "clarityStyleRawValue": None, "processingFailureReason": None} for value in ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"]]
    require(same_json(values, expected) and same_json(values, load(actual / "expected-historical-transcription-metadata.json")), "Historical Transcription metadata changed")
    return values


def runtime_comparison(names):
    reference = output / "seed/observations"
    old_schema = load(reference / "schema-canonical.json")
    old_snapshots = load(reference / "snapshots.json")
    old_identity = normalized_identity(load(reference / "runtimeidentity.json"))
    old_identity.pop("schemaCanonicalSHA256")
    old_transcription = historical_metadata(reference)
    pids, hashes = [], {}
    candidate_schema = None
    for name in names:
        directory = output / name
        actual = directory / "observations"
        observation = load(actual / "observation.json")
        pids.append(observation["hostPID"])
        require(load(directory / "host-exit.json")["observedExited"] is True, "Exact host exit evidence missing")
        snapshots = load(actual / "snapshots.json")
        require(same_json(snapshots, old_snapshots) and same_json(snapshots, load(actual / "expected-snapshots.json")), "Historical 35 golden fields changed")
        require(same_json(historical_metadata(actual), old_transcription), "Historical four Transcription metadata fields changed")
        check_string_bytes(snapshots)
        schema = load(actual / "schema-canonical.json")
        if name in ["seed", "old-reopen"]:
            require(same_json(schema, old_schema), "Same-old-app schema control changed")
            safe = load(actual / "old-reader-safety.json")
            require(type(safe["version"]) is int and safe["version"] == 1 and safe["phase"] == name and safe["hostPID"] == observation["hostPID"] and safe["unchanged"] is True, "Actual old-reader safety observation is missing")
            require(safe["rawOriginalText"]["value"] == safe["rawReplacementText"]["value"] == "" and same_json(safe["input"], safe["output"]), "Actual predecessor empty raw pair was not a no-op")
            check_string_bytes(safe)
        else:
            schema_delta(old_schema, schema)
            if candidate_schema is None:
                candidate_schema = schema
            require(same_json(schema, candidate_schema), "Candidate schema changed between write and reopen")
        identity_value = load(actual / "runtimeidentity.json")
        require(identity_value["schemaRawSHA256"] == digest((actual / "schema-raw.json").read_bytes()), "Actual raw schema digest mismatch")
        normalized = normalized_identity(identity_value)
        normalized.pop("schemaCanonicalSHA256")
        require(same_json(normalized, old_identity), "Actual legacy persistent identifiers/module/entities/store groups changed")
        hashes[name] = {"raw_schema_sha256": digest((actual / "schema-raw.json").read_bytes()), "canonical_schema_sha256": digest((actual / "schema-canonical.json").read_bytes()), "legacy_snapshots_sha256": digest((actual / "snapshots.json").read_bytes()), "transcription_metadata_sha256": digest((actual / "historical-transcription-metadata.json").read_bytes())}
    require(len(pids) == len(set(pids)), "Every phase must have a separate actual host PID")
    return {"phases": names, "distinct_host_pids": pids, "legacy_39_values_and_identifiers_equal": True, "schema_hashes": hashes}


def verify_correction():
    legacy = load(output / "seed/observations/runtimeidentity.json")
    store = legacy["persistentIdentifiers"]["WordReplacement"][0]["storeIdentifier"]
    entity = legacy["models"][2]["entityName"]
    original_generated = load(output / "correction-write/observations/service-generated-identity.json")
    generated_id = original_generated["id"]
    historical_ids = {row["id"] for rows in load(output / "seed/observations/snapshots.json").values() for row in rows if "id" in row}
    require(isinstance(generated_id, str) and re.fullmatch(r"[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}", generated_id) and generated_id not in set(fixed_ids) | historical_ids | {source_history_id}, "Actual service-generated UUID is missing or collides")
    expected_ids = sorted([*fixed_ids, generated_id])
    canonical_ids = sorted([fixed_ids[0], fixed_ids[1], generated_id])
    require(original_generated["version"] == 1 and original_generated["sourceTranscriptionID"] == source_history_id and original_generated["sourceVariant"] == "recognition" and original_generated["createdInPhase"] == "correction-write" and original_generated["generatedByServicePreview"] is True and original_generated["hostPID"] == load(output / "correction-write/observations/observation.json")["hostPID"], "Service-generated preview input receipt was relabeled")
    require(type(original_generated["dateAdded"]) in [int, float] and abs(original_generated["dateAdded"]) < 1e12, "Service-generated preview date is invalid")
    reference = None
    for name in ["correction-write", "correction-reopen"]:
        actual = output / name / "observations"
        require(same_json(load(actual / "service-generated-identity.json"), original_generated), "Fresh reopen changed the independently captured preview identity/date")
        records = load(actual / "correction-records.json")
        canonical = load(actual / "correction-canonical-records.json")
        identifiers = load(actual / "correction-identifiers.json")
        require(same_json(records, load(actual / "expected-correction-records.json")) and len(records) == 4 and [row["id"] for row in records] == expected_ids and all(len(row) == 11 for row in records), "New 11-field stored correction rows changed")
        require(same_json(canonical, load(actual / "expected-correction-canonical-records.json")) and len(canonical) == 3 and [row["id"] for row in canonical] == canonical_ids and all(len(row) == 9 for row in canonical), "Canonical literal correction DTO values changed")
        for row in records:
            if row["id"] in canonical_ids:
                require(row["originalText"]["value"] == row["replacementText"]["value"] == "" and row["matchingKindRawValue"]["value"] == "literal", "Literal legacy raw pair must remain empty for older readers")
                logical = next(value for value in canonical if value["id"] == row["id"])
                require(same_json(row["literalOriginalText"], logical["originalText"]) and same_json(row["literalReplacementText"], logical["replacementText"]), "Literal payload differs from canonical DTO text")
            else:
                require(row["id"] == fixed_ids[2] and row["isEnabled"] is False and row["matchingKindRawValue"]["value"] == "future-kind" and row["literalOriginalText"] is None and row["literalReplacementText"] is None, "Unknown kind must round-trip disabled without literal execution")
        generated = next(row for row in records if row["id"] == generated_id)
        require(generated["dateAdded"] == original_generated["dateAdded"] and generated["sourceTranscriptionID"] == source_history_id and generated["approvalOriginRawValue"]["value"] == "historyManual" and generated["sourceVariantRawValue"]["value"] == "recognition", "Approved scalar provenance changed after source history deletion")
        require(same_json(generated["literalOriginalText"], original_generated["originalText"]) and same_json(generated["literalReplacementText"], original_generated["replacementText"]), "Approved text differs from the pre-approval preview input")
        require(len(identifiers) == 4 and [row["recordID"] for row in identifiers] == expected_ids and all(row["entityName"] == entity and row["storeIdentifier"] == store and isinstance(row["encodedBase64"], str) and row["encodedBase64"] for row in identifiers), "New saved identifiers use wrong dictionary store/entity")
        old_metadata = load(actual / "historical-word-replacement-metadata.json")
        expected_old = [{"id": value, **{field: None for field in new_fields}} for value in ["33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444"]]
        require(same_json(old_metadata, expected_old) and same_json(old_metadata, load(actual / "expected-historical-word-replacement-metadata.json")), "Historical six new WordReplacement fields must remain nil")
        receipt = load(actual / "correction-observation.json")
        require(type(receipt["version"]) is int and receipt["version"] == 1 and receipt["phase"] == name and receipt["hostPID"] == load(actual / "observation.json")["hostPID"] and receipt["historicalRowCount"] == 2 and receipt["additionalRecordCount"] == 4 and receipt["storedFieldsPerNewRecord"] == 11 and receipt["historicalStoredFieldCount"] == 39, "Correction observation identifies wrong host or rows")
        require(all(receipt[key] is True for key in ["historicalNewFieldsNil", "historicalNilKindMeansLegacy", "literalRawPairsEmpty", "exactStoredAndCanonicalValues", "unknownRawPreserved", "unknownExecutionRejected", "unknownEnableRejected", "unknownRemainsDisabled", "sourceHistoryAbsent", "sourceScalarProvenancePreserved"]), "Correction semantic checks did not pass")
        require(all(receipt[key] is (name == "correction-write") for key in ["explicitSavePerformed", "sourceHistoryDeleted", "approvalServiceInvoked"]), "Write/reopen effects were relabeled")
        require(same_json(receipt["literalEngineOutput"], receipt["literalEngineExpected"]) and same_json(receipt["literalServiceOutput"], receipt["literalEngineExpected"]), "Actual literal engine/service output changed")
        for value in [records, canonical, original_generated, receipt]:
            check_string_bytes(value)
        value = {"records": records, "canonical": canonical, "identifiers": identifiers}
        if reference is None:
            reference = value
        require(same_json(value, reference), "Fresh candidate reopen changed a stored or canonical value or persistent identifier")
    return {"new_record_count": 4, "stored_fields_per_new_record": 11, "canonical_record_count": 3, "canonical_fields_per_record": 9, "new_values_and_identifiers_equal_after_reopen": True, "historical_six_new_fields_nil": True, "literal_legacy_raw_pair_empty": True, "deleted_source_history_scalar_provenance_preserved": True, "unknown_kind_remains_disabled_and_rejected": True}


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
    fixture = output / "stores/correction"
    clone_seed(fixture, "correction-write")
    phase("correction-write", fixture)
    checkpoint = store_tree(fixture)
    write(output / "correction-write-closed-tree.json", checkpoint)
    retained = output / "stores/correction-write-checkpoint"
    require(not retained.exists(), "Refusing to overwrite the closed correction write checkpoint")
    shutil.copytree(fixture, retained, symlinks=False)
    require(store_tree(retained) == checkpoint == store_tree(fixture), "Complete closed correction write copy differs")
    for path in [*retained.rglob("*"), retained]:
        path.chmod(0o500 if path.is_dir() else 0o400)
    write(output / "correction-write-readonly.json", {"path": str(retained), "entries": {str(path.relative_to(retained)): oct(path.stat().st_mode & 0o777) for path in [retained, *sorted(retained.rglob("*"))]}, "closedCopyReadOnly": True})
    seed_unchanged()
    require(store_tree(fixture) == checkpoint, "Closed correction write checkpoint changed before reopen")
    write(output / "correction-reopen-before.json", store_tree(fixture))
    phase("correction-reopen", fixture)
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
        if name != "correction-write":
            require(store_tree(Path(observed["fixturePath"])) == load(directory / "closed-store-tree.json"), "Closed phase fixture changed after completion")
    require(load(output / "correction-reopen-before.json") == load(output / "correction-write-closed-tree.json") == load(output / "correction-write/closed-store-tree.json"), "Fresh reopen did not receive the complete exact closed write checkpoint")
    retained = output / "stores/correction-write-checkpoint"
    require(store_tree(retained) == load(output / "correction-write-closed-tree.json"), "Retained complete correction write checkpoint changed")
    require({str(path.relative_to(retained)): oct(path.stat().st_mode & 0o777) for path in [retained, *sorted(retained.rglob("*"))]} == load(output / "correction-write-readonly.json")["entries"], "Correction write checkpoint read-only protection changed")
    require(load(output / "correction-write/observations/observation.json")["fixturePath"] == load(output / "correction-reopen/observations/observation.json")["fixturePath"], "Candidate reopen must read the same upgraded store clone")
    result = runtime_comparison(phases)
    result.update(verify_correction())
    write(output / "result.json", dict(result, classification="actual-correction-library-store-upgrade-passed", source_sha=load(output / "contract.json")["source_sha"], original_seed_immutable=True, limits=["Six local optional WordReplacement scalar attributes and explicit programmatic backend approval fixture only.", "Empty legacy raw pair checked at predecessor matching boundary; no CloudKit sync or backward store-open proof.", "No actual human approval, UI, real user store, provider call or microphone inactivity proof.", "Actual app initialization opened fresh normal Application Support and attempted recorder pre-roll on the disposable runner."]))


def self_test():
    actual_root = repo / "docs/research/competitors/evidence/dictation-metadata-40581983321"
    old = load(actual_root / "metadata-write/observations/schema-canonical.json")
    require(sum(old_field_counts.values()) == 39 and len(attribute_map(entity_map(old)["Transcription"], "attributes")) == 20, "Actual native fixture must already contain Transcription20 and WordReplacement5")
    candidate = copy.deepcopy(old)
    template = attribute_map(entity_map(old)["Transcription"], "attributes")["enhancedText"]
    for key in ["attributes", "storedAttributes"]:
        entity_map(candidate)["WordReplacement"][key].extend(dict(template, name=field, valueTypeName=type_name) for field, type_name in new_field_types.items())
    schema_delta(old, candidate)
    old_compare = [node for node in shared_ast.body if isinstance(node, ast.FunctionDef) and node.name == "compare_runtime"]
    require(len(old_compare) == 1, "Actual pinned strict old comparator is missing")
    with tempfile.TemporaryDirectory(prefix="rjt-correction-schema-controls-") as temporary:
        control = Path(temporary)
        native_names = ["metadata-write", "metadata-reopen"]
        for name in native_names:
            directory = control / name
            (directory / "observations").mkdir(parents=True)
            for filename in ["observation.json", "schema-canonical.json", "schema-raw.json", "snapshots.json", "expected-snapshots.json", "runtimeidentity.json"]:
                (directory / "observations" / filename).write_bytes((actual_root / name / "observations" / filename).read_bytes())
            (directory / "host-exit.json").write_bytes((actual_root / name / "host-exit.json").read_bytes())
        namespace = dict(globals(), output=control)
        exec(compile(ast.Module(body=old_compare, type_ignores=[]), baseline + ":" + baseline_path, "exec"), namespace)
        namespace["compare_runtime"](native_names)
        (control / "metadata-reopen/observations/schema-canonical.json").write_text(json.dumps(candidate))
        try:
            namespace["compare_runtime"](native_names)
        except RuntimeError as error:
            require(str(error) == "Normalized actual runtime schema changed", "Strict old comparator failed at an unrelated boundary")
        else:
            raise RuntimeError("Strict old comparator accepted synthetic WordReplacement schema additions")
    mutations = {}
    def changed(name, operation):
        value = copy.deepcopy(candidate)
        operation(value)
        mutations[name] = value
    def new_attribute(value, key="storedAttributes", name="matchingKindRawValue"):
        return attribute_map(entity_map(value)["WordReplacement"], key)[name]
    changed("unknown-field", lambda value: entity_map(value)["WordReplacement"]["storedAttributes"].append(dict(template, name="unknownField")))
    changed("missing-field", lambda value: entity_map(value)["WordReplacement"]["storedAttributes"].remove(new_attribute(value)))
    changed("duplicate-field", lambda value: entity_map(value)["WordReplacement"]["attributes"].append(dict(template, name="matchingKindRawValue")))
    for key in ["attributes", "storedAttributes"]:
        for field, type_name in new_field_types.items():
            changed(field + "/" + key + "/type", lambda value, k=key, f=field, t=type_name: new_attribute(value, k, f).update(valueTypeName="SSSg" if t != "SSSg" else "SdSg"))
            changed(field + "/" + key + "/nullable", lambda value, k=key, f=field: new_attribute(value, k, f).update(isOptional=False))
            changed(field + "/" + key + "/typed-bool", lambda value, k=key, f=field: new_attribute(value, k, f).update(isOptional=1))
            changed(field + "/" + key + "/default", lambda value, k=key, f=field: new_attribute(value, k, f).update(defaultValue="invented"))
    changed("old-word-default", lambda value: attribute_map(entity_map(value)["WordReplacement"], "attributes")["originalText"].update(defaultValue="invented"))
    changed("old-transcription-type", lambda value: attribute_map(entity_map(value)["Transcription"], "attributes")["recognitionText"].update(valueTypeName="SdSg"))
    changed("old-entity-metadata", lambda value: entity_map(value)["VocabularyWord"].update(hashModifier="changed"))
    changed("top-metadata", lambda value: value.update(hashModifier="changed"))
    mutations["all-additions-missing"] = old
    for name, value in mutations.items():
        try:
            schema_delta(old, value)
        except RuntimeError:
            continue
        raise RuntimeError("Invalid schema mutation accepted: " + name)
    for key in ["indices", "uniquenessConstraints", "futureOrderedMetadata"]:
        before, after = copy.deepcopy(old), copy.deepcopy(candidate)
        entity_map(before)["WordReplacement"][key] = [["originalText", "dateAdded"], ["id", "isEnabled"]]
        entity_map(after)["WordReplacement"][key] = copy.deepcopy(entity_map(before)["WordReplacement"][key])
        schema_delta(before, after)
        for inner in [False, True]:
            value = copy.deepcopy(after)
            array = entity_map(value)["WordReplacement"][key]
            (array[0] if inner else array).reverse()
            try:
                schema_delta(before, value)
            except RuntimeError:
                continue
            raise RuntimeError("Ordered schema metadata change accepted")
    text = "Test " + test_name + "() started.\nTest " + test_name + "() passed after 0.1 seconds.\nTest run with 1 test in 1 suite passed\n"
    require(classify(text, 0, test_name)["valid"], "Valid selected correction test rejected")
    for value in [text + text, text.replace("passed after", "skipped after"), text.replace("1 test in", "0 tests in"), text + "Test other() started.\n", text + "Test " + test_name + "() recorded an issue: failed\n"]:
        require(not classify(value, 0, test_name)["valid"], "Invalid exact hosted log accepted")
    require(not classify(text, 65, test_name)["valid"], "Nonzero exact hosted exit accepted")
    for lane in ["predecessor", "candidate"]:
        arguments = build_arguments(lane)[2]
        active = next(argument for argument in arguments if argument.startswith("SWIFT_ACTIVE_COMPILATION_CONDITIONS="))
        require(("CORRECTION_LIBRARY_CANDIDATE" in active.split()) is (lane == "candidate"), "Build argument macro boundary changed")
    print(json.dumps({"classification": "offline-correction-driver-controls-passed", "actual_strict_comparator_accepts_native_20_field_transcription_control": True, "actual_strict_comparator_rejects_only_synthetic_word_schema_additions": True,
          "new_delta_accepts_same_synthetic_word_schema": True, "historical_stored_fields": 39, "new_word_stored_fields": 11, "rejected_schema_mutations": len(mutations), "ordered_array_controls": 6,
          "shared_runtime": shared_receipt, "neutral_runtime": neutral_receipt, "scope": "Source-bound JSON comparator on unchanged captured native metadata-write/reopen evidence plus synthetic six-field additions; schema negatives, explicit candidate compile-argument and exact log classifiers only. No correction migration or new native execution."}, sort_keys=True))


try:
    actions = {"self-test": self_test, "prepare": prepare, "dependencies": dependencies, "predecessor": old_control, "candidate": candidate_control, "verify": verify}
    require(mode in actions, "usage: run-correction-library-store-check.sh self-test | prepare | dependencies | predecessor | candidate | verify")
    actions[mode]()
except BaseException as error:
    if output.is_dir() and mode != "self-test":
        (output / ("failure-" + mode + ".json")).write_text(json.dumps({"classification": "invalid-or-failed", "mode": mode, "error": str(error)}, indent=2) + "\n")
    raise

PY
