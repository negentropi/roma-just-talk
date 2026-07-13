#!/usr/bin/env bash
set -euo pipefail

repository="${NAMESPACE_E2E_REPOSITORY:-happyf-weallareeuropean/roma-just-talk}"
run_id="${1:-}"

command -v nsc >/dev/null 2>&1 || {
  echo "nsc is required: https://namespace.so/docs/reference/cli/installation" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "jq is required" >&2
  exit 1
}
nsc auth check-login >/dev/null

jobs="$(
  nsc github job list \
    --repository "$repository" \
    --running \
    --max_entries 20 \
    -o json
)"

if [ -n "$run_id" ]; then
  job_id="$(
    jq -r \
      --argjson run_id "$run_id" \
      '(. // []) | map(select(
        .workflow_name == "Prepare remote E2E stage"
        and .job_name == "Remote desktop ready"
        and .run_id == $run_id
      )) | sort_by(.created_at) | last | .job_id // empty' \
      <<< "$jobs"
  )"
else
  job_id="$(
    jq -r \
      '(. // []) | map(select(
        .workflow_name == "Prepare remote E2E stage"
        and .job_name == "Remote desktop ready"
      )) | sort_by(.created_at) | last | .job_id // empty' \
      <<< "$jobs"
  )"
fi

if [ -z "$job_id" ]; then
  echo "No running Remote desktop ready job found for $repository" >&2
  if [ -n "$run_id" ]; then
    echo "Requested GitHub run: $run_id" >&2
  fi
  exit 1
fi

job="$(nsc github job describe "$job_id" -o json)"
instance_id="$(jq -r '.runner.instance_id // empty' <<< "$job")"

if [ -z "$instance_id" ]; then
  echo "Namespace job $job_id has no running instance ID" >&2
  exit 1
fi

echo "GitHub job: $job_id"
echo "Namespace instance: $instance_id"
exec nsc vnc "$instance_id"
