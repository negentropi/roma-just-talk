#!/usr/bin/env python3

import copy
import hashlib
import json
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify-macos-release-qualification.py"
SOURCE = "d504e90e63035c4cb8e9597cbef9894253fdaf01"
RUN = {
    "id": 37140159415, "run_attempt": 1, "head_sha": SOURCE,
    "path": ".github/workflows/voiceink-build.yml", "status": "completed",
    "conclusion": "success", "event": "workflow_dispatch",
    "repository": {"full_name": "negentropi/roma-just-talk"},
    "head_repository": {"full_name": "negentropi/roma-just-talk"},
}
JOBS = {"total_count": 1, "jobs": [{
    "id": 111252888702, "run_id": 37140159415, "run_attempt": 1,
    "name": "Build release macOS app", "runner_id": 1000000726,
    "runner_name": "GitHub Actions 1000000726", "runner_group_name": "GitHub Actions",
    "labels": ["macos-26"], "status": "completed", "conclusion": "success",
    "started_at": "2026-10-03T17:21:37Z", "completed_at": "2026-10-03T18:02:25Z",
}]}
ARTIFACT = {
    "id": 11280422474, "name": "roma.just.talk.app", "expired": False,
    "size_in_bytes": 31006819,
    "digest": "sha256:dbc4670ff49d5632294ff89d2b86e76759db84ac0e0d34ec5940e36cb1af9be4",
    "workflow_run": {"id": 37140159415, "head_sha": SOURCE},
    "created_at": "2026-10-03T17:42:21Z",
}
ADHOC_SIGNATURE = """Identifier=com.negentropi.RomaJustTalk
CodeDirectory v=20500 size=193052 flags=0x10002(adhoc,runtime) hashes=6022+7 location=embedded
Signature=adhoc
TeamIdentifier=not set
"""
FAILED_LAUNCH = "launch_verdict=failed\nfailure=launched process did not finish AppKit launch\n"


