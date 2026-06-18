#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

full_build=0
if [[ "${1:-}" == "--full-build" ]]; then
  full_build=1
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--full-build]" >&2
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

require_plist_value() {
  local description="$1"
  local key="$2"
  local expected="$3"
  local file="$4"

  section "$description"
  local actual
  if ! actual="$(plutil -extract "$key" raw -o - "$file" 2>/dev/null)"; then
    fail "$description"
    return
  fi

  if [[ "$actual" != "$expected" ]]; then
    fail "$description: expected '$expected', got '$actual'"
  fi
}

reject_file() {
  if [[ -e "$1" ]]; then
    fail "obsolete duplicate should stay deleted: $1"
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

require_pattern() {
  local description="$1"
  local pattern="$2"
  local file="$3"

  section "$description"
  if ! rg -q "$pattern" "$file"; then
    fail "$description"
  fi
}

reject_pattern() {
  local description="$1"
  local pattern="$2"
  shift 2

  section "$description"
  if rg -n "$pattern" "$@"; then
    fail "$description"
  fi
}

require_command fd
require_command rg
require_command git
require_command plutil
require_command xmllint
require_command xcrun
require_command swift

section "single-repo layout"
git_root="$(git rev-parse --show-toplevel)"
[[ "$git_root" == "$ROOT" ]] || fail "VoiceInk/ must be the git root; got $git_root"
[[ -d VoiceInk.xcodeproj ]] || fail "missing macOS VoiceInk.xcodeproj"
[[ -d iOS/VoiceInk-ios.xcodeproj ]] || fail "missing in-repo iOS project"
[[ -d VoiceInkCore ]] || fail "missing in-repo VoiceInkCore package"
[[ ! -d ../VoiceInkCore ]] || fail "parent-level ../VoiceInkCore exists; shared core must live inside VoiceInk/"
[[ ! -f ../Package.swift ]] || fail "parent-level ../Package.swift exists; shared core must live inside VoiceInk/"
[[ ! -d ../Sources/VoiceInkCore ]] || fail "parent-level ../Sources/VoiceInkCore exists; shared core must live inside VoiceInk/"
[[ ! -d ../Tests/VoiceInkCoreTests ]] || fail "parent-level ../Tests/VoiceInkCoreTests exists; shared core tests must live inside VoiceInk/"

section "iOS ported assets and resources"
require_file iOS/Shared/AppGroupCoordinator.swift
require_file iOS/Shared/VoiceInkAppDeepLink.swift
require_file iOS/Shared/VoiceInkAppGroupRecordingBridge.swift
require_file iOS/VoiceInk-ios/PrivacyInfo.xcprivacy
require_file iOS/VoiceInk-ios/Resources/ggml-silero-v5.1.2.bin
require_file iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/Contents.json
for icon in 20.png 29.png 40.png 50.png 57.png 58.png 60.png 72.png 76.png 80.png 87.png 100.png 114.png 120.png 144.png 152.png 167.png 180.png 1024.png; do
  require_file "iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/$icon"
done

section "obsolete iOS clone-side duplicates stay deleted"
for file in \
  AppGroupCoordinator.swift \
  DeepgramTranscriptionService.swift \
  DefaultModeManager.swift \
  GroqTranscriptionService.swift \
  Item.swift \
  LLMPostProcessor.swift \
  Mode.swift \
  ModeSelectionView.swift \
  ModesView.swift \
  OpenAICompatibleClient.swift \
  PromptTemplate.swift \
  Provider.swift \
  RiffWaveUtils.swift \
  TranscriptionServiceFactory.swift \
  VADModelManager.swift; do
  reject_file "iOS/VoiceInk-ios/$file"
done

reject_pattern \
  "VoiceInkCore stays platform-neutral" \
  '^import (AppKit|UIKit|SwiftUI|SwiftData|AVFoundation|CoreAudio|AudioToolbox|ApplicationServices|Carbon|IOKit|FluidAudio|KeyboardKit|LLMKit|LLMkit|WhisperKit)$' \
  VoiceInkCore/Sources/VoiceInkCore \
  VoiceInkCore/Tests/VoiceInkCoreTests

require_pattern \
  "workspace includes iOS project" \
  'location = "group:iOS/VoiceInk-ios.xcodeproj"' \
  VoiceInk.xcworkspace/contents.xcworkspacedata

require_pattern \
  "macOS project resolves in-repo VoiceInkCore" \
  'relativePath = VoiceInkCore;' \
  VoiceInk.xcodeproj/project.pbxproj

require_pattern \
  "iOS project resolves in-repo VoiceInkCore from iOS/" \
  'relativePath = ../VoiceInkCore;' \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_pattern \
  "macOS project product name stays roma just talk" \
  'PRODUCT_NAME = "roma just talk";' \
  VoiceInk.xcodeproj/project.pbxproj

require_pattern \
  "iOS project product name stays roma just talk" \
  'PRODUCT_NAME = "roma just talk";' \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_plist_value \
  "iOS display name stays roma just talk" \
  CFBundleDisplayName \
  "roma just talk" \
  iOS/VoiceInk-ios/Info.plist

require_plist_value \
  "iOS bundle name stays roma just talk" \
  CFBundleName \
  "roma just talk" \
  iOS/VoiceInk-ios/Info.plist

require_plist_value \
  "iOS record deep-link scheme stays voiceink" \
  CFBundleURLTypes.0.CFBundleURLSchemes.0 \
  voiceink \
  iOS/VoiceInk-ios/Info.plist

run_required "git diff has no whitespace errors" git diff --check

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

run_required "iOS app icon JSON lint" plutil -convert xml1 -o /tmp/VoiceInkAppIconContents.plist iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/Contents.json

run_required "workspace and scheme XML lint" xmllint --noout \
  VoiceInk.xcworkspace/contents.xcworkspacedata \
  VoiceInk.xcodeproj/xcshareddata/xcschemes/VoiceInk.xcscheme \
  VoiceInk.xcworkspace/xcshareddata/xcschemes/VoiceInk-ios.xcscheme \
  VoiceInk.xcodeproj/project.xcworkspace/contents.xcworkspacedata \
  iOS/VoiceInk-ios.xcodeproj/project.xcworkspace/contents.xcworkspacedata

run_required "VoiceInkCore sources typecheck" xcrun swiftc -emit-module \
  -module-name VoiceInkCore \
  -enable-testing \
  -emit-module-path /tmp/VoiceInkCore.swiftmodule \
  VoiceInkCore/Sources/VoiceInkCore/*.swift

run_required "VoiceInkCore tests typecheck" xcrun swiftc -typecheck -I /tmp VoiceInkCore/Tests/VoiceInkCoreTests/*.swift

run_required "VoiceInkCoreChecks" swift run --package-path VoiceInkCore VoiceInkCoreChecks

run_required "macOS Swift sources parse" fd . VoiceInk -e swift -x xcrun swiftc -parse -I /tmp '{}'
run_required "iOS Swift sources parse" fd . \
  iOS/VoiceInk-ios \
  iOS/Shared \
  iOS/VoiceInkKeyboard \
  iOS/VoiceInk-iosTests \
  iOS/VoiceInk-iosUITests \
  -e swift \
  -x xcrun swiftc -parse -I /tmp '{}'

section "toolchain report"
xcode_path="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$xcode_path" ]]; then
  warn "xcode-select -p failed"
else
  printf 'xcode-select: %s\n' "$xcode_path"
  if [[ "$xcode_path" == *CommandLineTools* ]]; then
    warn "full app builds need real Xcode, not Command Line Tools"
  fi
fi

if ! xcrun --sdk iphonesimulator --show-sdk-path >/dev/null 2>&1; then
  warn "iphonesimulator SDK unavailable; iOS target build/test remains blocked"
fi

if (( full_build == 1 )); then
  run_required "macOS app build" xcodebuild -workspace VoiceInk.xcworkspace -scheme VoiceInk -configuration Debug build
  run_required "iOS app build" xcodebuild -workspace VoiceInk.xcworkspace -scheme VoiceInk-ios -destination "generic/platform=iOS Simulator" build
else
  warn "full app builds skipped; pass --full-build when real Xcode, app dependencies, and iOS platform are installed"
fi

if (( failures > 0 )); then
  printf '\n%d required gate(s) failed; %d warning(s).\n' "$failures" "$warnings" >&2
  exit 1
fi

printf '\nAll required single-repo migration gates passed; %d warning(s).\n' "$warnings"
