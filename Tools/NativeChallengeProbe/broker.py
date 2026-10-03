#!/usr/bin/env python3
import argparse
import base64
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

import native_challenge as protocol


ROOT = Path(__file__).resolve().parent
EXPORTER = Path('/Users/atalphalnmomhappyhouse/.codex/task-artifacts/roma-macos-proof/controller-export/export-native-cua-history.py')
EXPORTER_SHA = '69f7afdc99ff35b19440b1ade5cc8bc84101bfe0dd2dbec2c83fb425d7292d2e'
PYTHON = '/Users/atalphalnmomhappyhouse/.pyenv/versions/3.11.9/bin/python3'
SOURCE_PREFIX = 'Tools/NativeChallengeProbe/'


class GitHub:
    def __init__(self, case):
        self.case = case
        self.sequence = 0

    def get(self, endpoint):
        self.sequence += 1
        prefix = self.case / f'api-{self.sequence:02d}'
        with prefix.with_suffix('.stdout').open('xb') as stdout, prefix.with_suffix('.stderr').open('xb') as stderr:
            command = ['gh', 'api', endpoint]
            process = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                result = process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, 9)
                process.wait(timeout=3)
                raise protocol.Rejected('github-read-timeout') from None
        protocol.write(prefix.with_suffix('.json'), protocol.encoded({'argv': command, 'exitCode': result}))
        protocol.require(result == 0, 'github-read-failed')
        data = protocol.read(prefix.with_suffix('.stdout'))
        protocol.require(len(data) <= 1_048_576, 'github-read-size')
        return data

    def json(self, endpoint):
        return json.loads(self.get(endpoint))

    def source(self, name, sha):
        record = self.json(f'repos/{protocol.REPOSITORY}/contents/{SOURCE_PREFIX}{name}?ref={sha}')
        protocol.require(record.get('encoding') == 'base64', 'github-source-encoding')
        return base64.b64decode(record['content'].replace('\n', ''), validate=True)


def get_active(api, run_id, attempt, sha):
    run = api.json(f'repos/{protocol.REPOSITORY}/actions/runs/{run_id}')
    jobs = api.json(f'repos/{protocol.REPOSITORY}/actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100')
    job = protocol.active_job(run, jobs, sha, run_id, attempt)
    return run, job


def challenge_artifact(api, run_id, attempt, sha, job):
    record = api.json(f'repos/{protocol.REPOSITORY}/actions/runs/{run_id}/artifacts?per_page=100')
    artifacts = record.get('artifacts')
    protocol.require(isinstance(artifacts, list) and record.get('total_count') == len(artifacts), 'truncated-artifact-inventory')
    selected = [entry for entry in artifacts if entry.get('name') == f'roma.native.challenge.{run_id}.{attempt}']
    protocol.require(len(selected) == 1, 'challenge-artifact-count')
    artifact = selected[0]
    protocol.require(artifact.get('expired') is False and artifact.get('workflow_run', {}).get('id') == run_id
                     and artifact.get('workflow_run', {}).get('head_sha') == sha
                     and 0 < artifact.get('size_in_bytes', 0) <= 262144
                     and protocol.timestamp(artifact['created_at']) >= protocol.timestamp(job['started_at']), 'challenge-artifact-identity')
    data = api.get(f'repos/{protocol.REPOSITORY}/actions/artifacts/{artifact["id"]}/zip')
    protocol.require(len(data) == artifact['size_in_bytes'] and 'sha256:' + protocol.digest(data) == artifact.get('digest'), 'challenge-artifact-bytes')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        items = archive.infolist()
        protocol.require(len(items) == 1 and items[0].filename == 'challenge.json'
                         and items[0].file_size <= 65536 and not items[0].flag_bits & 1
                         and (items[0].external_attr >> 16) & 0o170000 != 0o120000, 'challenge-artifact-layout')
        return archive.read(items[0])


