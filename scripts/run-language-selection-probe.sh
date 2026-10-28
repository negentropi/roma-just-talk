#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != self-test ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
    echo "Run the language selection probe only on a disposable GitHub-hosted Mac." >&2
    exit 2
  fi
  if [[ "$(id -u)" == 0 || "$(stat -f %u /dev/console)" != "$(id -u)" || "${RUNNER_TEMP:-}" != /* ]]; then
    echo "The probe must own the disposable logged-in desktop and RUNNER_TEMP." >&2
    exit 2
  fi
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$repo/scripts/verify-language-selection-probe.py" "$repo" "${RUNNER_TEMP:-/tmp}/language-selection-proof" "${1:-}"
