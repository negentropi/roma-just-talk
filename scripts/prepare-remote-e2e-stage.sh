#!/usr/bin/env bash
set -euo pipefail

target="${1:?target required}"
hold_minutes="${2:?hold minutes required}"
inputs_root="${3:?inputs root required}"
stage_root="${4:?stage root required}"
ios_scenario="${5:-none}"
macos_scenario="${6:-none}"
macos_audio_artifact="${7:-}"
macos_repetitions="${8:-3}"
macos_expected_version="${9:-}"
macos_expected_build="${10:-}"
runtime_helper_archive="${11:-$inputs_root/macos/runtime-helper/roma.runtime-e2e-harness.macos.zip}"
runtime_model_cache_path="${RUNTIME_E2E_MODEL_CACHE_PATH:-$HOME/Library/Caches/roma-runtime-e2e-models}"
github_download_token="${GH_TOKEN:-}"
unset GH_TOKEN
source "$(cd "$(dirname "$0")" && pwd)/macos-bundle-manifest.sh"

case "$target" in
  both|macos|ios) ;;
  *)
    echo "Unsupported target: $target" >&2
    exit 2
    ;;
esac

if ! [[ "$hold_minutes" =~ ^[0-9]+$ ]] || (( hold_minutes < 0 || hold_minutes > 60 )); then
  echo "Hold minutes must be between 0 and 60" >&2
  exit 2
fi

case "$ios_scenario" in
  none|local-whisper-import) ;;
  *)
    echo "Unsupported iOS scenario: $ios_scenario" >&2
    exit 2
    ;;
esac

case "$macos_scenario" in
  none|runtime-smoke|runtime-e2e|distribution-e2e) ;;
  *)
    echo "Unsupported macOS scenario: $macos_scenario" >&2
    exit 2
    ;;
esac

if [ "$macos_scenario" = "distribution-e2e" ]; then
  runtime_model_cache_path=""
fi

if [ "$macos_scenario" = "distribution-e2e" ] && [ "$hold_minutes" -eq 0 ]; then
  echo "distribution-e2e requires time for Safari, Finder, and Gatekeeper interaction" >&2
  exit 2
fi
if [ "$macos_scenario" = "distribution-e2e" ] \
  && { [ -z "$macos_expected_version" ] || [ -z "$macos_expected_build" ]; }; then
  echo "distribution-e2e requires exact macOS product and build versions" >&2
  exit 2
fi
if [ -n "$macos_expected_version" ] \
  && ! [[ "$macos_expected_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Invalid macOS product version: $macos_expected_version" >&2
  exit 2
fi
if [ -n "$macos_expected_build" ] \
  && ! [[ "$macos_expected_build" =~ ^[0-9A-Za-z]+$ ]]; then
  echo "Invalid macOS build version: $macos_expected_build" >&2
  exit 2
fi

if [ "$target" = "ios" ] && [ "$macos_scenario" != "none" ]; then
  echo "A macOS scenario requires the macos or both target" >&2
  exit 2
fi

if [ "$macos_scenario" = "runtime-e2e" ] && [ -z "$macos_audio_artifact" ]; then
  echo "runtime-e2e requires a private Namespace audio artifact" >&2
  exit 2
fi
if [ "$macos_scenario" != "none" ] && [ ! -f "$runtime_helper_archive" ]; then
  echo "A macOS runtime scenario requires the prebuilt runtime helper artifact" >&2
  exit 2
fi

case "$macos_repetitions" in
  1|3|5) ;;
  *)
    echo "macOS repetitions must be 1, 3, or 5" >&2
    exit 2
    ;;
esac

if [ "$target" = "macos" ] && [ "$ios_scenario" != "none" ]; then
  echo "An iOS scenario requires the ios or both target" >&2
  exit 2
fi

