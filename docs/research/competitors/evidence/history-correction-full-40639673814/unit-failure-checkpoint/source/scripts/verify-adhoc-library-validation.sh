#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <macos-app-bundle>" >&2
  exit 2
fi

app="$1"
info_plist="$app/Contents/Info.plist"

if [[ ! -f "$info_plist" ]]; then
  echo "missing macOS app Info.plist: $info_plist" >&2
  exit 1
fi

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
executable="$app/Contents/MacOS/$executable_name"

if [[ ! -x "$executable" ]]; then
  echo "missing app executable: $executable" >&2
  exit 1
fi

if ! signature_details="$(codesign -dvvv "$executable" 2>&1)"; then
  echo "could not inspect app signature: $executable" >&2
  exit 1
fi

if ! grep -q '^Signature=adhoc$' <<< "$signature_details"; then
  echo "expected an ad-hoc signed local app: $executable" >&2
  exit 1
fi

if ! grep -Eq '^CodeDirectory .*flags=.*\([^)]*runtime' <<< "$signature_details"; then
  echo "ad-hoc app is missing Hardened Runtime: $executable" >&2
  exit 1
fi

if ! linked_libraries="$(otool -L "$executable")"; then
  echo "could not inspect app dependencies: $executable" >&2
  exit 1
fi

bundle_relative_dependencies="$(
  awk 'NR > 1 && ($1 ~ /^@rpath\// || $1 ~ /^@loader_path\// || $1 ~ /^@executable_path\//) { print $1 }' \
    <<< "$linked_libraries"
)"

if [[ -n "$bundle_relative_dependencies" ]]; then
  library_validation_disabled="$(
    codesign -d --entitlements :- "$executable" 2>/dev/null \
      | plutil -convert json -o - - 2>/dev/null \
      | ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("com.apple.security.cs.disable-library-validation", false).equal?(true)' 2>/dev/null \
      || true
  )"

  if [[ "$library_validation_disabled" != "true" ]]; then
    echo "ad-hoc app loads bundle-relative code without disabling Library Validation:" >&2
    echo "$bundle_relative_dependencies" >&2
    exit 1
  fi
fi

if ! codesign --verify --deep --strict --verbose=4 "$app"; then
  echo "app fails strict deep signature verification: $app" >&2
  exit 1
fi

echo "Verified ad-hoc Library Validation contract: ${bundle_relative_dependencies:-no bundle-relative dependencies}"
