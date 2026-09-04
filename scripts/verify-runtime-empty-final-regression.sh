#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 known-bad <report> <contract> <launch-events> <termination-events>" >&2
  echo "       $0 fixed <report> <contract> <launch-events> <termination-events> <known-bad-report> <known-bad-contract>" >&2
}

if [[ $# -lt 5 || $# -gt 7 ]]; then
  usage
  exit 2
fi

expectation="$1"
report="$2"
contract="$3"
launch_events="$4"
termination_events="$5"
known_bad_report="${6:-}"
known_bad_contract="${7:-}"

case "$expectation" in
  known-bad) [[ $# -eq 5 ]] || { usage; exit 2; } ;;
  fixed)
    if [[ $# -ne 7 ]]; then
      echo "fixed proof requires a verified known-bad report and evidence contract" >&2
      exit 2
    fi
    ;;
  *) usage; exit 2 ;;
esac

for required_file in "$report" "$contract" "$launch_events" "$termination_events"; do
  [[ -f "$required_file" ]] || { echo "runtime E2E evidence does not exist: $required_file" >&2; exit 2; }
done
if [[ "$expectation" == "fixed" ]]; then
  for required_file in "$known_bad_report" "$known_bad_contract"; do
    [[ -f "$required_file" ]] || { echo "verified known-bad evidence does not exist: $required_file" >&2; exit 2; }
  done
fi
command -v jq >/dev/null 2>&1 || { echo "jq is required to verify runtime E2E evidence" >&2; exit 2; }
command -v shasum >/dev/null 2>&1 || { echo "shasum is required to verify runtime E2E evidence" >&2; exit 2; }

validate_contract() {
  jq -e '
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
  ' "$1" >/dev/null 2>&1
}

report_configuration() {
  jq -cS '.configuration | with_entries(select(.value != null)) | del(.audioDirectory, .voiceInkAppPath, .voiceInkBuildDirectory)' "$1"
}

ensure_report_matches_contract() {
  local candidate_report="$1" candidate_contract="$2"
  jq -e '.cases | type == "array"' "$candidate_report" >/dev/null 2>&1 || {
    echo "runtime E2E report has no cases array: $candidate_report" >&2
    return 1
  }
  [[ "$(jq -cS '.configuration' "$candidate_contract")" == "$(report_configuration "$candidate_report")" ]] || {
    echo "runtime E2E report does not match its evidence contract" >&2
    return 1
  }
}

validate_contract "$contract" || { echo "runtime E2E evidence contract is invalid" >&2; exit 2; }
ensure_report_matches_contract "$report" "$contract" || exit 1

# Known-bad failures define the only profile the fixed proof may cure. A report
# with another failure, a different target tuple, or out-of-order symptoms is
# not evidence for this bug.
derive_known_bad_profile() {
  jq -ce '
    def ordered_empty_final:
      [ .latencyTrace.events[]? | { name, details: (.details // "") } ] as $events
      | ([ $events[] | select(.name == "streaming_event.first_partial" and (.details | test("(^|[[:space:]])chars=[1-9][0-9]*($|[[:space:]])"))) ] | length > 0)
      and [range(0; $events | length) | select($events[.].name == "fluid_streaming.final_asr.end")] as $finals
      | [range(0; $events | length) | select($events[.].name == "streaming_event.first_commit")] as $commits
      | ($finals | length) == 1
      and ($commits | length) == 1
      and ($events[$finals[0]].details | test("(^|[[:space:]])chars=0($|[[:space:]])"))
      and ($events[$commits[0]].details | test("(^|[[:space:]])chars=0($|[[:space:]])"))
      and $finals[0] < $commits[0];
    . as $report
    | ([.cases[] | select(.assessment.passed != true)]) as $failed
    | if ($failed | length) == 0 then error("no failed cases") else . end
    | if ($failed | all(
        . as $case
        | any($report.configuration.targets[]; . == $case.target)
          and any($report.preflight.targets[]?;
            {id, displayName, bundleIdentifier} == ($case.target | {id, displayName, bundleIdentifier})
          )
          and (.textScenario == "empty" or .textScenario == "existingText")
          and .assessment.status == "emptyTranscript"
          and ordered_empty_final
      )) then . else error("different failed case") end
    | ($failed | map(.target | tojson) | unique) as $target_keys
    | if ($target_keys | length) == 1 then . else error("split targets") end
    | {
        target: $failed[0].target,
        scenarios: ($failed | map(.textScenario) | unique | sort),
        failedCaseIDs: ($failed | map(.id // "<missing-case-id>"))
      }
  ' "$1"
}

ensure_complete_matrix() {
  jq -e '
    . as $report
    | (["empty", "existingText"]) as $scenarios
    | (.configuration.targets) as $targets
    | (.configuration.repetitions) as $repetitions
    | (.cases | length == ($targets | length) * ($scenarios | length) * $repetitions)
    and all($targets[]; . as $target
      | all($scenarios[]; . as $scenario
        | ([ $report.cases[]
            | select(.target == $target and .textScenario == $scenario)
            | .repetition
          ] | sort) == [range(1; $repetitions + 1)]
      )
    )
  ' "$1" >/dev/null 2>&1
}

validate_report_state() {
  local candidate_report="$1" label="$2"
  jq -e '.fatalError == null' "$candidate_report" >/dev/null || { echo "$label contains a fatal error" >&2; return 1; }
  jq -e '.restoredOriginalState == true' "$candidate_report" >/dev/null || { echo "$label did not restore original state" >&2; return 1; }
  jq -e '(.preflight.voiceInk.runningPaths | type == "array" and length == 0) and (.voiceInkSession.originallyRunningPaths | type == "array" and length == 0)' "$candidate_report" >/dev/null || { echo "$label did not begin from a stopped app" >&2; return 1; }
  jq -e '.configuration.repetitions == 5 and .configuration.voiceInkLifecycle == "relaunchPerCase"' "$candidate_report" >/dev/null || { echo "$label did not use five relaunch-per-case trials" >&2; return 1; }
}

validate_report_state "$report" "runtime E2E report" || exit 1
if [[ "$expectation" == "fixed" ]]; then
  validate_report_state "$known_bad_report" "verified known-bad report" || exit 1
  validate_contract "$known_bad_contract" || { echo "verified known-bad evidence contract is invalid" >&2; exit 2; }
  ensure_report_matches_contract "$known_bad_report" "$known_bad_contract" || exit 1
fi

ensure_complete_matrix "$report" || { echo "runtime E2E report did not contain the complete 20-case smoke matrix" >&2; exit 1; }
if [[ "$expectation" == "fixed" ]]; then
  ensure_complete_matrix "$known_bad_report" || { echo "verified known-bad report did not contain the complete 20-case smoke matrix" >&2; exit 1; }
fi

profile_source="$report"
[[ "$expectation" == "fixed" ]] && profile_source="$known_bad_report"
profile="$(derive_known_bad_profile "$profile_source")" || {
  if [[ "$expectation" == "known-bad" ]]; then
    echo "no case reproduced the live-partial to empty-final bug" >&2
  else
    echo "verified known-bad report did not reproduce one exact empty-final profile" >&2
  fi
  exit 1
}

if [[ "$expectation" == "known-bad" ]]; then
  jq -e '.summary.passed == false' "$report" >/dev/null || { echo "known-bad report summary did not fail" >&2; exit 1; }
else
  jq -e '.summary.passed == true and all(.cases[]; .assessment.passed == true)' "$report" >/dev/null || {
    echo "fixed report did not pass every case" >&2
    exit 1
  }
fi
voiceink_app_path="$(jq -r '.configuration.voiceInkAppPath // empty' "$report")"
[[ -n "$voiceink_app_path" ]] || { echo "runtime E2E report has no VoiceInk app path" >&2; exit 1; }
case_count="$(jq -r '.cases | length' "$report")"
launch_count="$(awk 'length($0) > 0 { count++ } END { print count + 0 }' "$launch_events")"
[[ "$launch_count" -eq "$case_count" ]] || { echo "fresh-process lifecycle did not record one launch per runtime case" >&2; exit 1; }
if ! awk -F '\t' -v expected_path="$voiceink_app_path" 'NF != 6 || $2 !~ /^[0-9]+$/ || length($3) != 64 || $3 !~ /^[0-9a-f]+$/ || $3 != $4 || $5 != expected_path { exit 1 }' "$launch_events"; then echo "fresh-process launch evidence is invalid" >&2; exit 1; fi
launch_unique_count="$({ awk -F '\t' '{ print $2 }' "$launch_events" | LC_ALL=C sort -nu; } | awk 'END { print NR + 0 }')"
[[ "$launch_unique_count" -eq "$launch_count" ]] || { echo "fresh-process lifecycle reused a Roma process" >&2; exit 1; }
termination_count="$(awk 'length($0) > 0 { count++ } END { print count + 0 }' "$termination_events")"
[[ "$termination_count" -eq "$case_count" ]] || { echo "fresh-process lifecycle did not record one termination per runtime case" >&2; exit 1; }
if ! awk -F '\t' 'NF != 2 || $2 !~ /^[0-9]+$/ { exit 1 }' "$termination_events"; then echo "fresh-process termination evidence is invalid" >&2; exit 1; fi
termination_unique_count="$({ awk -F '\t' '{ print $2 }' "$termination_events" | LC_ALL=C sort -nu; } | awk 'END { print NR + 0 }')"
[[ "$termination_unique_count" -eq "$termination_count" ]] || { echo "fresh-process lifecycle terminated a Roma process more than once" >&2; exit 1; }
lifecycle_temp="$(mktemp -d "${TMPDIR:-/tmp}/roma-empty-final-lifecycle.XXXXXX")"
trap 'rm -rf "$lifecycle_temp"' EXIT
awk -F '\t' '{ print $2 }' "$launch_events" | LC_ALL=C sort -nu > "$lifecycle_temp/launched-pids.txt"
awk -F '\t' '{ print $2 }' "$termination_events" | LC_ALL=C sort -nu > "$lifecycle_temp/terminated-pids.txt"
cmp -s "$lifecycle_temp/launched-pids.txt" "$lifecycle_temp/terminated-pids.txt" || { echo "fresh-process launch and termination PIDs differ" >&2; exit 1; }

contract_sha256="$(shasum -a 256 "$contract" | awk '{print $1}')"
fixed_analysis=""
if [[ "$expectation" == "fixed" ]]; then
  known_bad_contract_sha256="$(shasum -a 256 "$known_bad_contract" | awk '{print $1}')"
  [[ "$contract_sha256" == "$known_bad_contract_sha256" ]] || { echo "fixed and known-bad evidence contracts differ" >&2; exit 1; }
  fixed_analysis="$(jq -ce --argjson profile "$profile" '
    def ordered_fallback:
      [ .latencyTrace.events[]? | { name, details: (.details // "") } ] as $events
      | ([ $events[] | select(.name == "streaming_event.first_partial" and (.details | test("(^|[[:space:]])chars=[1-9][0-9]*($|[[:space:]])"))) ] | length > 0)
      and [range(0; $events | length) | select($events[.].name == "fluid_streaming.final_asr.end")] as $finals
      | [range(0; $events | length) | select($events[.].name == "fluid_streaming.commit.fallback_to_hypothesis")] as $fallbacks
      | [range(0; $events | length) | select($events[.].name == "streaming_event.first_commit")] as $commits
      | ($finals | length) == 1
      and ($fallbacks | length) == 1
      and ($commits | length) == 1
      and ($events[$finals[0]].details | test("(^|[[:space:]])chars=0($|[[:space:]])"))
      and ($events[$fallbacks[0]].details | test("(^|[[:space:]])chars=[1-9][0-9]*($|[[:space:]])"))
      and ($events[$commits[0]].details | test("(^|[[:space:]])chars=[1-9][0-9]*($|[[:space:]])"))
      and $finals[0] < $fallbacks[0]
      and $fallbacks[0] < $commits[0];
    . as $report
    | {
        scenarioMatches: [
          $profile.scenarios[] as $scenario
          | {
              scenario: $scenario,
              caseIDs: [
                $report.cases[]
                | select(
                    .target == $profile.target
                      and .textScenario == $scenario
                      and .assessment.passed == true
                      and ((.visibleText.text // "") | test("[^[:space:]]"))
                      and ordered_fallback
                  )
                | .id // "<missing-case-id>"
              ]
            }
        ]
      }
  ' "$report")" || {
    echo "could not analyze fixed empty-final report" >&2
    exit 1
  }
  if ! jq -e '.scenarioMatches | length > 0 and all(.[]; (.caseIDs | length) > 0)' \
    <<< "$fixed_analysis" >/dev/null; then
    echo "fixed report did not prove ordered fallback delivery for every affected baseline scenario" >&2
    exit 1
  fi
fi

printf 'runtime_empty_final_expectation=%s\n' "$expectation"
printf 'evidence_contract_sha256=%s\n' "$contract_sha256"
printf 'fresh_process_count=%s\n' "$launch_count"
printf 'affected_target=%s\n' "$(jq -c '.target' <<< "$profile")"
while IFS= read -r scenario; do printf 'affected_text_scenario=%s\n' "$scenario"; done < <(jq -r '.scenarios[]' <<< "$profile")
if [[ "$expectation" == "known-bad" ]]; then
  while IFS= read -r case_id; do printf 'matching_case_id=%s\n' "$case_id"; done < <(jq -r '.failedCaseIDs[]' <<< "$profile")
else
  while IFS= read -r case_id; do printf 'baseline_matching_case_id=%s\n' "$case_id"; done < <(jq -r '.failedCaseIDs[]' <<< "$profile")
  while IFS=$'\t' read -r scenario case_id; do
    printf 'fixed_matching_case=%s\t%s\n' "$scenario" "$case_id"
  done < <(jq -r '.scenarioMatches[] | .scenario as $scenario | .caseIDs[] | [$scenario, .] | @tsv' <<< "$fixed_analysis")
fi
