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
power_mode_policy = root / "VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift"
authorization = root / "VoiceInk/Services/CaptureAuthorizationDecision.swift"
recognition = root / "VoiceInk/Transcription/Engine/RecordingRecognition.swift"
candidates = {path: path.read_bytes() for path in (
    source, recorder, prewarm, power_modes, power_mode_policy, authorization, recognition,
)}
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
    "integrationSourceSHA256": {
        "VoiceInk/Transcription/Engine/VoiceInkEngine.swift": hashlib.sha256((
            root / "VoiceInk/Transcription/Engine/VoiceInkEngine.swift"
        ).read_bytes()).hexdigest(),
    },
    "testSourceSHA256": {
        relative: hashlib.sha256((root / relative).read_bytes()).hexdigest()
        for relative in (
            "VoiceInkTests/TranscriptionPipelineTests.swift",
            "VoiceInkTests/RecorderMicrophonePrivacyTests.swift",
            "VoiceInkTests/ModelPrewarmServiceTests.swift",
            "VoiceInkTests/PowerModeSessionManagerTests.swift",
            "VoiceInkTests/CaptureAuthorizationDecisionTests.swift",
            "VoiceInkTests/RecordingRecognitionTests.swift",
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
def semantic_revert(mutants, record):
    originals = {path: candidates[path] for path in mutants}
    require(all(path.read_bytes() == data for path, data in originals.items()),
            f"Candidate changed before {record['label']}")
    record["sources"] = {
        str(path.relative_to(root)): {"mutantSourceSHA256": hashlib.sha256(data).hexdigest()}
        for path, data in mutants.items()
    }
    if len(mutants) == 1:
        path = next(iter(mutants))
        record.update({"source": str(path.relative_to(root)), **record["sources"][str(path.relative_to(root))]})
    receipt["controls"].append(record)
    save_receipt()
    try:
        for path, data in mutants.items():
            path.write_bytes(data)
        yield
    finally:
        for path, data in originals.items():
            path.write_bytes(data)
            record["sources"][str(path.relative_to(root))]["restoredSourceSHA256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        record["sourceRestored"] = all(path.read_bytes() == data for path, data in originals.items())
        if len(mutants) == 1:
            record["restoredSourceSHA256"] = record["sources"][str(path.relative_to(root))]["restoredSourceSHA256"]
        save_receipt()
        require(record["sourceRestored"], f"Failed to restore sources for {record['label']}")

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
mixed_power_mode_selection = "VoiceInkTests/VoiceInkTests/recorderPowerModeMixedSessionRestoresAudioSelectionWithoutLoadingForLips()"
upgraded_power_mode_selection = "VoiceInkTests/VoiceInkTests/recorderPowerModeLipSessionCanUpgradeToVoiceAndRestoreAudioResources()"
hardware_suite = "VoiceInkTests/RecorderMicrophonePrivacyTests"
authorization_suite = "VoiceInkTests/CaptureAuthorizationDecisionTests"
authorization_selection = authorization_suite + "/testCanceledPermissionDecisionDrainsBeforeSystemCallback"
recognition_selection = "VoiceInkTests/RecordingRecognitionTests/testVoiceSuccessCancelsAndDrainsLipRecognition"
candidate_selections = (
    pipeline_selection, hardware_suite, auto_send_selection, prewarm_selection,
    central_lip_selection, central_voice_selection, authorization_suite, recognition_selection,
    mixed_power_mode_selection, upgraded_power_mode_selection,
)
receipt["candidateSelections"] = candidate_selections
receipt["expectedCandidateFunctions"] = 16
receipt["expectedCandidateInvocations"] = 20


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
    with semantic_revert({path: mutant.encode()}, record):
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
    hardware_case = {"known-bad-incomplete-stop": "queued_pre_roll",
                     "known-bad-stale-generation": "off_on_generation"}.get(label)
    if hardware_case:
        receipts = [json.loads(line[line.index("{"):]) for line in (evidence / f"{label}.log").read_text().splitlines()
                    if "microphone_privacy_proof" in line]
        matching = [entry for entry in receipts if entry.get("event") == "microphone_privacy_proof"
                    and entry.get("case") == hardware_case and entry.get("phase") == "hardware_precondition"]
        require(len(matching) == 1, f"{label} requires one matching actual microphone precondition")
        hardware = record["hardwarePrecondition"] = matching[0]
        save_receipt()
        require(hardware.get("required") is True and hardware.get("hasAudioUnit") is True
                and hardware.get("isPreBuffering") is True and type(hardware.get("bufferedPCMBytes")) is int
                and hardware["bufferedPCMBytes"] > 0,
                f"{label} lacks required live microphone/PCM evidence: {hardware}")
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
require(len(re.findall(pattern, pre_roll)) == 4, "Expected four pre-roll generation guards")
# Retain failed-start and caller checks; revert only queued setup and successful-start checks.
old_pre_roll = re.sub(pattern, "", pre_roll, count=2)
require(len(re.findall(pattern, old_pre_roll)) == 2, "Expected two retained pre-roll generation guards")
old_generation = recorder_text[:start] + old_pre_roll + recorder_text[end:]
prewarm_text = candidates[prewarm].decode()
prewarm_guard = "        guard dictationMode().usesMicrophone else { return }\n"
require(prewarm_text.count(prewarm_guard) == 1, "Expected one microphone-only prewarm guard")
audio_prewarm = prewarm_text.replace(prewarm_guard, "", 1)
power_mode_text = candidates[power_modes].decode()
scope = "let applicationScope = VoiceInkPowerModeSessionApplicationScope(dictationMode: stateProvider.currentDictationMode)"
require(power_mode_text.count(scope) == 1, "Expected one central recorder input scope")
full_scope = power_mode_text.replace(scope, "let applicationScope = VoiceInkPowerModeSessionApplicationScope.full", 1)
authorization_text = candidates[authorization].decode()
cancelable_decision = '''        guard !Task.isCancelled else { return false }
        let decisions = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        initiate { granted in
            decisions.continuation.yield(granted)
            decisions.continuation.finish()
        }
        for await decision in decisions.stream { return decision }
        return false
'''
uninterruptible_decision = '''        return await withCheckedContinuation { continuation in
            initiate { continuation.resume(returning: $0) }
        }
'''
require(authorization_text.count(cancelable_decision) == 1, "Expected one cancellation-aware permission decision body")
pending_decision = authorization_text.replace(cancelable_decision, uninterruptible_decision, 1)
recognition_text = candidates[recognition].decode()
cancel_unused_lips = "            lips?.cancel()\n"
drain_unused_lips = "            _ = await lips?.result\n"
require(recognition_text.count(cancel_unused_lips) == 1, "Expected one voice-ready unused-lip cancellation")
require(recognition_text.count(drain_unused_lips) == 1, "Expected one voice-ready lip cleanup drain")
wait_for_unused_lips = recognition_text.replace(cancel_unused_lips, "", 1)

restoration_commit = "6421408897bb92f95e8bc04e794d31b15ec0cc71"
if subprocess.run(["git", "cat-file", "-e", restoration_commit + "^{commit}"],
                  cwd=root, stderr=subprocess.DEVNULL).returncode != 0:
    subprocess.run(["git", "fetch", "--no-tags", "--no-write-fetch-head", "--depth=1", "origin", restoration_commit],
                   cwd=root, check=True)
old_restoration = {
    path: subprocess.check_output(["git", "show", f"{restoration_commit}:{path.relative_to(root)}"], cwd=root)
    for path in (power_mode_policy, power_modes)
}
require(all(data != candidates[path] for path, data in old_restoration.items()),
        "Expected the pre-fix Core policy and actual session manager to differ from the candidate")

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
                    else "Remove queued pre-roll generation checks before setup and after successful start.")
    red_control(source, escaped_timer, "known-bad-auto-send", auto_send_selection, 3,
                "Run the real delay and key post in an unstructured task; ignore sleep cancellation.")
    red_control(prewarm, audio_prewarm, "known-bad-audio-prewarm", prewarm_selection, 1,
                "Remove the lip-only microphone prewarm guard.")
    red_control(power_modes, full_scope, "known-bad-central-power-mode", central_lip_selection, 1,
                "Apply full audio resources instead of the frozen recorder input scope.")
    red_control(authorization, pending_decision, "known-bad-pending-permission", authorization_selection, 1,
                "Wait on the original withCheckedContinuation callback without owner-cancellation cooperation.")
    red_control(recognition, wait_for_unused_lips, "known-bad-unused-lip-wait", recognition_selection, 1,
                "Omit cancellation of unused lip inference after voice succeeds, retaining its cleanup drain.")

    label = "known-bad-power-mode-restoration"
    restoration = {
        "label": label, "selection": mixed_power_mode_selection,
        "positiveSelection": upgraded_power_mode_selection, "knownBadCommit": restoration_commit,
        "expectedFunctions": 2, "expectedInvocations": 2,
        "knownBadChange": "Restore the exact pre-fix Core policy and session manager; retain current app tests.",
    }
    with semantic_revert(old_restoration, restoration):
        red_exit, red = run(label, (mixed_power_mode_selection, upgraded_power_mode_selection))
    restoration.update({"exitCode": red_exit, "summary": red, "counts": counts(red)})
    save_receipt()
    require(red_exit != 0
            and restoration["counts"]["functions"] == {"passed": 1, "failed": 1, "skipped": 0, "total": 2}
            and restoration["counts"]["invocations"] == {"passed": 1, "failed": 1, "skipped": 0, "total": 2}
            and restoration["counts"]["parameterizedInvocations"] == 0,
            f"{label} must fail the mixed session and pass the lip-to-voice upgrade: {restoration['counts']}")
    mixed_identity = mixed_power_mode_selection.split("/")[-1]
    require(red["testFailures"] and all(mixed_identity in failure["testIdentifierString"]
                                       for failure in red["testFailures"]),
            f"{label} failed outside the actual mixed-session regression")
    log = (evidence / f"{label}.log").read_text()
    issues = [line.split("Expectation failed: ", 1)[1] for line in log.splitlines()
              if f"Test {mixed_identity} recorded an issue at PowerModeSessionManagerTests.swift:" in line
              and "Expectation failed: " in line]
    expected_issues = (
        r'\(fixture\.savedSession\?\.applicationScope → .*textOnly.*\) == \.full',
        r'\(fixture\.provider\.currentTranscriptionModel\?\.name → "audio-B"\) == "audio-A"',
        r'\(fixture\.provider\.resourceEvents → \[\]\) == \["select:audio-A"\]',
    )
    restoration["assertionFailures"] = issues
    save_receipt()
    require(len(issues) == 6 and all(sum(re.fullmatch(pattern, issue) is not None for issue in issues) == 2
                                   for pattern in expected_issues),
            f"{label} requires the scope, selection and resource assertions for both frozen/recovered sessions: {issues}")
    require(f"Test {upgraded_power_mode_selection.split('/')[-1]} passed after " in log,
            f"{label} did not execute its lip-to-voice positive control")
    restoration["expectedFailureConfirmed"] = True
    save_receipt()
    print(f"{label}: mixed-session assertions failed; lip-to-voice upgrade passed; both sources restored", flush=True)

    green_exit, green = run("candidate", candidate_selections)
    receipt["candidateSummary"] = green
    receipt["candidateExitCode"] = green_exit
    save_receipt()
    actual = counts(green)
    receipt["candidateCounts"] = actual
    save_receipt()
    require(green_exit == 0 and green["failedTests"] == 0
            and actual["functions"] == {"passed": 16, "failed": 0, "skipped": 0, "total": 16}
            and actual["invocations"] == {"passed": 20, "failed": 0, "skipped": 0, "total": 20}
            and actual["parameterizedInvocations"] == 6,
            f"Candidate must pass 16 functions / 20 invocations, including 6 parameterized runs: {actual}")
    require(all(path.read_bytes() == data for path, data in candidates.items()),
            "Candidate sources changed after controls")
    require(all(hashlib.sha256((root / path).read_bytes()).hexdigest() == digest
                for path, digest in receipt["testSourceSHA256"].items()),
            "Candidate tests changed during controls")
    receipt["status"] = "passed"
    print("Candidate: 16 functions / 20 invocations passed; all nine semantic reverts failed; sources restored", flush=True)
except BaseException as error:
    receipt.update({"status": "failed", "error": str(error)})
    raise
finally:
    save_receipt()
