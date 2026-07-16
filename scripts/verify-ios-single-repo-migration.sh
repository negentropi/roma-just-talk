#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

local_whisper_xcframework_path="${HOME}/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework"
expected_whisper_project_path='$(HOME)/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework'
expected_app_group="group.com.prakashjoshipax.VoiceInk"

if [[ $# -gt 0 ]]; then
  echo "usage: $0" >&2
  exit 2
fi

failures=0
warnings=0

section() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
  warnings=$((warnings + 1))
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing command: $1"
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    fail "missing file: $1"
  fi
}

require_file_string_count() {
  local description="$1"
  local file="$2"
  local needle="$3"
  local expected="$4"

  section "$description"
  local actual
  if ! actual="$(ruby -e 'path, needle = ARGV; print File.read(path).scan(needle).length' "$file" "$needle")"; then
    fail "$description"
    return
  fi

  if [[ "$actual" != "$expected" ]]; then
    fail "$description: expected $expected occurrence(s), got $actual"
  fi
}

require_dir() {
  if [[ ! -d "$1" ]]; then
    fail "missing directory: $1"
  fi
}

reject_path() {
  if [[ -e "$1" ]]; then
    fail "obsolete path should stay absent: $1"
  fi
}

run_required() {
  local description="$1"
  shift

  section "$description"
  if ! "$@"; then
    fail "$description"
  fi
}

require_plist_value() {
  local description="$1"
  local file="$2"
  local key_path="$3"
  local expected="$4"

  section "$description"
  local actual
  if ! actual="$(plutil -extract "$key_path" raw -o - "$file" 2>/dev/null)"; then
    fail "$description"
    return
  fi

  if [[ "$actual" != "$expected" ]]; then
    fail "$description: expected '$expected', got '$actual'"
  fi
}

require_json_array_value() {
  local description="$1"
  local file="$2"
  local key="$3"
  local index="$4"
  local expected="$5"

  section "$description"
  local actual
  if ! actual="$(
    plutil -convert json -o - "$file" |
      ruby -rjson -e '
        data = JSON.parse(STDIN.read)
        key = ARGV.fetch(0)
        index = Integer(ARGV.fetch(1))
        value = data.fetch(key).fetch(index)
        print value
      ' "$key" "$index"
  )"; then
    fail "$description"
    return
  fi

  if [[ "$actual" != "$expected" ]]; then
    fail "$description: expected '$expected', got '$actual'"
  fi
}

require_xml_xpath_value() {
  local description="$1"
  local file="$2"
  local xpath="$3"
  local expected="$4"

  section "$description"
  local actual
  if ! actual="$(xmllint --xpath "string($xpath)" "$file" 2>/dev/null)"; then
    fail "$description"
    return
  fi

  if [[ "$actual" != "$expected" ]]; then
    fail "$description: expected '$expected', got '$actual'"
  fi
}

project_string_count() {
  local project_file="$1"
  local needle="$2"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/voiceink-project.XXXXXX.xml")"
  plutil -convert xml1 -o "$tmp" "$project_file"
  xmllint --xpath "count(//string[contains(., '$needle')])" "$tmp"
  rm -f "$tmp"
}

require_project_string() {
  local description="$1"
  local project_file="$2"
  local expected="$3"

  section "$description"
  local count
  if ! count="$(project_string_count "$project_file" "$expected")"; then
    fail "$description"
    return
  fi

  if [[ "$count" == "0" ]]; then
    fail "$description: missing '$expected'"
  fi
}

reject_project_string() {
  local description="$1"
  local project_file="$2"
  local obsolete="$3"

  section "$description"
  local count
  if ! count="$(project_string_count "$project_file" "$obsolete")"; then
    fail "$description"
    return
  fi

  if [[ "$count" != "0" ]]; then
    fail "$description: found obsolete '$obsolete'"
  fi
}

section "tool availability"
require_command git
require_command plutil
require_command ruby
require_command xmllint

section "repository root"
actual_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ "$actual_root" != "$ROOT" ]]; then
  fail "expected git root '$ROOT', got '${actual_root:-<none>}'"
fi

section "required project directories"
require_dir VoiceInk.xcodeproj
require_dir VoiceInk.xcworkspace
require_dir VoiceInkCore
require_dir iOS/VoiceInk-ios.xcodeproj
require_dir iOS/VoiceInk-ios
require_dir iOS/VoiceInkKeyboard
require_dir iOS/Shared

