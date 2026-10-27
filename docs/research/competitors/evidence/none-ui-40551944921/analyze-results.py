#!/usr/bin/env python3
"""Verify source-bound partial success without promoting a failed candidate to acceptance."""
import json
from pathlib import Path
root = Path(__file__).resolve().parent
result = json.loads((root / "comparison-result.json").read_text())
assert result["baseline"]["valid"] is True
assert result["baseline"]["expected_assertion_line"] == 353
cases = result["candidate"]["tests"]
assert len(cases) == 4 and sum(v["results"] == ["passed"] for v in cases.values()) == 3
assert cases["testDictationProfilePreservesCustomSettingsAndPersists"]["results"] == ["failed"]
actors = json.loads((root / "candidate-after-background-pointer-1.json").read_text())
assert actors["backgroundPointerAttempted"] is True and actors["nativeSheetCount"] == 1
assert not actors["boundaryFailures"]
for name in ("custom", "none", "settings-close"):
    assert all(actors["actors"][name][key] is True for key in ("exists", "enabled", "hittable"))
for opening in (1, 2, 3):
    after = json.loads((root / f"candidate-after-opening-{opening}.json").read_text())
    assert after["nativeSheetCount"] == 1 and not after["boundaryFailures"]
for lane in ("baseline", "candidate"):
    for check in ("identity", "tcc", "process"):
        assert json.loads((root / f"{lane}-{check}-verification.json").read_text())["valid"] is True
clicks = (root / "pointer-clicks.txt").read_text()
counts = {name: clicks.count(f'Click "{name}" Button') for name in
          ("models.settings.open", "dictionary.settings.open", "powerMode.configuration.add")}
assert list(counts.values()) == [4, 2, 1]
assert "The background pointer probe overlapped the active sheet." in (root / "overlap-context.txt").read_text()
print(json.dumps({"baseline_intended_red": True, "candidate_passed": 3, "candidate_failed": 1,
                  "model_background_pointer_attempted": True, "click_counts": counts,
                  "both_lane_identity_tcc_process_verified": True,
                  "candidate_accepted": False, "scope": "Partial UI assertions only"}, indent=2))
