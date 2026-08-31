#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/run-macos-distribution-e2e.sh"
FINDER_STATE="$ROOT/scripts/macos-finder-extraction-state.sh"
FINDER_STATE_TEST="$ROOT/scripts/tests/macos-finder-extraction-state.test.sh"
PREPARER="$ROOT/scripts/prepare-remote-e2e-stage.sh"
WORKFLOW="$ROOT/.github/workflows/voiceink-remote-e2e-stage.yml"
BUILD_WORKFLOW="$ROOT/.github/workflows/voiceink-build.yml"
RUNTIME_RUNNER="$ROOT/scripts/run-macos-runtime-e2e.sh"
RUNTIME_PREFLIGHT="$ROOT/Tools/RuntimeE2EHarness/Sources/RuntimeE2EHarness/RuntimePreflight.swift"
RENDERED_OBSERVER="$ROOT/Tools/RuntimeE2EHarness/Sources/RuntimeE2EHarness/RuntimeRenderedTextObserver.swift"
VOICEINK_SESSION="$ROOT/Tools/RuntimeE2EHarness/Sources/RuntimeE2EHarness/RuntimeVoiceInkSession.swift"
HANDOFF_HELPER="$ROOT/scripts/macos-distribution-runtime-handoff.sh"
HANDOFF_TEST="$ROOT/scripts/tests/macos-distribution-runtime-handoff.test.sh"

require_text() {
  local file="$1"
  local text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    echo "missing distribution E2E contract in $file: $text" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  if grep -Eq -- "$pattern" "$file"; then
    echo "forbidden distribution E2E shortcut in $file: $pattern" >&2
    exit 1
  fi
}

eval "$(sed -n '/^version_is_at_least()/,/^}/p' "$RUNNER")"
version_is_at_least 26.3.1 14.4
version_is_at_least 14.4 14.4
version_is_at_least 14.4.1 14.4
if version_is_at_least 14.2.1 14.4; then
  echo "macOS 14.2.1 must not satisfy a 14.4 minimum" >&2
  exit 1
fi
if version_is_at_least 14.4 14.4.1; then
  echo "macOS 14.4 must not satisfy a 14.4.1 minimum" >&2
  exit 1
fi

test -x "$RUNNER"
test -x "$FINDER_STATE"
test -x "$FINDER_STATE_TEST"
test -x "$ROOT/scripts/verify-macos-distribution-launch.sh"
test -x "$HANDOFF_TEST"

