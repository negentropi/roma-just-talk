#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 7 ]]; then
  echo "usage: $0 <github-actions-download-zip> <expected-inner-app-zip> <evidence-directory> <stage-directory> [expected-macos-version] [expected-macos-build] [interaction-minutes]" >&2
  exit 2
fi

archive="$1"
expected_inner_archive="$2"
evidence="${3%/}"
stage_root="${4%/}"
expected_macos_version="${5:-}"
expected_macos_build="${6:-}"
interaction_minutes="${7:-30}"
github_download_token="${GH_TOKEN:-}"
unset GH_TOKEN

if [[ ! "$interaction_minutes" =~ ^[0-9]+$ ]] || (( interaction_minutes < 1 || interaction_minutes > 60 )); then
  echo "Distribution E2E interaction minutes must be between 1 and 60" >&2
  exit 2
fi

repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
verifier="$repo_root/scripts/verify-macos-distribution-launch.sh"
source "$repo_root/scripts/macos-bundle-manifest.sh"
distribution_root="$stage_root/macos-distribution-e2e"
distribution_evidence="$evidence/macos-distribution-e2e"
desktop="$HOME/Desktop"
instructions="$desktop/GATEKEEPER ACTION REQUIRED.txt"
phase_file="$distribution_evidence/distribution-phase.txt"
verdict_file="$distribution_evidence/distribution-verdict.txt"
first_extraction_confirmation="$distribution_root/first-finder-extraction-confirmed.txt"
second_extraction_confirmation="$distribution_root/second-finder-extraction-confirmed.txt"
gatekeeper_confirmation="$distribution_root/gatekeeper-not-opened-confirmed.txt"
readiness_confirmation="$distribution_root/first-launch-ui-confirmed.txt"
first_extraction_confirmation_command="$desktop/Confirm First Finder Extraction.command"
second_extraction_confirmation_command="$desktop/Confirm Second Finder Extraction.command"
gatekeeper_confirmation_command="$desktop/Confirm Gatekeeper Not Opened.command"
readiness_confirmation_command="$desktop/Confirm Roma First Launch Ready.command"
disk_image="$distribution_root/roma-distribution-e2e.dmg"
volume_name="Roma Distribution E2E"
download_name="$(basename "$archive")"
app_name="roma just talk.app"
process_name="roma just talk"
bundle_identifier="com.negentropi.RomaJustTalk"
approval_process_monitor_pid=""
approval_log_pid=""
approval_stop_file="$distribution_root/approval-window-stop"
approval_first_pid_file="$distribution_root/approval-window-first-pid.txt"
approval_process_events="$distribution_evidence/approval-window-process-events.txt"
approval_log="$distribution_evidence/approval-window-unified-log.txt"

mkdir -p "$distribution_root" "$distribution_evidence" "$desktop"

mark_phase() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" | tee -a "$phase_file"
}

capture_failure_state() {
  ps -axo pid,ppid,state,etime,command \
    > "$distribution_evidence/processes-at-failure.txt" 2>&1 || true
  /usr/bin/log show --last 30m --style compact \
    --predicate 'process == "roma just talk" OR process == "syspolicyd" OR process == "CoreServicesUIAgent" OR process == "Archive Utility" OR process == "Finder" OR process == "Safari"' \
    > "$distribution_evidence/distribution-failure-unified-log.txt" 2>&1 || true

  if [[ -n "${extracted_app:-}" && -d "${extracted_app:-}" ]]; then
    xattr -lr "$extracted_app" \
      > "$distribution_evidence/extracted-app-xattrs-at-failure.txt" 2>&1 || true
    codesign --verify --deep --strict --verbose=4 "$extracted_app" \
      > "$distribution_evidence/extracted-app-codesign-at-failure.txt" 2>&1 || true
  fi

  crash_reports="$distribution_evidence/crash-reports"
  mkdir -p "$crash_reports"
  while IFS= read -r report; do
    cp "$report" "$crash_reports/" 2>/dev/null || true
  done < <(
    find "$HOME/Library/Logs/DiagnosticReports" -type f \
      \( -name 'roma just talk*.ips' -o -name 'roma just talk*.crash' \) \
      -mtime -1 -print 2>/dev/null
  )
}

fail() {
  local message="$1"
  {
    printf 'distribution_verdict=failed\n'
    printf 'failure=%s\n' "$message"
  } > "$verdict_file"
  capture_failure_state
  echo "$message" >&2
  exit 1
}

