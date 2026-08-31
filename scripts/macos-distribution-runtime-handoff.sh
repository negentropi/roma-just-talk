#!/usr/bin/env bash

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
  if [ ! -d "$model_directory" ] \
    || [ -L "$(dirname "$model_directory")" ] \
    || [ -L "$model_directory" ]; then
    echo "The verified first launch did not create the live model directory" >&2
    return 2
  fi
}