require_text "$WORKFLOW" 'distribution-e2e'
require_text "$WORKFLOW" 'macos_expected_version'
require_text "$WORKFLOW" 'macos_expected_build'
require_text "$WORKFLOW" 'developer_dir'
require_text "$WORKFLOW" '- "scripts/run-macos-distribution-e2e.sh"'
require_text "$WORKFLOW" '- "scripts/macos-finder-extraction-state.sh"'
require_text "$WORKFLOW" '- "scripts/macos-bundle-manifest.sh"'
require_text "$WORKFLOW" '- "scripts/verify-macos-distribution-launch.sh"'
require_text "$WORKFLOW" '- "scripts/tests/macos-distribution-e2e-contract.test.sh"'
require_text "$WORKFLOW" '- "scripts/tests/macos-distribution-runtime-handoff.test.sh"'
require_text "$WORKFLOW" '- "scripts/macos-distribution-runtime-handoff.sh"'
require_text "$WORKFLOW" 'bash scripts/tests/macos-distribution-runtime-handoff.test.sh'
require_text "$WORKFLOW" '- "scripts/tests/macos-finder-extraction-state.test.sh"'
require_text "$WORKFLOW" 'bash scripts/tests/macos-finder-extraction-state.test.sh'
require_text "$WORKFLOW" '- "scripts/tests/verify-macos-distribution-launch.test.sh"'
require_text "$WORKFLOW" 'roma.runtime-e2e-harness.macos'
require_text "$WORKFLOW" 'runtime_helper_run_id'
require_text "$WORKFLOW" 'runtime-helper-run-metadata.json'
require_text "$WORKFLOW" 'macos-app-run-metadata.json'
require_text "$WORKFLOW" 'macos-app-run-jobs.json'
require_text "$WORKFLOW" 'runtime-helper-run-jobs.json'
require_text "$WORKFLOW" 'macos-artifact-id.txt'
require_text "$WORKFLOW" 'macos-artifact-repository.txt'
require_text "$WORKFLOW" 'macos-artifact-metadata.json'
require_text "$WORKFLOW" 'select(.digest | test("^sha256:[0-9a-f]{64}$"))'
require_text "$WORKFLOW" 'GH_TOKEN: ${{ github.token }}'
require_text "$WORKFLOW" '.conclusion == "success"'
require_text "$WORKFLOW" '.head_repository.full_name == $repository'
require_text "$WORKFLOW" '(.event == "push" or .event == "workflow_dispatch")'
require_text "$WORKFLOW" '$GITHUB_SHA'
require_text "$WORKFLOW" 'nsc-runner-'
require_text "$WORKFLOW" 'namespace-profile-*|nscloud-macos-*'
require_text "$WORKFLOW" 'sysctl -n kern.boottime'
require_text "$WORKFLOW" 'sysctl -n kern.bootsessionuuid'
require_text "$WORKFLOW" "sed -E 's/^\\{ sec = ([0-9]+),.*/\\1/'"
require_text "$WORKFLOW" "startsWith(inputs.macos_runner, 'namespace-profile-')"
require_text "$WORKFLOW" "startsWith(inputs.macos_runner, 'nscloud-macos-')"
require_text "$WORKFLOW" 'provisioning-context.txt'
require_text "$WORKFLOW" '$RUNNER_TEMP/roma-runtime-e2e-cold-model-cache'
require_text "$WORKFLOW" 'test ! -e "$COLD_CACHE"'
require_text "$WORKFLOW" 'test ! -L "$COLD_CACHE"'
require_text "$WORKFLOW" 'cold_model_cache_preexisting=true'
require_text "$WORKFLOW" 'cold_model_cache_preexisting=false'
require_text "$WORKFLOW" 'RUNTIME_E2E_MODEL_CACHE_PATH=$COLD_CACHE'
cache_exclusion_count="$(
  grep -Fc "env.STAGE_MACOS_SCENARIO != 'distribution-e2e'" "$WORKFLOW"
)"
if [ "$cache_exclusion_count" -ne 2 ]; then
  echo "distribution E2E must skip both persistent and cold runtime model caches" >&2
  exit 1
fi
require_text "$BUILD_WORKFLOW" 'roma.runtime-e2e-harness.macos'
require_text "$BUILD_WORKFLOW" 'bash scripts/tests/macos-distribution-runtime-handoff.test.sh'
require_text "$BUILD_WORKFLOW" 'bash scripts/tests/macos-finder-extraction-state.test.sh'

require_text "$PREPARER" 'none|runtime-smoke|runtime-e2e|distribution-e2e'
require_text "$PREPARER" 'run-macos-distribution-e2e.sh'
require_text "$PREPARER" 'run-macos-runtime-e2e.sh'
require_text "$PREPARER" 'macos_expected_version'
require_text "$PREPARER" 'runtime-helper/roma.runtime-e2e-harness.macos.zip'
require_text "$PREPARER" 'runtime-helper-run-metadata.json'
require_text "$PREPARER" 'macos-app-run-jobs.json'
require_text "$PREPARER" 'runtime-helper-run-jobs.json'
require_text "$PREPARER" 'runtime-helper-archive-sha256.txt'
require_text "$PREPARER" 'runtimeHelperRunId'
require_text "$PREPARER" 'runtimeHelperHeadSha'
require_text "$PREPARER" 'distribution_bundle_manifest_sha256'
require_text "$PREPARER" 'runtime_bundle_after_sha256'
require_text "$PREPARER" 'stage_runner_boot_age_seconds_at_job_start'
require_text "$PREPARER" 'if [ "$macos_artifact_runner_name" = "$runtime_helper_runner_name" ]; then'
require_text "$PREPARER" 'MACOS_ARTIFACT_ID="$macos_artifact_id"'
require_text "$PREPARER" 'MACOS_ARTIFACT_REPOSITORY="$macos_artifact_repository"'
require_text "$PREPARER" 'MACOS_ARTIFACT_DIGEST="$macos_artifact_digest"'
require_text "$PREPARER" 'github_download_token="${GH_TOKEN:-}"'
require_text "$PREPARER" 'unset GH_TOKEN'
require_text "$PREPARER" 'if [ "$macos_scenario" = "distribution-e2e" ]; then'
require_text "$PREPARER" 'runtime_model_cache_path=""'
require_text "$PREPARER" 'runtime_model_source=first_launch_live_directory'
require_text "$PREPARER" 'RUNTIME_E2E_EXPECTED_FIRST_LAUNCH_PID="$distribution_launched_pid"'

