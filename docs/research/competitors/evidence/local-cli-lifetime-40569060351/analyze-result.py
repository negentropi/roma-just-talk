#!/usr/bin/env python3
"""Recheck retained native evidence using the exact committed classifier and sources."""
import ast
import collections
import hashlib
import json
import re
import subprocess
from pathlib import Path

directory = Path(__file__).resolve().parent
artifact = directory / "artifact/local-cli-lifetime-check"
revision = "77d84bd1d75927b2d8a74990346476963c80f167"
driver_path = "scripts/run-local-cli-lifetime-check.sh"
digest = lambda data: hashlib.sha256(data).hexdigest()
read = lambda path: json.loads(path.read_text())

def source(commit, path):
    return subprocess.check_output(["git", "show", f"{commit}:{path}"])

run, contract = read(directory / "run.json"), read(artifact / "contract.json")
assert run["headSha"] == revision and run["status"] == "completed" and run["conclusion"] == "success"
assert all(step["conclusion"] == "success" for step in run["jobs"][0]["steps"])
assert contract["candidate_sha"] == revision
driver = source(revision, driver_path)
assert digest(driver) == contract["driver_sha256"]
python = driver.decode().split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
definitions = []
for node in ast.parse(python).body:
    if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "SWIFT" for target in node.targets):
        break
    definitions.append(node)
classifier = {}
exec(compile(ast.Module(body=definitions, type_ignores=[]), "<pinned-classifier>", "exec"), classifier)

before, after = read(artifact / "source-before.json"), read(artifact / "source-after.json")
assert before == after and len(before) == 154
assert all(digest(source(revision, path)) == value for path, value in before.items())
dependencies = contract["dependency_manifest"]
assert len(dependencies) == 150
assert dependencies == read(artifact / "baseline-dependencies.json") == read(artifact / "candidate-dependencies.json")
expected_paths = subprocess.check_output([
    "git", "ls-tree", "-r", "--name-only", "-z", revision, "--", "VoiceInkCore", "VoiceInkNVIDIA"
]).decode().strip("\0").split("\0")
assert set(expected_paths) == set(dependencies)
assert all(digest(source(contract["baseline_sha"], path)) == value for path, value in dependencies.items())
for lane, target in contract["targets"].items():
    folder = artifact / "package/Sources" / target
    service_hash = contract["baseline_service_sha256"] if lane == "baseline" else contract["candidate_service_sha256"]
    assert digest((folder / "LocalCLIService.swift").read_bytes()) == service_hash
    assert digest((folder / "CommonProbe.swift").read_bytes()) == contract["common_probe_sha256"]
generated = {str(path.relative_to(artifact / "package")): digest(path.read_bytes())
             for path in sorted((artifact / "package/Sources").rglob("*")) if path.is_file()}
assert generated == contract["target_sources"]
assert digest((artifact / "package/Package.swift").read_bytes()) == contract["package_manifest_sha256"]
lock = (artifact / "package/Package.resolved").read_bytes()
assert digest(lock) == contract["package_lock_sha256"] == digest(source(revision, "VoiceInkCore/Package.resolved"))
assert len(json.loads(lock)["pins"]) == 22
assert digest((artifact / "darwin-ps-shape-observation.json").read_bytes()) == contract["identity_fixture_sha256"]
assert digest((artifact / "old-identity-parser-source.txt").read_bytes()) == contract["old_parser_source_sha256"]
assert read(artifact / "source-verification.json")["valid"] is True
assert read(artifact / "identity-verification.json")["valid"] is True
wrappers = read(artifact / "wrapper-before.json")
assert wrappers == read(artifact / "wrapper-after.json")

