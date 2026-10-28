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
head = "0184f9a1552d281cd6b416446b92e091b6bdad29"
assert source["head_sha"] == units["head_sha"] == core["head_sha"] == run["headSha"] == head
assert source["run_id"] == units["run_id"] == core["run_id"] == run["databaseId"] == 40655003105
assert run["status"] == "completed" and run["conclusion"] == "success"
assert run["displayTitle"] == "Verify Mac writing actions (full)"
steps = {step["name"]: step["conclusion"] for job in run["jobs"] for step in job["steps"]}
for name in ("Verify the canonical package graph before compiling", "Shared core checks",
             "Prepare and verify static Whisper dependencies", "Full Mac unit suite with fresh CI permissions",
             "Live TextEdit and Safari selection transactions", "Matched snippet regression"):
    assert steps[name] == "success", name
assert steps["Writing, snippet and dictation settings UI"] == "success"
assert steps["Release build and packaging contracts"] == steps["Upload verified release app"] == "success"

snapshot_root = root.parents[1] / "history-correction-full-40639673814/unit-failure-checkpoint/source"
for name, record in source["sources"].items():
    data = (snapshot_root / name).read_bytes()
    assert len(data) == record["bytes"] and hashlib.sha256(data).hexdigest() == record["sha256"], name
    assert data == subprocess.check_output(["git", "show", head + ":" + name]), name
    assert record["unchanged_from_prior_normal_full"] is True
    assert data == subprocess.check_output(["git", "show", source["prior_normal_full_head"] + ":" + name]), name
    if record["unchanged_from_700"]:
        assert data == subprocess.check_output(["git", "show", source["prior_full_unit_head"] + ":" + name]), name
for name in ("HistoryCorrectionApprovalTests", "WordReplacementBackupAdapterTests", "WordReplacementLibraryAdapterTests"):
    path = "VoiceInkTests/" + name + ".swift"
    assert (snapshot_root / path).read_bytes() == subprocess.check_output(["git", "show", source["known_red_head"] + ":" + path])

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
assert units["decoded_file_bytes"] == 4899023
assert units["decoded_file_sha256"] == "14bfee37f3ccf9606b59556889201c5126df9b818cf78e69e67620e4502ca781"
assert units["all_record_count"] == 341 and units["all_record_statuses"] == {"Success": 310, "Skipped": 31}
assert units["all_unique_identifiers"] == 339 and units["all_issue_message_count"] == 0
assert units["unique_identifier_statuses_by_family"] == {
    "OnboardingRegionViewTests/": {"Success": 9}, "SwiftTesting": {"Success": 299, "Skipped": 31}
}
assert len(core["release_artifact_members"]["release_build_logs"]) == 2
assert len(core["release_artifact_members"]["release_app_hashes"]) == 1
regression = raw / "writing-feature-regression"
matched = json.loads((regression / "result.json").read_text())
assert matched["classification"] == "matched-red-green" and matched["candidate"] == head
assert matched["baseline"] == "ec7bc1bcf804cb9362e342e4c3f5fbf2dd9b69eb"
baseline = json.loads((regression / "baseline-result.json").read_text())
candidate = json.loads((regression / "candidate-result.json").read_text())
names = ["spokenSnippetPipelineInsertsExactWholeTriggerContentAndSavesIt",
         "spokenSnippetPipelinePreservesInlineCapitalsPunctuationAndParagraphs",
         "spokenSnippetPipelineLeavesUnmatchedDictationOnItsExistingFormattingPath"]
assert baseline["exit_code"] == 65 and candidate["exit_code"] == 0
assert baseline["tests"] == dict(zip(names, ["failed", "failed", "passed"]))
assert candidate["tests"] == dict.fromkeys(names, "passed")
for lane, expected in (("baseline", baseline), ("candidate", candidate)):
    log = (regression / (lane + "-tests.log")).read_text()
    for name, outcome in expected["tests"].items():
        assert len(re.findall(r"\bTest " + name + r"\(\) started\.", log)) == 1
        assert len(re.findall(r"\bTest " + name + r"\(\) " + outcome + r" after ", log)) == 1
    issues = re.findall(r"Test (\w+)\(\) recorded an issue at ([^\n]+)", log)
    if lane == "baseline":
        assert [name for name, _ in issues] == [names[0]] * 5 + [names[1]] * 4
        assert all("SpokenSnippetPipelineTests.swift:" in issue for _, issue in issues)
    else:
        assert not issues
