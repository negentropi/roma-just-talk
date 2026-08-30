#!/usr/bin/env bash
#
# Package a signed .app into the artifacts that are uploaded to GitHub
# Releases: a ditto ZIP (what the Homebrew cask and Sparkle consume) and,
# optionally, a DMG.
#
# Usage:
#   package-macos-app.sh --app <path> --out-dir <dir> [--zip-name <name>]
#                        [--dmg] [--dmg-name <name>] [--identity <name>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/lib.sh
. "$SCRIPT_DIR/lib.sh"

APP=""
OUT_DIR=""
ZIP_NAME="$RELEASE_ZIP_NAME"
DMG_NAME="$RELEASE_DMG_NAME"
MAKE_DMG=0
IDENTITY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --zip-name) ZIP_NAME="$2"; shift 2 ;;
    --dmg) MAKE_DMG=1; shift ;;
    --dmg-name) DMG_NAME="$2"; MAKE_DMG=1; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) rel_fail "unknown argument: $1" ;;
  esac
done

rel_require_macos
[ -n "$APP" ] || rel_fail "--app is required"
[ -d "$APP" ] || rel_fail "app bundle not found: $APP"
[ -n "$OUT_DIR" ] || rel_fail "--out-dir is required"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

ZIP_PATH="$OUT_DIR/$ZIP_NAME"
rel_step "Creating $ZIP_NAME"
rm -f "$ZIP_PATH"
# --sequesterRsrc keeps the signature and framework symlinks intact inside the
# archive; --keepParent preserves the .app directory itself.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"
rel_ok "$ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

if [ "$MAKE_DMG" -eq 1 ]; then
  rel_require_tool hdiutil
  DMG_PATH="$OUT_DIR/$DMG_NAME"
  STAGING="$(rel_mktemp_dir)"
  trap 'rm -rf "$STAGING"' EXIT
  rel_step "Creating $DMG_NAME"
  ditto "$APP" "$STAGING/$(basename "$APP")"
  ln -s /Applications "$STAGING/Applications"
  rm -f "$DMG_PATH"
  hdiutil create -volname "roma just talk" -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -ov "$DMG_PATH" >/dev/null
  if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ]; then
    rel_info "signing the disk image"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
  fi
  rel_ok "$DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
fi

rel_step "Checksums"
( cd "$OUT_DIR" && shasum -a 256 "$ZIP_NAME" $([ "$MAKE_DMG" -eq 1 ] && echo "$DMG_NAME") | tee checksums.txt )
