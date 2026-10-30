#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from contextlib import contextmanager


if os.environ.get("GITHUB_ACTIONS") != "true" or sys.platform != "darwin":
    raise SystemExit("Run on a disposable macOS Actions host.")

root = Path(__file__).resolve().parent.parent
source = root / "VoiceInk/Transcription/Engine/TranscriptionPipeline.swift"
candidate = source.read_bytes()
recorder = root / "VoiceInk/Recorder.swift"
prewarm = root / "VoiceInk/Services/ModelPrewarmService.swift"
power_modes = root / "VoiceInk/PowerMode/PowerModeSessionManager.swift"
candidates = {path: path.read_bytes() for path in (source, recorder, prewarm, power_modes)}
evidence = root / ".local-build/lip-pipeline-regression"
evidence.mkdir(parents=True, exist_ok=False)
test_evidence = root / ".local-build/onboarding-test-evidence"
if test_evidence.exists():
    shutil.move(test_evidence, evidence / "full-candidate")

receipt = {
    "status": "running",
    "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
    "githubRunID": os.environ.get("GITHUB_RUN_ID"),
    "githubRunAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
    "githubJob": os.environ.get("GITHUB_JOB"),
    "candidateSourceSHA256": {
        str(path.relative_to(root)): hashlib.sha256(data).hexdigest()
        for path, data in candidates.items()
    },
    "testSourceSHA256": {
        relative: hashlib.sha256((root / relative).read_bytes()).hexdigest()
        for relative in (
            "VoiceInkTests/TranscriptionPipelineTests.swift",
            "VoiceInkTests/RecorderMicrophonePrivacyTests.swift",
            "VoiceInkTests/ModelPrewarmServiceTests.swift",
            "VoiceInkTests/PowerModeSessionManagerTests.swift",
        )
    },
    "controls": [],
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def save_receipt():
    (evidence / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


@contextmanager
def semantic_revert(path, mutant, record):
    original = candidates[path]
    require(path.read_bytes() == original, f"Candidate changed before {record['label']}")
    record.update({
        "source": str(path.relative_to(root)),
        "mutantSourceSHA256": hashlib.sha256(mutant.encode()).hexdigest(),
    })
    receipt["controls"].append(record)
    save_receipt()
    try:
        path.write_text(mutant)
        yield
    finally:
        path.write_bytes(original)
        record["restoredSourceSHA256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        record["sourceRestored"] = path.read_bytes() == original
        save_receipt()
        require(record["sourceRestored"], f"Failed to restore {path}")

bad = candidate.decode()
for span in ("pastePreparationSpan", "pasteSpan"):
    guard = f'''            if shouldCancel() {{
                latencyTrace.end({span}, details: "result=cancelled")
                await finishCanceledTranscription()
                return
            }}
'''
    require(bad.count(guard) == 1, "Expected one cancellation guard at each real preparation boundary.")
    bad = bad.replace(guard, "", 1)
forwarding = '''            let pasteResult = await withTaskCancellationHandler {
                await pasteTask.value
            } onCancel: {
                pasteTask.cancel()
            }
'''
require(bad.count(forwarding) == 1, "Expected one real paste-task cancellation handler")
bad = bad.replace(forwarding, "            let pasteResult = await pasteTask.value\n", 1)

owned_auto_send = '''                #if DEBUG
                autoSendDelayStartedForTesting?()
                #endif
                do {
                    try await Task.sleep(nanoseconds: delayAfterPaste)
                    if !Task.isCancelled, !shouldCancel() {
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                } catch {
                    latencyTrace.event("pipeline.auto_send_cancelled", token: traceToken)
                }
'''
escaped_auto_send = '''                Task { @MainActor in
                    #if DEBUG
                    self.autoSendDelayStartedForTesting?()
                    #endif
                    try? await Task.sleep(nanoseconds: delayAfterPaste)
                    CursorPaster.performAutoSend(autoSendKey)
                }
'''
require(candidate.decode().count(owned_auto_send) == 1, "Expected one owned auto-send delay")
escaped_timer = candidate.decode().replace(owned_auto_send, escaped_auto_send, 1)


pipeline_selection = "VoiceInkTests/VoiceInkTests/canceledPipelineCannotPasteAfterPreparation(boundary:)"
auto_send_selection = "VoiceInkTests/VoiceInkTests/pipelineOwnsDelayedAutoSendUntilCompletion(scenario:)"
prewarm_selection = "VoiceInkTests/ModelPrewarmServiceTests/lipOnlyPrewarmNeverLoadsAnInstalledAudioModel()"
central_lip_selection = "VoiceInkTests/VoiceInkTests/recorderPowerModeSelectionUsesFrozenLipOnlyMode()"
central_voice_selection = "VoiceInkTests/VoiceInkTests/recorderPowerModeSelectionRetainsAudioForVoiceAndCombined()"
hardware_suite = "VoiceInkTests/RecorderMicrophonePrivacyTests"
candidate_selections = (
    pipeline_selection, hardware_suite, auto_send_selection, prewarm_selection,
    central_lip_selection, central_voice_selection,
)
receipt["candidateSelections"] = candidate_selections
receipt["expectedCandidateFunctions"] = 9
receipt["expectedCandidateInvocations"] = 13


def read_summary(destination):
    summary = subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(destination / "Debug.xcresult"), "--format", "json",
    ], text=True)
    (destination / "summary.json").write_text(summary)
    return json.loads(summary)


def run(label, selections):
    environment = dict(os.environ, RJT_REQUIRE_MICROPHONE_PRIVACY_PROOF="1",
                       TEST_RUNNER_RJT_REQUIRE_MICROPHONE_PRIVACY_PROOF="1")
    log = evidence / f"{label}.log"
    print(f"Running {label}: {', '.join(selections)}", flush=True)
    with log.open("w") as output:
        result = subprocess.run(
            ["bash", "scripts/run-macos-ci-unit-tests.sh", *selections],
            cwd=root, env=environment, stdout=output, stderr=subprocess.STDOUT, text=True,
        )
    destination = evidence / label
    require(test_evidence.exists(), f"{label} produced no test evidence; see {log}")
    shutil.move(test_evidence, destination)
    return result.returncode, read_summary(destination)


def counts(summary):
    configurations = summary["devicesAndConfigurations"]
    require(len(configurations) == 1, "Expected exactly one macOS device and test configuration")
    configuration = configurations[0]
    identity = {key: configuration[key] for key in ("device", "testPlanConfiguration")}
    require(identity["device"]["platform"] == "macOS", "Expected actual macOS test execution")
    previous = receipt.setdefault("deviceAndConfiguration", identity)
    require(identity == previous, "Regression controls did not run on the same device and configuration")
    require(summary["expectedFailures"] == 0 and configuration["expectedFailures"] == 0,
            "Regression controls cannot rely on expected failures")
    functions = {key: summary[key + "Tests"] for key in ("passed", "failed", "skipped")}
    functions["total"] = summary["totalTestCount"]
    require(sum(functions[key] for key in ("passed", "failed", "skipped")) == functions["total"],
            f"Inconsistent top-level function counts: {summary}")
    invocations = {key: configuration[key + "Tests"] for key in ("passed", "failed", "skipped")}
    invocations["total"] = sum(invocations.values())
    parameter_runs = 0
    for statistic in summary.get("statistics", []):
        if "dynamic parameters" in statistic.get("title", ""):
            match = re.fullmatch(r"(\d+) test runs?", statistic["subtitle"])
            require(match is not None, f"Unknown parameterized-run statistic: {statistic}")
            parameter_runs += int(match.group(1))
    return {"functions": functions, "invocations": invocations, "parameterizedInvocations": parameter_runs}


def red_control(path, mutant, label, selection, count, change):
    record = {
        "label": label, "selection": selection, "expectedFunctions": 1,
        "expectedInvocations": count, "knownBadChange": change,
    }
    with semantic_revert(path, mutant, record):
        exit_code, summary = run(label, (selection,))
    record.update({"exitCode": exit_code, "summary": summary})
    save_receipt()
    actual = counts(summary)
    record["counts"] = actual
    save_receipt()
    require(exit_code != 0, f"{label} unexpectedly passed")
    require(actual["functions"] == {"passed": 0, "failed": 1, "skipped": 0, "total": 1},
            f"{label} did not fail exactly one selected test function: {actual}")
    require(actual["invocations"] == {"passed": 0, "failed": count, "skipped": 0, "total": count}
            and actual["parameterizedInvocations"] == (count if count > 1 else 0),
            f"{label} did not fail exactly {count} actual invocations: {actual}")
    identity = selection.split("/")[-1].split("(")[0]
    require(summary["testFailures"] and all(
        identity in failure["testIdentifierString"] for failure in summary["testFailures"]
    ), f"{label} failed outside its selected regression: {summary}")
    record["expectedFailureConfirmed"] = True
    save_receipt()
    print(f"{label}: one function, {count}/{count} expected failed invocations; source restored", flush=True)


recorder_candidate = candidates[recorder]
recorder_text = recorder_candidate.decode()
start = recorder_text.index("    func setMicrophoneCaptureEnabled(")
end = recorder_text.index("    func microphoneCaptureStatus(", start)
suspension = recorder_text[start:end]
require(suspension.count("currentRecorder?.stopRecording()") == 1, "Expected one synchronous microphone stop")
incomplete_stop = recorder_text[:start] + suspension.replace(
    "currentRecorder?.stopRecording()", "currentRecorder?.finishRecording()"
) + recorder_text[end:]
start = recorder_text.index("    func startPreRollBuffering(")
end = recorder_text.index("    func ", start + 10)
pre_roll = recorder_text[start:end]
pattern = r",\n\s+captureGeneration\.load\(ordering: \.acquiring\) == generation"
require(len(re.findall(pattern, pre_roll)) == 2, "Expected two pre-roll generation guards")
old_generation = recorder_text[:start] + re.sub(pattern, "", pre_roll, count=2) + recorder_text[end:]
prewarm_text = candidates[prewarm].decode()
prewarm_guard = "        guard dictationMode().usesMicrophone else { return }\n"
require(prewarm_text.count(prewarm_guard) == 1, "Expected one microphone-only prewarm guard")
audio_prewarm = prewarm_text.replace(prewarm_guard, "", 1)
power_mode_text = candidates[power_modes].decode()
scope = "let applicationScope = VoiceInkPowerModeSessionApplicationScope(dictationMode: stateProvider.currentDictationMode)"
require(power_mode_text.count(scope) == 1, "Expected one central recorder input scope")
full_scope = power_mode_text.replace(scope, "let applicationScope = VoiceInkPowerModeSessionApplicationScope.full", 1)

try:
    if (evidence / "full-candidate").exists():
        full = read_summary(evidence / "full-candidate")
        receipt["fullCandidateSummary"] = full
        save_receipt()
        require(full["failedTests"] == 0 and full["passedTests"] > 0,
                f"Initial full candidate gate was not green: {full}")

    red_control(source, bad, "known-bad-paste", pipeline_selection, 3,
                "Remove both post-preparation guards and cancellation forwarding into the real paste task.")
    for label, mutant, test in (
        ("known-bad-incomplete-stop", incomplete_stop, "testQueuedPreRollCannotOpenMicrophoneAfterSuspension"),
        ("known-bad-stale-generation", old_generation, "testRapidReenableRejectsOldQueuedPreRollGeneration"),
    ):
        red_control(recorder, mutant, label, hardware_suite + "/" + test, 1,
                    "Use deferred microphone finish instead of synchronous stop." if label.endswith("incomplete-stop")
                    else "Remove both pre-roll capture-generation rechecks.")
    red_control(source, escaped_timer, "known-bad-auto-send", auto_send_selection, 3,
                "Run the real delay and key post in an unstructured task; ignore sleep cancellation.")
    red_control(prewarm, audio_prewarm, "known-bad-audio-prewarm", prewarm_selection, 1,
                "Remove the lip-only microphone prewarm guard.")
    red_control(power_modes, full_scope, "known-bad-central-power-mode", central_lip_selection, 1,
                "Apply full audio resources instead of the frozen recorder input scope.")

    green_exit, green = run("candidate", candidate_selections)
    receipt["candidateSummary"] = green
    receipt["candidateExitCode"] = green_exit
    save_receipt()
    actual = counts(green)
    receipt["candidateCounts"] = actual
    save_receipt()
    require(green_exit == 0 and green["failedTests"] == 0
            and actual["functions"] == {"passed": 9, "failed": 0, "skipped": 0, "total": 9}
            and actual["invocations"] == {"passed": 13, "failed": 0, "skipped": 0, "total": 13}
            and actual["parameterizedInvocations"] == 6,
            f"Candidate must pass 9 functions / 13 invocations, including 6 parameterized runs: {actual}")
    require(all(path.read_bytes() == data for path, data in candidates.items()),
            "Candidate sources changed after controls")
    receipt["status"] = "passed"
    print("Candidate: 9 functions / 13 invocations passed; all six semantic reverts failed; sources restored", flush=True)
except BaseException as error:
    receipt.update({"status": "failed", "error": str(error)})
    raise
finally:
    save_receipt()
