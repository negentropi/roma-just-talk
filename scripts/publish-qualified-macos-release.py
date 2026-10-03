#!/usr/bin/env python3
"""Publish an existing draft only after verifying its exact macOS distribution bytes."""

import argparse
import importlib.util
import json
import os
import plistlib
import re
import subprocess
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.parse import quote

SCRIPTS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("qualification", SCRIPTS / "verify-macos-release-qualification.py")
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)
REPOSITORY = qualification.REPOSITORY
APP_ARCHIVE = "roma.just.talk.app.zip"
QUALIFICATION_ARTIFACT = "roma.macos.release-qualification"
RESERVED = "_consumer"
MAX_TRANSPORT = qualification.MAX_APP_BYTES


class PublicationBlocked(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise PublicationBlocked(message)


def positive_id(value):
    require(type(value) is int and value > 0, "expected positive integer ID")
    return value


def sha256(path):
    with path.open("rb") as stream:
        return qualification.digest(stream)


class GitHub:
    def run(self, arguments, output=None, timeout=30):
        try:
            result = subprocess.run(["gh", *arguments], stdout=output or subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise PublicationBlocked("GitHub transport unavailable") from error
        require(result.returncode == 0, "GitHub transport failed")
        return result.stdout

    def api(self, endpoint):
        raw = self.run(["api", "--hostname", "github.com", f"repos/{REPOSITORY}/{endpoint}"])
        require(len(raw) <= qualification.MAX_RECEIPT, "API response exceeds receipt limit")
        return qualification.decode_json(raw)

    def download(self, endpoint, path, expected_sha, expected_size):
        require(qualification.SHA256.fullmatch(expected_sha or "") is not None,
                "download lacks an exact SHA-256")
        require(type(expected_size) is int and 0 < expected_size <= MAX_TRANSPORT,
                "download size is absent or exceeds capacity")
        with path.open("xb") as stream:
            os.chmod(path, 0o600)
            self.run(["api", "--hostname", "github.com", f"repos/{REPOSITORY}/{endpoint}",
                      "-H", "Accept: application/octet-stream"], stream, timeout=120)
        require(path.stat().st_size == expected_size and sha256(path) == expected_sha,
                "download bytes differ from the qualified digest or API artifact digest")

    def artifact(self, artifact_id, path):
        artifact_id = positive_id(artifact_id)
        metadata = self.api(f"actions/artifacts/{artifact_id}")
        require(metadata.get("id") == artifact_id and metadata.get("expired") is False,
                "artifact identity or expiration differs")
        digest = metadata.get("digest", "")
        require(isinstance(digest, str) and digest.startswith("sha256:"), "artifact lacks API digest")
        self.download(f"actions/artifacts/{artifact_id}/zip", path, digest[7:], metadata.get("size_in_bytes"))
        return metadata


def tag_commit(client, tag):
    reference = client.api("git/ref/tags/" + quote(tag, safe=""))
    require(reference.get("ref") == "refs/tags/" + tag, "release tag reference differs")
    object_ = reference["object"]
    for _ in range(8):
        require(qualification.SHA1.fullmatch(object_.get("sha", "")) is not None, "tag object SHA is invalid")
        if object_.get("type") == "commit":
            return object_["sha"]
        require(object_.get("type") == "tag", "release tag does not identify a commit")
        object_ = client.api("git/tags/" + object_["sha"])["object"]
    raise PublicationBlocked("annotated tag chain exceeds limit")


def release_version(tag):
    require(isinstance(tag, str) and re.fullmatch(r"v?\d+\.\d+(?:\.\d+)?", tag) is not None,
            "unsupported release tag")
    result = subprocess.run(["node", "-e", "const v=require(process.argv[1]).releaseVersion(process.argv[2]);"
                             "if(!v)process.exit(1);process.stdout.write(JSON.stringify(v));",
                             str(SCRIPTS / "generate-github-release-appcast.js"), tag],
                            capture_output=True, timeout=5, check=False)
    require(result.returncode == 0, "unsupported release version")
    return qualification.decode_json(result.stdout)


def read_draft(client, release_id, source_sha):
    release = client.api(f"releases/{positive_id(release_id)}")
    require(release.get("id") == release_id and release.get("draft") is True
            and release.get("prerelease") is False and release.get("published_at") is None,
            "release must remain an unpublished stable draft")
    tag = release.get("tag_name")
    release_version(tag)
    require(tag_commit(client, tag) == source_sha, "release tag differs from the qualified application source")
    assets = release.get("assets")
    require(isinstance(assets, list) and len(assets) <= 2, "unexpected draft asset inventory")
    names = []
    for asset in assets:
        positive_id(asset["id"])
        require(asset.get("state") == "uploaded" and asset.get("name") in (APP_ARCHIVE, "appcast.xml"),
                "unqualified or incomplete asset in draft")
        names.append(asset["name"])
    require(len(names) == len(set(names)) and APP_ARCHIVE in names, "missing or duplicate app archive")
    return release


def release_facts(release):
    return {key: release.get(key) for key in ("id", "tag_name", "name", "body", "draft", "prerelease", "published_at")}


def asset_facts(asset):
    return {key: asset.get(key) for key in ("id", "name", "state", "size", "digest", "updated_at")}


@dataclass(frozen=True)
class DraftBinding:
    release: dict
    source_sha: str
    archive_sha: str
    archive_size: int

    def check(self, client, output, expected_appcast=None):
        current = read_draft(client, self.release["id"], self.source_sha)
        require(release_facts(current) == release_facts(self.release), "draft release metadata changed")
        original = next(asset for asset in self.release["assets"] if asset["name"] == APP_ARCHIVE)
        actual = next(asset for asset in current["assets"] if asset["name"] == APP_ARCHIVE)
        require(asset_facts(actual) == asset_facts(original), "draft app asset identity changed")
        require(actual.get("size") == self.archive_size and actual.get("digest") == "sha256:" + self.archive_sha,
                "draft app asset metadata differs from qualified bytes")
        client.download(f"releases/assets/{actual['id']}", output / "draft-app.zip", self.archive_sha, self.archive_size)
        appcasts = [asset for asset in current["assets"] if asset["name"] == "appcast.xml"]
        if appcasts:
            require(expected_appcast is not None, "existing appcast has no verified release intent")
            expected_sha, expected_size = sha256(expected_appcast), expected_appcast.stat().st_size
            require(appcasts[0].get("size") == expected_size and appcasts[0].get("digest") == "sha256:" + expected_sha,
                    "existing appcast differs; immutable assets cannot be clobbered")
            client.download(f"releases/assets/{appcasts[0]['id']}", output / "draft-appcast.xml", expected_sha, expected_size)
        return current


def producer_inputs(client, root, run_id, attempt, tooling_sha, source_sha, team):
    run = client.api(f"actions/runs/{run_id}")
    require(run.get("id") == run_id and run.get("run_attempt") == attempt
            and run.get("repository", {}).get("full_name") == REPOSITORY
            and run.get("head_repository", {}).get("full_name") == REPOSITORY
            and run.get("event") in ("push", "workflow_dispatch")
            and run.get("path", "").split("@")[0] == qualification.QUALIFICATION_WORKFLOW
            and run.get("head_sha") == tooling_sha
            and run.get("status") == "completed" and run.get("conclusion") == "success",
            "qualification producer must be the exact completed successful trusted workflow")
    response = client.api(f"actions/runs/{run_id}/artifacts?per_page=100")
    artifacts = response.get("artifacts")
    require(isinstance(artifacts, list) and type(response.get("total_count")) is int
            and response["total_count"] <= 100 and response["total_count"] == len(artifacts),
            "artifact inventory absent or truncated")
    matches = [item for item in artifacts if isinstance(item, dict) and item.get("name") == QUALIFICATION_ARTIFACT]
    require(len(matches) == 1, "missing or duplicate qualification artifact")
    transport = root / "qualification.zip"
    client.artifact(matches[0]["id"], transport)
    with zipfile.ZipFile(transport) as archive:
        entry = archive.getinfo("qualification-inputs.json")
        require(entry.file_size <= qualification.MAX_RECEIPT, "qualification inputs exceed limit")
        projection = qualification.decode_json(archive.read(entry))
    jobs_response = client.api(f"actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100")
    jobs = jobs_response.get("jobs")
    require(isinstance(jobs, list) and type(jobs_response.get("total_count")) is int
            and jobs_response["total_count"] <= 100 and jobs_response["total_count"] == len(jobs),
            "job inventory absent or truncated")

    def job_id(name):
        matches = [job for job in jobs if isinstance(job, dict) and job.get("name") == name]
        require(len(matches) == 1, "missing or duplicate required producer job")
        return positive_id(matches[0]["id"])

    inputs = {
        "schemaVersion": 1,
        "sourceBuild": {key: projection["sourceBuild"][key] for key in ("runId", "runAttempt", "artifactId")},
        "qualification": {"runId": run_id, "runAttempt": attempt, "toolingSha": tooling_sha,
                          "artifactId": matches[0]["id"], "jobId": job_id("Collect macOS qualification evidence")},
        "finalArchive": {**projection["finalArchive"], "runId": run_id, "runAttempt": attempt,
                         "jobId": job_id("Finalize notarized macOS app"), "path": f"{RESERVED}/final.zip"},
        "rows": projection["rows"],
    }
    checker = qualification.Qualification(root, source_sha, tooling_sha, team)
    checker.bind_evidence(transport, inputs)
    require(not checker.problems, "authenticated qualification inputs differ from release policy")
    with zipfile.ZipFile(transport) as archive:
        require(all(qualification.archive_name(item.filename, set()).parts[0].casefold() not in (RESERVED, "qualification.zip") for item in archive.infolist()),
                "qualification archive collides with consumer files")
        archive.extractall(root)
    consumer = root / RESERVED
    consumer.mkdir(mode=0o700)
    transport.rename(consumer / "qualification.zip")
    for record, name in ((inputs["sourceBuild"], "source-build.zip"), (inputs["finalArchive"], "final-archive.zip")):
        record["transportArchive"] = f"{RESERVED}/{name}"
        client.artifact(record["artifactId"], consumer / name)
    inputs["qualification"]["transportArchive"] = f"{RESERVED}/qualification.zip"
    with zipfile.ZipFile(consumer / "final-archive.zip") as archive:
        members = [item for item in archive.infolist() if item.filename == APP_ARCHIVE]
        require(len(members) == 1 and members[0].file_size <= MAX_TRANSPORT and not members[0].flag_bits & 1,
                "finalization transport lacks one bounded unencrypted app ZIP")
        with archive.open(members[0]) as stream, (consumer / "final.zip").open("xb") as output:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                output.write(block)
    manifest = consumer / "manifest.json"
    manifest.write_text(json.dumps(inputs), encoding="utf-8")
    return manifest, inputs


def verify_qualification(manifest, root, source_sha, tooling_sha, team, report):
    result = subprocess.run([sys.executable, str(SCRIPTS / "verify-macos-release-qualification.py"), str(manifest),
                             "--evidence-root", str(root), "--expected-source-sha", source_sha,
                             "--expected-tooling-sha", tooling_sha, "--developer-id-team", team],
                            capture_output=True, timeout=60, check=False)
    require(len(result.stdout) <= qualification.MAX_RECEIPT, "qualification result exceeds limit")
    report.write_bytes(result.stdout)
    verdict = qualification.decode_json(result.stdout)
    require(result.returncode == 0 and verdict.get("publicationEligible") is True and verdict.get("rejections") == [],
            "shared qualification verifier rejected publication; see qualification-result.json")
    return verdict


def app_intent(path, release):
    with zipfile.ZipFile(path) as archive:
        info = archive.getinfo(qualification.APP_NAME + "/Contents/Info.plist")
        require(info.file_size <= 1024 ** 2, "final app plist exceeds limit")
        plist = plistlib.loads(archive.read(info))
    version = release_version(release["tag_name"])
    require(plist.get("CFBundleIdentifier") == qualification.BUNDLE_ID
            and plist.get("CFBundleShortVersionString") == version["short"]
            and plist.get("CFBundleVersion") == version["build"], "release tag and actual app versions differ")
    minimum = plist.get("LSMinimumSystemVersion")
    require(isinstance(minimum, str) and re.fullmatch(r"\d+\.\d+(?:\.\d+)?", minimum) is not None,
            "final app minimum OS is invalid")
    return {"publicationTime": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
            "minimumSystemVersion": minimum, "appVersion": version["short"], "appBuild": version["build"]}


def resume_appcast_time(client, draft, output):
    existing = [asset for asset in draft["assets"] if asset["name"] == "appcast.xml"]
    if not existing:
        return None
    asset = existing[0]
    require(type(asset.get("size")) is int and asset["size"] <= qualification.MAX_RECEIPT,
            "existing appcast exceeds receipt limit")
    digest = asset.get("digest", "")
    require(isinstance(digest, str) and digest.startswith("sha256:"), "existing appcast lacks API digest")
    client.download(f"releases/assets/{asset['id']}", output, digest[7:], asset["size"])
    dates = re.findall(r"<pubDate>([^<]+)</pubDate>", output.read_text(encoding="utf-8"))
    require(len(dates) == 1, "existing appcast lacks one publication timestamp")
    date = parsedate_to_datetime(dates[0])
    require(date.tzinfo is not None and date <= datetime.now(timezone.utc), "existing appcast timestamp is invalid")
    return date.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def publish(args):
    client = GitHub()
    draft = read_draft(client, args.release_id, args.expected_source_sha)
    root = args.output_dir / "evidence"
    root.mkdir(mode=0o700)
    manifest, inputs = producer_inputs(client, root, args.qualification_run_id, args.qualification_run_attempt,
                                       args.expected_tooling_sha, args.expected_source_sha, args.developer_id_team)
    verify_qualification(manifest, root, args.expected_source_sha, args.expected_tooling_sha,
                         args.developer_id_team, args.output_dir / "qualification-result.json")
    final = inputs["finalArchive"]
    binding = DraftBinding(draft, args.expected_source_sha, final["sha256"], final["size"])
    intent = app_intent(root / final["path"], draft)
    previous_time = resume_appcast_time(client, draft, args.output_dir / "previous-appcast.xml")
    if previous_time is not None:
        intent["publicationTime"] = previous_time
    intent_file, draft_file = args.output_dir / "intent.json", args.output_dir / "draft.json"
    intent_file.write_text(json.dumps(intent), encoding="utf-8")
    draft_file.write_text(json.dumps(draft), encoding="utf-8")
    appcast = args.output_dir / "appcast.xml"
    with appcast.open("xb") as output:
        result = subprocess.run(["node", str(SCRIPTS / "generate-github-release-appcast.js"), str(draft_file),
                                 "--draft-intent", str(intent_file)], stdout=output, stderr=subprocess.PIPE,
                                timeout=5, check=False)
    require(result.returncode == 0, "draft appcast generation failed")
    initial = args.output_dir / "initial-binding"
    initial.mkdir(mode=0o700)
    current = binding.check(client, initial, appcast)
    if not args.publish:
        return {"state": "verified-draft-preview", "releaseId": draft["id"], "archiveSha256": final["sha256"]}
    if not any(asset["name"] == "appcast.xml" for asset in current["assets"]):
        client.run(["release", "upload", draft["tag_name"], str(appcast), "--repo", REPOSITORY])
    last = args.output_dir / "final-binding"
    last.mkdir(mode=0o700)
    checked = binding.check(client, last, appcast)
    require(any(asset["name"] == "appcast.xml" for asset in checked["assets"]), "draft appcast missing before publication")
    client.run(["api", "--hostname", "github.com", f"repos/{REPOSITORY}/releases/{draft['id']}",
                "--method", "PATCH", "-F", "draft=false"])
    published = client.api(f"releases/{draft['id']}")
    require(published.get("draft") is False and published.get("prerelease") is False
            and published.get("id") == draft["id"] and published.get("tag_name") == draft["tag_name"],
            "publication result differs from verified draft")
    assets = published.get("assets", [])
    require(sorted((asset_facts(asset) for asset in assets), key=lambda asset: asset["id"])
            == sorted((asset_facts(asset) for asset in checked["assets"]), key=lambda asset: asset["id"]),
            "public asset inventory differs from verified draft")
    for asset in assets:
        client.download(f"releases/assets/{asset['id']}", args.output_dir / ("public-" + asset["name"]),
                        asset["digest"][7:], asset["size"])
    return {"state": "published", "releaseId": draft["id"], "archiveSha256": final["sha256"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_id", type=int)
    parser.add_argument("--qualification-run-id", type=int, required=True)
    parser.add_argument("--qualification-run-attempt", type=int, required=True)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--expected-tooling-sha", required=True)
    parser.add_argument("--developer-id-team", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    owned_output = False
    try:
        for value in (args.release_id, args.qualification_run_id, args.qualification_run_attempt):
            positive_id(value)
        require(qualification.SHA1.fullmatch(args.expected_source_sha) is not None
                and qualification.SHA1.fullmatch(args.expected_tooling_sha) is not None
                and re.fullmatch(r"[A-Z0-9]{10}", args.developer_id_team) is not None, "invalid release policy inputs")
        args.output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
        owned_output = True
        result = publish(args)
        exit_code = 0
    except (PublicationBlocked, qualification.InvalidEvidence, KeyError, TypeError, ValueError, AttributeError, IndexError, RuntimeError, OSError,
            subprocess.SubprocessError, zipfile.BadZipFile) as error:
        result = {"state": "blocked", "reason": str(error) if isinstance(error, (PublicationBlocked, qualification.InvalidEvidence)) else type(error).__name__}
        exit_code = 1
    if owned_output:
        (args.output_dir / "publication-result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
