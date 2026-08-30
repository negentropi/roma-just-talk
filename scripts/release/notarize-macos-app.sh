#!/usr/bin/env bash
#
# Submit a signed artifact to Apple's notary service and staple the ticket.
#
# Credentials are read from the environment only; nothing is ever hard-coded.
#   App Store Connect API key (preferred):
#     AC_API_KEY_ID, AC_API_ISSUER_ID, AC_API_KEY_BASE64 (or AC_API_KEY_PATH)
#   Apple ID fallback:
#     AC_APPLE_ID, AC_APP_PASSWORD, AC_TEAM_ID
#
# Usage: notarize-macos-app.sh --app <path> [--also <artifact> ...]
#        notarize-macos-app.sh --artifact <path>   # e.g. a DMG

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/lib.sh
. "$SCRIPT_DIR/lib.sh"

APP=""
EXTRA_ARTIFACTS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --also|--artifact) EXTRA_ARTIFACTS="$EXTRA_ARTIFACTS
$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) rel_fail "unknown argument: $1" ;;
  esac
done

rel_require_macos
rel_require_tool xcrun
if [ -n "$APP" ]; then
  [ -d "$APP" ] || rel_fail "app bundle not found: $APP"
elif [ -z "$EXTRA_ARTIFACTS" ]; then
  rel_fail "--app or --artifact is required"
fi

WORK_DIR="$(rel_mktemp_dir)"
trap 'rm -rf "$WORK_DIR"' EXIT

NOTARY_ARGS=""
if [ -n "${AC_API_KEY_ID:-}" ] && [ -n "${AC_API_ISSUER_ID:-}" ] && { [ -n "${AC_API_KEY_BASE64:-}" ] || [ -n "${AC_API_KEY_PATH:-}" ]; }; then
  KEY_PATH="${AC_API_KEY_PATH:-}"
  if [ -z "$KEY_PATH" ]; then
    KEY_PATH="$WORK_DIR/AuthKey_${AC_API_KEY_ID}.p8"
    printf '%s' "$AC_API_KEY_BASE64" | base64 --decode > "$KEY_PATH"
    chmod 600 "$KEY_PATH"
  fi
  [ -f "$KEY_PATH" ] || rel_fail "App Store Connect API key not readable"
  NOTARY_ARGS="--key $KEY_PATH --key-id $AC_API_KEY_ID --issuer $AC_API_ISSUER_ID"
  rel_info "notarizing with the App Store Connect API key $AC_API_KEY_ID"
elif [ -n "${AC_APPLE_ID:-}" ] && [ -n "${AC_APP_PASSWORD:-}" ] && [ -n "${AC_TEAM_ID:-}" ]; then
  NOTARY_ARGS="--apple-id $AC_APPLE_ID --password $AC_APP_PASSWORD --team-id $AC_TEAM_ID"
  rel_info "notarizing with the Apple ID $AC_APPLE_ID"
else
  rel_fail "no notarization credentials. Set AC_API_KEY_ID + AC_API_ISSUER_ID + AC_API_KEY_BASE64, or AC_APPLE_ID + AC_APP_PASSWORD + AC_TEAM_ID."
fi

submit() {
  local artifact="$1"
  local submission_log="$WORK_DIR/notary.json"
  rel_step "Submitting $(basename "$artifact") to the notary service"
  # shellcheck disable=SC2086
  if ! xcrun notarytool submit "$artifact" $NOTARY_ARGS --wait --timeout 45m --output-format json > "$submission_log"; then
    cat "$submission_log" >&2 || true
    rel_fail "notarytool submit failed for $artifact"
  fi
  cat "$submission_log"
  local status submission_id
  status="$(plutil -extract status raw -o - "$submission_log" 2>/dev/null || echo unknown)"
  submission_id="$(plutil -extract id raw -o - "$submission_log" 2>/dev/null || echo '')"
  if [ "$status" != "Accepted" ]; then
    if [ -n "$submission_id" ]; then
      rel_warn "fetching the notarization log for $submission_id"
      # shellcheck disable=SC2086
      xcrun notarytool log "$submission_id" $NOTARY_ARGS >&2 || true
    fi
    rel_fail "notarization was not accepted (status: $status)"
  fi
  rel_ok "notarization accepted for $(basename "$artifact")"
}

if [ -n "$APP" ]; then
  APP_ZIP="$WORK_DIR/notarize.zip"
  rel_step "Preparing the notarization payload"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_ZIP"
  submit "$APP_ZIP"

  rel_step "Stapling the ticket to the app"
  xcrun stapler staple -v "$APP" 2>&1 | tail -5 | sed 's/^/      /'
  xcrun stapler validate "$APP" | sed 's/^/      /'
  rel_ok "stapled $APP"
fi

printf '%s\n' "$EXTRA_ARTIFACTS" | while IFS= read -r artifact; do
  [ -n "$artifact" ] || continue
  [ -e "$artifact" ] || rel_fail "artifact not found: $artifact"
  submit "$artifact"
  rel_step "Stapling the ticket to $(basename "$artifact")"
  xcrun stapler staple -v "$artifact" 2>&1 | tail -5 | sed 's/^/      /'
  xcrun stapler validate "$artifact" | sed 's/^/      /'
done
