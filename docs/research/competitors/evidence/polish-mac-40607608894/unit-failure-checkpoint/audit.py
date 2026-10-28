#!/usr/bin/env python3
"""Audit the retained unit checkpoint without downloading or running the app."""
import collections
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent
read_json = lambda name: json.loads((root / name).read_text())
run = read_json("run-final.json")
fail = read_json("failure-summary.json")
census = read_json("positive-census.json")
source = read_json("source/source-manifest.json")
head = "4b50179da8ea145738bae9dcd011aa6d93de8669"
assert run["databaseId"] == fail["run_id"] == census["run_id"] == 40607608894
assert run["headSha"] == fail["head_sha"] == census["head_sha"] == source["head"] == head
assert run["status"] == "completed" and run["conclusion"] == "failure"
assert fail["failed_log_fetch_count"] == 1
assert fail["failed_log_sha256"] == census["failed_log_sha256"]
assert fail["raw_summary"] == [["325", "34", "31.320 seconds with 5 issues."]]

for name, expected in source["whole_files"].items():
    data = (root / "source" / name).read_bytes()
    assert len(data) == expected["bytes"]
    assert hashlib.sha256(data).hexdigest() == expected["sha256"], name
for method, expected in source["red_method_extractions"].items():
    whole = (root / "source" / expected["source"]).read_text()
    # Extractions begin at @Test and end at the method's closing brace.
    lines = whole.splitlines(keepends=True)
    segment = "".join(lines[expected["first_line"] - 1:expected["last_line"]])
    original = segment.strip()
    assert len(original.encode()) == expected["method_bytes"], method
    assert hashlib.sha256(original.encode()).hexdigest() == expected["method_sha256"]
    kept = (root / "source/red-methods" / (method + ".swift")).read_bytes()
    assert kept == original.encode() + b"\n"
    assert hashlib.sha256(kept).hexdigest() == expected["retained_file_sha256"]

registry = read_json("source/positive-methods.json")
assert registry["head"] == head
positive = (root / "positive-records.log").read_text().splitlines()
assert len(positive) == 74
counts = collections.defaultdict(collections.Counter)
for line in positive:
    m = re.search(r"\bTest (\w+)\(\) (started\.|(passed|failed|skipped) after |recorded an issue)", line)
    assert m, line
    counts[m[1]]["started" if m[2] == "started." else (m[3] or "issue")] += 1
expected_groups = {
    "VoiceInkTests/WritingActionUndoTests.swift": 20,
    "VoiceInkTests/WritingActionUndoPipelineTests.swift": 8,
    "VoiceInkTests/ClipboardRestorationOwnershipTests.swift": 5,
    "VoiceInkTests/ShortcutBackupTests.swift": 3,
    "VoiceInkTests/AudioFileTranscriptionPersistenceTests.swift": 1,
}
assert set(census["groups"]) == set(expected_groups)
all_methods = []
for path, size in expected_groups.items():
    group = census["groups"][path]
    names = [m["method"] for m in group["methods"]]
    source_names = re.findall(r"@Test(?:\([^\n]*\))?\s+(?:@MainActor\s+)?func\s+(\w+)\s*\(", (root / "source" / path).read_text())
    assert names == registry["groups"][path] == source_names, path
    assert group["expected"] == group["actual_passed"] == len(names) == size
    for method in group["methods"]:
        assert method["starts"] == 1 and method["results"] == ["passed"] and method["issues"] == 0
        assert counts[method["method"]] == {"started": 1, "passed": 1}
    all_methods.extend(names)
assert len(all_methods) == len(set(all_methods)) == census["total_exact_once_passed"] == 37
assert set(counts) == set(all_methods)

red = (root / "failed-test-records.log").read_text()
expected_failures = {
    "failedApprovalSaveKeepsExistingRulesAndUnrelatedUnsavedEdits": ("HistoryCorrectionApprovalTests.swift", [214, 216]),
    "failedSaveRemovesOnlyImportInsertionsAndPreservesUnrelatedDirtyEdits": ("WordReplacementBackupAdapterTests.swift", [217]),
    "failedEditToggleAndDeleteRestoreOnlyTheirOwnEntry": ("WordReplacementLibraryAdapterTests.swift", [185, 185]),
}
assert set(fail["failed_methods"]) == set(expected_failures)
assert len(fail["actual_issues"]) == 5
for method, (file, lines) in expected_failures.items():
    assert len(re.findall(r"\bTest " + method + r"\(\) started\.", red)) == 1
    assert len(re.findall(r"\bTest " + method + r"\(\) failed after ", red)) == 1
    issues = [line for line in fail["actual_issues"] if "Test " + method + "() recorded an issue" in line]
    assert len(issues) == len(lines)
    assert [int(re.search(re.escape(file) + r":(\d+):", line)[1]) for line in issues] == lines
    assert all(line in red for line in issues)
assert "(after.count → 3) == (before.count → 2)" in red
assert "** TEST EXECUTE FAILED **" in red

steps = {step["name"]: step["conclusion"] for step in run["jobs"][0]["steps"]}
assert steps["Full Mac unit suite with fresh CI permissions"] == "failure"
for step in ("Live TextEdit and Safari selection transactions", "Matched snippet regression", "Writing, snippet and dictation settings UI", "Release build and packaging contracts"):
    assert steps[step] == "skipped", step
print(json.dumps({"run_id": run["databaseId"], "head_sha": head, "unit_gate": "failure", "failed_cases": 3, "issues": 5, "exact_once_positive_methods": 37, "whole_source_files": len(source["whole_files"])}, indent=2))