desktop="$HOME/Desktop"
evidence="$stage_root/evidence"
done_file="/tmp/voiceink-remote-e2e-stage-done"
ready_file="$stage_root/READY"
simulator_udid=""
macos_artifact_run_id=""
macos_artifact_id=""
macos_artifact_repository=""
macos_artifact_digest=""
macos_artifact_head_sha=""
macos_artifact_workflow_path=""
runtime_helper_run_id=""
runtime_helper_head_sha=""
runtime_helper_workflow_path=""
runtime_helper_archive_sha256=""
macos_artifact_runner_name=""
runtime_helper_runner_name=""
stage_runner_label="${STAGE_RUNNER_LABEL:-}"
stage_runner_name="${STAGE_RUNNER_NAME:-}"
stage_runner_instance_id="${STAGE_RUNNER_INSTANCE_ID:-}"
stage_runner_boot_epoch="${STAGE_RUNNER_BOOT_EPOCH:-}"
stage_runner_boot_session_uuid="${STAGE_RUNNER_BOOT_SESSION_UUID:-}"
stage_runner_boot_age_seconds="${STAGE_RUNNER_BOOT_AGE_SECONDS:-}"
ios_artifact_run_id=""
macos_scenario_status=0
ios_scenario_status=0
log_pids=()

mkdir -p "$desktop" "$evidence"
rm -f "$done_file"

