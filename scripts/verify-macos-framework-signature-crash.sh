#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <crash-report.ips> <bundle-id> <macos-version> <macos-build> <main-uuid> <whisper|MediaRemoteAdapter> <framework-uuid> <approval-window-start-utc> <app-short-version> <app-bundle-version>" >&2
}

if [[ $# -ne 10 ]]; then
  usage
  exit 2
fi

report="$1"
bundle_id="$2"
macos_version="$3"
macos_build="$4"
main_uuid="$5"
framework="$6"
framework_uuid="$7"
approval_window_start_utc="$8"
app_short_version="$9"
app_bundle_version="${10}"

[[ -f "$report" ]] || { echo "crash report does not exist: $report" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to verify a macOS crash report" >&2; exit 2; }
command -v shasum >/dev/null 2>&1 || { echo "shasum is required to fingerprint a macOS crash report" >&2; exit 2; }
command -v ruby >/dev/null 2>&1 || { echo "ruby is required to verify crash-report timing" >&2; exit 2; }

uuid_pattern='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
[[ "$main_uuid" =~ $uuid_pattern && "$framework_uuid" =~ $uuid_pattern ]] || {
  echo "expected UUIDs must use the canonical 8-4-4-4-12 form" >&2
  exit 2
}
[[ "$macos_version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || {
  echo "expected macOS version must be numeric, for example 26.4.1" >&2
  exit 2
}
[[ "$macos_build" =~ ^[0-9A-Za-z]+$ ]] || {
  echo "expected macOS build must be alphanumeric" >&2
  exit 2
}
[[ "$approval_window_start_utc" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
  echo "approval-window start must be an ISO-8601 UTC timestamp" >&2
  exit 2
}
for app_version_value in "$app_short_version" "$app_bundle_version"; do
  [[ "$app_version_value" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || {
    echo "expected app versions must be nonempty plist-safe version strings" >&2
    exit 2
  }
done

case "$framework" in
  whisper)
    framework_rpath='@rpath/whisper.framework/Versions/Current/whisper'
    embedded_framework_path='whisper.framework/Versions/A/whisper'
    other_framework_rpath='@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter'
    ;;
  MediaRemoteAdapter)
    framework_rpath='@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter'
    embedded_framework_path='MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter'
    other_framework_rpath='@rpath/whisper.framework/Versions/Current/whisper'
    ;;
  *)
    echo "expected framework must be whisper or MediaRemoteAdapter" >&2
    exit 2
    ;;
esac

main_uuid="$(printf '%s' "$main_uuid" | tr '[:lower:]' '[:upper:]')"
framework_uuid="$(printf '%s' "$framework_uuid" | tr '[:lower:]' '[:upper:]')"

# A complete IPS file is two adjacent JSON objects: the metadata record and
# the detailed crash record. Parsing them together prevents accidental mixing
# of a first line from one report with a body from another.
if ! jq -e -s \
  --arg bundle_id "$bundle_id" \
  --arg macos_version "$macos_version" \
  --arg macos_build "$macos_build" \
  --arg main_uuid "$main_uuid" \
  --arg framework_uuid "$framework_uuid" \
  --arg framework_rpath "$framework_rpath" \
  --arg embedded_framework_path "$embedded_framework_path" \
  --arg other_framework_rpath "$other_framework_rpath" \
  --arg app_short_version "$app_short_version" \
  --arg app_bundle_version "$app_bundle_version" '
    def upper_uuid:
      if type == "string" then ascii_upcase else "" end;
    def app_executable:
      type == "string"
      and test("\\.app/Contents/MacOS/[^/]+$");
    def app_bundle_name:
      capture("/(?<bundle>[^/]+\\.app)/Contents/MacOS/[^/]+$").bundle;
    # Tahoe may truncate this reason at a different byte depending on the
    # extracted app name. Only accept a cut-off second framework path after
    # the exact signature marker, never an arbitrary incomplete reason.
    def mediaremote_truncated_reason($uuid; $framework_path):
      . as $reason
      | ("code signature in <" + $uuid + "> \u0027") as $signature_marker
      | ($reason | split($signature_marker)) as $signature_parts
      | ($signature_parts | length == 2)
      and ($signature_parts[0] | contains("/Contents/Frameworks/" + $framework_path))
      and ($signature_parts[1] | contains("\u0027") | not)
      and ($signature_parts[1] | contains("not valid for use in process") | not)
      and (
        ($signature_parts[1] | split("/Contents/Frameworks/") | last) as $truncated_suffix
        | ($truncated_suffix | type == "string" and length > 0)
        and ($framework_path | startswith($truncated_suffix))
      );
    . as $records
    | ($records | length == 2)
    and ($records | all(.[]; type == "object"))
    and ($records[0] as $metadata | $records[1] as $body
      | ($metadata.bundleID == $bundle_id)
      and ($metadata.os_version == ("macOS " + $macos_version + " (" + $macos_build + ")"))
      and (($metadata.slice_uuid | upper_uuid) == $main_uuid)
      and (($metadata.app_name | type) == "string" and $metadata.app_name == $metadata.name)
      and (($metadata.app_version | tostring) == $app_short_version)
      and (($metadata.build_version | tostring) == $app_bundle_version)
      and (($metadata.incident_id | type) == "string" and $metadata.incident_id == $body.incident)
      and ($body.pid | type == "number" and . > 0)
      and ($body.translated == false)
      and ($body.cpuType == "ARM-64")
      and ($body.osVersion.train == ("macOS " + $macos_version))
      and ($body.osVersion.build == $macos_build)
      and ($body.procName == $metadata.app_name)
      and ($body.procPath | app_executable)
      and ($body.bundleInfo.CFBundleIdentifier == $bundle_id)
      and ($body.bundleInfo.CFBundleShortVersionString == $metadata.app_version)
      and (($body.bundleInfo.CFBundleVersion | tostring) == ($metadata.build_version | tostring))
      and ($body.codeSigningID == $bundle_id)
      and ($body.coalitionName == $bundle_id)
      and ($body.fatalDyldError == 1)
      and ($body.exception.type == "EXC_CRASH" and $body.exception.signal == "SIGABRT")
      and ($body.termination.namespace == "DYLD")
      and ($body.termination.code == 1)
      and ($body.termination.indicator == "Library missing")
      and ($body.termination.reasons | type == "array" and length == 3)
      and ($body.termination.reasons | all(.[]; type == "string" and length > 0))
      and ($body.termination.reasons[0] == ("Library not loaded: " + $framework_rpath))
      and ($body.termination.reasons | all(.[]; contains($other_framework_rpath) | not))
      and ($body.termination.reasons[1]
          | type == "string"
          and contains("Referenced from: <" + $main_uuid + "> ")
          and contains($body.procPath))
      and (($body.procPath | app_bundle_name) as $app_bundle
        | $body.termination.reasons[2]
          | type == "string"
          and contains("/AppTranslocation/")
          and contains("/d/" + $app_bundle + "/Contents/Frameworks/" + $embedded_framework_path)
          and contains("code signature in <" + $framework_uuid + ">")
          and (
            contains("not valid for use in process")
            or (
              $embedded_framework_path == "MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"
              and mediaremote_truncated_reason($framework_uuid; $embedded_framework_path)
            )
          ))
      and ($body.usedImages | type == "array")
      and ([ $body.usedImages[]
             | select((.uuid | upper_uuid) == $main_uuid) ] | length == 1)
      and ([ $body.usedImages[]
             | select((.uuid | upper_uuid) == $main_uuid) ][0] as $main_image
          | $main_image.arch == "arm64"
          and $main_image.path == $body.procPath
          and $main_image.CFBundleIdentifier == $bundle_id
          and ($main_image.path | app_executable))
    )
  ' "$report" >/dev/null; then
  echo "crash report does not match the exact framework-signature DYLD failure" >&2
  exit 1
fi

timestamp_fields="$(jq -r -s '
  if length == 2 and all(.[]; type == "object") then
    [.[0].timestamp, .[1].procLaunch, .[1].captureTime]
    | if all(.[]; type == "string" and length > 0) then .[] else empty end
  else
    empty
  end
' "$report")"
if [[ "$(printf '%s\n' "$timestamp_fields" | awk 'NF { count++ } END { print count + 0 }')" -ne 3 ]]; then
  echo "crash report has incomplete metadata, procLaunch, or captureTime timestamps" >&2
  exit 1
fi
metadata_timestamp="$(printf '%s\n' "$timestamp_fields" | sed -n '1p')"
proc_launch_timestamp="$(printf '%s\n' "$timestamp_fields" | sed -n '2p')"
capture_timestamp="$(printf '%s\n' "$timestamp_fields" | sed -n '3p')"

if ! ruby -r time -e '
  metadata, proc_launch, capture, approval = ARGV
  begin
    metadata_time = Time.parse(metadata)
    proc_launch_time = Time.parse(proc_launch)
    capture_time = Time.parse(capture)
    approval_time = Time.iso8601(approval)
  rescue ArgumentError
    exit 1
  end
  now = Time.now.utc
  exit 1 if (metadata_time - proc_launch_time).abs > 2
  exit 1 if proc_launch_time < approval_time - 2
  exit 1 if capture_time < proc_launch_time
  exit 1 if capture_time > now + 120
' "$metadata_timestamp" "$proc_launch_timestamp" "$capture_timestamp" "$approval_window_start_utc"; then
  echo "crash report timestamps do not prove this approval-window launch" >&2
  exit 1
fi

report_sha256="$(shasum -a 256 "$report" | awk '{print $1}')"
pid="$(jq -r -s '.[1].pid' "$report")"
printf 'verdict=matched pid=%s crash_report_sha256=%s framework=%s main_uuid=%s framework_uuid=%s approval_window_start_utc=%s\n' \
  "$pid" "$report_sha256" "$framework" "$main_uuid" "$framework_uuid" "$approval_window_start_utc"
