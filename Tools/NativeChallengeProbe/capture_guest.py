#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description='Read-only live guest PID and archive observation for a diagnostic challenge.')
    parser.add_argument('--phase', choices=('before', 'after'), required=True)
    parser.add_argument('--nonce', required=True)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--zip', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    if not re.fullmatch(r'[0-9a-f]{32}', args.nonce) or args.pid <= 0:
        parser.error('invalid challenge or PID')
    root = Path('/Volumes/My Shared Files/proof/native-challenge') / args.nonce
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    records = []
    def command(argv):
        result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        records.append({'argv': argv, 'stdout': result.stdout, 'stderr': result.stderr, 'exitCode': result.returncode})
        if result.returncode:
            raise RuntimeError('guest command failed')
        return result.stdout.strip()
    result = {'schemaVersion': 1, 'phase': args.phase, 'nonce': args.nonce, 'startedAt': datetime.now(timezone.utc).isoformat()}
    status = 1
    try:
        process = command(['ps', '-p', str(args.pid), '-o', 'pid=', '-o', 'lstart=', '-o', 'state=', '-o', 'command='])
        state = command(['ps', '-p', str(args.pid), '-o', 'stat='])
        mapped = command(['lsof', '-a', '-p', str(args.pid), '-d', 'txt', '-Fn'])
        candidates = [line[1:] for line in mapped.splitlines() if line.startswith('n/') and line.endswith('/Contents/MacOS/roma just talk')]
        if len(candidates) != 1 or any(char in state for char in 'TZX'):
            raise RuntimeError('guest process is not usable')
        executable = Path(candidates[0])
        zip_hash = command(['shasum', '-a', '256', str(args.zip)]).split()[0]
        executable_hash = command(['shasum', '-a', '256', str(executable)]).split()[0]
        target = {'productVersion': command(['sw_vers', '-productVersion']), 'buildVersion': command(['sw_vers', '-buildVersion']),
                  'architecture': command(['uname', '-m']), 'bootUuid': command(['sysctl', '-n', 'kern.bootsessionuuid']),
                  'firstPid': args.pid, 'executableSha256': executable_hash, 'finalZipSha256': zip_hash}
        result.update({'target': target, 'gatekeeper': command(['spctl', '--status']), 'sip': command(['csrutil', 'status']),
                       'processState': state, 'processExecutable': str(executable)})
        for name, data in [(f'guest-{args.phase}-process.txt', process), (f'guest-{args.phase}-mapped-paths.txt', mapped)]:
            with (root / name).open('xb') as stream:
                stream.write((data + '\n').encode())
        status = 0
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        result['error'] = type(error).__name__
    result['commandResults'] = records
    result['exitCode'] = status
    result['completedAt'] = datetime.now(timezone.utc).isoformat()
    with (root / f'guest-{args.phase}.json').open('xb') as stream:
        stream.write((json.dumps(result, indent=2) + '\n').encode())
    print(json.dumps({'state': 'observed' if status == 0 else 'failed', 'phase': args.phase, 'nonce': args.nonce, 'publicationEligible': False}))
    return status


if __name__ == '__main__':
    sys.exit(main())
