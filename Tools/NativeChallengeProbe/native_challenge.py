#!/usr/bin/env python3
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import sys
import warnings

from PIL import Image, ImageStat


REPOSITORY = "negentropi/roma-just-talk"
WORKFLOW = ".github/workflows/roma-native-challenge-probe.yml"
JOB = "Collect original native calls"
THREAD = "01a0de81-d14c-7670-b36d-7b045ff3c6d0"
PHASES = ("before", "action", "after")
MAX_FILE = 32 * 1024 * 1024


class Rejected(Exception):
    pass


def require(value, reason):
    if not value:
        raise Rejected(reason)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_FILE, "file-admission")
    return path.read_bytes()


def load(path):
    return json.loads(read(path))


def write(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def now_ms():
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def timestamp(value):
    require(isinstance(value, str), "timestamp-type")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None, "timestamp-timezone")
    return int(parsed.timestamp() * 1000)


def member(root, relative):
    require(isinstance(relative, str) and relative and not PurePosixPath(relative).is_absolute()
            and all(part not in (".", "..") for part in relative.split("/")), "unsafe-relative-path")
    path = root / relative
    require(path.resolve().is_relative_to(root.resolve()), "escaped-relative-path")
    for parent in [path, *path.parents]:
        if parent == root:
            break
        require(not parent.is_symlink(), "symlink-evidence")
    return path


def policy_check(policy):
    require(type(policy.get("schemaVersion")) is int and policy["schemaVersion"] == 1
            and policy.get("threadId") == THREAD, "policy-thread")
    require(set(policy.get("codes", {})) == set(PHASES)
            and all(isinstance(policy["codes"][phase], str) and 0 < len(policy["codes"][phase]) < 2000 for phase in PHASES), "policy-code-profile")
    require(policy["codes"]["before"] == policy["codes"]["after"] == "await currentVm.getAXStateAndScreenshot();"
            and re.fullmatch(r"await currentVm\.click\(\[[0-9]{1,4}, ?[0-9]{1,4}\]\); await currentVm\.getAXStateAndScreenshot\(\);", policy["codes"]["action"]), "policy-code-not-supported")
    browser = policy.get("browser", {})
    url = re.fullmatch(r"http://127\.0\.0\.1:([0-9]{1,5})/vnc\.html", browser.get("url", ""))
    require(browser.get("backend") == "iab" and re.fullmatch(r"[0-9]+", browser.get("browserId", ""))
            and url and 1 <= int(url.group(1)) <= 65535, "policy-browser")
    target = policy.get("target", {})
    require(target.get("productVersion") == "26.4.1" and target.get("buildVersion") == "25E253"
            and target.get("architecture") == "arm64" and type(target.get("firstPid")) is int and target["firstPid"] > 0
            and re.fullmatch(r"[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", target.get("bootUuid", "")), "policy-guest")
    for key in ("executableSha256", "finalZipSha256"):
        require(re.fullmatch(r"[0-9a-f]{64}", target.get(key, "")), "policy-byte-identity")


def active_job(run, jobs, expected_sha, run_id, attempt):
    require(run.get("id") == run_id and run.get("run_attempt") == attempt
            and run.get("repository", {}).get("full_name") == REPOSITORY
            and run.get("head_repository", {}).get("full_name") == REPOSITORY
            and run.get("head_sha") == expected_sha and run.get("path", "").split("@")[0] == WORKFLOW
            and run.get("status") == "in_progress" and run.get("conclusion") is None
            and run.get("event") in ("push", "workflow_dispatch"), "active-run-identity")
    branch = run.get("head_branch", "")
    require(run["event"] != "push" or branch.startswith("ci/roma-native-challenge-"), "untrusted-push-branch")
    require(isinstance(jobs.get("jobs"), list) and jobs.get("total_count") == len(jobs["jobs"]), "truncated-job-inventory")
    selected = [job for job in jobs["jobs"] if job.get("name") == JOB]
    require(len(selected) == 1, "missing-or-duplicate-job")
    job = selected[0]
    require(type(job.get("id")) is int and job["id"] > 0 and job.get("run_id") == run_id
            and job.get("run_attempt") == attempt and job.get("status") == "in_progress"
            and job.get("conclusion") is None and type(job.get("runner_id")) is int and job["runner_id"] > 0,
            "active-job-identity")
    return job


