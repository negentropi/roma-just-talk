#!/usr/bin/env bash
#
# Build "roma just talk.app" for distribution.
#
# developer-id mode: xcodebuild archive + exportArchive with the Developer ID
#                    method, so Xcode embeds and signs nested code correctly.
# adhoc mode:        the historical unsigned local build, kept only as an
#                    explicit development fallback.
#
# Usage:
#   build-macos-app.sh --mode developer-id|adhoc --out-dir <dir>
#                      [--configuration Release] [--team-id <id>]
#                      [--identity <name>] [--keychain <path>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/release/lib.sh
. "$SCRIPT_DIR/lib.sh"

MODE="developer-id"
OUT_DIR=""
CONFIGURATION="Release"
IDENTITY=""
KEYCHAIN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --team-id) MACOS_TEAM_ID="$2"; export MACOS_TEAM_ID; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --keychain) KEYCHAIN="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) rel_fail "unknown argument: $1" ;;
  esac
done

rel_require_macos
rel_require_tool xcodebuild
[ -n "$OUT_DIR" ] || rel_fail "--out-dir is required"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

DERIVED_DATA="$OUT_DIR/DerivedData"
ARCHIVE_PATH="$OUT_DIR/RomaJustTalk.xcarchive"
EXPORT_DIR="$OUT_DIR/export"
APP_PATH="$EXPORT_DIR/$RELEASE_APP_NAME"

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

cd "$REPO_ROOT"

case "$MODE" in
  developer-id)
    if [ -z "$IDENTITY" ]; then
      IDENTITY="$(rel_resolve_developer_id_identity || true)"
      [ -n "$IDENTITY" ] || rel_fail "no Developer ID Application identity available; pass --identity or use --mode adhoc for a development build"
    fi
    TEAM_ID="${MACOS_TEAM_ID:-$(rel_team_id_from_identity "$IDENTITY")}"
    [ -n "$TEAM_ID" ] || rel_fail "cannot determine the team id; set MACOS_TEAM_ID or pass --team-id"

    rel_step "Archiving ($CONFIGURATION, Developer ID, team $TEAM_ID)"
    XCODE_ARGS=""
    [ -n "$KEYCHAIN" ] && XCODE_ARGS="OTHER_CODE_SIGN_FLAGS=--keychain=$KEYCHAIN"
    # shellcheck disable=SC2086
    xcodebuild archive \
      -project VoiceInk.xcodeproj \
      -scheme VoiceInk \
      -configuration "$CONFIGURATION" \
      -destination 'generic/platform=macOS' \
      -derivedDataPath "$DERIVED_DATA" \
      -archivePath "$ARCHIVE_PATH" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="$IDENTITY" \
      "CODE_SIGN_IDENTITY[sdk=macosx*]=$IDENTITY" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      ENABLE_HARDENED_RUNTIME=YES \
      ENABLE_DEBUG_DYLIB=NO \
      ENABLE_PREVIEWS=NO \
      $XCODE_ARGS

    rel_step "Exporting the archive"
    EXPORT_OPTIONS="$OUT_DIR/ExportOptions.plist"
    cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>destination</key><string>export</string>
  <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS" \
      -exportPath "$EXPORT_DIR"
    ;;

  adhoc)
    rel_warn "ad-hoc mode produces a DEVELOPMENT build. It is not suitable for a public release."
    rel_step "Building ($CONFIGURATION, ad-hoc)"
    xcodebuild build \
      -project VoiceInk.xcodeproj \
      -scheme VoiceInk \
      -configuration "$CONFIGURATION" \
      -destination 'generic/platform=macOS' \
      -derivedDataPath "$DERIVED_DATA" \
      -xcconfig LocalBuild.xcconfig \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=YES \
      DEVELOPMENT_TEAM="" \
      ENABLE_DEBUG_DYLIB=NO \
      ENABLE_PREVIEWS=NO \
      CODE_SIGN_ENTITLEMENTS="$REPO_ROOT/VoiceInk/VoiceInk.local.entitlements" \
      SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
      build
    BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$RELEASE_APP_NAME"
    [ -d "$BUILT_APP" ] || rel_fail "built app not found at $BUILT_APP"
    ditto "$BUILT_APP" "$APP_PATH"
    ;;

  *) rel_fail "unknown --mode: $MODE (expected developer-id or adhoc)" ;;
esac

[ -d "$APP_PATH" ] || rel_fail "expected exported app at $APP_PATH"

rel_step "Build result"
rel_info "app: $APP_PATH"
for framework in $RELEASE_REQUIRED_FRAMEWORKS; do
  if [ -d "$APP_PATH/Contents/Frameworks/$framework" ]; then
    rel_ok "embedded $framework"
  else
    rel_fail "$framework was not embedded into $APP_PATH/Contents/Frameworks"
  fi
done

printf '%s\n' "$APP_PATH" > "$OUT_DIR/app-path.txt"
