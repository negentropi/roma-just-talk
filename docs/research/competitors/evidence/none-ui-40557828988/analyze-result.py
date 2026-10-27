#!/usr/bin/env python3
"""Distinguish an intended baseline red from candidate compile failure; no UI acceptance."""
import json
from pathlib import Path
root = Path(__file__).resolve().parent
result = json.loads((root / "comparison-result.json").read_text())
assert result["baseline"]["valid"] is True
assert result["baseline"]["expected_assertion_line"] == 353
assert result["candidate"]["boundary"] == "ui-build"
assert result["candidate"]["classification"] == "invalid"
log = (root / "candidate-driver.log").read_text()
assert "recursive expansion of macro 'require(_:_:sourceLocation:)'" in log
assert "** TEST BUILD FAILED **" in log
assert "Test Case '-[VoiceInkUITests.WritingFeaturesUITests" not in log
source = (root / "owning-source-excerpt.txt").read_text()
assert '53:         phase = try #require(Phase(rawValue: try #require(Self.value("RJT_STORE_PHASE"))))' in source
print(json.dumps({"baseline_intended_red": True, "baseline_assertion_line": 353,
                  "candidate_ui_cases_executed": 0, "candidate_boundary": "ui-build",
                  "cause": "nested require macro in DictationStoreSeedLiveTests.swift:53",
                  "candidate_accepted": False}, indent=2))
