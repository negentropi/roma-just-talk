#!/usr/bin/env python3
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import native_challenge as protocol


def api(endpoint):
    result = subprocess.run(['gh', 'api', endpoint], capture_output=True, timeout=20)
    protocol.require(result.returncode == 0 and len(result.stdout) <= 8 * 1024 * 1024, 'response-api-read')
    return json.loads(result.stdout)


def main():
    os.umask(0o077)
    try:
        commit_sha, parent_sha, directory, receipt_path = sys.argv[1:]
        protocol.require(re.fullmatch(r'[0-9a-f]{40}', commit_sha) and re.fullmatch(r'[0-9a-f]{40}', parent_sha), 'response-commit-shape')
        prefix = f'repos/{protocol.REPOSITORY}/git'
        commit = api(f'{prefix}/commits/{commit_sha}')
        protocol.require(commit.get('sha') == commit_sha and [parent.get('sha') for parent in commit.get('parents', [])] == [parent_sha], 'response-commit-parent')
        protocol.write(Path(receipt_path), protocol.encoded(commit))
        top = api(f'{prefix}/trees/{commit["tree"]["sha"]}')
        protocol.require(top.get('truncated') is False, 'response-tree-truncated')
        roots = [entry for entry in top['tree'] if entry['path'] == 'native-challenge-response']
        protocol.require(len(roots) == 1 and roots[0]['type'] == 'tree', 'response-root')
        tree = api(f'{prefix}/trees/{roots[0]["sha"]}?recursive=1')
        protocol.require(tree.get('truncated') is False and len(tree['tree']) <= 30, 'response-tree-bound')
        blobs = [entry for entry in tree['tree'] if entry.get('type') == 'blob']
        protocol.require(blobs and len({entry['path'] for entry in tree['tree']}) == len(tree['tree'])
                         and all(entry.get('mode') == '100644' and 0 < entry.get('size', 0) <= 4 * 1024 * 1024 for entry in blobs)
                         and sum(entry['size'] for entry in blobs) <= 12 * 1024 * 1024
                         and all(entry.get('type') in ('blob', 'tree') for entry in tree['tree']), 'response-blob-admission')
        output = Path(directory)
        output.mkdir(mode=0o700)
        for entry in blobs:
            path = protocol.member(output, entry['path'])
            blob = api(f'{prefix}/blobs/{entry["sha"]}')
            protocol.require(blob.get('sha') == entry['sha'] and blob.get('encoding') == 'base64', 'response-blob-identity')
            data = base64.b64decode(blob['content'].replace('\n', ''), validate=True)
            require_sha = hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
            protocol.require(len(data) == entry['size'] == blob['size'] and require_sha == entry['sha'], 'response-git-blob-hash')
            protocol.write(path, data)
        print(json.dumps({'state': 'response-bytes-read', 'commit': commit_sha, 'publicationEligible': False}))
        return 0
    except (protocol.Rejected, OSError, ValueError, TypeError, KeyError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'state': 'rejected', 'reason': str(error) if isinstance(error, protocol.Rejected) else type(error).__name__, 'publicationEligible': False}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