native = load("native-six-results.json")
assert native["run_id"] == run["databaseId"] and native["scope"] == "live"
assert hashlib.sha256((root / "native-six-results.json").read_bytes()).hexdigest() == "165d31b6e623576e27315bb579f7fb8356af66fe466901865ec2aa257566791b"
native_names = ["liveWritingTargetTextEditPreservesUnicodeOutsideSelection",
                "liveWritingTargetTextEditRefusesRangeTextAndFocusDrift",
                "liveWritingTargetSafariTextareaReplacesOnlySelection",
                "liveWritingActionPipelineUsesLocalCLIAndRetainsFailure",
                "liveWritingStartupContextRespectsOwnerAfterCancellation",
                "liveDictationProfileKeepsContextEligibilityAcrossPreferenceChanges"]
assert len(native["case_details"]) == len({case["identifier"] for case in native["case_details"]}) == 6
assert [case["identifier"] for case in native["case_details"]] == ["VoiceInkTests/" + name + "()" for name in native_names]
native_dir = raw / "writing-proof-snapshot/onboarding-test-evidence/writing-target-live"
native_result = json.loads((native_dir / "result.json").read_text())
assert native_result["exit_code"] == 0 and native_result["tests"] == dict.fromkeys(native_names, "passed")
native_log = (native_dir / "tests.log").read_text()
for case, name in zip(native["case_details"], native_names):
    assert case["status"] == "Success" and not [item for item in case["failure_summaries"] if item.get("message")]
    assert len(re.findall(r"\bTest " + name + r"\(\) started\.", native_log)) == 1
    assert len(re.findall(r"\bTest " + name + r"\(\) passed after ", native_log)) == 1
assert not re.search(r"Test \w+\(\) recorded an issue", native_log)
assert (native_dir / "identity-before.txt").read_bytes() == (native_dir / "identity-after.txt").read_bytes()
release = load("release-results.json")
assert release["run_id"] == run["databaseId"] and release["head_sha"] == head
release_log = (root / "raw" / release["make_log_member"]).read_bytes()
assert len(release_log) == release["make_log_bytes"] == 4863549
assert hashlib.sha256(release_log).hexdigest() == release["make_log_sha256"] == "bb1689ce52b91363b0f9dfb28157a0aefe24a0da54c77e36432ae62bcdaebbbf"
for required in ("-configuration Release", "ENABLE_CODE_COVERAGE=NO", "** BUILD SUCCEEDED **",
                 "Verified statically linked Whisper app: 8 Mach-O files",
                 "Verified ad-hoc Library Validation contract: @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"):
    assert required in release_log.decode(), required
hash_line = (root / "raw" / release["app_hash_member"]).read_text()
assert re.fullmatch(r"[a-f0-9]{64}  .+roma\.just\.talk\.app\.zip\n", hash_line)
assert hash_line.split()[0] == release["recorded_app_zip_sha256"] == "e4f31cfa5dca2cd9c0ba130dc0d80c53f00d5ba05200e496f3784cc577cc34b6"
release_head_members = [name for name in core["archive_members"] if name.endswith("writing-check-evidence/source-sha.txt")]
assert len(release_head_members) == 1 and (root / "raw" / release_head_members[0]).read_text().strip() == head
workflow = (snapshot_root / ".github/workflows/voiceink-writing-actions-check.yml").read_text()
for command in ('codesign --verify --deep --strict "$app"', 'bash scripts/verify-static-whisper-app.sh "$app"',
                'bash scripts/verify-adhoc-library-validation.sh "$app"', 'bash scripts/verify-macos-release-instrumentation.sh "$app"',
                'test "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = com.negentropi.RomaJustTalk'):
    assert command in workflow
print(json.dumps({"run_id": run["databaseId"], "head_sha": head, "mode": "full", "core_pass": 1758,
                  "canonical_pins": 41, "focused_unit_success": 44, "correction_success": 29, "overlap": 7,
                  "unique_swift_identifiers": {"Success": 299, "Skipped": 31}, "onboarding_xctest_success": 9,
                  "literal_snippet_regression": "two old failures plus one passing control; three candidate passes",
                  "native_case_success": 6, "recorded_app_zip_sha256": release["recorded_app_zip_sha256"],
                  "release": "CI packaging verified", "whole_workflow": "success"}, indent=2))
