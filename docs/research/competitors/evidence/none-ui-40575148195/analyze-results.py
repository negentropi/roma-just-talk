#!/usr/bin/env python3
"""Verify the matched UI verdict and original typed shortcut censuses."""
import hashlib
import json
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parent
result = json.loads((root / "comparison-result.json").read_text())
bindings = json.loads((root / "source-bindings.json").read_text())
source = json.loads((root / "source-verification.json").read_text())
assert result["baseline"]["valid"] and result["baseline"]["expected_assertion_line"] == 377
assert result["baseline"]["starts"] == 1 and result["baseline"]["results"] == ["failed"]
assert result["candidate_valid"] and result["candidate"]["exit_code"] == 0
assert len(result["candidate"]["tests"]) == 4
assert all(v["starts"] == 1 and v["results"] == ["passed"] for v in result["candidate"]["tests"].values())
assert source["valid"] and source["candidate_sha"] == bindings["candidate_sha"]
assert source["baseline_sha"] == bindings["baseline_sha"]
assert source["oracle_sha256"] == bindings["inputs"]["VoiceInkUITests/WritingFeaturesUITests.swift"]
for row in (root / "runtime-source-inputs.sha256").read_text().splitlines():
    expected, path = row.split("  ", 1)
    actual = hashlib.sha256(subprocess.check_output(["git", "show", bindings["candidate_sha"] + ":" + path])).hexdigest()
    assert actual == expected == bindings["inputs"][path]
assert all(v["valid"] for lane in ("baseline_identity_and_tcc", "candidate_identity_and_tcc") for v in result[lane].values())
for name, record in json.loads((root / "selected-members.json").read_text()).items():
    data = (root / name).read_bytes()
    assert len(data) == record["bytes"] and hashlib.sha256(data).hexdigest() == record["sha256"]
expected = {"primaryRecordingShortcut": "custom", "secondaryRecordingShortcut": "none",
            "primaryRecordingShortcutMode": "hybrid", "secondaryRecordingShortcutMode": "hybrid",
            "Shortcut_LegacyKeyboardShortcutsMigrated": True, "Shortcut_LegacyCustomRecordingShortcutsMigrated": True,
            "isMiddleClickToggleEnabled": False, "specialShortcutDoubleShiftTapInterval": 0}
actions = ("primaryRecording", "secondaryRecording", "pasteLastTranscription", "pasteLastEnhancement",
           "retryLastTranscription", "openHistoryWindow", "quickAddToDictionary", "translateRecording",
           "rewriteSelectionRecording", "draftRecording")
groups = {}
for path in root.glob("*-shortcut-*.json"):
    value = json.loads(path.read_text())
    assert value["version"] == 1 and value["synchronized"] is True
    case = path.name.split("-shortcut-")[0]
    groups.setdefault(case, {}).setdefault(value["phase"], []).append(value)
assert len(groups) == 5
summaries = {}
for case, phases in sorted(groups.items()):
    assert set(phases) == {"before", "isolated", "after-launch", "restored"}
    assert all(len(phases[name]) == 1 for name in ("before", "isolated", "restored"))
    expected_launches = 1 if case.startswith("baseline-") or "testCSVImport" in case else 2
    assert len(phases["after-launch"]) == expected_launches
    before, restored = phases["before"][0]["keys"], phases["restored"][0]["keys"]
    assert before == restored
    for census in phases["isolated"] + phases["after-launch"]:
        keys = census["keys"]
        for key, wanted in expected.items():
            actor = keys[key]
            assert actor["exists"] and actor["value"] == wanted
            if type(wanted) is bool:
                assert actor["numberEncoding"] == "c" and type(actor["value"]) is bool
            elif type(wanted) is int:
                assert actor["numberEncoding"] != "c" and type(actor["value"]) is int
        for action in actions:
            cleared = keys["Shortcut_" + action + "_cleared"]
            assert cleared["exists"] and cleared["value"] is True and cleared["numberEncoding"] == "c"
            assert keys["Shortcut_" + action] == before["Shortcut_" + action]
    summaries[case] = {"phase_counts": {name: len(rows) for name, rows in phases.items()},
                       "key_count": len(before), "redacted_before_restored_equal": True,
                       "runtime_restore_assertion_succeeded": True,
                       "dynamic_power_mode_keys_present": any(key.startswith("Shortcut_powerMode_") for key in before)}
pointer = json.loads((root / "candidate-after-background-pointer-1.json").read_text())
assert pointer["backgroundPointerAttempted"] and pointer["nativeSheetCount"] == 1 and not pointer["boundaryFailures"]
for opening in (1, 2, 3):
    observed = json.loads((root / f"candidate-after-opening-{opening}.json").read_text())
    assert observed["nativeSheetCount"] == 1 and not observed["boundaryFailures"]
for closing in (1, 3):
    observed = json.loads((root / f"candidate-after-closing-{closing}.json").read_text())
    assert observed["nativeSheetCount"] == 0 and not observed["boundaryFailures"]
log = (root / "candidate-tests.log").read_text()
assert ": error:" not in log and "Executed 4 tests, with 0 failures (0 unexpected)" in log
assert "Unexpected recording notification" not in log
for panel in ("Dictionary settings", "Enhancement settings", "Prompt editor unsaved", "Power Mode unsaved", "Power Mode reorder"):
    assert f"Added attachment named '{panel} native sheet'" in log
assert 'Click "powerMode.reorder.close" Button' in log
assert len(list(root.glob("*.png"))) == 10
print(json.dumps({"baseline_intended_red": True, "candidate_passed": 4, "candidate_failed_or_skipped": 0,
                  "source_identity_tcc_process_verified": True, "shortcut_censuses": summaries,
                  "unexpected_microphone_notification_observed": False,
                  "historical_typing_trigger_attributed": False,
                  "acceptance": "Matched Debug UI; no Release, speech or VoiceOver proof"}, indent=2, sort_keys=True))