def make_challenge(policy, policy_bytes, run, jobs, sha, run_id, attempt):
    policy_check(policy)
    job = active_job(run, jobs, sha, run_id, attempt)
    created = now_ms()
    require(timestamp(job["started_at"]) <= created <= timestamp(job["started_at"]) + 300_000, "challenge-job-window")
    nonce = secrets.token_hex(16)
    return {"schemaVersion": 1, "repository": REPOSITORY, "workflow": WORKFLOW, "jobName": JOB,
            "runId": run_id, "runAttempt": attempt, "jobId": job["id"], "toolingSha": sha,
            "nonce": nonce, "titlePrefix": f"Roma-native-{nonce} ", "createdAtMs": created,
            "expiresAtMs": created + 900_000, "policySha256": digest(policy_bytes), "target": policy["target"],
            "responseRef": f"ci/roma-native-response-{run_id}-{attempt}-{nonce}"}


def challenge_check(challenge, policy, policy_bytes, sha, run_id, attempt, clock=None):
    policy_check(policy)
    require(challenge.get("schemaVersion") == 1 and challenge.get("repository") == REPOSITORY
            and challenge.get("workflow") == WORKFLOW and challenge.get("jobName") == JOB
            and challenge.get("toolingSha") == sha and challenge.get("runId") == run_id
            and challenge.get("runAttempt") == attempt and type(challenge.get("jobId")) is int
            and challenge["jobId"] > 0, "challenge-origin")
    require(challenge.get("policySha256") == digest(policy_bytes) and challenge.get("target") == policy["target"], "challenge-policy")
    nonce = challenge.get("nonce", "")
    require(re.fullmatch(r"[0-9a-f]{32}", nonce) and challenge.get("titlePrefix") == f"Roma-native-{nonce} "
            and challenge.get("responseRef") == f"ci/roma-native-response-{run_id}-{attempt}-{nonce}", "challenge-shape")
    created, expires = challenge.get("createdAtMs"), challenge.get("expiresAtMs")
    require(type(created) is int and type(expires) is int and expires - created == 900_000, "challenge-lifetime")
    current = now_ms() if clock is None else clock
    require(created <= current < expires, "challenge-expired-or-future")


