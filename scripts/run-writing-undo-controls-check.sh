#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run Undo control checks only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" || "${RUNNER_TEMP:-}" != /* ]]; then
    echo "The check must own the disposable logged-in desktop and RUNNER_TEMP." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$repo/scripts/verify-writing-undo-controls.py" "$repo" "${RUNNER_TEMP:-/tmp}/writing-undo-controls-proof" "${1:-}"