require_text "$RUNTIME_RUNNER" 'prebuilt_helper_archive'
require_text "$RUNTIME_RUNNER" 'RUNTIME_E2E_APP="$helper_app"'
require_text "$RUNTIME_RUNNER" 'helper-host-loadability.txt'
require_text "$RUNTIME_RUNNER" 'helper-host-launch.exit-code.txt'
require_text "$RUNTIME_RUNNER" 'RuntimeE2EHarness" --help'
require_text "$ROOT/Tools/RuntimeE2EHarness/Info.plist" '<string>14.0</string>'
require_text "$RENDERED_OBSERVER" 'contentFilter: filter'
require_text "$RENDERED_OBSERVER" 'configuration: configuration'
reject_text "$RUNTIME_PREFLIGHT" 'macOS 15\.2 or newer'
require_text "$RUNTIME_RUNNER" 'runtime-translocation-new-crash-reports.txt'
require_text "$RUNTIME_RUNNER" 'runtime-translocation-termination-events.tsv'
require_text "$RUNTIME_RUNNER" 'DISTRIBUTION_E2E_CAPTURE_MAPPED_CODE_UNTIL_EXIT=true'
require_text "$VOICEINK_SESSION" 'RUNTIME_E2E_VOICEINK_TERMINATION_EVENTS'
require_text "$RUNTIME_RUNNER" 'source "$repo_root/scripts/macos-distribution-runtime-handoff.sh"'
require_text "$RUNTIME_RUNNER" 'distribution_runtime_validate_handoff'
require_text "$RUNTIME_RUNNER" 'distribution-runtime-handoff.txt'
require_text "$RUNTIME_RUNNER" 'first_launch_termination=normal'
require_text "$HANDOFF_HELPER" 'requires only the verified first-launch PID'
require_text "$HANDOFF_HELPER" 'must not use an external model cache'
require_text "$HANDOFF_HELPER" 'did not create the live model directory'

distribution_termination_line="$(
  grep -n '^  terminate_runtime_voiceink_pid "$expected_first_launch_pid"' \
    "$RUNTIME_RUNNER" \
    | head -n 1 \
    | cut -d: -f1
)"
model_prepare_line="$(
  grep -n '^runtime_prepare_pinned_model \\' "$RUNTIME_RUNNER" \
    | head -n 1 \
    | cut -d: -f1
)"
if [ -z "$distribution_termination_line" ] \
  || [ -z "$model_prepare_line" ] \
  || [ "$distribution_termination_line" -ge "$model_prepare_line" ]; then
  echo "distribution E2E must stop first launch before model hydration" >&2
  exit 1
fi

