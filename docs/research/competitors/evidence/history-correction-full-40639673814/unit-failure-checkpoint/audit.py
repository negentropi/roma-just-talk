#!/usr/bin/env python3
"""Check retained unit/Core/package evidence without running or downloading the app."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent
load = lambda name: json.loads((root / name).read_text())
source = load("source-preflight.json")
units = load("unit-results.json")
core = load("core-package-results.json")
run = load("run-final.json")
head = "3f62c6da2fd98361d48305c9c5e0d01bed980f82"
assert source["head_sha"] == units["head_sha"] == core["head_sha"] == run["headSha"] == head
assert source["run_id"] == units["run_id"] == core["run_id"] == run["databaseId"] == 40639673814
assert run["status"] == "completed" and run["conclusion"] == "failure"
assert run["displayTitle"] == "Verify Mac writing actions (full)"
steps = {step["name"]: step["conclusion"] for job in run["jobs"] for step in job["steps"]}
for name in ("Verify the canonical package graph before compiling", "Shared core checks",
             "Prepare and verify static Whisper dependencies", "Full Mac unit suite with fresh CI permissions",
             "Live TextEdit and Safari selection transactions", "Matched snippet regression"):
    assert steps[name] == "success", name
assert steps["Writing, snippet and dictation settings UI"] == "failure"
assert steps["Release build and packaging contracts"] == steps["Upload verified release app"] == "skipped"

for name, record in source["sources"].items():
    data = (root / "source" / name).read_bytes()
    assert len(data) == record["bytes"] and hashlib.sha256(data).hexdigest() == record["sha256"], name
    assert data == subprocess.check_output(["git", "show", head + ":" + name]), name
    if record["unchanged_from_700"]:
        assert data == subprocess.check_output(["git", "show", source["prior_full_unit_head"] + ":" + name]), name
for name in ("HistoryCorrectionApprovalTests", "WordReplacementBackupAdapterTests", "WordReplacementLibraryAdapterTests"):
    path = "VoiceInkTests/" + name + ".swift"
    assert (root / "source" / path).read_bytes() == subprocess.check_output(["git", "show", source["known_red_head"] + ":" + path])

for name, record in core["archive_members"].items():
    data = (root / "raw" / name).read_bytes()
    assert len(data) == record["bytes"] and hashlib.sha256(data).hexdigest() == record["sha256"], name
raw = root / "raw/_temp"
assert json.loads((raw / "writing-proof-snapshot/verification-mode.json").read_text()) == {
    "sourceSHA": head, "mode": "full", "fullGateRequired": True
}
assert (raw / "writing-proof-snapshot/source-sha.txt").read_text().strip() == head
core_log = (raw / "writing-core-checks.log").read_text()
passes = re.findall(r"^PASS (.+)$", core_log, re.M)
assert passes == source["core_registry"] and len(set(passes)) == core["core_exact_registry_pass_count"] == 1758
assert not re.search(r"^FAIL ", core_log, re.M)
assert re.findall(r"^Executed (\d+) VoiceInkCore checks\.$", core_log, re.M) == ["1758"]
lock = (raw / "writing-package-proof/canonical.Package.resolved").read_bytes()
assert hashlib.sha256(lock).hexdigest() == source["canonical_package_lock_sha256"] == core["canonical_lock_sha256"]
pins = json.loads(lock)["pins"]
assert pins == source["canonical_package_pins"] and len(pins) == len({pin["identity"] for pin in pins}) == 41
assert all(pin["location"] and pin["state"].get("revision") for pin in pins)
assert json.loads((raw / "writing-package-proof/candidate-strict-resolve.json").read_text()) == core["strict_resolution"] == {
    "exit_code": 0, "canonical_lock_unchanged": True
}
contract = json.loads((raw / "writing-package-proof/canonical-graph-contract.json").read_text())
assert contract["canonical_pin_count"] == 41 and contract["canonical_sha256"] == core["canonical_lock_sha256"]
for name, digest in contract["declaration_sha256"].items():
    assert hashlib.sha256(subprocess.check_output(["git", "show", head + ":" + name])).hexdigest() == digest, name
assert "Verified static Whisper XCFramework: 7 slices" in (raw / "writing-dependency-setup.log").read_text()
environment = (raw / "writing-feature-regression/contract.txt").read_text()
for expected in ("candidate=" + head, "Xcode 26.6", "Build version 17F113", "26.6.2", "25G83", "arm64"):
    assert expected in environment

previous_root = root.parents[1] / "polish-mac-40619909088/unit-failure-checkpoint"
previous = json.loads((previous_root / "unit-results.json").read_text())
selected = units["selected_44"]
assert len(selected) == len({case["identifier"] for case in selected}) == 44
assert [case["identifier"] for case in selected] == [case["identifier"] for case in previous["selected_44"]]
for case in selected:
    assert case["status"] == "Success" and not [item for item in case["failure_summaries"] if item.get("message")]
    assert len(case["decoded_summary_sha256"]) == 64 and case["summary_reference"]
correction_ids = set()
for group, count in {"WordReplacementLibraryAdapterTests": 6, "HistoryCorrectionApprovalTests": 7,
                     "DictionaryContextFreshnessTests": 2, "WordReplacementBackupAdapterTests": 10,
                     "DictionaryPersistenceIsolationTests": 4}.items():
    cases = units["correction_29"][group]
    assert len(cases) == count
    assert [case["identifier"] for case in cases] == [case["identifier"] for case in previous["correction_29"][group]]
    for case in cases:
        assert case["status"] == "Success" and not [item for item in case["failure_summaries"] if item.get("message")]
        assert case["identifier"] not in correction_ids
        correction_ids.add(case["identifier"])
assert len(correction_ids) == 29 and len(correction_ids & {case["identifier"] for case in selected}) == units["overlap"] == 7
assert units["decoded_file_bytes"] == 4899031
assert units["decoded_file_sha256"] == "fd12ff0e72ae39db29ee715d4a66e3af2e3321725aa977cd26bd2f1d5167bc86"
assert units["all_record_count"] == 341 and units["all_record_statuses"] == {"Success": 310, "Skipped": 31}
assert units["all_unique_identifiers"] == 339 and units["all_issue_message_count"] == 0
assert units["unique_identifier_statuses_by_family"] == {
    "OnboardingRegionViewTests/": {"Success": 9}, "SwiftTesting": {"Success": 299, "Skipped": 31}
}
assert core["release_artifact_absence"] == {"release_build_logs": [], "release_app_hashes": []}
print(json.dumps({"run_id": run["databaseId"], "head_sha": head, "mode": "full", "core_pass": 1758,
                  "canonical_pins": 41, "focused_unit_success": 44, "correction_success": 29, "overlap": 7,
                  "unique_swift_identifiers": {"Success": 299, "Skipped": 31}, "onboarding_xctest_success": 9,
                  "release": "skipped", "whole_workflow": "failed later UI/persistence permission preflight"}, indent=2))
