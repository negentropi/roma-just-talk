#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import re
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
forwarding = '''            let pasteResult = await withTaskCancellationHandler {
                await pasteTask.value
            } onCancel: {
                pasteTask.cancel()
            }
'''
assert bad.count(forwarding) == 1
bad = bad.replace(forwarding, "            let pasteResult = await pasteTask.value\n", 1)


pipeline_selection = "VoiceInkTests/VoiceInkTests/canceledPipelineCannotPasteAfterPreparation(boundary:)"
hardware_suite = "VoiceInkTests/RecorderMicrophonePrivacyTests"


def run(label, selections=(pipeline_selection,)):
    environment = dict(os.environ, RJT_REQUIRE_MICROPHONE_PRIVACY_PROOF="1",
                       TEST_RUNNER_RJT_REQUIRE_MICROPHONE_PRIVACY_PROOF="1")
    result = subprocess.run(
        ["bash", "scripts/run-macos-ci-unit-tests.sh", *selections],
        cwd=root, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
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
assert red["failedTests"] == 3 and red["totalTestCount"] == 3, red
assert all("canceledPipelineCannotPasteAfterPreparation" in failure["testIdentifierString"]
           for failure in red["testFailures"]), red

recorder = root / "VoiceInk/Recorder.swift"
recorder_candidate = recorder.read_bytes()
recorder_text = recorder_candidate.decode()
start = recorder_text.index("    func setMicrophoneCaptureEnabled(")
end = recorder_text.index("    func microphoneCaptureStatus(", start)
suspension = recorder_text[start:end]
assert suspension.count("currentRecorder?.stopRecording()") == 1
incomplete_stop = recorder_text[:start] + suspension.replace(
    "currentRecorder?.stopRecording()", "currentRecorder?.finishRecording()"
) + recorder_text[end:]
start = recorder_text.index("    func startPreRollBuffering(")
end = recorder_text.index("    func ", start + 10)
pre_roll = recorder_text[start:end]
pattern = r",\n\s+captureGeneration\.load\(ordering: \.acquiring\) == generation"
assert len(re.findall(pattern, pre_roll)) >= 2
old_generation = recorder_text[:start] + re.sub(pattern, "", pre_roll, count=2) + recorder_text[end:]
hardware_red = []
for label, bad_source, test in (
    ("known-bad-incomplete-stop", incomplete_stop, "testQueuedPreRollCannotOpenMicrophoneAfterSuspension"),
    ("known-bad-stale-generation", old_generation, "testRapidReenableRejectsOldQueuedPreRollGeneration"),
):
    try:
        recorder.write_text(bad_source)
        exit_code, summary = run(label, (hardware_suite + "/" + test,))
    finally:
        recorder.write_bytes(recorder_candidate)
        assert recorder.read_bytes() == recorder_candidate
    assert exit_code != 0 and summary["failedTests"] == 1 and summary["totalTestCount"] == 1, summary
    hardware_red.append({"control": label, "failedTests": summary["failedTests"]})

green_exit, green = run("candidate", (pipeline_selection, hardware_suite))
assert green_exit == 0 and green["failedTests"] == 0, green
assert green["passedTests"] == 7 and green["totalTestCount"] == 7, green
(evidence / "receipt.json").write_text(json.dumps({
    "candidateSourceSHA256": candidate_hash,
    "knownBadChange": "Remove the two post-preparation cancellation guards and cancellation forwarding into the real paste task.",
    "boundary": "Actual pipeline, held preparation completion, cancellation, clipboard and persisted history.",
    "knownBadFailedCases": red["failedTests"],
    "microphoneControls": hardware_red,
    "recorderSourceSHA256": hashlib.sha256(recorder_candidate).hexdigest(),
    "candidatePassedCases": green["passedTests"],
}, indent=2) + "\n")
