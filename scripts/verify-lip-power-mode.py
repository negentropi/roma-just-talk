#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


if os.environ.get("GITHUB_ACTIONS") != "true" or sys.platform != "darwin":
    raise SystemExit("Run on a disposable macOS Actions host.")

root = Path(__file__).resolve().parent.parent
source = root / "VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift"
runner = root / "VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift"
candidate = source.read_bytes()
evidence = root / ".local-build/lip-power-mode-regression"
evidence.mkdir(parents=True, exist_ok=False)
receipt = {
    "status": "running",
    "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
    "githubRunID": os.environ.get("GITHUB_RUN_ID"),
    "githubRunAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
    "githubJob": os.environ.get("GITHUB_JOB"),
    "candidateSourceSHA256": hashlib.sha256(candidate).hexdigest(),
    "runnerSHA256": hashlib.sha256(runner.read_bytes()).hexdigest(),
    "testSourceSHA256": hashlib.sha256((
        root / "VoiceInkCore/Tests/VoiceInkCoreTests/PowerModeLipDictationTests.swift"
    ).read_bytes()).hexdigest(),
    "knownBadChange": "Apply audio-model resources to text-only Power Mode sessions.",
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def save_receipt():
    (evidence / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


expected = re.findall(r'^\s*VoiceInkCoreCheck\(name: "([^"]+)"', runner.read_text(), re.MULTILINE)
require(expected and len(expected) == len(set(expected)), "Core runner checks must be nonempty and unique")
receipt["expectedChecks"] = len(expected)
failed_names = [
    "PowerModeLipDictationTests.testLipOnlyAppliesTextPreferencesWithoutSelectingOrLoadingAudioModel",
    "PowerModeLipDictationTests.testReusedAndRecoveredLipSessionRetainsTextOnlyRestoration",
]
require(set(failed_names) <= set(expected), "Expected lip-only checks missing from the actual runner")
guard = "modelResourcePlan: applicationScope == .textOnly ? nil : VoiceInkPowerModeTranscriptionModelResourcePlan.plan("
require(candidate.decode().count(guard) == 1, "Expected one text-only resource exclusion")
mutant = candidate.decode().replace(guard, "modelResourcePlan: VoiceInkPowerModeTranscriptionModelResourcePlan.plan(", 1)
receipt["mutantSourceSHA256"] = hashlib.sha256(mutant.encode()).hexdigest()


def run(label):
    log = evidence / f"{label}.log"
    print(f"Running {label}: {len(expected)} actual VoiceInkCoreChecks", flush=True)
    with log.open("w") as output:
        result = subprocess.run(
            ["swift", "run", "--package-path", "VoiceInkCore", "VoiceInkCoreChecks"],
            cwd=root, stdout=output, stderr=subprocess.STDOUT, text=True,
        )
    text = log.read_text()
    outcomes = re.findall(r"^(PASS|FAIL) (\S+)$", text, re.MULTILINE)
    summary = {
        "exitCode": result.returncode,
        "totalChecks": len(outcomes),
        "passedChecks": sum(outcome == "PASS" for outcome, _ in outcomes),
        "failedChecks": [name for outcome, name in outcomes if outcome == "FAIL"],
    }
    receipt[label] = summary
    (evidence / f"{label}.json").write_text(json.dumps(summary, indent=2) + "\n")
    save_receipt()
    require([name for _, name in outcomes] == expected,
            f"{label} did not execute every registered check exactly once; see {log}")
    return result.returncode, summary, text


try:
    try:
        source.write_text(mutant)
        red_exit, red, _ = run("known-bad")
    finally:
        source.write_bytes(candidate)
        receipt["restoredSourceSHA256"] = hashlib.sha256(source.read_bytes()).hexdigest()
        save_receipt()
        require(source.read_bytes() == candidate, "Core source restoration failed")
    require(red_exit != 0 and red["failedChecks"] == failed_names,
            f"Known-bad must fail exactly the two actual text-only runtime checks: {red}")

    green_exit, green, text = run("candidate")
    require(green_exit == 0 and not green["failedChecks"] and green["passedChecks"] == len(expected),
            f"Candidate must pass every registered core check: {green}")
    require(f"Executed {len(expected)} VoiceInkCore checks." in text, "Candidate core summary count missing")
    require(source.read_bytes() == candidate, "Core candidate changed after verification")
    receipt["status"] = "passed"
    print(f"Core candidate: {len(expected)}/{len(expected)} passed; known-bad failed exactly two lip-only checks", flush=True)
except BaseException as error:
    receipt.update({"status": "failed", "error": str(error)})
    raise
finally:
    save_receipt()
