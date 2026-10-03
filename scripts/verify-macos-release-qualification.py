#!/usr/bin/env python3
"""Verify publication inputs. Unestablished controller origin prevents publication."""

import argparse
import hashlib
import json
import plistlib
import posixpath
import re
import stat
import subprocess
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path, PurePosixPath

REPOSITORY = "negentropi/roma-just-talk"
QUALIFICATION_WORKFLOW = ".github/workflows/qualify-macos-distribution.yml"
BUNDLE_ID = "com.negentropi.RomaJustTalk"
APP_NAME = "roma just talk.app"
ROWS = {
    "sonoma": ("14.2.1", "23C71", "Qualify Sonoma 14.2.1 (23C71)"),
    "tahoe": ("26.4.1", "25E253", "Qualify Tahoe 26.4.1 (25E253)"),
}
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
SHA1 = re.compile(r"[0-9a-f]{40}\Z")
MAX_RECEIPT = 16 * 1024 * 1024
MAX_APP_BYTES = 2 * 1024 ** 3


class InvalidEvidence(ValueError):
    pass


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InvalidEvidence("duplicate JSON key")
        result[key] = value
    return result


def decode_json(raw):
    value = json.loads(raw, object_pairs_hook=object_pairs)
    if not isinstance(value, dict):
        raise InvalidEvidence("expected JSON object")
    return value


def positive_id(value):
    if type(value) is not int or value <= 0:
        raise InvalidEvidence("expected positive integer ID")
    return value


