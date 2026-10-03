#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 || ! "$2" =~ ^[A-Z0-9]{10}$ || ! "$3" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
  echo "usage: $0 <app> <expected-developer-id-team> <expected-signing-identifier> <evidence-directory>" >&2
  exit 2
fi
python3 - "$@" <<'PY'
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

app, team, identifier, directory = sys.argv[1:]
app = os.path.abspath(app)
evidence = Path(directory)
evidence.mkdir(parents=True, exist_ok=True)
receipt_path = evidence / 'trust-command-receipts.json'
if receipt_path.exists() or (evidence / 'trust-verdict.txt').exists():
    sys.exit('Trust evidence already exists')
requirement = ('=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
               'and certificate 1[field.1.2.840.113635.100.6.2.6] exists '
               f'and certificate leaf[subject.OU] = "{team}" and identifier "{identifier}"')
commands = [
    ('codesign-verify', 'developer-id-verification', ['codesign', '--verify', '--deep', '--strict', '--test-requirement=' + requirement, app]),
    ('codesign-display', 'signature', ['codesign', '--display', '--verbose=4', app]),
    ('stapler-validate', 'stapled-ticket', ['xcrun', 'stapler', 'validate', app]),
    ('gatekeeper-assess', 'gatekeeper-assessment', ['spctl', '--assess', '--type', 'execute', '--verbose=4', app]),
]
for _, output_name, _ in commands:
    for suffix in ('.stdout', '.stderr', '.txt'):
        if (evidence / (output_name + suffix)).exists():
            sys.exit('Trust command output already exists')
receipt = {'schemaVersion': 1, 'app': app, 'developerIdTeam': team, 'signingIdentifier': identifier, 'commands': []}
with receipt_path.open('x', encoding='utf-8') as stream:
    json.dump(receipt, stream, indent=2)
for name, output_name, argv in commands:
    command = {'name': name, 'argv': argv, 'startedAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'), 'timedOut': False}
    stdout_path, stderr_path = (evidence / (output_name + '.' + channel) for channel in ('stdout', 'stderr'))
    with stdout_path.open('xb') as stdout, stderr_path.open('xb') as stderr:
        try:
            process = subprocess.Popen(argv, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                command['exitStatus'] = process.wait(timeout=120)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                command['exitStatus'] = process.wait()
                command['timedOut'] = True
        except OSError as error:
            command['exitStatus'] = None
            command['error'] = type(error).__name__
    command['endedAt'] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    for channel, path in (('stdout', stdout_path), ('stderr', stderr_path)):
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        command[channel] = {'path': path.name, 'sha256': digest.hexdigest(), 'size': path.stat().st_size}
    with (evidence / (output_name + '.txt')).open('xb') as stream:
        for path in (stdout_path, stderr_path):
            with path.open('rb') as source:
                shutil.copyfileobj(source, stream)
    receipt['commands'].append(command)
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    if command['exitStatus'] != 0 or command['timedOut'] or (evidence / (output_name + '.txt')).stat().st_size > 16 * 1024 * 1024:
        sys.exit(f'Trust command failed: {name}')
    combined = (evidence / (output_name + '.txt')).read_bytes()
    if name == 'codesign-display' and re.search(rb'^CodeDirectory .*flags=.*\(.*runtime.*\)', combined, re.M) is None:
        sys.exit('Hardened Runtime signature is missing')
    if name == 'gatekeeper-assess' and (b'source=Notarized Developer ID' not in combined.splitlines() or re.search(rb'^override=', combined, re.M)):
        sys.exit('Gatekeeper notarized assessment is missing or used a policy override')
with (evidence / 'trust-verdict.txt').open('x', encoding='utf-8') as stream:
    stream.write(f'trust_verdict=passed\ndeveloper_id_team={team}\nsigning_identifier={identifier}\n')
PY
