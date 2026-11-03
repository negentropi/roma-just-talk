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
engine = root / "VoiceInk/Transcription/Engine/VoiceInkEngine.swift"
candidates = {path: path.read_bytes() for path in (
    source, recorder, prewarm, power_modes, power_mode_policy, authorization, recognition, engine,
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
    "verificationScriptSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
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
            "VoiceInkTests/CaptureAuthorizationDecisionTests.swift",
            "VoiceInkTests/RecordingRecognitionTests.swift",
            "VoiceInkTests/DiscardedRecordingTests.swift",
            "VoiceInkTests/QwenRecordingSelectionTests.swift",
            "VoiceInkTests/VoiceInkTests.swift",
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
    guard = f'''            if let cancellation = cancellation() {{
                latencyTrace.end({span}, details: "result=cancelled")
                await finishCanceledTranscription(cancellation)
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
                    if !Task.isCancelled, cancellation() == nil {
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

accidental_discard = "            if cancellation == .accidentalShortcut {\n"
shared_cancellation_discard = "            if !cancellation.retainsCapturedHistory(audioURL: transcription.audioFileURL.flatMap { URL(string: $0) }) {\n"
require(candidate.decode().count(shared_cancellation_discard) == 1, "Expected one shared cancellation History discard guard")
retained_accidental = candidate.decode().replace(
    shared_cancellation_discard,
    shared_cancellation_discard.replace("if !", "if cancellation != .accidentalShortcut && !", 1), 1,
)
retained_pipeline_session_end = candidate.decode().replace(shared_cancellation_discard, accidental_discard, 1)
empty_discard = '''        if VoiceInkEmptyTranscriptionPolicy.isEmptyCompletion(
            status: transcription.transcriptionState,
            rawText: transcription.text,
            enhancedText: transcription.enhancedText
        ) {
            discard(transcription)
            latencyTrace.finish(event: "pipeline.empty_discarded", token: traceToken)
            return
        }

'''
require(candidate.decode().count(empty_discard) == 1, "Expected one empty-completion discard before persistence")
retained_empty = candidate.decode().replace(empty_discard, "", 1)
engine_text = candidates[engine].decode()
start = engine_text.index("    private func requestCancellation(")
end = engine_text.index("    private func reserveCanceledRecording(", start)
request_cancellation = engine_text[start:end]
reservation = "        reserveCanceledRecording(recording)\n"
require(request_cancellation.count(reservation) == 1, "Expected one synchronous canceled-history reservation")
late_reservation = engine_text[:start] + request_cancellation.replace(reservation, "", 1) + engine_text[end:]
session_end_history = "        case .sessionEnded: return audioURL != nil\n"
require(engine_text.count(session_end_history) == 1, "Expected one audio-backed implicit session-end History policy")
retained_lip_session_end = engine_text.replace(session_end_history, "        case .sessionEnded: return true\n", 1)


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
non_speech_selection = "VoiceInkTests/RecordingRecognitionTests/testNonSpeechVoiceUsesLipResultWithoutCancelingIt"
failure_ui_selection = "VoiceInkTests/VoiceInkTests/cameraFinalizationFailureDismissesRecorderAndAllowsNextShortcut()"
newer_ui_selection = "VoiceInkTests/VoiceInkTests/cameraFinalizationFailurePreservesNewerRecorderSession()"
audio_restoration_selection = "VoiceInkTests/VoiceInkTests/fastTranscriptionAndResetShareOneDelayedAudioRestoration()"
lip_history_selection = "VoiceInkTests/VoiceInkTests/lipOnlyPipelineCancellationUsesTypedHistoryPolicy()"
lip_empty_selection = "VoiceInkTests/VoiceInkTests/lipOnlyPipelineDiscardsOnlyEmptyCompletion()"
lip_engine_selection = "VoiceInkTests/VoiceInkTests/lipOnlyCancellationPreservesOnlyUserRequestedHistory()"
startup_history_selection = "VoiceInkTests/VoiceInkTests/userCanceledStartupOwnsAudioBeforeAwaitingDrain()"
lip_session_end_selection = "VoiceInkTests/VoiceInkTests/lipOnlySessionEndDoesNotCreateHistory(action:)"
lip_pipeline_session_end_selection = "VoiceInkTests/VoiceInkTests/lipOnlySessionEndDuringRecognitionDoesNotCreateHistory(action:)"
voice_session_end_selection = "VoiceInkTests/VoiceInkTests/sessionEndedPipelineRetainsCapturedVoiceHistory()"
delivered_history_selection = "VoiceInkTests/VoiceInkTests/pipelinePreservesDeliveredHistoryAfterLateCancellation(sessionEnded:)"
deleted_startup_selection = "VoiceInkTests/VoiceInkTests/deletedStartupCancellationIsNotRecreatedAfterDrain()"
candidate_selections = (
    pipeline_selection, hardware_suite, auto_send_selection, prewarm_selection,
    central_lip_selection, central_voice_selection, authorization_suite, recognition_selection,
    mixed_power_mode_selection, upgraded_power_mode_selection,
    lip_history_selection, lip_empty_selection, lip_engine_selection, startup_history_selection,
    lip_session_end_selection, lip_pipeline_session_end_selection,
    voice_session_end_selection, delivered_history_selection, deleted_startup_selection,
    non_speech_selection, failure_ui_selection, newer_ui_selection, audio_restoration_selection,
)
receipt["candidateSelections"] = candidate_selections
receipt["expectedCandidateFunctions"] = 29
receipt["expectedCandidateInvocations"] = 38
receipt["expectedCandidateParameterizedInvocations"] = 14
receipt["expectedSemanticControls"] = 17


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


history_assertions = {
    "known-bad-lip-cancellation-history": ("TranscriptionPipelineTests.swift", (
        r'\(rows → .+\)\.isEmpty → false',
        r'\(events → \["canceled", "duration"\]\) == \["canceled"\]',
    ), ()),
    "known-bad-empty-lip-history": ("TranscriptionPipelineTests.swift", (
        r'\(rows → .+\)\.isEmpty → false',
        r'try fixture\.readMetrics\(\)\.isEmpty',
        r'\(events → \["dismissed", "duration"\]\) == \["dismissed"\]',
    ), ()),
    "known-bad-startup-history-reservation": ("DiscardedRecordingTests.swift", (
        r'\(pending\.map\(\\\.audioFileURL\) → \[\]\) == \(\[startupFile\.absoluteString\] → .+\)',
        r'\(pending\.map\(\\\.transcriptionState\) → \[\]\) == .*\.canceled.*',
    ), (
        # Without the pending row, failed startup can delete the unreferenced WAV before drain.
        r'\(rows\.map\(\\\.transcriptionState\) → \[\]\) == .*\.canceled.*',
        r'\(rows → \[\]\)\.first → nil → nil',
    )),
}


stop_assertions = {
    "known-bad-camera-finalization-ui": (
        '#expect(!manager.isRecorderSessionActive, "A failed camera finalization must end its logical recorder session")',
        '#expect(!manager.isMiniRecorderVisible)',
        '#expect(manager.recorderSessionID == nil)',
        '#expect(manager.begunSessionIDs.count == 2, "The next shortcut must start a new session instead of dismissing the failed one")',
        '#expect(manager.begunSessionIDs.last != failedSessionID)',
    ),
    "known-bad-duplicate-audio-restoration": (
        '#expect(restorationTasks.count == 1, "Fast transcription and drain must schedule audio restoration once")',
        '#expect(restorationTasks.count == 1, "Reset must reuse the pending restoration instead of scheduling another media toggle")',
        '#expect(restorationCompletions == 1)',
        '#expect(restorationTasks.count == 1, "A completed restoration stays consumed until the next recording starts")',
    ),
}


def verify_stop_assertions(label, record, selection):
    test_source = root / "VoiceInkTests/DiscardedRecordingTests.swift"
    lines = test_source.read_text().splitlines()
    expected = {}
    for assertion in stop_assertions[label]:
        matches = [index + 1 for index, line in enumerate(lines) if line.strip() == assertion]
        require(len(matches) == 1, f"{label} requires one exact source assertion: {assertion}")
        expected[matches[0]] = assertion
    test_name = selection.split("/")[-1]
    issues = [line for line in (evidence / f"{label}.log").read_text().splitlines()
              if f"Test {test_name} recorded an issue" in line]
    actual = []
    for issue in issues:
        match = re.search(r" at DiscardedRecordingTests\.swift:(\d+)(?::\d+)?:", issue)
        require(match is not None and "Expectation failed: " in issue,
                f"{label} has an unrelated or non-assertion failure: {issue}")
        actual.append(int(match.group(1)))
    record.update({"assertionFailures": issues, "expectedAssertionSourceLines": expected})
    save_receipt()
    require(sorted(actual) == sorted(expected),
            f"{label} must fail exactly its pinned source assertions, not preconditions or cleanup: {issues}")


def red_control(path, mutant, label, selection, count, change):
    record = {
        "label": label, "selection": selection, "expectedFunctions": 1,
        "expectedInvocations": count, "knownBadChange": change,
    }
    if label in ("known-bad-non-speech-voice", "known-bad-duplicate-audio-restoration"):
        record["knownBadCommit"] = cb_commit
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
    if label in history_assertions:
        filename, required_assertions, followon_assertions = history_assertions[label]
        test_name = selection.split("/")[-1]
        issue_lines = [line for line in (evidence / f"{label}.log").read_text().splitlines()
                       if f"Test {test_name} recorded an issue" in line]
        issues = [line.split("Expectation failed: ", 1)[-1] for line in issue_lines]
        record["assertionFailures"] = issues
        save_receipt()
        require(all(f" at {filename}:" in line for line in issue_lines)
                and all(sum(re.fullmatch(pattern, issue) is not None for issue in issues) == 1
                    for pattern in required_assertions)
                and all(sum(re.fullmatch(pattern, issue) is not None for issue in issues) <= 1
                        for pattern in followon_assertions)
                and all(any(re.fullmatch(pattern, issue) is not None
                            for pattern in (*required_assertions, *followon_assertions)) for issue in issues),
                f"{label} lacks its exact History assertions or has unrelated failures: {issues}")
    if label == "known-bad-lip-session-end-history":
        log = (evidence / f"{label}.log").read_text()
        test_name = selection.split("/")[-1]
        issues = [line for line in log.splitlines() if f"Test {test_name} recorded an issue" in line]
        record["assertionFailures"] = issues
        save_receipt()
        require(len(issues) == 3 and all(sum(
            f"with 1 argument action → .{action} at DiscardedRecordingTests.swift:" in issue
            and re.fullmatch(r'try fixture\.transcriptionCount\(\) == 0',
                             issue.split("Expectation failed: ", 1)[-1]) is not None
            for issue in issues
        ) == 1 for action in ("masterOff", "reset", "shutdown")),
                f"{label} requires the retained-row assertion in each of master-off, reset and shutdown: {issues}")
    if label == "known-bad-pipeline-session-end-history":
        log = (evidence / f"{label}.log").read_text()
        test_name = selection.split("/")[-1]
        issues = [line for line in log.splitlines() if f"Test {test_name} recorded an issue" in line]
        record["assertionFailures"] = issues
        save_receipt()
        require(len(issues) == 3 and all(sum(
            f"with 1 argument action → .{action} at DiscardedRecordingTests.swift:" in issue
            and re.fullmatch(r'try fixture\.transcriptionCount\(\) == 0',
                             issue.split("Expectation failed: ", 1)[-1]) is not None
            for issue in issues
        ) == 1 for action in ("masterOff", "reset", "shutdown")),
                f"{label} requires the retained-row assertion after blocked recognition in each session-end action: {issues}")
    if label == "known-bad-non-speech-voice":
        test_name = selection.split("/")[-1]
        issues = [line for line in (evidence / f"{label}.log").read_text().splitlines()
                  if test_name in line and ": error:" in line]
        record["assertionFailures"] = issues
        save_receipt()
        required = []
        allowed = []
        for marker in ("[BLANK_AUDIO]", "[music]", "<noise>discard</noise>"):
            selected = [line for line in issues if "RecordingRecognitionTests.swift:" in line
                        and "XCTAssertEqual failed:" in line and "voice(" in line and "lips(" in line
                        and line.endswith(" - Non-speech voice output: " + marker)]
            canceled = [line for line in issues if "RecordingRecognitionTests.swift:" in line
                        and "XCTAssertFalse failed" in line
                        and line.endswith(" - Non-speech voice must preserve lip inference: " + marker)]
            require(len(selected) == 1 and len(canceled) <= 1,
                    f"{label} requires wrong source selection for {marker}; cancellation is a permitted follow-on: {issues}")
            required.extend(selected)
            allowed.extend((*selected, *canceled))
        require(len(required) == 3 and sorted(issues) == sorted(allowed),
                f"{label} has unrelated assertions or lacks a marker selection failure: {issues}")
    if label == "known-bad-duplicate-audio-restoration":
        verify_stop_assertions(label, record, selection)
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

cb_commit = "cb057fc4055d4947a105f5a7f16d614278e55537"
if subprocess.run(["git", "cat-file", "-e", cb_commit + "^{commit}"],
                  cwd=root, stderr=subprocess.DEVNULL).returncode != 0:
    subprocess.run(["git", "fetch", "--no-tags", "--no-write-fetch-head", "--depth=1", "origin", cb_commit],
                   cwd=root, check=True)
cb_sources = {
    path: subprocess.check_output(["git", "show", f"{cb_commit}:{path.relative_to(root)}"], cwd=root)
    for path in (recognition, engine, recorder)
}
receipt["cbBaselineSourceSHA256"] = {
    str(path.relative_to(root)): hashlib.sha256(data).hexdigest() for path, data in cb_sources.items()
}
filtered_voice_guard = "           !VoiceInkTranscriptionOutputFilter.filter(text).isEmpty {\n"
raw_voice_guard = "           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n"
require(recognition_text.count(filtered_voice_guard) == 1, "Expected one shared-filter voice-success guard")
unfiltered_voice = cb_sources[recognition].decode()
expected_cb_recognition = recognition_text.replace("import VoiceInkCore\n", "", 1).replace(
    filtered_voice_guard, raw_voice_guard, 1,
).replace("            // Classify after non-speech filtering; preserve raw text for the shared cleanup pipeline.\n", "", 1)
require(expected_cb_recognition == unfiltered_voice, "CB recognition revert would change unrelated source")
failure_ui_guard = '''        if recording.failure != nil {
            await recorderUIManager?.dismissRecorderSession(recording.recorderUISessionID)
        }
'''
require(engine_text.count(failure_ui_guard) == 1 and failure_ui_guard not in cb_sources[engine].decode(),
        "Expected one new camera-finalization failure dismissal absent from CB")
stale_failure_ui = engine_text.replace(failure_ui_guard, "", 1)
restoration_guard = "        if audioRestorationTask == nil {\n"
require(recorder_text.count(restoration_guard) == 1 and restoration_guard not in cb_sources[recorder].decode(),
        "Expected one new audio restoration coalescing guard absent from CB")
duplicate_restoration = recorder_text.replace(restoration_guard, "        do {\n", 1)
require("audioRestorationTaskForTesting?() ?? restoreAudio()" in duplicate_restoration,
        "Restoration revert must retain the current DEBUG scheduling seam")

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
    red_control(recognition, unfiltered_voice, "known-bad-non-speech-voice", non_speech_selection, 1,
                "Restore the exact CB recognition file: raw nonempty markers win and cancel lip fallback.")

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

    red_control(source, retained_accidental, "known-bad-lip-cancellation-history", lip_history_selection, 1,
                "Retain an accidental lip cancellation as a canceled History row instead of discarding it.")
    red_control(source, retained_empty, "known-bad-empty-lip-history", lip_empty_selection, 1,
                "Persist a completed empty lip result and session metric instead of discarding them.")
    red_control(engine, late_reservation, "known-bad-startup-history-reservation", startup_history_selection, 1,
                "Omit the user-cancel History reservation before awaiting startup; retain the later drain fallback.")
    red_control(engine, retained_lip_session_end, "known-bad-lip-session-end-history", lip_session_end_selection, 3,
                "Retain nil-audio History on implicit session end, including master-off, reset and shutdown.")
    red_control(source, retained_pipeline_session_end, "known-bad-pipeline-session-end-history", lip_pipeline_session_end_selection, 3,
                "Restore the S5 accidental-only pipeline discard guard; retain shared candidate policy and engine cancellation.")
    label = "known-bad-camera-finalization-ui"
    failed_ui = {
        "label": label, "selection": failure_ui_selection, "positiveSelection": newer_ui_selection,
        "knownBadCommit": cb_commit, "expectedFunctions": 2, "expectedInvocations": 2,
        "knownBadChange": "Remove only the CB-missing failed-finalization dismissal; retain current DEBUG capture-stop seam.",
    }
    with semantic_revert({engine: stale_failure_ui.encode()}, failed_ui):
        ui_exit, ui_summary = run(label, (failure_ui_selection, newer_ui_selection))
    failed_ui.update({"exitCode": ui_exit, "summary": ui_summary, "counts": counts(ui_summary)})
    save_receipt()
    require(ui_exit != 0
            and failed_ui["counts"]["functions"] == {"passed": 1, "failed": 1, "skipped": 0, "total": 2}
            and failed_ui["counts"]["invocations"] == {"passed": 1, "failed": 1, "skipped": 0, "total": 2}
            and failed_ui["counts"]["parameterizedInvocations"] == 0,
            f"{label} must fail old-session dismissal and pass newer-session preservation: {failed_ui['counts']}")
    require(ui_summary["testFailures"] and all(
        failure_ui_selection.split("/")[-1] in failure["testIdentifierString"]
        for failure in ui_summary["testFailures"]
    ), f"{label} failed outside its failed-finalization regression")
    verify_stop_assertions(label, failed_ui, failure_ui_selection)
    require(f"Test {newer_ui_selection.split('/')[-1]} passed after " in (evidence / f"{label}.log").read_text(),
            f"{label} did not execute the newer-session positive control")
    failed_ui["expectedFailureConfirmed"] = True
    save_receipt()
    red_control(recorder, duplicate_restoration, "known-bad-duplicate-audio-restoration", audio_restoration_selection, 1,
                "Restore unconditional CB restoration scheduling; retain DEBUG task factory and hardware cleanup.")
    require(len(receipt["controls"]) == 17
            and all(control.get("expectedFailureConfirmed") is True for control in receipt["controls"]),
            "All seventeen semantic controls must confirm their selected failures before the candidate gate")

    green_exit, green = run("candidate", candidate_selections)
    receipt["candidateSummary"] = green
    receipt["candidateExitCode"] = green_exit
    save_receipt()
    actual = counts(green)
    receipt["candidateCounts"] = actual
    save_receipt()
    require(green_exit == 0 and green["failedTests"] == 0
            and actual["functions"] == {"passed": 29, "failed": 0, "skipped": 0, "total": 29}
            and actual["invocations"] == {"passed": 38, "failed": 0, "skipped": 0, "total": 38}
            and actual["parameterizedInvocations"] == 14,
            f"Candidate must pass 29 functions / 38 invocations, including 14 parameterized runs: {actual}")
    receipt["status"] = "passed"
except BaseException as error:
    receipt.update({"status": "failed", "error": str(error)})
    raise
finally:
    receipt["restoredCandidateSourceSHA256"] = {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in candidates
    }
    receipt["finalTestSourceSHA256"] = {
        path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in receipt["testSourceSHA256"]
    }
    receipt["sourcesRestored"] = all(path.read_bytes() == data for path, data in candidates.items())
    receipt["testsUnchanged"] = receipt["finalTestSourceSHA256"] == receipt["testSourceSHA256"]
    if not receipt["sourcesRestored"] or not receipt["testsUnchanged"]:
        receipt.update({"status": "failed", "error": "Candidate sources or tests changed during controls"})
    save_receipt()
    require(receipt["sourcesRestored"], "Candidate sources changed after controls")
    require(receipt["testsUnchanged"], "Candidate tests changed during controls")
    if receipt["status"] == "passed":
        print("Candidate: 29 functions / 38 invocations passed; all seventeen semantic reverts failed; sources restored", flush=True)
