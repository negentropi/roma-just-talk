#!/usr/bin/env python3
import hashlib
import io
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = next(path for path in ROOT.parents if (path / ".git").exists())
ARTIFACT = ROOT / "artifact"
HEAD = "808c1a36609a05a20744c6a7a3abad7fce5715bb"
OLD = "919670ae5b918afbfad6f4d88982a481c1c4b532"
POLICY = "VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift"
TEST = "VoiceInkCore/Tests/VoiceInkCoreTests/LiteralCorrectionRuleTests.swift"
RUNNER = "VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift"
PREFIX = "LiteralCorrectionRuleTests."
digest = lambda value: hashlib.sha256(value).hexdigest()
read = lambda name: json.loads((ARTIFACT / name).read_text())

def git(*args):
    return subprocess.check_output(["git", "-C", str(REPO), *args])

def source(revision):
    entries = []
    for raw in git("ls-tree", "-r", "-z", revision, "--", "VoiceInkCore", "VoiceInkNVIDIA").split(b"\0"):
        if raw:
            metadata, path = raw.split(b"\t", 1)
            mode, kind, oid = metadata.decode().split()
            assert kind == "blob" and mode in {"100644", "100755"}
            entries.append((path.decode(), mode, oid))
    stream = io.BytesIO(subprocess.check_output(
        ["git", "-C", str(REPO), "cat-file", "--batch"],
        input=("\n".join(oid for _, _, oid in entries) + "\n").encode()))
    result = {}
    for path, mode, oid in entries:
        header = stream.readline().decode().split()
        assert header[:2] == [oid, "blob"]
        value = stream.read(int(header[2]))
        assert stream.read(1) == b"\n"
        result[path] = {"mode": mode, "gitObject": oid, "sha256": digest(value)}
    assert not stream.read()
    return result

