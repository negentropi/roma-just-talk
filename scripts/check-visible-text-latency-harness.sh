#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harness="$repo_root/.local-build/Tools/VisibleTextLatencyHarness"

if [[ ! -x "$harness" ]]; then
  echo "Build the latency harness first with: make latency-harness-app" >&2
  exit 2
fi

"$harness" --self-test
