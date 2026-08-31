#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIFIER="$ROOT/scripts/macos-finder-extraction-state.sh"
source "$ROOT/scripts/macos-bundle-manifest.sh"
TEST_ROOT="$(mktemp -d)"
VOLUME="$TEST_ROOT/Roma Distribution E2E"
OUTER="$VOLUME/roma.just.talk.app.zip"
INNER_FIXTURE="$TEST_ROOT/expected-inner.zip"
APP_NAME="roma just talk.app"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$VOLUME"
printf 'outer\n' > "$OUTER"
printf 'inner\n' > "$INNER_FIXTURE"
INNER_SHA256="$(shasum -a 256 "$INNER_FIXTURE" | awk '{print $1}')"

state_value() {
  local output="$1"
  local key="$2"
  awk -F '\t' -v key="$key" '$1 == key { sub(/^[^\t]*\t/, ""); print; exit }' \
    <<< "$output"
}

assert_state() {
  local expected="$1"
  local output
  output="$("$CLASSIFIER" "$VOLUME" "$OUTER" "$INNER_SHA256" "$APP_NAME")"
  [[ "$(state_value "$output" state)" == "$expected" ]] || {
    echo "expected Finder extraction state $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  }
  printf '%s\n' "$output"
}

pending_output="$(assert_state pending)"
[[ "$(state_value "$pending_output" app_count)" == 0 ]]
[[ "$(state_value "$pending_output" inner_count)" == 0 ]]

cp "$INNER_FIXTURE" "$VOLUME/inner app.zip"
separate_output="$(assert_state separate)"
[[ "$(state_value "$separate_output" inner_path)" == "$VOLUME/inner app.zip" ]]

mkdir -p "$VOLUME/$APP_NAME/Contents"
recursive_with_inner_output="$(assert_state recursive)"
[[ "$(state_value "$recursive_with_inner_output" app_path)" == "$VOLUME/$APP_NAME" ]]
printf 'bundled resource\n' > "$VOLUME/$APP_NAME/Contents/resource.zip"
assert_state recursive >/dev/null

rm "$VOLUME/inner app.zip"
assert_state recursive >/dev/null

mkdir -p "$VOLUME/duplicate/$APP_NAME"
assert_state invalid >/dev/null
rmdir "$VOLUME/duplicate/$APP_NAME" "$VOLUME/duplicate"

printf 'wrong archive\n' > "$VOLUME/wrong.zip"
assert_state invalid >/dev/null

REFERENCE_APP="$TEST_ROOT/reference/$APP_NAME"
PROVENANCE_APP="$TEST_ROOT/provenance/$APP_NAME"
EXPECTED_MANIFEST="$TEST_ROOT/expected-app.sha256"
OBSERVED_MANIFEST="$TEST_ROOT/observed-app.sha256"
MANIFEST_DIFF="$TEST_ROOT/app.diff"
mkdir -p \
  "$REFERENCE_APP/Contents/MacOS" \
  "$REFERENCE_APP/Contents/Frameworks/Fixture.framework/Versions/A"
printf 'main executable\n' > "$REFERENCE_APP/Contents/MacOS/roma just talk"
printf 'framework binary\n' \
  > "$REFERENCE_APP/Contents/Frameworks/Fixture.framework/Versions/A/Fixture"
ln -s A "$REFERENCE_APP/Contents/Frameworks/Fixture.framework/Versions/Current"
write_macos_bundle_manifest "$REFERENCE_APP" "$EXPECTED_MANIFEST"
mkdir -p "$(dirname "$PROVENANCE_APP")"
cp -R "$REFERENCE_APP" "$PROVENANCE_APP"
compare_macos_bundle_to_manifest \
  "$PROVENANCE_APP" "$EXPECTED_MANIFEST" "$OBSERVED_MANIFEST" "$MANIFEST_DIFF"

DIRECTORY_MODE="$(stat -f '%Lp' "$PROVENANCE_APP/Contents/Frameworks")"
chmod 700 "$PROVENANCE_APP/Contents/Frameworks"
if compare_macos_bundle_to_manifest \
  "$PROVENANCE_APP" "$EXPECTED_MANIFEST" "$OBSERVED_MANIFEST" "$MANIFEST_DIFF"; then
  echo "directory-mode-changed Finder app unexpectedly matched the expected inner ZIP" >&2
  exit 1
fi
grep -Fq 'Contents/Frameworks' "$MANIFEST_DIFF"
chmod "$DIRECTORY_MODE" "$PROVENANCE_APP/Contents/Frameworks"

ORIGINAL_MODE="$(stat -f '%Lp' "$PROVENANCE_APP/Contents/MacOS/roma just talk")"
chmod 600 "$PROVENANCE_APP/Contents/MacOS/roma just talk"
if compare_macos_bundle_to_manifest \
  "$PROVENANCE_APP" "$EXPECTED_MANIFEST" "$OBSERVED_MANIFEST" "$MANIFEST_DIFF"; then
  echo "mode-changed Finder app unexpectedly matched the expected inner ZIP" >&2
  exit 1
fi
grep -Fq 'mode=' "$MANIFEST_DIFF"
chmod "$ORIGINAL_MODE" "$PROVENANCE_APP/Contents/MacOS/roma just talk"

printf 'tampered\n' > "$PROVENANCE_APP/Contents/MacOS/roma just talk"
if compare_macos_bundle_to_manifest \
  "$PROVENANCE_APP" "$EXPECTED_MANIFEST" "$OBSERVED_MANIFEST" "$MANIFEST_DIFF"; then
  echo "tampered Finder app unexpectedly matched the expected inner ZIP" >&2
  exit 1
fi
grep -Fq 'Contents/MacOS/roma just talk' "$MANIFEST_DIFF"

cp -R "$REFERENCE_APP" "$TEST_ROOT/provenance-two.app"
rm "$TEST_ROOT/provenance-two.app/Contents/Frameworks/Fixture.framework/Versions/Current"
ln -s B "$TEST_ROOT/provenance-two.app/Contents/Frameworks/Fixture.framework/Versions/Current"
if compare_macos_bundle_to_manifest \
  "$TEST_ROOT/provenance-two.app" \
  "$EXPECTED_MANIFEST" \
  "$OBSERVED_MANIFEST" \
  "$MANIFEST_DIFF"; then
  echo "changed framework symlink unexpectedly matched the expected inner ZIP" >&2
  exit 1
fi
grep -Fq 'Fixture.framework/Versions/Current' "$MANIFEST_DIFF"

echo "macOS Finder extraction state checks passed"
