import base64
from dataclasses import replace
from datetime import datetime
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from Tools.MacOSNativeRow.protocol import Rejected, archive_snapshot, canonical, decode, digest
from Tools.MacOSNativeRow.rowreader import authenticate_diagnostic_origin, authenticate_native_row
from Tools.MacOSNativeRow.schema import Artifact, BrokerPolicy, CallProfile, CONTRACT, ExpectedRow, FinalArchive, Job, NAMESPACE, PHASES, REPOSITORY, ROW_FILES, WORKFLOW


def zip_bytes(files):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, raw in sorted(files.items()):
            archive.writestr(name, raw)
    return buffer.getvalue()


def artifact(raw, identity):
    return Artifact(identity, digest(raw), len(raw))


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="roma-row-test-only-key-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = self.root / "test-only-key"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.key)], check=True, capture_output=True)
        public = " ".join(self.key.with_suffix(".pub").read_text().split()[:2])
        self.policy = BrokerPolicy("test-only-broker", NAMESPACE, public, "1" * 64, "2" * 64, "3" * 64,
                                   "test-only-transport", ("/fixed/collector", "--case", "fixed-nonce"), "iab", "4", "http://127.0.0.1:6080/vnc.html",
                                   tuple(CallProfile(phase, "await currentVm.getAXStateAndScreenshot();") for phase in PHASES))
        self.expected = ExpectedRow(Job(REPOSITORY, WORKFLOW, "a" * 40, 1, 1, 2, "Qualify Tahoe 26.4.1 (25E253)", 900000, 1300000),
                                    Artifact(3, "0" * 64, 1), Artifact(4, "0" * 64, 1),
                                    FinalArchive("b" * 40, 5, "4" * 64, "5" * 64, 100, "6" * 64, "7" * 64, "ABCDE12345", "com.negentropi.RomaJustTalk"),
                                    "tahoe", "00112233-4455-6677-8899-AABBCCDDEEFF")
        self.request = {"schemaVersion": 1, "contract": CONTRACT, "context": self.expected.identity(), "nonce": "c" * 32,
                        "titlePrefix": "Roma-first-open-" + "c" * 32 + " ", "createdAtMs": 1000000, "expiresAtMs": 1200000,
                        "policySha256": self.policy.policy_sha256, "exporterSha256": self.policy.exporter_sha256, "collectorSha256": self.policy.collector_sha256}
        self.files = {name: b"not a qualified app receipt\n" for name in ROW_FILES}
        self.files["challenge.json"] = canonical(self.request)
        image = io.BytesIO()
        Image.new("RGB", (8, 8), (180, 120, 60)).save(image, "PNG")
        image_raw = image.getvalue()
        self.calls = []
        for index, profile in enumerate(self.policy.calls):
            start = 1000000 + (80000 if profile.phase == "smoke" else (index + 1) * 1000)
            entry = {"turnId": "test-only-turn", "startedAtMs": start, "completedAtMs": start + 10, "item": {
                "id": "test-only-" + profile.phase, "type": "mcpToolCall", "server": "cua_repl", "tool": "js", "status": "completed", "error": None,
                "arguments": {"code": profile.code, "title": self.request["titlePrefix"] + profile.phase}, "result": {
                    "_meta": {"browser_use": {"url": self.policy.browser_url}, "codex/toolSurface": {"backend": "iab", "browserId": "4"}},
                    "content": [{"type": "image", "mimeType": "image/png", "data": base64.b64encode(image_raw).decode()}]}}}
            raw = canonical(entry)
            self.files[profile.phase + "/original-entry.json"] = raw
            self.files[profile.phase + "/image-000.png"] = image_raw
            self.calls.append({"phase": profile.phase, "turnId": "test-only-turn", "itemId": "test-only-" + profile.phase,
                               "startedAtMs": start, "completedAtMs": start + 10, "entrySha256": digest(raw),
                               "images": [{"index": 0, "sha256": digest(image_raw), "bytes": len(image_raw)}]})
        ready = {"schemaVersion": 1, "nonce": self.request["nonce"], "bootUuid": self.expected.boot_uuid, "scanCompletedGuestMs": 1002500,
                 "acknowledgedControllerMs": 1002500, "initialScanExitStatus": 0, "initialPids": [], "logStartedGuestMs": 1000100, "crashBaselineGuestMs": 1000100}
        events = {"schemaVersion": 1, "nonce": self.request["nonce"], "bootUuid": self.expected.boot_uuid,
                  "events": [{"pid": 42, "startTimeMs": 1003000, "observedGuestMs": instant, "observedMonotonicMs": instant - 900000, "state": "S", "executableSha256": "6" * 64,
                              "manifestSha256": "7" * 64} for instant in (1003500, 1090000)]}
        clock = {"schemaVersion": 1, "nonce": self.request["nonce"], "samples": [
            {"controllerBeforeMs": instant, "controllerAfterMs": instant, "guestUtcMs": instant, "guestMonotonicMs": instant - 900000}
            for instant in (1000000, 1100000)]}
        process = {"pid": 42, "startTimeMs": 1003000, "bootUuid": self.expected.boot_uuid, "executableSha256": "6" * 64}
        self.files["observer/readiness.json"] = canonical(ready)
        self.files["observer/process-events.json"] = canonical(events)
        self.files["observer/clock.json"] = canonical(clock)
        self.files["manual-whisper-smoke/result.json"] = canonical({"runtimeProcess": "same-first-process", "beforeProcess": process, "afterProcess": process})
        self.files["manual-whisper-smoke/baseline-query.stdout"] = b"[]"
        self.files["manual-whisper-smoke/result-query.stdout"] = b'[{"id":1}]'
        self.files["collector.stdout"], self.files["collector.stderr"] = b"fixture-only stdout", b""
        self.files["broker-execution.json"] = canonical({"schemaVersion": 1, "transportIdentity": self.policy.transport_identity,
            "collectorSha256": self.policy.collector_sha256, "argv": list(self.policy.collector_argv), "startedAtMs": 1000000,
            "completedAtMs": 1100000, "exitStatus": 0, "timedOut": False, "stdoutSha256": digest(self.files["collector.stdout"]), "stderrSha256": digest(b"")})
        self.origin = {"schemaVersion": 1, "contract": CONTRACT, "brokerIdentity": self.policy.identity, "namespace": self.policy.namespace,
            "context": self.expected.identity(), "challengeArtifactId": 4, "requestSha256": digest(self.files["challenge.json"]),
            "policySha256": self.policy.policy_sha256, "exporterSha256": self.policy.exporter_sha256, "collectorSha256": self.policy.collector_sha256,
            "collectionStartedAtMs": 1000000, "collectionEndedAtMs": 1100000, "signedAtMs": 1100100, "calls": self.calls}

    def mutate_json(self, path, mutate):
        value = json.loads(self.files[path])
        mutate(value)
        self.files[path] = canonical(value)

    def sealed(self):
        self.origin["files"] = [{"path": name, "size": len(raw), "sha256": digest(raw)} for name, raw in sorted(self.files.items())
                                if name not in ("broker-origin.json", "broker-origin.json.sig")]
        self.files["broker-origin.json"] = canonical(self.origin)
        result = subprocess.run(["ssh-keygen", "-Y", "sign", "-f", str(self.key), "-n", self.policy.namespace, "-"],
                                input=self.files["broker-origin.json"], capture_output=True, check=True)
        self.files["broker-origin.json.sig"] = result.stdout
        payload, challenge = zip_bytes(self.files), zip_bytes({"challenge.json": self.files["challenge.json"]})
        return payload, challenge, replace(self.expected, payload=artifact(payload, 3), challenge=artifact(challenge, 4))

    def reject(self, reason):
        payload, challenge, expected = self.sealed()
        with self.assertRaisesRegex(Rejected, reason):
            authenticate_native_row(payload, challenge, expected=expected, policy=self.policy, now_ms=1400000)

    def test_request_cannot_choose_a_pid(self):
        self.mutate_json("challenge.json", lambda value: value.update(firstPid=42))
        self.reject("unopened-request-fields")

    def test_preexisting_pid_and_sampler_after_open_reject(self):
        self.mutate_json("observer/readiness.json", lambda value: value.update(initialPids=[41]))
        self.reject("observer-not-unopened")
        self.mutate_json("observer/readiness.json", lambda value: value.update(initialPids=[], acknowledgedControllerMs=1004000))
        self.reject("sampler-after-open")

    def test_first_process_cannot_be_replaced_by_later_survivor(self):
        self.mutate_json("observer/process-events.json", lambda value: value["events"][1].update(pid=43))
        self.reject("first-process-replaced")

    def test_late_detection_cannot_hide_a_preexisting_process(self):
        self.mutate_json("observer/process-events.json", lambda value: [event.update(startTimeMs=1002000) for event in value["events"]])
        self.mutate_json("manual-whisper-smoke/result.json", lambda value: [value[key].update(startTimeMs=1002000) for key in ("beforeProcess", "afterProcess")])
        self.reject("process-event-window")

    def test_malformed_nested_browser_metadata_rejects(self):
        self.mutate_json("download/original-entry.json", lambda value: value["item"]["result"]["_meta"].update(browser_use=[]))
        self.reject("call-browser-target")

    def test_wall_clock_jump_cannot_substitute_for_stability(self):
        self.mutate_json("observer/process-events.json", lambda value: value["events"][1].update(observedMonotonicMs=110000))
        self.reject("first-process-not-stable")

    def test_separate_relaunch_and_existing_transcript_reject(self):
        self.mutate_json("manual-whisper-smoke/result.json", lambda value: value.update(runtimeProcess="separate_relaunch_of_same_artifact"))
        self.reject("smoke-process-replaced")
        self.mutate_json("manual-whisper-smoke/result.json", lambda value: value.update(runtimeProcess="same-first-process"))
        self.files["manual-whisper-smoke/baseline-query.stdout"] = b'[{"id":1}]'
        self.reject("smoke-no-new-record")

    def test_failed_or_replaced_collector_command_rejects(self):
        self.mutate_json("broker-execution.json", lambda value: value.update(exitStatus=1))
        self.reject("collector-execution-origin")
        self.mutate_json("broker-execution.json", lambda value: value.update(exitStatus=0, argv=["/different/collector"]))
        self.reject("collector-execution-origin")

    def test_collector_started_after_observation_rejects(self):
        self.mutate_json("broker-execution.json", lambda value: value.update(startedAtMs=1095000))
        self.reject("observer-outside-collector")

    def test_late_signing_rejects(self):
        self.origin["signedAtMs"] = self.request["expiresAtMs"]
        self.reject("production-collection-window")

    def test_missing_receipt_and_extra_member_reject(self):
        raw = self.files.pop("macos-distribution-e2e/reference-trust/signature.stderr")
        self.reject("production-receipt-missing")
        self.files["macos-distribution-e2e/reference-trust/signature.stderr"] = raw
        self.files["extra.txt"] = b"not an admitted receipt"
        self.reject("unapproved-response-file")

    def test_duplicate_original_call_and_substituted_image_reject(self):
        self.mutate_json("ui-action/original-entry.json", lambda value: value["item"].update(id="test-only-ui-before"))
        self.reject("call-duplicate-identity")
        self.mutate_json("ui-action/original-entry.json", lambda value: value["item"].update(id="test-only-ui-action"))
        self.files["ui-action/image-000.png"] = b"changed image"
        self.reject("substituted-or-missing-image")

    def test_wrong_context_and_key_reject(self):
        payload, challenge, expected = self.sealed()
        for changed in (replace(expected, boot_uuid="different"), replace(expected, job=replace(expected.job, attempt=2)),
                        replace(expected, final=replace(expected.final, zip_sha256="e" * 64))):
            with self.subTest(context=changed), self.assertRaisesRegex(Rejected, "production-request-context"):
                authenticate_native_row(payload, challenge, expected=changed, policy=self.policy, now_ms=1400000)
        other = self.root / "other-test-only-key"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(other)], check=True, capture_output=True)
        other_public = " ".join(other.with_suffix(".pub").read_text().split()[:2])
        with self.assertRaisesRegex(Rejected, "broker-signature-invalid"):
            authenticate_native_row(payload, challenge, expected=expected, policy=replace(self.policy, public_key=other_public), now_ms=1400000)

    def test_snapshot_authenticates_returned_bytes_and_is_immutable(self):
        raw = zip_bytes({"receipt.txt": b"original"})
        files = archive_snapshot(raw, digest(raw), len(raw))
        with self.assertRaises(TypeError):
            files["receipt.txt"] = b"replacement"
        self.assertEqual(files["receipt.txt"], b"original")
        with self.assertRaisesRegex(Rejected, "api-artifact-bytes"):
            archive_snapshot(raw + b"changed", digest(raw), len(raw))

    def test_duplicate_json_nonfinite_and_archive_capacity_reject(self):
        for raw, reason in ((b'{"pid":1,"pid":2}', "duplicate-json-key"), (b'{"time":NaN}', "nonfinite-json")):
            with self.subTest(raw=raw), self.assertRaisesRegex(Rejected, reason):
                decode(raw)
        raw = zip_bytes({"receipt.txt": b"bounded"})
        with self.assertRaisesRegex(Rejected, "transport-capacity"):
            archive_snapshot(raw, digest(raw), len(raw), max_transport_bytes=len(raw) - 1)
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            link = zipfile.ZipInfo("linked-receipt.txt")
            link.create_system = 3
            link.external_attr = 0o120777 << 16
            archive.writestr(link, "receipt.txt")
        raw = buffer.getvalue()
        with self.assertRaisesRegex(Rejected, "archive-member-type"):
            archive_snapshot(raw, digest(raw), len(raw))

    def test_numeric_overflow_rejects_without_losing_finite_decimals(self):
        for raw in (b'{"x":1e999}', b'{"x":-1e999}', b'{"nested":[{"x":1e999}]}'):
            with self.subTest(raw=raw), self.assertRaisesRegex(Rejected, "nonfinite-json"):
                decode(raw)
        self.assertEqual(decode(b'{"values":[1.25,-0.5,1e-3]}'), {"values": [1.25, -0.5, 0.001]})

    def test_oversized_integer_rejects_as_invalid_json(self):
        with self.assertRaisesRegex(Rejected, "invalid-json"):
            decode(b'{"x":' + b'1' * 5000 + b'}')

    def test_production_namespace_and_inconsistent_clock_reject(self):
        payload, challenge, expected = self.sealed()
        with self.assertRaisesRegex(Rejected, "production-policy-profile"):
            authenticate_native_row(payload, challenge, expected=expected,
                                    policy=replace(self.policy, namespace="roma-native-origin@roma-just-talk"), now_ms=1400000)
        self.mutate_json("observer/clock.json", lambda value: value["samples"][1].update(guestUtcMs=1101000))
        self.reject("clock-offset-unproved")

    def test_black_original_image_rejects(self):
        image = io.BytesIO()
        Image.new("RGB", (8, 8), (0, 0, 0)).save(image, "PNG")
        raw = image.getvalue()
        self.files["download/image-000.png"] = raw
        self.mutate_json("download/original-entry.json", lambda value: value["item"]["result"]["content"][0].update(data=base64.b64encode(raw).decode()))
        self.reject("black-image")

    def test_duplicate_path_escape_and_encrypted_member_reject(self):
        buffer = io.BytesIO()
        with warnings.catch_warnings(), zipfile.ZipFile(buffer, "w") as archive:
            warnings.simplefilter("ignore", UserWarning)
            archive.writestr("receipt.txt", b"one")
            archive.writestr("receipt.txt", b"two")
        raw = buffer.getvalue()
        with self.assertRaisesRegex(Rejected, "duplicate-member"):
            archive_snapshot(raw, digest(raw), len(raw))
        raw = zip_bytes({"../receipt.txt": b"escape"})
        with self.assertRaisesRegex(Rejected, "unsafe-member"):
            archive_snapshot(raw, digest(raw), len(raw))
        raw = bytearray(zip_bytes({"receipt.txt": b"encrypted flag"}))
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            central = archive.start_dir
        struct.pack_into("<H", raw, 6, 1)
        struct.pack_into("<H", raw, central + 8, 1)
        raw = bytes(raw)
        with self.assertRaisesRegex(Rejected, "archive-member-type"):
            archive_snapshot(raw, digest(raw), len(raw))

    def test_corrupt_compressed_member_rejects(self):
        raw = bytearray(zip_bytes({"receipt.txt": b"a" * 1000}))
        name_size, extra_size = struct.unpack_from("<HH", raw, 26)
        raw[30 + name_size + extra_size] = 0xff
        raw = bytes(raw)
        with self.assertRaisesRegex(Rejected, "invalid-archive"):
            archive_snapshot(raw, digest(raw), len(raw))


