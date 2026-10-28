#!/usr/bin/env python3
"""Run the extracted Foundation helper against one owned existing file."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

if sys.platform != "darwin":
    raise SystemExit("Requires actual macOS Foundation; no substitute URL implementation.")
root = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="RJT-Writing-Live-Alias-") as directory:
    resource = Path(directory) / "owned.txt"
    resource.write_bytes(b"owned Foundation URL identity probe")
    if not str(resource).startswith("/var/"):
        raise SystemExit("The native /var versus /private/var boundary is unavailable.")
    for mode, expected_exit in [("old", 1), ("new", 0)]:
        process = subprocess.run(
            ["/usr/bin/swift", str(root / (mode + ".swift")), mode, str(resource)],
            capture_output=True, text=True, check=False,
        )
        receipt = json.loads(process.stdout)
        if process.returncode != expected_exit or not receipt["typedOwnedIdentityMatches"]:
            raise SystemExit(f"Invalid {mode} gate: {process.returncode}; {process.stderr}")
        if receipt["failed"] != (1 if mode == "old" else 0):
            raise SystemExit(f"Unexpected {mode} case result")
        print(json.dumps({"mode": mode, "exitCode": process.returncode, "stdout": receipt}))
