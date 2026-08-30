#!/usr/bin/env bash
#
# Import the Developer ID Application certificate into a temporary keychain.
# Reads MACOS_CERTIFICATE_P12_BASE64 and MACOS_CERTIFICATE_PASSWORD from the
# environment; no secret is ever written to the repository or to the log.
#
# Prints the keychain path on stdout and, in GitHub Actions, exports
# `keychain_path` and `signing_identity` through $GITHUB_OUTPUT.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/lib.sh
. "$SCRIPT_DIR/lib.sh"

rel_require_macos
[ -n "${MACOS_CERTIFICATE_P12_BASE64:-}" ] || rel_fail "MACOS_CERTIFICATE_P12_BASE64 is not set"
[ -n "${MACOS_CERTIFICATE_PASSWORD:-}" ] || rel_fail "MACOS_CERTIFICATE_PASSWORD is not set"

KEYCHAIN_PATH="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/roma-release-signing.keychain-db"
KEYCHAIN_PASSWORD="${MACOS_KEYCHAIN_PASSWORD:-$(uuidgen)}"
CERT_PATH="$(mktemp "${TMPDIR:-/tmp}/certificate.XXXXXXXX.p12")"
trap 'rm -f "$CERT_PATH"' EXIT

printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$CERT_PATH"

rel_step "Creating a temporary signing keychain"
security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

rel_step "Importing the Developer ID certificate"
security import "$CERT_PATH" -k "$KEYCHAIN_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security -f pkcs12
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')

IDENTITY="$(rel_resolve_developer_id_identity || true)"
[ -n "$IDENTITY" ] || rel_fail "no Developer ID Application identity in the imported keychain"
rel_ok "identity: $IDENTITY"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "keychain_path=$KEYCHAIN_PATH"
    echo "signing_identity=$IDENTITY"
  } >> "$GITHUB_OUTPUT"
fi
printf '%s\n' "$KEYCHAIN_PATH"
