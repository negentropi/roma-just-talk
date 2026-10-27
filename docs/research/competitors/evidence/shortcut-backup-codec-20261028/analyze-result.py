#!/usr/bin/env python3
"""Recheck the retained actual-source decoder probe without compiling or running it."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent
digest = lambda data: hashlib.sha256(data).hexdigest()
load = lambda name: json.loads((root / name).read_text())
contract = load("contract.json")
manifest = load("retained-files.json")
for name, record in manifest.items():
    data = (root / name).read_bytes()
    assert len(data) == record["bytes"] and digest(data) == record["sha256"]

baseline = subprocess.check_output([
    "git", "show", contract["baseline_head"] + ":VoiceInk/Shortcuts/ShortcutMigration.swift"
])
assert baseline == (root / "baseline-ShortcutMigration.swift").read_bytes()
assert digest(baseline) == contract["baseline_full_file_sha256"]
for lane in ["baseline", "candidate"]:
    owner = (root / (lane + "-ShortcutMigration.swift")).read_bytes()
    prefix = owner.split(b"\nenum ShortcutMigration {", 1)[0].replace(b"import VoiceInkCore\n", b"")
    assert prefix == (root / ("Backup-" + lane + ".swift")).read_bytes()
    assert digest(prefix) == contract[lane + "_decoder_prefix_sha256"]
    assert digest(owner) == contract[lane + "_full_file_sha256"]
    assert load(lane + "-build.json")["exit"] == 0

shortcut = subprocess.check_output([
    "git", "show", contract["baseline_head"] + ":VoiceInk/Shortcuts/Shortcut.swift"
])
assert shortcut == (root / "Shortcut.swift").read_bytes()
assert digest(shortcut) == contract["actual_full_shortcut_sha256"]
monitor = subprocess.check_output([
    "git", "show", contract["baseline_head"] + ":VoiceInk/Shortcuts/ShortcutMonitor.swift"
]).decode()
event = re.search(r"final class ShortcutMonitor \{\n    enum EventKind \{[^}]+\}", monitor).group(0)
assert digest(event.encode()) == contract["actual_eventkind_slice_sha256"]
assert (root / "EventKind.swift").read_text() == event + "\n}\n"
fixture = "private enum ShortcutBackupDecodeFixtures {" + (root / "ShortcutBackupTests.swift").read_text().split(
    "private enum ShortcutBackupDecodeFixtures {", 1
)[1]
oracle = (root / "Oracle.swift").read_text()
assert fixture in oracle and digest(oracle.encode()) == contract["oracle_sha256"]
case_names = (["invalid-modern-" + str(index) for index in range(6)] + ["legacy-carbon-control"]
              + ["valid-modern-" + str(index) for index in range(3)]
              + ["invalid-legacy-" + str(index) for index in range(4)])
for lane, exit_code in [("baseline", 1), ("candidate", 0)]:
    log = (root / (lane + "-run.log")).read_text()
    expected = [("FAIL" if lane == "baseline" and name.startswith("invalid-modern-") else "PASS", name)
                for name in case_names]
    assert re.findall(r"^(PASS|FAIL) (.+)$", log, re.MULTILINE) == expected
    assert re.findall(r"^Executed (\d+); failures (\d+)$", log, re.MULTILINE) == [
        ("14", "6" if lane == "baseline" else "0")
    ]
    assert load(lane + "-run.json")["exit"] == exit_code
print(json.dumps({"classification": "actual-decoder-source-audit-passed", "cases": 14,
                  "baseline_failures": 6, "baseline_exit": 1, "candidate_failures": 0,
                  "candidate_exit": 0, "retained_files_verified": len(manifest)}, indent=2))