stop_logs() {
  for pid in "${log_pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap stop_logs EXIT

capture_desktop() {
  local phase="$1"
  local image="$evidence/desktop-$phase.png"
  local error_log="$evidence/desktop-$phase-screencapture.err"

  if ! /usr/sbin/screencapture -x "$image" 2> "$error_log"; then
    echo "Namespace VNC is available, but screencapture cannot see its display from the runner shell." \
      > "$evidence/desktop-$phase-controller-capture-required.txt"
  fi
}

prepare_macos() {
  local archive="$inputs_root/macos/unwrapped/roma.just.talk.app.zip"
  local actions_archive="$inputs_root/macos/distributed/roma.just.talk.app.zip"
  local app="$HOME/Applications/roma just talk.app"
  local preferences="$HOME/Library/Preferences/com.negentropi.RomaJustTalk.plist"
  local preferences_backup="$HOME/Library/Preferences/ccom.negentropi.RomaJustTalk.plist"

  test -f "$archive"
  read -r macos_artifact_run_id < "$inputs_root/macos/build-run-id.txt"
  macos_run_metadata="$inputs_root/macos/macos-app-run-metadata.json"
  test -f "$macos_run_metadata"
  jq -e \
    --arg run_id "$macos_artifact_run_id" \
    --arg repository "${GITHUB_REPOSITORY:-}" \
    '(.runId | tostring) == $run_id
      and .status == "completed"
      and .conclusion == "success"
      and (.event == "push" or .event == "workflow_dispatch")
      and ($repository == "" or .headRepository == $repository)
      and .workflowPath == ".github/workflows/voiceink-build.yml"
      and (.headSha | test("^[0-9a-f]{40}$"))' \
    "$macos_run_metadata" >/dev/null
  macos_artifact_head_sha="$(jq -r .headSha "$macos_run_metadata")"
  macos_artifact_workflow_path="$(jq -r .workflowPath "$macos_run_metadata")"
  cp "$macos_run_metadata" "$evidence/macos-app-run-metadata.json"

  if [ "$macos_scenario" = "distribution-e2e" ]; then
    macos_run_jobs="$inputs_root/macos/macos-app-run-jobs.json"
    test -f "$macos_run_jobs"
    jq -e \
      --arg run_id "$macos_artifact_run_id" \
      '(.runId | tostring) == $run_id
        and .job.name == "Build release macOS app"
        and .job.status == "completed"
        and .job.conclusion == "success"
        and (.job.runnerName | startswith("nsc-runner-"))' \
      "$macos_run_jobs" >/dev/null
    macos_artifact_runner_name="$(jq -r .job.runnerName "$macos_run_jobs")"
    cp "$macos_run_jobs" "$evidence/macos-app-run-jobs.json"
  fi

  if [ "$macos_scenario" != "none" ]; then
    helper_run_metadata="$inputs_root/macos/runtime-helper-run-metadata.json"
    test -f "$helper_run_metadata"
    read -r runtime_helper_run_id \
      < "$inputs_root/macos/runtime-helper-run-id.txt"
    jq -e \
      --arg run_id "$runtime_helper_run_id" \
      --arg repository "${GITHUB_REPOSITORY:-}" \
      --arg expected_head_sha "${GITHUB_SHA:-}" \
      '(.runId | tostring) == $run_id
        and .status == "completed"
        and .conclusion == "success"
        and (.event == "push" or .event == "workflow_dispatch")
        and ($repository == "" or .headRepository == $repository)
        and ($expected_head_sha == "" or .headSha == $expected_head_sha)
        and .workflowPath == ".github/workflows/voiceink-build.yml"
        and (.headSha | test("^[0-9a-f]{40}$"))' \
      "$helper_run_metadata" >/dev/null
    runtime_helper_head_sha="$(jq -r .headSha "$helper_run_metadata")"
    runtime_helper_workflow_path="$(jq -r .workflowPath "$helper_run_metadata")"
    runtime_helper_archive_sha256="$(
      shasum -a 256 "$runtime_helper_archive" | awk '{print $1}'
    )"
    cp "$helper_run_metadata" "$evidence/runtime-helper-run-metadata.json"
    printf '%s  %s\n' \
      "$runtime_helper_archive_sha256" \
      "$runtime_helper_archive" \
      > "$evidence/runtime-helper-archive-sha256.txt"

    if [ "$macos_scenario" = "distribution-e2e" ]; then
      helper_run_jobs="$inputs_root/macos/runtime-helper-run-jobs.json"
      test -f "$helper_run_jobs"
      jq -e \
        --arg run_id "$runtime_helper_run_id" \
        '(.runId | tostring) == $run_id
          and .job.name == "Build reusable runtime E2E helper"
          and .job.status == "completed"
          and .job.conclusion == "success"
          and (.job.runnerName | startswith("nsc-runner-"))' \
        "$helper_run_jobs" >/dev/null
      runtime_helper_runner_name="$(jq -r .job.runnerName "$helper_run_jobs")"
      cp "$helper_run_jobs" "$evidence/runtime-helper-run-jobs.json"
    fi
  fi
  mkdir -p "$HOME/Applications" "$stage_root/macos"

  /usr/bin/log stream \
    --style compact \
    --predicate 'process == "roma just talk"' \
    > "$evidence/macos-app.log" 2>&1 &
  log_pids+=("$!")

  if [ "$macos_scenario" = "distribution-e2e" ]; then
    test -f "$actions_archive"
    read -r macos_artifact_id \
      < "$inputs_root/macos/macos-artifact-id.txt"
    read -r macos_artifact_repository \
      < "$inputs_root/macos/macos-artifact-repository.txt"
    macos_artifact_metadata="$inputs_root/macos/macos-artifact-metadata.json"
    test -f "$macos_artifact_metadata"
    [[ "$macos_artifact_id" =~ ^[0-9]+$ ]]
    [ "$macos_artifact_repository" = "${GITHUB_REPOSITORY:-}" ]
    jq -e \
      --argjson artifact_id "$macos_artifact_id" \
      --arg run_id "$macos_artifact_run_id" '
        .id == $artifact_id
        and (.runId | tostring) == $run_id
        and .name == "roma.just.talk.app"
        and .expired == false
        and (.digest | test("^sha256:[0-9a-f]{64}$"))
      ' "$macos_artifact_metadata" >/dev/null
    macos_artifact_digest="$(jq -r .digest "$macos_artifact_metadata")"
    cp "$macos_artifact_metadata" "$evidence/macos-artifact-metadata.json"
    [ -n "$github_download_token" ]
    case "$stage_runner_label" in
      namespace-profile-*|nscloud-macos-*) ;;
      *)
        echo "distribution-e2e did not receive a Namespace runner label" >&2
        exit 2
        ;;
    esac
    case "$stage_runner_name" in
      nsc-runner-*) ;;
      *)
        echo "distribution-e2e did not receive a Namespace runner instance" >&2
        exit 2
        ;;
    esac
    test -n "$stage_runner_instance_id"
    [[ "$stage_runner_boot_epoch" =~ ^[0-9]+$ ]]
    [[ "$stage_runner_boot_session_uuid" =~ ^[0-9A-Fa-f-]{36}$ ]]
    [[ "$stage_runner_boot_age_seconds" =~ ^[0-9]+$ ]]
    if [ "$stage_runner_name" = "$macos_artifact_runner_name" ]; then
      echo "distribution stage reused the macOS artifact build machine" >&2
      exit 2
    fi
    if [ "$stage_runner_name" = "$runtime_helper_runner_name" ]; then
      echo "distribution stage reused the runtime-helper build machine" >&2
      exit 2
    fi
    if [ "$macos_artifact_runner_name" = "$runtime_helper_runner_name" ]; then
      echo "macOS artifact and runtime helper reused the same build machine" >&2
      exit 2
    fi
    {
      printf 'stage_runner_label=%s\n' "$stage_runner_label"
      printf 'stage_runner_name=%s\n' "$stage_runner_name"
      printf 'stage_runner_instance_id=%s\n' "$stage_runner_instance_id"
      printf 'stage_runner_boot_epoch=%s\n' "$stage_runner_boot_epoch"
      printf 'stage_runner_boot_session_uuid=%s\n' "$stage_runner_boot_session_uuid"
      printf 'stage_runner_boot_age_seconds_at_job_start=%s\n' "$stage_runner_boot_age_seconds"
      printf 'macos_artifact_runner_name=%s\n' "$macos_artifact_runner_name"
      printf 'runtime_helper_runner_name=%s\n' "$runtime_helper_runner_name"
      printf 'fresh_machine_provenance=passed\n'
    } > "$evidence/fresh-namespace-runner.txt"
    echo "$actions_archive" > "$stage_root/macos-actions-archive-path.txt"
    return
  fi

  ditto -x -k "$archive" "$stage_root/macos"
  test -d "$stage_root/macos/roma just talk.app"
  ditto "$stage_root/macos/roma just talk.app" "$app"
  xattr -cr "$app"

  if [ -f "$preferences" ] && [ ! -f "$preferences_backup" ]; then
    mv "$preferences" "$preferences_backup"
  fi
  defaults delete com.negentropi.RomaJustTalk hasCompletedOnboarding 2>/dev/null || true
  defaults delete com.negentropi.RomaJustTalk macOSOnboardingStage 2>/dev/null || true
  defaults delete com.negentropi.RomaJustTalk macOSOnboardingPermissionKind 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true

  if [ "$macos_scenario" = "none" ]; then
    open -na "$app"
  fi
  echo "$app" > "$stage_root/macos-app-path.txt"
}

