#!/usr/bin/env bash

run_runtime_e2e_phases() {
  local smoke_config="$1"
  local full_config="$2"

  mark_phase preflight
  run_harness_phase preflight runtime-e2e-preflight "$full_config" || return $?
  mark_phase target-probe
  run_harness_phase target-probe runtime-e2e-target-probe "$full_config" || return $?
  mark_phase functional-smoke
  run_harness_phase functional-smoke runtime-e2e-run "$smoke_config" || scenario_status=$?
  mark_phase repeated-runtime-matrix
  run_harness_phase runtime-e2e-report runtime-e2e-run "$full_config" || scenario_status=$?
}
