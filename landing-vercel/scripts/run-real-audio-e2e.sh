#!/usr/bin/env bash
set -euo pipefail

site_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$site_root"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Real-audio demo E2E requires macOS." >&2
  exit 2
fi

for command_name in SwitchAudioSource curl lsof node; do
  if ! command -v "$command_name" >/dev/null; then
    echo "Missing required command: $command_name" >&2
    exit 2
  fi
done
if [ ! -x "node_modules/.bin/playwright" ]; then
  echo "Run npm install before the real-audio E2E." >&2
  exit 2
fi

fixture="${ROMA_DEMO_AUDIO_FIXTURE:-}"
expected="${ROMA_DEMO_EXPECTED_TRANSCRIPT:-}"
audio_device="${ROMA_DEMO_AUDIO_DEVICE:-BlackHole 2ch}"
audio_player="${ROMA_DEMO_AUDIO_PLAYER:-}"
chrome_app="${ROMA_DEMO_CHROME_APP:-/Applications/Google Chrome.app}"
chrome_log="${ROMA_DEMO_CHROME_LOG:-}"
cdp_port="${ROMA_DEMO_CDP_PORT:-9222}"
browser_launch_report="${ROMA_DEMO_BROWSER_LAUNCH_REPORT:-}"
browser_state_file="${ROMA_DEMO_BROWSER_STATE_FILE:-}"

if [ -z "$fixture" ] || [ ! -f "$fixture" ]; then
  echo "ROMA_DEMO_AUDIO_FIXTURE must name an existing WAV file." >&2
  exit 2
fi
if [ "${fixture##*.}" != "wav" ] && [ "${fixture##*.}" != "WAV" ]; then
  echo "ROMA_DEMO_AUDIO_FIXTURE must be a WAV file." >&2
  exit 2
fi
if [ -z "$expected" ]; then
  echo "ROMA_DEMO_EXPECTED_TRANSCRIPT is required." >&2
  exit 2
fi
if [ -z "$audio_player" ] || [ ! -x "$audio_player" ]; then
  echo "ROMA_DEMO_AUDIO_PLAYER must name the compiled CoreAudio WAV player." >&2
  exit 2
fi
chrome_executable="$chrome_app/Contents/MacOS/Google Chrome"
chrome_info_plist="$chrome_app/Contents/Info.plist"
if [ ! -x "$chrome_executable" ] || [ ! -f "$chrome_info_plist" ]; then
  echo "ROMA_DEMO_CHROME_APP must name an installed Google Chrome app." >&2
  exit 2
fi
chrome_bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$chrome_info_plist")"
chrome_codesign_id="$(/usr/bin/codesign -dv --verbose=4 "$chrome_app" 2>&1 | sed -n 's/^Identifier=//p')"
chrome_team_id="$(/usr/bin/codesign -dv --verbose=4 "$chrome_app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
/usr/bin/codesign --verify --deep --strict "$chrome_app"
if [ "$chrome_bundle_id" != "com.google.Chrome" ] \
  || [ "$chrome_codesign_id" != "com.google.Chrome" ] \
  || [ "$chrome_team_id" != "EQHXZ8M8AV" ]; then
  echo "ROMA_DEMO_CHROME_APP must be Google's signed Chrome app." >&2
  exit 2
fi
if [[ ! "$cdp_port" =~ ^[0-9]+$ ]] || [ "$cdp_port" -lt 1024 ] || [ "$cdp_port" -gt 65535 ]; then
  echo "ROMA_DEMO_CDP_PORT must be an unused port between 1024 and 65535." >&2
  exit 2
fi

current_uid() {
  SwitchAudioSource -c -f json -t "$1" \
    | node -e 'let value=""; process.stdin.on("data", chunk => { value += chunk; }); process.stdin.on("end", () => process.stdout.write(JSON.parse(value).uid));'
}

original_input_uid="$(current_uid input)"
original_output_uid="$(current_uid output)"
[ -n "$original_input_uid" ]
[ -n "$original_output_uid" ]
audio_changed=false
loopback_level_captured=false
original_loopback_output_volume=""
original_loopback_output_muted=""
chrome_pid=""
chrome_profile=""

output_volume() {
  /usr/bin/osascript -e 'output volume of (get volume settings)'
}

output_muted() {
  /usr/bin/osascript -e 'output muted of (get volume settings)'
}

write_output_level() {
  local destination="$1"
  local volume="$2"
  local muted="$3"
  if [ -n "$destination" ]; then
    printf 'output_volume=%s\noutput_muted=%s\n' "$volume" "$muted" > "$destination"
  fi
}