section "required project files"
require_file VoiceInk.xcworkspace/contents.xcworkspacedata
require_file VoiceInk.xcworkspace/xcshareddata/xcschemes/VoiceInk-ios.xcscheme
require_file VoiceInk.xcodeproj/project.pbxproj
require_file VoiceInk.xcodeproj/project.xcworkspace/contents.xcworkspacedata
require_file VoiceInk.xcodeproj/xcshareddata/xcschemes/VoiceInk.xcscheme
require_file iOS/VoiceInk-ios.xcodeproj/project.pbxproj
require_file iOS/VoiceInk-ios.xcodeproj/project.xcworkspace/contents.xcworkspacedata
require_file VoiceInkCore/Package.swift
require_file Makefile
require_file LocalBuild.xcconfig
require_file .github/workflows/voiceink-ios-single-repo-migration.yml

section "required app configuration files"
require_file VoiceInk/Info.plist
require_file VoiceInk/VoiceInk.entitlements
require_file VoiceInk/VoiceInk.local.entitlements
require_file iOS/VoiceInk-ios/Info.plist
require_file iOS/VoiceInk-ios/PrivacyInfo.xcprivacy
require_file iOS/VoiceInk-ios/VoiceInk_ios.entitlements
require_file iOS/VoiceInkKeyboard/Info.plist
require_file iOS/VoiceInkKeyboard/VoiceInkKeyboard.entitlements

section "required iOS shared shell files"
require_file iOS/Shared/AppGroupCoordinator.swift
require_file iOS/Shared/VoiceInkIOSLogger.swift
require_file iOS/Shared/VoiceInkKeyboardURLOpener.swift

section "required iOS resources"
require_file iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/Contents.json
require_file iOS/VoiceInk-ios/Resources/ggml-silero-v5.1.2.bin

section "abandoned root-level shared-core shape stays absent"
reject_path ../VoiceInkCore
reject_path ../Package.swift
reject_path ../Sources/VoiceInkCore
reject_path ../Tests/VoiceInkCoreTests

run_required "project/plist/entitlements lint" plutil -lint \
  VoiceInk.xcodeproj/project.pbxproj \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj \
  VoiceInk/Info.plist \
  VoiceInk/VoiceInk.entitlements \
  VoiceInk/VoiceInk.local.entitlements \
  iOS/VoiceInk-ios/Info.plist \
  iOS/VoiceInk-ios/PrivacyInfo.xcprivacy \
  iOS/VoiceInk-ios/VoiceInk_ios.entitlements \
  iOS/VoiceInkKeyboard/Info.plist \
  iOS/VoiceInkKeyboard/VoiceInkKeyboard.entitlements

run_required "iOS app icon JSON lint" plutil -convert xml1 \
  -o /tmp/VoiceInkAppIconContents.plist \
  iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/Contents.json

run_required "workspace and scheme XML lint" xmllint --noout \
  VoiceInk.xcworkspace/contents.xcworkspacedata \
  VoiceInk.xcworkspace/xcshareddata/xcschemes/VoiceInk-ios.xcscheme \
  VoiceInk.xcodeproj/xcshareddata/xcschemes/VoiceInk.xcscheme \
  VoiceInk.xcodeproj/project.xcworkspace/contents.xcworkspacedata \
  iOS/VoiceInk-ios.xcodeproj/project.xcworkspace/contents.xcworkspacedata

require_xml_xpath_value \
  "workspace includes in-repo iOS project" \
  VoiceInk.xcworkspace/contents.xcworkspacedata \
  "/Workspace/FileRef[contains(@location, 'iOS/VoiceInk-ios.xcodeproj')]/@location" \
  "group:iOS/VoiceInk-ios.xcodeproj"

require_xml_xpath_value \
  "iOS workspace scheme includes unit-test bundle" \
  VoiceInk.xcworkspace/xcshareddata/xcschemes/VoiceInk-ios.xcscheme \
  "//BuildableReference[@BlueprintName='VoiceInk-iosTests']/@BlueprintName" \
  "VoiceInk-iosTests"

