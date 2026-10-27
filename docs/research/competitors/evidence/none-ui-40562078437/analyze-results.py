#!/usr/bin/env python3
"""Reproduce the matched Debug UI verdict from original source-bound evidence."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parent
result = json.loads((root / "comparison-result.json").read_text())
bindings = json.loads((root / "source-bindings.json").read_text())
source = json.loads((root / "source-verification.json").read_text())
assert result["baseline"]["valid"] and result["baseline"]["expected_assertion_line"] == 353
assert result["baseline"]["starts"] == 1 and result["baseline"]["results"] == ["failed"]
assert result["candidate_valid"] and result["candidate"]["exit_code"] == 0
assert len(result["candidate"]["tests"]) == 4
assert all(v["starts"] == 1 and v["results"] == ["passed"] for v in result["candidate"]["tests"].values())
assert source["valid"] and source["candidate_sha"] == bindings["candidate_sha"]
assert source["baseline_sha"] == bindings["baseline_sha"]
contract = json.loads((root / "comparison-contract.json").read_text())
assert contract["candidate_sha"] == source["candidate_sha"]
assert contract["canonical_lock_sha256"] == bindings["inputs"]["VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]
assert source["oracle_sha256"] == bindings["inputs"]["VoiceInkUITests/WritingFeaturesUITests.swift"]
for row in (root / "runtime-source-inputs.sha256").read_text().splitlines():
    expected, path = row.split("  ", 1)
    actual = hashlib.sha256(subprocess.check_output(["git", "show", bindings["candidate_sha"] + ":" + path])).hexdigest()
    assert actual == expected == bindings["inputs"][path]
assert all(v["valid"] for lane in ("baseline_identity_and_tcc", "candidate_identity_and_tcc") for v in result[lane].values())
for name, record in json.loads((root / "selected-members.json").read_text()).items():
    data = (root / name).read_bytes()
    assert len(data) == record["bytes"] and hashlib.sha256(data).hexdigest() == record["sha256"]
pointer = json.loads((root / "candidate-after-background-pointer-1.json").read_text())
assert pointer["backgroundPointerAttempted"] and pointer["nativeSheetCount"] == 1 and not pointer["boundaryFailures"]
assert all(pointer["actors"][name][key] is True for name in ("custom", "none", "settings-close") for key in ("exists", "enabled", "hittable"))
for opening in (1, 2, 3):
    observed = json.loads((root / f"candidate-after-opening-{opening}.json").read_text())
    assert observed["nativeSheetCount"] == 1 and not observed["boundaryFailures"]
for closing in (1, 3):
    observed = json.loads((root / f"candidate-after-closing-{closing}.json").read_text())
    assert observed["nativeSheetCount"] == 0 and not observed["boundaryFailures"]
    assert all(observed["actors"][name][key] is True for name in ("settings-open", "background-filter") for key in ("exists", "enabled", "hittable"))
log = (root / "candidate-tests.log").read_text()
assert ": error:" not in log and "Executed 4 tests, with 0 failures (0 unexpected)" in log
for panel in ("Dictionary settings", "Enhancement settings", "Prompt editor unsaved", "Power Mode unsaved", "Power Mode reorder"):
    assert f"Added attachment named '{panel} native sheet'" in log
assert 'Click "powerMode.reorder.close" Button' in log
assert 'Checking existence of `"powerMode.configuration.cancel" Button`' in log
print(json.dumps({"baseline_intended_red": True, "candidate_cases": 4, "candidate_passed": 4,
                  "candidate_failed_or_skipped": 0, "source_identity_tcc_process_verified": True,
                  "model_background_pointer_attempted": True, "shared_panel_screenshots": 5,
                  "power_mode_cancel_and_reorder_completed": True,
                  "accepted_scope": "Debug native UI only"}, indent=2))
