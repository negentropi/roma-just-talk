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
