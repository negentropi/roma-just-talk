#!/usr/bin/env bash

runtime_audio_duration_seconds() {
  afinfo -r "$1" 2>/dev/null \
    | awk '/estimated duration:/ { print $3; exit }'
}

select_runtime_smoke_fixture() {
  local audio_directory="$1"
  local maximum_duration_seconds="${2:-8}"
  local fixture
  local duration

  while IFS= read -r fixture; do
    duration="$(runtime_audio_duration_seconds "$fixture" || true)"
    if [[ "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]] \
      && awk -v duration="$duration" -v maximum="$maximum_duration_seconds" \
        'BEGIN { exit !(duration > 0 && duration <= maximum) }'; then
      printf '%s\n' "$fixture"
      return 0
    fi
  done < <(
    fd -a -i -t f \
      -e wav -e wave -e aif -e aiff -e caf -e m4a -e mp3 -e flac \
      'quick.*release' "$audio_directory" \
      | sort
  )

  echo "No quick-release audio fixture is at most ${maximum_duration_seconds}s" >&2
  return 1
}

runtime_e2e_config_json() {
  local audio_directory="$1"
  local voiceink_app="$2"
  local repetitions="$3"
  local latency_threshold="$4"
  local mode="$5"

  # The quick-release speech lands in pre-roll; two seconds produced empty remote transcripts.
  jq -n \
    --arg audio_directory "$audio_directory" \
    --arg voiceink_app "$voiceink_app" \
    --arg voiceink_build_directory "$(dirname "$voiceink_app")" \
    --arg config_mode "$mode" \
    --argjson repetitions "$repetitions" \
    --argjson latency_threshold "$latency_threshold" \
    '{
      audioDirectory: $audio_directory,
      audioDeviceName: "BlackHole 2ch",
      voiceInkBundleIdentifier: "com.negentropi.RomaJustTalk",
      voiceInkAppPath: $voiceink_app,
      voiceInkBuildDirectory: $voiceink_build_directory,
      audioLeadSeconds: 1.1,
      releaseTailSeconds: 0.15,
      explicitHoldSeconds: null,
      preRollWarmupSeconds: 12,
      targetSettleSeconds: 1,
      # Prior green Namespace evidence peaked at 174ms; smoke keeps over 17x headroom.
      targetTextTimeoutSeconds: (if $config_mode == "smoke" then 3 else 20 end),
      latencyThresholdMilliseconds: $latency_threshold,
      maximumWordErrorRate: 1,
      repetitions: $repetitions,
      targetAvailabilityPolicy: "runningOnly",
      minimumTargetCount: (if $config_mode == "smoke" then 2 else 4 end),
      targets: (if $config_mode == "smoke" then [
          {id:"textedit",displayName:"TextEdit",bundleIdentifier:"com.apple.TextEdit",kind:"document"},
          {id:"chrome",displayName:"Google Chrome",bundleIdentifier:"com.google.Chrome",kind:"browser"}
        ] else [
          {id:"textedit",displayName:"TextEdit",bundleIdentifier:"com.apple.TextEdit",kind:"document"},
          {id:"safari",displayName:"Safari",bundleIdentifier:"com.apple.Safari",kind:"browser"},
          {id:"chrome",displayName:"Google Chrome",bundleIdentifier:"com.google.Chrome",kind:"browser"},
          {id:"vscode",displayName:"Visual Studio Code",bundleIdentifier:"com.microsoft.VSCode",kind:"electron"}
        ] end),
      expectedTranscripts: {},
      voiceInkLifecycle: "reuse"
    }'
}

run_runtime_e2e_phases() {
  local smoke_config="$1"
  local full_config="$2"
  local mode="${3:-full}"

  case "$mode" in
    smoke|full) ;;
    *)
      echo "Unsupported runtime E2E mode: $mode" >&2
      return 2
      ;;
  esac

  local preflight_config="$full_config"
  if [ "$mode" = "smoke" ]; then
    preflight_config="$smoke_config"
  fi

  mark_phase preflight
  run_harness_phase preflight runtime-e2e-preflight "$preflight_config" || return $?
  mark_phase target-probe
  run_harness_phase target-probe runtime-e2e-target-probe "$preflight_config" || return $?
  mark_phase functional-smoke
  run_harness_phase functional-smoke runtime-e2e-run "$smoke_config" || scenario_status=$?

  if [ "$mode" = "smoke" ]; then
    return 0
  fi

  mark_phase repeated-runtime-matrix
  run_harness_phase runtime-e2e-report runtime-e2e-run "$full_config" || scenario_status=$?
}
