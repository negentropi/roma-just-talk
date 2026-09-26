#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/macos-deployment-target-lib.sh"

assert_records() {
  local expected="$1"
  local fixture="$2"
  local actual
  actual="$(macos_load_command_records <<<"$fixture")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected load-command records: $actual" >&2
    exit 1
  fi
}

modern_macos_fixture=$'cmd LC_BUILD_VERSION\ncmdsize 32\nplatform 1\nminos 14.0\nsdk 26.0'
legacy_macos_fixture=$'cmd LC_VERSION_MIN_MACOSX\ncmdsize 16\nversion 10.13\nsdk 11.0'
ios_fixture=$'cmd LC_BUILD_VERSION\ncmdsize 32\nplatform 2\nminos 14.0\nsdk 26.0'
missing_fixture=$'cmd LC_SEGMENT_64\ncmdsize 72'

assert_records $'1\t14.0' "$modern_macos_fixture"
assert_records $'1\t10.13' "$legacy_macos_fixture"
assert_records $'2\t14.0' "$ios_fixture"
assert_records '' "$missing_fixture"

if ! macos_version_is_at_most 10.13 14.0; then
  echo "Older macOS versions should pass the 14.0 maximum" >&2
  exit 1
fi

if macos_version_is_at_most 14.1 14.0; then
  echo "macOS 14.1 should fail the 14.0 maximum" >&2
  exit 1
fi

if macos_version_is_at_most malformed 14.0 || macos_version_is_at_most '' 14.0; then
  echo "Malformed macOS versions should fail the minimum-version check" >&2
  exit 1
fi

echo "macOS deployment load-command fixtures passed."
