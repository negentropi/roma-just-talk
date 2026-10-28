#!/usr/bin/env python3
"""Check the selected unit receipt and frozen source comparison without a build."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent
read = lambda name: json.loads((root / name).read_text())
registry = read("source-registry.json")
selected = read("selected-unit-results.json")
census = read("xcresult-census.json")
baseline_path = root.parents[1] / "polish-mac-40607608894/unit-results.json"
baseline = json.loads(baseline_path.read_text())
assert registry["run_id"] == selected["run_id"] == census["run_id"] == 40613521362
assert registry["head_sha"] == census["head_sha"] == "53d62fb11fbdb425781e1cab3b087a627c18dfc1"
assert selected["decoded_file_bytes"] == 5075554
assert selected["decoded_file_sha256"] == census["candidate_decoded_sha256"] == "c0941f976ac2af5c6ae8892ed6dadccb8d9404823d89fa5f2f18cfc64f85e405"
assert hashlib.sha256(baseline_path.read_bytes()).hexdigest() == census["baseline_result_sha256"]
for section in ("whole_sources", "unchanged_gate_sources", "candidate_production_sources"):
    for name, expected in registry[section].items():
        data = (root / "source" / name).read_bytes()
        assert len(data) == expected["bytes"] and hashlib.sha256(data).hexdigest() == expected["sha256"], name
        assert data == subprocess.check_output(["git", "show", registry["head_sha"] + ":" + name]), name
        if section == "unchanged_gate_sources" or (section == "whole_sources" and not name.endswith("DictionaryPersistenceIsolationTests.swift")):
            assert data == subprocess.check_output(["git", "show", registry["known_red_head"] + ":" + name]), name

assert len(selected["case_details"]) == 44
by_id = {case["identifier"]: case for case in selected["case_details"]}
assert len(by_id) == 44
baseline_by_id = {}
for case in baseline["case_summaries"]:
    baseline_by_id.setdefault(case["identifier"], []).append(case)

def issues(case):
    return [item for item in case.get("failure_summaries", case.get("failures", [])) if item.get("message")]

def check_case(record, expected_status, baseline_case=False):
    actual = baseline_by_id[record["identifier"]] if baseline_case else [by_id[record["identifier"]]]
    assert len(actual) == record["records"] == 1
    actual = actual[0]
    assert actual["status"] == record["status"] == expected_status
    assert actual["summary_reference"] == record["summary_reference"]
    assert actual["decoded_summary_sha256"] == record["decoded_summary_sha256"]
    assert issues(actual) == record["issues"]
    if expected_status == "Success":
        assert not issues(actual)

for path, methods in registry["positive_registry"].items():
    source = (root / "source" / path).read_text()
    source_methods = re.findall(r"@Test(?:\([^\n]*\))?\s+(?:@MainActor\s+)?func\s+(\w+)\s*\(", source)
    assert source_methods == methods
    group = census["groups"][path]
    assert len(group) == len(methods)
    for record, method in zip(group, methods):
        assert record["identifier"].endswith("/" + method + "()")
        check_case(record, "Success")
        if not path.endswith("DictionaryPersistenceIsolationTests.swift"):
            check_case(record["baseline"], "Success", baseline_case=True)
expected_issue_counts = [2, 1, 2]
for record, method, count in zip(census["former_failures"], registry["known_red_registry"], expected_issue_counts):
    assert record["identifier"].endswith("/" + method + "()")
    check_case(record, "Success")
    check_case(record["baseline"], "Failure", baseline_case=True)
    assert len(record["baseline"]["issues"]) == count
assert census["selected_success_count"] == 44
assert census["old_positive_success_count"] == 37
assert census["new_success_count"] == 4
assert census["formerly_failed_success_count"] == 3
assert selected["all_decoded_summary_record_count"] == 340
assert selected["all_decoded_status_counts"] == {"Success": 310, "Skipped": 30}
assert selected["all_unique_identifiers"] == 338
assert selected["unique_identifier_statuses_by_family"] == {
    "OnboardingRegionViewTests/": {"Success": 9}, "SwiftTesting": {"Success": 299, "Skipped": 30}
}
assert selected["issues_message_count"] == 0
correction = read("correction-group-results.json")
assert correction["run_id"] == registry["run_id"] and correction["head_sha"] == registry["head_sha"]
assert correction["decoded_source_sha256"] == selected["decoded_file_sha256"]
expected_correction_counts = {
    "WordReplacementLibraryAdapterTests": 6, "HistoryCorrectionApprovalTests": 7,
    "DictionaryContextFreshnessTests": 2, "WordReplacementBackupAdapterTests": 10,
    "DictionaryPersistenceIsolationTests": 4,
}
correction_ids = set()
for group, count in expected_correction_counts.items():
    records = correction["groups"][group]
    names = re.findall(r"@Test(?:\([^\n]*\))?\s+(?:@MainActor\s+)?func\s+(\w+)\s*\(",
                       (root / "source/VoiceInkTests" / (group + ".swift")).read_text())
    assert len(records) == len(names) == count
    assert {record["identifier"].split("/")[-1] for record in records} == {name + "()" for name in names}
    for record in records:
        assert record["status"] == "Success" and not issues(record)
        assert record["identifier"].startswith("VoiceInkTests/" + group + "/")
        assert record["identifier"] not in correction_ids
        correction_ids.add(record["identifier"])
assert len(correction_ids) == 29
assert len(correction_ids.intersection(by_id)) == correction["overlap_with_44_selected_census"] == 7
environment = read("unit-environment-comparison.json")
assert environment["matched"] is True
assert [item["run_id"] for item in environment["observations"]] == [40607608894, 40613521362]
assert environment["observations"][0]["facts"] == environment["observations"][1]["facts"]
assert environment["observations"][0]["facts"]["sdk_identifier"] == "macosx26.5"
assert environment["observations"][0]["facts"]["os_version_with_build"] == "26.6.2 (25G83)"
assert environment["observations"][0]["facts"]["target_architecture"] == "arm64"
print(json.dumps({"run_id": registry["run_id"], "head_sha": registry["head_sha"], "selected_success": 44,
                  "former_failure_to_success": 3, "prior_success_preserved": 37, "new_success": 4,
                  "correction_group_success": 29, "overlap_between_censuses": 7,
                  "unique_swift_identifiers": {"Success": 299, "Skipped": 30},
                  "unique_onboarding_xctest_identifiers": {"Success": 9},
                  "whole_workflow": "UI failed; Release skipped"}, indent=2))
