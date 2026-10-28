#!/usr/bin/env python3
"""Verify the retained 700cde9 unit checkpoint without running the app."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent
load = lambda name: json.loads((root / name).read_text())
registry = load("source-registry.json")
results = load("unit-results.json")
previous_root = root.parents[1] / "polish-mac-40613521362/unit-failure-checkpoint"
previous = json.loads((previous_root / "selected-unit-results.json").read_text())
previous_correction = json.loads((previous_root / "correction-group-results.json").read_text())
old_census = json.loads((previous_root / "xcresult-census.json").read_text())
assert registry["run_id"] == results["run_id"] == 40619909088
assert registry["head_sha"] == results["head_sha"] == "700cde9be5867b8c0c625cc95ee9ac7cf141720a"
assert results["decoded_file_bytes"] == 4902220
assert results["decoded_file_sha256"] == "88e73bc370634a623c344d728301e1b1176a253b95d55aeba0f05aeebbf0aff6"
for group in ("whole_sources", "unchanged_gate_sources", "candidate_production_sources", "additional_gated_test_source"):
    for name, expected in registry[group].items():
        data = (root / "source" / name).read_bytes()
        assert len(data) == expected["bytes"] and hashlib.sha256(data).hexdigest() == expected["sha256"], name
        assert data == subprocess.check_output(["git", "show", registry["head_sha"] + ":" + name]), name
        if group != "additional_gated_test_source":
            assert data == subprocess.check_output(["git", "show", registry["prior_green_head"] + ":" + name]), name
        if group == "unchanged_gate_sources" or (group == "whole_sources" and not name.endswith("DictionaryPersistenceIsolationTests.swift")):
            assert data == subprocess.check_output(["git", "show", registry["known_red_head"] + ":" + name]), name

def issues(record):
    return [item for item in record.get("failure_summaries", []) if item.get("message")]

selected = results["selected_44"]
assert len(selected) == len({record["identifier"] for record in selected}) == 44
assert [record["identifier"] for record in selected] == [record["identifier"] for record in previous["case_details"]]
for record in selected:
    assert record["status"] == "Success" and not issues(record)
    assert len(record["decoded_summary_sha256"]) == 64 and record["summary_reference"]
selected_ids = {record["identifier"] for record in selected}
source_selected = set()
for path, methods in registry["positive_registry"].items():
    source = (root / "source" / path).read_text()
    assert methods == re.findall(r"@Test(?:\([^\n]*\))?\s+(?:@MainActor\s+)?func\s+(\w+)\s*\(", source)
    group = Path(path).stem
    prefix = "" if group == "ClipboardRestorationOwnershipTests" else "VoiceInkTests/"
    source_selected.update(prefix + group + "/" + method + "()" for method in methods)
source_selected.update(record["identifier"] for record in old_census["former_failures"])
assert source_selected == selected_ids
assert len(old_census["former_failures"]) == 3
assert [len(record["baseline"]["issues"]) for record in old_census["former_failures"]] == [2, 1, 2]
correction_ids = set()
for group, expected_count in {"WordReplacementLibraryAdapterTests": 6, "HistoryCorrectionApprovalTests": 7,
                              "DictionaryContextFreshnessTests": 2, "WordReplacementBackupAdapterTests": 10,
                              "DictionaryPersistenceIsolationTests": 4}.items():
    records = results["correction_29"][group]
    assert len(records) == expected_count
    assert [record["identifier"] for record in records] == [record["identifier"] for record in previous_correction["groups"][group]]
    for record in records:
        assert record["status"] == "Success" and not issues(record)
        assert record["identifier"] not in correction_ids
        correction_ids.add(record["identifier"])
assert len(correction_ids) == 29 and len(correction_ids.intersection(selected_ids)) == results["overlap"] == 7
assert results["all_record_count"] == 341
assert results["all_record_statuses"] == {"Success": 310, "Skipped": 31}
assert results["all_unique_identifiers"] == 339
assert results["unique_identifier_statuses_by_family"] == {
    "OnboardingRegionViewTests/": {"Success": 9}, "SwiftTesting": {"Success": 299, "Skipped": 31}
}
assert results["all_issue_message_count"] == 0
added = results["added_gated_case"]
assert added["identifier"] == "VoiceInkTests/liveWritingUndoSafariRejectsNormalizedDecomposedOutput()"
assert added["records"] == 1 and added["statuses"] == ["Skipped"]
assert len(added["case_details"]) == 1 and added["case_details"][0]["status"] == "Skipped"
assert "liveWritingUndoSafariRejectsNormalizedDecomposedOutput" in (root / "source/VoiceInkTests/WritingUndoLiveTests.swift").read_text()
print(json.dumps({"run_id": results["run_id"], "head_sha": results["head_sha"], "selected_success": 44,
                  "correction_success": 29, "overlap": 7, "unique_swift_identifiers": {"Success": 299, "Skipped": 31},
                  "unique_onboarding_xctest_identifiers": {"Success": 9}, "whole_workflow": "UI failed; Release skipped"}, indent=2))
