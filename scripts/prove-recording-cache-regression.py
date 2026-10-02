#!/usr/bin/env python3
"""Compare the cache regression on a disposable macOS Actions checkout."""

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import stat
import subprocess
import sys
import time


KNOWN_BAD = "238516c5cd6022eed161aead00db6fa588e778e1"
SOURCE = "VoiceInkQwen/Sources/VoiceInkQwen/QwenRuntime.swift"
TEST = "VoiceInkQwen/Tests/VoiceInkQwenTests/QwenRuntimeCacheCleanupTests.swift"
FILTER = "acceptedLivePassesRetainBuffersUntilFinishOrIdleCancellation"
BEHAVIORAL_MARKER = "A continuing live pass must retain its reusable buffers"
BUILD_ARGS = ["--package-path", "VoiceInkQwen", "-c", "release",
              "--force-resolved-versions", "-Xswiftc", "-enable-testing"]
BUILD_COMMAND = ["swift", "build", *BUILD_ARGS, "--build-tests"]
TEST_COMMAND = ["swift", "test", *BUILD_ARGS, "--skip-build", "--filter", FILTER]
spawning_process = False
pending_interrupt = None


@dataclass(frozen=True)
class PhaseResult:
    command: list[str]
    pid: int | None
    pgid: int | None
    timeout_seconds: float
    elapsed_seconds: float
    returncode: int | None
    timed_out: bool
    log: str


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def terminate_group(process):
    # The compiler/test descendants may survive after the Swift driver exits.
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass
        if sig == signal.SIGTERM:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
    process.wait(timeout=5)
    deadline = time.monotonic() + 5
    while True:
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            return
        except PermissionError:
            # Darwin can return EPERM before the emptied group disappears.
            pass
        require(time.monotonic() < deadline, "Owned subprocess group did not terminate")
        time.sleep(0.05)


def interrupt(signum, _frame):
    global pending_interrupt
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    if spawning_process:
        pending_interrupt = signum
        return
    raise InterruptedError(f"Received {signal.Signals(signum).name}")


def run_phase(root, out, name, command, timeout):
    global spawning_process, pending_interrupt
    log_path = out / f"{name}.log"
    result_path = out / f"{name}.json"
    running = {"state": "running", "command": command, "pid": None, "pgid": None,
               "timeout_seconds": timeout, "log": str(log_path)}
    save_json(result_path, running)
    started = time.monotonic()
    process = None
    timed_out = False
    failure = None
    print(f"{name}: starting; budget={timeout}s; log={log_path}", flush=True)
    with log_path.open("wb") as log:
        try:
            spawning_process = True
            try:
                process = subprocess.Popen(command, cwd=root, stdout=log,
                                           stderr=subprocess.STDOUT, start_new_session=True)
            finally:
                spawning_process = False
            running.update(pid=process.pid, pgid=process.pid)
            save_json(result_path, running)
            if pending_interrupt is not None:
                signum, pending_interrupt = pending_interrupt, None
                interrupt(signum, None)
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
        except BaseException as error:
            failure = error
        finally:
            if process is not None:
                try:
                    terminate_group(process)
                except (InterruptedError, KeyboardInterrupt) as error:
                    failure = error
                    try:
                        terminate_group(process)
                    except BaseException as cleanup_error:
                        failure = cleanup_error
                except BaseException as error:
                    failure = error
    result = PhaseResult(command, process.pid if process is not None else None,
                         process.pid if process is not None else None,
                         timeout, round(time.monotonic() - started, 3),
                         process.returncode if process is not None else None,
                         timed_out, str(log_path))
    metadata = asdict(result)
    metadata["classification"] = ("timeout" if timed_out else
                                  "exit-success" if result.returncode == 0 else "exit-failure")
    if failure is not None:
        metadata["classification"] = "interrupted-or-process-failure"
        metadata["failure"] = f"{type(failure).__name__}: {failure}"
    save_json(result_path, metadata)
    print(f"{name}: exit={result.returncode}; timeout={timed_out}; "
          f"elapsed={result.elapsed_seconds}s", flush=True)
    if result.returncode != 0:
        print("\n".join(log_path.read_text(errors="replace").splitlines()[-40:]), flush=True)
    if failure is not None:
        raise failure
    return result


def git_output(root, *arguments):
    return subprocess.check_output(["git", *arguments], cwd=root, timeout=30)