require_xml_xpath_value \
  "iOS workspace scheme includes UI-test bundle" \
  VoiceInk.xcworkspace/xcshareddata/xcschemes/VoiceInk-ios.xcscheme \
  "//BuildableReference[@BlueprintName='VoiceInk-iosUITests']/@BlueprintName" \
  "VoiceInk-iosUITests"

require_plist_value \
  "iOS app display name stays roma just talk" \
  iOS/VoiceInk-ios/Info.plist \
  CFBundleDisplayName \
  "roma just talk"

require_plist_value \
  "iOS app bundle name stays roma just talk" \
  iOS/VoiceInk-ios/Info.plist \
  CFBundleName \
  "roma just talk"

require_plist_value \
  "iOS record deep-link scheme stays voiceink" \
  iOS/VoiceInk-ios/Info.plist \
  CFBundleURLTypes.0.CFBundleURLSchemes.0 \
  voiceink

require_plist_value \
  "iOS app keeps audio background mode" \
  iOS/VoiceInk-ios/Info.plist \
  UIBackgroundModes.0 \
  audio

require_plist_value \
  "keyboard extension point stays keyboard service" \
  iOS/VoiceInkKeyboard/Info.plist \
  NSExtension.NSExtensionPointIdentifier \
  com.apple.keyboard-service

require_plist_value \
  "keyboard open access stays enabled" \
  iOS/VoiceInkKeyboard/Info.plist \
  NSExtension.NSExtensionAttributes.RequestsOpenAccess \
  true

require_json_array_value \
  "iOS app entitlement uses shared App Group" \
  iOS/VoiceInk-ios/VoiceInk_ios.entitlements \
  "com.apple.security.application-groups" \
  0 \
  "$expected_app_group"

require_json_array_value \
  "keyboard entitlement uses shared App Group" \
  iOS/VoiceInkKeyboard/VoiceInkKeyboard.entitlements \
  "com.apple.security.application-groups" \
  0 \
  "$expected_app_group"

require_file_string_count \
  "iOS CI keeps Simulator entitlements in unsigned builds and tests" \
  .github/workflows/voiceink-ios-single-repo-migration.yml \
  "ENTITLEMENTS_ALLOWED=YES" \
  2

require_project_string \
  "macOS project references VoiceInkCore" \
  VoiceInk.xcodeproj/project.pbxproj \
  VoiceInkCore

require_project_string \
  "iOS project references VoiceInkCore" \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj \
  VoiceInkCore

require_project_string \
  "iOS project references shared shell group" \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj \
  Shared

require_project_string \
  "macOS project product name stays roma just talk" \
  VoiceInk.xcodeproj/project.pbxproj \
  "roma just talk"

require_project_string \
  "iOS project product name stays roma just talk" \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj \
  "roma just talk"

reject_project_string \
  "macOS project avoids sibling VoiceInk-iOS references" \
  VoiceInk.xcodeproj/project.pbxproj \
  VoiceInk-iOS

reject_project_string \
  "iOS project avoids sibling VoiceInk-iOS references" \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj \
  VoiceInk-iOS

require_project_string \
  "macOS project uses canonical local Whisper framework path" \
  VoiceInk.xcodeproj/project.pbxproj \
  "$expected_whisper_project_path"

require_project_string \
  "iOS project uses canonical local Whisper framework path" \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj \
  "$expected_whisper_project_path"

for obsolete_framework_path in \
  "../Downloads/build-apple/whisper.xcframework" \
  "../whisper.cpp/build-apple/whisper.xcframework" \
  "../build-apple/whisper.xcframework"
do
  reject_project_string \
    "macOS project avoids obsolete framework path $obsolete_framework_path" \
    VoiceInk.xcodeproj/project.pbxproj \
    "$obsolete_framework_path"
  reject_project_string \
    "iOS project avoids obsolete framework path $obsolete_framework_path" \
    iOS/VoiceInk-ios.xcodeproj/project.pbxproj \
    "$obsolete_framework_path"
done

section "local framework readiness"
if [[ ! -d "$local_whisper_xcframework_path" ]]; then
  warn "local Whisper xcframework missing at $local_whisper_xcframework_path"
fi

if (( failures > 0 )); then
  printf '\n%d required config gate(s) failed; %d warning(s).\n' "$failures" "$warnings" >&2
  exit 1
fi

printf '\nAll required single-repo config gates passed; %d warning(s).\n' "$warnings"