require_text "$RUNNER" 'com.apple.quarantine'
require_text "$RUNNER" 'Safari'
require_text "$RUNNER" 'Finder'
require_text "$RUNNER" 'Double-click the app in Finder.'
require_text "$RUNNER" 'open -R "$extracted_app"'
require_text "$RUNNER" 'gatekeeper-finder-reveal-exit-code.txt'
require_text "$RUNNER" 'APFS'
require_text "$RUNNER" 'AppTranslocation'
require_text "$RUNNER" 'DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=true'
require_text "$RUNNER" 'DISTRIBUTION_E2E_REQUIRE_APPKIT_FINISHED=true'
require_text "$RUNNER" 'verify-macos-distribution-launch.sh'
require_text "$RUNNER" 'macos-bundle-manifest.sh'
require_text "$RUNNER" 'GATEKEEPER ACTION REQUIRED'
require_text "$RUNNER" 'Confirm Finder Extraction Complete.command'
require_text "$RUNNER" 'Confirm Finder Follow-up Extraction.command'
require_text "$RUNNER" '/bin/date -u +%Y-%m-%dT%H:%M:%SZ > "$confirmation_path"'
require_text "$RUNNER" 'archive-utility-recursive'
require_text "$RUNNER" 'finder-extraction-mode.txt'
require_text "$RUNNER" 'expected-inner-app-files.sha256'
require_text "$RUNNER" 'compare_macos_bundle_to_manifest'
require_text "$RUNNER" 'Finder-extracted app does not match the hash-verified inner ZIP'
require_text "$RUNNER" 'macos-finder-extraction-state.sh'
require_text "$RUNNER" 'ditto -x -k "$expected_inner_archive" "$reference_root"'
require_text "$RUNNER" 'Confirm Gatekeeper Not Opened.command'
require_text "$RUNNER" 'Confirm Roma First Launch Ready.command'
require_text "$RUNNER" 'finder-archive-utility-unified-log.txt'
require_text "$RUNNER" 'extracted-app-compatibility.txt'
require_text "$RUNNER" 'app requires macOS'
require_text "$RUNNER" 'approval-window-process-events.txt'
require_text "$RUNNER" 'approval-window-new-crash-reports.txt'
require_text "$RUNNER" 'approval-window-unified-log.txt'
require_text "$RUNNER" 'fresh-tcc-user.txt'
require_text "$RUNNER" 'fresh-tcc-system.txt'
require_text "$RUNNER" 'api.github.com/repos/$repository/actions/artifacts/$artifact_id/zip'
require_text "$RUNNER" 'Authorization: Bearer $github_download_token'
require_text "$RUNNER" 'browser-download-origin.txt'
require_text "$RUNNER" 'open location artifactURL'
require_text "$RUNNER" 'wait_for_matching_browser_download'
require_text "$RUNNER" 'downloaded GitHub Actions archive does not match its artifact digest'
require_text "$RUNNER" 'unset GH_TOKEN'
require_text "$RUNNER" 'approved first launch did not create the live FluidAudio model directory'
require_text "$RUNNER" 'first-launch-live-model-state.txt'
require_text "$RUNNER" 'live_model_state=created_by_verified_first_launch'

reject_text "$RUNNER" 'xattr[[:space:]]+-(c|d|cr|dr)'
reject_text "$RUNNER" 'codesign[[:space:]].*--(force|sign)'
reject_text "$RUNNER" 'unzip[[:space:]]'
reject_text "$RUNNER" 'kill[[:space:]]+-CONT'
reject_text "$RUNNER" '(whisper|Sparkle|MediaRemoteAdapter)'
reject_text "$RUNNER" 'ExFAT'
reject_text "$RUNNER" 'http://127\.0\.0\.1'
reject_text "$RUNNER" 'python3[[:space:]]+-m[[:space:]]+http\.server'
reject_text "$RUNNER" 'browser-download-url\.txt'
reject_text "$RUNNER" 'Confirm (First|Second) Finder Extraction\.command'
reject_text "$RUNNER" '/usr/bin/date'
reject_text "$RUNNER" 'tell application "Finder"'

ditto_extraction_count="$(grep -Ec 'ditto[[:space:]].*-x' "$RUNNER")"
if [[ "$ditto_extraction_count" -ne 1 ]]; then
  echo "distribution E2E must use one CLI extraction, only for the expected reference bundle" >&2
  exit 1
fi

echo "macOS distribution E2E contract checks passed"
