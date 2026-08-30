#!/usr/bin/env bash
#
# Report which signing / notarization credentials are available.
#
# Prints a readable table and writes machine-readable results to
# $GITHUB_OUTPUT when running inside GitHub Actions:
#   signing_available=true|false
#   notarization_available=true|false
#   release_mode=developer-id|adhoc
#
# With --require, a missing credential is a hard failure (used for public
# releases). Without it the script always exits 0 so development builds can
# continue with the ad-hoc fallback.
#
# Usage: check-signing-credentials.sh [--require]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/lib.sh
. "$SCRIPT_DIR/lib.sh"

REQUIRE=0
[ "${1:-}" = "--require" ] && REQUIRE=1

MISSING=""
note_missing() { MISSING="$MISSING $1"; }

report() {
  if [ -n "${2:-}" ]; then
    rel_ok "$1 is set"
  else
    rel_warn "$1 is NOT set"
    note_missing "$1"
  fi
}

rel_step "Code-signing credentials"
report MACOS_CERTIFICATE_P12_BASE64 "${MACOS_CERTIFICATE_P12_BASE64:-}"
report MACOS_CERTIFICATE_PASSWORD "${MACOS_CERTIFICATE_PASSWORD:-}"
report MACOS_TEAM_ID "${MACOS_TEAM_ID:-}"
if [ -n "${MACOS_SIGNING_IDENTITY:-}" ]; then
  rel_ok "MACOS_SIGNING_IDENTITY is set (optional)"
else
  rel_info "MACOS_SIGNING_IDENTITY is not set (optional; resolved from the keychain)"
fi

SIGNING_AVAILABLE=false
if [ -n "${MACOS_CERTIFICATE_P12_BASE64:-}" ] && [ -n "${MACOS_CERTIFICATE_PASSWORD:-}" ] && [ -n "${MACOS_TEAM_ID:-}" ]; then
  SIGNING_AVAILABLE=true
elif rel_resolve_developer_id_identity >/dev/null 2>&1; then
  rel_ok "a Developer ID Application identity is already present in the keychain"
  SIGNING_AVAILABLE=true
fi

rel_step "Notarization credentials"
NOTARIZATION_AVAILABLE=false
if [ -n "${AC_API_KEY_ID:-}" ] && [ -n "${AC_API_ISSUER_ID:-}" ] && [ -n "${AC_API_KEY_BASE64:-}" ]; then
  rel_ok "App Store Connect API key credentials are set"
  NOTARIZATION_AVAILABLE=true
elif [ -n "${AC_APPLE_ID:-}" ] && [ -n "${AC_APP_PASSWORD:-}" ] && [ -n "${AC_TEAM_ID:-}" ]; then
  rel_ok "Apple ID notarization credentials are set"
  NOTARIZATION_AVAILABLE=true
else
  rel_warn "no notarization credentials"
  rel_info "set AC_API_KEY_ID + AC_API_ISSUER_ID + AC_API_KEY_BASE64 (preferred)"
  rel_info "or AC_APPLE_ID + AC_APP_PASSWORD + AC_TEAM_ID"
  note_missing "notarization-credentials"
fi

RELEASE_MODE=adhoc
[ "$SIGNING_AVAILABLE" = "true" ] && RELEASE_MODE=developer-id

rel_step "Result"
rel_info "signing_available=$SIGNING_AVAILABLE"
rel_info "notarization_available=$NOTARIZATION_AVAILABLE"
rel_info "release_mode=$RELEASE_MODE"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "signing_available=$SIGNING_AVAILABLE"
    echo "notarization_available=$NOTARIZATION_AVAILABLE"
    echo "release_mode=$RELEASE_MODE"
  } >> "$GITHUB_OUTPUT"
fi

if [ "$REQUIRE" -eq 1 ]; then
  if [ "$SIGNING_AVAILABLE" != "true" ] || [ "$NOTARIZATION_AVAILABLE" != "true" ]; then
    rel_err "a public release requires Developer ID signing and notarization."
    rel_err "missing configuration:$MISSING"
    rel_err "configure these as GitHub Actions secrets - see docs/macos-release-pipeline.md"
    exit 1
  fi
  rel_ok "all release credentials are configured"
fi
