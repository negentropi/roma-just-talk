#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <workflow-file> <commit-sha> [required-artifact ...]" >&2
  exit 2
fi

workflow="$1"
commit_sha="$2"
shift 2
required_artifacts=("$@")

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

if [[ ! "$GITHUB_REPOSITORY" =~ ^[^/]+/[^/]+$ ]]; then
  echo "invalid GITHUB_REPOSITORY: $GITHUB_REPOSITORY" >&2
  exit 2
fi

if [[ ! "$workflow" =~ ^[A-Za-z0-9._-]+\.ya?ml$ ]]; then
  echo "invalid workflow filename: $workflow" >&2
  exit 2
fi

if [[ ! "$commit_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "invalid commit SHA: $commit_sha" >&2
  exit 2
fi

runs="$(
  gh api --method GET --paginate --slurp \
    "repos/$GITHUB_REPOSITORY/actions/workflows/$workflow/runs" \
    -f "head_sha=$commit_sha" \
    -f status=success \
    -f per_page=100
)"

reusable_run_id=""
while IFS= read -r run_id; do
  [[ -n "$run_id" ]] || continue
  artifacts="$(
    gh api --method GET --paginate --slurp \
      "repos/$GITHUB_REPOSITORY/actions/runs/$run_id/artifacts" \
      -f per_page=100
  )"
  reusable=true

  for artifact_name in "${required_artifacts[@]}"; do
    if ! jq -e --arg name "$artifact_name" '
      [.[].artifacts[]]
      | any(.name == $name and .expired == false and .size_in_bytes > 0)
    ' <<<"$artifacts" >/dev/null; then
      reusable=false
      break
    fi
  done

  if [[ "$reusable" == true ]]; then
    reusable_run_id="$run_id"
    break
  fi
done < <(jq -r '.[].workflow_runs[].id' <<<"$runs")

if [[ -n "$reusable_run_id" ]]; then
  echo "Reusable exact-SHA result: workflow=$workflow sha=$commit_sha run=$reusable_run_id"
  hit=true
else
  echo "No reusable exact-SHA result with every required artifact: workflow=$workflow sha=$commit_sha"
  hit=false
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'hit=%s\nrun_id=%s\n' "$hit" "$reusable_run_id" >>"$GITHUB_OUTPUT"
else
  printf 'hit=%s\nrun_id=%s\n' "$hit" "$reusable_run_id"
fi
