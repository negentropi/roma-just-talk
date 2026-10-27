#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <app-bundle>" >&2
  exit 2
fi

app="$1"

if [[ -f "$app/Contents/Info.plist" ]]; then
  bundle_contents="$app/Contents"
elif [[ -f "$app/Info.plist" ]]; then
  bundle_contents="$app"
else
  echo "missing app Info.plist: $app" >&2
  exit 1
fi

info_plist="$bundle_contents/Info.plist"

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
if [[ "$bundle_contents" == "$app/Contents" ]]; then
  executable="$bundle_contents/MacOS/$executable_name"
else
  executable="$bundle_contents/$executable_name"
fi

if [[ ! -x "$executable" ]]; then
  echo "missing app executable: $executable" >&2
  exit 1
fi

whisper_payloads="$(
  find "$app" \( \
    -type d -name 'whisper.framework' -o \
    -type f -name 'libwhisper*.dylib' \
  \) -print
)"
if [[ -n "$whisper_payloads" ]]; then
  echo "app still embeds a dynamic Whisper payload:" >&2
  echo "$whisper_payloads" >&2
  exit 1
fi

inspected_mach_o_count=0
while IFS= read -r -d '' candidate; do
  candidate_description="$(LC_ALL=C file -b "$candidate")"
  if [[ "$candidate_description" != *"Mach-O"* || "$candidate_description" == *"current ar archive"* ]]; then
    continue
  fi

  if ! linked_libraries="$(otool -L "$candidate")"; then
    echo "could not inspect bundled Mach-O dependencies: $candidate" >&2
    exit 1
  fi

  if grep -Eq 'whisper\.(framework|dylib)' <<< "$linked_libraries"; then
    echo "bundled Mach-O still dynamically loads Whisper: $candidate" >&2
    grep -E 'whisper\.(framework|dylib)' <<< "$linked_libraries" >&2
    exit 1
  fi

  inspected_mach_o_count=$((inspected_mach_o_count + 1))
done < <(find "$app" -type f -print0)

if (( inspected_mach_o_count == 0 )); then
  echo "app contains no inspectable Mach-O binaries: $app" >&2
  exit 1
fi

echo "Verified statically linked Whisper app: $inspected_mach_o_count Mach-O files"
