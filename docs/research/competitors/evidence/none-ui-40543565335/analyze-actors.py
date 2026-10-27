#!/usr/bin/env python3
"""Reproduce direct controls and background traits; traits do not prove routing."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
out = {"run_id": 40543565335, "lanes": {}}
for lane in ("baseline", "candidate"):
    before = json.loads((root / f"{lane}-boundary-before-opening.json").read_text())
    after = json.loads((root / f"{lane}-boundary-after-opening.json").read_text())
    foreground = {key: after["actors"][key] for key in ("custom", "none", "settings-close")}
    unreachable = [key for key, actor in foreground.items()
                   if not (actor["exists"] and actor["enabled"] and actor["hittable"])]
    out["lanes"][lane] = {
        "before": before, "after": after,
        "foreground_boundary_failures": unreachable,
        "background_action_attempted": False,
    }
assert out["lanes"]["baseline"]["foreground_boundary_failures"] == ["custom", "none"]
assert out["lanes"]["candidate"]["foreground_boundary_failures"] == []
assert out["lanes"]["candidate"]["after"]["nativeSheetCount"] == 1
print(json.dumps(out, indent=2, sort_keys=True))
