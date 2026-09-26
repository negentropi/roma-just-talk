#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <sonoma|tahoe> <known-bad-actions-zip> <candidate-actions-zip> <evidence-directory>" >&2
  exit 2
fi

case "$1" in
  sonoma) expected_version=14.2.1; expected_build=23C71 ;;
  tahoe) expected_version=26.4.1; expected_build=25E253 ;;
  *) echo "unknown case: $1" >&2; exit 2 ;;
esac

known_bad_zip="$2"
candidate_zip="$3"
evidence="$4"
script_root="$(cd "$(dirname "$0")" && pwd)"
known_bad_digest=aa4c70b468230be88b2bb76157fbfd70ae068d4b6289542c70524eb527cc071c
candidate_digest=97e9821d001c8ab539bc3c30db3c9fc5fd57721814b7f496ba4cd61069097dac

[[ "$(uname -s)" == Darwin ]] || { echo "This proof requires macOS" >&2; exit 2; }
[[ "$(uname -m)" == arm64 ]] || { echo "This proof requires Apple Silicon" >&2; exit 2; }
for tool in codesign ditto dwarfdump jq ruby screencapture; do
  command -v "$tool" >/dev/null || { echo "Missing macOS proof tool: $tool" >&2; exit 2; }
done
[[ "$(sw_vers -productVersion)" == "$expected_version" ]] || {
  echo "Wrong macOS version. Expected $expected_version" >&2
  exit 2
}
[[ "$(sw_vers -buildVersion)" == "$expected_build" ]] || {
  echo "Wrong macOS build. Expected $expected_build" >&2
  exit 2
}
[[ "$(shasum -a 256 "$known_bad_zip" | awk '{print $1}')" == "$known_bad_digest" ]] || {
  echo "Known-bad Actions artifact digest mismatch" >&2
  exit 2
}
[[ "$(shasum -a 256 "$candidate_zip" | awk '{print $1}')" == "$candidate_digest" ]] || {
  echo "Candidate Actions artifact digest mismatch" >&2
  exit 2
}
if pgrep -x 'roma just talk' >/dev/null; then
  echo "Close the existing Roma process before starting the pair" >&2
  exit 2
fi

mkdir -p "$evidence"
evidence="$(cd "$evidence" && pwd -P)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/roma-launch-pair.XXXXXX")"
mkdir -p "$stage"
record_failure() {
  status=$?
  if (( status != 0 )); then
    printf 'runtime_verdict=failed\nexit_status=%s\n' "$status" > "$evidence/verdict.txt"
  fi
}
trap record_failure EXIT
sw_vers > "$evidence/host.txt"
uname -a >> "$evidence/host.txt"
sysctl -n kern.bootsessionuuid >> "$evidence/host.txt"
printf 'known_bad_run=32947690892\nknown_bad_artifact=9599292633\nknown_bad_sha256=%s\ncandidate_run=36238526273\ncandidate_artifact=10906513138\ncandidate_sha256=%s\n' \
  "$known_bad_digest" "$candidate_digest" > "$evidence/artifacts.txt"

