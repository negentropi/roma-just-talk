from dataclasses import dataclass
from datetime import datetime, timezone
import re
from types import MappingProxyType

from .protocol import Rejected, archive_snapshot, canonical, decode, digest, native_call, require, signed_inventory
from .schema import CONTRACT, NAMESPACE, OS_ROWS, PHASES, REPOSITORY, ROW_FILES, WORKFLOW, FirstProcess


def milliseconds():
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def object_with_keys(value, keys, reason):
    require(isinstance(value, dict) and set(value) == set(keys), reason)
    return value


def positive(value):
    return type(value) is int and value > 0


@dataclass(frozen=True)
class AuthenticatedNativeRow:
    first_process: FirstProcess
    inventory_sha256: str
    _files: object

    def bytes(self, relative):
        require(relative in self._files, "unsigned-or-unknown-receipt")
        return self._files[relative]

    def text(self, relative):
        try:
            return self.bytes(relative).decode("utf-8")
        except UnicodeError as error:
            raise Rejected("receipt-not-utf8") from error


@dataclass(frozen=True)
class DiagnosticOrigin:
    inventory_sha256: str
    run_id: int
    job_id: int


def challenge_snapshot(raw, artifact, limit):
    files = archive_snapshot(raw, artifact.sha256, artifact.size, limit)
    require(set(files) == {"challenge.json"}, "challenge-artifact-layout")
    return files["challenge.json"]


def calls_from_profiles(files, profiles, title_prefix, browser, created, expires, now):
    calls, members, identities = [], set(), set()
    previous = created
    for profile in profiles:
        call, paths = native_call(files, profile.phase, profile.code, title_prefix + profile.phase, browser, previous, expires, now)
        identity = call["turnId"], call["itemId"]
        require(identity not in identities, "call-duplicate-identity")
        identities.add(identity)
        calls.append(call)
        members.update(paths)
        previous = call["completedAtMs"]
    return calls, members


def authenticate_diagnostic_origin(payload_raw, challenge_raw, *, job, payload, challenge, policy_raw, expected_policy_sha256, exporter_sha256, now_ms=None):
    now = milliseconds() if now_ms is None else now_ms
    require(digest(policy_raw) == expected_policy_sha256, "diagnostic-policy-bytes")
    policy = decode(policy_raw)
    broker = policy["broker"]
    require(broker["namespace"] == "roma-native-origin@roma-just-talk"
            and job.repository == REPOSITORY and job.workflow == ".github/workflows/roma-native-challenge-probe.yml"
            and job.job_name == "Collect original native calls", "diagnostic-profile")
    files = archive_snapshot(payload_raw, payload.sha256, payload.size)
    request_raw = challenge_snapshot(challenge_raw, challenge, 65536)
    require(files.get("challenge.json") == request_raw, "response-challenge-substitution")
    request = decode(request_raw)
    require(all(request.get(key) == value for key, value in job.identity().items())
            and request.get("policySha256") == expected_policy_sha256 and request.get("target") == policy["target"], "diagnostic-context")
    created, expires = request["createdAtMs"], request["expiresAtMs"]
    require(type(created) is int and type(expires) is int and job.started_ms <= created <= now
            and expires - created == 900000, "diagnostic-window")
    nonce = request["nonce"]
    require(re.fullmatch(r"[0-9a-f]{32}", nonce) and request["titlePrefix"] == "Roma-native-" + nonce + " ", "diagnostic-nonce")
    from .schema import CallProfile
    profiles = tuple(CallProfile(phase, policy["codes"][phase]) for phase in ("before", "action", "after"))
    calls, members = calls_from_profiles(files, profiles, request["titlePrefix"], policy["browser"], created, expires, now)
    origin = decode(files["broker-origin.json"])
    expected_keys = {"schemaVersion", "brokerIdentity", "namespace", "repository", "workflow", "jobName", "runId", "runAttempt",
                     "jobId", "toolingSha", "exporterSha256", "policySha256", "nonce", "target", "collectionStartedAtMs",
                     "collectionEndedAtMs", "signedAtMs", "calls", "files", "publicationEligible"}
    object_with_keys(origin, expected_keys, "diagnostic-envelope")
    require(all(origin.get(key) == value for key, value in job.identity().items()) and origin["schemaVersion"] == 1
            and origin["brokerIdentity"] == broker["identity"] and origin["namespace"] == broker["namespace"]
            and origin["policySha256"] == expected_policy_sha256 and origin["exporterSha256"] == exporter_sha256
            and origin["nonce"] == nonce and origin["target"] == policy["target"] and origin["calls"] == calls
            and origin["publicationEligible"] is False, "diagnostic-envelope-binding")
    started, ended, signed = (origin[key] for key in ("collectionStartedAtMs", "collectionEndedAtMs", "signedAtMs"))
    require(all(type(value) is int for value in (started, ended, signed)) and created <= started <= ended <= signed < expires
            and signed <= min(now, job.completed_ms), "diagnostic-collection-window")
    members.update({"challenge.json", "broker-execution.json"})
    members.update(f"guest-{phase}{suffix}" for phase in ("before", "after") for suffix in (".json", "-mapped-paths.txt", "-process.txt"))
    inventory_sha = signed_inventory(files, origin, members, broker["identity"], broker["namespace"], broker["publicKey"])
    return DiagnosticOrigin(inventory_sha, job.run_id, job.job_id)


