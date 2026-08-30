#!/usr/bin/env bash
#
# Regression tests for the macOS release pipeline.
#
# These build a miniature app bundle whose layout matches the shipped app -
# a versioned MediaRemoteAdapter.framework loaded through
# @executable_path/../Frameworks - and then assert that:
#
#   1. an ad-hoc, hardened-runtime signature reproduces the exact macOS 26
#      failure ("different Team IDs"), which is the bug this pipeline fixes;
#   2. scripts/release/sign-macos-app.sh produces a bundle that loads;
#   3. scripts/release/validate-macos-artifact.sh accepts a good ZIP artifact;
#   4. it rejects a missing framework, an unsigned nested framework and a
#      broken framework symlink.
#
# Requires the Command Line Tools only (clang, codesign, ditto). No Xcode, no
# certificate, no network.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$REPO_ROOT/scripts/release"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/roma-release-test.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

APP_NAME="fixture app.app"
BUNDLE_ID="com.example.romareleasefixture"

make_fixture() {
  local dest="$1"
  local app="$dest/$APP_NAME"
  local fw="$app/Contents/Frameworks/MediaRemoteAdapter.framework"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$fw/Versions/A/Resources"

  cat > "$WORK/lib.c" <<'C'
int mra_answer(void) { return 42; }
C
  cat > "$WORK/main.c" <<'C'
#include <stdio.h>
#include <unistd.h>
extern int mra_answer(void);
int main(void) { printf("loaded=%d\n", mra_answer()); fflush(stdout); sleep(30); return 0; }
C
  clang -dynamiclib -o "$fw/Versions/A/MediaRemoteAdapter" "$WORK/lib.c" \
    -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" 2>/dev/null
  ( cd "$fw/Versions" && ln -sf A Current )
  ( cd "$fw" && ln -sf Versions/Current/MediaRemoteAdapter MediaRemoteAdapter && ln -sf Versions/Current/Resources Resources )

  cat > "$fw/Versions/A/Resources/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleIdentifier</key><string>com.example.MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
P

  clang -o "$app/Contents/MacOS/fixture" "$WORK/main.c" "$fw/Versions/A/MediaRemoteAdapter" \
    -Wl,-rpath,@executable_path/../Frameworks 2>/dev/null

  cat > "$app/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>fixture</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleName</key><string>fixture</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
P
  printf '%s\n' "$app"
}

run_validate() {
  RELEASE_APP_NAME="$APP_NAME" \
  RELEASE_BUNDLE_ID="$BUNDLE_ID" \
  RELEASE_REQUIRED_FRAMEWORKS="MediaRemoteAdapter.framework" \
  "$RELEASE_DIR/validate-macos-artifact.sh" "$@"
}

########################################
head_ "1. ad-hoc + hardened runtime reproduces the macOS 26 load failure"
STAGE="$WORK/repro"; mkdir -p "$STAGE"
APP="$(make_fixture "$STAGE")"
FW="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --options runtime --timestamp=none --sign - "$FW/Versions/A" >/dev/null 2>&1
codesign --force --options runtime --timestamp=none --sign - "$APP" >/dev/null 2>&1
OUTPUT="$("$APP/Contents/MacOS/fixture" 2>&1)"
if printf '%s' "$OUTPUT" | grep -q 'different Team IDs'; then
  ok "ad-hoc + hardened runtime is rejected by dyld (the bug being fixed)"
else
  bad "expected a Team ID load failure, got: $(printf '%s' "$OUTPUT" | head -2)"
fi

########################################
head_ "2. sign-macos-app.sh --adhoc produces a bundle that loads"
STAGE="$WORK/signed"; mkdir -p "$STAGE"
APP="$(make_fixture "$STAGE")"
if "$RELEASE_DIR/sign-macos-app.sh" --app "$APP" --adhoc >"$WORK/sign.log" 2>&1; then
  ok "sign-macos-app.sh completed"
else
  bad "sign-macos-app.sh failed"; sed 's/^/       /' "$WORK/sign.log"
fi
if grep -q 'Signing nested Mach-O images' "$WORK/sign.log" && \
   grep -q 'Signing the application bundle last' "$WORK/sign.log" && \
   [ "$(grep -c 'sign Contents/Frameworks/MediaRemoteAdapter.framework' "$WORK/sign.log")" -ge 1 ]; then
  ok "nested framework was signed before the app bundle"
else
  bad "signing order could not be confirmed from the log"
fi
"$APP/Contents/MacOS/fixture" >"$WORK/launch.log" 2>&1 &
LAUNCH_PID=$!
sleep 2
if kill -0 "$LAUNCH_PID" 2>/dev/null && grep -q 'loaded=42' "$WORK/launch.log"; then
  ok "the signed bundle launches and loads MediaRemoteAdapter.framework"
