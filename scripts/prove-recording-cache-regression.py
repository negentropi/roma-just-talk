#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time


KNOWN_BAD = "238516c5cd6022eed161aead00db6fa588e778e1"
ASSERTION = "A continuing live pass must retain its reusable buffers"


class ProcessCleanupError(RuntimeError):
    pass


def stop_process_group(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired as error:
        raise ProcessCleanupError("Compiler process did not exit after SIGKILL") from error
    deadline = time.monotonic() + 5
    while True:
        try:
            listing = subprocess.check_output(["ps", "-axo", "pgid=,stat="], text=True, timeout=5)
        except (OSError, subprocess.SubprocessError) as error:
            raise ProcessCleanupError("Compiler process group termination could not be inspected") from error
        alive = any(
            fields[0] == str(process.pid) and not fields[1].startswith("Z")
            for line in listing.splitlines()
            if len(fields := line.split()) == 2
        )
        if not alive:
            return
        if time.monotonic() >= deadline:
            raise ProcessCleanupError("Compiler process group remains alive; source must not be restored")
        time.sleep(0.05)


def run_phase(command, log_path, timeout):
    started = time.monotonic()
    with log_path.open("xb") as output:
        process = subprocess.Popen(
            command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True
        )
        try:
            result = process.wait(timeout=timeout)
        finally:
            try:
                stop_process_group(process)
            except BaseException as error:
                raise ProcessCleanupError("Compiler process group cleanup was interrupted or failed") from error
    print(log_path.read_text(errors="replace"), flush=True)
    return {"exitCode": result, "seconds": time.monotonic() - started}


def prove_regression(source, bad_source, command, evidence, timeout):
    candidate = source.read_bytes()
    digest = hashlib.sha256(candidate).hexdigest()
    cleanup_failed = False
    try:
        source.write_bytes(bad_source)
        red = run_phase(command, evidence / "known-bad.log", timeout)
        output = (evidence / "known-bad.log").read_text(errors="replace")
        if red["exitCode"] == 0 or ASSERTION not in output or "Build complete!" not in output:
            raise RuntimeError("Known bad must fail the behavioral assertion after a successful build")
    except ProcessCleanupError:
        cleanup_failed = True
        (evidence / "cleanup-failed.txt").write_text("Compiler group termination was not established\n")
        (evidence / "candidate-source.swift").write_bytes(candidate)
        raise
    finally:
        if not cleanup_failed:
            source.write_bytes(candidate)
            if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
                raise RuntimeError("Candidate source was not restored")
    green = run_phase(command, evidence / "candidate.log", timeout)
    if green["exitCode"] != 0:
        raise RuntimeError("Candidate recording-cache regression failed")
    receipt = {
        "knownBad": KNOWN_BAD,
        "candidateSourceSHA256": digest,
        "behavioralRed": True,
        "candidateGreen": True,
        "knownBadPhase": red,
        "candidatePhase": green,
    }
    (evidence / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


def interrupted(signum, frame):
    raise InterruptedError(f"Regression check interrupted by signal {signum}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path)
    args = parser.parse_args()
    root = args.repo.resolve()
    source = root / "VoiceInkQwen/Sources/VoiceInkQwen/QwenRuntime.swift"
    evidence = root / ".local-build/recording-cache-regression"
    evidence.mkdir()
    signal.signal(signal.SIGTERM, interrupted)
    subprocess.run(
        ["git", "-C", str(root), "fetch", "--no-tags", "--depth=1", "origin", KNOWN_BAD],
        check=True, timeout=60,
    )
    bad_source = subprocess.check_output(
        ["git", "-C", str(root), "show", KNOWN_BAD + ":VoiceInkQwen/Sources/VoiceInkQwen/QwenRuntime.swift"],
        timeout=30,
    )
    command = [
        "swift", "test", "--package-path", str(root / "VoiceInkQwen"), "-c", "release",
        "--force-resolved-versions", "-Xswiftc", "-enable-testing", "--filter",
        "acceptedLivePassesRetainBuffersUntilFinishOrIdleCancellation",
    ]
    prove_regression(source, bad_source, command, evidence, timeout=360)


if __name__ == "__main__":
    main()
