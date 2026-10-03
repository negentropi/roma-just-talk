#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT/scripts/verify-macos-distribution-launch.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roma-distribution-launch.XXXXXX")"
APP="$TEMP_ROOT/Fixture.app"
LEAF_FRAMEWORK="$APP/Contents/Frameworks/RomaDistributionFixtureLeaf.framework"
MIDDLE_FRAMEWORKS="$APP/Contents/Frameworks/My Frameworks"
EVIDENCE="$TEMP_ROOT/evidence"
OUTPUT="$TEMP_ROOT/verifier-output.txt"
fixture_pid=""
unrelated_pid=""
capture_verifier_pid=""

cleanup() {
  local test_exit_code=$?
  if [[ -n "$capture_verifier_pid" ]]; then
    kill -KILL "$capture_verifier_pid" 2>/dev/null || true
    wait "$capture_verifier_pid" 2>/dev/null || true
  fi
  if [[ -n "$fixture_pid" ]]; then
    kill -KILL "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  if [[ -n "$unrelated_pid" ]]; then
    kill -KILL "$unrelated_pid" 2>/dev/null || true
    wait "$unrelated_pid" 2>/dev/null || true
  fi
  if [[ "${KEEP_DISTRIBUTION_FIXTURE:-false}" == "true" || "$test_exit_code" -ne 0 ]]; then
    echo "preserved distribution fixture: $TEMP_ROOT" >&2
  else
    rm -rf "$TEMP_ROOT"
  fi
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

start_fixture() {
  "$APP/Contents/MacOS/Fixture" \
    >"$TEMP_ROOT/fixture.stdout.log" \
    2>"$TEMP_ROOT/fixture.stderr.log" &
  fixture_pid=$!
  sleep 1
  if ! kill -0 "$fixture_pid" 2>/dev/null; then
    cat "$TEMP_ROOT/fixture.stderr.log" >&2
    return 1
  fi
}

stop_fixture() {
  if [[ -n "$fixture_pid" ]]; then
    kill -KILL "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
    fixture_pid=""
  fi
}

mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Frameworks" \
  "$MIDDLE_FRAMEWORKS" \
  "$APP/Contents/Frameworks/x86-only" \
  "$LEAF_FRAMEWORK/Versions/A/Resources" \
  "$EVIDENCE"

cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Fixture</string>
  <key>CFBundleIdentifier</key>
  <string>com.negentropi.RomaDistributionLaunchFixture</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST

cat >"$TEMP_ROOT/fixture.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>
PLIST

cat >"$LEAF_FRAMEWORK/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>RomaDistributionFixtureLeaf</string>
  <key>CFBundleIdentifier</key>
  <string>com.negentropi.RomaDistributionFixtureLeaf</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
PLIST

cat >"$TEMP_ROOT/library.c" <<'C'
extern int roma_distribution_fixture_leaf_value(void);

int roma_distribution_fixture_value(void) {
  return roma_distribution_fixture_leaf_value();
}
C

cat >"$TEMP_ROOT/leaf.c" <<'C'
int roma_distribution_fixture_leaf_value(void) { return 42; }
C

cat >"$TEMP_ROOT/opened-only.c" <<'C'
int roma_distribution_opened_only_value(void) { return 7; }
C

cat >"$TEMP_ROOT/optional-child.c" <<'C'
int roma_distribution_optional_child_value(void) { return 42; }
C

cat >"$TEMP_ROOT/optional-mapped.c" <<'C'
extern int roma_distribution_optional_child_value(void);
int roma_distribution_optional_mapped_value(void) {
  return roma_distribution_optional_child_value();
}
C

cat >"$TEMP_ROOT/optional-unmapped.c" <<'C'
extern int roma_distribution_optional_child_value(void);
int roma_distribution_optional_unmapped_value(void) {
  return roma_distribution_optional_child_value();
}
C

cat >"$TEMP_ROOT/optional-missing.c" <<'C'
int roma_distribution_optional_missing_value(void) { return 42; }
C

cat >"$TEMP_ROOT/main.m" <<'OBJC'
#import <AppKit/AppKit.h>
#include <fcntl.h>
extern int roma_distribution_fixture_value(void);
extern int roma_distribution_optional_mapped_value(void) __attribute__((weak_import));
extern int roma_distribution_optional_unmapped_value(void) __attribute__((weak_import));
extern int roma_distribution_optional_missing_value(void) __attribute__((weak_import));

int main(void) {
  if (roma_distribution_fixture_value() != 42) return 1;
  if (!roma_distribution_optional_mapped_value
      || roma_distribution_optional_mapped_value() != 42) return 3;
  if (roma_distribution_optional_unmapped_value
      || roma_distribution_optional_missing_value) return 4;
  NSString *openedOnlyPath = [
    [[NSBundle mainBundle] bundlePath]
    stringByAppendingPathComponent:
      @"Contents/Frameworks/libRomaDistributionOpenedOnly.dylib"
  ];
  int openedOnly = open([openedOnlyPath fileSystemRepresentation], O_RDONLY);
  if (openedOnly < 0) return 2;
  [NSApplication sharedApplication];
  [NSApp run];
  close(openedOnly);
  return 0;
}
OBJC

xcrun clang \
  -arch arm64 \
  -dynamiclib "$TEMP_ROOT/opened-only.c" \
  -Wl,-install_name,@rpath/libRomaDistributionOpenedOnly.dylib \
  -o "$APP/Contents/Frameworks/libRomaDistributionOpenedOnly.dylib"
xcrun clang \
  -arch arm64 \
  -dynamiclib "$TEMP_ROOT/optional-child.c" \
  -Wl,-install_name,@loader_path/libRomaDistributionOptionalChild.dylib \
  -o "$APP/Contents/Frameworks/libRomaDistributionOptionalChild.dylib"
xcrun clang \
  -arch arm64 \
  -dynamiclib "$TEMP_ROOT/optional-mapped.c" \
  "$APP/Contents/Frameworks/libRomaDistributionOptionalChild.dylib" \
  -Wl,-install_name,@rpath/libRomaDistributionOptionalMapped.dylib \
  -o "$APP/Contents/Frameworks/libRomaDistributionOptionalMapped.dylib"
xcrun clang \
  -arch arm64 \
  -dynamiclib "$TEMP_ROOT/optional-child.c" \
  -Wl,-install_name,@loader_path/libRomaDistributionAbsentOptionalChild.dylib \
  -o "$TEMP_ROOT/libRomaDistributionAbsentOptionalChild.dylib"
xcrun clang \
  -arch arm64 \
  -dynamiclib "$TEMP_ROOT/optional-unmapped.c" \
  "$TEMP_ROOT/libRomaDistributionAbsentOptionalChild.dylib" \
  -Wl,-install_name,@rpath/libSystem.B.dylib \
  -o "$APP/Contents/Frameworks/libSystem.B.dylib"
xcrun clang \
  -arch arm64 \
  -dynamiclib "$TEMP_ROOT/optional-missing.c" \
  -Wl,-install_name,@executable_path/../Frameworks/libRomaDistributionMissingWeak.dylib \
  -o "$TEMP_ROOT/libRomaDistributionMissingWeak.dylib"
xcrun clang \
  -arch arm64 \
  -dynamiclib "$TEMP_ROOT/leaf.c" \
  -Wl,-install_name,@rpath/RomaDistributionFixtureLeaf.framework/RomaDistributionFixtureLeaf \
  -o "$LEAF_FRAMEWORK/Versions/A/RomaDistributionFixtureLeaf"
ln -s A "$LEAF_FRAMEWORK/Versions/Current"
ln -s Versions/Current/RomaDistributionFixtureLeaf \
  "$LEAF_FRAMEWORK/RomaDistributionFixtureLeaf"
ln -s Versions/Current/Resources "$LEAF_FRAMEWORK/Resources"
xcrun clang \
  -arch arm64 \
  -dynamiclib "$TEMP_ROOT/library.c" \
  "$LEAF_FRAMEWORK/Versions/A/RomaDistributionFixtureLeaf" \
  '-Wl,-install_name,@rpath/libRoma Distribution Fixture.dylib' \
  -o "$TEMP_ROOT/libRoma Distribution Fixture-arm64.dylib"
xcrun clang \
  -arch x86_64 \
  -dynamiclib "$TEMP_ROOT/leaf.c" \
  -Wl,-install_name,@rpath/RomaDistributionWrongSliceOnly.dylib \
  -o "$APP/Contents/Frameworks/x86-only/RomaDistributionWrongSliceOnly.dylib"
xcrun clang \
  -arch x86_64 \
  -dynamiclib "$TEMP_ROOT/library.c" \
  "$APP/Contents/Frameworks/x86-only/RomaDistributionWrongSliceOnly.dylib" \
  '-Wl,-install_name,@rpath/libRoma Distribution Fixture.dylib' \
  -Wl,-rpath,@loader_path/x86-only \
  -o "$TEMP_ROOT/libRoma Distribution Fixture-x86_64.dylib"
lipo -create \
  "$TEMP_ROOT/libRoma Distribution Fixture-arm64.dylib" \
  "$TEMP_ROOT/libRoma Distribution Fixture-x86_64.dylib" \
  -output "$MIDDLE_FRAMEWORKS/libRoma Distribution Fixture.dylib"
xcrun clang \
  -arch arm64 \
  "$TEMP_ROOT/main.m" \
  "$MIDDLE_FRAMEWORKS/libRoma Distribution Fixture.dylib" \
  -Wl,-weak_library,"$APP/Contents/Frameworks/libSystem.B.dylib" \
  -Wl,-weak_library,"$TEMP_ROOT/libRomaDistributionMissingWeak.dylib" \
  -Wl,-weak_library,"$APP/Contents/Frameworks/libRomaDistributionOptionalMapped.dylib" \
  -framework AppKit \
  -Wl,-rpath,/usr/lib \
  '-Wl,-rpath,@executable_path/../Frameworks/My Frameworks' \
  -Wl,-rpath,@executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/Fixture"

codesign --force --sign - --options runtime \
  "$APP/Contents/Frameworks/libRomaDistributionOpenedOnly.dylib" >/dev/null
codesign --force --sign - --options runtime \
  "$APP/Contents/Frameworks/libRomaDistributionOptionalChild.dylib" >/dev/null
codesign --force --sign - --options runtime \
  "$APP/Contents/Frameworks/libRomaDistributionOptionalMapped.dylib" >/dev/null
codesign --force --sign - --options runtime \
  "$APP/Contents/Frameworks/libSystem.B.dylib" >/dev/null
codesign --force --sign - --options runtime "$LEAF_FRAMEWORK" >/dev/null
codesign --force --sign - --options runtime \
  "$APP/Contents/Frameworks/x86-only/RomaDistributionWrongSliceOnly.dylib" >/dev/null
codesign --force --sign - --options runtime \
  "$MIDDLE_FRAMEWORKS/libRoma Distribution Fixture.dylib" >/dev/null
codesign --force --sign - --options runtime \
  --entitlements "$TEMP_ROOT/fixture.entitlements" \
  "$APP" >/dev/null
xattr -w com.apple.quarantine \
  '0083;00000000;Safari;ROMA-DISTRIBUTION-E2E' \
  "$APP"

start_fixture
DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
DISTRIBUTION_E2E_REQUIRE_APPKIT_FINISHED=true \
DISTRIBUTION_E2E_STABILITY_SECONDS=1 \
  bash "$VERIFIER" "$APP" "$fixture_pid" "$EVIDENCE"

grep -Fq 'libRoma Distribution Fixture.dylib' \
  "$EVIDENCE/expected-mapped-bundle-code.txt"
grep -Fq 'RomaDistributionFixtureLeaf.framework/Versions/A/RomaDistributionFixtureLeaf' \
  "$EVIDENCE/expected-mapped-bundle-code.txt"
grep -Fq 'libRoma Distribution Fixture.dylib' \
  "$EVIDENCE/observed-mapped-bundle-code.txt"
grep -Fq 'RomaDistributionFixtureLeaf.framework/Versions/A/RomaDistributionFixtureLeaf' \
  "$EVIDENCE/observed-mapped-bundle-code.txt"
if grep -Fq 'RomaDistributionWrongSliceOnly.dylib' \
  "$EVIDENCE/expected-mapped-bundle-code.txt"; then
  echo "x86_64-only load commands must not enter the ARM64 dependency graph" >&2
  exit 1
fi
if grep -Fq 'libRomaDistributionOpenedOnly.dylib' \
  "$EVIDENCE/observed-mapped-bundle-code.txt"; then
  echo "an opened data file must not count as mapped code" >&2
  exit 1
fi
grep -Fq 'launch_verdict=passed' "$EVIDENCE/distribution-launch-verdict.txt"
grep -Fxq 'Contents/Frameworks/libRomaDistributionOptionalMapped.dylib' \
  "$EVIDENCE/observed-mapped-bundle-code.txt"
grep -Fxq 'Contents/Frameworks/libRomaDistributionOptionalChild.dylib' \
  "$EVIDENCE/expected-mapped-bundle-code.txt"
for optional_unmapped in libSystem.B.dylib libRomaDistributionMissingWeak.dylib \
  libRomaDistributionAbsentOptionalChild.dylib; do
  if grep -Fq "$optional_unmapped" "$EVIDENCE/expected-mapped-bundle-code.txt"; then
    echo "unmapped optional branch must not require bundled code: $optional_unmapped" >&2
    exit 1
  fi
done
grep -Fq $'LC_LOAD_WEAK_DYLIB\t@rpath/libSystem.B.dylib\tContents/Frameworks/libSystem.B.dylib\tunmapped' \
  "$EVIDENCE/optional-weak-dependencies.txt"
grep -Fq $'LC_LOAD_WEAK_DYLIB\t@executable_path/../Frameworks/libRomaDistributionMissingWeak.dylib\t\tunresolved' \
  "$EVIDENCE/optional-weak-dependencies.txt"

mkdir -p "$TEMP_ROOT/filtered-mapping-tools"
cat > "$TEMP_ROOT/filtered-mapping-tools/lsof" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
/usr/sbin/lsof "$@" | awk '$0 != "n" ENVIRON["HIDE_MAPPED_CODE_PATH"]'
SCRIPT
chmod +x "$TEMP_ROOT/filtered-mapping-tools/lsof"
for required_relative in \
  'Contents/Frameworks/My Frameworks/libRoma Distribution Fixture.dylib' \
  'Contents/Frameworks/RomaDistributionFixtureLeaf.framework/Versions/A/RomaDistributionFixtureLeaf' \
  'Contents/Frameworks/libRomaDistributionOptionalChild.dylib'; do
  expect_failure \
    "launched process did not map bundled dependency: $required_relative" \
    env PATH="$TEMP_ROOT/filtered-mapping-tools:$PATH" \
      HIDE_MAPPED_CODE_PATH="$(cd "$APP" && pwd -P)/$required_relative" \
      DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
      DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
      bash "$VERIFIER" "$APP" "$fixture_pid" "$EVIDENCE"
done

mutated_app="$TEMP_ROOT/Mutated.app"
ditto "$APP" "$mutated_app"
printf 'changed\n' > "$mutated_app/Contents/PkgInfo"
codesign --force --sign - --options runtime \
  --entitlements "$TEMP_ROOT/fixture.entitlements" \
  "$mutated_app" >/dev/null
expect_failure \
  'running process bundle does not match the downloaded app bundle' \
  env DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$mutated_app" "$fixture_pid" "$EVIDENCE"

tampered_app="$TEMP_ROOT/TamperedOptional.app"
ditto "$APP" "$tampered_app"
printf 'changed\n' >> "$tampered_app/Contents/Frameworks/libSystem.B.dylib"
expect_failure \
  'source app fails strict deep signature verification' \
  env DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$tampered_app" "$fixture_pid" "$EVIDENCE"

mkdir -p "$TEMP_ROOT/fake-tools"
cat > "$TEMP_ROOT/fake-tools/vmmap" <<'SCRIPT'
#!/usr/bin/env bash
echo 'Process: Fixture'
echo 'Code Type: X86-64 (Translated)'
SCRIPT
chmod +x "$TEMP_ROOT/fake-tools/vmmap"
expect_failure \
  'launched process is not native Apple Silicon' \
  env PATH="$TEMP_ROOT/fake-tools:$PATH" \
    DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$APP" "$fixture_pid" "$EVIDENCE"
stop_fixture

start_fixture
capture_evidence="$TEMP_ROOT/capture-evidence"
capture_app="$(cd "$APP" && pwd -P)"
mkdir -p "$capture_evidence" "$TEMP_ROOT/slow-inspection-tools"
cat > "$TEMP_ROOT/slow-inspection-tools/lsof" <<'SCRIPT'
#!/bin/bash
marker="$(dirname "$0")/delay-applied"
if [[ ! -e "$marker" ]]; then
  : > "$marker"
  sleep 3
fi
exec /usr/sbin/lsof "$@"
SCRIPT
chmod +x "$TEMP_ROOT/slow-inspection-tools/lsof"
PATH="$TEMP_ROOT/slow-inspection-tools:$PATH" \
DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
DISTRIBUTION_E2E_CAPTURE_MAPPED_CODE_UNTIL_EXIT=true \
DISTRIBUTION_E2E_CAPTURE_TIMEOUT_SECONDS=30 \
DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
  bash "$VERIFIER" "$APP" "$fixture_pid" "$capture_evidence" &
capture_verifier_pid=$!
capture_ready_deadline=$((SECONDS + 30))
until grep -Fxq "pid=$fixture_pid" "$capture_evidence/launch-identity.txt" 2>/dev/null \
  && grep -Fxq "$capture_app/Contents/MacOS/Fixture" "$capture_evidence/process-mapped-paths-through-runtime.txt" 2>/dev/null \
  && grep -Fxq "$capture_app/Contents/Frameworks/RomaDistributionFixtureLeaf.framework/Versions/A/RomaDistributionFixtureLeaf" "$capture_evidence/process-mapped-paths-through-runtime.txt" 2>/dev/null \
  && [[ -s "$capture_evidence/process-open-files-runtime-sample.txt" ]]; do
  if (( SECONDS >= capture_ready_deadline )) \
    || ! kill -0 "$fixture_pid" 2>/dev/null \
    || ! kill -0 "$capture_verifier_pid" 2>/dev/null; then
    echo 'Capture verifier did not observe the live fixture before termination' >&2
    exit 1
  fi
  sleep 0.1
done
stop_fixture
wait "$capture_verifier_pid"
capture_verifier_pid=""
grep -Fq 'capture_mapped_code_until_exit=true' \
  "$capture_evidence/distribution-launch-verdict.txt"

start_fixture
expect_failure \
  'launched process is not running through App Translocation' \
  env DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$APP" "$fixture_pid" "$EVIDENCE"
stop_fixture

start_fixture
expect_failure \
  'expected macOS 0.0.0' \
  env DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_EXPECTED_MACOS_VERSION=0.0.0 \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$APP" "$fixture_pid" "$EVIDENCE"
expect_failure \
  'expected macOS build NOTAREALBUILD' \
  env DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_EXPECTED_MACOS_VERSION="$(sw_vers -productVersion)" \
    DISTRIBUTION_E2E_EXPECTED_MACOS_BUILD=NOTAREALBUILD \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$APP" "$fixture_pid" "$EVIDENCE"
stop_fixture

sleep 30 &
unrelated_pid=$!
expect_failure \
  'running process does not map the expected app executable' \
  env DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$APP" "$unrelated_pid" "$EVIDENCE"
kill -KILL "$unrelated_pid" 2>/dev/null || true
wait "$unrelated_pid" 2>/dev/null || true
unrelated_pid=""

xattr -d com.apple.quarantine "$APP"
start_fixture
expect_failure \
  'source app is missing download quarantine' \
  env DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$APP" "$fixture_pid" "$EVIDENCE"
stop_fixture

xattr -w com.apple.quarantine \
  '0083;00000000;Safari;ROMA-DISTRIBUTION-E2E' \
  "$APP"
start_fixture
kill -STOP "$fixture_pid"
expect_failure \
  'launched process is stopped' \
  env DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$APP" "$fixture_pid" "$EVIDENCE"
stop_fixture

x86_app="$TEMP_ROOT/X86Only.app"
ditto "$APP" "$x86_app"
cp \
  "$APP/Contents/Frameworks/x86-only/RomaDistributionWrongSliceOnly.dylib" \
  "$x86_app/Contents/MacOS/Fixture"
chmod +x "$x86_app/Contents/MacOS/Fixture"
xattr -w com.apple.quarantine \
  '0083;00000000;Safari;ROMA-DISTRIBUTION-E2E' \
  "$x86_app"
expect_failure \
  'bundled Mach-O has no arm64 slice' \
  env DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=false \
    DISTRIBUTION_E2E_STABILITY_SECONDS=0 \
    bash "$VERIFIER" "$x86_app" 999999 "$EVIDENCE"

echo "macOS distribution launch verifier regression checks passed"
