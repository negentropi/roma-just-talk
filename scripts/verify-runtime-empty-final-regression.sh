#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <known-bad|fixed> <functional-smoke.json> <evidence-contract.json> <launch-events.tsv> <termination-events.tsv> [known-bad-contract.json]" >&2
}

if [[ $# -lt 5 || $# -gt 6 ]]; then
  usage
  exit 2
fi

expectation="$1"
report="$2"
contract="$3"
launch_events="$4"
termination_events="$5"
known_bad_contract="${6:-}"

case "$expectation" in
  known-bad)
    if [[ $# -ne 5 ]]; then
      usage
      exit 2
    fi
    ;;
  fixed)
    if [[ $# -ne 6 ]]; then
      echo "fixed proof requires a verified known-bad evidence contract" >&2
      exit 2
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac

[[ -f "$report" ]] || {
  echo "runtime E2E report does not exist: $report" >&2
  exit 2
}
[[ -f "$contract" ]] || {
  echo "runtime E2E evidence contract does not exist: $contract" >&2
  exit 2
}
[[ -f "$launch_events" ]] || {
  echo "runtime E2E launch evidence does not exist: $launch_events" >&2
  exit 2
}
[[ -f "$termination_events" ]] || {
  echo "runtime E2E termination evidence does not exist: $termination_events" >&2
  exit 2
}
if [[ "$expectation" == "fixed" && ! -f "$known_bad_contract" ]]; then
  echo "verified known-bad evidence contract does not exist: $known_bad_contract" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || {
  echo "jq is required to verify runtime E2E evidence" >&2
  exit 2
}
command -v shasum >/dev/null 2>&1 || {
  echo "shasum is required to verify runtime E2E evidence" >&2
  exit 2
}

if ! jq -e '.cases | type == "array"' "$report" >/dev/null 2>&1; then
  echo "runtime E2E report has no cases array: $report" >&2
  exit 2
fi

if ! jq -e '
  .schemaVersion == 1
    and (.toolingSha | type == "string" and length > 0)
    and .runtimeMode == "smoke"
    and (.requireAppTranslocation | type == "boolean")
    and (.platform.productVersion | type == "string" and length > 0)
    and (.platform.buildVersion | type == "string" and length > 0)
    and .platform.architecture == "arm64"
    and (.audio.sourceKind == "public" or .audio.sourceKind == "namespace")
    and (.audio.fixtureName | type == "string" and length > 0)
    and (.audio.sha256 | test("^[0-9a-f]{64}$"))
    and (.audio.durationSeconds | type == "number" and . > 0)
    and (.model.revision | test("^[0-9a-f]{40}$"))
    and (.model.manifestSha256 | test("^[0-9a-f]{64}$"))
    and .model.storage == "normal-application-support"
    and .model.prewarmOnWake == true
    and (.helperExecutableSha256 | test("^[0-9a-f]{64}$"))
    and .configuration.voiceInkBundleIdentifier == "com.negentropi.RomaJustTalk"
    and .configuration.repetitions == 5
    and .configuration.voiceInkLifecycle == "relaunchPerCase"
    and .configuration.targets == [
      {
        id: "textedit",
        displayName: "TextEdit",
        bundleIdentifier: "com.apple.TextEdit",
        kind: "document"
      },
      {
        id: "safari",
        displayName: "Safari",
        bundleIdentifier: "com.apple.Safari",
        kind: "browser"
      }
    ]
' "$contract" >/dev/null 2>&1; then
  echo "runtime E2E evidence contract is invalid" >&2
  exit 2
fi

analysis="$({
  jq -c --arg expectation "$expectation" '
    def has_positive_chars($event_name):
      any(
        .latencyTrace.events[]?;
        .name == $event_name
          and ((.details // "") | test("(^|[[:space:]])chars=[1-9][0-9]*($|[[:space:]])"))
      );
    def has_zero_chars($event_name):
      any(
        .latencyTrace.events[]?;
        .name == $event_name
          and ((.details // "") | test("(^|[[:space:]])chars=0($|[[:space:]])"))
      );
    def is_textedit_empty_trial:
      (.target == {
        id: "textedit",
        displayName: "TextEdit",
        bundleIdentifier: "com.apple.TextEdit",
        kind: "document"
      })
        and .textScenario == "empty";
    def reproduced_empty_final:
      is_textedit_empty_trial
        and .assessment.status == "emptyTranscript"
        and .assessment.passed == false
        and has_positive_chars("streaming_event.first_partial")
        and has_zero_chars("fluid_streaming.final_asr.end")
        and has_zero_chars("streaming_event.first_commit");
    def fixed_empty_final:
      is_textedit_empty_trial
        and .assessment.passed == true
        and ((.visibleText.text // "") | test("[^[:space:]]"))
        and has_positive_chars("streaming_event.first_partial")
        and has_zero_chars("fluid_streaming.final_asr.end")
        and has_positive_chars("fluid_streaming.commit.fallback_to_hypothesis")
        and has_positive_chars("streaming_event.first_commit");

    [
      .cases[]
      | select(is_textedit_empty_trial)
      | .repetition
    ] as $texteditEmptyRepetitions
    |
    {
      summaryPassed: .summary.passed,
      fatalError: .fatalError,
      restoredOriginalState: .restoredOriginalState,
      usedRequiredTrialConfiguration: (
        .configuration.repetitions == 5
          and .configuration.voiceInkLifecycle == "relaunchPerCase"
      ),
      hasRequiredTrialMatrix: (
        ($texteditEmptyRepetitions | length) == 5
          and ($texteditEmptyRepetitions | sort) == [1, 2, 3, 4, 5]
      ),
      hasCompleteSmokeMatrix: ((.cases | length) == 20),
      beganFromStoppedApp: (
        (.preflight.voiceInk.runningPaths | type == "array" and length == 0)
          and (.voiceInkSession.originallyRunningPaths | type == "array" and length == 0)
      ),
      failedCaseCount: ([.cases[] | select(.assessment.passed != true)] | length),
      unrelatedFailedCaseCount: (
        [.cases[] | select(.assessment.passed != true) | select(reproduced_empty_final | not)]
        | length
      ),
      matchingCaseIDs: [
        .cases[]
        | select(
            if $expectation == "known-bad"
            then reproduced_empty_final
            else fixed_empty_final
            end
          )
        | .id // "<missing-case-id>"
      ]
    }
  ' "$report"
})" || {
  echo "could not parse runtime E2E cases: $report" >&2
  exit 2
}

if ! jq -e '.fatalError == null' <<< "$analysis" >/dev/null; then
  echo "runtime E2E report contains a fatal error" >&2
  exit 1
fi
if ! jq -e '.restoredOriginalState == true' <<< "$analysis" >/dev/null; then
  echo "runtime E2E report did not restore original state" >&2
  exit 1
fi
if ! jq -e '.beganFromStoppedApp == true' <<< "$analysis" >/dev/null; then
  echo "runtime E2E report did not begin from a stopped app" >&2
  exit 1
fi
if ! jq -e '.usedRequiredTrialConfiguration == true' <<< "$analysis" >/dev/null; then
  echo "runtime E2E report did not use five relaunch-per-case trials" >&2
  exit 1
fi
if ! jq -e '.hasRequiredTrialMatrix == true' <<< "$analysis" >/dev/null; then
  echo "runtime E2E report did not contain five TextEdit empty-document repetitions" >&2
  exit 1
fi
if ! jq -e '.hasCompleteSmokeMatrix == true' <<< "$analysis" >/dev/null; then
  echo "runtime E2E report did not contain the complete 20-case smoke matrix" >&2
  exit 1
fi

contract_configuration="$(jq -cS '.configuration' "$contract")"
report_configuration="$(
  jq -cS '
    .configuration
    | with_entries(select(.value != null))
    | del(.audioDirectory, .voiceInkAppPath, .voiceInkBuildDirectory)
  ' "$report"
)"
if [[ "$contract_configuration" != "$report_configuration" ]]; then
  echo "runtime E2E report does not match its evidence contract" >&2
  exit 1
fi

voiceink_app_path="$(jq -r '.configuration.voiceInkAppPath // empty' "$report")"
if [[ -z "$voiceink_app_path" ]]; then
  echo "runtime E2E report has no VoiceInk app path" >&2
  exit 1
fi
case_count="$(jq -r '.cases | length' "$report")"
launch_count="$(awk 'length($0) > 0 { count++ } END { print count + 0 }' "$launch_events")"
if [[ "$launch_count" -ne "$case_count" ]]; then
  echo "fresh-process lifecycle did not record one launch per runtime case" >&2
  exit 1
fi
if ! awk -F '\t' -v expected_path="$voiceink_app_path" '
  NF != 6 { exit 1 }
  $2 !~ /^[0-9]+$/ { exit 1 }
  length($3) != 64 || $3 !~ /^[0-9a-f]+$/ { exit 1 }
  $3 != $4 { exit 1 }
  $5 != expected_path { exit 1 }
' "$launch_events"; then
  echo "fresh-process launch evidence is invalid" >&2
  exit 1
fi
launch_unique_count="$({ awk -F '\t' '{ print $2 }' "$launch_events" | LC_ALL=C sort -nu; } | awk 'END { print NR + 0 }')"
if [[ "$launch_unique_count" -ne "$launch_count" ]]; then
  echo "fresh-process lifecycle reused a Roma process" >&2
  exit 1
fi

termination_count="$(awk 'length($0) > 0 { count++ } END { print count + 0 }' "$termination_events")"
if [[ "$termination_count" -ne "$case_count" ]]; then
  echo "fresh-process lifecycle did not record one termination per runtime case" >&2
  exit 1
fi
if ! awk -F '\t' '
  NF != 2 { exit 1 }
  $2 !~ /^[0-9]+$/ { exit 1 }
' "$termination_events"; then
  echo "fresh-process termination evidence is invalid" >&2
  exit 1
fi
termination_unique_count="$({ awk -F '\t' '{ print $2 }' "$termination_events" | LC_ALL=C sort -nu; } | awk 'END { print NR + 0 }')"
if [[ "$termination_unique_count" -ne "$termination_count" ]]; then
  echo "fresh-process lifecycle terminated a Roma process more than once" >&2
  exit 1
fi

lifecycle_temp="$(mktemp -d "${TMPDIR:-/tmp}/roma-empty-final-lifecycle.XXXXXX")"
trap 'rm -rf "$lifecycle_temp"' EXIT
awk -F '\t' '{ print $2 }' "$launch_events" | LC_ALL=C sort -nu \
  > "$lifecycle_temp/launched-pids.txt"
awk -F '\t' '{ print $2 }' "$termination_events" | LC_ALL=C sort -nu \
  > "$lifecycle_temp/terminated-pids.txt"
if ! cmp -s \
  "$lifecycle_temp/launched-pids.txt" \
  "$lifecycle_temp/terminated-pids.txt"; then
  echo "fresh-process launch and termination PIDs differ" >&2
  exit 1
fi

contract_sha256="$(shasum -a 256 "$contract" | awk '{print $1}')"
if [[ "$expectation" == "fixed" ]]; then
  known_bad_contract_sha256="$(
    shasum -a 256 "$known_bad_contract" | awk '{print $1}'
  )"
  if [[ "$contract_sha256" != "$known_bad_contract_sha256" ]]; then
    echo "fixed and known-bad evidence contracts differ" >&2
    exit 1
  fi
fi

matching_case_count="$(jq -r '.matchingCaseIDs | length' <<< "$analysis")"
if [[ "$matching_case_count" -eq 0 ]]; then
  if [[ "$expectation" == "known-bad" ]]; then
    echo "no case reproduced the live-partial to empty-final bug" >&2
  else
    echo "no case proved the fixed empty-final fallback" >&2
  fi
  exit 1
fi

summary_passed="$(jq -r '.summaryPassed' <<< "$analysis")"
if [[ "$expectation" == "known-bad" ]]; then
  if [[ "$summary_passed" != "false" ]]; then
    echo "known-bad report summary did not fail" >&2
    exit 1
  fi
  if [[ "$(jq -r '.unrelatedFailedCaseCount' <<< "$analysis")" -ne 0 ]]; then
    echo "known-bad report contains a different failed case" >&2
    exit 1
  fi
else
  if [[ "$summary_passed" != "true" ]] \
    || [[ "$(jq -r '.failedCaseCount' <<< "$analysis")" -ne 0 ]]; then
    echo "fixed report did not pass every case" >&2
    exit 1
  fi
fi

printf 'runtime_empty_final_expectation=%s\n' "$expectation"
printf 'evidence_contract_sha256=%s\n' "$contract_sha256"
printf 'fresh_process_count=%s\n' "$launch_count"
while IFS= read -r case_id; do
  printf 'matching_case_id=%s\n' "$case_id"
done < <(jq -r '.matchingCaseIDs[]' <<< "$analysis")