class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="roma-qualification-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("run.json", RUN)
        self.write("jobs.json", JOBS)
        self.write("artifact.json", ARTIFACT)
        info = plistlib.dumps({"CFBundleIdentifier": "com.negentropi.RomaJustTalk", "CFBundleExecutable": "roma just talk", "LSMinimumSystemVersion": "14.2.1"})
        with zipfile.ZipFile(self.root / "final.zip", "w") as archive:
            archive.writestr("roma just talk.app/Contents/Info.plist", info)
            archive.writestr("roma just talk.app/Contents/MacOS/roma just talk", b"unsigned byte-container fixture, not an app launch")
        with zipfile.ZipFile(self.root / "transport.zip", "w") as archive:
            archive.write(self.root / "final.zip", "roma.just.talk.app.zip")
        self.inputs = {
            "schemaVersion": 1,
            "sourceBuild": self.origin(),
            "qualification": {**self.origin(), "toolingSha": SOURCE, "jobId": 111252888702},
            "finalArchive": {**self.origin(), "sourceSha": SOURCE, "jobId": 111252888702,
                             "path": "final.zip", "size": (self.root / "final.zip").stat().st_size,
                             "sha256": hashlib.sha256((self.root / "final.zip").read_bytes()).hexdigest()},
            "rows": [],
        }

    def origin(self):
        return {"runId": 37140159415, "runAttempt": 1, "artifactId": 11280422474,
                "runMetadata": "run.json", "jobsMetadata": "jobs.json",
                "artifactMetadata": "artifact.json", "transportArchive": "transport.zip"}

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value) if isinstance(value, dict) else value)

    def invoke(self, raw=None, live=False, environment=None):
        self.write("input.json", self.inputs)
        if raw is not None:
            self.write("input.json", raw)
        command = [sys.executable, str(SCRIPT), str(self.root / "input.json"),
                   "--expected-source-sha", SOURCE, "--expected-tooling-sha", SOURCE,
                   "--developer-id-team", "ABCDE12345"]
        if not live:
            command.append("--offline-preview")
        result = subprocess.run(command, capture_output=True, text=True, timeout=15, env=environment)
        self.assertEqual(result.returncode, 1, result.stderr)
        output = json.loads(result.stdout)
        self.assertIs(output["publicationEligible"], False)
        return output

    def codes(self, **options):
        return {item["code"] for item in self.invoke(**options)["rejections"]}

    def test_actual_completed_build_does_not_qualify_publication(self):
        output = self.invoke()
        source_errors = [item for item in output["rejections"] if item["scope"] == "sourceBuild"]
        self.assertEqual([item["code"] for item in source_errors], ["TRANSPORT_DIGEST_MISMATCH"])
        self.assertEqual(output["preview"]["sourceBuild"]["runId"], 37140159415)
        self.assertIn("API_ORIGIN_UNVERIFIED", self.codes())
        self.assertIn("CONTROLLER_ORIGIN_UNVERIFIED", self.codes())

    def test_uploaded_pass_flags_and_marker_cannot_authenticate_cua(self):
        self.inputs["passed"] = True
        self.inputs["controller"] = {"authenticated": True, "passed": True, "origin": "cua", "marker": "ready.txt"}
        self.write("ready.txt", "2026-10-03T17:50:50Z\n")
        self.assertIn("CONTROLLER_ORIGIN_UNVERIFIED", self.codes())

    def test_wrong_bytes_and_authenticated_transport_content_are_distinct(self):
        with (self.root / "final.zip").open("ab") as stream:
            stream.write(b"changed after qualification")
        self.assertIn("FINAL_BYTES_MISMATCH", self.codes())
        self.inputs["finalArchive"]["sha256"] = hashlib.sha256((self.root / "final.zip").read_bytes()).hexdigest()
        self.inputs["finalArchive"]["size"] = (self.root / "final.zip").stat().st_size
        self.assertIn("FINAL_TRANSPORT_CONTENT_MISMATCH", self.codes())

    def test_incomplete_failed_and_wrong_attempt_source_runs(self):
        for status, conclusion in [("in_progress", None), ("completed", "failure"), ("completed", "cancelled")]:
            with self.subTest(status=status, conclusion=conclusion):
                self.write("run.json", {**RUN, "status": status, "conclusion": conclusion})
                self.assertIn("RUN_NOT_SUCCESSFUL", self.codes())
        self.write("run.json", {**RUN, "run_attempt": 2})
        self.assertIn("RUN_IDENTITY_MISMATCH", self.codes())

    def test_wrong_source_workflow_fork_and_unexpected_policy(self):
        for changes in [{"head_sha": "0" * 40}, {"path": ".github/workflows/other.yml"}, {"event": "pull_request"}, {"head_repository": {"full_name": "fork/roma-just-talk"}}]:
            with self.subTest(changes=changes):
                self.write("run.json", {**RUN, **changes})
                self.assertIn("RUN_IDENTITY_MISMATCH", self.codes())
        self.inputs["qualification"]["toolingSha"] = "0" * 40
        self.assertIn("TOOLING_SHA_MISMATCH", self.codes())

    def test_missing_exact_os_and_duplicate_or_unknown_rows(self):
        self.inputs["rows"] = [{"name": "sonoma", "evidenceDirectory": "row", "jobId": 111252888702}]
        rejected = self.invoke()["rejections"]
        self.assertTrue(any(item["code"] == "REQUIRED_OS_ROW_MISSING" and item["scope"] == "rows.tahoe" for item in rejected))
        self.inputs["rows"] *= 2
        self.assertIn("REQUIRED_OS_ROW_MISSING", self.codes())
        self.inputs["rows"] = [{"name": "sonoma-14.4"}]
        self.assertIn("ROWS_INVALID", self.codes())

    def write_failed_adhoc_row(self):
        prefix = "row/macos-distribution-e2e/"
        self.write(prefix + "runner-identity.txt", "ProductVersion:\t14.2.1\nBuildVersion:\t23C71\narchitecture=arm64\n")
        self.write(prefix + "gatekeeper-status.txt", "assessments enabled\n")
        self.write(prefix + "sip-status.txt", "System Integrity Protection status: enabled.\n")
        self.write(prefix + "launch-verification/distribution-launch-verdict.txt", FAILED_LAUNCH)
        self.write(prefix + "source-artifact.txt", "launch_contract=adhoc-approval\n")
        self.write(prefix + "browser-downloaded-artifact.txt", "downloaded_sha256=unqualified\n")
        self.write(prefix + "downloaded-archive-quarantine.txt", "0083;68df93ad;Safari;recorded\n")
        self.write(prefix + "reference-trust/signature.txt", ADHOC_SIGNATURE)
        self.inputs["rows"] = [{"name": "sonoma", "evidenceDirectory": "row", "jobId": 111252888702}]

    def test_actual_adhoc_signature_and_failed_first_process_reject(self):
        self.write_failed_adhoc_row()
        codes = self.codes()
        self.assertIn("FIRST_LAUNCH_FAILED", codes)
        self.assertIn("SIGNER_MISMATCH", codes)
        self.assertIn("ROW_DOWNLOAD_MISMATCH", codes)

    def bind_failed_qualification_archive(self):
        self.write_failed_adhoc_row()
        producer = {**RUN, "id": 42, "path": ".github/workflows/qualify-macos-distribution.yml"}
        jobs = {"total_count": 3, "jobs": []}
        for job_id, name in [(51, "Collect macOS qualification evidence"), (52, "Finalize notarized macOS app"), (53, "Qualify Sonoma 14.2.1 (23C71)")]:
            jobs["jobs"].append({**JOBS["jobs"][0], "id": job_id, "run_id": 42, "name": name})
        self.write("producer-run.json", producer)
        self.write("producer-jobs.json", jobs)
        self.inputs["qualification"].update(runId=42, artifactId=61, jobId=51, runMetadata="producer-run.json", jobsMetadata="producer-jobs.json", artifactMetadata="qualification-artifact.json", transportArchive="qualification.zip")
        self.inputs["finalArchive"].update(runId=42, artifactId=62, jobId=52, artifactMetadata="final-artifact.json")
        self.inputs["rows"][0]["jobId"] = 53
        producer_inputs = {
            "sourceBuild": {"runId": RUN["id"], "runAttempt": 1, "artifactId": ARTIFACT["id"], "sourceSha": SOURCE},
            "qualification": {"runId": 42, "runAttempt": 1, "toolingSha": SOURCE},
            "finalArchive": {key: self.inputs["finalArchive"][key] for key in ("artifactId", "sourceSha", "sha256", "size")},
            "developerIdTeam": "ABCDE12345", "rows": self.inputs["rows"],
        }
        with zipfile.ZipFile(self.root / "qualification.zip", "w") as archive:
            archive.writestr("qualification-inputs.json", json.dumps(producer_inputs))
            for path in sorted((self.root / "row").rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(self.root).as_posix())
        for artifact_id, name, transport, metadata in [(61, "roma.macos.release-qualification", "qualification.zip", "qualification-artifact.json"), (62, "roma.macos.final-archive", "transport.zip", "final-artifact.json")]:
            path = self.root / transport
            self.write(metadata, {**ARTIFACT, "id": artifact_id, "name": name,
                                  "workflow_run": {"id": 42, "head_sha": SOURCE},
                                  "size_in_bytes": path.stat().st_size,
                                  "digest": "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()})

    def test_local_raw_receipt_must_match_qualification_archive(self):
        self.bind_failed_qualification_archive()
        receipt = "row/macos-distribution-e2e/runner-identity.txt"
        output = self.invoke()
        self.assertFalse(any(item["code"] == "RAW_RECEIPT_UNBOUND" and item["scope"] == receipt for item in output["rejections"]))
        self.write(receipt, "ProductVersion:\t14.4\nBuildVersion:\t23E214\narchitecture=arm64\n")
        output = self.invoke()
        self.assertTrue(any(item["code"] == "RAW_RECEIPT_UNBOUND" and item["scope"] == receipt for item in output["rejections"]))
        self.assertIn("CONTROLLER_ORIGIN_UNVERIFIED", {item["code"] for item in output["rejections"]})

    def test_producer_inputs_and_final_attempt_cannot_be_replaced(self):
        self.bind_failed_qualification_archive()
        self.inputs["finalArchive"]["runAttempt"] = 2
        codes = self.codes()
        self.assertIn("FINAL_PRODUCER_MISMATCH", codes)
        self.inputs["finalArchive"]["runAttempt"] = 1
        self.inputs["finalArchive"]["sourceSha"] = "0" * 40
        self.assertIn("QUALIFICATION_INPUTS_UNBOUND", self.codes())

    def test_encrypted_qualification_entry_rejects_at_inventory(self):
        self.bind_failed_qualification_archive()
        path = self.root / "qualification.zip"
        with zipfile.ZipFile(path) as archive:
            entry = archive.getinfo("qualification-inputs.json")
            central_offset = archive.start_dir
        raw = bytearray(path.read_bytes())
        struct.pack_into("<H", raw, entry.header_offset + 6, 1)
        struct.pack_into("<H", raw, central_offset + 8, 1)
        path.write_bytes(raw)
        metadata = json.loads((self.root / "qualification-artifact.json").read_text())
        metadata["digest"] = "sha256:" + hashlib.sha256(raw).hexdigest()
        self.write("qualification-artifact.json", metadata)
        output = self.invoke()
        self.assertTrue(any(item["scope"] == "qualification" and item["detail"] == "qualification ZIP contains encrypted entry or symlink" for item in output["rejections"]))

    def test_duplicate_json_keys_and_path_escape_reject(self):
        self.assertIn("INPUT_INVALID", self.codes(raw='{"schemaVersion":1,"schemaVersion":1}'))
        self.inputs["sourceBuild"]["runMetadata"] = "../run.json"
        output = self.invoke()
        self.assertTrue(any(item["scope"] == "sourceBuild" and item["detail"] == "evidence path escapes root" for item in output["rejections"]))

    def test_duplicate_job_and_wrong_artifact_origin_reject(self):
        duplicate = copy.deepcopy(JOBS)
        duplicate["jobs"] *= 2
        duplicate["total_count"] = 2
        self.write("jobs.json", duplicate)
        self.assertIn("JOB_MISSING_OR_DUPLICATE", self.codes())
        self.write("artifact.json", {**ARTIFACT, "workflow_run": {"id": 1, "head_sha": SOURCE}})
        self.assertIn("ARTIFACT_IDENTITY_MISMATCH", self.codes())

    def test_artifact_from_another_attempt_or_unsupported_runner_reject(self):
        self.write("artifact.json", {**ARTIFACT, "created_at": "2026-10-02T17:42:21Z"})
        self.assertIn("ARTIFACT_ATTEMPT_MISMATCH", self.codes())
        jobs = copy.deepcopy(JOBS)
        jobs["jobs"][0]["labels"] = ["ubuntu-latest"]
        self.write("jobs.json", jobs)
        self.assertIn("BUILD_RUNNER_UNSUPPORTED", self.codes())

    def test_authenticated_api_failure_does_not_fall_back_to_files(self):
        bin_path = self.root / "bin"
        bin_path.mkdir()
        fake_gh = bin_path / "gh"
        fake_gh.write_text("#!/bin/sh\nexit 1\n")
        fake_gh.chmod(0o755)
        environment = dict(os.environ, PATH=str(bin_path) + os.pathsep + os.environ.get("PATH", ""))
        output = self.invoke(live=True, environment=environment)
        self.assertTrue(any(item["scope"] == "sourceBuild" and item["detail"] == "authenticated GitHub API read failed" for item in output["rejections"]))
        self.assertNotIn("sourceBuild", output["preview"])

    @unittest.skipUnless(os.environ.get("RJT_QUALIFICATION_RECORDED_EVIDENCE"), "actual task evidence path not supplied")
    def test_actual_current_app_archives_remain_unqualified(self):
        proof = Path(os.environ["RJT_QUALIFICATION_RECORDED_EVIDENCE"])
        candidate = proof / "sonoma-14-2-1/candidate-d504e90e"
        completed = proof / "storage-repair-d504e90e"
        shutil.copyfile(completed / "build-run-completed.json", self.root / "run.json")
        shutil.copyfile(completed / "build-jobs-completed.json", self.root / "jobs.json")
        shutil.copyfile(candidate / "candidate-actions.zip", self.root / "transport.zip")
        shutil.copyfile(candidate / "roma.just.talk.app.zip", self.root / "final.zip")
        self.inputs["finalArchive"]["sha256"] = hashlib.sha256((self.root / "final.zip").read_bytes()).hexdigest()
        self.inputs["finalArchive"]["size"] = (self.root / "final.zip").stat().st_size
        output = self.invoke()
        self.assertFalse(any(item["scope"] == "sourceBuild" for item in output["rejections"]))
        self.assertIn("CONTROLLER_ORIGIN_UNVERIFIED", {item["code"] for item in output["rejections"]})
        self.assertEqual(output["preview"]["finalArchive"]["minimumSystemVersion"], "14.2.1")


if __name__ == "__main__":
    unittest.main()
