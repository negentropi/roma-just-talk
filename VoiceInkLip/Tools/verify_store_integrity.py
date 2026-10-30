#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess


TEST_NAME = "testRestartVerifiesSameSizeCorruptionBeforeInferenceAndExplicitInstallRepairs"
TEST_ID = "VoiceInkLipTests.LipModelStoreTests/" + TEST_NAME
TEST_CASE = "-[VoiceInkLipTests.LipModelStoreTests " + TEST_NAME + "]"
FILTER = "^" + re.escape(TEST_ID) + "$"
ASSERTIONS = (
    "Failed integrity verification must expose installation retry",
    "Invalidation must survive another store instance",
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def run_test(root, proof, command, label, expected_status, expected_failures):
    log_path = proof / (label + ".log")
    print("Running actual XCTest integrity " + label, flush=True)
    with log_path.open("wb") as log:
        result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
    output = log_path.read_text(errors="replace")
    started = re.findall(r"^Test Case '([^']+)' started\.$", output, re.MULTILINE)
    completed = re.findall(r"^Test Case '([^']+)' (passed|failed) \(", output, re.MULTILINE)
    summaries = [tuple(map(int, values)) for values in re.findall(
        r"\bExecuted (\d+) tests?, with (\d+) failures? \((\d+) unexpected\)", output
    )]
    failures = [message for message in ASSERTIONS if any(
        "XCTAssertFalse failed" in line and message in line for line in output.splitlines()
    )]
    observed = {
        "exitCode": result.returncode,
        "startedCases": started,
        "completedCases": completed,
        "executionSummaries": summaries,
        "intendedAssertionFailures": failures,
        "log": str(log_path.relative_to(proof.parent)),
        "logSHA256": sha256(log_path.read_bytes()),
    }
    errors = []
    if started != [TEST_CASE] or completed != [(TEST_CASE, expected_status)]:
        errors.append("The exact XCTest must start and complete once")
    if not summaries or any(values != (1, expected_failures, 0) for values in summaries):
        errors.append("Runtime summaries must report exactly one test with the expected failures")
    if expected_status == "failed":
        if result.returncode == 0 or failures != list(ASSERTIONS):
            errors.append("Known-bad source must fail both intended retry assertions")
    elif result.returncode != 0 or failures:
        errors.append("Restored candidate must pass without integrity assertion failures")
    observed["accepted"] = not errors
    observed["errors"] = errors
    print(label + " exit=" + str(result.returncode) + " selected=" + str(len(started))
          + " accepted=" + str(not errors), flush=True)
    return observed


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or platform.system() != "Darwin":
        raise SystemExit("Run only on the disposable native macOS proof host.")
    root = Path(__file__).resolve().parents[2]
    source = root / "VoiceInkLip/Sources/VoiceInkLip/LipModelStore.swift"
    fixture = root / "VoiceInkLip/Tests/VoiceInkLipTests/LipModelStoreTests.swift"
    proof = Path(os.environ["LIP_PROOF_DIR"]) / "store-integrity"
    proof.mkdir()
    candidate = source.read_bytes()
    fixture_bytes = fixture.read_bytes()
    invalidation = b'                try FileManager.default.removeItem(at: installed.appendingPathComponent("complete"))\n'
    if candidate.count(invalidation) != 1:
        raise SystemExit("Expected exactly one owned completion-receipt invalidation to disable.")
    known_bad = candidate.replace(invalidation, b"", 1)
    (proof / "candidate-source.swift").write_bytes(candidate)
    (proof / "known-bad-source.swift").write_bytes(known_bad)
    (proof / "fixture.swift").write_bytes(fixture_bytes)
    command = ["swift", "test", "--package-path", "VoiceInkLip", "--scratch-path", os.environ["LIP_BUILD_DIR"],
               "--jobs", "4", "--filter", FILTER]
    receipt = {
        "schemaVersion": 1,
        "boundary": "Actual SwiftPM XCTest on the same disposable macOS host and scratch build",
        "gitHead": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "testIdentifier": TEST_ID,
        "filter": FILTER,
        "command": command,
        "knownBadChange": "Omit only completion-receipt invalidation from the exact candidate source",
        "candidateSourceSHA256": sha256(candidate),
        "knownBadSourceSHA256": sha256(known_bad),
        "fixtureSHA256": sha256(fixture_bytes),
        "passed": False,
    }
    try:
        try:
            source.write_bytes(known_bad)
            receipt["knownBad"] = run_test(root, proof, command, "known-bad", "failed", 2)
        finally:
            source.write_bytes(candidate)
            receipt["exactCandidateRestored"] = source.read_bytes() == candidate
            if not receipt["exactCandidateRestored"]:
                raise RuntimeError("Failed to restore the exact candidate source bytes")
        receipt["candidate"] = run_test(root, proof, command, "candidate", "passed", 0)
        receipt["fixtureUnchanged"] = fixture.read_bytes() == fixture_bytes
        if source.read_bytes() != candidate or not receipt["fixtureUnchanged"]:
            raise RuntimeError("Source or fixture changed during the same-source integrity proof")
        if not receipt["knownBad"]["accepted"] or not receipt["candidate"]["accepted"]:
            raise RuntimeError("Actual XCTest integrity red/green proof failed; inspect store-integrity logs")
        receipt["passed"] = True
    except Exception as error:
        receipt["error"] = str(error)
        raise
    finally:
        (proof / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("PASS actual XCTest integrity recovery; known-bad fails, exact candidate repairs", flush=True)


if __name__ == "__main__":
    main()