def digest(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        value.update(block)
    return value.hexdigest()


def key_values(text):
    result = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in result:
            raise InvalidEvidence("duplicate receipt key")
        result[key] = value
    return result


def utc_time(value):
    if not isinstance(value, str) or re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z", value) is None:
        raise InvalidEvidence("expected UTC timestamp")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def archive_name(name, seen):
    parts = PurePosixPath(name)
    normalized = parts.as_posix()
    if not parts.parts or normalized in seen or name.rstrip("/") != normalized or parts.is_absolute() or ".." in parts.parts or "\\" in name or any(ord(char) < 32 for char in name):
        raise InvalidEvidence("unsafe or duplicate ZIP entry")
    seen.add(normalized)
    return parts


class Qualification:
    def __init__(self, root, source_sha, tooling_sha, team, offline=False):
        self.root = root.resolve(strict=True)
        self.source_sha = source_sha
        self.tooling_sha = tooling_sha
        self.team = team
        self.offline = offline
        self.problems = []
        self.observed = {}
        self.evidence_archive = None
        self.evidence_members = {}
        self.api_deadline = time.monotonic() + 30

    def reject(self, code, scope, detail):
        self.problems.append({"code": code, "scope": scope, "detail": detail})

    def require(self, predicate, code, scope, detail):
        if not predicate:
            self.reject(code, scope, detail)

    def path(self, reference):
        if not isinstance(reference, str) or not reference or "\\" in reference:
            raise InvalidEvidence("expected relative evidence path")
        parts = PurePosixPath(reference)
        if parts.is_absolute() or ".." in parts.parts:
            raise InvalidEvidence("evidence path escapes root")
        path = self.root / reference
        if not path.resolve(strict=True).is_relative_to(self.root):
            raise InvalidEvidence("evidence symlink escapes root")
        if not path.is_file():
            raise InvalidEvidence("evidence reference is not a file")
        return path

    def text(self, reference):
        path = self.path(reference)
        if path.stat().st_size > MAX_RECEIPT:
            raise InvalidEvidence("receipt exceeds size limit")
        return path.read_text(encoding="utf-8")

    def file_digest(self, reference):
        with self.path(reference).open("rb") as stream:
            return digest(stream)

    def bind_evidence(self, archive_path, inputs):
        with zipfile.ZipFile(archive_path) as archive:
            inventory = archive.infolist()
            if len(inventory) > 20000 or sum(item.file_size for item in inventory) > 512 * 1024 ** 2:
                raise InvalidEvidence("qualification ZIP exceeds evidence capacity")
            seen, members = set(), {}
            for item in inventory:
                parts = archive_name(item.filename, seen)
                if item.flag_bits & 1 or stat.S_ISLNK(item.external_attr >> 16):
                    raise InvalidEvidence("qualification ZIP contains encrypted entry or symlink")
                if not item.is_dir():
                    members[parts.as_posix()] = item.filename
            self.evidence_archive, self.evidence_members = archive_path, members
            manifest = members.get("qualification-inputs.json")
            if manifest is None or archive.getinfo(manifest).file_size > MAX_RECEIPT:
                raise InvalidEvidence("qualification ZIP lacks bounded qualification-inputs.json")
            expected = {
                "sourceBuild": {**{key: inputs["sourceBuild"][key] for key in ("runId", "runAttempt", "artifactId")}, "sourceSha": self.source_sha},
                "finalArchive": {key: inputs["finalArchive"][key] for key in ("artifactId", "sourceSha", "sha256", "size")},
                "qualification": {**{key: inputs["qualification"][key] for key in ("runId", "runAttempt")}, "toolingSha": self.tooling_sha},
                "developerIdTeam": self.team,
                "rows": [{key: row[key] for key in ("name", "jobId", "evidenceDirectory")} for row in inputs["rows"]],
            }
            self.require(decode_json(archive.read(manifest)) == expected,
                         "QUALIFICATION_INPUTS_UNBOUND", "qualification", "requested inputs differ from authenticated producer inputs")

    def evidence_bytes(self, reference):
        path = self.path(reference)
        if path.stat().st_size > MAX_RECEIPT:
            raise InvalidEvidence("raw receipt exceeds size limit")
        raw = path.read_bytes()
        member = self.evidence_members.get(reference)
        if self.evidence_archive is None or member is None:
            self.reject("RAW_RECEIPT_UNBOUND", reference, "raw receipt is absent from qualification artifact")
        else:
            with zipfile.ZipFile(self.evidence_archive) as archive:
                if archive.getinfo(member).file_size > MAX_RECEIPT:
                    raise InvalidEvidence("raw receipt exceeds size limit")
                with archive.open(member) as stream:
                    self.require(digest(stream) == hashlib.sha256(raw).hexdigest(),
                                 "RAW_RECEIPT_UNBOUND", reference, "local raw receipt differs from qualification artifact")
        return raw

    def evidence_text(self, reference):
        return self.evidence_bytes(reference).decode("utf-8")

    def unit(self, scope, operation):
        try:
            operation()
        except (InvalidEvidence, KeyError, TypeError, ValueError, AttributeError, IndexError, OSError, RuntimeError, NotImplementedError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
            self.reject("EVIDENCE_INVALID", scope, str(error) if isinstance(error, InvalidEvidence) else type(error).__name__)

    def api(self, endpoint, recorded=None):
        if self.offline:
            if recorded is None:
                raise InvalidEvidence("offline preview lacks recorded API reference")
            return decode_json(self.text(recorded))
        timeout = min(10, self.api_deadline - time.monotonic())
        if timeout <= 0:
            raise InvalidEvidence("authenticated API read budget exhausted")
        try:
            result = subprocess.run(
                ["gh", "api", "--hostname", "github.com", f"repos/{REPOSITORY}/{endpoint}"],
                capture_output=True, timeout=timeout, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise InvalidEvidence("authenticated GitHub API read unavailable") from error
        if result.returncode or len(result.stdout) > MAX_RECEIPT:
            raise InvalidEvidence("authenticated GitHub API read failed")
        return decode_json(result.stdout)

    def run(self, record, workflow, head, scope):
        run_id, attempt = positive_id(record["runId"]), positive_id(record["runAttempt"])
        run = self.api(f"actions/runs/{run_id}", record.get("runMetadata"))
        valid = (
            run.get("id") == run_id and run.get("run_attempt") == attempt
            and run.get("repository", {}).get("full_name") == REPOSITORY
            and run.get("head_repository", {}).get("full_name") == REPOSITORY
            and run.get("event") in ("push", "workflow_dispatch")
            and run.get("path", "").split("@")[0] == workflow
            and run.get("head_sha") == head
        )
        self.require(valid, "RUN_IDENTITY_MISMATCH", scope, "run, attempt, repository, workflow, event, or expected head differs")
        self.require(run.get("status") == "completed" and run.get("conclusion") == "success",
                     "RUN_NOT_SUCCESSFUL", scope, "whole workflow must be completed and successful")
        jobs = self.api(f"actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100", record.get("jobsMetadata"))
        if not isinstance(jobs.get("jobs"), list) or type(jobs.get("total_count")) is not int or not 0 <= jobs["total_count"] <= 100 or len(jobs["jobs"]) != jobs["total_count"]:
            raise InvalidEvidence("jobs response absent or truncated")
        return run_id, jobs["jobs"]

    def job(self, jobs, run_id, attempt, name, scope, job_id=None):
        matches = [job for job in jobs if isinstance(job, dict) and job.get("name") == name]
        if len(matches) != 1:
            self.reject("JOB_MISSING_OR_DUPLICATE", scope, "expected exactly one required job")
            return
        job = matches[0]
        valid = (
            job.get("run_id") == run_id and job.get("run_attempt") == attempt
            and type(job.get("id")) is int and job["id"] > 0
            and type(job.get("runner_id")) is int and job["runner_id"] > 0
            and isinstance(job.get("runner_name"), str) and bool(job["runner_name"])
            and isinstance(job.get("labels"), list) and bool(job["labels"])
            and all(isinstance(label, str) for label in job["labels"])
            and job.get("status") == "completed" and job.get("conclusion") == "success"
            and (job_id is None or job.get("id") == positive_id(job_id))
        )
        self.require(valid, "JOB_IDENTITY_MISMATCH", scope, "required completed job, attempt, or actual runner differs")
        return job

    def artifact(self, record, run_id, head, name, scope, job):
        artifact_id = positive_id(record["artifactId"])
        artifact = self.api(f"actions/artifacts/{artifact_id}", record.get("artifactMetadata"))
        valid = (
            artifact.get("id") == artifact_id and artifact.get("name") == name
            and artifact.get("expired") is False
            and artifact.get("workflow_run", {}).get("id") == run_id
            and artifact.get("workflow_run", {}).get("head_sha") == head
            and isinstance(artifact.get("digest"), str)
            and artifact["digest"].startswith("sha256:")
            and SHA256.fullmatch(artifact["digest"][7:]) is not None
        )
        self.require(valid, "ARTIFACT_IDENTITY_MISMATCH", scope, "artifact origin, name, expiration, or digest differs")
        archive = self.path(record["transportArchive"])
        with archive.open("rb") as stream:
            actual = digest(stream)
        self.require(artifact.get("digest") == f"sha256:{actual}" and artifact.get("size_in_bytes") == archive.stat().st_size,
                     "TRANSPORT_DIGEST_MISMATCH", scope, "downloaded Actions bytes differ from API digest or size")
        if job is None:
            raise InvalidEvidence("artifact attempt has no authenticated producing job")
        self.require(utc_time(job["started_at"]) <= utc_time(artifact["created_at"]) <= utc_time(job["completed_at"]),
                     "ARTIFACT_ATTEMPT_MISMATCH", scope, "artifact creation falls outside producing job's run attempt")
        return archive

    def final_zip(self, record, transport):
        path = self.path(record["path"])
        expected = record["sha256"]
        if not isinstance(expected, str) or SHA256.fullmatch(expected) is None:
            raise InvalidEvidence("invalid final ZIP digest")
        self.require(self.file_digest(record["path"]) == expected and type(record["size"]) is int and path.stat().st_size == record["size"],
                     "FINAL_BYTES_MISMATCH", "finalArchive", "final direct ZIP digest or size differs")
        with zipfile.ZipFile(transport) as archive:
            members = [item for item in archive.infolist() if item.filename == "roma.just.talk.app.zip"]
            if len(members) != 1:
                raise InvalidEvidence("finalization transport must contain exactly one app ZIP")
            if members[0].file_size > MAX_APP_BYTES:
                raise InvalidEvidence("finalization ZIP exceeds collector capacity")
            if members[0].flag_bits & 1:
                raise InvalidEvidence("finalization ZIP is encrypted")
            with archive.open(members[0]) as stream:
                inner = digest(stream)
            self.require(inner == expected and members[0].file_size == record["size"],
                         "FINAL_TRANSPORT_CONTENT_MISMATCH", "finalArchive", "final ZIP is not the authenticated artifact's inner ZIP")
        directories, files, links = {}, {}, {}
        with zipfile.ZipFile(path) as archive:
            inventory = archive.infolist()
            if len(inventory) > 20000 or sum(item.file_size for item in inventory) > MAX_APP_BYTES:
                raise InvalidEvidence("final ZIP exceeds collector capacity")
            names = set()
            for item in inventory:
                name = item.filename
                parts = archive_name(name, names)
                if item.flag_bits & 1:
                    raise InvalidEvidence("final ZIP contains encrypted entry")
                if parts.parts[0] == "__MACOSX":
                    continue
                if parts.parts[0] != APP_NAME:
                    raise InvalidEvidence("final ZIP must directly contain only the expected app")
                relative = "/".join(parts.parts[1:]) or "."
                mode = item.external_attr >> 16
                if item.is_dir():
                    directories[relative] = stat.S_IMODE(mode)
                elif stat.S_ISLNK(mode):
                    target = archive.read(item).decode("utf-8")
                    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(relative), target))
                    if target.startswith("/") or resolved == ".." or resolved.startswith("../") or any(ord(char) < 32 for char in target):
                        raise InvalidEvidence("final ZIP symlink escapes app")
                    links[relative] = target
                else:
                    with archive.open(item) as stream:
                        files[relative] = (digest(stream), stat.S_IMODE(mode))
            info_name = f"{APP_NAME}/Contents/Info.plist"
            info_entry = archive.getinfo(info_name)
            if info_entry.file_size > 1024 ** 2:
                raise InvalidEvidence("Info.plist exceeds size limit")
            info = plistlib.loads(archive.read(info_entry))
        if info.get("CFBundleIdentifier") != BUNDLE_ID:
            raise InvalidEvidence("final ZIP bundle identifier differs")
        executable = "Contents/MacOS/" + info["CFBundleExecutable"]
        if executable not in files:
            raise InvalidEvidence("final app executable missing")
        manifest = "".join(f"directory  mode={mode:o}  {name}\n" for name, mode in sorted(directories.items()))
        manifest += "".join(f"{value}  mode={mode:o}  {name}\n" for name, (value, mode) in sorted(files.items()))
        manifest += "".join(f"symlink  {name} -> {target}\n" for name, target in sorted(links.items()))
        self.observed["finalArchive"] = {"sha256": expected, "size": path.stat().st_size, "minimumSystemVersion": info.get("LSMinimumSystemVersion")}
        return manifest, files[executable][0]

    def trust_commands(self, prefix, trust, scope, job):
        directory = prefix + trust + "/"
        receipt = decode_json(self.evidence_text(directory + "trust-command-receipts.json"))
        if set(receipt) != {"schemaVersion", "app", "developerIdTeam", "signingIdentifier", "commands"}:
            raise InvalidEvidence("unexpected trust command receipt fields")
        app = receipt["app"]
        executables = [line.partition("=")[2] for line in self.evidence_text(directory + "signature.txt").splitlines() if line.startswith("Executable=")]
        if len(executables) != 1:
            raise InvalidEvidence("expected exactly one signature Executable line")
        if not isinstance(app, str) or not app.startswith("/") or posixpath.normpath(app) != app or not app.endswith("/" + APP_NAME):
            raise InvalidEvidence("expected canonical absolute trust app path")
        if trust == "reference-trust":
            self.require(app.endswith("/macos-distribution-e2e/expected-inner-reference/" + APP_NAME),
                         "TRUST_APP_MISMATCH", scope, "reference commands must target the extracted final ZIP reference")
        else:
            extracted = key_values(self.evidence_text(prefix + "extracted-app-identity.txt"))
            launch = key_values(self.evidence_text(prefix + "launch-verification/launch-identity.txt"))
            self.require(app == extracted.get("app") == launch.get("source_app"),
                         "TRUST_APP_MISMATCH", scope, "trust commands must target the same Finder-extracted source app")
        self.require(executables[0].startswith(app + "/Contents/MacOS/"),
                     "TRUST_APP_MISMATCH", scope, "signature display must identify the command's app executable")
        self.require(type(receipt["schemaVersion"]) is int and receipt["schemaVersion"] == 1
                     and receipt["developerIdTeam"] == self.team and receipt["signingIdentifier"] == BUNDLE_ID,
                     "TRUST_POLICY_MISMATCH", scope, "trust receipts must use the expected team and identifier")
        requirement = ('=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
                       'and certificate 1[field.1.2.840.113635.100.6.2.6] exists '
                       f'and certificate leaf[subject.OU] = "{self.team}" and identifier "{BUNDLE_ID}"')
        expected = [
            ("codesign-verify", "developer-id-verification", ["codesign", "--verify", "--deep", "--strict", "--test-requirement=" + requirement, app]),
            ("codesign-display", "signature", ["codesign", "--display", "--verbose=4", app]),
            ("stapler-validate", "stapled-ticket", ["xcrun", "stapler", "validate", app]),
            ("gatekeeper-assess", "gatekeeper-assessment", ["spctl", "--assess", "--type", "execute", "--verbose=4", app]),
        ]
        commands = receipt["commands"]
        if not isinstance(commands, list) or len(commands) != len(expected):
            raise InvalidEvidence("expected exactly four trust command receipts")
        if job is None:
            raise InvalidEvidence("trust commands lack authenticated OS job window")
        job_start, job_end = utc_time(job["started_at"]), utc_time(job["completed_at"])
        launch_start = utc_time(self.evidence_text(prefix + "approval-window-started-at.txt").strip())
        launch_end = utc_time(self.evidence_text(prefix + "approval-window-ended-at.txt").strip())
        previous_end = job_start
        for command, (name, output_name, argv) in zip(commands, expected):
            if not isinstance(command, dict) or set(command) != {"name", "argv", "exitStatus", "startedAt", "endedAt", "timedOut", "stdout", "stderr"}:
                raise InvalidEvidence("unexpected trust command fields")
            self.require(command["name"] == name and command["argv"] == argv,
                         "TRUST_COMMAND_MISMATCH", scope, "exact ordered trust commands, flags, and app required")
            self.require(type(command["exitStatus"]) is int and command["exitStatus"] == 0 and command["timedOut"] is False,
                         "TRUST_COMMAND_FAILED", scope, "each actual trust command must exit zero without timeout")
            start, end = utc_time(command["startedAt"]), utc_time(command["endedAt"])
            self.require(previous_end <= start <= end <= job_end and (end - start).total_seconds() <= 120
                         and (start >= launch_end if trust == "extracted-trust-after" else end <= launch_start),
                         "TRUST_COMMAND_WINDOW_INVALID", scope, "ordered bounded trust commands must fall inside the OS job and their launch phase")
            previous_end = end
            raw = []
            for channel in ("stdout", "stderr"):
                record = command[channel]
                if not isinstance(record, dict) or set(record) != {"path", "sha256", "size"}:
                    raise InvalidEvidence("unexpected trust command output fields")
                expected_path = output_name + "." + channel
                self.require(record["path"] == expected_path, "TRUST_OUTPUT_PATH_MISMATCH", scope, "fixed raw command output path required")
                data = self.evidence_bytes(directory + expected_path)
                self.require(type(record["size"]) is int and record["size"] == len(data)
                             and isinstance(record["sha256"], str) and SHA256.fullmatch(record["sha256"]) is not None
                             and record["sha256"] == hashlib.sha256(data).hexdigest(),
                             "TRUST_OUTPUT_MISMATCH", scope, "raw output bytes must match the command receipt's size and hash")
                raw.append(data)
            self.require(b"".join(raw) == self.evidence_bytes(directory + output_name + ".txt"),
                         "TRUST_OUTPUT_MISMATCH", scope, "legacy text must contain the recorded stdout followed by stderr")

    def row(self, row, jobs, run_id, attempt, final_record, manifest, executable_sha):
        name = row["name"]
        version, build, job_name = ROWS[name]
        scope = f"rows.{name}"
        job = self.job(jobs, run_id, attempt, job_name, scope, row["jobId"])
        prefix = row["evidenceDirectory"].rstrip("/") + "/macos-distribution-e2e/"
        read = lambda relative: self.evidence_text(prefix + relative)
        values = lambda relative: key_values(read(relative))
        identity = read("runner-identity.txt")
        self.require(re.search(rf"^ProductVersion:\s+{re.escape(version)}\s*$", identity, re.M) is not None
                     and re.search(rf"^BuildVersion:\s+{build}\s*$", identity, re.M) is not None
                     and re.search(r"^architecture=arm64$", identity, re.M) is not None,
                     "OS_ROW_MISMATCH", scope, "exact product version, build, and architecture required")
        self.require("assessments enabled" in read("gatekeeper-status.txt") and read("sip-status.txt").strip() == "System Integrity Protection status: enabled.",
                     "PROTECTIONS_NOT_ENABLED", scope, "Gatekeeper and SIP must be enabled")
        verdict = values("launch-verification/distribution-launch-verdict.txt")
        self.require(verdict.get("launch_verdict") != "failed", "FIRST_LAUNCH_FAILED", scope, "recorded first-process verifier failed")
        source = values("source-artifact.txt")
        downloaded = values("browser-downloaded-artifact.txt")
        self.require(source.get("launch_contract") == "notarized-first-open"
                     and source.get("expected_inner_archive_sha256") == final_record["sha256"]
                     and source.get("browser_expected_sha256") == final_record["sha256"]
                     and downloaded.get("downloaded_sha256") == final_record["sha256"]
                     and downloaded.get("downloaded_size") == str(final_record["size"]),
                     "ROW_DOWNLOAD_MISMATCH", scope, "row must browser-download the exact final direct ZIP")
        transport_sha = self.file_digest(final_record["transportArchive"])
        self.require(source.get("github_artifact_run_id") == str(final_record["runId"])
                     and source.get("github_artifact_id") == str(final_record["artifactId"])
                     and source.get("github_artifact_digest") == "sha256:" + transport_sha
                     and source.get("github_actions_archive_sha256") == transport_sha,
                     "ROW_ARTIFACT_MISMATCH", scope, "row source must be the exact finalization artifact")
        quarantine = read("downloaded-archive-quarantine.txt").strip().split(";")
        self.require(len(quarantine) >= 3 and quarantine[2] == "Safari", "QUARANTINE_MISSING", scope, "Safari archive quarantine required")
        for trust in ("reference-trust", "extracted-trust-before", "extracted-trust-after"):
            signature = read(f"{trust}/signature.txt")
            self.require("Signature=adhoc" not in signature and f"TeamIdentifier={self.team}" in signature.splitlines()
                         and f"Identifier={BUNDLE_ID}" in signature.splitlines()
                         and re.search(r"^CodeDirectory .*flags=.*\(.*runtime.*\)", signature, re.M) is not None,
                         "SIGNER_MISMATCH", scope, "expected Developer ID team, identifier, and runtime signature required")
            read(f"{trust}/developer-id-verification.txt")
            self.require("The validate action worked!" in read(f"{trust}/stapled-ticket.txt"), "STAPLED_TICKET_MISSING", scope, "actual stapler success output required")
            assessment = read(f"{trust}/gatekeeper-assessment.txt")
            self.require("source=Notarized Developer ID" in assessment.splitlines() and re.search(r"^override=", assessment, re.M) is None,
                         "TRUST_ASSESSMENT_REJECTED", scope, "notarized assessment without override required")
            self.unit(scope + "." + trust, lambda trust=trust: self.trust_commands(prefix, trust, scope + "." + trust, job))
        for relative in ("expected-inner-app-files.sha256", "extracted-app-files-before-gatekeeper.sha256", "extracted-app-files-after-gatekeeper.sha256",
                         "launch-verification/source-bundle-files.sha256", "launch-verification/process-bundle-files.sha256"):
            self.require(read(relative) == manifest, "BUNDLE_MANIFEST_MISMATCH", scope, "recorded full bundle differs from final ZIP")
        launch = values("launch-verification/launch-identity.txt")
        pid = read("launched-pid.txt").strip()
        self.require(pid.isdecimal() and int(pid) > 0 and launch.get("pid") == pid and verdict.get("pid") == pid
                     and launch.get("bundle_identifier") == BUNDLE_ID
                     and launch.get("source_executable_sha256") == executable_sha
                     and launch.get("process_executable_sha256") == executable_sha,
                     "FIRST_PROCESS_MISMATCH", scope, "same first PID and final executable required")
        app_quarantine = read("launch-verification/source-app-quarantine.txt").strip().split(";")
        self.require(len(app_quarantine) >= 3 and app_quarantine[2] == "Safari", "QUARANTINE_MISSING", scope, "Safari app quarantine required")
        self.require(verdict.get("launch_verdict") == "passed" and verdict.get("product_version") == version
                     and verdict.get("build_version") == build and verdict.get("active_architecture") == "arm64"
                     and verdict.get("stability_seconds", "").isdecimal() and int(verdict["stability_seconds"]) >= 60,
                     "FIRST_LAUNCH_NOT_PROVED", scope, "raw first-process proof must cover at least 60 seconds")
        start = utc_time(read("approval-window-started-at.txt").strip())
        end = utc_time(read("approval-window-ended-at.txt").strip())
        self.require((end - start).total_seconds() >= 60,
                     "GUEST_WINDOW_INVALID", scope, "bounded guest observation window must cover stability")
        self.require(not read("approval-window-new-crash-reports.txt").strip(), "LAUNCH_CRASH_RECORDED", scope, "first Open produced a crash")
        self.require(values("launch-verification/appkit-running-application.txt").get("is_finished_launching") == "true",
                     "APPKIT_NOT_READY", scope, "first process must finish AppKit launch")
        self.require(read("approval-window-distinct-pids.txt").strip() == pid, "FIRST_PROCESS_MISMATCH", scope, "one first process required")
        expected = set(read("launch-verification/expected-bundle-code.txt").splitlines())
        observed = set(read("launch-verification/observed-bundle-code.txt").splitlines())
        self.require(bool(expected) and expected <= observed, "MAPPED_CODE_MISSING", scope, "all expected bundled dependencies must be mapped")
        read("launch-verification/mapped-code-signatures.txt")
        self.require(re.search(r"Library not loaded|code signature .*not valid for use in process|Namespace DYLD|DYLD, Code 1", read("approval-window-unified-log.txt"), re.I) is None,
                     "DYLD_FAILURE_RECORDED", scope, "launch window contains a DYLD signature failure")
        for relative in ("launch-verification/process-open-files.txt", "launch-verification/process-open-files-after-stability.txt"):
            self.require("n" + launch.get("process_executable", "") in read(relative).splitlines(), "EXECUTABLE_MAPPING_MISSING", scope, "first executable mapping missing")
        chain = key_values(self.evidence_text(row["evidenceDirectory"].rstrip("/") + "/runtime-chain-verdict.txt"))
        manifest_sha = hashlib.sha256(manifest.encode("utf-8")).hexdigest()
        self.require(chain.get("runtime_transcription_verdict") == "passed" and chain.get("runtime_first_launch_pid") == pid
                     and chain.get("runtime_executable_sha256") == executable_sha
                     and chain.get("distribution_executable_sha256") == executable_sha
                     and all(chain.get(key) == manifest_sha for key in ("distribution_bundle_manifest_sha256", "runtime_bundle_before_sha256", "runtime_bundle_after_sha256")),
                     "RUNTIME_CHAIN_MISSING", scope, "same-artifact runtime smoke binding required")

    def verify(self, inputs):
        self.require(type(inputs.get("schemaVersion")) is int and inputs["schemaVersion"] == 1, "SCHEMA_UNSUPPORTED", "input", "schemaVersion must be integer 1")
        if self.offline:
            self.reject("API_ORIGIN_UNVERIFIED", "origin", "recorded JSON supports preview only; no live API authentication")
        self.reject("CONTROLLER_ORIGIN_UNVERIFIED", "controller", "no authenticated native CUA export adapter is established; uploaded assertions or readiness markers cannot authorize publication")
        def source():
            record = inputs["sourceBuild"]
            run_id, jobs = self.run(record, ".github/workflows/voiceink-build.yml", self.source_sha, "sourceBuild")
            job = self.job(jobs, run_id, record["runAttempt"], "Build release macOS app", "sourceBuild")
            selected = subprocess.run(
                ["jq", "-e", "-L", str(Path(__file__).resolve().parent), "--argjson", "run_id", str(run_id),
                 '--arg', 'job_name', 'Build release macOS app', 'include "macos-build-job"; select_macos_build_job($run_id; $job_name)'],
                input=json.dumps({"jobs": jobs}), capture_output=True, text=True, timeout=5, check=False,
            )
            self.require(selected.returncode == 0, "BUILD_RUNNER_UNSUPPORTED", "sourceBuild", "source job must pass the existing shared macOS build provider predicate")
            self.artifact(record, run_id, self.source_sha, "roma.just.talk.app", "sourceBuild", job)
            self.observed["sourceBuild"] = {"runId": run_id, "runAttempt": record["runAttempt"], "sourceSha": self.source_sha}
        self.unit("sourceBuild", source)
        qualification_jobs = []
        def qualification():
            record = inputs["qualification"]
            head = self.tooling_sha
            self.require(record.get("toolingSha") == head, "TOOLING_SHA_MISMATCH", "qualification", "input cannot choose qualification policy source")
            run_id, jobs = self.run(record, QUALIFICATION_WORKFLOW, head, "qualification")
            qualification_jobs.extend(jobs)
            job = self.job(jobs, run_id, record["runAttempt"], "Collect macOS qualification evidence", "qualification", record["jobId"])
            archive = self.artifact(record, run_id, head, "roma.macos.release-qualification", "qualification", job)
            self.bind_evidence(archive, inputs)
        self.unit("qualification", qualification)
        final = []
        def archive():
            record, producer = inputs["finalArchive"], inputs["qualification"]
            final.extend(self.final_zip(record, self.path(record["transportArchive"])))
            self.require(record["runId"] == producer["runId"] and record["runAttempt"] == producer["runAttempt"],
                         "FINAL_PRODUCER_MISMATCH", "finalArchive", "final ZIP and qualification must share the exact producer run attempt")
            self.require(record.get("sourceSha") == self.source_sha, "FINAL_SOURCE_MISMATCH", "finalArchive", "finalizer application source differs")
            job = self.job(qualification_jobs, producer["runId"], producer["runAttempt"], "Finalize notarized macOS app", "finalArchive", record["jobId"])
            self.artifact(record, producer["runId"], self.tooling_sha, "roma.macos.final-archive", "finalArchive", job)
        self.unit("finalArchive", archive)
        rows = inputs.get("rows")
        if not isinstance(rows, list) or len(rows) > len(ROWS):
            self.reject("ROWS_INVALID", "rows", "exact supported matrix required")
            rows = []
        for name in ROWS:
            matches = [row for row in rows if isinstance(row, dict) and row.get("name") == name]
            if len(matches) != 1:
                self.reject("REQUIRED_OS_ROW_MISSING", f"rows.{name}", "exactly one required OS row must be present")
            elif len(final) == 2:
                self.unit(f"rows.{name}", lambda row=matches[0]: self.row(row, qualification_jobs, inputs["qualification"]["runId"], inputs["qualification"]["runAttempt"], inputs["finalArchive"], *final))
        if any(not isinstance(row, dict) or row.get("name") not in ROWS for row in rows):
            self.reject("ROWS_INVALID", "rows", "unknown row cannot substitute for required OS")
        return {
            "schemaVersion": 1, "publicationEligible": False,
            "preview": {"repository": REPOSITORY, "sourceSha": self.source_sha, "toolingSha": self.tooling_sha, "developerIdTeam": self.team,
                        "requiredRows": [{"name": name, "productVersion": values[0], "buildVersion": values[1], "architecture": "arm64"} for name, values in ROWS.items()],
                        **self.observed},
            "rejections": self.problems,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--expected-tooling-sha", required=True)
    parser.add_argument("--developer-id-team", required=True)
    parser.add_argument("--offline-preview", action="store_true")
    args = parser.parse_args()
    if SHA1.fullmatch(args.expected_source_sha) is None or SHA1.fullmatch(args.expected_tooling_sha) is None or re.fullmatch(r"[A-Z0-9]{10}", args.developer_id_team) is None:
        parser.error("expected exact source SHA and ten-character Developer ID team")
    try:
        checker = Qualification(args.evidence_root or args.manifest.parent, args.expected_source_sha, args.expected_tooling_sha, args.developer_id_team, args.offline_preview)
        reference = str(args.manifest.resolve().relative_to(checker.root))
        inputs = decode_json(checker.text(reference))
        result = checker.verify(inputs)
    except (InvalidEvidence, OSError, ValueError) as error:
        result = {"schemaVersion": 1, "publicationEligible": False, "rejections": [{"code": "INPUT_INVALID", "scope": "input", "detail": str(error) if isinstance(error, InvalidEvidence) else type(error).__name__}]}
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