else
  bad "the signed bundle failed to launch: $(head -2 "$WORK/launch.log")"
fi
kill "$LAUNCH_PID" 2>/dev/null
wait "$LAUNCH_PID" 2>/dev/null

########################################
head_ "3. validate-macos-artifact.sh accepts a well-formed ZIP artifact"
ARTIFACTS="$WORK/artifacts"; mkdir -p "$ARTIFACTS"
ZIP="$ARTIFACTS/fixture.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
if run_validate --artifact "$ZIP" --allow-adhoc --skip-launch >"$WORK/validate-good.log" 2>&1; then
  ok "a good artifact passes validation"
else
  bad "a good artifact was rejected"; sed 's/^/       /' "$WORK/validate-good.log"
fi
for expected in "codesign --verify --deep --strict passed" \
                "MediaRemoteAdapter.framework is embedded" \
                "LC_RPATH contains @executable_path/../Frameworks" \
                "every nested code item shares the app's Team ID" \
                "no broken symlinks"; do
  if grep -qF "$expected" "$WORK/validate-good.log"; then
    ok "checked: $expected"
  else
    bad "validation never reported: $expected"
  fi
done

########################################
head_ "4. validate-macos-artifact.sh rejects broken artifacts"

# 4a. missing framework
STAGE="$WORK/missing"; mkdir -p "$STAGE"
APP_BAD="$(make_fixture "$STAGE")"
"$RELEASE_DIR/sign-macos-app.sh" --app "$APP_BAD" --adhoc >/dev/null 2>&1
rm -rf "$APP_BAD/Contents/Frameworks/MediaRemoteAdapter.framework"
ZIP_BAD="$ARTIFACTS/missing.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BAD" "$ZIP_BAD"
if run_validate --artifact "$ZIP_BAD" --allow-adhoc --skip-launch >"$WORK/validate-missing.log" 2>&1; then
  bad "an artifact without MediaRemoteAdapter.framework was accepted"
else
  ok "rejects a missing MediaRemoteAdapter.framework"
fi

# 4b. unsigned nested framework
STAGE="$WORK/unsigned"; mkdir -p "$STAGE"
APP_BAD="$(make_fixture "$STAGE")"
"$RELEASE_DIR/sign-macos-app.sh" --app "$APP_BAD" --adhoc >/dev/null 2>&1
codesign --remove-signature "$APP_BAD/Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" >/dev/null 2>&1
ZIP_BAD="$ARTIFACTS/unsigned.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BAD" "$ZIP_BAD"
if run_validate --artifact "$ZIP_BAD" --allow-adhoc --skip-launch >"$WORK/validate-unsigned.log" 2>&1; then
  bad "an artifact with unsigned nested code was accepted"
else
  ok "rejects unsigned or mis-signed nested code"
fi

# 4c. broken framework symlink
STAGE="$WORK/symlink"; mkdir -p "$STAGE"
APP_BAD="$(make_fixture "$STAGE")"
"$RELEASE_DIR/sign-macos-app.sh" --app "$APP_BAD" --adhoc >/dev/null 2>&1
BAD_FW="$APP_BAD/Contents/Frameworks/MediaRemoteAdapter.framework"
rm -f "$BAD_FW/Versions/Current"
ln -s NoSuchVersion "$BAD_FW/Versions/Current"
ZIP_BAD="$ARTIFACTS/symlink.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BAD" "$ZIP_BAD"
if run_validate --artifact "$ZIP_BAD" --allow-adhoc --skip-launch >"$WORK/validate-symlink.log" 2>&1; then
  bad "an artifact with a broken framework symlink was accepted"
else
  ok "rejects a broken framework symlink"
fi

# 4d. the original bug: ad-hoc signature + hardened runtime. The launch stage
#     of the validator must catch it, which is what stops it reaching users.
STAGE="$WORK/libval"; mkdir -p "$STAGE"
APP_BAD="$(make_fixture "$STAGE")"
"$RELEASE_DIR/sign-macos-app.sh" --app "$APP_BAD" --adhoc --hardened-runtime >/dev/null 2>&1
ZIP_BAD="$ARTIFACTS/libval.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BAD" "$ZIP_BAD"
if run_validate --artifact "$ZIP_BAD" --allow-adhoc --launch-timeout 4 >"$WORK/validate-libval.log" 2>&1; then
  bad "an artifact whose framework cannot be loaded was accepted"
else
  if grep -q 'different Team IDs' "$WORK/validate-libval.log"; then
    ok "the launch check rejects the Team ID / library-validation failure"
  else
    ok "rejects an artifact that fails to launch"
  fi
fi

########################################
head_ "5. release scripts parse cleanly"
for script in "$RELEASE_DIR"/*.sh; do
  if bash -n "$script"; then
    ok "$(basename "$script") parses"
  else
    bad "$(basename "$script") has a syntax error"
  fi
done

########################################
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
