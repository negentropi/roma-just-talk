#!/usr/bin/env bash
#
# Sign a built .app inside-out: every nested Mach-O image and code bundle is
# signed before the enclosing bundle, and the .app itself is signed last.
#
# `codesign --deep` is deliberately NOT used to produce signatures: it cannot
# apply per-bundle entitlements and silently mis-signs helper apps and XPC
# services. It is only used afterwards to verify the result.
#
# Usage:
#   sign-macos-app.sh --app <path> [--identity <name> | --adhoc]
#                     [--team-id <id>] [--entitlements <plist>]
#                     [--keychain <path>] [--no-hardened-runtime]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/lib.sh
. "$SCRIPT_DIR/lib.sh"

APP=""
IDENTITY=""
ADHOC=0
ENTITLEMENTS=""
KEYCHAIN=""
HARDENED_RUNTIME=1
HARDENED_RUNTIME_EXPLICIT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --adhoc) ADHOC=1; shift ;;
    --team-id) MACOS_TEAM_ID="$2"; export MACOS_TEAM_ID; shift 2 ;;
    --entitlements) ENTITLEMENTS="$2"; shift 2 ;;
    --keychain) KEYCHAIN="$2"; shift 2 ;;
    --hardened-runtime) HARDENED_RUNTIME=1; HARDENED_RUNTIME_EXPLICIT=1; shift ;;
    --no-hardened-runtime) HARDENED_RUNTIME=0; HARDENED_RUNTIME_EXPLICIT=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) rel_fail "unknown argument: $1" ;;
  esac
done

rel_require_macos
rel_require_tool codesign
[ -n "$APP" ] || rel_fail "--app is required"
[ -d "$APP" ] || rel_fail "app bundle not found: $APP"

if [ "$ADHOC" -eq 1 ]; then
  IDENTITY="-"
  # Ad-hoc signatures carry no Team ID, so Library Validation (which the
  # hardened runtime turns on) cannot match the app against its own embedded
  # frameworks. Development fallback builds therefore ship without the runtime
  # flag; production builds get a real Developer ID Team ID instead.
  [ "$HARDENED_RUNTIME_EXPLICIT" -eq 1 ] || HARDENED_RUNTIME=0
elif [ -z "$IDENTITY" ]; then
  IDENTITY="$(rel_resolve_developer_id_identity || true)"
  [ -n "$IDENTITY" ] || rel_fail "no Developer ID Application identity found. Pass --identity, set MACOS_SIGNING_IDENTITY, or use --adhoc for a development build."
fi

case "$IDENTITY" in
  -) SIGN_KIND="ad-hoc (development only)" ;;
  *) SIGN_KIND="$IDENTITY" ;;
esac

CODESIGN_COMMON="--force --generate-entitlement-der"
[ "$HARDENED_RUNTIME" -eq 1 ] && CODESIGN_COMMON="$CODESIGN_COMMON --options runtime"
if [ "$ADHOC" -eq 1 ]; then
  CODESIGN_COMMON="$CODESIGN_COMMON --timestamp=none"
else
  CODESIGN_COMMON="$CODESIGN_COMMON --timestamp"
fi

KEYCHAIN_ARGS=""
[ -n "$KEYCHAIN" ] && KEYCHAIN_ARGS="--keychain $KEYCHAIN"

WORK_DIR="$(rel_mktemp_dir)"
trap 'rm -rf "$WORK_DIR"' EXIT

SIGN_COUNT=0

# Extract the entitlements a nested bundle was shipped with so re-signing does
# not silently drop them (Sparkle's XPC services depend on theirs).
extract_entitlements() {
  local target="$1" out="$2"
  codesign -d --entitlements - --xml "$target" >"$out" 2>/dev/null || return 1
  [ -s "$out" ] || return 1
  plutil -lint "$out" >/dev/null 2>&1 || return 1
  return 0
}

# sign_one <target> <label> [entitlements] [quiet]
# With "quiet" a failure is reported through the return code instead of
# aborting, so the caller can try a different signing target.
sign_one() {
  local target="$1" label="$2" ent="${3:-}" quiet="${4:-}"
  local ent_file="$WORK_DIR/entitlements.$SIGN_COUNT.plist"
  local ent_args=""

  if [ -n "$ent" ]; then
    ent_args="--entitlements $ent"
  elif extract_entitlements "$target" "$ent_file"; then
    ent_args="--entitlements $ent_file"
  fi

  # shellcheck disable=SC2086
  if ! codesign $CODESIGN_COMMON $KEYCHAIN_ARGS $ent_args --sign "$IDENTITY" "$target" 2>&1 | sed 's/^/      /'; then
    [ "$quiet" = "quiet" ] && return 1
    rel_fail "codesign failed for $label"
  fi
  SIGN_COUNT=$((SIGN_COUNT + 1))
  return 0
}

rel_step "Signing $(basename "$APP")"
rel_info "identity:         $SIGN_KIND"
rel_info "hardened runtime: $([ "$HARDENED_RUNTIME" -eq 1 ] && echo enabled || echo disabled)"

rel_step "Clearing extended attributes"
# /usr/bin/xattr explicitly: a pip-installed `xattr` earlier in PATH has no -r.
/usr/bin/xattr -cr "$APP"

rel_step "Signing nested Mach-O images (deepest first)"
MAIN_EXECUTABLE="$(rel_main_executable "$APP")"
rel_nested_macho_files "$APP" > "$WORK_DIR/macho.txt"
while IFS= read -r macho; do
  [ -n "$macho" ] || continue
  [ "$macho" = "$MAIN_EXECUTABLE" ] && continue
  rel_info "sign ${macho#"$APP"/}"
  sign_one "$macho" "$macho"
done < "$WORK_DIR/macho.txt"

rel_step "Signing nested code bundles (deepest first)"
rel_nested_code_bundles "$APP" > "$WORK_DIR/bundles.txt"
while IFS= read -r bundle; do
  [ -n "$bundle" ] || continue
  rel_info "sign ${bundle#"$APP"/}"
  case "$bundle" in
    *.framework/Versions/*)
      # A versioned framework is signed at Versions/<X>. If that directory is
      # not a well-formed bundle (no Resources/Info.plist), fall back to the
      # framework root rather than shipping it unsigned.
      if ! sign_one "$bundle" "$bundle" "" quiet; then
        FRAMEWORK_ROOT="${bundle%%/Versions/*}"
        rel_warn "$(basename "$bundle") is not a signable bundle; signing ${FRAMEWORK_ROOT#"$APP"/} instead"
        sign_one "$FRAMEWORK_ROOT" "$FRAMEWORK_ROOT"
      fi
      ;;
    *) sign_one "$bundle" "$bundle" ;;
  esac
done < "$WORK_DIR/bundles.txt"

rel_step "Signing the application bundle last"
if [ -n "$ENTITLEMENTS" ]; then
  [ -f "$ENTITLEMENTS" ] || rel_fail "entitlements file not found: $ENTITLEMENTS"
  rel_info "entitlements: $ENTITLEMENTS"
  sign_one "$APP" "$APP" "$ENTITLEMENTS"
else
  rel_info "entitlements: preserved from the build"
  sign_one "$APP" "$APP"
fi

rel_step "Verifying the signature"
codesign --verify --deep --strict --verbose=4 "$APP" 2>&1 | sed 's/^/      /'
codesign -dv --verbose=4 "$APP" 2>&1 | sed 's/^/      /'
rel_ok "signed $((SIGN_COUNT)) code items in $APP"
