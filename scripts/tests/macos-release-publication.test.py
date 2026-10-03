#!/usr/bin/env python3

import copy
import hashlib
import importlib.util
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parent


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


publisher = load_module("macos_publisher", SCRIPTS / "publish-qualified-macos-release.py")
fixtures = load_module("qualification_test_fixtures", SCRIPTS / "tests/macos-release-qualification.test.py")
SOURCE = fixtures.SOURCE

FAKE_GH = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['PUBLICATION_TEST_TRANSPORT'])
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as stream:
    stream.write(json.dumps(args) + '\n')
if args[:2] == ['release', 'upload'] or '--method' in args:
    with (root / 'writes.jsonl').open('a') as stream:
        stream.write(json.dumps(args) + '\n')
    print('{}')
    sys.exit(0)
endpoint = next((arg.split('repos/negentropi/roma-just-talk/', 1)[1] for arg in args if arg.startswith('repos/negentropi/roma-just-talk/')), None)
routes = json.loads((root / 'routes.json').read_text())
if endpoint not in routes:
    sys.exit(7)
response = routes[endpoint]
if isinstance(response, dict) and set(response) == {'file'}:
    sys.stdout.buffer.write(Path(response['file']).read_bytes())
else:
    print(json.dumps(response))
'''


def run_block(workflow, step_name):
    step = workflow.split("      - name: " + step_name + "\n", 1)[1].split("      - name: ", 1)[0]
    match = re.search(r"        run: \|\n((?:          [^\n]*\n|\n)+)", step)
    if match:
        return "\n".join(line[10:] for line in match[1].splitlines())
    return re.search(r"        run: ([^\n]+)", step)[1]


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="roma-publication-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fixture = fixtures.QualificationTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.bind_failed_qualification_archive()
        self.data = self.fixture.root
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "gh").write_text(FAKE_GH)
        (self.bin / "gh").chmod(0o755)
        self.environment = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ.get("PATH", ""),
                                PUBLICATION_TEST_TRANSPORT=str(self.root), GH_TOKEN="local-fixture-only")
        self.sha = hashlib.sha256((self.data / "final.zip").read_bytes()).hexdigest()
        self.size = (self.data / "final.zip").stat().st_size
        self.draft = {"id": 70, "tag_name": "v1.95", "name": "Roma 1.95", "body": "Recorded ad-hoc candidate; not qualified.",
                      "html_url": "https://github.com/negentropi/roma-just-talk/releases/tag/v1.95",
                      "draft": True, "prerelease": False, "published_at": None,
                      "assets": [{"id": 501, "name": publisher.APP_ARCHIVE, "state": "uploaded", "size": self.size,
                                  "digest": "sha256:" + self.sha, "updated_at": "2026-10-03T18:05:00Z"}]}
        self.routes = {
            "releases/70": self.draft,
            "git/ref/tags/v1.95": {"ref": "refs/tags/v1.95", "object": {"type": "commit", "sha": SOURCE}},
            "releases/assets/501": {"file": str(self.data / "final.zip")},
            "actions/runs/42": self.read("producer-run.json"),
            "actions/runs/42/attempts/1/jobs?per_page=100": self.read("producer-jobs.json"),
            "actions/runs/42/artifacts?per_page=100": {"total_count": 1, "artifacts": [self.read("qualification-artifact.json")]},
            f"actions/runs/{fixtures.RUN['id']}": fixtures.RUN,
            f"actions/runs/{fixtures.RUN['id']}/attempts/1/jobs?per_page=100": fixtures.JOBS,
        }
        for artifact_id, metadata, archive in [(61, "qualification-artifact.json", "qualification.zip"),
                                                (62, "final-artifact.json", "transport.zip"),
                                                (fixtures.ARTIFACT["id"], "artifact.json", "transport.zip")]:
            record = self.read(metadata)
            path = self.data / archive
            record.update(size_in_bytes=path.stat().st_size, digest="sha256:" + hashlib.sha256(path.read_bytes()).hexdigest())
            self.routes[f"actions/artifacts/{artifact_id}"] = record
            self.routes[f"actions/artifacts/{artifact_id}/zip"] = {"file": str(path)}
        self.routes["actions/runs/42/artifacts?per_page=100"]["artifacts"] = [self.routes["actions/artifacts/61"]]
        self.save_routes()

    def read(self, name):
        return json.loads((self.data / name).read_text())

    def save_routes(self):
        (self.root / "routes.json").write_text(json.dumps(self.routes))

    def writes(self):
        path = self.root / "writes.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def invoke(self, output=None):
        output = output or self.root / "output"
        result = subprocess.run([sys.executable, str(SCRIPTS / "publish-qualified-macos-release.py"), "70",
                                 "--qualification-run-id", "42", "--qualification-run-attempt", "1",
                                 "--expected-source-sha", SOURCE, "--expected-tooling-sha", SOURCE,
                                 "--developer-id-team", "ABCDE12345", "--output-dir", str(output), "--publish"],
                                env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1, result.stderr)
        parsed = json.loads(result.stdout)
        self.assertEqual(parsed["state"], "blocked")
        self.assertEqual(self.writes(), [])
        return parsed

    def client(self):
        original = dict(os.environ)
        os.environ.update(self.environment)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(original)))
        return publisher.GitHub()

    def binding_check(self, draft=None, appcast=None):
        output = self.root / "binding"
        output.mkdir()
        return publisher.DraftBinding(draft or self.draft, SOURCE, self.sha, self.size).check(self.client(), output, appcast)

    def test_old_published_event_writes_feed_but_new_actual_verifier_writes_nothing(self):
        legacy = (SCRIPTS / "tests/fixtures/publish-update-feed-before-qualification.yml").read_text()
        self.routes["releases/tags/v1.95"] = {**self.draft, "draft": False, "published_at": "2026-10-03T18:05:00Z"}
        self.save_routes()
        environment = dict(self.environment, RELEASE_TAG="v1.95", GITHUB_REPOSITORY=publisher.REPOSITORY,
                           RUNNER_TEMP=str(self.root))
        for name in ("Read release after app archive upload", "Generate informational appcast", "Attach appcast to GitHub release"):
            result = subprocess.run(["bash", "-euo", "pipefail", "-c", run_block(legacy, name)], cwd=REPO,
                                    env=environment, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.writes()[0][:3], ["release", "upload", "v1.95"])
        self.assertIn("--clobber", self.writes()[0])
        (self.root / "writes.jsonl").unlink()
        self.invoke()
        report = json.loads((self.root / "output/qualification-result.json").read_text())
        codes = {item["code"] for item in report["rejections"]}
        self.assertIn("CONTROLLER_ORIGIN_UNVERIFIED", codes)
        self.assertIn("SIGNER_MISMATCH", codes)
        self.assertIn("REQUIRED_OS_ROW_MISSING", codes)
        self.assertNotIn("API_ORIGIN_UNVERIFIED", codes)

    def test_incomplete_or_failed_whole_producer_never_writes(self):
        self.routes["actions/runs/42"].update(status="in_progress", conclusion=None)
        self.save_routes()
        self.assertIn("completed successful", self.invoke()["reason"])

    def test_duplicate_qualification_artifact_rejects(self):
        listing = self.routes["actions/runs/42/artifacts?per_page=100"]
        listing["artifacts"] *= 2
        listing["total_count"] = 2
        self.save_routes()
        self.assertIn("duplicate qualification artifact", self.invoke()["reason"])

    def test_archive_cannot_overwrite_its_own_authenticated_transport(self):
        path = self.data / "qualification.zip"
        with zipfile.ZipFile(path, "a") as archive:
            archive.writestr("qualification.zip", b"replacement of the authenticated transport")
        self.routes["actions/artifacts/61"].update(size_in_bytes=path.stat().st_size, digest="sha256:" + hashlib.sha256(path.read_bytes()).hexdigest())
        self.save_routes()
        self.assertIn("collides with consumer files", self.invoke()["reason"])
        self.assertEqual((self.root / "output/evidence/qualification.zip").read_bytes(), path.read_bytes())

    def test_wrong_producer_head_and_failed_source_never_write(self):
        self.routes["actions/runs/42"]["head_sha"] = "0" * 40
        self.save_routes()
        self.assertIn("trusted workflow", self.invoke()["reason"])
        self.routes["actions/runs/42"]["head_sha"] = SOURCE
        self.routes[f"actions/runs/{fixtures.RUN['id']}"] = {**fixtures.RUN, "conclusion": "failure"}
        self.save_routes()
        self.invoke(self.root / "second-output")
        codes = {item["code"] for item in json.loads((self.root / "second-output/qualification-result.json").read_text())["rejections"]}
        self.assertIn("RUN_NOT_SUCCESSFUL", codes)

    def test_uploaded_pass_assertions_do_not_authorize_publication(self):
        path = self.data / "qualification.zip"
        with zipfile.ZipFile(path) as archive:
            entries = {item.filename: archive.read(item) for item in archive.infolist()}
        projection = json.loads(entries["qualification-inputs.json"])
        projection["controller"] = {"authenticated": True, "passed": True}
        entries["qualification-inputs.json"] = json.dumps(projection).encode()
        with zipfile.ZipFile(path, "w") as archive:
            for name, value in entries.items():
                archive.writestr(name, value)
        self.routes["actions/artifacts/61"].update(size_in_bytes=path.stat().st_size, digest="sha256:" + hashlib.sha256(path.read_bytes()).hexdigest())
        self.save_routes()
        self.assertIn("inputs differ", self.invoke()["reason"])

    def test_published_release_and_extra_distribution_asset_reject(self):
        self.draft["draft"] = False
        self.save_routes()
        self.assertIn("unpublished stable draft", self.invoke()["reason"])
        self.draft["draft"] = True
        self.draft["assets"].append({"id": 502, "name": "unqualified.dmg", "state": "uploaded"})
        self.save_routes()
        self.assertIn("unqualified", self.invoke(self.root / "second-output")["reason"])

    def test_binding_downloads_exact_draft_asset_by_id(self):
        self.binding_check()
        self.assertEqual((self.root / "binding/draft-app.zip").read_bytes(), (self.data / "final.zip").read_bytes())
        calls = [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]
        self.assertTrue(any(f"repos/{publisher.REPOSITORY}/releases/assets/501" in call and "Accept: application/octet-stream" in call for call in calls))
        self.assertEqual(self.writes(), [])

    def test_same_asset_metadata_with_changed_actual_bytes_rejects(self):
        changed = self.root / "changed.zip"
        changed.write_bytes((self.data / "final.zip").read_bytes() + b"replacement")
        self.routes["releases/assets/501"] = {"file": str(changed)}
        self.save_routes()
        with self.assertRaisesRegex(publisher.PublicationBlocked, "download bytes differ"):
            self.binding_check()
        self.assertEqual(self.writes(), [])

    def test_final_recheck_detects_replacement_after_initial_download(self):
        client = self.client()
        binding = publisher.DraftBinding(copy.deepcopy(self.draft), SOURCE, self.sha, self.size)
        first, last = self.root / "first-check", self.root / "last-check"
        first.mkdir()
        last.mkdir()
        binding.check(client, first)
        changed = self.root / "changed-after-check.zip"
        changed.write_bytes((self.data / "final.zip").read_bytes() + b"changed after first download")
        self.routes["releases/assets/501"] = {"file": str(changed)}
        self.save_routes()
        with self.assertRaisesRegex(publisher.PublicationBlocked, "download bytes differ"):
            binding.check(client, last)
        self.assertEqual(self.writes(), [])

    def test_replaced_asset_and_changed_draft_metadata_reject_before_download(self):
        original = copy.deepcopy(self.draft)
        self.draft["assets"][0]["id"] = 502
        self.save_routes()
        with self.assertRaisesRegex(publisher.PublicationBlocked, "asset identity changed"):
            self.binding_check(original)
        (self.root / "binding").rmdir()
        self.draft["assets"][0]["id"] = 501
        self.draft["body"] = "changed release notes"
        self.save_routes()
        with self.assertRaisesRegex(publisher.PublicationBlocked, "metadata changed"):
            self.binding_check(original)
        self.assertEqual(self.writes(), [])

    def test_annotated_tag_is_peeled_and_moved_tag_rejects(self):
        self.routes["git/ref/tags/v1.95"]["object"] = {"type": "tag", "sha": "a" * 40}
        self.routes["git/tags/" + "a" * 40] = {"object": {"type": "commit", "sha": SOURCE}}
        self.save_routes()
        self.binding_check()
        (self.root / "binding/draft-app.zip").unlink()
        (self.root / "binding").rmdir()
        self.routes["git/tags/" + "a" * 40]["object"]["sha"] = "0" * 40
        self.save_routes()
        with self.assertRaisesRegex(publisher.PublicationBlocked, "tag differs"):
            self.binding_check()

    def test_existing_appcast_retains_timestamp_and_rejects_clobber(self):
        appcast = self.root / "expected-appcast.xml"
        appcast.write_text("<rss><pubDate>Wed, 01 Jan 2020 18:05:00 GMT</pubDate></rss>\n")
        self.draft["assets"].append({"id": 503, "name": "appcast.xml", "state": "uploaded", "size": appcast.stat().st_size,
                                     "digest": "sha256:" + hashlib.sha256(appcast.read_bytes()).hexdigest()})
        self.routes["releases/assets/503"] = {"file": str(appcast)}
        self.save_routes()
        actual_time = publisher.resume_appcast_time(self.client(), self.draft, self.root / "previous.xml")
        self.assertEqual(actual_time, "2020-01-01T18:05:00Z")
        self.binding_check(appcast=appcast)
        (self.root / "binding/draft-app.zip").unlink()
        (self.root / "binding/draft-appcast.xml").unlink()
        (self.root / "binding").rmdir()
        appcast.write_text("changed")
        with self.assertRaisesRegex(publisher.PublicationBlocked, "cannot be clobbered"):
            self.binding_check(appcast=appcast)
        self.assertEqual(self.writes(), [])

    def test_actual_plist_versions_must_match_tag(self):
        path = self.root / "version-only.zip"
        info = {"CFBundleIdentifier": "com.negentropi.RomaJustTalk", "CFBundleShortVersionString": "1.95",
                "CFBundleVersion": "195", "LSMinimumSystemVersion": "14.2.1"}
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("roma just talk.app/Contents/Info.plist", plistlib.dumps(info))
        intent = publisher.app_intent(path, self.draft)
        self.assertEqual((intent["appVersion"], intent["appBuild"], intent["minimumSystemVersion"]), ("1.95", "195", "14.2.1"))
        info["CFBundleVersion"] = "196"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("roma just talk.app/Contents/Info.plist", plistlib.dumps(info))
        with self.assertRaisesRegex(publisher.PublicationBlocked, "actual app versions differ"):
            publisher.app_intent(path, self.draft)

    def test_existing_output_is_preserved(self):
        output = self.root / "output"
        output.mkdir()
        sentinel = output / "publication-result.json"
        sentinel.write_text("owned by an earlier invocation\n")
        self.invoke()
        self.assertEqual(sentinel.read_text(), "owned by an earlier invocation\n")

    def test_actual_workflow_guard_requires_default_branch_dispatch(self):
        workflow = (REPO / ".github/workflows/publish-update-feed.yml").read_text()
        command = run_block(workflow, "Require trusted default-branch dispatch")
        base = dict(self.environment, EXPECTED_REF="refs/heads/main", GITHUB_REF="refs/heads/main",
                    GITHUB_EVENT_NAME="workflow_dispatch", GITHUB_REPOSITORY=publisher.REPOSITORY)
        for changes, expected in [({}, 0), ({"GITHUB_REF": "refs/heads/unreviewed"}, 1),
                                   ({"GITHUB_EVENT_NAME": "release"}, 1), ({"GITHUB_REPOSITORY": "fork/roma"}, 1)]:
            result = subprocess.run(["bash", "-euo", "pipefail", "-c", command], env={**base, **changes},
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, expected)
        self.assertEqual(self.writes(), [])


if __name__ == "__main__":
    unittest.main()
