#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <known-bad|fixed> <functional-smoke.json>" >&2
  exit 2
fi

expectation="$1"
report="$2"

case "$expectation" in
  known-bad|fixed) ;;
  *)
    echo "usage: $0 <known-bad|fixed> <functional-smoke.json>" >&2
    exit 2
    ;;
esac

[[ -f "$report" ]] || {
  echo "runtime E2E report does not exist: $report" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || {
  echo "jq is required to verify runtime E2E evidence" >&2
  exit 2
}

if ! jq -e '.cases | type == "array"' "$report" >/dev/null 2>&1; then
  echo "runtime E2E report has no cases array: $report" >&2
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
    def reproduced_empty_final:
      .assessment.status == "emptyTranscript"
        and .assessment.passed == false
        and has_positive_chars("streaming_event.first_partial")
        and has_zero_chars("fluid_streaming.final_asr.end")
        and has_zero_chars("streaming_event.first_commit");
    def fixed_empty_final:
      .assessment.passed == true
        and ((.visibleText.text // "") | test("[^[:space:]]"))
        and has_positive_chars("streaming_event.first_partial")
        and has_zero_chars("fluid_streaming.final_asr.end")
        and has_positive_chars("fluid_streaming.commit.fallback_to_hypothesis")
        and has_positive_chars("streaming_event.first_commit");

    {
      summaryPassed: .summary.passed,
      fatalError: .fatalError,
      restoredOriginalState: .restoredOriginalState,
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
} 2>/dev/null)" || {
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
while IFS= read -r case_id; do
  printf 'matching_case_id=%s\n' "$case_id"
done < <(jq -r '.matchingCaseIDs[]' <<< "$analysis")
