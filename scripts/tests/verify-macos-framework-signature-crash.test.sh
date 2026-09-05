#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT/scripts/verify-macos-framework-signature-crash.sh"
FIXTURES="$ROOT/scripts/tests/fixtures/macos-framework-signature-crash"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roma-framework-signature-crash.XXXXXX")"
OUTPUT="$TEMP_ROOT/output.txt"
trap 'rm -rf "$TEMP_ROOT"' EXIT

expect_match() {
  local fixture="$1" framework="$2" main_uuid="$3" framework_uuid="$4"
  "$VERIFIER" "$fixture" com.negentropi.RomaJustTalk 26.4.1 25E253 \
    "$main_uuid" "$framework" "$framework_uuid" \
    "$(approval_start_for_framework "$framework")" \
    1.95 195 >"$OUTPUT"
  grep -Eq '^verdict=matched pid=[1-9][0-9]* crash_report_sha256=[0-9a-f]{64} framework=' "$OUTPUT"
}

approval_start_for_framework() {
  case "$1" in
    whisper) printf '%s\n' '2026-08-28T13:01:33Z' ;;
    MediaRemoteAdapter) printf '%s\n' '2026-08-30T04:31:08Z' ;;
    *) return 1 ;;
  esac
}

expect_failure() {
  local expected_message="$1"
  shift
  local framework="${7:-}"
  if "$@" "$(approval_start_for_framework "$framework")" \
    1.95 195 >"$OUTPUT" 2>&1; then
    echo "expected command to fail: $*" >&2
    exit 1
  fi
  grep -Fq "$expected_message" "$OUTPUT" || {
    echo "failure did not contain: $expected_message" >&2
    cat "$OUTPUT" >&2
    exit 1
  }
}

expect_failure_with_approval() {
  local expected_message="$1" approval_start="$2"
  shift 2
  if "$@" "$approval_start" 1.95 195 >"$OUTPUT" 2>&1; then
    echo "expected command to fail: $*" >&2
    exit 1
  fi
  grep -Fq "$expected_message" "$OUTPUT" || {
    echo "failure did not contain: $expected_message" >&2
    cat "$OUTPUT" >&2
    exit 1
  }
}

as_multiline_ips() {
  local source="$1" destination="$2"
  jq -s '.[]' "$source" > "$destination"
  if [[ "$(jq -s 'length' "$destination")" -ne 2 ]] \
    || [[ "$(awk 'END { print NR + 0 }' "$destination")" -le 2 ]]; then
    echo "fixture is not a multiline two-document IPS report" >&2
    exit 1
  fi
}

whisper="$TEMP_ROOT/whisper-multiline.ips"
mediaremote="$TEMP_ROOT/mediaremote-multiline.ips"
as_multiline_ips "$FIXTURES/whisper.ips" "$whisper"
as_multiline_ips "$FIXTURES/mediaremote-adapter.ips" "$mediaremote"
expect_match "$whisper" whisper DD61BD03-E85F-3824-9A93-5386BCE534B2 73A2EE0D-7421-3340-95D9-48D385E4747B
expect_match "$mediaremote" MediaRemoteAdapter A51BCF76-FDCD-3355-9DBB-D23F2BC65726 D9A3CAFD-7DA9-3BC2-A771-16A3AE5B8C18

mutate_body() {
  local source="$1" destination="$2" filter="$3"
  jq -s ".[1] |= ($filter) | .[]" "$source" > "$destination"
}

mutate_metadata() {
  local source="$1" destination="$2" filter="$3"
  jq -s ".[0] |= ($filter) | .[]" "$source" > "$destination"
}

mutate_report() {
  local source="$1" destination="$2" filter="$3"
  jq -s "$filter | .[]" "$source" > "$destination"
}

wrong_framework="$TEMP_ROOT/wrong-framework.ips"
mutate_body "$whisper" "$wrong_framework" '.termination.reasons[0] = "Library not loaded: @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_framework" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

wrong_uuid="$TEMP_ROOT/wrong-uuid.ips"
mutate_body "$whisper" "$wrong_uuid" '.termination.reasons[2] |= sub("73A2EE0D-7421-3340-95D9-48D385E4747B"; "00000000-0000-0000-0000-000000000000")'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_uuid" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

mixed_identity="$TEMP_ROOT/mixed-identity.ips"
mutate_metadata "$whisper" "$mixed_identity" '.slice_uuid = "A51BCF76-FDCD-3355-9DBB-D23F2BC65726"'
expect_failure "crash report does not match" "$VERIFIER" "$mixed_identity" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

wrong_os="$TEMP_ROOT/wrong-os.ips"
mutate_body "$whisper" "$wrong_os" '.osVersion.build = "25D2128"'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_os" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

wrong_app_version="$TEMP_ROOT/wrong-app-version.ips"
mutate_report "$whisper" "$wrong_app_version" '
  .[0].app_version = "1.94"
  | .[1].bundleInfo.CFBundleShortVersionString = "1.94"
'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_app_version" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

wrong_app_build="$TEMP_ROOT/wrong-app-build.ips"
mutate_report "$whisper" "$wrong_app_build" '
  .[0].build_version = "194"
  | .[1].bundleInfo.CFBundleVersion = "194"
'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_app_build" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