def unopened_request(raw, expected, policy, now):
    request = object_with_keys(decode(raw), {"schemaVersion", "contract", "context", "nonce", "titlePrefix", "createdAtMs", "expiresAtMs",
                                                "policySha256", "exporterSha256", "collectorSha256"}, "unopened-request-fields")
    require(request["schemaVersion"] == 1 and type(request["schemaVersion"]) is int and request["contract"] == CONTRACT,
            "production-request-contract")
    require(request["context"] == expected.identity() and request["policySha256"] == policy.policy_sha256
            and request["exporterSha256"] == policy.exporter_sha256 and request["collectorSha256"] == policy.collector_sha256,
            "production-request-context")
    nonce = request["nonce"]
    require(isinstance(nonce, str) and re.fullmatch(r"[0-9a-f]{32}", nonce)
            and request["titlePrefix"] == "Roma-first-open-" + nonce + " ", "production-request-nonce")
    created, expires = request["createdAtMs"], request["expiresAtMs"]
    require(type(created) is int and type(expires) is int and expected.job.started_ms <= created <= now
            and 0 < expires - created <= 900000, "production-request-window")
    return request


def observer_first_process(files, request, expected, calls, collection_ended_ms, execution):
    clock = object_with_keys(decode(files["observer/clock.json"]), {"schemaVersion", "nonce", "samples"}, "clock-fields")
    require(type(clock["schemaVersion"]) is int and clock["schemaVersion"] == 1 and clock["nonce"] == request["nonce"] and isinstance(clock["samples"], list)
            and len(clock["samples"]) == 2, "clock-samples")
    low, high, previous = -10 ** 20, 10 ** 20, None
    for sample in clock["samples"]:
        object_with_keys(sample, {"controllerBeforeMs", "controllerAfterMs", "guestUtcMs", "guestMonotonicMs"}, "clock-sample-fields")
        require(all(type(value) is int for value in sample.values()), "clock-sample-types")
        before, after, guest, monotonic = (sample[key] for key in ("controllerBeforeMs", "controllerAfterMs", "guestUtcMs", "guestMonotonicMs"))
        require(request["createdAtMs"] <= before <= after <= collection_ended_ms and after - before <= 2000, "clock-window")
        if previous:
            require(previous[1] <= before and before - previous[1] <= monotonic - previous[2] <= after - previous[0], "clock-monotonic-mismatch")
        previous = before, after, monotonic
        low, high = max(low, before - guest), min(high, after - guest)
    require(low <= high, "clock-offset-unproved")
    require(execution["startedAtMs"] <= clock["samples"][0]["controllerBeforeMs"]
            and clock["samples"][1]["controllerAfterMs"] <= execution["completedAtMs"], "observer-outside-collector")
    ready = object_with_keys(decode(files["observer/readiness.json"]), {"schemaVersion", "nonce", "bootUuid", "scanCompletedGuestMs",
                            "acknowledgedControllerMs", "initialScanExitStatus", "initialPids", "logStartedGuestMs", "crashBaselineGuestMs"}, "readiness-fields")
    open_call = next(call for call in calls if call["phase"] == "finder-open")
    require(type(ready["schemaVersion"]) is int and ready["schemaVersion"] == 1 and ready["nonce"] == request["nonce"] and ready["bootUuid"] == expected.boot_uuid
            and type(ready["initialScanExitStatus"]) is int and ready["initialScanExitStatus"] == 0 and ready["initialPids"] == [], "observer-not-unopened")
    require(all(type(ready[key]) is int for key in ("scanCompletedGuestMs", "acknowledgedControllerMs", "logStartedGuestMs", "crashBaselineGuestMs")), "readiness-times")
    require(request["createdAtMs"] <= ready["logStartedGuestMs"] + low <= ready["scanCompletedGuestMs"] + low
            and request["createdAtMs"] <= ready["crashBaselineGuestMs"] + low <= ready["scanCompletedGuestMs"] + low
            and clock["samples"][0]["controllerAfterMs"] <= ready["scanCompletedGuestMs"] + low
            and ready["scanCompletedGuestMs"] + high <= ready["acknowledgedControllerMs"] <= open_call["startedAtMs"], "sampler-after-open")
    observed = object_with_keys(decode(files["observer/process-events.json"]), {"schemaVersion", "nonce", "bootUuid", "events"}, "process-event-fields")
    require(type(observed["schemaVersion"]) is int and observed["schemaVersion"] == 1 and observed["nonce"] == request["nonce"] and observed["bootUuid"] == expected.boot_uuid
            and isinstance(observed["events"], list) and 2 <= len(observed["events"]) <= 20000, "process-event-context")
    first, previous_time, previous_monotonic = None, 0, -1
    for event in observed["events"]:
        object_with_keys(event, {"pid", "startTimeMs", "observedGuestMs", "observedMonotonicMs", "state", "executableSha256", "manifestSha256"}, "process-event-shape")
        require(positive(event["pid"]) and positive(event["startTimeMs"]) and type(event["observedGuestMs"]) is int
                and type(event["observedMonotonicMs"]) is int and event["startTimeMs"] <= event["observedGuestMs"]
                and isinstance(event["state"], str) and re.fullmatch(r"[IRSTUZ][A-Za-z<>+]*", event["state"]), "process-event-types")
        require(previous_time <= event["observedGuestMs"] and previous_monotonic <= event["observedMonotonicMs"]
                and open_call["startedAtMs"] <= event["startTimeMs"] + low
                and event["observedGuestMs"] + high <= collection_ended_ms, "process-event-window")
        require(clock["samples"][0]["guestMonotonicMs"] <= event["observedMonotonicMs"] <= clock["samples"][1]["guestMonotonicMs"], "process-event-clock")
        identity = event["pid"], event["startTimeMs"], event["executableSha256"], event["manifestSha256"]
        require(first is None or identity == first, "first-process-replaced")
        require(event["executableSha256"] == expected.final.executable_sha256 and event["manifestSha256"] == expected.final.manifest_sha256,
                "first-process-byte-identity")
        first, previous_time, previous_monotonic = identity, event["observedGuestMs"], event["observedMonotonicMs"]
    events = observed["events"]
    require(events[-1]["observedMonotonicMs"] - events[0]["observedMonotonicMs"] >= 60000
            and not any(char in events[-1]["state"] for char in "TZX")
            and events[-1]["observedGuestMs"] + high <= clock["samples"][1]["controllerBeforeMs"]
            and next(call for call in calls if call["phase"] == "smoke")["completedAtMs"] <= events[-1]["observedGuestMs"] + low,
            "first-process-not-stable")
    return FirstProcess(first[0], first[1], expected.boot_uuid, first[2])


