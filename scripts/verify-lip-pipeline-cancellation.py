#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


if os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("Run on a disposable macOS Actions host.")

root = Path(__file__).resolve().parent.parent
source = root / "VoiceInk/Transcription/Engine/TranscriptionPipeline.swift"
candidate = source.read_bytes()
candidate_hash = hashlib.sha256(candidate).hexdigest()
evidence = root / ".local-build/lip-pipeline-regression"
evidence.mkdir(parents=True, exist_ok=False)
test_evidence = root / ".local-build/onboarding-test-evidence"
if test_evidence.exists():
    shutil.move(test_evidence, evidence / "full-candidate")

bad = candidate.decode()
for span in ("pastePreparationSpan", "pasteSpan"):
    guard = f'''            if shouldCancel() {{
                latencyTrace.end({span}, details: "result=cancelled")
                await finishCanceledTranscription()
                return
            }}
'''
    if bad.count(guard) != 1:
        raise SystemExit("Expected one cancellation guard at each real preparation boundary.")
    bad = bad.replace(guard, "", 1)


def run(label):
    result = subprocess.run(
        ["bash", "scripts/run-macos-ci-unit-tests.sh",
         "VoiceInkTests/VoiceInkTests/canceledPipelineCannotPasteAfterPreparation"],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    log = evidence / f"{label}.log"
    log.write_text(result.stdout)
    print(result.stdout, flush=True)
    destination = evidence / label
    if not test_evidence.exists():
        raise RuntimeError(f"{label} produced no test evidence")
    shutil.move(test_evidence, destination)
    summary = subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(destination / "Debug.xcresult"), "--format", "json",
    ], text=True)
    (destination / "summary.json").write_text(summary)
    return result.returncode, json.loads(summary)


try:
    source.write_text(bad)
    red_exit, red = run("known-bad")
finally:
    source.write_bytes(candidate)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == candidate_hash

assert red_exit != 0, "Known-bad guards must permit the canceled paste and fail."
assert red["failedTests"] == 2 and red["totalTestCount"] == 2, red
assert all("canceledPipelineCannotPasteAfterPreparation" in failure["testIdentifierString"]
           for failure in red["testFailures"]), red
green_exit, green = run("candidate")
assert green_exit == 0 and green["failedTests"] == 0, green
assert green["passedTests"] == 2 and green["totalTestCount"] == 2, green
(evidence / "receipt.json").write_text(json.dumps({
    "candidateSourceSHA256": candidate_hash,
    "knownBadChange": "Remove only the two post-preparation cancellation guards.",
    "boundary": "Actual pipeline, held preparation completion, cancellation, clipboard and persisted history.",
    "knownBadFailedCases": red["failedTests"],
    "candidatePassedCases": green["passedTests"],
}, indent=2) + "\n")