restore_loopback_level() {
  local restore_exit=0
  local restored_volume=""
  local restored_muted=""
  local mute_clause="without output muted"
  if [ "$loopback_level_captured" != true ]; then
    return 0
  fi
  if [ "$original_loopback_output_muted" = true ]; then
    mute_clause="with output muted"
  fi
  /usr/bin/osascript -e \
    "set volume output volume $original_loopback_output_volume $mute_clause" \
    >/dev/null 2>&1 || restore_exit=1
  restored_volume="$(output_volume 2>/dev/null || true)"
  restored_muted="$(output_muted 2>/dev/null || true)"
  write_output_level \
    "${ROMA_DEMO_AUDIO_LEVEL_AFTER:-}" \
    "$restored_volume" \
    "$restored_muted" || restore_exit=1
  if [ "$restored_volume" != "$original_loopback_output_volume" ] \
    || [ "$restored_muted" != "$original_loopback_output_muted" ]; then
    restore_exit=1
  fi
  if [ "$restore_exit" -ne 0 ]; then
    echo "Could not verify the original BlackHole output level was restored." >&2
  fi
  return "$restore_exit"
}

restore_audio() {
  local restore_exit=0
  local restored_input_uid=""
  local restored_output_uid=""
  if [ "$audio_changed" = true ]; then
    restore_loopback_level || restore_exit=1
    SwitchAudioSource -u "$original_input_uid" -t input >/dev/null 2>&1 || restore_exit=1
    SwitchAudioSource -u "$original_output_uid" -t output >/dev/null 2>&1 || restore_exit=1
    restored_input_uid="$(current_uid input 2>/dev/null || true)"
    restored_output_uid="$(current_uid output 2>/dev/null || true)"
    if [ "$restored_input_uid" != "$original_input_uid" ] \
      || [ "$restored_output_uid" != "$original_output_uid" ]; then
      restore_exit=1
    fi
  fi
  if [ "$restore_exit" -ne 0 ]; then
    echo "Could not verify the original macOS audio route was restored." >&2
  fi
  return "$restore_exit"
}

chrome_process_pids() {
  ps -ww -axo pid=,command= \
    | node -e '
      let rows = "";
      process.stdin.on("data", (chunk) => { rows += chunk; });
      process.stdin.on("end", () => {
        const executable = `${process.argv[1]}/Contents/MacOS/Google Chrome`;
        const profile = `--user-data-dir=${process.argv[2]}`;
        const matches = rows.split("\n").map((row) => row.trim()).filter((row) => {
          const separator = row.indexOf(" ");
          const command = separator === -1 ? "" : row.slice(separator + 1).trim();
          const executableMatches = command === executable || command.startsWith(`${executable} `);
          const profileMatches = command.endsWith(` ${profile}`) || command.includes(` ${profile} `);
          return executableMatches && profileMatches;
        });
        process.stdout.write(matches.map((row) => row.slice(0, row.indexOf(" "))).join("\n"));
      });
    ' "$chrome_app" "$chrome_profile"
}

chrome_profile_process_pids() {
  ps -ww -axo pid=,command= \
    | node -e '
      let rows = "";
      process.stdin.on("data", (chunk) => { rows += chunk; });
      process.stdin.on("end", () => {
        const appPrefix = `${process.argv[1]}/Contents/`;
        const profile = `--user-data-dir=${process.argv[2]}`;
        const matches = rows.split("\n").map((row) => row.trim()).filter((row) => {
          const separator = row.indexOf(" ");
          const command = separator === -1 ? "" : row.slice(separator + 1).trim();
          const profileMatches = command.endsWith(` ${profile}`) || command.includes(` ${profile} `);
          return command.startsWith(appPrefix) && profileMatches;
        });
        process.stdout.write(matches.map((row) => row.slice(0, row.indexOf(" "))).join("\n"));
      });
    ' "$chrome_app" "$chrome_profile"
}

chrome_microphone_process_pids() {
  ps -ww -axo pid=,command= \
    | node -e '
      let rows = "";
      process.stdin.on("data", (chunk) => { rows += chunk; });
      process.stdin.on("end", () => {
        const app = process.argv[1];
        const main = `${app}/Contents/MacOS/Google Chrome`;
        const helperPrefix = `${app}/Contents/Frameworks/Google Chrome Framework.framework/Versions/`;
        const matches = rows.split("\n").map((row) => row.trim()).filter((row) => {
          const separator = row.indexOf(" ");
          const command = separator === -1 ? "" : row.slice(separator + 1).trim();
          const isMain = command === main || command.startsWith(`${main} `);
          const isHelper = command.startsWith(helperPrefix) && command.includes("/Helpers/Google Chrome Helper");
          return isMain || isHelper;
        });
        process.stdout.write(matches.map((row) => row.slice(0, row.indexOf(" "))).join("\n"));
      });
    ' "$chrome_app"
}