def main():
    parser = argparse.ArgumentParser(description='Fixed read-only GitHub/native-history broker. No GUI action or Git write.')
    parser.add_argument('mode', choices=('arm', 'export'))
    parser.add_argument('--case', type=Path, required=True)
    parser.add_argument('--sha')
    parser.add_argument('--run-id', type=int)
    parser.add_argument('--attempt', type=int)
    parser.add_argument('--guest', type=Path)
    parser.add_argument('--turn-id')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        case = args.case.resolve()
        protocol.require(case.is_relative_to(ROOT / 'cases') and case != ROOT / 'cases', 'broker-case-scope')
        if args.mode == 'arm':
            protocol.require(re.fullmatch(r'[0-9a-f]{40}', args.sha or '') and args.run_id and args.attempt, 'broker-inputs')
            case.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            case.mkdir(mode=0o700)
            api = GitHub(case)
            for name in ('native_challenge.py', 'broker.py'):
                protocol.require(api.source(name, args.sha) == protocol.read(ROOT / name), 'broker-code-differs-from-reviewed-head')
            policy_bytes = api.source('policy.json', args.sha)
            policy = json.loads(policy_bytes)
            run, job = get_active(api, args.run_id, args.attempt, args.sha)
            challenge_bytes = challenge_artifact(api, args.run_id, args.attempt, args.sha, job)
            challenge = json.loads(challenge_bytes)
            protocol.challenge_check(challenge, policy, policy_bytes, args.sha, args.run_id, args.attempt)
            protocol.require(challenge['jobId'] == job['id'], 'challenge-job-mismatch')
            protocol.write(case / 'policy.json', policy_bytes)
            protocol.write(case / 'challenge.json', challenge_bytes)
            protocol.write(case / 'arm.json', protocol.encoded({'sha': args.sha, 'runId': args.run_id, 'attempt': args.attempt,
                'localSourceSha256': {name: protocol.digest(protocol.read(ROOT / name)) for name in ('native_challenge.py', 'broker.py')}}))
            print(json.dumps({'state': 'armed', 'publicationEligible': False, 'titlePrefix': challenge['titlePrefix'],
                              'expiresAtMs': challenge['expiresAtMs'], 'codes': policy['codes'], 'target': policy['target']}))
        else:
            protocol.require(args.guest is not None and args.guest.is_dir() and not args.guest.is_symlink(), 'broker-guest-input')
            arm = protocol.load(case / 'arm.json')
            protocol.require(arm.get('localSourceSha256') == {name: protocol.digest(protocol.read(ROOT / name))
                             for name in ('native_challenge.py', 'broker.py')}, 'broker-source-changed-after-arm')
            policy_bytes = protocol.read(case / 'policy.json')
            policy = json.loads(policy_bytes)
            challenge_bytes = protocol.read(case / 'challenge.json')
            challenge = json.loads(challenge_bytes)
            protocol.challenge_check(challenge, policy, policy_bytes, arm['sha'], arm['runId'], arm['attempt'])
            api_dir = case / 'export-api'
            api_dir.mkdir(mode=0o700)
            api = GitHub(api_dir)
            _, job = get_active(api, arm['runId'], arm['attempt'], arm['sha'])
            protocol.require(job['id'] == challenge['jobId'], 'export-job-mismatch')
            protocol.require(protocol.digest(protocol.read(EXPORTER)) == EXPORTER_SHA, 'exporter-source-changed')
            export = EXPORTER.parent / ('native-job-' + challenge['nonce'])
            command = [PYTHON, str(EXPORTER), '--case', str(export), '--thread', protocol.THREAD,
                       '--title-prefix', challenge['titlePrefix'], '--since',
                       datetime_utc(challenge['createdAtMs']), '--expected-count', '3', '--max-read-pages', '8']
            if args.turn_id:
                command += ['--turn-id', args.turn_id]
            with (case / 'export.stdout').open('xb') as stdout, (case / 'export.stderr').open('xb') as stderr:
                process = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True)
                try:
                    result = process.wait(timeout=330)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, 15)
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, 9)
                        process.wait(timeout=3)
                    raise protocol.Rejected('exporter-timeout') from None
            protocol.write(case / 'export-execution.json', protocol.encoded({'argv': command, 'exitCode': result, 'privateExport': str(export)}))
            protocol.require(result == 0, 'exporter-exit-nonzero')
            protocol.challenge_check(challenge, policy, policy_bytes, arm['sha'], arm['runId'], arm['attempt'])
            protocol.prepare_response(export, args.guest, case / 'response', challenge, challenge_bytes, policy, policy_bytes, EXPORTER_SHA)
            print(json.dumps({'state': 'diagnostic-response-staged', 'publicationEligible': False,
                              'responseRef': challenge['responseRef'], 'responseDirectory': str(case / 'response')}))
        return 0
    except (protocol.Rejected, OSError, ValueError, TypeError, KeyError, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        print(json.dumps({'state': 'rejected', 'reason': str(error) if isinstance(error, protocol.Rejected) else type(error).__name__, 'publicationEligible': False}))
        return 1


def datetime_utc(milliseconds):
    from datetime import datetime, timezone
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc).isoformat(timespec='milliseconds')


if __name__ == '__main__':
    sys.exit(main())
