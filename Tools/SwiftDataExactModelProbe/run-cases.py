#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile
import time


def now():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("fresh_output", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    app = binary.parent.parent.parent
    info = app / "Contents" / "Info.plist"
    properties = plistlib.loads(info.read_bytes())
    if (binary.parent.name != "MacOS" or not app.name.endswith(".app") or
            properties["CFBundleExecutable"] != binary.name or
            properties["CFBundleIdentifier"] != "com.negentropi.RomaJustTalk.SwiftDataExactProbe" or
            properties["CFBundleName"] != "VoiceInkSwiftDataExactProbe" or
            properties["LSMinimumSystemVersion"] != "14.2.1"):
        raise ValueError("Probe requires its recorded app bundle")
    args.fresh_output.mkdir(parents=True, exist_ok=False)
    output = args.fresh_output.resolve()
    identity = {
        "diagnosticOnly": True,
        "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "infoPlistSHA256": hashlib.sha256(info.read_bytes()).hexdigest(),
        "bundleIdentifier": properties["CFBundleIdentifier"],
        "bundleName": properties["CFBundleName"],
        "bundleSHA256": {str(path.relative_to(app)): hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in sorted(app.rglob("*")) if path.is_file()},
        "osVersion": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
        "osBuild": subprocess.check_output(["sw_vers", "-buildVersion"], text=True).strip(),
        "arch": platform.machine(),
    }
    (output / "runtime-identity.json").write_text(json.dumps(identity, sort_keys=True, indent=2) + "\n")
    with (output / "signature-verification.txt").open("wb") as log:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)
    signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)],
                               capture_output=True, text=True, check=True, timeout=30)
    (output / "signature-identity.txt").write_text(signature.stdout + signature.stderr)
    with (output / "list-modes.log").open("wb") as log:
        listed = subprocess.run([str(binary), "--list-modes"], stdout=log,
                                stderr=subprocess.STDOUT, timeout=10)
    (output / "list-modes.exit").write_text(str(listed.returncode) + "\n")
    if listed.returncode != 0:
        raise ValueError("Probe mode listing failed before store cases")
    modes = json.loads((output / "list-modes.log").read_text())
    if not isinstance(modes, list) or not modes or any(not isinstance(mode, str) for mode in modes):
        raise ValueError("Invalid probe mode list")
    if len(set(modes)) != len(modes):
        raise ValueError("Duplicate probe mode")
    for mode in modes:
        if not mode or any(c not in "abcdefghijklmnopqrstuvwxyz-" for c in mode):
            raise ValueError("Invalid probe mode")
    identity["modes"] = modes
    (output / "runtime-identity.json").write_text(json.dumps(identity, sort_keys=True, indent=2) + "\n")
    for mode in modes:
        stores = Path(tempfile.mkdtemp(prefix="roma-swiftdata-exact-" + mode + "-")).resolve()
        file_system = subprocess.check_output(["df", "-P", str(stores)], text=True, timeout=10)
        started = now()
        begin = time.monotonic()
        timed_out = False
        command = [str(binary), mode, str(stores)]
        with (output / (mode + ".log")).open("wb") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            try:
                exit_code = process.wait(timeout=60)
            except subprocess.TimeoutExpired:
                timed_out = True
                process.kill()
                exit_code = process.wait(timeout=5)
        result = {"mode": mode, "pid": process.pid, "command": command, "startedUTC": started,
                  "finishedUTC": now(), "seconds": round(time.monotonic() - begin, 3),
                  "exitCode": exit_code, "timedOut": timed_out,
                  "storeDirectory": str(stores), "storeFileSystem": file_system,
                  "storeDevice": stores.stat().st_dev, "outputDevice": output.stat().st_dev}
        (output / (mode + ".result.json")).write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
        shutil.copytree(stores, output / (mode + ".stores"))
        print(json.dumps(result, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
