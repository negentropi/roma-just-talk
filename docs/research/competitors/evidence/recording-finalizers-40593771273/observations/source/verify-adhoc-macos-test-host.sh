#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <macos-test-host-app> <new-evidence-directory>" >&2
  exit 2
fi

app="$1"
evidence="$2"
info="$app/Contents/Info.plist"
[[ -f "$info" ]] || { echo "missing test-host Info.plist: $app" >&2; exit 1; }
[[ ! -e "$evidence" ]] || { echo "test-host evidence directory must be new: $evidence" >&2; exit 1; }
mkdir -p "$evidence"

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
[[ "$executable_name" != */* && "$executable_name" != . && "$executable_name" != .. ]] || {
  echo "invalid test-host executable name" >&2
  exit 1
}
executable="$app/Contents/MacOS/$executable_name"
[[ "$bundle_id" == com.negentropi.RomaJustTalk && -x "$executable" ]] || {
  echo "unexpected or missing RJT test-host executable: $executable" >&2
  exit 1
}

if ! codesign -dvvv "$executable" > "$evidence/signature.txt" 2>&1; then
  cat "$evidence/signature.txt" >&2
  exit 1
fi
if ! codesign -d --entitlements :- "$executable" > "$evidence/entitlements.plist" 2> "$evidence/entitlements.log"; then
  cat "$evidence/entitlements.log" >&2
  exit 1
fi
if ! otool -L "$executable" > "$evidence/linked-libraries.txt"; then
  echo "could not inspect test-host libraries" >&2
  exit 1
fi
if ! codesign --verify --deep --strict --verbose=4 "$app" > "$evidence/deep-verification.txt" 2>&1; then
  cat "$evidence/deep-verification.txt" >&2
  exit 1
fi

python3 - "$app" "$executable" "$evidence" <<'PY'
import hashlib
import json
import plistlib
import re
import sys
from pathlib import Path

app, executable, output = map(Path, sys.argv[1:])
signature = (output / "signature.txt").read_text()
if not re.search(r"^Signature=adhoc$", signature, re.M):
    raise SystemExit("The test-host main executable must have an ad-hoc signature")
flags = re.findall(r"^CodeDirectory .*flags=(\S+)", signature, re.M)
if len(flags) != 1:
    raise SystemExit("The actual test-host CodeDirectory flags are unavailable")
if not re.fullmatch(r"0x[0-9a-fA-F]+(?:\([a-zA-Z0-9_,.-]+\))?", flags[0]):
    raise SystemExit("The actual test-host CodeDirectory flags are malformed")
data = (output / "entitlements.plist").read_bytes()
entitlements = plistlib.loads(data) if data else {}
libraries = []
for line in (output / "linked-libraries.txt").read_text().splitlines()[1:]:
    dependency = line.strip().split(" ", 1)[0]
    if dependency.startswith(("@rpath/", "@loader_path/", "@executable_path/")):
        libraries.append(dependency)
validation_disabled = entitlements.get("com.apple.security.cs.disable-library-validation") is True
if libraries and not validation_disabled:
    raise SystemExit("Ad-hoc test host loads bundle-relative code without disabling Library Validation")
receipt = {
    "classification": "verified-adhoc-macos-test-host",
    "app_path": str(app), "executable_path": str(executable),
    "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
    "signature": "adhoc", "raw_code_directory_flags": flags[0],
    "numeric_code_directory_flags": int(flags[0].split("(", 1)[0], 16),
    "bundle_relative_libraries": libraries, "library_validation_disabled": validation_disabled,
    "strict_deep_verification_passed": True,
    "scope": "Xcode build-for-testing host. Raw flags retained; Hardened Runtime is not required because Xcode disables it for ad-hoc test signing. No signing mutation or release-policy change."
}
(output / "result.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
print(json.dumps(receipt, sort_keys=True))
PY