prepare_ios() {
  local archive="$inputs_root/ios/roma.just.talk.ios-simulator.app.zip"
  local unpacked="$stage_root/ios"
  local app="$unpacked/roma just talk.app"

  test -f "$archive"
  read -r ios_artifact_run_id < "$inputs_root/ios/build-run-id.txt"
  mkdir -p "$unpacked"
  ditto -x -k "$archive" "$unpacked"
  test -d "$app"

  simulator_udid="$(
    xcrun simctl list devices available --json \
      | jq -r '[.devices[][] | select(.name | startswith("iPhone"))][0].udid'
  )"
  test -n "$simulator_udid"
  test "$simulator_udid" != "null"

  xcrun simctl shutdown "$simulator_udid" 2>/dev/null || true
  xcrun simctl erase "$simulator_udid"
  xcrun simctl boot "$simulator_udid"
  xcrun simctl bootstatus "$simulator_udid" -b
  xcrun simctl install "$simulator_udid" "$app"
  open -a Simulator
  xcrun simctl launch "$simulator_udid" com.negentropi.RomaJustTalk

  xcrun simctl spawn "$simulator_udid" log stream \
    --style compact \
    --predicate 'process == "roma just talk"' \
    > "$evidence/ios-app.log" 2>&1 &
  log_pids+=("$!")

  echo "$simulator_udid" > "$stage_root/ios-simulator-udid.txt"
}

case "$target" in
  both)
    prepare_macos
    prepare_ios
    ;;
  macos)
    prepare_macos
    ;;
  ios)
    prepare_ios
    ;;
esac