def guest_check(root, challenge, policy, calls):
    target = policy["target"]
    process_identity = None
    for phase in ("before", "after"):
        guest = load(root / f"guest-{phase}.json")
        started, completed = timestamp(guest.get("startedAt")), timestamp(guest.get("completedAt"))
        require(challenge["createdAtMs"] <= started <= completed < challenge["expiresAtMs"]
                and (completed <= calls[0]["startedAtMs"] if phase == "before"
                     else started >= calls[-1]["completedAtMs"]), "guest-stale-or-unordered")
        require(guest.get("target") == target and guest.get("gatekeeper") == "assessments enabled"
                and guest.get("sip") == "System Integrity Protection status: enabled."
                and isinstance(guest.get("processState"), str) and guest["processState"]
                and not any(char in guest["processState"] for char in "TZX"), "guest-identity-or-protection")
        require(guest.get("phase") == phase and guest.get("nonce") == challenge["nonce"]
                and guest.get("exitCode") == 0 and isinstance(guest.get("commandResults"), list)
                and guest["commandResults"] and all(command.get("exitCode") == 0 for command in guest["commandResults"]), "guest-command-failed-or-marker-only")
        commands = {tuple(command["argv"]): command["stdout"].strip() for command in guest["commandResults"]}
        require(len(commands) == len(guest["commandResults"]), "guest-duplicate-command")
        for argv, value in [(('sw_vers', '-productVersion'), target['productVersion']),
                            (('sw_vers', '-buildVersion'), target['buildVersion']),
                            (('uname', '-m'), target['architecture']),
                            (('sysctl', '-n', 'kern.bootsessionuuid'), target['bootUuid']),
                            (('spctl', '--status'), guest['gatekeeper']),
                            (('csrutil', 'status'), guest['sip'])]:
            require(commands.get(argv) == value, "guest-raw-command-mismatch")
        mapping = read(root / f"guest-{phase}-mapped-paths.txt").decode()
        executable = guest.get("processExecutable", "")
        require(executable.endswith("/Contents/MacOS/roma just talk") and "n" + executable in mapping.splitlines(), "guest-executable-mapping")
        process = read(root / f"guest-{phase}-process.txt").decode().split(None, 7)
        require(process and process[0] == str(target["firstPid"]), "guest-first-pid")
        require(len(process) == 8, "guest-process-start-missing")
        observed_identity = (tuple(process[:6]), executable)
        require(process_identity is None or observed_identity == process_identity, "guest-process-replaced")
        process_identity = observed_identity
        require(commands.get(('ps', '-p', str(target['firstPid']), '-o', 'pid=', '-o', 'lstart=', '-o', 'state=', '-o', 'command='))
                == read(root / f"guest-{phase}-process.txt").decode().strip()
                and commands.get(('ps', '-p', str(target['firstPid']), '-o', 'stat=')) == guest['processState']
                and commands.get(('lsof', '-a', '-p', str(target['firstPid']), '-d', 'txt', '-Fn')) == mapping.strip(), "guest-process-command-mismatch")
        hashes = [(argv, stdout.split(None, 1)) for argv, stdout in commands.items() if len(argv) == 4 and argv[:3] == ('shasum', '-a', '256')]
        require(len(hashes) == 2 and any(argv[3] == executable and fields[0] == target['executableSha256'] for argv, fields in hashes)
                and any(argv[3].endswith('.zip') and fields[0] == target['finalZipSha256'] for argv, fields in hashes), "guest-raw-hash-mismatch")


def calls_check(root, challenge, policy):
    identities = set()
    previous_end = challenge["createdAtMs"]
    selected = []
    for phase in PHASES:
        entry_bytes = read(root / phase / "original-entry.json")
        entry = json.loads(entry_bytes)
        item = entry.get("item", {})
        arguments = item.get("arguments", {})
        require((item.get("type"), item.get("server"), item.get("tool"), item.get("status"))
                == ("mcpToolCall", "cua_repl", "js", "completed") and item.get("error") is None, "call-incomplete-or-error")
        require(arguments == {"code": policy["codes"][phase], "title": challenge["titlePrefix"] + phase}, "call-profile-or-challenge")
        started, completed = entry.get("startedAtMs"), entry.get("completedAtMs")
        require(type(started) is int and type(completed) is int and previous_end <= started <= completed < challenge["expiresAtMs"]
                and completed <= now_ms(), "call-stale-or-unordered")
        previous_end = completed
        identity = (entry.get("turnId"), item.get("id"))
        require(all(isinstance(value, str) and value for value in identity) and identity not in identities, "call-duplicate-identity")
        identities.add(identity)
        result = item.get("result", {})
        require(isinstance(result, dict) and result.get("isError", False) is False, "call-result-error")
        meta = result.get("_meta", {})
        surface = meta.get("codex/toolSurface", {})
        require(meta.get("browser_use", {}).get("url") == policy["browser"]["url"]
                and surface.get("backend") == policy["browser"]["backend"]
                and surface.get("browserId") == policy["browser"]["browserId"], "call-browser-target")
        content = result.get("content")
        require(isinstance(content, list) and all(isinstance(block, dict) for block in content), "call-content")
        images = []
        for index, block in enumerate(content):
            if block.get("type") != "image":
                continue
            suffix = {"image/png": "png", "image/jpeg": "jpg"}.get(block.get("mimeType"))
            require(suffix is not None, "unsupported-image-mime")
            try:
                data = base64.b64decode(block["data"], validate=True)
            except (KeyError, TypeError, ValueError):
                raise Rejected("invalid-image-base64") from None
            require(0 < len(data) <= MAX_FILE and read(root / phase / f"image-{index:03d}.{suffix}") == data, "substituted-or-missing-image")
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("error", Image.DecompressionBombWarning)
                    with Image.open(io.BytesIO(data)) as image:
                        require(image.format == {"png": "PNG", "jpg": "JPEG"}[suffix] and 0 < image.width * image.height <= 64 * 1024 * 1024, "image-format-or-capacity")
                        image.verify()
                    with Image.open(io.BytesIO(data)) as image:
                        image.load()
                        require(max(ImageStat.Stat(image.convert('RGB')).mean) >= 2, "black-image")
            except Rejected:
                raise
            except Exception:
                raise Rejected("malformed-image") from None
            images.append({"index": index, "sha256": digest(data), "bytes": len(data)})
        require(images, "call-image-missing")
        selected.append({"phase": phase, "turnId": identity[0], "itemId": identity[1],
                         "startedAtMs": started, "completedAtMs": completed,
                         "entrySha256": digest(entry_bytes), "images": images})
    return selected


