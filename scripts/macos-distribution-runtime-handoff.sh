#!/usr/bin/env bash

distribution_live_model_state() {
  local model_directory="$1"
  local storage_path=""

  for storage_path in \
    "$(dirname "$(dirname "$model_directory")")" \
    "$(dirname "$model_directory")" \
    "$model_directory"; do
    if [ -L "$storage_path" ] \
      || { [ -e "$storage_path" ] && [ ! -d "$storage_path" ]; }; then
      echo "Distribution model storage must contain only real directories" >&2
      return 2
    fi
  done
  if [ -d "$model_directory" ]; then
    printf 'present\n'
  else
    printf 'absent\n'
  fi
}

distribution_runtime_validate_handoff() {
  local expected_pid="$1"
  local observed_pids="$2"
  local model_directory="$3"
  local external_model_cache="$4"

  if ! [[ "$expected_pid" =~ ^[0-9]+$ ]]; then
    echo "Distribution runtime handoff is missing the verified first-launch PID" >&2
    return 2
  fi
  if [ "$observed_pids" != "$expected_pid" ]; then
    echo "Distribution runtime handoff requires only the verified first-launch PID" >&2
    return 2
  fi
  if [ -n "$external_model_cache" ]; then
    echo "Distribution runtime handoff must not use an external model cache" >&2
    return 2
  fi
  distribution_live_model_state "$model_directory" > /dev/null
}
