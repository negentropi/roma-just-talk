#!/usr/bin/env bash
set -euo pipefail

report_path="${1:-}"
if [ -z "$report_path" ]; then
  echo "usage: invalidate-tccd-cache.sh <report-path>" >&2
  exit 2
fi

service_target="gui/$(id -u)/com.apple.tccd"
service_pid() {
  launchctl print "$service_target" \
    | awk '$1 == "pid" && $2 == "=" && $3 ~ /^[0-9]+$/ { print $3; exit }'
}

tccd_before="$(service_pid)"
if [ -n "$tccd_before" ] && [[ ! "$tccd_before" =~ ^[0-9]+$ ]]; then
  echo "The current user's tccd service reported an invalid process ID." >&2
  exit 3
fi

if [ -n "$tccd_before" ]; then
  tccd_restarted="$(launchctl kickstart -kp "$service_target")"
else
  tccd_restarted="$(launchctl kickstart -p "$service_target")"
fi
tccd_after="$(service_pid)"

{
  printf 'service=%s\n' "$service_target"
  printf 'before=%s\n' "${tccd_before:-not-running}"
  printf 'kickstart=%s\n' "$tccd_restarted"
  printf 'after=%s\n' "$tccd_after"
} > "$report_path"

if [[ ! "$tccd_restarted" =~ ^[0-9]+$ ]] \
  || [[ ! "$tccd_after" =~ ^[0-9]+$ ]] \
  || { [ -n "$tccd_before" ] && [ "$tccd_restarted" = "$tccd_before" ]; } \
  || { [ -n "$tccd_before" ] && [ "$tccd_after" = "$tccd_before" ]; }; then
  echo "The current user's tccd cache was not replaced." >&2
  exit 4
fi