def prepare_response(export, guest, output, challenge, challenge_bytes, policy, policy_bytes, exporter_sha):
    receipt = load(export / "receipt.json")
    require(receipt.get("threadId") == THREAD and receipt.get("titlePrefix") == challenge["titlePrefix"]
            and receipt.get("sinceMs") == challenge["createdAtMs"] and receipt.get("exporterSha256") == exporter_sha,
            "exporter-request-identity")
    lifecycle = receipt.get("lifecycle", {})
    require(receipt.get("state") == "exported" and lifecycle.get("endpointExitCode") == 0
            and lifecycle.get("remainingOwnedProcesses") == [] and lifecycle.get("errors") == [], "exporter-failed-or-live")
    entries = receipt.get("entries", [])
    require(len(entries) == 3 and {e.get("title") for e in entries} == {challenge["titlePrefix"] + phase for phase in PHASES}, "exporter-call-count")
    output.mkdir(mode=0o700)
    write(output / "challenge.json", challenge_bytes)
    for reference in entries:
        phase = reference["title"][len(challenge["titlePrefix"]):]
        data = read(member(export, reference["entryFile"]))
        require(digest(data) == reference["entrySha256"], "changed-export-entry")
        original = json.loads(data)
        source = reference["sourceResponse"]
        raw = read(member(export, source["file"]))
        require(digest(raw) == source["sha256"] and source["method"] == "thread/items/list", "changed-original-response")
        response = json.loads(raw)
        require(response.get("result", {}).get("data", []).count(original) == 1, "entry-not-in-original-response")
        write(output / phase / "original-entry.json", data)
        for image in reference["images"]:
            image_data = read(member(export, image["file"]))
            require(digest(image_data) == image["sha256"], "changed-export-image")
            write(output / phase / Path(image["file"]).name, image_data)
    for phase in ("before", "after"):
        for suffix in (".json", "-mapped-paths.txt", "-process.txt"):
            name = f"guest-{phase}{suffix}"
            write(output / name, read(guest / name))
    calls = calls_check(output, challenge, policy)
    guest_check(output, challenge, policy, calls)
    write(output / "broker-execution.json", encoded({"schemaVersion": 1, "state": "diagnostic-payload-bound",
          "publicationEligible": False, "threadId": THREAD, "policySha256": digest(policy_bytes),
          "exporterSha256": exporter_sha, "privateReceiptSha256": digest(read(export / "receipt.json")),
          "calls": calls, "createdAtMs": now_ms(), "trustLimit": "Mac broker and guest-command origin are not independently attested"}))
    verify_response(output, challenge_bytes, challenge, policy, policy_bytes, exporter_sha)