write_manifest() {
  local status="$1"
  local runtime_helper_executable_sha256=""
  if [ -f "$evidence/helper-sha256.txt" ]; then
    runtime_helper_executable_sha256="$(
      awk 'NR == 1 { print $1 }' "$evidence/helper-sha256.txt"
    )"
  fi

  cat > "$stage_root/stage-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "status": "$status",
  "target": "$target",
  "macOSScenario": "$macos_scenario",
  "macOSScenarioExitCode": $macos_scenario_status,
  "macOSExpectedVersion": "$macos_expected_version",
  "macOSExpectedBuild": "$macos_expected_build",
  "macOSAudioArtifact": "$macos_audio_artifact",
  "macOSRepetitions": $macos_repetitions,
  "iOSScenario": "$ios_scenario",
  "iOSScenarioExitCode": $ios_scenario_status,
  "githubRunId": "${GITHUB_RUN_ID:-local}",
  "githubSha": "${GITHUB_SHA:-local}",
  "githubRef": "${GITHUB_REF:-local}",
  "stageRunnerLabel": "$stage_runner_label",
  "stageRunnerName": "$stage_runner_name",
  "stageRunnerInstanceId": "$stage_runner_instance_id",
  "stageRunnerBootEpoch": "$stage_runner_boot_epoch",
  "stageRunnerBootSessionUUID": "$stage_runner_boot_session_uuid",
  "stageRunnerBootAgeSecondsAtJobStart": "$stage_runner_boot_age_seconds",
  "macOSArtifactRunId": "$macos_artifact_run_id",
  "macOSArtifactId": "$macos_artifact_id",
  "macOSArtifactRepository": "$macos_artifact_repository",
  "macOSArtifactDigest": "$macos_artifact_digest",
  "macOSArtifactHeadSha": "$macos_artifact_head_sha",
  "macOSArtifactWorkflowPath": "$macos_artifact_workflow_path",
  "macOSArtifactRunnerName": "$macos_artifact_runner_name",
  "runtimeHelperRunId": "$runtime_helper_run_id",
  "runtimeHelperHeadSha": "$runtime_helper_head_sha",
  "runtimeHelperWorkflowPath": "$runtime_helper_workflow_path",
  "runtimeHelperRunnerName": "$runtime_helper_runner_name",
  "runtimeHelperArchiveSha256": "$runtime_helper_archive_sha256",
  "runtimeHelperExecutableSha256": "$runtime_helper_executable_sha256",
  "iOSArtifactRunId": "$ios_artifact_run_id",
  "doneFile": "$done_file",
  "evidenceDirectory": "$evidence",
  "macOSBundleIdentifier": "com.negentropi.RomaJustTalk",
  "iOSBundleIdentifier": "com.negentropi.RomaJustTalk",
  "simulatorUDID": "$simulator_udid"
}
EOF
  cp "$stage_root/stage-manifest.json" "$evidence/stage-manifest.json"
}

write_manifest scenario-running

