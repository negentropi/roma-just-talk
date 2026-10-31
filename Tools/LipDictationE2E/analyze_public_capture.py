#!/usr/bin/env python3
"""Diagnose explicit public-fixture capture copies; never installs a model."""

import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess


APP_HEAD = "6a3e4cbbef3e39bdf4ef6bf20fadb58824114ca1"
PUBLIC_SHA = "db7b8cf8cdbe547ab491c42801a1bae5b16c5471050d7e3d9e1f0173c7a0d8fc"


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def execute(command, log, cwd):
    with log.open("wb") as output:
        return subprocess.run([str(item) for item in command], cwd=cwd, stdout=output,
                              stderr=subprocess.STDOUT, timeout=600).returncode


def main():
    env = os.environ
    if (env.get("GITHUB_ACTIONS") != "true" or env.get("RUNNER_ENVIRONMENT") != "github-hosted"
            or not env.get("GITHUB_REF", "").startswith("refs/heads/ci/lip-runtime-diagnostic-")
            or platform.system() != "Darwin" or os.getuid() == 0
            or Path("/dev/console").stat().st_uid != os.getuid()):
        raise SystemExit("Only the explicit disposable GitHub-hosted diagnostic is allowed")
    root = Path(__file__).resolve().parents[2]
    temporary = Path(env["RUNNER_TEMP"]).resolve()
    evidence = temporary / "lip-dictation-e2e"
    output = evidence / "public-capture-analysis"
    output.mkdir(parents=True, exist_ok=True)
    receipt = {"diagnosticOnly": True, "appBuildHead": APP_HEAD, "proofGitHead": env["GITHUB_SHA"],
               "boundary": "Exact older app native package; existing actual-Setup model; no model install/download", "cases": []}
    try:
        context = json.loads((temporary / "lip-runtime-source/public-capture-context.json").read_text())
        assert context["diagnosticOnly"] is True and context["appBuildHead"] == APP_HEAD
        assert context["proofGitHead"] == env["GITHUB_SHA"] and context["publicSourceSHA256"] == PUBLIC_SHA
        assert Path(context["evidenceDirectory"]).resolve() == evidence
        copies = evidence / "public-captures"
        reports = sorted(copies.glob("*.json"))
        assert len(reports) <= 3
        if not reports:
            receipt["status"] = "noRetainedPublicCaptures"
            return
        cases = []
        for report in reports:
            item = json.loads(report.read_text())
            assert item["diagnosticOnly"] is True and item["publicFixtureOnly"] is True
            assert item["appBuildHead"] == APP_HEAD and item["proofGitHead"] == env["GITHUB_SHA"]
            assert item["scenario"] in ("combined", "combined-silent", "lips")
            assert item["copiedMovie"] == item["scenario"] + ".mov"
            movie = copies / item["copiedMovie"]
            assert movie.is_file() and not movie.is_symlink() and movie.stat().st_uid == os.getuid()
            assert 0 < movie.stat().st_size <= 64_000_000 and sha256(movie) == item["sha256"]
            cases.append((item, movie))
        work = temporary / "lip-runtime-public-analysis"
        work.mkdir(exist_ok=True)
        subprocess.run(["git", "fetch", "--no-tags", "--depth=1", "origin", APP_HEAD], cwd=root, check=True)
        package_diff = subprocess.check_output(["git", "diff", "--name-only", APP_HEAD, "HEAD", "--", "VoiceInkLip"], cwd=root, text=True)
        receipt["checkoutPackageDiffFromApp"] = package_diff.splitlines()
        receipt["compiledPackageGitTree"] = subprocess.check_output(["git", "rev-parse", APP_HEAD + ":VoiceInkLip"], cwd=root, text=True).strip()
        archive = work / "exact-app-package.tar"
        with archive.open("wb") as target:
            subprocess.run(["git", "archive", APP_HEAD, "VoiceInkLip"], cwd=root, stdout=target, check=True)
        source = work / "exact-app-source"
        source.mkdir(exist_ok=True)
        subprocess.run(["tar", "-xf", archive, "-C", source], check=True)
        package = source / "VoiceInkLip"
        scratch = work / "swift-build"
        build = ["swift", "build", "--package-path", package, "--scratch-path", scratch,
                 "--configuration", "release", "--product", "LipDictationProof", "--jobs", "4"]
        assert execute(build, output / "native-build.log", root) == 0, "Exact-app native CLI build failed"
        binary_dir = subprocess.check_output(["swift", "build", "--package-path", package, "--scratch-path", scratch,
                                              "--configuration", "release", "--show-bin-path"], text=True).strip()
        binary = Path(binary_dir) / "LipDictationProof"
        model = Path.home() / "Library/Application Support/com.negentropi.RomaJustTalk/WhisperModels/LipReading"
        assert model.is_dir(), "The actual app Setup did not install a lip model"
        receipt["modelDirectory"] = str(model)
        receipt["nativeExecutableSHA256"] = sha256(binary)
        probe_source = work / "LipVideoFrameProbe.swift"
        probe_source.write_bytes(subprocess.check_output(["git", "show", APP_HEAD + ":Tools/LipVideoFrameProbe.swift"], cwd=root))
        probe = work / "LipVideoFrameProbe"
        probe_status = execute(["xcrun", "swiftc", "-parse-as-library", probe_source, "-o", probe], output / "frame-probe-build.log", root)
        for item, movie in cases:
            name = item["scenario"]
            native_receipt = output / (name + "-native.json")
            command = [binary, "infer", "--model-directory", model, "--video", movie, "--receipt", native_receipt]
            status = execute(command, output / (name + "-native.log"), root)
            observed = json.loads(native_receipt.read_text()) if native_receipt.is_file() else {}
            result = {"scenario": name, "movieSHA256": item["sha256"], "nativeExitCode": status,
                      "nativeReceipt": native_receipt.name, "errorFrame": observed.get("errorFrame"),
                      "errorPresentationTime": observed.get("errorPresentationTime"), "errorDetails": observed.get("errorDetails"),
                      "status": observed.get("status")}
            if probe_status == 0:
                result["frameProbeExitCode"] = execute([probe, movie, output / (name + "-frames"), "3"], output / (name + "-frame-probe.log"), root)
            receipt["cases"].append(result)
            print(json.dumps(result), flush=True)
        receipt["status"] = "diagnosticCompleted"
    except Exception as error:
        receipt["status"] = "diagnosticFailed"
        receipt["error"] = str(error)
        raise
    finally:
        (output / "summary.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