def analyze():
    contract, comparison = read("contract.json"), read("comparison-result.json")
    assert contract["baselineSHA"] == comparison["baselineSHA"] == OLD
    assert contract["candidateSHA"] == comparison["candidateSHA"] == HEAD
    assert comparison["valid"] is True and comparison["classification"] == "matched-old-red-new-green"
    old, candidate = source(OLD), source(HEAD)
    assert old == contract["originalSource"] and candidate == contract["candidateSource"]
    assert {key for key in set(old) | set(candidate) if old.get(key) != candidate.get(key)} == {POLICY, TEST, RUNNER}
    for name, value in contract["helpers"].items():
        assert digest(git("show", HEAD + ":" + name)) == value
    oracle = (ARTIFACT / "oracle/LiteralCorrectionRuleTests.swift").read_bytes()
    runner = (ARTIFACT / "oracle/VoiceInkCoreCheckRunner.swift").read_bytes()
    old_runner = (ARTIFACT / "oracle/baseline-VoiceInkCoreCheckRunner.swift").read_bytes()
    assert oracle == git("show", HEAD + ":" + TEST)
    assert runner == git("show", HEAD + ":" + RUNNER)
    assert old_runner == git("show", OLD + ":" + RUNNER)
    assert digest(oracle) == contract["oracleSHA256"] == comparison["oracleSHA256"]
    assert digest(runner) == contract["runnerSHA256"] == comparison["runnerSHA256"]
    assert b"".join(line for line in runner.splitlines(keepends=True) if b'VoiceInkCoreCheck(name: "LiteralCorrectionRuleTests.' not in line) == old_runner
    for lane, revision in [("baseline", OLD), ("candidate", HEAD)]:
        assert (ARTIFACT / ("oracle/" + lane + "-DictionaryPolicy.swift")).read_bytes() == git("show", revision + ":" + POLICY)
    names = re.findall(r'VoiceInkCoreCheck\(name: "([^"]+)"', runner.decode())
    old_names = re.findall(r'VoiceInkCoreCheck\(name: "([^"]+)"', old_runner.decode())
    fresh = {name for name in names if name.startswith(PREFIX)}
    assert names == contract["registrations"] and old_names == contract["oldRegistrations"]
    assert len(names) == len(set(names)) == 1721 and len(old_names) == 1707 and len(fresh) == 14
    assert [name for name in names if name not in fresh] == old_names
    results = {}
    for lane in ["baseline", "candidate"]:
        log = (ARTIFACT / (lane + "-checks.log")).read_text()
        rows = re.findall(r"^(PASS|FAIL) (\S+)$", log, re.M)
        assert [name for _, name in rows] == names
        assert len(rows) == 1721 and "Build of product 'VoiceInkCoreChecks' complete!" in log
        failed = {name for verdict, name in rows if verdict == "FAIL"}
        retained = read(lane + "-result.json")
        code = int((ARTIFACT / (lane + "-exit.txt")).read_text())
        assert retained == comparison[lane] and retained["valid"] is True
        assert retained["failedMethods"] == sorted(failed) and retained["exitCode"] == code
        if lane == "baseline":
            assert code == 1 and len(failed) == 11 and failed <= fresh
            assert set(contract["requiredOldFailures"]) <= failed
            assert contract["legacyControl"] not in failed
            assert all(("PASS", name) in rows for name in old_names)
            assert retained["passed"] == 1710 and retained["assertionCount"] == len(retained["assertions"]) == 23
            summary = log.split("VoiceInkCoreChecks failed:\n")
            assert len(summary) == 2
            raw = [line for line in summary[1].splitlines() if line.strip()]
            assert raw == [value["raw"] for value in retained["assertions"]]
            command = read("baseline-command.json")["argv"]
            fixture = Path(command[command.index("--package-path") + 1]).parent / TEST
            for assertion in retained["assertions"]:
                match = re.fullmatch(r"(.+):(\d+): (.*)", assertion["raw"])
                assert match and Path(match[1]) == fixture and int(match[2]) == assertion["line"]
                assert assertion["method"] in failed and assertion["line"] in contract["assertionLines"][assertion["method"]]
                assert "unexpected thrown error" not in assertion["message"].lower()
        else:
            assert code == 0 and not failed and retained["passed"] == 1721
            assert log.count("Executed 1721 VoiceInkCore checks.") == 1
            assert "VoiceInkCoreChecks failed:\n" not in log and not retained["assertions"]
        expected = dict(old if lane == "baseline" else candidate)
        if lane == "baseline":
            expected.update({name: candidate[name] for name in [TEST, RUNNER]})
        assert read(lane + "-source-before.json") == read(lane + "-source-after.json") == expected
        packages = read(lane + "-packages.json")
        assert len(packages) == len(contract["packagePins"]) == 22
        for identity, value in packages.items():
            assert value["revision"] == contract["packagePins"][identity]["state"]["revision"]
            assert value["trackedChanges"] == ""
        results[lane] = {"registered": len(names), "executed": len(rows), "passed": retained["passed"],
                         "failedMethods": sorted(failed), "assertions": retained["assertionCount"], "exitCode": code}
    assert read("baseline-packages.json") == read("candidate-packages.json")
    assert (ARTIFACT / "toolchain-before.txt").read_bytes() == (ARTIFACT / "toolchain-after.txt").read_bytes()
    download = json.loads((ROOT / "download-receipt.json").read_text())
    actual_files = {str(path.relative_to(ARTIFACT)): path for path in ARTIFACT.rglob("*") if path.is_file()}
    assert set(actual_files) == {value["path"] for value in download["files"]}
    for value in download["files"]:
        path = actual_files[value["path"]]
        assert path.stat().st_size == value["bytes"] and digest(path.read_bytes()) == value["sha256"]
    return {"classification": "independent-artifact-audit-passed", "candidateSHA": HEAD, "baselineSHA": OLD,
            "oracleSHA256": digest(oracle), "runnerSHA256": digest(runner), "sourceFiles": {"baseline": len(old), "candidate": len(candidate)},
            "graphPins": 22, "oldControlsPassed": len(old_names), "newMethods": len(fresh), "lanes": results,
            "toolchainBeforeAfterEqual": True, "allRetainedArtifactFilesVerified": len(actual_files),
            "scope": "Core policy/codec/legacy-data boundaries only. No app activation, approval UI, SwiftData migration, provider or broader Unicode-quality claim."}

if __name__ == "__main__":
    print(json.dumps(analyze(), indent=2, sort_keys=True))