if [ "$macos_scenario" = "distribution-e2e" ]; then
  set +e
  GH_TOKEN="$github_download_token" \
  MACOS_ARTIFACT_RUN_ID="$macos_artifact_run_id" \
  MACOS_ARTIFACT_ID="$macos_artifact_id" \
  MACOS_ARTIFACT_REPOSITORY="$macos_artifact_repository" \
  MACOS_ARTIFACT_DIGEST="$macos_artifact_digest" \
    bash "$(dirname "$0")/run-macos-distribution-e2e.sh" \
      "$inputs_root/macos/distributed/roma.just.talk.app.zip" \
      "$inputs_root/macos/unwrapped/roma.just.talk.app.zip" \
      "$evidence" \
      "$stage_root" \
      "$macos_expected_version" \
      "$macos_expected_build" \
      "$hold_minutes"
  macos_scenario_status=$?
  github_download_token=""
  set -e

  if [ "$macos_scenario_status" -eq 0 ]; then
    read -r distribution_app < "$stage_root/macos-app-path.txt"
    distribution_bundle_manifest="$evidence/macos-distribution-e2e/extracted-app-files-after-gatekeeper.sha256"
    runtime_bundle_before="$evidence/macos-distribution-e2e/runtime-bundle-before.sha256"
    runtime_bundle_after="$evidence/macos-distribution-e2e/runtime-bundle-after.sha256"
    runtime_chain_verdict="$evidence/macos-distribution-e2e/runtime-chain-verdict.txt"
    distribution_launched_pid="$(
      sed -n 's/^launched_pid=//p' \
        "$evidence/macos-distribution-e2e/distribution-verdict.txt"
    )"
    write_macos_bundle_manifest "$distribution_app" "$runtime_bundle_before"
    runtime_status=0
    if ! cmp -s "$distribution_bundle_manifest" "$runtime_bundle_before"; then
      diff -u "$distribution_bundle_manifest" "$runtime_bundle_before" \
        > "$evidence/macos-distribution-e2e/distribution-runtime-bundle-before.diff" \
        || true
      runtime_status=1
    else
      set +e
      RUNTIME_E2E_REQUIRE_APP_TRANSLOCATION=true \
      RUNTIME_E2E_EXPECTED_MACOS_VERSION="$macos_expected_version" \
      RUNTIME_E2E_EXPECTED_MACOS_BUILD="$macos_expected_build" \
      RUNTIME_E2E_EXPECTED_FIRST_LAUNCH_PID="$distribution_launched_pid" \
      RUNTIME_E2E_MODEL_CACHE_PATH="$runtime_model_cache_path" \
        bash "$(dirname "$0")/run-macos-runtime-e2e.sh" \
        "$distribution_app" \
        "$macos_audio_artifact" \
        "$evidence" \
        "1" \
        "smoke" \
        "$runtime_helper_archive"
      runtime_status=$?
      set -e
    fi
    write_macos_bundle_manifest "$distribution_app" "$runtime_bundle_after"
    if ! cmp -s "$runtime_bundle_before" "$runtime_bundle_after"; then
      diff -u "$runtime_bundle_before" "$runtime_bundle_after" \
        > "$evidence/macos-distribution-e2e/runtime-bundle-mutation.diff" \
        || true
      runtime_status=1
    fi
    macos_scenario_status="$runtime_status"

    distribution_executable_sha256="$(
      sed -n 's/^executable_sha256=//p' \
        "$evidence/macos-distribution-e2e/extracted-app-identity.txt"
    )"
    runtime_executable_sha256="$(
      awk 'NR == 1 { print $1 }' "$evidence/voiceink-sha256.txt" 2>/dev/null || true
    )"
    distribution_bundle_manifest_sha256="$(
      shasum -a 256 "$distribution_bundle_manifest" | awk '{print $1}'
    )"
    runtime_bundle_before_sha256="$(
      shasum -a 256 "$runtime_bundle_before" | awk '{print $1}'
    )"
    runtime_bundle_after_sha256="$(
      shasum -a 256 "$runtime_bundle_after" | awk '{print $1}'
    )"
    if [ "$macos_scenario_status" -eq 0 ] \
      && [ -n "$distribution_executable_sha256" ] \
      && [ "$distribution_executable_sha256" = "$runtime_executable_sha256" ] \
      && [ "$distribution_bundle_manifest_sha256" = "$runtime_bundle_before_sha256" ] \
      && [ "$runtime_bundle_before_sha256" = "$runtime_bundle_after_sha256" ]; then
      {
        printf 'runtime_transcription_verdict=passed\n'
        printf 'runtime_process=separate_relaunch_of_same_artifact\n'
        printf 'runtime_model_source=first_launch_live_directory\n'
        printf 'runtime_first_launch_pid=%s\n' "$distribution_launched_pid"
        printf 'distribution_executable_sha256=%s\n' "$distribution_executable_sha256"
        printf 'runtime_executable_sha256=%s\n' "$runtime_executable_sha256"
        printf 'distribution_bundle_manifest_sha256=%s\n' "$distribution_bundle_manifest_sha256"
        printf 'runtime_bundle_before_sha256=%s\n' "$runtime_bundle_before_sha256"
        printf 'runtime_bundle_after_sha256=%s\n' "$runtime_bundle_after_sha256"
      } > "$runtime_chain_verdict"
    else
      {
        printf 'runtime_transcription_verdict=failed\n'
        printf 'runtime_process=separate_relaunch_of_same_artifact\n'
        printf 'runtime_model_source=first_launch_live_directory\n'
        printf 'runtime_first_launch_pid=%s\n' "$distribution_launched_pid"
        printf 'runtime_exit_code=%s\n' "$macos_scenario_status"
        printf 'distribution_executable_sha256=%s\n' "$distribution_executable_sha256"
        printf 'runtime_executable_sha256=%s\n' "$runtime_executable_sha256"
        printf 'distribution_bundle_manifest_sha256=%s\n' "$distribution_bundle_manifest_sha256"
        printf 'runtime_bundle_before_sha256=%s\n' "$runtime_bundle_before_sha256"
        printf 'runtime_bundle_after_sha256=%s\n' "$runtime_bundle_after_sha256"
      } > "$runtime_chain_verdict"
      if [ "$macos_scenario_status" -eq 0 ]; then
        macos_scenario_status=1
      fi
    fi
  fi

  # The interaction window was consumed while the distribution scenario ran.
  hold_minutes=0