for phase in known-bad candidate; do
  if [[ "$phase" == known-bad ]]; then
    outer_zip="$known_bad_zip"
    expected_minimum=14.4
  else
    outer_zip="$candidate_zip"
    expected_minimum=14.0
  fi
  phase_dir="$stage/$phase"
  mkdir -p "$phase_dir/wrapper" "$phase_dir/app"
  ditto -x -k "$outer_zip" "$phase_dir/wrapper"
  ditto -x -k "$phase_dir/wrapper/roma.just.talk.app.zip" "$phase_dir/app"
  app="$phase_dir/app/roma just talk.app"
  [[ -d "$app" ]] || { echo "Missing $phase app" >&2; exit 1; }
  actual_minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
  [[ "$actual_minimum" == "$expected_minimum" ]] || {
    echo "$phase minimum OS changed: $actual_minimum" >&2
    exit 1
  }
  codesign --verify --deep --strict --verbose=4 "$app" > "$evidence/$phase-codesign.txt" 2>&1
  shasum -a 256 "$phase_dir/wrapper/roma.just.talk.app.zip" > "$evidence/$phase-inner-sha256.txt"
  dwarfdump --uuid "$app/Contents/MacOS/roma just talk" > "$evidence/$phase-main-uuid.txt"

  quarantine_time="$(printf '%x' "$(date +%s)")"
  xattr -w com.apple.quarantine "0083;$quarantine_time;CodexTest;$phase" "$app"
  xattr -p com.apple.quarantine "$app" > "$evidence/$phase-quarantine.txt"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$evidence/$phase-launch-start-utc.txt"
  open "$app" > "$evidence/$phase-open.txt" 2>&1 || true

  if [[ "$phase" == known-bad && "$1" == sonoma ]]; then
    sleep 5
    screencapture -x "$evidence/sonoma-known-bad-block.png"
    if pgrep -x 'roma just talk' > "$evidence/sonoma-known-bad-processes.txt"; then
      echo "The known-bad app unexpectedly started on Sonoma 14.2.1" >&2
      exit 1
    fi
    echo "Inspect sonoma-known-bad-block.png for the actual macOS compatibility dialog."
    read -r -p 'Press Enter after you have inspected that dialog in VNC. '
    continue
  fi

  if [[ "$phase" == known-bad ]]; then
    echo "In VNC, approve the known-bad app in Privacy & Security and wait for its launch attempt."
    read -r -p 'Press Enter after Gatekeeper approval completes. '
    crash_dir="$HOME/Library/Logs/DiagnosticReports"
    mkdir -p "$crash_dir"
    crash_report=""
    for (( attempt=0; attempt<30; attempt++ )); do
      crash_report="$(find "$crash_dir" -maxdepth 1 -name 'roma just talk*.ips' -newer "$evidence/$phase-launch-start-utc.txt" -print | sort | tail -1)"
      [[ -n "$crash_report" ]] && break
      sleep 1
    done
    screencapture -x "$evidence/tahoe-known-bad-after-launch.png"
    [[ -n "$crash_report" ]] || { echo "No new Roma crash report" >&2; exit 1; }
    cp "$crash_report" "$evidence/tahoe-known-bad.ips"
    main_uuid="$(awk '/arm64/ { print $2; exit }' "$evidence/$phase-main-uuid.txt")"
    if grep -Fq '@rpath/whisper.framework/' "$evidence/tahoe-known-bad.ips"; then
      framework=whisper
    elif grep -Fq '@rpath/MediaRemoteAdapter.framework/' "$evidence/tahoe-known-bad.ips"; then
      framework=MediaRemoteAdapter
    else
      echo "The old app did not crash on either reported framework" >&2
      exit 1
    fi
    framework_uuid="$(dwarfdump --uuid "$app/Contents/Frameworks/$framework.framework/Versions/A/$framework" | awk '/arm64/ { print $2; exit }')"
    short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
    bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
    "$script_root/verify-macos-framework-signature-crash.sh" \
      "$evidence/tahoe-known-bad.ips" com.negentropi.RomaJustTalk \
      "$expected_version" "$expected_build" "$main_uuid" "$framework" "$framework_uuid" \
      "$(cat "$evidence/$phase-launch-start-utc.txt")" "$short_version" "$bundle_version" \
      > "$evidence/tahoe-known-bad-verifier.txt"
    if pgrep -x 'roma just talk' > "$evidence/tahoe-known-bad-processes.txt"; then
      echo "Known-bad Roma still runs after the expected crash" >&2
      exit 1
    fi
    continue
  fi

  echo "In VNC, approve the candidate app in Privacy & Security if prompted."
  read -r -p 'Press Enter once its first-launch window is visible and responsive. '
  candidate_pid="$(pgrep -x 'roma just talk' | head -1 || true)"
  [[ "$candidate_pid" =~ ^[0-9]+$ ]] || { echo "Candidate is not running" >&2; exit 1; }
  screencapture -x "$evidence/$1-candidate-running.png"
  ps -p "$candidate_pid" -o pid,etime,state,command > "$evidence/$1-candidate-process.txt"
  DISTRIBUTION_E2E_EXPECTED_MACOS_VERSION="$expected_version" \
  DISTRIBUTION_E2E_EXPECTED_MACOS_BUILD="$expected_build" \
  DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=true \
    "$script_root/verify-macos-distribution-launch.sh" "$app" "$candidate_pid" "$evidence/$1-candidate-launch" \
      > "$evidence/$1-candidate-verifier.txt" 2>&1
  printf 'runtime_verdict=matched_host_pair_complete\nvisual_review=required\n' > "$evidence/verdict.txt"
done

echo "Pair captured in $evidence. Review the two screenshots and the runtime verifier outputs."
