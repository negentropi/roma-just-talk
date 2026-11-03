#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone


KNOWN_BAD = "238516c5cd6022eed161aead00db6fa588e778e1"
TEST = "acceptedLivePassesRetainBuffersUntilFinishOrIdleCancellation(cancel:)"
ASSERTION = "A continuing live pass must retain its reusable buffers"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save(out, receipt):
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


def group_exists(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False


def drain(process):
    handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        for sig, budget in ((signal.SIGTERM, 3), (signal.SIGKILL, 5)):
            process.poll()
            if not group_exists(process.pid):
                return True
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                pass
            deadline = time.monotonic() + budget
            while time.monotonic() < deadline:
                process.poll()
                if not group_exists(process.pid):
                    return True
                time.sleep(0.05)
        return not group_exists(process.pid)
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


def run_phase(root, out, receipt, label, command, budget):
    started = time.monotonic()
    record = {"label": label, "command": command, "budgetSeconds": budget,
              "startedUTC": datetime.now(timezone.utc).isoformat(), "status": "running",
              "exitCode": None, "exception": None, "logs": {}}
    receipt["phases"].append(record)
    save(out, receipt)
    print(f"START {label}, budget {budget}s; logs {out / label}", flush=True)
    process = None
    try:
        with (out / f"{label}.stdout.log").open("wb") as stdout, (out / f"{label}.stderr.log").open("wb") as stderr:
            try:
                process = subprocess.Popen(command, cwd=root, stdin=subprocess.DEVNULL,
                                           stdout=stdout, stderr=stderr, start_new_session=True)
                record["processGroupID"] = process.pid
                save(out, receipt)
                process.wait(timeout=budget)
                record["status"] = "exited"
            except BaseException as error:
                record["status"] = "timedOut" if isinstance(error, subprocess.TimeoutExpired) else "interruptedOrFailed"
                record["exception"] = {"type": type(error).__name__, "message": str(error)}
                raise
            finally:
                record["commandElapsedSeconds"] = time.monotonic() - started
                if process is not None:
                    record["processGroupDrained"] = drain(process)
                    record["exitCode"] = process.returncode
    except BaseException as error:
        if record["exception"] is None:
            record["status"] = "interruptedOrFailed"
            record["exception"] = {"type": type(error).__name__, "message": str(error)}
        raise
    finally:
        record["elapsedSeconds"] = time.monotonic() - started
        record["finishedUTC"] = datetime.now(timezone.utc).isoformat()
        for stream in ("stdout", "stderr"):
            path = out / f"{label}.{stream}.log"
            if path.exists():
                record["logs"][stream] = {"path": path.name, "bytes": path.stat().st_size, "sha256": sha256(path)}
        save(out, receipt)
        print(f"END {label}, {record['status']}, exit {record['exitCode']}, {record['elapsedSeconds']:.3f}s", flush=True)
        require(record.get("processGroupDrained") is not False, f"{label} process group did not drain")
    return record


def phase_text(out, record):
    return "\n".join((out / record["logs"][stream]["path"]).read_text(errors="replace")
                     for stream in ("stdout", "stderr"))


def behavior(log, known_bad):
    identity = re.escape(TEST)
    require(not re.search(r"\b(skipped|skipping|timed out|time limit exceeded|no matching tests?|unexpected signal|crashed)\b", log, re.I),
            "Behavioral proof cannot contain skips, timeouts, missing tests or crashes")
    require(re.findall(r"Test (?!case )([^\n]+\([^\n]*\)) started\.", log) == [TEST],
            "Expected exactly the selected recording-cache test function")
    cases = re.findall(r"Test case passing 1 argument cancel → (false|true) to " + identity + r" started\.", log)
    require(sorted(cases) == ["false", "true"], "Expected both actual cancel Bool invocations exactly once")
    outcome = "failed" if known_bad else "passed"
    require(len(re.findall(r"Test " + identity + r" with 2 test cases " + outcome + r" after ", log)) == 1
            and len(re.findall(r"Test run with 1 test(?: in \d+ suites?)? " + outcome + r" after ", log)) == 1,
            "Expected one completed function with two actual cases")
    lines = log.splitlines()
    issues = [(line, lines[index + 1].strip() if index + 1 < len(lines) else "")
              for index, line in enumerate(lines) if "recorded an issue" in line]
    if known_bad:
        for value in ("false", "true"):
            require(any(f"Test {TEST} recorded an issue with 1 argument cancel → {value} " in header
                        and "QwenRuntimeCacheCleanupTests.swift:" in header
                        and (ASSERTION in header or (header.rstrip().endswith(": Issue recorded")
                             and continuation == f"↳ {ASSERTION}")) for header, continuation in issues),
                    f"Known bad did not reach the reusable-buffer assertion for cancel={value}")
    else:
        require(not issues, "Candidate recorded a test issue")
    return {"functions": 1, "invocations": 2, "cancelArguments": cases,
            "outcome": outcome, "intendedAssertionConfirmed": known_bad}


def verify(root, app, out):
    out.mkdir(parents=True, exist_ok=False)
    package = root / "VoiceInkQwen"
    source = package / "Sources/VoiceInkQwen/QwenRuntime.swift"
    app_lock = root / "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    package_lock = package / "Package.resolved"
    inputs = [source, package / "Package.swift", app_lock, package_lock, *sorted((package / "Tests").rglob("*.swift"))]
    originals = {}
    receipt = {"status": "running", "knownBad": KNOWN_BAD, "githubRunID": os.environ.get("GITHUB_RUN_ID"),
               "githubSHA": os.environ.get("GITHUB_SHA"), "phases": [],
               "inputSHA256": {}}
    save(out, receipt)

    def restore_inputs():
        receipt["restoreProcessGroupsDrained"] = all(not group_exists(phase["processGroupID"])
                                                   for phase in receipt["phases"] if "processGroupID" in phase)
        save(out, receipt)
        require(receipt["restoreProcessGroupsDrained"], "Refuse to restore while an owned process can read mutated source")
        changed = [path for path, data in originals.items() if not path.is_file() or path.read_bytes() != data]
        unexpected = [str(path.relative_to(root)) for path in changed if path != source]
        for path, data in originals.items():
            if path in changed:
                path.write_bytes(data)
        receipt["restoredInputSHA256"] = {str(path.relative_to(root)): sha256(path) for path in originals}
        receipt["sourceAndInputsRestored"] = receipt["inputSHA256"] == receipt["restoredInputSHA256"]
        receipt.setdefault("unexpectedInputChanges", []).extend(unexpected)
        save(out, receipt)
        require(receipt["sourceAndInputsRestored"] and not receipt["unexpectedInputChanges"],
                "Source, tests or package pins changed unexpectedly during the control")

    try:
        for path in inputs:
            originals[path] = path.read_bytes()
            receipt["inputSHA256"][str(path.relative_to(root))] = hashlib.sha256(originals[path]).hexdigest()
        receipt["candidateSourceSHA256"] = receipt["inputSHA256"][str(source.relative_to(root))]
        shader = app / "Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        require(shader.is_file() and shader.stat().st_size > 0, "Missing shader from the preceding full Qwen gate")
        receipt["shader"] = {"path": str(shader), "sha256": sha256(shader)}
        app_pins = {pin["identity"]: pin for pin in json.loads(app_lock.read_text())["pins"]}
        pins = json.loads(package_lock.read_text())["pins"]
        require(pins, "Preceding full Qwen gate did not establish package pins")
        for pin in pins:
            expected = app_pins.get(pin["identity"])
            require(expected is not None and pin["state"]["revision"] == expected["state"]["revision"]
                    and pin["location"].rstrip("/").removesuffix(".git").lower()
                    == expected["location"].rstrip("/").removesuffix(".git").lower(),
                    f"Qwen package pin differs from the built app: {pin['identity']}")
        receipt["verifiedPackageRevisions"] = {pin["identity"]: pin["state"]["revision"] for pin in pins}
        flags = ["--package-path", str(package), "-c", "release", "--force-resolved-versions", "-Xswiftc", "-enable-testing"]
        fetched = run_phase(root, out, receipt, "historic-fetch", ["git", "fetch", "--no-tags", "--depth=1", "origin", KNOWN_BAD], 120)
        require(fetched["exitCode"] == 0, "Historic source fetch failed")
        historic = run_phase(root, out, receipt, "historic-source", ["git", "show", f"{KNOWN_BAD}:{source.relative_to(root)}"], 30)
        require(historic["exitCode"] == 0, "Historic source lookup failed")
        bad = (out / historic["logs"]["stdout"]["path"]).read_bytes()
        require(bad and bad != originals[source], "Known-bad source must differ from the candidate")
        receipt["knownBadSourceSHA256"] = hashlib.sha256(bad).hexdigest()
        location = run_phase(root, out, receipt, "test-bin-path", ["swift", "build", *flags, "--show-bin-path"], 30)
        require(location["exitCode"] == 0, "SwiftPM test binary lookup failed")
        locations = (out / location["logs"]["stdout"]["path"]).read_text().splitlines()
        require(len(locations) == 1, "SwiftPM did not report one test binary directory")
        bin_path = Path(locations[0])
        require(bin_path.is_absolute(), "SwiftPM did not report an absolute binary directory")
        executable = bin_path / "VoiceInkQwenPackageTests.xctest/Contents/MacOS/VoiceInkQwenPackageTests"

        for label, data in (("known-bad", bad), ("candidate", originals[source])):
            try:
                source.write_bytes(data)
                build = run_phase(root, out, receipt, label + "-BUILD_TESTS", ["swift", "build", *flags, "--build-tests"], 600)
                require(build["exitCode"] == 0 and "Build complete!" in phase_text(out, build)
                        and executable.is_file() and os.access(executable, os.X_OK),
                        f"{label} did not build the actual Release test executable")
                shader_destination = executable.parent / "mlx.metallib"
                shutil.copyfile(shader, shader_destination)
                require(sha256(shader_destination) == receipt["shader"]["sha256"], "Test shader differs from the preceding app build")
                receipt.setdefault("testExecutables", {})[label] = {"path": str(executable), "sha256": sha256(executable),
                                                                  "shaderSHA256": sha256(shader_destination)}
                runtime = run_phase(root, out, receipt, label + "-SKIP_BUILD", ["swift", "test", *flags, "--skip-build", "--filter", TEST.split("(")[0]], 150)
                require((runtime["exitCode"] > 0 if label == "known-bad" else runtime["exitCode"] == 0),
                        f"{label} behavioral test exited unexpectedly")
                receipt[label] = behavior(phase_text(out, runtime), label == "known-bad")
                save(out, receipt)
            finally:
                restore_inputs()
    except BaseException as error:
        receipt.update({"status": "failed", "error": {"type": type(error).__name__, "message": str(error)}})
        raise
    finally:
        try:
            restore_inputs()
        except BaseException as error:
            receipt.update({"status": "failed", "error": {"type": type(error).__name__, "message": str(error)}})
            raise
        finally:
            save(out, receipt)
    receipt.update({"status": "passed", "behavioralRed": True, "candidateGreen": True})
    save(out, receipt)


def main():
    require(os.environ.get("GITHUB_ACTIONS") == "true" and sys.platform == "darwin",
            "Run on a disposable macOS Actions host")
    require(len(sys.argv) == 2, "Usage: verify-recording-cache-regression.py /path/to/built/app")
    def interrupted(signum, frame):
        raise InterruptedError(f"Received signal {signum}")
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, interrupted)
    root = Path(__file__).resolve().parent.parent
    verify(root, Path(sys.argv[1]), root / ".local-build/recording-cache-regression")


if __name__ == "__main__":
    main()
