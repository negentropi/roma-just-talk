#!/usr/bin/env python3
"""Audit the retained native Core run against its immutable Git source."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

directory = Path(__file__).resolve().parent
artifact = directory / "artifact"
revision = "143ce8fbb4b2cc3f5a8383d98f7ce8443e018dd5"
previous = "808c1a36609a05a20744c6a7a3abad7fce5715bb"
run_id = 40576969692
digest = lambda data: hashlib.sha256(data).hexdigest()
read_json = lambda path: json.loads(path.read_text())

run = read_json(directory / "run.json")
assert run["databaseId"] == run_id and run["headSha"] == revision
assert run["headBranch"] == "ci/rjt-core-check-polish-01a17bef"
assert run["status"] == "completed" and run["conclusion"] == "success"
assert len(run["jobs"]) == 1
job = run["jobs"][0]
assert job["status"] == "completed" and job["conclusion"] == "success"
assert all(step["status"] == "completed" and step["conclusion"] == "success" for step in job["steps"])
assert (artifact / "source-head.txt").read_text().strip() == revision
assert (artifact / "source-after-head.txt").read_bytes() == (artifact / "source-head.txt").read_bytes()
assert (artifact / "check-exit-code.txt").read_text().strip() == "0"
assert (artifact / "git-status.txt").read_bytes() == b""

roots = ["VoiceInkCore", "VoiceInkNVIDIA", ".github/workflows/voiceink-core-check.yml",
         "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]
tree = subprocess.check_output(["git", "ls-tree", "-r", "-z", revision, "--", *roots])
entries = {}
for row in tree.split(b"\0"):
    if row:
        metadata, raw_path = row.split(b"\t", 1)
        mode, kind, object_id = metadata.decode().split()
        assert mode in {"100644", "100755"} and kind == "blob"
        path = raw_path.decode()
        assert path not in entries
        entries[path] = {"git_mode": mode, "git_blob": object_id}
paths = sorted(entries)
requests = "".join(f"{revision}:{path}\n" for path in paths).encode()
batch = subprocess.check_output(["git", "cat-file", "--batch"], input=requests)
source = {}
position = 0
for path in paths:
    end = batch.index(b"\n", position)
    object_id, kind, raw_size = batch[position:end].decode().split()
    assert kind == "blob" and object_id == entries[path]["git_blob"]
    position = end + 1
    size = int(raw_size)
    source[path] = batch[position:position + size]
    position += size
    assert batch[position:position + 1] == b"\n"
    position += 1
assert position == len(batch)

manifest = {}
for line in (artifact / "source-before.sha256").read_text().splitlines():
    expected, path = line.split("  ", 1)
    assert path not in manifest and re.fullmatch("[0-9a-f]{64}", expected)
    manifest[path] = expected
assert list(manifest) == paths, "The retained manifest must cover every tracked file in the workflow's roots."
assert all(digest(source[path]) == expected for path, expected in manifest.items())
assert (artifact / "source-verification.log").read_text().splitlines() == [f"{path}: OK" for path in paths]

runner_path = "VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift"
pattern = r'VoiceInkCoreCheck\(name: "([^"]+)"'
registered = re.findall(pattern, source[runner_path].decode())
old_runner = subprocess.check_output(["git", "show", f"{previous}:{runner_path}"]).decode()
old_checks = re.findall(pattern, old_runner)
assert len(old_checks) == len(set(old_checks)) == 1721
assert len(registered) == len(set(registered)) == 1744
old_set = set(old_checks)
assert [name for name in registered if name in old_set] == old_checks
new_checks = [name for name in registered if name not in old_set]
families = {
    "WordReplacementLibraryCodecCompatibilityTests": ("WordReplacementLibraryTests.swift", 4),
    "WordReplacementLibraryTests": ("WordReplacementLibraryTests.swift", 10),
    "DictationDraftMetadataTests": ("DictationDraftMetadataTests.swift", 7),
    "ClarityStylePreferenceTests": ("ClarityStylePreferenceTests.swift", 2),
}
assert len(new_checks) == 23
for family, (filename, count) in families.items():
    names = [name for name in new_checks if name.startswith(family + ".")]
    assert len(names) == count
    body = source["VoiceInkCore/Tests/VoiceInkCoreTests/" + filename].decode()
    for name in names:
        method = name.split(".", 1)[1]
        assert len(re.findall(r"\bfunc " + method + r"\(", body)) == 1

log = (artifact / "core-checks.log").read_text()
assert re.findall(r"^(PASS|FAIL) (.+)$", log, re.MULTILINE) == [("PASS", name) for name in registered]
assert re.findall(r"^Executed (\d+) VoiceInkCore checks\.$", log, re.MULTILINE) == ["1744"]
assert not re.search(r"^FAIL |VoiceInkCoreChecks failed:|^error:", log, re.MULTILINE)
assert "Build of product 'VoiceInkCoreChecks' complete!" in log

locks = {}
for retained, path in {
    "Core": "VoiceInkCore/Package.resolved",
    "NVIDIA": "VoiceInkNVIDIA/Package.resolved",
    "Xcode": "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
}.items():
    data = (artifact / "pins" / f"{retained}.Package.resolved").read_bytes()
    assert data == source[path]
    lock = json.loads(data)
    assert len(lock["pins"]) == (41 if retained == "Xcode" else 22)
    locks[path] = {"sha256": digest(data), "format_version": lock["version"],
                   "pin_count": len(lock["pins"]), "unchanged_after_checks": True}

download = read_json(directory / "download-receipt.json")
metadata = read_json(directory / "artifact.json")
assert metadata["name"] == "roma.core-check-evidence" and not metadata["expired"]
assert metadata["workflow_run"]["id"] == run_id and metadata["workflow_run"]["head_sha"] == revision
assert metadata["workflow_run"]["head_branch"] == run["headBranch"]
assert download["artifact_id"] == metadata["id"] and download["run_id"] == run_id
assert download["download_count"] == 1 and download["all_members_crc_verified"]
assert download["zip_bytes"] == metadata["size_in_bytes"]
assert "sha256:" + download["zip_sha256"] == metadata["digest"]
members = download["members"]
actual_files = {str(path.relative_to(artifact)) for path in artifact.rglob("*") if path.is_file()}
assert actual_files == set(members)
for name, record in members.items():
    data = (artifact / name).read_bytes()
    assert len(data) == record["bytes"] and digest(data) == record["sha256"]

result = {
    "run_id": run_id, "run_url": run["url"], "source_head": revision, "conclusion": "success",
    "scope": "Full native Core compilation and policy/codec checks; no app activation, store migration, provider, UI, semantic-quality, release or known-bad comparison proof.",
    "command": "swift run --package-path VoiceInkCore --force-resolved-versions --skip-update VoiceInkCoreChecks",
    "checks": {"registered": 1744, "executed": 1744, "passed": 1744, "failed": 0, "skipped": 0,
               "ordered_pass_names_equal_all_registrations": True, "prior_checks_each_passed_once": 1721,
               "new_checks_each_passed_once": new_checks},
    "source_verification": {"file_count": len(manifest), "complete_workflow_source_census": True,
                            "all_before_hashes_match_pinned_git_blobs": True,
                            "all_after_hash_checks_passed": True, "head_unchanged": True, "git_status_empty": True},
    "locks": locks, "artifact": metadata, "download": download,
    "toolchain_before_checks": (artifact / "toolchain.log").read_text(),
    "limits": ["Actual dependency checkout trees were not retained; pins are verified lock bytes and frozen-resolution command.",
               "Toolchain was logged before compilation only; no post-check toolchain capture.",
               "Candidate compilation and feature checks only; no matched old-reader comparison in this run."],
    "warnings": re.findall(r"^warning: (.+)$", log, re.MULTILINE),
    "job_started_at": job["startedAt"], "job_completed_at": job["completedAt"],
}
(directory / "receipt.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"classification": "native-core-artifact-audit-passed", "checks": result["checks"],
                  "verified_source_files": len(manifest), "locks": locks}, indent=2))
