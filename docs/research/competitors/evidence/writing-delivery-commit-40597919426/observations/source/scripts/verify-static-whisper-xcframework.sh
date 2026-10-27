#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <whisper.xcframework>" >&2
  exit 2
fi

xcframework="$1"
info_plist="$xcframework/Info.plist"

if [[ ! -f "$info_plist" ]]; then
  echo "missing XCFramework Info.plist: $info_plist" >&2
  exit 1
fi

library_count=0
library_index=0

while library_identifier="$(
  /usr/libexec/PlistBuddy \
    -c "Print :AvailableLibraries:${library_index}:LibraryIdentifier" \
    "$info_plist" 2>/dev/null
)"
do
  library_path="$(
    /usr/libexec/PlistBuddy \
      -c "Print :AvailableLibraries:${library_index}:LibraryPath" \
      "$info_plist"
  )"
  framework="$xcframework/$library_identifier/$library_path"
  framework_name="$(basename "$library_path" .framework)"
  binary="$framework/$framework_name"
  module_map="$framework/Modules/module.modulemap"

  if [[ ! -f "$binary" ]]; then
    echo "missing framework binary: $binary" >&2
    exit 1
  fi

  binary_description="$(LC_ALL=C file -b "$binary")"
  if [[ "$binary_description" != *"current ar archive"* ]]; then
    echo "Whisper slice is not a static archive: $binary" >&2
    echo "$binary_description" >&2
    exit 1
  fi

  if [[ ! -f "$module_map" ]]; then
    echo "missing framework module map: $module_map" >&2
    exit 1
  fi

  for link_directive in \
    'link "c++"' \
    'link framework "Accelerate"' \
    'link framework "Metal"' \
    'link framework "Foundation"'
  do
    if ! grep -Fq "$link_directive" "$module_map"; then
      echo "missing static Whisper link directive '$link_directive': $module_map" >&2
      exit 1
    fi
  done

  library_count=$((library_count + 1))
  library_index=$((library_index + 1))
done

if (( library_count == 0 )); then
  echo "XCFramework contains no library slices: $xcframework" >&2
  exit 1
fi

echo "Verified static Whisper XCFramework: $library_count slices"