lanes = {}
for lane, target in contract["targets"].items():
    signature = (artifact / f"{target}-signature-before.txt").read_bytes()
    assert signature == (artifact / f"{target}-signature-after.txt").read_bytes()
    assert f"Identifier={contract['bundles'][lane]}\n" in signature.decode()
    binary = (artifact / f"{target}-binary-before.txt").read_bytes()
    assert binary == (artifact / f"{target}-binary-after.txt").read_bytes()
    executable_hash, plist_hash = [line.split("  ", 1)[0] for line in binary.decode().splitlines()]
    assert wrappers[lane][f"Contents/MacOS/{target}"] == executable_hash
    assert wrappers[lane]["Contents/Info.plist"] == plist_hash
    result, supervisor = read(artifact / lane / "result.json"), read(artifact / lane / "supervisor.json")
    assert classifier["classify"](result, lane, supervisor, contract)["valid"] is True
    assert supervisor["cleanupActions"] == [] and supervisor["remainingChildren"] == [] and supervisor["errors"] == []
    rows = [json.loads(line) for line in (artifact / lane / "process-observations.jsonl").read_text().splitlines()]
    states = collections.Counter(row["state"] for row in rows)
    assert set(states) == {"running", "gone"}
    for row in rows:
        if row["state"] == "running":
            assert row["verified"] is True and row["differences"] == []
            assert classifier["identity_differences"](row["expected"], row["actual"]) == []
            parsed = classifier["parse_ps_fields"](row["rawPS"]["ppid"]["stdout"], row["rawPS"]["args"]["stdout"])
            assert all(row["actual"][key] == value for key, value in parsed.items())
            assert row["actual"]["kernelReturnCode"] > 0 and row["actual"]["kernelErrno"] == 0
        else:
            assert row["actual"]["kernelReturnCode"] == 0 and row["actual"]["kernelErrno"] == 3
            assert all(field["exitCode"] == 1 and field["stdout"] == "" and field["stderr"] == "" and not field["timedOut"]
                       for field in row["rawPS"].values())
    roots = [row for row in rows if row["phase"] == "probe-root" and row["state"] == "running"]
    assert roots and all(row["expected"]["pid"] == supervisor["rootPID"] and row["expected"]["executable"] == contract["executables"][lane] for row in roots)
    lanes[lane] = {"native_exit_code": supervisor["exitCode"], "cases": result["cases"],
                   "root_identity_verified": True, "verified_root_samples": len(roots),
                   "child_identities_verified": len(supervisor["children"]), "journal_rows": len(rows),
                   "journal_states": dict(states), "cleanup_verified": True,
                   "supervisor_cleanup_actions": [], "remaining_children": [], "watchdog_fired": False,
                   "binary_sha256": executable_hash,
                   "cdhash": re.search(r"^CDHash=(.+)$", signature.decode(), re.MULTILINE).group(1)}

comparison = read(artifact / "comparison-result.json")
assert comparison["valid"] is True and comparison["classification"] == "matched-old-red-new-green"
assert comparison["lanes"]["baseline"]["failedCases"] == ["pre-cancelled", "cancel-blocked-stdin", "dual-pipe", "timeout-blocked-stdin"]
build = (artifact / "build.log").read_text()
assert all(f"Emitting module {name}" in build for name in ["VoiceInkCore", "VoiceInkNVIDIA"])
receipt = {
    "run_id": 40569060351, "run_url": run["url"], "source_head": revision,
    "baseline_head": contract["baseline_sha"], "classification": "matched-old-red-new-green",
    "native_regression_proof_valid": True, "source_files_verified": 154,
    "identical_real_core_nvidia_source_files": 150, "frozen_root_pin_count": 22,
    "root_lock_sha256": contract["package_lock_sha256"],
    "production_service_sha256": contract["candidate_service_sha256"],
    "common_probe_sha256": contract["common_probe_sha256"],
    "source_pins_signatures_and_wrappers_unchanged": True,
    "build_seconds": float(re.search(r"Build complete! \(([\d.]+)s\)", build).group(1)),
    "toolchain_before_build": (artifact / "toolchain.txt").read_text(),
    "warnings": re.findall(r"^warning: (.+)$", build, re.MULTILINE),
    "lanes": lanes, "artifact": read(directory / "artifact.json"),
    "scope": "Actual production service with real Core, synthetic local commands, and direct-child lifetime. No app/UI, descendants, provider credentials, AI quality, profile activation, release, or uncommitted Core changes proof. This run compiled Core but did not execute the full CoreChecks suite.",
}
(directory / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({"classification": receipt["classification"], "source_head": revision,
                  "native_exits": {lane: value["native_exit_code"] for lane, value in lanes.items()},
                  "journal_rows": {lane: value["journal_rows"] for lane, value in lanes.items()}}, indent=2))