chrome_profile_clear() {
  local lsof_exit=0
  local lsof_output=""
  local profile_pids=""
  if ! profile_pids="$(chrome_profile_process_pids)"; then
    echo "Could not inspect processes using the real-audio test profile." >&2
    return 2
  fi
  if [ -n "$profile_pids" ]; then
    return 1
  fi
  if lsof_output="$(lsof +D "$chrome_profile" 2>&1)"; then
    if [ -n "$lsof_output" ]; then
      return 1
    fi
    echo "lsof reported success without a profile-use result." >&2
    return 2
  else
    lsof_exit=$?
  fi
  if [ "$lsof_exit" -eq 1 ] && [ -z "$lsof_output" ]; then
    return 0
  fi
  echo "Could not verify that Chrome released the real-audio test profile: $lsof_output" >&2
  return 2
}

find_chrome_pid() {
  chrome_process_pids | sed -n '1p'
}

stop_browser() {
  local matching_pids=""
  local microphone_pids=""
  local profile_check=0
  local profile_clear=false
  if [ -z "$chrome_profile" ]; then
    return 0
  fi
  if ! matching_pids="$(chrome_profile_process_pids)"; then
    echo "Could not inspect the real-audio test's Chrome processes." >&2
    return 1
  fi
  while IFS= read -r matching_pid; do
    if [ -n "$matching_pid" ] && ! kill "$matching_pid" 2>/dev/null \
      && kill -0 "$matching_pid" 2>/dev/null; then
      echo "Could not stop real-audio Chrome process $matching_pid." >&2
      return 1
    fi
  done <<< "$matching_pids"
  for _ in {1..50}; do
    if ! matching_pids="$(chrome_profile_process_pids)"; then
      echo "Could not inspect the real-audio test's Chrome processes." >&2
      return 1
    fi
    if [ -z "$matching_pids" ]; then
      break
    fi
    sleep 0.1
  done
  if [ -n "$matching_pids" ]; then
    while IFS= read -r matching_pid; do
      if [ -n "$matching_pid" ]; then
        kill -KILL "$matching_pid" 2>/dev/null || true
      fi
    done <<< "$matching_pids"
    for _ in {1..20}; do
      if ! matching_pids="$(chrome_profile_process_pids)"; then
        echo "Could not inspect the real-audio test's Chrome processes." >&2
        return 1
      fi
      if [ -z "$matching_pids" ]; then
        break
      fi
      sleep 0.1
    done
  fi
  if [ -n "$matching_pids" ]; then
    echo "Chrome did not stop after the real-audio E2E: $matching_pids" >&2
    return 1
  fi
  for _ in {1..50}; do
    if chrome_profile_clear; then
      profile_clear=true
      break
    else
      profile_check=$?
    fi
    if [ "$profile_check" -eq 2 ]; then
      return 1
    fi
    sleep 0.1
  done
  if [ "$profile_clear" != true ]; then
    echo "Chrome processes still reference the real-audio test profile." >&2
    return 1
  fi
  for _ in {1..50}; do
    if ! microphone_pids="$(chrome_microphone_process_pids)"; then
      echo "Could not inspect Chrome microphone-client processes." >&2
      return 1
    fi
    if [ -z "$microphone_pids" ]; then
      break
    fi
    sleep 0.1
  done
  if [ -n "$microphone_pids" ]; then
    echo "Chrome microphone-client processes are still running: $microphone_pids" >&2
    return 1
  fi
  case "$chrome_profile" in
    "${TMPDIR:-/tmp}"/roma-demo-chrome.*) rm -r "$chrome_profile" ;;
    *)
      echo "Refusing to delete an unexpected Chrome profile path." >&2
      return 1
      ;;
  esac
}