stop_approval_monitors() {
  touch "$approval_stop_file" 2>/dev/null || true
  if [[ -n "$approval_process_monitor_pid" ]]; then
    kill "$approval_process_monitor_pid" 2>/dev/null || true
    wait "$approval_process_monitor_pid" 2>/dev/null || true
    approval_process_monitor_pid=""
  fi
  if [[ -n "$approval_log_pid" ]]; then
    kill "$approval_log_pid" 2>/dev/null || true
    wait "$approval_log_pid" 2>/dev/null || true
    approval_log_pid=""
  fi
}

cleanup_background_processes() {
  stop_approval_monitors
}
trap cleanup_background_processes EXIT

write_confirmation_command() {
  local command_path="$1"
  local confirmation_path="$2"
  cat > "$command_path" <<EOF
#!/usr/bin/env bash
/usr/bin/date -u +%Y-%m-%dT%H:%M:%SZ > "$confirmation_path"
EOF
  chmod +x "$command_path"
}

wait_for_path() {
  local path="$1"
  local description="$2"
  local deadline="$3"
  while (( SECONDS < deadline )); do
    if [[ -e "$path" ]]; then
      return 0
    fi
    sleep 2
  done
  fail "timed out waiting for $description: $path"
}

resolve_github_artifact_download_url() {
  local artifact_id="${MACOS_ARTIFACT_ID:-}"
  local repository="${MACOS_ARTIFACT_REPOSITORY:-}"
  local api_endpoint=""
  local response_headers=""
  local response_status=""
  local redirect_url=""
  local redirect_host=""

  [[ "$artifact_id" =~ ^[0-9]+$ ]] \
    || fail "distribution E2E requires the selected GitHub artifact ID"
  [[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || fail "distribution E2E requires the selected GitHub repository"
  [[ -n "$github_download_token" ]] \
    || fail "distribution E2E requires a GitHub token for the browser download"

  api_endpoint="https://api.github.com/repos/$repository/actions/artifacts/$artifact_id/zip"
  if ! response_headers="$(
    curl --fail --silent --show-error \
      --dump-header - \
      --output /dev/null \
      --header "Authorization: Bearer $github_download_token" \
      --header "Accept: application/vnd.github+json" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      "$api_endpoint"
  )"; then
    fail "GitHub did not issue a browser download for artifact $artifact_id"
  fi
  response_status="$(
    printf '%s\n' "$response_headers" \
      | awk '/^HTTP\// { status = $2 } END { print status }'
  )"
  redirect_url="$(
    printf '%s\n' "$response_headers" \
      | awk '
          tolower($1) == "location:" {
            sub(/^[^:]*:[[:space:]]*/, "")
            sub(/\r$/, "")
            location = $0
          }
          END { print location }
        '
  )"
  unset response_headers
  [[ "$response_status" =~ ^30(2|3|7|8)$ ]] \
    || fail "GitHub artifact endpoint returned HTTP ${response_status:-unknown}, not a download redirect"
  case "$redirect_url" in
    https://*) ;;
    *) fail "GitHub artifact endpoint did not return an HTTPS download redirect" ;;
  esac
  redirect_host="$(
    DISTRIBUTION_E2E_DOWNLOAD_URL="$redirect_url" \
      ruby -ruri -e '
        uri = URI.parse(ENV.fetch("DISTRIBUTION_E2E_DOWNLOAD_URL"))
        abort unless uri.scheme == "https" && uri.host && !uri.host.empty?
        puts uri.host
      '
  )" || fail "could not validate the GitHub artifact download host"
  {
    printf 'artifact_id=%s\n' "$artifact_id"
    printf 'repository=%s\n' "$repository"
    printf 'artifact_api_endpoint=%s\n' "$api_endpoint"
    printf 'redirect_http_status=%s\n' "$response_status"
    printf 'redirect_host=%s\n' "$redirect_host"
    printf 'redirect_url_recorded=false\n'
  } > "$distribution_evidence/browser-download-origin.txt"
  printf '%s\n' "$redirect_url"
}