def runtime_continuity(files, first):
    result = object_with_keys(decode(files["manual-whisper-smoke/result.json"]), {"runtimeProcess", "beforeProcess", "afterProcess"}, "smoke-identity-fields")
    identity = {"pid": first.pid, "startTimeMs": first.start_time_ms, "bootUuid": first.boot_uuid, "executableSha256": first.executable_sha256}
    require(result["runtimeProcess"] == "same-first-process" and result["beforeProcess"] == result["afterProcess"] == identity, "smoke-process-replaced")
    baseline = decode(files["manual-whisper-smoke/baseline-query.stdout"])
    after = decode(files["manual-whisper-smoke/result-query.stdout"])
    require(isinstance(baseline, list) and isinstance(after, list) and all(isinstance(row, dict) and positive(row.get("id")) for row in baseline + after), "smoke-query-shape")
    before_ids = {row["id"] for row in baseline}
    require(len(before_ids) == len(baseline) and len({row["id"] for row in after}) == len(after)
            and any(row["id"] not in before_ids for row in after), "smoke-no-new-record")


def authenticate_native_row(payload_raw, challenge_raw, *, expected, policy, now_ms=None):
    now = milliseconds() if now_ms is None else now_ms
    require(expected.row in OS_ROWS and expected.job.repository == REPOSITORY and expected.job.workflow == WORKFLOW
            and expected.job.job_name == OS_ROWS[expected.row][3] and expected.final.bundle_id == "com.negentropi.RomaJustTalk",
            "production-expected-context")
    require(policy.namespace == NAMESPACE and tuple(profile.phase for profile in policy.calls) in
            (PHASES, PHASES[:3] + ("normal-open-dialog",) + PHASES[3:]), "production-policy-profile")
    files = archive_snapshot(payload_raw, expected.payload.sha256, expected.payload.size, policy.max_transport_bytes)
    request_raw = challenge_snapshot(challenge_raw, expected.challenge, 65536)
    require(files.get("challenge.json") == request_raw, "response-challenge-substitution")
    request = unopened_request(request_raw, expected, policy, now)
    origin = object_with_keys(decode(files.get("broker-origin.json", b"{}")), {"schemaVersion", "contract", "brokerIdentity", "namespace",
                   "context", "challengeArtifactId", "requestSha256", "policySha256", "exporterSha256", "collectorSha256",
                   "collectionStartedAtMs", "collectionEndedAtMs", "signedAtMs", "calls", "files"}, "production-envelope-fields")
    require(type(origin["schemaVersion"]) is int and origin["schemaVersion"] == 1 and origin["contract"] == CONTRACT
            and origin["brokerIdentity"] == policy.identity and origin["namespace"] == policy.namespace
            and origin["context"] == expected.identity() and origin["challengeArtifactId"] == expected.challenge.artifact_id
            and origin["requestSha256"] == digest(request_raw) and origin["policySha256"] == policy.policy_sha256
            and origin["exporterSha256"] == policy.exporter_sha256 and origin["collectorSha256"] == policy.collector_sha256, "production-envelope-binding")
    started, ended, signed = (origin[key] for key in ("collectionStartedAtMs", "collectionEndedAtMs", "signedAtMs"))
    require(all(type(value) is int for value in (started, ended, signed)) and request["createdAtMs"] <= started <= ended <= signed < request["expiresAtMs"]
            and signed <= min(now, expected.job.completed_ms), "production-collection-window")
    calls, members = calls_from_profiles(files, policy.calls, request["titlePrefix"], policy.browser(), started, ended + 1, now)
    require(origin["calls"] == calls, "production-call-inventory")
    members.update(ROW_FILES)
    require(members <= set(files), "production-receipt-missing")
    inventory_sha = signed_inventory(files, origin, members, policy.identity, policy.namespace, policy.public_key)
    execution = object_with_keys(decode(files["broker-execution.json"]), {"schemaVersion", "transportIdentity", "collectorSha256", "argv",
                           "startedAtMs", "completedAtMs", "exitStatus", "timedOut", "stdoutSha256", "stderrSha256"}, "collector-execution-fields")
    require(type(execution["schemaVersion"]) is int and execution["schemaVersion"] == 1 and execution["transportIdentity"] == policy.transport_identity
            and execution["collectorSha256"] == policy.collector_sha256 and execution["argv"] == list(policy.collector_argv)
            and type(execution["exitStatus"]) is int and execution["exitStatus"] == 0 and execution["timedOut"] is False
            and execution["stdoutSha256"] == digest(files["collector.stdout"]) and execution["stderrSha256"] == digest(files["collector.stderr"]), "collector-execution-origin")
    require(type(execution["startedAtMs"]) is int and type(execution["completedAtMs"]) is int
            and started <= execution["startedAtMs"] <= execution["completedAtMs"] <= ended, "collector-execution-window")
    first = observer_first_process(files, request, expected, calls, ended, execution)
    runtime_continuity(files, first)
    admitted = MappingProxyType({name: files[name] for name in members})
    return AuthenticatedNativeRow(first, inventory_sha, admitted)