finish() {
  local test_exit=$?
  local cleanup_exit=0
  trap - EXIT
  if stop_browser; then
    if [ -n "$browser_state_file" ] && ! printf 'stopped\n' > "$browser_state_file"; then
      echo "Could not record that the browser stopped." >&2
      cleanup_exit=4
    fi
  else
    cleanup_exit=4
  fi
  if ! restore_audio; then
    cleanup_exit=4
  fi
  if [ "$test_exit" -eq 0 ]; then
    test_exit="$cleanup_exit"
  fi
  exit "$test_exit"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

audio_changed=true
SwitchAudioSource -s "$audio_device" -t input >/dev/null
SwitchAudioSource -s "$audio_device" -t output >/dev/null

actual_input="$(SwitchAudioSource -c -t input)"
actual_output="$(SwitchAudioSource -c -t output)"
if [ "$actual_input" != "$audio_device" ] \
  || [ "$actual_output" != "$audio_device" ]; then
  echo "BlackHole did not become both the default input and output." >&2
  exit 3
fi

original_loopback_output_volume="$(output_volume)"
original_loopback_output_muted="$(output_muted)"
if [[ ! "$original_loopback_output_volume" =~ ^[0-9]+$ ]] \
  || { [ "$original_loopback_output_muted" != true ] && [ "$original_loopback_output_muted" != false ]; }; then
  echo "BlackHole did not expose restorable output volume and mute controls." >&2
  exit 3
fi
write_output_level \
  "${ROMA_DEMO_AUDIO_LEVEL_BEFORE:-}" \
  "$original_loopback_output_volume" \
  "$original_loopback_output_muted"
loopback_level_captured=true

export ROMA_DEMO_AUDIO_FIXTURE="$fixture"
export ROMA_DEMO_EXPECTED_TRANSCRIPT="$expected"
export ROMA_DEMO_AUDIO_DEVICE="$audio_device"
export ROMA_DEMO_AUDIO_DEVICE_UID="$(current_uid output)"

chrome_profile="$(mktemp -d "${TMPDIR:-/tmp}/roma-demo-chrome.XXXXXX")"
if lsof -nP -iTCP:"$cdp_port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "ROMA_DEMO_CDP_PORT is already in use: $cdp_port" >&2
  exit 2
fi
chrome_args=(
  "--remote-debugging-address=127.0.0.1"
  "--remote-debugging-port=$cdp_port"
  "--user-data-dir=$chrome_profile"
  "--use-fake-ui-for-media-stream"
  "--no-first-run"
  "--no-default-browser-check"
)
if [ -n "$chrome_log" ]; then
  chrome_args+=(
    "--enable-logging"
    "--log-file=$chrome_log"
    "--vmodule=audio*=2,media*=2"
  )
fi

# LaunchServices makes the signed browser, rather than this shell's host, the
# responsible macOS process for microphone permission checks.
if [ -n "$browser_state_file" ]; then
  printf 'running\n' > "$browser_state_file"
fi
/usr/bin/open -n -g "$chrome_app" --args "${chrome_args[@]}"
for _ in {1..50}; do
  chrome_pid="$(find_chrome_pid)"
  if [ -n "$chrome_pid" ]; then
    break
  fi
  sleep 0.1
done
if [ -z "$chrome_pid" ]; then
  echo "Could not identify the LaunchServices Chrome process." >&2
  exit 3
fi
cdp_version_url="http://127.0.0.1:$cdp_port/json/version"
cdp_version_file="$chrome_profile/cdp-version.json"
cdp_deadline_seconds="$((SECONDS + 10))"
while [ "$SECONDS" -lt "$cdp_deadline_seconds" ]; do
  if curl --silent --fail --connect-timeout 0.2 --max-time 0.2 \
      "$cdp_version_url" --output "$cdp_version_file"; then
    break
  fi
  sleep 0.2
done
if [ ! -s "$cdp_version_file" ]; then
  echo "Chrome did not expose its DevTools endpoint at $cdp_version_url." >&2
  exit 3
fi
listener_pid="$(lsof -nP -iTCP:"$cdp_port" -sTCP:LISTEN -t | sed -n '1p')"
if [ "$listener_pid" != "$chrome_pid" ]; then
  echo "The DevTools listener does not belong to this test's Chrome process." >&2
  exit 3
fi
node -e '
  const version = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
  if (!String(version.Browser).startsWith("Chrome/") || !version.webSocketDebuggerUrl) process.exit(1);
' "$cdp_version_file"
if [ -n "$browser_launch_report" ]; then
  cp "$cdp_version_file" "$browser_launch_report"
fi
export ROMA_DEMO_CDP_ENDPOINT="http://127.0.0.1:$cdp_port"

node_modules/.bin/playwright test --config playwright.real-audio.config.mjs