rounded_metadata="$TEMP_ROOT/rounded-metadata.ips"
mutate_metadata "$mediaremote" "$rounded_metadata" '.timestamp = "2026-08-30 10:01:08.40 +0530"'
expect_match "$rounded_metadata" MediaRemoteAdapter A51BCF76-FDCD-3355-9DBB-D23F2BC65726 D9A3CAFD-7DA9-3BC2-A771-16A3AE5B8C18

expect_failure_with_approval \
  "crash report timestamps do not prove this approval-window launch" \
  2026-08-30T04:32:00Z \
  "$VERIFIER" "$mediaremote" com.negentropi.RomaJustTalk 26.4.1 25E253 \
  A51BCF76-FDCD-3355-9DBB-D23F2BC65726 MediaRemoteAdapter D9A3CAFD-7DA9-3BC2-A771-16A3AE5B8C18

wrong_bundle="$TEMP_ROOT/wrong-bundle.ips"
mutate_report "$whisper" "$wrong_bundle" '
  .[0].bundleID = "com.example.Wrong"
  | .[1].bundleInfo.CFBundleIdentifier = "com.example.Wrong"
  | .[1].codeSigningID = "com.example.Wrong"
  | .[1].coalitionName = "com.example.Wrong"
  | .[1].usedImages[0].CFBundleIdentifier = "com.example.Wrong"
'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_bundle" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

missing_translocation="$TEMP_ROOT/missing-translocation.ips"
mutate_body "$mediaremote" "$missing_translocation" '.termination.reasons[2] |= gsub("AppTranslocation"; "NotTranslocation")'
expect_failure "crash report does not match" "$VERIFIER" "$missing_translocation" com.negentropi.RomaJustTalk 26.4.1 25E253 A51BCF76-FDCD-3355-9DBB-D23F2BC65726 MediaRemoteAdapter D9A3CAFD-7DA9-3BC2-A771-16A3AE5B8C18

wrong_translocated_app="$TEMP_ROOT/wrong-translocated-app.ips"
mutate_body "$whisper" "$wrong_translocated_app" '.termination.reasons[2] |= gsub("/d/roma just talk.app/"; "/d/another.app/")'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_translocated_app" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

generic_amfi="$TEMP_ROOT/generic-amfi.ips"
mutate_body "$whisper" "$generic_amfi" '.fatalDyldError = 0 | .termination.namespace = "CODESIGNING" | .termination.code = 0 | .termination.indicator = "Code Signature Invalid"'
expect_failure "crash report does not match" "$VERIFIER" "$generic_amfi" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

unrelated_dyld="$TEMP_ROOT/unrelated-dyld.ips"
mutate_body "$whisper" "$unrelated_dyld" '.termination.reasons[0] = "Library not loaded: @rpath/Other.framework/Versions/A/Other" | .termination.reasons[2] |= gsub("whisper.framework/Versions/A/whisper"; "Other.framework/Versions/A/Other")'
expect_failure "crash report does not match" "$VERIFIER" "$unrelated_dyld" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

truncated_reason="$TEMP_ROOT/truncated-reason.ips"
mutate_body "$mediaremote" "$truncated_reason" '.termination.reasons[2] = "Reason: tried: AppTranslocation MediaRemoteAdapter"'
expect_failure "crash report does not match" "$VERIFIER" "$truncated_reason" com.negentropi.RomaJustTalk 26.4.1 25E253 A51BCF76-FDCD-3355-9DBB-D23F2BC65726 MediaRemoteAdapter D9A3CAFD-7DA9-3BC2-A771-16A3AE5B8C18

alternate_truncation="$TEMP_ROOT/alternate-truncation.ips"
mutate_body "$mediaremote" "$alternate_truncation" '.termination.reasons[2] |= sub("/Ve$"; "/Vers")'
expect_match "$alternate_truncation" MediaRemoteAdapter A51BCF76-FDCD-3355-9DBB-D23F2BC65726 D9A3CAFD-7DA9-3BC2-A771-16A3AE5B8C18

wrong_truncation_prefix="$TEMP_ROOT/wrong-truncation-prefix.ips"
mutate_body "$mediaremote" "$wrong_truncation_prefix" '.termination.reasons[2] |= sub("/Ve$"; "/Wrong")'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_truncation_prefix" com.negentropi.RomaJustTalk 26.4.1 25E253 A51BCF76-FDCD-3355-9DBB-D23F2BC65726 MediaRemoteAdapter D9A3CAFD-7DA9-3BC2-A771-16A3AE5B8C18

wrong_architecture="$TEMP_ROOT/wrong-architecture.ips"
mutate_body "$mediaremote" "$wrong_architecture" '.cpuType = "X86-64"'
expect_failure "crash report does not match" "$VERIFIER" "$wrong_architecture" com.negentropi.RomaJustTalk 26.4.1 25E253 A51BCF76-FDCD-3355-9DBB-D23F2BC65726 MediaRemoteAdapter D9A3CAFD-7DA9-3BC2-A771-16A3AE5B8C18

third_record="$TEMP_ROOT/third-record.ips"
{ cat "$whisper"; printf '%s\n' '{"not":"an IPS body"}'; } > "$third_record"
expect_failure "crash report does not match" "$VERIFIER" "$third_record" com.negentropi.RomaJustTalk 26.4.1 25E253 DD61BD03-E85F-3824-9A93-5386BCE534B2 whisper 73A2EE0D-7421-3340-95D9-48D385E4747B

echo "macOS framework-signature crash verifier tests passed"
