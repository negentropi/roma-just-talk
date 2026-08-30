#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT/scripts/verify-adhoc-library-validation.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roma-adhoc-library-validation.XXXXXX")"
APP="$TEMP_ROOT/Fixture.app"
OUTPUT="$TEMP_ROOT/verifier-output.txt"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

expect_failure() {
  local expected_message="$1"
  shift

  if "$@" >"$OUTPUT" 2>&1; then
    echo "expected command to fail: $*" >&2
    cat "$OUTPUT" >&2
    exit 1
  fi

  if ! grep -Fq "$expected_message" "$OUTPUT"; then
    echo "failure did not contain: $expected_message" >&2
    cat "$OUTPUT" >&2
    exit 1
  fi
}

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"

cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Fixture</string>
  <key>CFBundleIdentifier</key>
  <string>com.negentropi.RomaAdhocLibraryValidationFixture</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST

cat >"$TEMP_ROOT/library.c" <<'C'
int roma_fixture_value(void) { return 0; }
C

cat >"$TEMP_ROOT/main.c" <<'C'
extern int roma_fixture_value(void);
int main(void) { return roma_fixture_value(); }
C

cat >"$TEMP_ROOT/boolean.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>
PLIST

cat >"$TEMP_ROOT/string.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key>
  <string>true</string>
</dict>
</plist>
PLIST

xcrun clang \
  -dynamiclib "$TEMP_ROOT/library.c" \
  -Wl,-install_name,@rpath/libRomaFixture.dylib \
  -o "$APP/Contents/Frameworks/libRomaFixture.dylib"
xcrun clang \
  "$TEMP_ROOT/main.c" \
  "$APP/Contents/Frameworks/libRomaFixture.dylib" \
  -Wl,-rpath,@executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/Fixture"

codesign --force --sign - --options runtime "$APP/Contents/Frameworks/libRomaFixture.dylib" >/dev/null
codesign --force --sign - --options runtime "$APP" >/dev/null
expect_failure \
  "without disabling Library Validation" \
  bash "$VERIFIER" "$APP"

codesign --force --sign - --options runtime \
  --entitlements "$TEMP_ROOT/string.entitlements" \
  "$APP" >/dev/null
expect_failure \
  "without disabling Library Validation" \
  bash "$VERIFIER" "$APP"

codesign --force --sign - --options runtime \
  --entitlements "$TEMP_ROOT/boolean.entitlements" \
  "$APP" >/dev/null
bash "$VERIFIER" "$APP" >/dev/null

cat >"$TEMP_ROOT/library.c" <<'C'
int roma_fixture_value(void) { return 1; }
C
xcrun clang \
  -dynamiclib "$TEMP_ROOT/library.c" \
  -Wl,-install_name,@rpath/libRomaFixture.dylib \
  -o "$APP/Contents/Frameworks/libRomaFixture.dylib"
codesign --force --sign - --options runtime "$APP/Contents/Frameworks/libRomaFixture.dylib" >/dev/null
expect_failure \
  "app fails strict deep signature verification" \
  bash "$VERIFIER" "$APP"

codesign --force --sign - \
  --entitlements "$TEMP_ROOT/boolean.entitlements" \
  "$APP" >/dev/null
expect_failure \
  "missing Hardened Runtime" \
  bash "$VERIFIER" "$APP"

echo "Ad-hoc Library Validation verifier regression checks passed"
