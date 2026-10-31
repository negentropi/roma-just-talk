#!/usr/bin/env python3
"""Diagnose explicit public-fixture capture copies; never installs a model."""

import hashlib
import json
import os
from pathlib import Path
import platform
import stat
import subprocess
import zipfile


APP_HEAD = "6a3e4cbbef3e39bdf4ef6bf20fadb58824114ca1"
PUBLIC_SHA = "db7b8cf8cdbe547ab491c42801a1bae5b16c5471050d7e3d9e1f0173c7a0d8fc"
BAD_RUN = 41157989283
BAD_HEAD = "7058286b465788422fac0a653f0a9d8e5bd16722"
BAD_ARTIFACT = 13026335983
BAD_ARCHIVE_SHA = "0757a717bc342de64308159815b45279e92969f025b2297b28831ad32049bf27"
BAD_MOVIE_SHA = "4ddd916d17b3dce5ca62d9c591037298f78f79be35361fb8b1c82a70cc40c9fe"
BAD_MEMBER = "lip-dictation-e2e/public-captures/combined-silent.mov"


def extract_known_bad_capture(archive_path, destination):
    with zipfile.ZipFile(archive_path) as archive:
        members = archive.infolist()
        names = [item.filename for item in members]
        assert len(names) == len(set(names)), "Duplicate artifact member names"

        def member(name, limit):
            assert names.count(name) == 1, "Missing exact public capture artifact member"
            item = archive.getinfo(name)
            assert not item.is_dir() and not stat.S_ISLNK(item.external_attr >> 16), "Symlink or directory artifact member"
            assert 0 < item.file_size <= limit, "Artifact member exceeds its diagnostic bound"
            return item

        def metadata(name):
            item = member(name, 16_384)
            return json.loads(archive.read(item))

        captured = metadata("lip-dictation-e2e/public-captures/combined-silent.json")
        context = metadata("lip-runtime-source/public-capture-context.json")
        assert captured["diagnosticOnly"] is True and captured["publicFixtureOnly"] is True
        assert captured["scenario"] == "combined-silent" and captured["copiedMovie"] == "combined-silent.mov"
        assert captured["proofGitHead"] == BAD_HEAD and captured["appBuildHead"] == APP_HEAD
        assert captured["sha256"] == BAD_MOVIE_SHA and captured["matchingCaptureClosedObserved"] is True
        assert captured["captureRootEmptyBeforeShortcut"] is True and captured["matchingDrainObservedBeforeCopy"] is False
        assert context["diagnosticOnly"] is True and context["proofGitHead"] == BAD_HEAD
        assert context["appBuildHead"] == APP_HEAD and context["publicSourceSHA256"] == PUBLIC_SHA
        movie = member(BAD_MEMBER, 64_000_000)
        total = 0
        with archive.open(movie) as source, destination.open("xb") as target:
            for data in iter(lambda: source.read(1_048_576), b""):
                total += len(data)
                assert total <= 64_000_000, "Public MOV exceeded extraction bound"
                target.write(data)
        assert total == movie.file_size == captured["bytes"]
        assert sha256(destination) == BAD_MOVIE_SHA, "Known-bad public MOV hash mismatch"
        return {"originalCaptureReceipt": captured, "originalPublicContext": context,
                "selectedMember": BAD_MEMBER, "extractedBytes": total, "movieSHA256": BAD_MOVIE_SHA}


def retrieve_known_bad_capture(root, work, output):
    directory = output / "known-bad"
    directory.mkdir()
    endpoint = f"repos/negentropi/roma-just-talk/actions/artifacts/{BAD_ARTIFACT}"
    artifact = json.loads(subprocess.check_output(["gh", "api", endpoint], cwd=root, text=True))
    (directory / "artifact.json").write_text(json.dumps(artifact, indent=2) + "\n")
    assert artifact["id"] == BAD_ARTIFACT and artifact["name"] == "lip-runtime-diagnostic-evidence"
    assert artifact["expired"] is False and artifact["workflow_run"]["id"] == BAD_RUN
    assert artifact["workflow_run"]["head_sha"] == BAD_HEAD
    assert artifact["workflow_run"]["repository_id"] == artifact["workflow_run"]["head_repository_id"] == 1253985786
    assert artifact["size_in_bytes"] == 18_368_425 and artifact["digest"] == "sha256:" + BAD_ARCHIVE_SHA
    archive = work / "known-bad-runtime-artifact.zip"
    with archive.open("xb") as target, (directory / "download.log").open("wb") as log:
        subprocess.run(["gh", "api", endpoint + "/zip"], cwd=root, stdout=target, stderr=log, timeout=120, check=True)
    assert archive.stat().st_size == artifact["size_in_bytes"] and sha256(archive) == BAD_ARCHIVE_SHA
    movie = directory / "retained-combined-silent.mov"
    provenance = extract_known_bad_capture(archive, movie)
    provenance.update({"diagnosticOnly": True, "sourceRepository": "negentropi/roma-just-talk",
                       "sourceRun": BAD_RUN, "sourceHead": BAD_HEAD, "artifactID": BAD_ARTIFACT,
                       "artifactSHA256": BAD_ARCHIVE_SHA, "extractionBoundary": "Only the exact public MOV is extracted; two small original provenance JSON members are read, not executed."})
    (directory / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    return movie, directory


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
    receipt = {"diagnosticOnly": True, "candidateAcceptanceAssessed": False,
               "appBuildHead": APP_HEAD, "proofGitHead": env["GITHUB_SHA"],
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
        bad_movie, bad_directory = retrieve_known_bad_capture(root, work, output)
        bad_receipt = bad_directory / "native-preprocess.json"
        bad_command = [binary, "preprocess", "--video", bad_movie,
                       "--mouth-dump", bad_directory / "unexpected-mouth.float32", "--receipt", bad_receipt]
        bad_status = execute(bad_command, bad_directory / "native-preprocess.log", root)
        bad_result = json.loads(bad_receipt.read_text()) if bad_receipt.is_file() else {}
        expected_bad = (bad_status == 1 and bad_result.get("status") == "error"
                        and bad_result.get("errorCode") == "mouthVideo.missingFace"
                        and bad_result.get("errorType") == "VoiceInkLip.MouthVideoProcessingError"
                        and bad_result.get("errorFrame") == 22
                        and isinstance(bad_result.get("errorPresentationTime"), (int, float))
                        and abs(bad_result["errorPresentationTime"] - 0.88) < 1e-9
                        and bad_result.get("text", "") == "" and bad_result.get("videoSHA256") == BAD_MOVIE_SHA)
        receipt["knownBad"] = {"requiredResultMatched": expected_bad, "sourceRun": BAD_RUN,
                               "movieSHA256": BAD_MOVIE_SHA, "nativeExitCode": bad_status,
                               "nativeReceipt": "known-bad/native-preprocess.json",
                               "errorFrame": bad_result.get("errorFrame"),
                               "errorPresentationTime": bad_result.get("errorPresentationTime"),
                               "errorDetails": bad_result.get("errorDetails"),
                               "nativeExecutableSHA256": receipt["nativeExecutableSHA256"],
                               "compiledPackageGitTree": receipt["compiledPackageGitTree"]}
        print(json.dumps({"knownBad": receipt["knownBad"]}), flush=True)
        assert expected_bad, "Known-bad replay must reject the actual public MOV at missingFace frame 22, time 0.88"
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