wait_for_matching_browser_download() {
  local wait_deadline="$1"
  local candidate=""
  local candidate_sha=""
  while (( SECONDS < wait_deadline )); do
    while IFS= read -r candidate; do
      [[ -f "$candidate" ]] || continue
      [[ "$(stat -f '%z' "$candidate" 2>/dev/null || true)" == "$source_size" ]] \
        || continue
      candidate_sha="$(shasum -a 256 "$candidate" 2>/dev/null | awk '{print $1}')"
      if [[ "$candidate_sha" == "$source_sha256" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done < <(find "$volume" -maxdepth 1 -type f -name '*.zip' -print 2>/dev/null)
    sleep 2
  done
  return 1
}

write_roma_crash_report_inventory() {
  local output="$1"
  local crash_root="$HOME/Library/Logs/DiagnosticReports"
  : > "$output"
  [[ -d "$crash_root" ]] || return 0
  find "$crash_root" -type f \
    \( -name 'roma just talk*.ips' -o -name 'roma just talk*.crash' \) \
    -print 2>/dev/null \
    | LC_ALL=C sort \
    > "$output"
}

monitor_roma_processes() {
  local seen=$'\n'
  local candidate_pid=""
  local process_details=""

  while [[ ! -e "$approval_stop_file" ]]; do
    while IFS= read -r candidate_pid; do
      [[ "$candidate_pid" =~ ^[0-9]+$ ]] || continue
      if [[ "$seen" == *$'\n'"$candidate_pid"$'\n'* ]]; then
        continue
      fi
      seen+="$candidate_pid"$'\n'
      process_details="$(
        ps -p "$candidate_pid" -o lstart= -o state= -o command= 2>/dev/null \
          || true
      )"
      printf '%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$candidate_pid" \
        "$process_details" \
        >> "$approval_process_events"
      if [[ ! -e "$approval_first_pid_file" ]]; then
        printf '%s\n' "$candidate_pid" > "$approval_first_pid_file"
      fi
    done < <(pgrep -x "$process_name" 2>/dev/null | LC_ALL=C sort -n || true)
    sleep 0.05
  done
}

start_approval_monitors() {
  rm -f "$approval_stop_file" "$approval_first_pid_file"
  : > "$approval_process_events"
  write_roma_crash_report_inventory \
    "$distribution_evidence/approval-window-crash-reports-before.txt"
  date -u +%Y-%m-%dT%H:%M:%SZ \
    > "$distribution_evidence/approval-window-started-at.txt"

  /usr/bin/log stream --style compact \
    --predicate 'process == "roma just talk" OR eventMessage CONTAINS[c] "com.negentropi.RomaJustTalk" OR eventMessage CONTAINS[c] "/roma just talk.app/"' \
    > "$approval_log" 2>&1 &
  approval_log_pid=$!
  monitor_roma_processes &
  approval_process_monitor_pid=$!
  sleep 1
  kill -0 "$approval_log_pid" 2>/dev/null \
    || fail "could not start approval-window unified-log monitor"
  kill -0 "$approval_process_monitor_pid" 2>/dev/null \
    || fail "could not start approval-window Roma process monitor"
}

wait_for_first_approval_pid() {
  local deadline="$1"
  while (( SECONDS < deadline )); do
    if [[ -s "$approval_first_pid_file" ]]; then
      cat "$approval_first_pid_file"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

version_is_at_least() {
  local actual="$1"
  local minimum="$2"
  awk -v actual="$actual" -v minimum="$minimum" '
    BEGIN {
      actual_count = split(actual, actual_parts, ".")
      minimum_count = split(minimum, minimum_parts, ".")
      count = actual_count > minimum_count ? actual_count : minimum_count
      for (index = 1; index <= count; index++) {
        actual_part = actual_parts[index] + 0
        minimum_part = minimum_parts[index] + 0
        if (actual_part > minimum_part) exit 0
        if (actual_part < minimum_part) exit 1
      }
      exit 0
    }
  '
}

capture_tcc_rows() {
  local database="$1"
  local output="$2"
  local scope="$3"
  local row_count="0"
  local rows=""
  local query="select service,client,client_type,auth_value,auth_reason,last_modified from access where client='$bundle_identifier' order by service;"
  local count_query="select count(*) from access where client='$bundle_identifier';"
  local sqlite_command=(sqlite3)

  if [[ "$scope" == "system" ]]; then
    sqlite_command=(sudo sqlite3)
  fi
  if [[ -f "$database" ]]; then
    if ! row_count="$("${sqlite_command[@]}" "$database" "$count_query")"; then
      fail "could not inspect the $scope TCC database"
    fi
    if ! rows="$("${sqlite_command[@]}" -header -column "$database" "$query")"; then
      fail "could not capture the $scope TCC rows"
    fi
  fi
  [[ "$row_count" =~ ^[0-9]+$ ]] \
    || fail "invalid $scope TCC row count: $row_count"
  {
    printf 'database=%s\n' "$database"
    printf 'database_present=%s\n' "$([[ -f "$database" ]] && echo true || echo false)"
    printf 'row_count=%s\n' "$row_count"
    if [[ -n "$rows" ]]; then
      printf '%s\n' "$rows"
    fi
  } > "$output"
  [[ "$row_count" -eq 0 ]] \
    || fail "fresh-Mac precondition failed: Roma already has $scope TCC state"
}

test -f "$archive" || fail "GitHub Actions archive is missing: $archive"
test -f "$expected_inner_archive" \
  || fail "unwrapped app archive is missing: $expected_inner_archive"
test -x "$verifier" || fail "distribution launch verifier is missing: $verifier"
[[ "$(uname -s)" == "Darwin" ]] || fail "distribution E2E requires macOS"
[[ "$(uname -m)" == "arm64" ]] || fail "distribution E2E requires Apple Silicon"
[[ -n "$expected_macos_version" && -n "$expected_macos_build" ]] \
  || fail "distribution E2E requires exact macOS product and build versions"
[[ "$expected_macos_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
  || fail "invalid expected macOS product version: $expected_macos_version"
[[ "$expected_macos_build" =~ ^[0-9A-Za-z]+$ ]] \
  || fail "invalid expected macOS build version: $expected_macos_build"

actual_macos_version="$(sw_vers -productVersion)"
actual_macos_build="$(sw_vers -buildVersion)"
{
  sw_vers
  uname -a
  printf 'architecture=%s\n' "$(uname -m)"
  printf 'expected_product_version=%s\n' "${expected_macos_version:-not-enforced}"
  printf 'expected_build_version=%s\n' "${expected_macos_build:-not-enforced}"
} > "$distribution_evidence/runner-identity.txt"
if [[ -n "$expected_macos_version" && "$actual_macos_version" != "$expected_macos_version" ]]; then
  fail "expected macOS $expected_macos_version, got $actual_macos_version"
fi
if [[ "$actual_macos_build" != "$expected_macos_build" ]]; then
  fail "expected macOS build $expected_macos_build, got $actual_macos_build"
fi

if pgrep -x "$process_name" >/dev/null 2>&1; then
  fail "fresh-Mac precondition failed: roma just talk is already running"
fi
if defaults read com.negentropi.RomaJustTalk \
  > "$distribution_evidence/preexisting-defaults.txt" 2>&1; then
  fail "fresh-Mac precondition failed: Roma preferences already exist"
fi
if [[ -e "$HOME/Applications/$app_name" || -e "/Applications/$app_name" ]]; then
  fail "fresh-Mac precondition failed: Roma is already installed"
fi
if [[ -e "$HOME/Library/Application Support/FluidAudio/Models" ]]; then
  fail "fresh-Mac precondition failed: Roma model state already exists"
fi
printf 'fluid_audio_models=absent\n' \
  > "$distribution_evidence/fresh-model-state.txt"
command -v sqlite3 >/dev/null \
  || fail "sqlite3 is required to inspect fresh-Mac TCC state"
capture_tcc_rows \
  "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "$distribution_evidence/fresh-tcc-user.txt" \
  user
capture_tcc_rows \
  "/Library/Application Support/com.apple.TCC/TCC.db" \
  "$distribution_evidence/fresh-tcc-system.txt" \
  system
if ! spctl --status > "$distribution_evidence/gatekeeper-status.txt" 2>&1; then
  fail "could not inspect Gatekeeper status"
fi
if ! grep -Fq 'assessments enabled' "$distribution_evidence/gatekeeper-status.txt"; then
  fail "Gatekeeper assessments are not enabled"
fi

source_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
source_size="$(stat -f '%z' "$archive")"
expected_inner_sha256="$(shasum -a 256 "$expected_inner_archive" | awk '{print $1}')"
artifact_digest="${MACOS_ARTIFACT_DIGEST:-}"
[[ "$artifact_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || fail "distribution E2E requires the GitHub artifact digest"
[[ "sha256:$source_sha256" == "$artifact_digest" ]] \
  || fail "downloaded GitHub Actions archive does not match its artifact digest"
{
  printf 'github_actions_archive=%s\n' "$archive"
  printf 'github_actions_archive_sha256=%s\n' "$source_sha256"
  printf 'github_actions_archive_size=%s\n' "$source_size"
  printf 'expected_inner_archive=%s\n' "$expected_inner_archive"
  printf 'expected_inner_archive_sha256=%s\n' "$expected_inner_sha256"
  printf 'github_artifact_run_id=%s\n' "${MACOS_ARTIFACT_RUN_ID:-unknown}"
  printf 'github_artifact_id=%s\n' "${MACOS_ARTIFACT_ID:-unknown}"
  printf 'github_artifact_digest=%s\n' "$artifact_digest"
} > "$distribution_evidence/source-artifact.txt"

mark_phase create-external-volume
[[ ! -e "$disk_image" ]] || fail "distribution disk image already exists: $disk_image"
hdiutil create -quiet -size 2g -fs APFS -volname "$volume_name" "$disk_image"
if ! hdiutil attach -nobrowse -plist "$disk_image" \
  > "$distribution_evidence/hdiutil-attach.plist"; then
  fail "could not attach the distribution disk image"
fi
volume="$({
  plutil -convert json -o - "$distribution_evidence/hdiutil-attach.plist" \
    | ruby -rjson -e '
      entities = JSON.parse(STDIN.read).fetch("system-entities")
      puts entities.map { |item| item["mount-point"] }.compact.first
    '
} 2>/dev/null || true)"
[[ -n "$volume" && -d "$volume" ]] || fail "could not resolve the external volume mount point"
diskutil info "$volume" > "$distribution_evidence/external-volume.txt"
grep -Fq 'APFS' "$distribution_evidence/external-volume.txt" \
  || fail "distribution volume is not APFS"
printf '%s\n' "$volume" > "$distribution_root/volume-path.txt"

downloaded_archive="$volume/$download_name"
deadline=$((SECONDS + interaction_minutes * 60))

mark_phase browser-download
defaults write com.apple.Safari DownloadsPath -string "$volume"
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
download_url="$(resolve_github_artifact_download_url)"
github_download_token=""

cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: browser download

Safari is downloading the selected artifact from GitHub Actions to an APFS volume.
If Safari asks whether GitHub's download host may download files, click Allow.

Do not copy the ZIP, clear quarantine, re-sign anything, or move the app.
This window will update for the Finder and Gatekeeper steps.
EOF
ln -sfn "$stage_root" "$desktop/Remote E2E Stage"
touch "$stage_root/READY"
echo "DISTRIBUTION E2E BROWSER ACTION REQUIRED"
echo "Open Remote Display and allow Safari's GitHub artifact download if prompted."
DISTRIBUTION_E2E_DOWNLOAD_URL="$download_url" \
  /usr/bin/osascript <<'APPLESCRIPT' \
    > "$distribution_evidence/safari-artifact-download.stdout.txt" \
    2> "$distribution_evidence/safari-artifact-download.stderr.txt"
set artifactURL to system attribute "DISTRIBUTION_E2E_DOWNLOAD_URL"
tell application "Safari"
  activate
  open location artifactURL
end tell
APPLESCRIPT
unset download_url
if ! downloaded_archive="$(wait_for_matching_browser_download "$deadline")"; then
  fail "timed out waiting for Safari to download the exact GitHub Actions artifact"
fi
download_name="$(basename "$downloaded_archive")"

downloaded_sha256="$(shasum -a 256 "$downloaded_archive" | awk '{print $1}')"
[[ "$downloaded_sha256" == "$source_sha256" ]] \
  || fail "Safari download does not match the GitHub Actions archive"
if ! archive_quarantine="$(xattr -p com.apple.quarantine "$downloaded_archive" 2>/dev/null)"; then
  fail "Safari download is missing quarantine"
fi
printf '%s\n' "$archive_quarantine" > "$distribution_evidence/downloaded-archive-quarantine.txt"
IFS=';' read -r _ _ archive_quarantine_agent _ <<< "$archive_quarantine"
[[ "$archive_quarantine_agent" == "Safari" ]] \
  || fail "expected Safari quarantine, got ${archive_quarantine_agent:-missing agent}"
{
  printf 'downloaded_archive=%s\n' "$downloaded_archive"
  printf 'downloaded_sha256=%s\n' "$downloaded_sha256"
  printf 'downloaded_size=%s\n' "$(stat -f '%z' "$downloaded_archive")"
} > "$distribution_evidence/browser-downloaded-artifact.txt"
mdls \
  -name kMDItemFSName \
  -name kMDItemContentType \
  -name kMDItemFSCreationDate \
  "$downloaded_archive" \
  > "$distribution_evidence/browser-downloaded-metadata.txt" 2>&1 || true

mark_phase finder-actions-artifact-extraction
[[ ! -e "$first_extraction_confirmation" ]] \
  || fail "first Finder extraction confirmation already exists"
write_confirmation_command \
  "$first_extraction_confirmation_command" \
  "$first_extraction_confirmation"
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: first Finder extraction

In the open Finder window, double-click:
$download_name

This is the outer ZIP supplied by GitHub Actions. Wait for its folder and the
inner app ZIP to appear. Then double-click on the Desktop:

Confirm First Finder Extraction.command

Run that confirmation only if you used Finder and Archive Utility for this step.
Do not use Terminal, move the app, clear quarantine, or re-sign it.
EOF
echo "DISTRIBUTION E2E FINDER ACTION REQUIRED"
echo "In Finder, double-click the outer GitHub Actions ZIP: $download_name."
open -a Finder "$volume"

inner_archive=""
while (( SECONDS < deadline )); do
  while IFS= read -r candidate; do
    [[ "$candidate" != "$downloaded_archive" ]] || continue
    candidate_sha256="$(shasum -a 256 "$candidate" | awk '{print $1}')"
    if [[ "$candidate_sha256" == "$expected_inner_sha256" ]]; then
      inner_archive="$candidate"
      break 2
    fi
  done < <(find "$volume" -type f -name '*.zip' -print 2>/dev/null)
  sleep 2
done
[[ -n "$inner_archive" ]] \
  || fail "timed out waiting for Finder to extract the exact inner app ZIP"

if ! inner_quarantine="$(xattr -p com.apple.quarantine "$inner_archive" 2>/dev/null)"; then
  fail "Finder-extracted inner app ZIP did not inherit download quarantine"
fi
printf '%s\n' "$inner_quarantine" > "$distribution_evidence/inner-archive-quarantine.txt"
IFS=';' read -r _ _ inner_quarantine_agent _ <<< "$inner_quarantine"
[[ "$inner_quarantine_agent" == "Safari" ]] \
  || fail "inner app ZIP did not preserve Safari quarantine"
{
  printf 'inner_archive=%s\n' "$inner_archive"
  printf 'inner_archive_sha256=%s\n' "$expected_inner_sha256"
} > "$distribution_evidence/inner-artifact.txt"
wait_for_path \
  "$first_extraction_confirmation" \
  "operator confirmation of the first Finder and Archive Utility extraction" \
  "$deadline"
cp "$first_extraction_confirmation" \
  "$distribution_evidence/first-finder-extraction-human-confirmation.txt"
ps -axo pid,ppid,state,lstart,command \
  > "$distribution_evidence/processes-after-first-finder-extraction.txt" 2>&1 \
  || true

mark_phase finder-app-extraction
[[ ! -e "$second_extraction_confirmation" ]] \
  || fail "second Finder extraction confirmation already exists"
write_confirmation_command \
  "$second_extraction_confirmation_command" \
  "$second_extraction_confirmation"
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: second Finder extraction

In Finder, double-click the inner app ZIP:
$inner_archive

Wait for "$app_name" to appear beside it. Then double-click on the Desktop:

Confirm Second Finder Extraction.command

Run that confirmation only if you used Finder and Archive Utility for this step.
Do not use Terminal, move the app, clear quarantine, or re-sign it.
EOF
echo "DISTRIBUTION E2E SECOND FINDER ACTION REQUIRED"
echo "In Finder, double-click the inner app ZIP: $inner_archive"
open -R "$inner_archive"
extracted_app="$(dirname "$inner_archive")/$app_name"
wait_for_path "$extracted_app/Contents/Info.plist" \
  "Finder and Archive Utility app extraction" "$deadline"

codesign_deadline=$((SECONDS + 60))
while ! codesign --verify --deep --strict --verbose=4 "$extracted_app" \
  > "$distribution_evidence/extracted-app-codesign.txt" 2>&1; do
  if (( SECONDS >= codesign_deadline )); then
    fail "Finder-extracted app fails strict deep signature verification"
  fi
  sleep 2
done
if ! app_quarantine="$(xattr -p com.apple.quarantine "$extracted_app" 2>/dev/null)"; then
  fail "second Finder extraction did not preserve app quarantine"
fi
printf '%s\n' "$app_quarantine" > "$distribution_evidence/extracted-app-quarantine.txt"
IFS=';' read -r _ _ app_quarantine_agent _ <<< "$app_quarantine"
[[ "$app_quarantine_agent" == "Safari" ]] \
  || fail "second Finder extraction did not preserve Safari quarantine"
wait_for_path \
  "$second_extraction_confirmation" \
  "operator confirmation of the second Finder and Archive Utility extraction" \
  "$deadline"
cp "$second_extraction_confirmation" \
  "$distribution_evidence/second-finder-extraction-human-confirmation.txt"
ps -axo pid,ppid,state,lstart,command \
  > "$distribution_evidence/processes-after-second-finder-extraction.txt" 2>&1 \
  || true
/usr/bin/log show --last "${interaction_minutes}m" --style compact \
  --predicate 'process == "Archive Utility" OR process == "Finder"' \
  > "$distribution_evidence/finder-archive-utility-unified-log.txt" 2>&1 \
  || true
codesign -dvvv "$extracted_app" > "$distribution_evidence/extracted-app-signature.txt" 2>&1 \
  || fail "could not inspect Finder-extracted app signature"
extracted_executable_name="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$extracted_app/Contents/Info.plist"
)"
extracted_executable="$extracted_app/Contents/MacOS/$extracted_executable_name"
extracted_executable_sha256="$(shasum -a 256 "$extracted_executable" | awk '{print $1}')"
app_minimum_system_version="$(
  /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
    "$extracted_app/Contents/Info.plist" 2>/dev/null || true
)"
[[ "$app_minimum_system_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
  || fail "extracted app has no valid minimum macOS version"
{
  printf 'runner_product_version=%s\n' "$actual_macos_version"
  printf 'app_minimum_system_version=%s\n' "$app_minimum_system_version"
} > "$distribution_evidence/extracted-app-compatibility.txt"
if ! version_is_at_least "$actual_macos_version" "$app_minimum_system_version"; then
  fail "app requires macOS $app_minimum_system_version; runner is $actual_macos_version"
fi
{
  printf 'app=%s\n' "$extracted_app"
  printf 'executable=%s\n' "$extracted_executable"
  printf 'executable_sha256=%s\n' "$extracted_executable_sha256"
} > "$distribution_evidence/extracted-app-identity.txt"
write_macos_bundle_manifest \
  "$extracted_app" \
  "$distribution_evidence/extracted-app-files-before-gatekeeper.sha256"
printf '%s\n' "$extracted_app" > "$stage_root/macos-app-path.txt"

mark_phase gatekeeper-first-block
[[ ! -e "$gatekeeper_confirmation" ]] \
  || fail "Gatekeeper confirmation already exists on a supposedly fresh stage"
write_confirmation_command \
  "$gatekeeper_confirmation_command" \
  "$gatekeeper_confirmation"
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: prove the first Gatekeeper block

Finder will open "$app_name" while Gatekeeper still rejects it.
When the real "Not Opened" dialog appears:

1. Click Done.
2. In Finder, double-click "Confirm Gatekeeper Not Opened.command" on the Desktop.

Do not run the confirmation command unless you actually saw that dialog.
EOF
set +e
spctl --assess --type execute --verbose=4 "$extracted_app" \
  > "$distribution_evidence/gatekeeper-assessment-before.txt" 2>&1
assessment_status=$?
set -e
printf '%s\n' "$assessment_status" > "$distribution_evidence/gatekeeper-assessment-before-exit-code.txt"
if [[ "$assessment_status" -eq 0 ]]; then
  fail "fresh-Mac Gatekeeper precondition failed: app was already trusted"
fi
if ! grep -Eiq 'rejected|not accepted|denied' \
  "$distribution_evidence/gatekeeper-assessment-before.txt"; then
  fail "Gatekeeper assessment failed without an explicit rejection result"
fi

set +e
DISTRIBUTION_E2E_APP_PATH="$extracted_app" osascript <<'APPLESCRIPT' \
  > "$distribution_evidence/gatekeeper-first-open.stdout.txt" \
  2> "$distribution_evidence/gatekeeper-first-open.stderr.txt"
set appPath to system attribute "DISTRIBUTION_E2E_APP_PATH"
tell application "Finder"
  activate
  open (POSIX file appPath as alias)
end tell
APPLESCRIPT
first_open_status=$?
set -e
printf '%s\n' "$first_open_status" > "$distribution_evidence/gatekeeper-first-open-exit-code.txt"
if [[ "$first_open_status" -ne 0 ]]; then
  fail "Finder could not request the first Gatekeeper-protected launch"
fi
sleep 5
if pgrep -x "$process_name" >/dev/null 2>&1; then
  fail "first launch bypassed the expected fresh-Mac Gatekeeper block"
fi
ps -axo pid,ppid,state,etime,command \
  > "$distribution_evidence/processes-after-first-block.txt" 2>&1 || true
wait_for_path \
  "$gatekeeper_confirmation" \
  "operator confirmation of the visible Gatekeeper Not Opened dialog" \
  "$deadline"
cp "$gatekeeper_confirmation" \
  "$distribution_evidence/gatekeeper-not-opened-human-confirmation.txt"

start_approval_monitors
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: GATEKEEPER ACTION REQUIRED

1. Open System Settings, Privacy & Security.
2. Find the blocked "$process_name" launch and click Open Anyway.
3. Confirm Open. Authenticate if macOS asks.

Keep the app on $volume. Do not clear quarantine or re-sign it.
The test is waiting for the first approved AppTranslocation process.
EOF
echo "DISTRIBUTION E2E GATEKEEPER ACTION REQUIRED"
echo "In Remote Display: dismiss Not Opened, then Privacy & Security -> Open Anyway -> Open."
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension" \
  > "$distribution_evidence/privacy-settings-open.txt" 2>&1 || true

if ! launched_pid="$(wait_for_first_approval_pid "$deadline")"; then
  fail "timed out waiting for the first user-approved Gatekeeper launch"
fi
printf '%s\n' "$launched_pid" > "$distribution_evidence/launched-pid.txt"

[[ ! -e "$readiness_confirmation" ]] \
  || fail "first-launch readiness confirmation already exists"
write_confirmation_command \
  "$readiness_confirmation_command" \
  "$readiness_confirmation"
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: prove the approved first process reached usable UI

Confirm that Roma's first-launch or onboarding UI is visible and responds to
normal clicks. Then, without quitting or moving Roma, double-click:

Confirm Roma First Launch Ready.command

The test will verify this same PID through AppTranslocation after confirmation.
EOF
echo "DISTRIBUTION E2E FIRST-LAUNCH UI CONFIRMATION REQUIRED"
echo "Confirm the approved Roma UI responds, then run the Desktop confirmation command."
wait_for_path \
  "$readiness_confirmation" \
  "operator confirmation of responsive Roma first-launch UI" \
  "$deadline"
cp "$readiness_confirmation" \
  "$distribution_evidence/first-launch-ui-human-confirmation.txt"

mark_phase verify-apptranslocation-and-bundled-code
DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=true \
DISTRIBUTION_E2E_REQUIRE_APPKIT_FINISHED=true \
DISTRIBUTION_E2E_EXPECTED_MACOS_VERSION="$expected_macos_version" \
DISTRIBUTION_E2E_EXPECTED_MACOS_BUILD="$expected_macos_build" \
DISTRIBUTION_E2E_EXPECTED_QUARANTINE_AGENT=Safari \
  bash "$verifier" \
    "$extracted_app" \
    "$launched_pid" \
    "$distribution_evidence/launch-verification"

sleep 2
stop_approval_monitors
awk -F '\t' 'NF >= 2 { print $2 }' "$approval_process_events" \
  | LC_ALL=C sort -nu \
  > "$distribution_evidence/approval-window-distinct-pids.txt"
approval_pid_count="$(
  awk 'NF { count++ } END { print count + 0 }' \
    "$distribution_evidence/approval-window-distinct-pids.txt"
)"
if [[ "$approval_pid_count" -ne 1 ]] \
  || ! grep -Fxq "$launched_pid" \
    "$distribution_evidence/approval-window-distinct-pids.txt"; then
  fail "more than one Roma process appeared during the approval window"
fi
write_roma_crash_report_inventory \
  "$distribution_evidence/approval-window-crash-reports-after.txt"
comm -13 \
  "$distribution_evidence/approval-window-crash-reports-before.txt" \
  "$distribution_evidence/approval-window-crash-reports-after.txt" \
  > "$distribution_evidence/approval-window-new-crash-reports.txt"
if [[ -s "$distribution_evidence/approval-window-new-crash-reports.txt" ]]; then
  fail "a new Roma crash report appeared during the approved launch"
fi
if grep -Eiq \
  'Library not loaded|code signature .*not valid for use in process|Namespace DYLD|DYLD, Code 1' \
  "$approval_log"; then
  fail "dyld or code-signature failure appeared during the approval window"
fi

write_macos_bundle_manifest \
  "$extracted_app" \
  "$distribution_evidence/extracted-app-files-after-gatekeeper.sha256"
if ! cmp -s \
  "$distribution_evidence/extracted-app-files-before-gatekeeper.sha256" \
  "$distribution_evidence/extracted-app-files-after-gatekeeper.sha256"; then
  diff -u \
    "$distribution_evidence/extracted-app-files-before-gatekeeper.sha256" \
    "$distribution_evidence/extracted-app-files-after-gatekeeper.sha256" \
    > "$distribution_evidence/extracted-app-files-gatekeeper.diff" || true
  fail "app bundle bytes changed between Finder extraction and approved launch"
fi

set +e
spctl --assess --type execute --verbose=4 "$extracted_app" \
  > "$distribution_evidence/gatekeeper-assessment-after.txt" 2>&1
assessment_after_status=$?
set -e
printf '%s\n' "$assessment_after_status" \
  > "$distribution_evidence/gatekeeper-assessment-after-exit-code.txt"

cat > "$instructions" <<EOF
roma just talk distribution E2E

Distribution launch passed.

The exact Safari-downloaded ZIP survived Finder extraction, Gatekeeper approval,
AppTranslocation, signature checks, and generic bundled-code mapping checks.
The stage will now run the deterministic transcription smoke against this same app.
EOF

mark_phase complete
{
  printf 'distribution_verdict=passed\n'
  printf 'github_actions_archive_sha256=%s\n' "$source_sha256"
  printf 'browser_downloaded_archive_sha256=%s\n' "$downloaded_sha256"
  printf 'inner_app_archive_sha256=%s\n' "$expected_inner_sha256"
  printf 'macos_version=%s\n' "$actual_macos_version"
  printf 'macos_build=%s\n' "$actual_macos_build"
  printf 'external_volume=%s\n' "$volume"
  printf 'source_app=%s\n' "$extracted_app"
  printf 'launched_pid=%s\n' "$launched_pid"
  printf 'launch_verification=passed\n'
} > "$verdict_file"

echo "macOS distribution E2E launch passed: $extracted_app"
