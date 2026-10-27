#!/usr/bin/env python3
"""Validate the retained Core receipt against the exact compiled source revision."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

directory = Path(__file__).resolve().parent
artifact = directory / "artifact"
revision = "aaaa286a794ac6f60773ef5149a30f214c586f23"
run = json.loads((directory / "run.json").read_text())
assert run["headSha"] == revision and run["status"] == "completed"
assert run["conclusion"] == "success" and len(run["jobs"]) == 1
assert all(step["conclusion"] == "success" for step in run["jobs"][0]["steps"])
assert (artifact / "source-head.txt").read_text().strip() == revision
assert (artifact / "source-after-head.txt").read_bytes() == (artifact / "source-head.txt").read_bytes()
assert (artifact / "check-exit-code.txt").read_text().strip() == "0"
assert (artifact / "git-status.txt").read_bytes() == b""

def source(path):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"])

digest = lambda data: hashlib.sha256(data).hexdigest()
manifest = {}
for line in (artifact / "source-before.sha256").read_text().splitlines():
    expected, path = line.split("  ", 1)
    assert path not in manifest and digest(source(path)) == expected, path
    manifest[path] = expected
assert (artifact / "source-verification.log").read_text().splitlines() == [
    f"{path}: OK" for path in manifest
]

runner_path = "VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift"
registered = re.findall(r'VoiceInkCoreCheck\(name: "([^"]+)"', source(runner_path).decode())
assert len(registered) == len(set(registered)) == 1707
log = (artifact / "core-checks.log").read_text()
passed = re.findall(r"^PASS (.+)$", log, re.MULTILINE)
assert passed == registered
assert not re.search(r"^FAIL |VoiceInkCoreChecks failed:", log, re.MULTILINE)
assert re.findall(r"^Executed (\d+) VoiceInkCore checks\.$", log, re.MULTILINE) == ["1707"]
new_checks = [name for name in registered if name.startswith("DictationPolishTests.")]
assert len(new_checks) == 8 and all(passed.count(name) == 1 for name in new_checks)

locks = {}
for retained, path in {
    "Core": "VoiceInkCore/Package.resolved",
    "NVIDIA": "VoiceInkNVIDIA/Package.resolved",
    "Xcode": "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
}.items():
    data = (artifact / "pins" / f"{retained}.Package.resolved").read_bytes()
    assert data == source(path)
    lock = json.loads(data)
    locks[path] = {"sha256": digest(data), "format_version": lock["version"],
                   "pin_count": len(lock["pins"]), "unchanged_after_checks": True}

result = {
    "run_id": 40562076345,
    "run_url": run["url"],
    "source_head": revision,
    "conclusion": "success",
    "scope": "Full Core compilation and policy checks; no app integration, UI, model inference, AI-quality, release, or known-bad comparison proof.",
    "command": "swift run --package-path VoiceInkCore --force-resolved-versions --skip-update VoiceInkCoreChecks",
    "checks": {"registered": 1707, "executed": len(passed), "passed": len(passed),
               "failed": 0, "skipped": 0, "ordered_pass_names_equal_all_registrations": True,
               "new_checks_each_passed_once": new_checks},
    "source_verification": {"file_count": len(manifest), "all_before_hashes_match_pinned_git_blobs": True,
                            "all_after_hash_checks_passed": True, "head_unchanged": True,
                            "git_status_empty": True},
    "locks": locks,
    "toolchain_before_checks": (artifact / "toolchain.log").read_text(),
    "toolchain_limit": "Toolchain logged once before compilation; no separate post-check toolchain capture.",
    "warnings": re.findall(r"^warning: (.+)$", log, re.MULTILINE),
    "job_started_at": run["jobs"][0]["startedAt"],
    "job_completed_at": run["jobs"][0]["completedAt"],
    "artifact": json.loads((directory / "artifact.json").read_text()),
    "retained_artifact_file_sha256": {
        str(path.relative_to(directory)): digest(path.read_bytes())
        for path in sorted(artifact.rglob("*")) if path.is_file()
    },
}
(directory / "receipt.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"checks": result["checks"], "verified_source_files": len(manifest),
                  "locks": locks}, indent=2))
