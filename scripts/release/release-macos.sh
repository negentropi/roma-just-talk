#!/usr/bin/env bash
#
# End-to-end macOS release pipeline for "roma just talk".
#
#   build  ->  sign nested code, then the app  ->  notarize  ->  staple
#          ->  package (ZIP/DMG)  ->  validate the packaged artifact
#
# Every stage is fatal: nothing is published unless the exact artifact that
# will be uploaded expands cleanly, verifies, and launches.
#
# Usage:
#   release-macos.sh [--mode auto|developer-id|adhoc] [--out-dir <dir>]
#                    [--configuration Release] [--dmg]
#                    [--skip-deps] [--skip-notarize] [--skip-validate]
#                    [--skip-launch] [--require-signing]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/release/lib.sh
. "$SCRIPT_DIR/lib.sh"

MODE="auto"
OUT_DIR="$REPO_ROOT/build/release"
CONFIGURATION="Release"
MAKE_DMG=0
SKIP_DEPS=0
SKIP_NOTARIZE=0
SKIP_VALIDATE=0
SKIP_LAUNCH=0
REQUIRE_SIGNING=0
KEYCHAIN="${MACOS_KEYCHAIN_PATH:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --dmg) MAKE_DMG=1; shift ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-validate) SKIP_VALIDATE=1; shift ;;
    --skip-launch) SKIP_LAUNCH=1; shift ;;
    --require-signing) REQUIRE_SIGNING=1; shift ;;
    --keychain) KEYCHAIN="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) rel_fail "unknown argument: $1" ;;
  esac
done

rel_require_macos
cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

########################################
rel_step "Resolving the signing mode"
IDENTITY=""
if [ "$MODE" = "auto" ] || [ "$MODE" = "developer-id" ]; then
  IDENTITY="$(rel_resolve_developer_id_identity || true)"
fi

if [ -n "$IDENTITY" ]; then
  MODE="developer-id"
  TEAM_ID="${MACOS_TEAM_ID:-$(rel_team_id_from_identity "$IDENTITY")}"
  rel_ok "Developer ID signing: $IDENTITY (team $TEAM_ID)"
else
  if [ "$REQUIRE_SIGNING" -eq 1 ] || [ "$MODE" = "developer-id" ]; then
    rel_fail "no Developer ID Application identity is available, but signing was required. Run scripts/release/check-signing-credentials.sh to see what is missing."
  fi
  MODE="adhoc"
  TEAM_ID=""
  rel_warn "no Developer ID identity found - falling back to an AD-HOC DEVELOPMENT build."
  rel_warn "Ad-hoc artifacts must never be published to GitHub Releases."
fi

########################################
if [ "$SKIP_DEPS" -eq 0 ]; then
  rel_step "Preparing dependencies (whisper.xcframework)"
  make setup
fi

########################################
BUILD_ARGS="--mode $MODE --out-dir $OUT_DIR --configuration $CONFIGURATION"
[ -n "$KEYCHAIN" ] && BUILD_ARGS="$BUILD_ARGS --keychain $KEYCHAIN"
# shellcheck disable=SC2086
"$SCRIPT_DIR/build-macos-app.sh" $BUILD_ARGS

APP="$(cat "$OUT_DIR/app-path.txt")"
[ -d "$APP" ] || rel_fail "the build did not produce an app bundle"

########################################
if [ "$MODE" = "developer-id" ]; then
  KEYCHAIN_ARG=""
  if [ -n "$KEYCHAIN" ]; then KEYCHAIN_ARG="--keychain $KEYCHAIN"; fi
  # shellcheck disable=SC2086
  "$SCRIPT_DIR/sign-macos-app.sh" --app "$APP" --identity "$IDENTITY" $KEYCHAIN_ARG
else
  "$SCRIPT_DIR/sign-macos-app.sh" --app "$APP" --adhoc
fi

########################################
NOTARIZED=0
if [ "$MODE" = "developer-id" ] && [ "$SKIP_NOTARIZE" -eq 0 ]; then
  "$SCRIPT_DIR/notarize-macos-app.sh" --app "$APP"
  NOTARIZED=1
elif [ "$MODE" = "developer-id" ]; then
  rel_warn "notarization skipped (--skip-notarize); the artifact is not publishable"
else
  rel_warn "notarization skipped for the ad-hoc development build"
fi

########################################
if [ "$MODE" = "developer-id" ]; then
  "$SCRIPT_DIR/package-macos-app.sh" --app "$APP" --out-dir "$OUT_DIR" \
    $([ "$MAKE_DMG" -eq 1 ] && echo --dmg) --identity "$IDENTITY"
else
  "$SCRIPT_DIR/package-macos-app.sh" --app "$APP" --out-dir "$OUT_DIR" \
    $([ "$MAKE_DMG" -eq 1 ] && echo --dmg)
fi

ZIP_PATH="$OUT_DIR/$RELEASE_ZIP_NAME"
DMG_PATH="$OUT_DIR/$RELEASE_DMG_NAME"

if [ "$MAKE_DMG" -eq 1 ] && [ "$NOTARIZED" -eq 1 ]; then
  "$SCRIPT_DIR/notarize-macos-app.sh" --artifact "$DMG_PATH"
fi

########################################
if [ "$SKIP_VALIDATE" -eq 1 ]; then
  rel_warn "artifact validation skipped (--skip-validate)"
else
  VALIDATE_ARGS=""
  if [ "$MODE" = "developer-id" ]; then
    [ -n "$TEAM_ID" ] && VALIDATE_ARGS="--expect-team-id $TEAM_ID"
    [ "$NOTARIZED" -eq 1 ] && VALIDATE_ARGS="$VALIDATE_ARGS --expect-notarized"
    [ "$NOTARIZED" -eq 1 ] || VALIDATE_ARGS="$VALIDATE_ARGS --require-hardened-runtime"
  else
    VALIDATE_ARGS="--allow-adhoc"
  fi
  [ "$SKIP_LAUNCH" -eq 1 ] && VALIDATE_ARGS="$VALIDATE_ARGS --skip-launch"

  # shellcheck disable=SC2086
  "$SCRIPT_DIR/validate-macos-artifact.sh" --artifact "$ZIP_PATH" $VALIDATE_ARGS
  if [ "$MAKE_DMG" -eq 1 ]; then
    # shellcheck disable=SC2086
    "$SCRIPT_DIR/validate-macos-artifact.sh" --artifact "$DMG_PATH" $VALIDATE_ARGS
  fi
fi

########################################
rel_step "Release pipeline complete"
rel_info "mode:       $MODE"
rel_info "notarized:  $([ "$NOTARIZED" -eq 1 ] && echo yes || echo no)"
rel_info "app:        $APP"
rel_info "zip:        $ZIP_PATH"
[ "$MAKE_DMG" -eq 1 ] && rel_info "dmg:        $DMG_PATH"
if [ "$MODE" = "adhoc" ]; then
  rel_warn "this is a DEVELOPMENT artifact - do not upload it to GitHub Releases"
else
  rel_ok "artifact is ready to upload"
fi