class RetainedOriginTests(unittest.TestCase):
    def test_real_signed_diagnostic_origin_and_production_rejection(self):
        location = os.environ.get("RJT_NATIVE_ROW_REPLAY_ROOT")
        if not location:
            self.skipTest("retained original native payload not supplied")
        root = Path(location)
        utc = lambda value: int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)
        job = Job(REPOSITORY, ".github/workflows/roma-native-challenge-probe.yml", "2dee65174cfeb6ad27c43a7a41fab4d9c63a7d43", 37158262982, 1,
                  111306109060, "Collect original native calls", utc("2026-10-03T22:23:13Z"), utc("2026-10-03T22:30:34Z"))
        payload = Artifact(11287305162, "5ae01b3ce640ff7395c7c77d95ea64ae601ba2742505d9bf01cf54d301f0da42", 447603)
        challenge = Artifact(11287215003, "3f54b4a441dff1509bacae3256a0443a8fdcd023a08e8c486a63d8ba2a96b353", 724)
        payload_raw, challenge_raw = (root / "hosted-result/payload.zip").read_bytes(), (root / "api-07.stdout").read_bytes()
        policy_raw = (root / "policy.json").read_bytes()
        result = authenticate_diagnostic_origin(payload_raw, challenge_raw, job=job, payload=payload, challenge=challenge, policy_raw=policy_raw,
            expected_policy_sha256="a46524120fe0aa6c13086d6dad61741113cbaa0bb340e0ab8723b91e16078c4a",
            exporter_sha256="69f7afdc99ff35b19440b1ade5cc8bc84101bfe0dd2dbec2c83fb425d7292d2e")
        self.assertEqual(result.inventory_sha256, "eb6820769a3a10850c270465241039682202eee6c2f72ac4d5deb5f0b6eb85f1")
        self.assertEqual(result.job_id, 111306109060)
        self.assertFalse(hasattr(result, "first_process"))
        self.assertFalse(hasattr(result, "publicationEligible"))
        policy_data = json.loads(policy_raw)
        policy = BrokerPolicy("unimplemented-production-broker", NAMESPACE, policy_data["broker"]["publicKey"], "0" * 64, "0" * 64, "0" * 64,
                              "unimplemented-transport", (), "iab", "4", "http://127.0.0.1:6080/vnc.html", tuple(CallProfile(phase, "unimplemented") for phase in PHASES))
        expected = ExpectedRow(replace(job, workflow=WORKFLOW, job_name="Qualify Tahoe 26.4.1 (25E253)"), payload, challenge,
                              FinalArchive("0" * 40, 1, "0" * 64, "0" * 64, 1, "0" * 64, "0" * 64, "ABCDE12345", "com.negentropi.RomaJustTalk"), "tahoe",
                              "393C9C89-55DA-41C7-BE80-59B000E7BE43")
        with self.assertRaisesRegex(Rejected, "unopened-request-fields"):
            authenticate_native_row(payload_raw, challenge_raw, expected=expected, policy=policy)


if __name__ == "__main__":
    unittest.main()