def tracked_tree(root):
    entries = []
    for record in git_output(root, "ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        mode, blob, stage = metadata.decode().split()
        require(stage == "0", "Unmerged tracked file in proof checkout")
        path = os.fsdecode(raw_path)
        file = root / path
        content = os.fsencode(os.readlink(file)) if file.is_symlink() else file.read_bytes()
        entries.append({"path": path, "index_mode": mode, "index_blob": blob,
                        "mode": stat.S_IMODE(file.lstat().st_mode), "sha256": digest(content)})
    return entries


def dependency_snapshot(root):
    paths = ["VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
             "VoiceInkQwen/Package.resolved"]
    snapshots = {}
    for path in paths:
        data = (root / path).read_bytes()
        snapshots[path] = {"sha256": digest(data), "resolved": json.loads(data)}
    app, package = [snapshots[path]["resolved"] for path in paths]
    app_pins = {pin["identity"]: pin for pin in app["pins"]}
    require(bool(package["pins"]), "Prewarm Qwen before running the cache proof")
    for pin in package["pins"]:
        expected = app_pins.get(pin["identity"])
        require(expected is not None, f"Package absent from app graph: {pin['identity']}")
        require(pin["state"]["revision"] == expected["state"]["revision"],
                f"Package revision mismatch: {pin['identity']}")
        normalize = lambda url: url.rstrip("/").removesuffix(".git").lower()
        require(normalize(pin["location"]) == normalize(expected["location"]),
                f"Package source mismatch: {pin['identity']}")
    return snapshots


def test_observations(text):
    arguments = sorted(set(re.findall(
        rf"Test case passing 1 argument cancel → (false|true) to {FILTER}\(cancel:\) started\.",
        text)))
    summaries = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
    actual = [(int(count), status) for count, status in summaries if int(count) > 0]
    return {"arguments_started": arguments, "summaries": actual,
            "behavioral_marker": BEHAVIORAL_MARKER in text,
            "runtime_failure": bool(re.search(
                r"time limit|timed out|fatal error:|signal \d+", text, re.IGNORECASE))}


def prove_lane(root, out, name, shader, expected_shader, dependencies, receipt):
    lane = receipt["lanes"][name] = {"classification": "building"}
    build = run_phase(root, out, f"{name}-build", BUILD_COMMAND, 900)
    lane["build"] = asdict(build)
    require(not build.timed_out, f"{name}: build timeout is invalid regression evidence")
    require(build.returncode == 0, f"{name}: compilation failed")
    require("Build complete!" in Path(build.log).read_text(errors="replace"),
            f"{name}: successful build marker missing")
    bin_phase = run_phase(root, out, f"{name}-bin-path",
                          ["swift", "build", *BUILD_ARGS, "--show-bin-path"], 30)
    require(not bin_phase.timed_out and bin_phase.returncode == 0,
            f"{name}: could not locate built test executable")
    bin_path = Path(Path(bin_phase.log).read_text().strip())
    require(bin_path.is_absolute(), f"{name}: invalid SwiftPM binary path")
    executable = bin_path / "VoiceInkQwenPackageTests.xctest/Contents/MacOS/VoiceInkQwenPackageTests"
    require(executable.is_file() and os.access(executable, os.X_OK),
            f"{name}: built test executable missing")
    require(shader.read_bytes() == expected_shader, "App shader changed during proof")
    installed_shader = executable.parent / "mlx.metallib"
    shutil.copyfile(shader, installed_shader)
    require(installed_shader.read_bytes() == expected_shader, f"{name}: shader byte mismatch")
    lane["shader_sha256"] = digest(installed_shader.read_bytes())
    lane["test_executable"] = str(executable)
    lane["dependencies_after_build"] = dependency_snapshot(root)
    require(lane["dependencies_after_build"] == dependencies, f"{name}: dependency graph drift")
    lane["classification"] = "running"
    runtime = run_phase(root, out, f"{name}-test", TEST_COMMAND, 150)
    lane["test"] = asdict(runtime)
    observed = test_observations(Path(runtime.log).read_text(errors="replace"))
    lane["observations"] = observed
    require(not runtime.timed_out, f"{name}: test timeout is invalid regression evidence")
    require(not observed["runtime_failure"], f"{name}: runtime failure is invalid regression evidence")
    require(observed["arguments_started"] == ["false", "true"],
            f"{name}: both Bool argument cases must actually start")
    require(bool(observed["summaries"]), f"{name}: nonzero Swift Testing count missing")
    if name == "known-bad":
        require(runtime.returncode > 0 and observed["behavioral_marker"]
                and observed["summaries"][-1][1] == "failed",
                "Known bad must fail the literal cache behavior assertion")
        lane["classification"] = "behavioral-red"
    else:
        require(runtime.returncode == 0 and observed["summaries"][-1][1] == "passed",
                "Candidate regression test must pass")
        lane["classification"] = "behavioral-green"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Prewarmed candidate Release app")
    args = parser.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true" or platform.system() != "Darwin":
        parser.error("Run only on a disposable macOS Actions runner")
    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    root = Path(__file__).resolve().parents[1]
    out = root / ".local-build/recording-cache-regression"
    out.mkdir(parents=True, exist_ok=False)
    receipt_path = out / "receipt.json"
    receipt = {"known_bad": KNOWN_BAD, "classification": "preparing", "lanes": {}}
    save_json(receipt_path, receipt)
    source = root / SOURCE
    candidate = source.read_bytes()
    candidate_hash = digest(candidate)
    dependencies = None
    before = None
    shader = None
    expected_shader = None
    failure = None
    try:
        receipt["candidate_head"] = git_output(root, "rev-parse", "HEAD").decode().strip()
        require(not git_output(root, "diff", "--name-only", "HEAD"),
                "Proof checkout must match its tracked HEAD before source replacement")
        receipt["candidate_source_sha256"] = candidate_hash
        receipt["test_source_sha256"] = digest((root / TEST).read_bytes())
        (out / "candidate-QwenRuntime.swift").write_bytes(candidate)
        (out / "QwenRuntimeCacheCleanupTests.swift").write_bytes((root / TEST).read_bytes())
        before = tracked_tree(root)
        save_json(out / "tracked-tree-before.json", before)
        receipt["tracked_tree_before_sha256"] = digest(json.dumps(before, sort_keys=True).encode())
        dependencies = dependency_snapshot(root)
        save_json(out / "dependencies-before.json", dependencies)
        shader = args.app.resolve() / "Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        expected_shader = shader.read_bytes()
        require(bool(expected_shader), "Candidate app shader is empty")
        receipt["app"] = str(args.app.resolve())
        receipt["app_shader_sha256"] = digest(expected_shader)
        fetch = run_phase(root, out, "fetch-known-bad",
                          ["git", "fetch", "--no-tags", "--depth=1", "origin", KNOWN_BAD], 120)
        receipt["fetch"] = asdict(fetch)
        require(not fetch.timed_out and fetch.returncode == 0, "Could not fetch exact known-bad source")
        bad = git_output(root, "show", f"{KNOWN_BAD}:{SOURCE}")
        receipt["known_bad_source_sha256"] = digest(bad)
        (out / "known-bad-QwenRuntime.swift").write_bytes(bad)
        require(bad != candidate, "Known-bad source must differ from candidate")
        try:
            source.write_bytes(bad)
            prove_lane(root, out, "known-bad", shader, expected_shader, dependencies, receipt)
        finally:
            source.write_bytes(candidate)
            require(digest(source.read_bytes()) == candidate_hash, "Candidate restoration failed")
            save_json(receipt_path, receipt)
        prove_lane(root, out, "candidate", shader, expected_shader, dependencies, receipt)
        require(shader.read_bytes() == expected_shader, "App shader changed during proof")
        receipt["classification"] = "matched-regression-passed"
    except BaseException as error:
        failure = error
        receipt["classification"] = "invalid-or-failed-proof"
        receipt["failure"] = f"{type(error).__name__}: {error}"
    finally:
        source.write_bytes(candidate)
        receipt["restored_source_sha256"] = digest(source.read_bytes())
        try:
            require(receipt["restored_source_sha256"] == candidate_hash, "Candidate restoration failed")
            after = tracked_tree(root)
            save_json(out / "tracked-tree-after.json", after)
            receipt["tracked_tree_after_sha256"] = digest(json.dumps(after, sort_keys=True).encode())
            if before is not None:
                require(after == before, "Tracked source tree changed during proof")
            if dependencies is not None:
                after_dependencies = dependency_snapshot(root)
                save_json(out / "dependencies-after.json", after_dependencies)
                require(after_dependencies == dependencies, "Dependency graph changed during proof")
            if expected_shader is not None:
                receipt["app_shader_after_sha256"] = digest(shader.read_bytes())
                require(shader.read_bytes() == expected_shader, "App shader changed during proof")
            receipt["tracked_tree_unchanged"] = before is not None and after == before
        except BaseException as error:
            failure = error
            receipt["classification"] = "invalid-or-failed-proof"
            receipt["restoration_failure"] = f"{type(error).__name__}: {error}"
        save_json(receipt_path, receipt)
    print(f"Cache proof: {receipt['classification']}; receipt={receipt_path}", flush=True)
    if failure is not None:
        print(str(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