elif [ "$macos_scenario" != "none" ]; then
  macos_runtime_mode="full"
  if [ "$macos_scenario" = "runtime-smoke" ]; then
    macos_runtime_mode="smoke"
  fi
  set +e
  RUNTIME_E2E_MODEL_CACHE_PATH="$runtime_model_cache_path" \
    bash "$(dirname "$0")/run-macos-runtime-e2e.sh" \
    "$HOME/Applications/roma just talk.app" \
    "$macos_audio_artifact" \
    "$evidence" \
    "$macos_repetitions" \
    "$macos_runtime_mode" \
    "$runtime_helper_archive"
  macos_scenario_status=$?
  set -e
fi

if [ "$ios_scenario" = "local-whisper-import" ]; then
  set +e
  bash "$(dirname "$0")/run-ios-remote-stt-e2e.sh" \
    "$simulator_udid" \
    "$evidence"
  ios_scenario_status=$?
  set -e
fi

if [ "$macos_scenario_status" -ne 0 ] || [ "$ios_scenario_status" -ne 0 ]; then
  scenario_summary="A scripted scenario failed. Inspect the uploaded evidence before assigning ownership."
elif [ "$macos_scenario" = "none" ] && [ "$ios_scenario" = "none" ]; then
  scenario_summary="No scripted scenario ran."
else
  scenario_summary="The requested scripted scenario completed successfully."
fi

cat > "$desktop/REMOTE E2E STAGE READY.txt" <<EOF
roma just talk remote E2E stage

Target: $target
macOS scenario: $macos_scenario
iOS scenario: $ios_scenario
GitHub run: ${GITHUB_RUN_ID:-local}
Stage root: $stage_root

$scenario_summary
The desktop is ready for manual VNC or Computer Use interaction during the remaining hold.

To finish early, double-click:
Finish Remote E2E Stage.command
EOF

cat > "$desktop/Finish Remote E2E Stage.command" <<EOF
#!/usr/bin/env bash
touch "$done_file"
EOF
chmod +x "$desktop/Finish Remote E2E Stage.command"
ln -sfn "$stage_root" "$desktop/Remote E2E Stage"

if [ "$macos_scenario_status" -eq 0 ] && [ "$ios_scenario_status" -eq 0 ]; then
  write_manifest ready
else
  write_manifest scenario-failed
fi

touch "$ready_file"
capture_desktop ready
if [ -n "$simulator_udid" ]; then
  xcrun simctl io "$simulator_udid" screenshot "$evidence/ios-ready.png" 2>/dev/null || true
fi

echo "REMOTE E2E STAGE READY"
echo "Open Namespace dashboard -> this GitHub job -> Remote Display."
echo "Target: $target"
echo "macOS scenario: $macos_scenario (exit $macos_scenario_status)"
echo "iOS scenario: $ios_scenario (exit $ios_scenario_status)"
echo "Hold: $hold_minutes minutes"
echo "Finish early: double-click Finish Remote E2E Stage.command on the remote desktop."

deadline=$((SECONDS + hold_minutes * 60))
while (( SECONDS < deadline )) && [ ! -f "$done_file" ]; do
  remaining=$(((deadline - SECONDS + 59) / 60))
  echo "Stage alive; about $remaining minute(s) remaining."
  sleep 30
done

capture_desktop final
if [ -n "$simulator_udid" ]; then
  xcrun simctl io "$simulator_udid" screenshot "$evidence/ios-final.png" 2>/dev/null || true
fi
xcodebuild -version > "$evidence/xcode-version.txt"
sw_vers > "$evidence/macos-version.txt"
xcrun simctl list devices > "$evidence/simulator-devices.txt"

if [ -f "$done_file" ]; then
  echo "Remote E2E stage finished early."
else
  echo "Remote E2E stage hold expired."
fi

if [ "$macos_scenario_status" -eq 0 ] && [ "$ios_scenario_status" -eq 0 ]; then
  write_manifest completed
else
  write_manifest scenario-failed
fi

if [ "$macos_scenario_status" -ne 0 ]; then
  exit "$macos_scenario_status"
fi
if [ "$ios_scenario_status" -ne 0 ]; then
  exit "$ios_scenario_status"
fi