def verify_response(root, challenge_bytes, challenge, policy, policy_bytes, exporter_sha):
    require(read(root / "challenge.json") == challenge_bytes, "response-challenge-substitution")
    calls = calls_check(root, challenge, policy)
    guest_check(root, challenge, policy, calls)
    execution = load(root / "broker-execution.json")
    require(execution.get("threadId") == THREAD and execution.get("policySha256") == digest(policy_bytes)
            and execution.get("exporterSha256") == exporter_sha and execution.get("calls") == calls
            and execution.get("publicationEligible") is False, "broker-execution-binding")
    paths = list(root.rglob("*"))
    require(not root.is_symlink() and not any(path.is_symlink() for path in paths), "symlink-evidence")
    files = {str(path.relative_to(root)) for path in paths if path.is_file()}
    expected = {"challenge.json", "broker-execution.json"}
    for phase in ("before", "after"):
        expected.update(f"guest-{phase}{suffix}" for suffix in (".json", "-mapped-paths.txt", "-process.txt"))
    for phase in PHASES:
        expected.add(f"{phase}/original-entry.json")
        entry = load(root / phase / "original-entry.json")
        for index, block in enumerate(entry["item"]["result"]["content"]):
            if block.get("type") == "image":
                suffix = {"image/png": "png", "image/jpeg": "jpg"}[block["mimeType"]]
                expected.add(f"{phase}/image-{index:03d}.{suffix}")
    require(files == expected, "unapproved-response-file")
    require(all((root / name).stat().st_size <= 4 * 1024 * 1024 for name in files)
            and sum((root / name).stat().st_size for name in files) <= 12 * 1024 * 1024, "response-size-bound")
    return {"state": "diagnostic-payload-bound", "publicationEligible": False,
            "runId": challenge["runId"], "jobId": challenge["jobId"], "target": policy["target"], "calls": calls}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("make", "prepare", "verify"))
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--attempt", type=int, required=True)
    parser.add_argument("--run", type=Path)
    parser.add_argument("--jobs", type=Path)
    parser.add_argument("--challenge", type=Path)
    parser.add_argument("--export", type=Path)
    parser.add_argument("--guest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--exporter-sha", required=True)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        require(re.fullmatch(r"[0-9a-f]{40}", args.sha) and re.fullmatch(r"[0-9a-f]{64}", args.exporter_sha)
                and args.run_id > 0 and args.attempt > 0, "cli-identity")
        policy_bytes = read(args.policy)
        policy = json.loads(policy_bytes)
        if args.mode == "make":
            result = make_challenge(policy, policy_bytes, load(args.run), load(args.jobs), args.sha, args.run_id, args.attempt)
            write(args.output, encoded(result))
        else:
            challenge_bytes = read(args.challenge)
            challenge = json.loads(challenge_bytes)
            challenge_check(challenge, policy, policy_bytes, args.sha, args.run_id, args.attempt)
            if args.mode == "prepare":
                prepare_response(args.export, args.guest, args.output, challenge, challenge_bytes, policy, policy_bytes, args.exporter_sha)
                result = {"state": "diagnostic-payload-bound", "publicationEligible": False, "responseRef": challenge["responseRef"]}
            else:
                result = verify_response(args.export, challenge_bytes, challenge, policy, policy_bytes, args.exporter_sha)
                write(args.output, encoded(result))
        print(json.dumps({"state": result.get("state", "challenge-created"), "publicationEligible": False}))
        return 0
    except (Rejected, OSError, ValueError, TypeError, KeyError) as error:
        print(json.dumps({"state": "rejected", "reason": str(error) if isinstance(error, Rejected) else type(error).__name__, "publicationEligible": False}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
