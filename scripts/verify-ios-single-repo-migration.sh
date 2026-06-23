#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

local_whisper_xcframework_path="${HOME}/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework"

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

relative_swift_file_list() {
  local base="$1"
  fd -e swift -t f . "$base" | while IFS= read -r file; do
    printf '%s\n' "${file#"$base"/}"
  done | sort
}

require_no_sibling_swift_extras() {
  local description="$1"
  local sibling_dir="$2"
  local in_repo_dir="$3"
  shift 3

  section "$description"
  if [[ ! -d "$sibling_dir" ]]; then
    printf 'No sibling %s checkout path; skipping optional clone-extra audit.\n' "$sibling_dir"
    return
  fi

  local sibling_files
  local in_repo_files
  local extras
  sibling_files="$(mktemp "${TMPDIR:-/tmp}/voiceink-sibling-swift.XXXXXX")"
  in_repo_files="$(mktemp "${TMPDIR:-/tmp}/voiceink-in-repo-swift.XXXXXX")"
  extras="$(mktemp "${TMPDIR:-/tmp}/voiceink-sibling-extras.XXXXXX")"

  relative_swift_file_list "$sibling_dir" >"$sibling_files"
  relative_swift_file_list "$in_repo_dir" >"$in_repo_files"
  comm -23 "$sibling_files" "$in_repo_files" >"$extras"

  local allowed_extra
  local filtered_extras
  for allowed_extra in "$@"; do
    filtered_extras="$(mktemp "${TMPDIR:-/tmp}/voiceink-sibling-extras-filtered.XXXXXX")"
    rg -F -x -v "$allowed_extra" "$extras" >"$filtered_extras" || true
    mv "$filtered_extras" "$extras"
  done

  if [[ -s "$extras" ]]; then
    printf 'Sibling-only Swift files:\n' >&2
    cat "$extras" >&2
    rm -f "$sibling_files" "$in_repo_files" "$extras"
    fail "$description"
    return
  fi

  rm -f "$sibling_files" "$in_repo_files" "$extras"
}

run_required() {
  local description="$1"
  shift

  section "$description"
  if ! "$@"; then
    fail "$description"
  fi
}

require_full_build_prerequisites() {
  local rc=0
  local xcode_path
  local xcodebuild_output

  if ! xcode_path="$(xcode-select -p 2>/dev/null)"; then
    printf 'xcode-select -p failed; select a real Xcode before running --full-build.\n' >&2
    rc=1
  elif [[ "$xcode_path" == *CommandLineTools* ]]; then
    printf 'xcode-select points to Command Line Tools (%s); select a real Xcode before running --full-build.\n' "$xcode_path" >&2
    rc=1
  fi

  if ! xcodebuild_output="$(xcodebuild -version 2>&1)"; then
    printf 'xcodebuild is unavailable: %s\n' "$xcodebuild_output" >&2
    rc=1
  fi

  if ! xcrun --sdk iphonesimulator --show-sdk-path >/dev/null 2>&1; then
    printf 'iphonesimulator SDK unavailable; install the iOS simulator platform before running --full-build.\n' >&2
    rc=1
  fi

  if [[ ! -d "$local_whisper_xcframework_path" ]]; then
    printf 'missing local Whisper framework: %s\n' "$local_whisper_xcframework_path" >&2
    rc=1
  fi

  return "$rc"
}

swiftpm_sandbox_blocked() {
  rg -q 'sandbox-exec: sandbox_apply: Operation not permitted' "$1"
}

build_voiceink_core_library() {
  local build_dir="$1"

  xcrun swiftc -emit-module -emit-library \
    -enable-testing \
    -module-name VoiceInkCore \
    -emit-module-path "$build_dir/VoiceInkCore.swiftmodule" \
    -o "$build_dir/libVoiceInkCore.dylib" \
    VoiceInkCore/Sources/VoiceInkCore/*.swift
}

run_direct_voiceink_core_checks() {
  local build_dir
  build_dir="$(mktemp -d "${TMPDIR:-/tmp}/voiceink-core-checks.XXXXXX")"
  local rc=0

  build_voiceink_core_library "$build_dir" || rc=$?
  if (( rc == 0 )); then
    xcrun swiftc \
      -I "$build_dir" \
      -L "$build_dir" \
      -lVoiceInkCore \
      -Xlinker -rpath \
      -Xlinker "$build_dir" \
      -o "$build_dir/VoiceInkCoreChecks" \
      VoiceInkCore/Tests/VoiceInkCoreTests/*.swift || rc=$?
  fi
  if (( rc == 0 )); then
    "$build_dir/VoiceInkCoreChecks" || rc=$?
  fi

  rm -rf "$build_dir"
  return "$rc"
}

run_voiceink_core_checks() {
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/voiceink-core-checks-swiftpm.XXXXXX")"

  if swift run --package-path VoiceInkCore VoiceInkCoreChecks >"$output_file" 2>&1; then
    cat "$output_file"
    rm -f "$output_file"
    return 0
  fi

  local swiftpm_rc=$?
  cat "$output_file" >&2
  if swiftpm_sandbox_blocked "$output_file"; then
    rm -f "$output_file"
    warn "SwiftPM VoiceInkCoreChecks blocked by sandbox-exec; using direct swiftc fallback"
    run_direct_voiceink_core_checks
    return $?
  fi

  rm -f "$output_file"
  return "$swiftpm_rc"
}

run_direct_voiceink_audio_proof_help() {
  local build_dir
  build_dir="$(mktemp -d "${TMPDIR:-/tmp}/voiceink-audio-proof.XXXXXX")"
  local rc=0

  build_voiceink_core_library "$build_dir" || rc=$?
  if (( rc == 0 )); then
    xcrun swiftc -parse-as-library \
      -I "$build_dir" \
      -L "$build_dir" \
      -lVoiceInkCore \
      -Xlinker -rpath \
      -Xlinker "$build_dir" \
      -o "$build_dir/VoiceInkAudioProof" \
      VoiceInkCore/Sources/VoiceInkAudioProof/main.swift || rc=$?
  fi
  if (( rc == 0 )); then
    "$build_dir/VoiceInkAudioProof" --help || rc=$?
  fi

  rm -rf "$build_dir"
  return "$rc"
}

run_voiceink_audio_proof_help() {
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/voiceink-audio-proof-swiftpm.XXXXXX")"

  if swift run --package-path VoiceInkCore VoiceInkAudioProof --help >"$output_file" 2>&1; then
    cat "$output_file"
    rm -f "$output_file"
    return 0
  fi

  local swiftpm_rc=$?
  cat "$output_file" >&2
  if swiftpm_sandbox_blocked "$output_file"; then
    rm -f "$output_file"
    warn "SwiftPM VoiceInkAudioProof blocked by sandbox-exec; using direct swiftc fallback"
    run_direct_voiceink_audio_proof_help
    return $?
  fi

  rm -f "$output_file"
  return "$swiftpm_rc"
}

require_pattern() {
  local description="$1"
  local pattern="$2"
  shift 2

  section "$description"
  local file
  for file in "$@"; do
    if ! rg -q "$pattern" "$file"; then
      fail "$description: missing pattern in $file"
    fi
  done
}

require_patterns() {
  local description="$1"
  local file="$2"
  shift 2

  section "$description"
  local pattern
  for pattern in "$@"; do
    if ! rg -q "$pattern" "$file"; then
      fail "$description: missing pattern '$pattern' in $file"
    fi
  done
}

require_context_pattern_count_at_least() {
  local description="$1"
  local anchor="$2"
  local pattern="$3"
  local minimum_count="$4"
  local file="$5"

  section "$description"
  local count
  count="$(rg -A 32 "$anchor" "$file" | rg -c "$pattern" || true)"
  if (( count < minimum_count )); then
    fail "$description: expected at least $minimum_count matching build settings, got $count"
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

reject_fixed_string() {
  local description="$1"
  local needle="$2"
  shift 2

  section "$description"
  if rg -n -F "$needle" "$@"; then
    fail "$description"
  fi
}

reject_ios_storage_duplicate_pattern() {
  local description="$1"
  local pattern="$2"

  section "$description"
  local files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(fd -e swift -t f . iOS/VoiceInk-ios iOS/Shared iOS/VoiceInkKeyboard)

  if ((${#files[@]} == 0)); then
    fail "$description: no iOS Swift files found"
    return
  fi

  if rg -n "$pattern" "${files[@]}"; then
    fail "$description"
  fi
}

reject_macos_storage_duplicate_pattern() {
  local description="$1"
  local pattern="$2"

  section "$description"
  local files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(fd -e swift -t f . VoiceInk)

  if ((${#files[@]} == 0)); then
    fail "$description: no macOS Swift files found"
    return
  fi

  if rg -n "$pattern" "${files[@]}"; then
    fail "$description"
  fi
}

reject_context_pattern() {
  local description="$1"
  local anchor="$2"
  local pattern="$3"
  local file="$4"

  section "$description"
  local matches
  matches="$(rg -A 80 "$anchor" "$file" | rg -n "$pattern" || true)"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
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

obsolete_ios_clone_files=(
  AppGroupCoordinator.swift
  ContentView.swift
  DeepgramTranscriptionService.swift
  DefaultModeManager.swift
  GroqTranscriptionService.swift
  Item.swift
  KeychainService.swift
  LLMPostProcessor.swift
  Mode.swift
  ModeSelectionView.swift
  ModesView.swift
  OpenAICompatibleClient.swift
  PromptTemplate.swift
  Provider.swift
  RiffWaveUtils.swift
  TranscriptionServiceFactory.swift
  VADModelManager.swift
  VoiceInk-ios/Transcription.swift
)

in_repo_only_ios_app_files=(
  ProviderAPIKeyTone+iOS.swift
  TranscriptStatusTone+iOS.swift
  Transcription.swift
)

xcode_metadata_files=(
  VoiceInk.xcodeproj/project.pbxproj
  VoiceInk.xcodeproj/project.xcworkspace/contents.xcworkspacedata
  VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings
  VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
  VoiceInk.xcodeproj/xcshareddata/xcschemes/VoiceInk.xcscheme
  VoiceInk.xcworkspace/contents.xcworkspacedata
  VoiceInk.xcworkspace/xcshareddata/swiftpm/Package.resolved
  VoiceInk.xcworkspace/xcshareddata/xcschemes/VoiceInk-ios.xcscheme
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj
  iOS/VoiceInk-ios.xcodeproj/project.xcworkspace/contents.xcworkspacedata
  iOS/VoiceInk-ios.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
)

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

reject_fixed_string \
  "Xcode metadata avoids sibling VoiceInk-iOS clone references" \
  "VoiceInk-iOS" \
  "${xcode_metadata_files[@]}"

section "iOS storage directories live in shared core"
reject_file iOS/VoiceInk-ios/VoiceInkIOSStorageDirectories.swift
require_patterns \
  "shared iOS storage directories live in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/PlatformStorageDirectories.swift \
  'public enum VoiceInkIOSStorageDirectories' \
  'VoiceInkStoredAudioFile\.recordingsDirectory\(in: documentsDirectory\)' \
  'VoiceInkStoredAudioFile\.createRecordingsDirectory' \
  'VoiceInkWhisperModelFiles\.modelsDirectory\(in: documentsDirectory\)' \
  'VoiceInkWhisperModelFiles\.createModelsDirectory' \
  'FileManager\.default\.urls\(for: \.(documentDirectory|cachesDirectory),'

require_pattern \
  "core checks execute iOS storage directory tests" \
  'testIOSStorageDirectoriesUseDocumentsDirectoryForRecordingsAndModels|testIOSStorageDirectoriesPrepareRecordingAndModelDirectories' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_ios_storage_duplicate_pattern \
  "iOS shell avoids duplicate Documents/Caches directory roots" \
  'FileManager\.default\.urls\(for: \.(documentDirectory|cachesDirectory),'

reject_ios_storage_duplicate_pattern \
  "iOS shell avoids duplicate recordings/model directory literals" \
  'appendingPathComponent\((VoiceInkStoredAudioFile\.recordingsDirectoryName|VoiceInkWhisperModelFiles\.modelsDirectoryName|"Recordings"|"WhisperModels")'

section "macOS storage directories live in shared core"
reject_file VoiceInk/VoiceInkMacOSStorageDirectories.swift
require_patterns \
  "shared macOS storage directories live in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/PlatformStorageDirectories.swift \
  'public enum VoiceInkMacOSStorageDirectories' \
  'VoiceInkAppIdentity\.macOSApplicationSupportDirectory\(in: applicationSupportBaseDirectory\)' \
  'VoiceInkStoredAudioFile\.recordingsDirectory\(in: appSupportDirectory\)' \
  'VoiceInkWhisperModelFiles\.modelsDirectory\(in: appSupportDirectory\)' \
  'VoiceInkCustomSoundPreference\.customSoundsRelativeDirectory'

require_pattern \
  "core checks execute macOS storage directory tests" \
  'testMacOSStorageDirectoriesUseApplicationSupportBaseForAppRecordingsModelsAndCustomSounds' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS app startup uses shared storage directories for local models" \
  'VoiceInkMacOSStorageDirectories\.modelsDirectory' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS persistent store uses shared storage directories app support" \
  'VoiceInkMacOSStorageDirectories\.appSupportDirectory' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS recording paths use shared storage directories recordings directory" \
  'VoiceInkMacOSStorageDirectories\.recordingsDirectory' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift \
  VoiceInk/Services/TranscriptionAutoCleanupService.swift

require_pattern \
  "macOS audio import flows use shared storage directories app support" \
  'VoiceInkMacOSStorageDirectories\.appSupportDirectory' \
  VoiceInk/Services/AudioFileTranscriptionService.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS custom sounds use shared storage directories" \
  'VoiceInkMacOSStorageDirectories\.customSoundsDirectory' \
  VoiceInk/CustomSoundManager.swift

reject_macos_storage_duplicate_pattern \
  "macOS shell avoids duplicate Application Support roots" \
  'FileManager\.default\.urls\(for: \.applicationSupportDirectory|VoiceInkAppIdentity\.macOSApplicationSupportDirectory\('

reject_macos_storage_duplicate_pattern \
  "macOS shell avoids duplicate app-local storage directory derivation" \
  'VoiceInkStoredAudioFile\.recordingsDirectory\(in:|VoiceInkWhisperModelFiles\.modelsDirectory\(in:|appendingPathComponent\(VoiceInkCustomSoundPreference\.customSoundsRelativeDirectory'

require_pattern \
  "macOS app uses shared local Whisper framework path" \
  '\$\(HOME\)/VoiceInk-Dependencies/whisper\.cpp/build-apple/whisper\.xcframework' \
  VoiceInk.xcodeproj/project.pbxproj

require_pattern \
  "iOS app uses shared local Whisper framework path" \
  '\$\(HOME\)/VoiceInk-Dependencies/whisper\.cpp/build-apple/whisper\.xcframework' \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

reject_pattern \
  "app projects avoid clone-side local Whisper framework paths" \
  '\.\./(Downloads/)?build-apple/whisper\.xcframework|\.\./whisper\.cpp/build-apple/whisper\.xcframework' \
  VoiceInk.xcodeproj/project.pbxproj \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

section "iOS ported assets and resources"
require_file iOS/Shared/AppGroupCoordinator.swift
require_file iOS/Shared/VoiceInkAppGroupRecordingBridge.swift
require_file iOS/Shared/VoiceInkIOSLogger.swift
require_file iOS/Shared/VoiceInkKeyboardURLOpener.swift
require_file iOS/VoiceInk-ios/Transcription.swift
require_file docs/ios-privacy-policy.md
require_file iOS/VoiceInk-ios/PrivacyInfo.xcprivacy
require_file iOS/VoiceInk-ios/Resources/ggml-silero-v5.1.2.bin
require_file iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/Contents.json
for icon in 20.png 29.png 40.png 50.png 57.png 58.png 60.png 72.png 76.png 80.png 87.png 100.png 114.png 120.png 144.png 152.png 167.png 180.png 1024.png; do
  require_file "iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/$icon"
done
reject_file iOS/.github/workflows/deploy.yml
reject_file iOS/.nojekyll
reject_file iOS/tasks.md
reject_file iOS/index.html
reject_file iOS/PRIVACY.html
reject_file iOS/PRIVACY.md
reject_file iOS/app-icon.png
reject_file iOS/Shared/VoiceInkAppDeepLink.swift
reject_file iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift
reject_file iOS/Shared/VoiceInkKeyboardRecordingTiming.swift
reject_file iOS/VoiceInk-ios/VoiceInk-ios
reject_file iOS/VoiceInk-ios/KeychainService.swift

section "obsolete iOS clone-side duplicates stay deleted"
for file in "${obsolete_ios_clone_files[@]}"; do
  reject_file "iOS/VoiceInk-ios/$file"
done

section "iOS project avoids obsolete clone-side source references"
for file in "${obsolete_ios_clone_files[@]}" VoiceInk_iosUITestsLaunchTests.swift; do
  reject_fixed_string \
    "iOS project avoids obsolete clone-side source reference $file" \
    "$file" \
    iOS/VoiceInk-ios.xcodeproj/project.pbxproj
done

section "sibling iOS clone extras are documented obsolete files"
if [[ -d ../VoiceInk-iOS/VoiceInk-ios ]]; then
  sibling_ios_files="$(mktemp "${TMPDIR:-/tmp}/voiceink-sibling-ios.XXXXXX")"
  in_repo_ios_files="$(mktemp "${TMPDIR:-/tmp}/voiceink-in-repo-ios.XXXXXX")"
  actual_sibling_extras="$(mktemp "${TMPDIR:-/tmp}/voiceink-actual-sibling-extras.XXXXXX")"
  expected_sibling_extras="$(mktemp "${TMPDIR:-/tmp}/voiceink-expected-sibling-extras.XXXXXX")"
  actual_in_repo_extras="$(mktemp "${TMPDIR:-/tmp}/voiceink-actual-in-repo-extras.XXXXXX")"
  expected_in_repo_extras="$(mktemp "${TMPDIR:-/tmp}/voiceink-expected-in-repo-extras.XXXXXX")"

  relative_swift_file_list ../VoiceInk-iOS/VoiceInk-ios >"$sibling_ios_files"
  relative_swift_file_list iOS/VoiceInk-ios >"$in_repo_ios_files"
  comm -23 "$sibling_ios_files" "$in_repo_ios_files" >"$actual_sibling_extras"
  printf '%s\n' "${obsolete_ios_clone_files[@]}" | sort >"$expected_sibling_extras"
  comm -13 "$sibling_ios_files" "$in_repo_ios_files" >"$actual_in_repo_extras"
  printf '%s\n' "${in_repo_only_ios_app_files[@]}" | sort >"$expected_in_repo_extras"

  if ! cmp -s "$actual_sibling_extras" "$expected_sibling_extras"; then
    printf 'Expected sibling-only Swift files:\n' >&2
    cat "$expected_sibling_extras" >&2
    printf 'Actual sibling-only Swift files:\n' >&2
    cat "$actual_sibling_extras" >&2
    rm -f "$sibling_ios_files" "$in_repo_ios_files" "$actual_sibling_extras" "$expected_sibling_extras" "$actual_in_repo_extras" "$expected_in_repo_extras"
    fail "sibling iOS clone has undocumented Swift extras"
  fi

  if ! cmp -s "$actual_in_repo_extras" "$expected_in_repo_extras"; then
    printf 'Expected in-repo-only iOS app Swift files:\n' >&2
    cat "$expected_in_repo_extras" >&2
    printf 'Actual in-repo-only iOS app Swift files:\n' >&2
    cat "$actual_in_repo_extras" >&2
    rm -f "$sibling_ios_files" "$in_repo_ios_files" "$actual_sibling_extras" "$expected_sibling_extras" "$actual_in_repo_extras" "$expected_in_repo_extras"
    fail "in-repo iOS app has undocumented Swift-only files"
  fi

  rm -f "$sibling_ios_files" "$in_repo_ios_files" "$actual_sibling_extras" "$expected_sibling_extras" "$actual_in_repo_extras" "$expected_in_repo_extras"
else
  printf 'No sibling ../VoiceInk-iOS checkout; skipping optional clone-extra audit.\n'
fi

require_no_sibling_swift_extras \
  "sibling iOS keyboard clone has no undocumented Swift extras" \
  ../VoiceInk-iOS/VoiceInkKeyboard \
  iOS/VoiceInkKeyboard

require_no_sibling_swift_extras \
  "sibling iOS unit-test clone has no undocumented Swift extras" \
  ../VoiceInk-iOS/VoiceInk-iosTests \
  iOS/VoiceInk-iosTests

require_no_sibling_swift_extras \
  "sibling iOS UI-test clone has no undocumented Swift extras" \
  ../VoiceInk-iOS/VoiceInk-iosUITests \
  iOS/VoiceInk-iosUITests \
  VoiceInk_iosUITestsLaunchTests.swift

require_pattern \
  "iOS UI tests keep primary launch smoke assertion" \
  'testLaunchShowsPrimaryIOSExperience|Expected either the notes list or first-run onboarding to be visible after launch' \
  iOS/VoiceInk-iosUITests/VoiceInk_iosUITests.swift

reject_file iOS/VoiceInk-iosUITests/VoiceInk_iosUITestsLaunchTests.swift

reject_pattern \
  "VoiceInkCore stays platform-neutral" \
  '^import (AppKit|UIKit|SwiftUI|SwiftData|AVFoundation|CoreAudio|AudioToolbox|ApplicationServices|Carbon|IOKit|FluidAudio|KeyboardKit|LLMKit|LLMkit|WhisperKit|whisper)$' \
  VoiceInkCore/Sources/VoiceInkCore \
  VoiceInkCore/Tests/VoiceInkCoreTests

reject_pattern \
  "iOS App Group keyboard bridge implementation stays out of VoiceInkCore" \
  '\b(VoiceInkAppGroupRecordingBridge|AppGroupCoordinator|CFNotificationCenter|DarwinNotify)\b' \
  VoiceInkCore/Sources/VoiceInkCore \
  VoiceInkCore/Tests/VoiceInkCoreTests

reject_pattern \
  "API-key reference resolution stays in VoiceInkCore" \
  'resolveAPIKeyReference' \
  VoiceInk \
  iOS \
  VoiceInkCore/Sources/VoiceInkCore \
  VoiceInkCore/Tests/VoiceInkCoreTests

require_pattern \
  "shared custom model API-key account identifier lives with provider catalog" \
  'customModelAccountIdentifier\(forModelId:|customModel_.*_APIKey' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

section "obsolete standalone provider API-key account module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyAccounts.swift

require_pattern \
  "shared provider API-key accounts live with provider access requirements" \
  'VoiceInkProviderAPIKeyAccount|VoiceInkProviderAccessRequirement|fallbackEnvironmentKey\(forProviderName:' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "macOS API-key manager uses shared custom model account identifier" \
  'VoiceInkProviderAPIKeyAccount\.customModelAccountIdentifier\(forModelId:' \
  VoiceInk/Services/APIKeyManager.swift

require_pattern \
  "macOS API-key manager uses shared provider account identifier" \
  'VoiceInkProviderAPIKeyAccount\.accountIdentifier\(forProviderName:' \
  VoiceInk/Services/APIKeyManager.swift

reject_pattern \
  "macOS API-key manager avoids shallow account identifier wrappers" \
  'private func +(keychainIdentifier|customModelKeyIdentifier)\(' \
  VoiceInk/Services/APIKeyManager.swift

reject_pattern \
  "macOS API-key manager avoids shell-owned custom model account strings" \
  'customModel_.*_APIKey' \
  VoiceInk/Services/APIKeyManager.swift

reject_pattern \
  "removed shared-type shell aliases stay deleted" \
  'typealias +(CustomPrompt|PromptIcon|RollingBufferPreloadMode|RollingBufferPreloadConfiguration|RollingBufferPowerState|RollingBufferPreloadPolicy|RollingBufferPreloadSettings|AIProvider|WhisperModelFile|RecordingState|RecorderAction|ShortcutPressContext|PowerModeValidationError|StreamingTranscriptionEvent|StreamingTranscriptionError)\b|PerformanceAnalyzer\.(AnalysisResult|ModelStat)' \
  VoiceInk \
  iOS

reject_pattern \
  "removed mode custom-prompt draft shim stays deleted" \
  'public var (customPromptText|selectedTemplateType)' \
  VoiceInkCore/Sources/VoiceInkCore/Mode.swift

reject_pattern \
  "removed macOS streaming migration wrapper stays deleted" \
  'enum StreamingKeysMigration' \
  VoiceInk \
  iOS

reject_pattern \
  "removed macOS language support wrapper stays deleted" \
  '\benum +TranscriptionLanguageSupport\b' \
  VoiceInk \
  iOS

reject_pattern \
  "obsolete iOS clone runtime shims stay deleted" \
  '\b(TranscriptionServiceFactory|LLMPostProcessor|currentRecordingNote|effectiveTranscriptionProvider|effectivePostProcessingProvider|effectiveCustomPrompt|effectiveIsPostProcessingEnabled)\b|\bvar +effective(TranscriptionModel|PostProcessingModel)\b|\bsettings\.effective(TranscriptionModel|PostProcessingModel)\b|\bawait +settings\.effective(TranscriptionModel|PostProcessingModel)\b|\benum +RecordingState\b|URL\(string: +"voiceink://record"\)|Open VoiceInk|static +func +recordingsDirectory\b' \
  iOS/VoiceInk-ios \
  iOS/VoiceInkKeyboard

require_pattern \
  "shared transcript export owns localized date style" \
  'dateStyle = \.medium' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptExport.swift

require_pattern \
  "shared transcript export owns localized time style" \
  'timeStyle = \.short' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptExport.swift

require_patterns \
  "shared transcript export owns macOS file extensions" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptExport.swift \
  'plainTextFileExtension = "txt"' \
  'markdownFileExtension = "md"'

reject_file VoiceInkCore/Sources/VoiceInkCore/TranscriptFileExport.swift
reject_file VoiceInkCore/Sources/VoiceInkCore/TranscriptionCSVExport.swift

require_pattern \
  "shared language display fallback lives in VoiceInkCore" \
  'displayName\(for languageCode: String|fallback: String = "Unknown"' \
  VoiceInkCore/Sources/VoiceInkCore/LanguageCatalog.swift

require_pattern \
  "shared transcription language presentation lives in VoiceInkCore" \
  'VoiceInkTranscriptionLanguagePresentation' \
  VoiceInkCore/Sources/VoiceInkCore/LanguageCatalog.swift

require_pattern \
  "shared transcription language presentation uses shared display fallback" \
  'VoiceInkLanguageCatalog\.displayName' \
  VoiceInkCore/Sources/VoiceInkCore/LanguageCatalog.swift

require_pattern \
  "shared transcription language selection facts live in VoiceInkCore" \
  'VoiceInkTranscriptionLanguageSelectionFacts|VoiceInkTranscriptionLanguageSelectionControl|compatibleLanguage' \
  VoiceInkCore/Sources/VoiceInkCore/LanguageCatalog.swift

require_pattern \
  "shared transcription language repair plan lives in VoiceInkCore" \
  'VoiceInkTranscriptionLanguageRepairPlan|repairPlan\(for selectedLanguage' \
  VoiceInkCore/Sources/VoiceInkCore/LanguageCatalog.swift

require_pattern \
  "shared Native Apple language asset presentation lives in VoiceInkCore" \
  'VoiceInkNativeAppleLanguageAsset(State|Display|Presentation)|presentation\(for state: VoiceInkNativeAppleLanguageAssetState\)' \
  VoiceInkCore/Sources/VoiceInkCore/LanguageCatalog.swift

require_pattern \
  "core checks execute Native Apple language asset presentation tests" \
  'LanguageCatalogTests\.testNativeAppleLanguageAssetPresentationPreservesProgressAndIconStates|LanguageCatalogTests\.testNativeAppleLanguageAssetPresentationPreservesActionStates' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS language picker uses shared language display fallback" \
  'VoiceInkTranscriptionLanguagePresentation\.menuLabel' \
  "VoiceInk/Views/AI Models/LanguageSelectionView.swift"

require_pattern \
  "macOS language picker uses shared language presentation" \
  'VoiceInkTranscriptionLanguagePresentation' \
  "VoiceInk/Views/AI Models/LanguageSelectionView.swift"

require_pattern \
  "macOS language picker uses shared selection facts" \
  'languageSelectionFacts|facts\.control|showsNativeAppleAssetControl' \
  "VoiceInk/Views/AI Models/LanguageSelectionView.swift"

require_pattern \
  "macOS Native Apple asset control uses shared presentation" \
  'VoiceInkNativeAppleLanguageAsset(Presentation|State)|presentation\.(display|helpText|accessibilityLabel)' \
  "VoiceInk/Views/AI Models/NativeAppleLanguageAssetControl.swift"

require_pattern \
  "macOS TranscriptionModel adapts shared language selection facts" \
  'transcriptionLanguageSelectionFacts|VoiceInkTranscriptionLanguageSelectionFacts' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "iOS language settings uses shared language presentation" \
  'VoiceInkTranscriptionLanguagePresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS language settings avoids shallow sorted-language wrapper" \
  'private var +sortedTranscriptionLanguages\b' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS language settings avoids shallow selected-language binding wrapper" \
  'private var +selectedLanguageBinding\b' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "macOS language picker avoids shell-only language display fallback" \
  'private func +currentLanguageDisplayName|\?\? "Unknown"' \
  "VoiceInk/Views/AI Models/LanguageSelectionView.swift"

reject_pattern \
  "macOS language picker avoids shallow selected-language binding wrapper" \
  'private var +selectedLanguageBinding\b' \
  "VoiceInk/Views/AI Models/LanguageSelectionView.swift"

reject_pattern \
  "macOS language picker avoids shell-only language presentation copy" \
  '"Transcription Language"|"Select Language"|"Language: Autodetected"|"The transcription language is automatically detected by the model\."|"This model supports multiple languages\. Select a specific language or auto-detect\(if available\)"|"Language: English"|"This is an English-optimized model and only supports English transcription\."|"No model selected"|"Language: English \(only\)"' \
  "VoiceInk/Views/AI Models/LanguageSelectionView.swift"

reject_pattern \
  "macOS language picker avoids duplicate provider selection policy" \
  'languageSelectionDisabled|isMultilingualModel\(|isNativeAppleModelSelected|availableLanguagesForCurrentModel|provider == \.(gemini|nativeApple)' \
  "VoiceInk/Views/AI Models/LanguageSelectionView.swift"

reject_pattern \
  "macOS Native Apple asset control avoids shell-owned presentation copy and icons" \
  '"(Checking Apple Speech language download status\.|Download this Apple Speech language before transcribing\.|Download Apple Speech language|Downloading Apple Speech language\.|This language is not supported by Apple Speech\.|Apple Speech asset management is not available on this system\.|Retry downloading this Apple Speech language\.|Retry Apple Speech language download|arrow\.down\.circle\.fill|arrow\.clockwise\.circle\.fill|exclamationmark\.triangle)"' \
  "VoiceInk/Views/AI Models/NativeAppleLanguageAssetControl.swift"

reject_pattern \
  "iOS language settings avoids shell-only language presentation copy" \
  '"Transcription Language"|"Language"' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS save button uses shared timestamped markdown export" \
  'VoiceInkTranscriptFileExport\.markdownContent\(for: textToSave\)' \
  VoiceInk/Views/Common/SaveIconButton.swift

require_patterns \
  "macOS copy button uses shared transcript action presentation" \
  VoiceInk/Views/Common/CopyIconButton.swift \
  'VoiceInkTranscriptPresentation\.actionSucceededSystemImageName' \
  'VoiceInkTranscriptPresentation\.copyTranscriptSystemImageName' \
  'VoiceInkTranscriptPresentation\.copyToClipboardHelp'

require_patterns \
  "macOS save button uses shared transcript action presentation and export extensions" \
  VoiceInk/Views/Common/SaveIconButton.swift \
  'VoiceInkTranscriptPresentation\.actionSucceededSystemImageName' \
  'VoiceInkTranscriptPresentation\.saveTranscriptSystemImageName' \
  'VoiceInkTranscriptPresentation\.saveTranscriptAsPlainTextButtonTitle' \
  'VoiceInkTranscriptPresentation\.saveTranscriptAsMarkdownButtonTitle' \
  'VoiceInkTranscriptPresentation\.saveTranscriptHelp' \
  'VoiceInkTranscriptPresentation\.saveTranscriptPanelTitle' \
  'VoiceInkTranscriptPresentation\.saveTranscriptFailureConsolePrefix' \
  'VoiceInkTranscriptFileExport\.plainTextFileExtension' \
  'VoiceInkTranscriptFileExport\.markdownFileExtension'

reject_pattern \
  "macOS save button avoids shallow markdown export wrapper" \
  'private +func +markdownContent\(' \
  VoiceInk/Views/Common/SaveIconButton.swift

reject_pattern \
  "macOS save button avoids shell-owned transcript export date formatting" \
  'DateFormatter|localizedString' \
  VoiceInk/Views/Common/SaveIconButton.swift

reject_pattern \
  "macOS copy button avoids shell-owned transcript action presentation" \
  '"(checkmark|doc\.on\.doc|Copy to clipboard)"' \
  VoiceInk/Views/Common/CopyIconButton.swift

reject_pattern \
  "macOS save button avoids shell-owned transcript action presentation and export extensions" \
  '"(Save as TXT|Save as MD|Save to file|Save Transcription|Failed to save file:|checkmark|square\.and\.arrow\.down|txt|md)"' \
  VoiceInk/Views/Common/SaveIconButton.swift

require_pattern \
  "migration docs track shared transcript action controls and export extensions" \
  'macOS common transcript copy/save button copy/icons.*VoiceInkTranscriptPresentation.*/`VoiceInkTranscriptFileExport' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared recording state exposes active-recording predicate" \
  'var +isActivelyRecording: +Bool' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording state owns recorder capture predicate" \
  'isRecorderCaptureInProgress' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording state owns post-recording processing predicate" \
  'isPostRecordingProcessing' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording state owns recorder dismiss policy" \
  'isRecorderDismissCancelable' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording state owns active-pipeline finish policy" \
  'shouldReturnToIdleWhenActivePipelineFinishes' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording state owns recorder processing presentation" \
  'VoiceInkRecorderProcessingPresentation|recorderProcessingPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared macOS recording cancellation plan lives in VoiceInkCore" \
  'VoiceInkMacOSRecordingCancellationPolicy|VoiceInkMacOSRecordingCancellationPlan|shouldFinishActiveRecorderCancellation|shouldFinishRecorderSessionImmediately' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recorder processing and cancellation checks run in VoiceInkCore" \
  'testRecorderCaptureStatePolicyPreservesMacOSCancellationPath|testPostRecordingProcessingStatePolicyPreservesMacOSProcessingStates|testRecorderDismissCancelableStatePolicyPreservesMacOSWindowBehavior|testPipelineFinishIdleRepairStatePolicyPreservesMacOSEngineBehavior|testRecorderProcessingPresentationPreservesMacOSCopyAndTiming|testMacOSRecordingCancellationPlanFinishesActiveCaptureImmediately|testMacOSRecordingCancellationPlanCancelsProcessingWithoutFinishingSession|testMacOSRecordingCancellationPlanRepairsIdleAndBusyState' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared macOS active-capture cancellation check runs in VoiceInkCore" \
  'testMacOSRecordingCancellationPlanFinishesActiveCaptureImmediately' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared macOS processing cancellation check runs in VoiceInkCore" \
  'testMacOSRecordingCancellationPlanCancelsProcessingWithoutFinishingSession' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared macOS idle cancellation repair check runs in VoiceInkCore" \
  'testMacOSRecordingCancellationPlanRepairsIdleAndBusyState' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared recording flow state lives in VoiceInkCore" \
  'VoiceInkRecordingFlowState|prepareRecordingStart|completeRecordingStart|failRecordingStart|finishRecording|cancelRecording|advanceDuration' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording flow state owns iOS duration tick interval" \
  'durationUpdateInterval: +TimeInterval += +0\.1' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_patterns \
  "shared recording permission action policy lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift \
  'VoiceInkRecordingPermissionPolicy' \
  'VoiceInkRecordingPermissionStatus' \
  'VoiceInkRecordingPermissionAction' \
  'VoiceInkRecordingPermissionSettingsAction' \
  'settingsOpenAction'

require_patterns \
  "shared recording permission action checks run in VoiceInkCore" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'testRecordingPermissionPolicyPreservesStartPermissionActions' \
  'testRecordingPermissionPolicyPreservesPermissionRequestResults' \
  'testRecordingPermissionPolicyPreservesSettingsOpenFallback'

require_pattern \
  "shared recording stop plan lives in VoiceInkCore" \
  'VoiceInkRecordingStopPlan|stopRecordingPlan' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording stop plan checks run in VoiceInkCore" \
  'testRecordingStopPlanFinishesFlowAndCreatesPendingDraftOnlyWhenAudioExists' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared audio-recorder stop cleanup plan lives in VoiceInkCore" \
  'VoiceInkAudioRecorderStopPolicy|VoiceInkAudioRecorderStopPlan|VoiceInkAudioRecorderStopMode' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared audio-recorder stop cleanup checks run in VoiceInkCore" \
  'testAudioRecorderStopPolicyPreservesIOSStopCleanup|testAudioRecorderStopPolicyPreservesIOSDiscardCleanup' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "iOS audio recorder applies shared stop cleanup plan" \
  'VoiceInkAudioRecorderStopPolicy\.plan|applyStopPlan|shouldDeleteCurrentRecordingFile|shouldClearCurrentRecordingURL' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_patterns \
  "shared iOS audio recorder configuration lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/IOSAudioConfiguration.swift \
  'VoiceInkIOSAudioRecorderConfiguration' \
  'voiceRecording' \
  'linearPCM' \
  'sampleRate: VoiceInkPCM16Audio\.mono16kSampleRate' \
  'channelCount: VoiceInkPCM16Audio\.monoChannelCount' \
  'bitDepth: VoiceInkPCM16Audio\.bitsPerSample' \
  'isBigEndian: VoiceInkPCM16Audio\.isBigEndian' \
  'isFloatingPoint: VoiceInkPCM16Audio\.isFloatingPoint' \
  'quality: \.high' \
  'isMeteringEnabled: true'

require_pattern \
  "VoiceInkCore checks cover iOS audio recorder configuration policy" \
  'AudioRecorderConfigurationTests\.testIOSAudioRecorderConfigurationUsesMono16kPCM16Policy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_patterns \
  "iOS audio recorder adapts shared recorder configuration" \
  iOS/VoiceInk-ios/AudioRecorder.swift \
  'VoiceInkIOSAudioRecorderConfiguration\.voiceRecording' \
  'configuration\.avAudioRecorderSettings' \
  'configuration\.isMeteringEnabled'

reject_pattern \
  "iOS audio recorder avoids shell-owned PCM16 recorder policy values" \
  'VoiceInkPCM16Audio\.(mono16kSampleRate|monoChannelCount|bitsPerSample|isBigEndian|isFloatingPoint)|isMeteringEnabled = true' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "migration docs track shared iOS audio recorder configuration policy" \
  'AudioRecorder\.swift` maps AVFoundation recorder settings from `VoiceInkIOSAudioRecorderConfiguration`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS recording engine uses shared active-recording predicate" \
  'recordingState\.isActivelyRecording' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recording engine asks shared cancellation plan" \
  'VoiceInkMacOSRecordingCancellationPolicy\.plan' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recording engine applies shared active-capture cancellation decision" \
  'cancellationPlan\.shouldFinishActiveRecorderCancellation' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recording engine applies shared immediate-session-finish decision" \
  'cancellationPlan\.shouldFinishRecorderSessionImmediately' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_context_pattern \
  "macOS recording cancellation avoids shell-owned state branch matrix" \
  'func cancelRecording\(\) async' \
  'recordingState\.isRecorderCaptureInProgress|else if +recordingState\.isPostRecordingProcessing|let shouldFinishSessionImmediately: Bool' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recording engine uses shared active-pipeline finish policy" \
  'recordingState\.shouldReturnToIdleWhenActivePipelineFinishes' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recording engine delegates microphone permission action planning to shared core" \
  'VoiceInkRecordingPermissionPolicy\.action|VoiceInkRecordingPermissionStatus' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recorder dismiss uses shared cancelable-state policy" \
  'recordingState\.isRecorderDismissCancelable' \
  VoiceInk/Transcription/Engine/RecorderUIManager.swift

require_pattern \
  "shared recorder UI session policy owns stale hidden session repair" \
  'shouldClearStaleHiddenRecorderSession' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "macOS recorder UI uses shared stale hidden session policy" \
  'VoiceInkRecorderUISessionPolicy\.shouldClearStaleHiddenRecorderSession' \
  VoiceInk/Transcription/Engine/RecorderUIManager.swift

require_pattern \
  "core checks execute stale hidden recorder session policy test" \
  'RecordingStatePolicyTests\.testRecorderSessionPolicyClearsOnlyStaleHiddenIdleSessions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS recorder preview uses shared active-recording predicate" \
  'recordingState\.isActivelyRecording' \
  VoiceInk/Views/Recorder/MiniRecorderView.swift

require_pattern \
  "macOS processing status display uses shared animation interval" \
  'presentation\.progressAnimationInterval' \
  VoiceInk/Views/Recorder/AudioVisualizerView.swift

require_pattern \
  "macOS recorder status display consumes shared processing presentation" \
  'recorderProcessingPresentation' \
  VoiceInk/Views/Recorder/RecorderComponents.swift

require_pattern \
  "macOS processing status display accepts shared processing presentation" \
  'VoiceInkRecorderProcessingPresentation' \
  VoiceInk/Views/Recorder/AudioVisualizerView.swift

require_pattern \
  "macOS notch recorder uses shared post-recording processing predicate" \
  'recordingState\.isPostRecordingProcessing' \
  VoiceInk/Views/Recorder/NotchRecorderView.swift

reject_pattern \
  "macOS recorder shells avoid shell-only processing state sets and copy" \
  'recordingState == \.(transcribing|enhancing|busy)|case \.starting, \.recording, \.transcribing, \.enhancing|case \.transcribing, \.enhancing|ProcessingStatusDisplay\(mode:|"Transcribing"|"Enhancing"|return 0\.18|return 0\.22' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift \
  VoiceInk/Transcription/Engine/RecorderUIManager.swift \
  VoiceInk/Views/Recorder/AudioVisualizerView.swift \
  VoiceInk/Views/Recorder/RecorderComponents.swift \
  VoiceInk/Views/Recorder/NotchRecorderView.swift

reject_pattern \
  "macOS recorder UI avoids shell-owned stale hidden session policy" \
  '!VoiceInkRecorderStylePreference\.hasVisibleRecorder\(rawValue: recorderType\)|activeSessionToggleAction\(for:' \
  VoiceInk/Transcription/Engine/RecorderUIManager.swift

require_pattern \
  "iOS recording manager uses shared active-recording predicate" \
  'recordingState\.isActivelyRecording' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS recording manager uses shared recording flow state" \
  'VoiceInkRecordingFlowState|flowState|updateFlowState' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS recording manager delegates duration ticks to shared flow state" \
  'VoiceInkRecordingFlowState\.durationUpdateInterval|advanceDuration' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS recording manager delegates microphone permission action planning to shared core" \
  'VoiceInkRecordingPermissionPolicy\.action|VoiceInkRecordingPermissionStatus|VoiceInkRecordingPermissionAction' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS recording manager delegates settings-open fallback planning to shared core" \
  'VoiceInkRecordingPermissionPolicy\.settingsOpenAction|VoiceInkRecordingPermissionSettingsAction' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS recording manager delegates stop result planning to shared flow state" \
  'stopRecordingPlan' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS recording manager adapts recorder URL into shared stop plan" \
  'audioFileURL: +recorder\.currentRecordingURL\?\.lastPathComponent' \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS recording manager avoids shell-owned recording flow fields" \
  '@Published var +(recordingState|animate|isRecordingSheetPresented|currentDuration)' \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS recording manager avoids shell-owned microphone permission action enum" \
  'private enum MicrophonePermissionStatus|case granted, denied, undetermined' \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS recording manager avoids shell-owned settings-open fallback branch" \
  'if +let +url += +URL\(string: +UIApplication\.openSettingsURLString\), +UIApplication\.shared\.canOpenURL\(url\)' \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS recording manager avoids shell-owned recording flow mutation" \
  '\b(recordingState|animate|isRecordingSheetPresented|currentDuration) *(=|\+=)|withTimeInterval: +0\.1' \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS recording manager avoids missing-audio early return before stop cleanup" \
  'guard +let +fileURL += +recorder\.currentRecordingURL +else +\{ +return +\}' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "shared recording alert presentation lives in VoiceInkCore" \
  'VoiceInkRecordingAlertPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording notification presentation lives in VoiceInkCore" \
  'VoiceInkRecordingNotificationPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording alert presentation owns iOS microphone-busy OSStatus" \
  'microphoneInUseOSStatusCode' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording alert presentation maps OSStatus domain" \
  'NSOSStatusErrorDomain' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "iOS recording manager uses shared permission-denied alert presentation" \
  'VoiceInkRecordingAlertPresentation\.microphonePermissionDenied' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS recording manager uses shared recording-failure alert presentation" \
  'VoiceInkRecordingAlertPresentation\.recordingStartFailure' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "shared iOS audio recorder start-failure error policy lives in VoiceInkCore" \
  'VoiceInkAudioRecorderStartFailurePolicy|returnedFalseErrorCode|returnedFalseErrorDomain|returnedFalseUserInfo|returnedFalseError\(\)' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore checks cover iOS audio recorder start-failure error policy" \
  'testAudioRecorderStartFailurePolicyBuildsIOSReturnedFalseError' \
  VoiceInkCore/Tests/VoiceInkCoreTests/RecordingStatePolicyTests.swift

require_pattern \
  "iOS audio recorder uses shared recording-start failure error policy" \
  'VoiceInkAudioRecorderStartFailurePolicy\.returnedFalseError\(\)' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "VoiceInkCore owns iOS recording start action policy" \
  'VoiceInkRecordingStart(Action|Policy)|action\(modeCount:' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore checks cover iOS recording start action policy" \
  'testRecordingStartPolicy(StartsWhenModesAreAvailable|PresentsNoModeAlertWhenNoModesAreAvailable)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/RecordingStatePolicyTests.swift

require_pattern \
  "iOS recording manager delegates every start entrypoint to shared mode-count policy" \
  'VoiceInkRecordingStartPolicy\.action' \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS note-list start button avoids duplicate start-policy branching" \
  'VoiceInkRecordingStartPolicy\.action|recordingStartAlert|case \.presentAlert|case \.startRecording' \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS note-list start button avoids shell-owned no-mode branching" \
  'noModesAvailableIfNeeded|if +let +alert *= *VoiceInkRecordingAlertPresentation' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "macOS recording engine uses shared recording notification presentation" \
  'VoiceInkRecordingNotificationPresentation\.(noTranscriptionModelSelected|failedToStart|microphonePermissionRequired)' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recorder uses shared runtime failure notification presentation" \
  'VoiceInkRecordingNotificationPresentation\.runtimeFailure' \
  VoiceInk/Recorder.swift

require_pattern \
  "shared recording notification presentation owns macOS microphone-permission title" \
  '"Microphone permission required"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording notification presentation owns macOS microphone-permission duration" \
  'duration: +8\.0' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared recording notification presentation owns macOS microphone-permission action copy" \
  'actionButtonTitle: +"Grant"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared macOS recorder style preference lives in VoiceInkCore" \
  'VoiceInkRecorderStyle|VoiceInkRecorderWindowKind|VoiceInkRecorderStylePreference|VoiceInkMacOSRecorderStyleSettingsPresentation|userDefaultsKey = "RecorderType"|defaultRawValue|windowKind|hasVisibleRecorder' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "macOS recorder UI manager uses shared recorder style policy" \
  'VoiceInkRecorderStylePreference\.(rawValue|saveRawValue|hasVisibleRecorder|windowKind)' \
  VoiceInk/Transcription/Engine/RecorderUIManager.swift

require_pattern \
  "macOS recorder settings uses shared recorder style catalog" \
  'VoiceInkRecorderStylePreference\.macOSSettingsPresentation|recorderStylePresentation\.(sectionTitle|pickerTitle)|VoiceInkRecorderStyle\.allCases|style\.displayName|style\.rawValue' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS defaults register shared recorder style default" \
  'VoiceInkRecorderStylePreference\.(userDefaultsKey|defaultRawValue)' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS diagnostics use shared recorder style preference" \
  'VoiceInkRecorderStylePreference\.rawValue\(\)' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "shared mode selection presentation lives in VoiceInkCore" \
  'VoiceInkModeSelectionPresentation|controlTitle' \
  VoiceInkCore/Sources/VoiceInkCore/Mode.swift

require_pattern \
  "shared recording sheet presentation lives in VoiceInkCore" \
  'VoiceInkRecordingSheetPresentation|cancelButtonTitle|stopButtonTitle|stopButtonSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared mode summary presentation lives in VoiceInkCore" \
  'VoiceInkModeSummaryPresentation|summaryPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/Mode.swift

require_pattern \
  "shared mode form presentation lives in VoiceInkCore" \
  'VoiceInkModeFormPresentation|formPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/Mode.swift

require_pattern \
  "shared mode form provider availability lives in VoiceInkCore" \
  'VoiceInkModeFormProviderAvailability|providerAvailability' \
  VoiceInkCore/Sources/VoiceInkCore/Mode.swift

require_pattern \
  "shared mode list policy lives in VoiceInkCore" \
  'VoiceInkModeListPolicy|appending\(|replacing\(|removing\(at:|defaultModeRepairPlan|VoiceInkModeListRepairPlan' \
  VoiceInkCore/Sources/VoiceInkCore/Mode.swift

require_pattern \
  "core checks execute mode list removal policy test" \
  'ModeRuntimeConfigurationTests\.testModeListPolicyRemovesModesByOffsets' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared mode settings repair plan lives in VoiceInkCore" \
  'VoiceInkModeSettingsPolicy|VoiceInkModeSettingsRepairPlan|VoiceInkModeSettingsRepairAction|applicationActions|shouldApplySelectedModeId|shouldApplySelectedTranscriptionLanguage' \
  VoiceInkCore/Sources/VoiceInkCore/Mode.swift

require_pattern \
  "core checks execute mode settings repair action tests" \
  'ModeRuntimeConfigurationTests\.testModeSettingsRepairPlanBuilds(NoActionsWhenCurrentStateMatches|SelectionAndLanguageActions|DefaultModeSeedActionsInOrder)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "iOS recording sheet uses shared mode selection presentation adapter" \
  'VoiceInkModeSelectionControlView' \
  iOS/VoiceInk-ios/RecordingSheetView.swift

require_pattern \
  "iOS recording sheet uses shared recording sheet presentation" \
  'VoiceInkRecordingSheetPresentation\.iOS|recordingSheetPresentation\.(cancelButtonTitle|stopButtonTitle|stopButtonSystemImageName)' \
  iOS/VoiceInk-ios/RecordingSheetView.swift

require_pattern \
  "iOS retry status uses shared mode selection presentation adapter" \
  'VoiceInkModeSelectionControlView' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS mode selection adapter delegates picker-vs-label policy to shared core" \
  'modeSelectionPresentation' \
  iOS/VoiceInk-ios/RecordingSheetView.swift

reject_pattern \
  "iOS mode selection adapter avoids shallow presentation wrapper" \
  'private var +presentation\b' \
  iOS/VoiceInk-ios/RecordingSheetView.swift

require_pattern \
  "iOS settings mode rows use shared summary presentation" \
  'summaryPresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

require_patterns \
  "iOS AppSettings uses shared mode list policy" \
  iOS/VoiceInk-ios/AppSettings.swift \
  'VoiceInkModeListPolicy\.appending' \
  'VoiceInkModeListPolicy\.replacing' \
  'VoiceInkModeListPolicy\.removing'

require_pattern \
  "iOS AppSettings delegates mode selection and language repair to shared core" \
  'VoiceInkModeSettingsPolicy\.repairPlan|VoiceInkModeSettingsRepairPlan|applicationActions|VoiceInkModeSettingsRepairAction' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS AppSettings avoids shell-owned mode selection and language repair sequencing" \
  'repairedSelectedModeId|repairedSelectedTranscriptionLanguage|VoiceInkModeListPolicy\.defaultModeRepairPlan|selectedModeId != plan\.selectedModeId|selectedTranscriptionLanguage != plan\.selectedTranscriptionLanguage|plan\.shouldReplaceModes|plan\.shouldApplySelectedModeId|plan\.shouldApplySelectedTranscriptionLanguage' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS AppSettings exposes shared mode form provider availability" \
  'VoiceInkModeFormProviderAvailability|modeFormProviderAvailability' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS mode configuration uses shared form presentation" \
  'formPresentation|VoiceInkModeFormPresentation' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "iOS mode configuration uses shared provider availability" \
  'modeFormProviderAvailability|providerAvailability\.(canSave|repairedMode|transcriptionProviders|postProcessingProviders)' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

reject_pattern \
  "iOS mode configuration avoids shallow form pass-through properties" \
  'private var +(canSave|presentation|providerAvailability)\b' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "shared settings presentation lives in VoiceInkCore" \
  'VoiceInkSettingsPresentation|VoiceInkMacOSSettingsPresentation|addModeButtonTitle|resetAllAppDataButtonTitle|checkForUpdatesButtonTitle|backupFooterText' \
  VoiceInkCore/Sources/VoiceInkCore/SettingsPresentation.swift

require_pattern \
  "iOS settings uses shared settings presentation" \
  'VoiceInkSettingsPresentation\.iOS|settingsPresentation\.(navigationTitle|modesSectionTitle|addModeButtonTitle|addActionSystemImageName|debugSectionTitle|resetAllAppDataButtonTitle|resetAllAppDataSystemImageName)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS settings uses shared top-level settings presentation" \
  'VoiceInkMacOSSettingsPresentation\.macOS|settingsPresentation\.(generalSectionTitle|showMenuBarIconTitle|hideDockIconTitle|launchAtLoginTitle|autoCheckUpdatesTitle|showAnnouncementsTitle|checkForUpdatesButtonTitle|privacySectionTitle|privacyFooterText|backupSectionTitle|backupFooterText|exportSettingsLabel|exportButtonTitle|importSettingsLabel|importButtonTitle|diagnosticsSectionTitle)' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "core checks execute settings presentation tests" \
  'SettingsPresentationTests\.testIOSSettingsPresentationPreservesSettingsChromeCopy|SettingsPresentationTests\.testMacOSSettingsPresentationPreservesSettingsChromeCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_file VoiceInkCore/Sources/VoiceInkCore/AnnouncementsPolicy.swift

require_pattern \
  "shared announcement policy owns feed and storage defaults" \
  'VoiceInkAnnouncementPreference|isEnabledKey = VoiceInkUserDefaultsKey\.enableAnnouncements|dismissedIdsKey = "dismissedAnnouncementIds"|announcementsURLString = "https://beingpax\.github\.io/VoiceInk/announcements\.json"|refreshInterval|initialFetchDelay|requestTimeout|maxDismissedIdsToKeep' \
  VoiceInkCore/Sources/VoiceInkCore/AnnouncementsPolicy.swift

require_pattern \
  "shared announcement policy owns dismissal and active selection" \
  'dismissedIds\(afterDismissing|nextAnnouncement|isActive|VoiceInkAnnouncementPresentation|VoiceInkRemoteAnnouncement|closeButtonSystemImageName|learnMoreButtonTitle|dismissButtonTitle|shouldShowDescription' \
  VoiceInkCore/Sources/VoiceInkCore/AnnouncementsPolicy.swift

require_pattern \
  "macOS announcements service uses shared announcement policy" \
  'VoiceInkAnnouncementPreference\.(announcementsURL|refreshInterval|initialFetchDelay|requestTimeout|dismissedIds|saveDismissedIds)|VoiceInkAnnouncementPolicy\.nextAnnouncement|VoiceInkRemoteAnnouncement' \
  VoiceInk/Services/AnnouncementsService.swift

require_patterns \
  "macOS announcements service passes shared announcement presentation through shell" \
  VoiceInk/Services/AnnouncementsService.swift \
  'AnnouncementManager\.shared\.showAnnouncement' \
  'presentation: next'

require_pattern \
  "macOS announcement manager accepts shared announcement presentation" \
  'showAnnouncement\(presentation: VoiceInkAnnouncementPresentation' \
  VoiceInk/Notifications/AnnouncementManager.swift

require_patterns \
  "macOS announcement view renders shared announcement presentation" \
  VoiceInk/Notifications/AnnouncementView.swift \
  'let presentation: VoiceInkAnnouncementPresentation' \
  'presentation\.title' \
  'presentation\.descriptionText' \
  'presentation\.shouldShowDescription' \
  'presentation\.closeButtonSystemImageName' \
  'presentation\.learnMoreButtonTitle' \
  'presentation\.dismissButtonTitle'

require_pattern \
  "macOS app uses shared announcements enablement key" \
  '@AppStorage\(VoiceInkAnnouncementPreference\.isEnabledKey\)' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS settings uses shared announcements enablement key" \
  '@AppStorage\(VoiceInkAnnouncementPreference\.isEnabledKey\)' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS defaults register shared announcement defaults" \
  'VoiceInkAnnouncementPreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "core checks execute announcement policy tests" \
  'AnnouncementsPolicyTests\.testAnnouncementPreferencePreservesMacOSStorageAndFetchDefaults|AnnouncementsPolicyTests\.testNextAnnouncementSkipsDismissedAndInactiveThenReturnsFirstValidPresentation|AnnouncementsPolicyTests\.testAnnouncementPresentationPreservesMacOSActionCopyAndDescriptionVisibility' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared announcement presentation copy" \
  'announcements enablement.*next-announcement presentation, action copy, close icon, and description visibility.*VoiceInkAnnouncementPreference`/`VoiceInkAnnouncementPolicy' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS announcement shell avoids raw announcement policy" \
  '"(enableAnnouncements|dismissedAnnouncementIds|https://beingpax\.github\.io/VoiceInk/announcements\.json)"|private struct RemoteAnnouncement|ISO8601DateFormatter|maxDismissedToKeep|refreshInterval: TimeInterval = 4|DispatchQueue\.main\.asyncAfter\(deadline: \.now\(\) \+ 5\)' \
  VoiceInk/Services/AnnouncementsService.swift \
  VoiceInk/AppDefaults.swift \
  VoiceInk/VoiceInk.swift \
  VoiceInk/Views/Settings/SettingsView.swift

reject_pattern \
  "macOS announcement shell avoids raw announcement presentation copy" \
  '"(xmark|Learn more|Dismiss)"|trimmingCharacters\(in: \.whitespacesAndNewlines\)|description \?\? ""|title: next\.title|description: next\.description|learnMoreURL: next\.learnMoreURL' \
  VoiceInk/Notifications/AnnouncementView.swift \
  VoiceInk/Notifications/AnnouncementManager.swift \
  VoiceInk/Services/AnnouncementsService.swift

reject_pattern \
  "iOS mode selection views avoid shell-only mode-count picker branching" \
  'modes\.count > 1|settings\.modes\.count > 1|modes\.first|settings\.modes\.first|!settings\.modes\.isEmpty' \
  iOS/VoiceInk-ios/RecordingSheetView.swift \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_pattern \
  "iOS AppSettings avoids shell-owned mode list mutation policy" \
  'modes\.append|modes\[index\]|firstIndex\(where: \{ \$0\.id == modeId \}\)|Mode\.defaultModesAndSelection\(|VoiceInkPreferenceList\.removing' \
  iOS/VoiceInk-ios/AppSettings.swift

section "obsolete standalone preference-list module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/PreferenceList.swift

require_pattern \
  "shared preference-list policy lives with UserDefaults preference policy" \
  'VoiceInkPreferenceList|changedElements|removing<Element>' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

reject_pattern \
  "iOS recording sheet avoids shell-only recording controls copy" \
  '"(Cancel|Stop Recording|Mode)"' \
  iOS/VoiceInk-ios/RecordingSheetView.swift

reject_pattern \
  "iOS recording sheet avoids duplicate stop-button icon" \
  '"stop\.fill"' \
  iOS/VoiceInk-ios/RecordingSheetView.swift

reject_pattern \
  "iOS settings mode rows avoid shell-only model summary formatting" \
  'Transcription: |Post-processing: |effectiveTranscriptionModel|effectivePostProcessingModel' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS settings avoids shell-only settings chrome and action copy" \
  '"(Modes|Add New Mode|Debug|Reset All App Data|Settings|plus\.circle\.fill|trash)"' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "macOS settings avoids shell-only top-level settings copy" \
  '"(Show in Menu Bar|Hide Dock Icon|Launch at Login|Auto-check Updates|Show Announcements|Check for Updates|Privacy|Control how VoiceInk handles your transcription data and audio recordings\.|Export Settings|Export|Import Settings|Import|Backup|Export all settings, or choose specific categories when importing a backup\.|Diagnostics)"' \
  VoiceInk/Views/Settings/SettingsView.swift

reject_pattern \
  "iOS mode configuration avoids shell-only form presentation copy" \
  '"(Mode Details|Mode Name|Transcription|Post-processing|Enable Post-processing|Provider|Prompt Template|Custom Prompt|Edit Mode|New Mode|Save|Model)"|Configure how the raw transcription should be processed and refined\.' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

reject_pattern \
  "iOS mode configuration avoids shell-owned provider availability plumbing" \
  'settings\.availableProviders\(for:|isSaveableDraft\(availableTranscriptionProviders:|repairProviderSelection\(availableTranscriptionProviders:' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

reject_pattern \
  "iOS recording views avoid shell-only recording alert copy and OSStatus mapping" \
  'ActiveRecordingAlert|Microphone Access Denied|Microphone In Use|Recording Failed|No Modes Found|Please create a new mode in Settings before recording|Could not start recording:|561017449|NSOSStatusErrorDomain' \
  iOS/VoiceInk-ios/RecordingManager.swift \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS audio recorder avoids shell-owned recording-start failure error policy" \
  'Failed to start AVAudioRecorder|record\(\) method returned false|audio session is not configured correctly|NSLocalizedDescriptionKey|NSError\(domain:|code: 1001|VoiceInkAppIdentity\.errorDomain\(component: "AudioRecorder"\)' \
  iOS/VoiceInk-ios/AudioRecorder.swift

reject_pattern \
  "macOS recorder style avoids shell-owned raw policy" \
  '"RecorderType"|"(none|notch|mini)"|"(Interface|Recorder Style)"|recorderType != "none"|recorderType == "none"|case "(none|notch|mini)"|Text\("(None|Notch|Mini)"\)' \
  VoiceInk/Transcription/Engine/RecorderUIManager.swift \
  VoiceInk/Views/Settings/SettingsView.swift \
  VoiceInk/AppDefaults.swift \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "migration checklist tracks shared recorder style settings labels" \
  'macOS recorder style labels, settings section/picker labels, raw storage key/default' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared recorder UI session policy" \
  'stale hidden-recorder session policy routes through `VoiceInkRecorderUISessionPolicy`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared announcement policy gate" \
  'macOS announcements .*VoiceInkAnnouncementPreference.*VoiceInkAnnouncementPolicy' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "recording behavior avoids raw active-state equality" \
  'recordingState == \.recording' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift \
  VoiceInk/Views/Recorder/MiniRecorderView.swift \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "macOS recording engine avoids shell-only start failure notification copy" \
  '"No AI Model Selected"|"Recording failed to start"|"Microphone permission required"|label: "Grant"' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS recorder avoids shell-only runtime failure notification copy" \
  '"Recording Failed:' \
  VoiceInk/Recorder.swift

reject_pattern \
  "iOS recording background transcription uses shared record updates" \
  '\b(existingAudioFileURL|markTranscriptionFailed|applyCompletedRunResult)\b' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS retry adapter owns stored-audio retranscription record update" \
  'retranscribeStoredAudio' \
  iOS/VoiceInk-ios/TranscriptionRetryService.swift

require_pattern \
  "iOS recording manager delegates background retry to retry adapter" \
  'TranscriptionRetryService\.shared\.retranscribe\(note: note\)' \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS recording manager avoids direct stored-audio retry mutation seam" \
  'retranscribeStoredAudio|TranscriptionRetryService\.shared\.transcribe\(fileURL:' \
  iOS/VoiceInk-ios/RecordingManager.swift

section "obsolete standalone recording transcription draft module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/RecordingTranscriptionDraft.swift

require_pattern \
  "shared recording transcription draft lives with completed transcription drafts" \
  'VoiceInkRecordingTranscriptionDraft' \
  VoiceInkCore/Sources/VoiceInkCore/CompletedTranscriptionDraft.swift

section "obsolete standalone transcription status module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/TranscriptionStatus.swift

require_pattern \
  "shared transcription status lives with record mutation policy" \
  'public enum VoiceInkTranscriptionStatus|case pending|case completed|case failed|case canceled' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "shared transcription cancellation plan lives in VoiceInkCore" \
  'public struct VoiceInkTranscriptionRecordCancellationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "shared transcription cancellation plan owns canceled text" \
  'self\.text = VoiceInkTranscriptPresentation\.canceledTranscriptionText' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "shared transcription cancellation plan owns canceled status" \
  'self\.status = \.canceled' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "shared mutable transcription records can apply cancellation plan" \
  'applyCancellationPlan|markTranscriptionCanceled' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "macOS Transcription adapts shared recording draft" \
  'init\(recordingDraft draft: VoiceInkRecordingTranscriptionDraft\)' \
  VoiceInk/Models/Transcription.swift

require_pattern \
  "iOS Transcription adapts shared recording draft" \
  'init\(recordingDraft draft: VoiceInkRecordingTranscriptionDraft\)' \
  iOS/VoiceInk-ios/Transcription.swift

require_pattern \
  "macOS recording rows build shared recording draft" \
  'VoiceInkRecordingTranscriptionDraft' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS live recording builds shared pending recording draft" \
  'VoiceInkRecordingTranscriptionDraft\.pending' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS canceled recording builds shared canceled recording draft" \
  'VoiceInkRecordingTranscriptionDraft\.canceled' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recording rows insert through shared recording draft" \
  'Transcription\(recordingDraft: draft\)' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS recording rows avoid shell-only pending/canceled draft construction" \
  'text: VoiceInkTranscriptPresentation\.canceledTranscriptionText|transcriptionStatus: +\.(pending|canceled)' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "iOS live recording receives shared stop-plan pending draft" \
  'stopPlan\.pendingDraft' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS live recording inserts through shared recording draft" \
  'Transcription\(recordingDraft: draft\)' \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS live recording avoids shell-only pending note construction" \
  'transcriptionStatus: +\.pending' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS live recording uses shared stored-audio filename policy" \
  'VoiceInkStoredAudioFile\.timestampedRecordingFileURL' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "iOS note detail uses shared stored-audio availability presentation" \
  'storedAudioAvailability\(\)|shouldShowAudioSection|unavailableTitle|unavailableDetail|unavailableSystemImageName' \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_pattern \
  "iOS note detail avoids shallow audio-section visibility wrappers" \
  'private var +(shouldShowAudioSection|audioAvailability)\b' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "shared stored-audio availability owns unavailable icon" \
  'unavailableSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/StoredAudioFile.swift

reject_pattern \
  "iOS note detail avoids shell-only stored-audio path checks" \
  'VoiceInkStoredAudioFile\.(availability|existingURL|fileExists)|FileManager|audioFileURL' \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_pattern \
  "iOS audio player consumes availability-gated paths" \
  'FileManager\.default\.fileExists' \
  iOS/VoiceInk-ios/AudioPlayerView.swift

require_pattern \
  "iOS note deletion uses shared stored-audio record delete helper" \
  'deleteExistingAudioFile\(\)' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "shared stored-audio file owns deletion error text" \
  'deletionErrorMessage\(for error: Error\)' \
  VoiceInkCore/Sources/VoiceInkCore/StoredAudioFile.swift

require_pattern \
  "shared stored-audio deletion error copy is centralized" \
  '"Error deleting audio file:' \
  VoiceInkCore/Sources/VoiceInkCore/StoredAudioFile.swift

require_pattern \
  "iOS note deletion uses shared stored-audio deletion error text" \
  'VoiceInkStoredAudioFile\.deletionErrorMessage' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "macOS full history deletion uses shared stored-audio deletion error text" \
  'VoiceInkStoredAudioFile\.deletionErrorMessage' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift

require_pattern \
  "macOS inline history deletion uses shared stored-audio deletion error text" \
  'VoiceInkStoredAudioFile\.deletionErrorMessage' \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "platform note/history deletion avoids duplicate stored-audio deletion error text" \
  '"Error deleting audio file:' \
  iOS/VoiceInk-ios/NotesListView.swift \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "iOS note deletion avoids shell-only stored-audio file deletion" \
  'FileManager|removeItem|audioFileURL' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "shared stored-audio record owns delete-and-clear policy" \
  'deleteExistingAudioFileAndClearReference' \
  VoiceInkCore/Sources/VoiceInkCore/StoredAudioFile.swift

require_pattern \
  "shared supported-media presentation lives in VoiceInkCore" \
  'displayFileExtensions|supportedFileTypesText|openPanelContentTypes|dropContentTypes|dropProviderTypeIdentifiers' \
  VoiceInkCore/Sources/VoiceInkCore/SupportedMedia.swift

require_pattern \
  "shared audio-file queue status and presentation live in VoiceInkCore" \
  'VoiceInkAudioFileQueue(Status|ProcessingPhase|Policy|Presentation)|VoiceInkAudioImportPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/SupportedMedia.swift

require_pattern \
  "shared audio-file queue policy owns mutation decisions" \
  'VoiceInkAudioFileQueuePolicy|eligibleAdditionURLs|canRemoveItem|statusAfterRetryRequest|nextPendingItemID|hasPendingItems|statusesAfterCancelingProcessing' \
  VoiceInkCore/Sources/VoiceInkCore/SupportedMedia.swift

reject_pattern \
  "shared audio-file queue status avoids public predicate helpers" \
  'public +var +(isTerminal|isPending|isProcessing|canRemoveFromQueue|canRetry) *: *Bool' \
  VoiceInkCore/Sources/VoiceInkCore/SupportedMedia.swift

require_pattern \
  "macOS audio import help uses shared supported-media presentation" \
  'VoiceInkSupportedMedia\.supportedFileTypesText' \
  VoiceInk/Views/AudioTranscribeView.swift

require_pattern \
  "macOS audio import view uses shared supported-media type identifiers" \
  'VoiceInkSupportedMedia\.(openPanelContentTypes|dropContentTypes|dropProviderTypeIdentifiers)' \
  VoiceInk/Views/AudioTranscribeView.swift

require_pattern \
  "macOS audio import view uses shared queue presentation" \
  'VoiceInkAudioImportPresentation\.(dropTargetSystemImageName|queueCountText|addButtonTitle|cancelButtonTitle|startButtonTitle|clearButtonTitle|enhancementToggleTitle|promptPickerTitle)' \
  VoiceInk/Views/AudioTranscribeView.swift

require_pattern \
  "macOS audio queue item uses shared queue status" \
  'VoiceInkAudioFileQueueStatus' \
  VoiceInk/Models/AudioFileQueueItem.swift

require_pattern \
  "macOS audio queue manager delegates queue mutation policy" \
  'VoiceInkAudioFileQueuePolicy\.(eligibleAdditionURLs|canRemoveItem|statusAfterRetryRequest|nextPendingItemID|hasPendingItems|statusesAfterCancelingProcessing)' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS audio file row uses shared queue presentation" \
  'VoiceInkAudioFileQueuePresentation\.(pendingStatusSystemImageName|pendingStatusText|completedStatusSystemImageName|failedStatusSystemImageName|retryButtonSystemImageName)' \
  VoiceInk/Views/AudioFileRow.swift

require_pattern \
  "core tests pin supported-media presentation copy" \
  'testSupportedMediaDisplayExtensionsPreserveMacOSImportCopyOrder|testSupportedMediaImportTypePoliciesPreserveMacOSShellIdentifiers|testSupportedMediaDisplayExtensionsMatchAcceptedExtensions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/SupportedMediaTests.swift

require_pattern \
  "core tests pin audio-file queue status and presentation" \
  'testAudioImportPresentationPreservesMacOSQueueCopyAndActions|testAudioFileQueueProcessingPhasesPreserveCopy|testAudioFileQueueStatusCancelingProcessingResetsOnlyProcessingItems|testAudioFileQueuePolicyKeepsOnlyExistingSupportedNonActivePaths|testAudioFileQueuePolicyPreservesMutationDecisions|testAudioFileQueuePresentationPreservesRowCopyAndIcons' \
  VoiceInkCore/Tests/VoiceInkCoreTests/SupportedMediaTests.swift

require_pattern \
  "core check runner executes supported-media presentation tests" \
  'testSupportedMediaDisplayExtensionsPreserveMacOSImportCopyOrder|testSupportedMediaImportTypePoliciesPreserveMacOSShellIdentifiers|testSupportedMediaDisplayExtensionsMatchAcceptedExtensions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core check runner executes audio-file queue status and presentation tests" \
  'testAudioImportPresentationPreservesMacOSQueueCopyAndActions|testAudioFileQueueProcessingPhasesPreserveCopy|testAudioFileQueueStatusCancelingProcessingResetsOnlyProcessingItems|testAudioFileQueuePolicyKeepsOnlyExistingSupportedNonActivePaths|testAudioFileQueuePolicyPreservesMutationDecisions|testAudioFileQueuePresentationPreservesRowCopyAndIcons' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS audio import view avoids shell-owned supported-media list copy" \
  'Supports WAV|MP3, M4A|OGG, OPUS|OGG, OGA|OPUS, 3GP|onDrop\(of: \[\.(fileURL|data|audio|movie)|allowedContentTypes = \[\.(audio|movie)|UTType\.(fileURL|audio|movie|data)\.identifier|"public\.file-url"' \
  VoiceInk/Views/AudioTranscribeView.swift

reject_pattern \
  "macOS audio import view avoids shell-owned queue copy and action icons" \
  '"(arrow\.down\.doc|Drop audio or video files here|or|Choose Files|Drop files anywhere to add more|Drop to add files|plus|Add|Add files|stop\.fill|Cancel|Cancel transcription|play\.fill|Start|xmark\.bin|Clear|Clear all items|AI Enhancement|Prompt)"' \
  VoiceInk/Views/AudioTranscribeView.swift

reject_pattern \
  "macOS audio queue item avoids shell-owned queue status enum" \
  'enum +(QueueItemStatus|ProcessingPhase)\b|case +processingAudio = "Processing audio\.\.\."' \
  VoiceInk/Models/AudioFileQueueItem.swift

reject_pattern \
  "macOS audio queue manager avoids shell-owned queue status predicates" \
  'guard +case +\.(pending|failed) += +item\.status|if +case +\.processing += +item\.status|queue\.(contains|first) +\{ +if +case +\.pending += +\$0\.status' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

reject_pattern \
  "macOS audio file row avoids shell-owned queue copy and icons" \
  '"(clock|Waiting|xmark\.circle\.fill|checkmark\.circle\.fill|chevron\.right|cpu|sparkles|exclamationmark\.circle\.fill|arrow\.counterclockwise)"' \
  VoiceInk/Views/AudioFileRow.swift

require_pattern \
  "macOS audio cleanup clears audio references through shared helper" \
  'deleteExistingAudioFileAndClearReference\(\)' \
  VoiceInk/Views/Settings/AudioCleanupManager.swift

require_pattern \
  "macOS audio cleanup uses shared cleanup check interval" \
  'VoiceInkAudioCleanupPreference\.cleanupCheckInterval' \
  VoiceInk/Views/Settings/AudioCleanupManager.swift

reject_pattern \
  "macOS audio cleanup avoids shell-owned cleanup check interval literals" \
  '\b(86400|86_400)\b' \
  VoiceInk/Views/Settings/AudioCleanupManager.swift

reject_pattern \
  "macOS audio cleanup avoids shell-only delete-and-clear sequence" \
  'audioFileURL = nil' \
  VoiceInk/Views/Settings/AudioCleanupManager.swift

reject_pattern \
  "macOS audio cleanup avoids shell-owned file-size presentation" \
  'formatFileSize|ByteCountFormatter' \
  VoiceInk/Views/Settings/AudioCleanupManager.swift

require_patterns \
  "iOS live recording adapts shared recorder configuration to AVFoundation" \
  iOS/VoiceInk-ios/AudioRecorder.swift \
  'AVFormatIDKey: format\.avFormatID' \
  'AVSampleRateKey: sampleRate' \
  'AVNumberOfChannelsKey: channelCount' \
  'AVLinearPCMBitDepthKey: bitDepth' \
  'AVLinearPCMIsBigEndianKey: isBigEndian' \
  'AVLinearPCMIsFloatKey: isFloatingPoint' \
  'AVEncoderAudioQualityKey: quality\.avQualityRawValue'

require_pattern \
  "shared audio-processing error vocabulary lives in VoiceInkCore" \
  'VoiceInkAudioProcessingError|invalidAudioFile|conversionFailed|unsupportedFormat' \
  VoiceInkCore/Sources/VoiceInkCore/PCM16AudioSamples.swift

section "obsolete standalone Whisper audio sample module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/WhisperAudioSamples.swift

require_pattern \
  "shared Whisper audio sample policy lives with PCM16 conversion" \
  'VoiceInkWhisperAudioSamples|audioLevelingTargetPeak|leveledFloatSamples' \
  VoiceInkCore/Sources/VoiceInkCore/PCM16AudioSamples.swift

require_pattern \
  "core tests pin shared audio-processing error copy" \
  'testAudioProcessingErrorDescriptionsPreserveMacOSImportCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/PCM16AudioSamplesTests.swift

require_pattern \
  "core check runner executes shared audio-processing error copy test" \
  'PCM16AudioSamplesTests\.testAudioProcessingErrorDescriptionsPreserveMacOSImportCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS audio processor throws shared audio-processing errors" \
  'VoiceInkAudioProcessingError\.(invalidAudioFile|conversionFailed|unsupportedFormat)' \
  VoiceInk/Transcription/Engine/AudioFileProcessor.swift

reject_pattern \
  "macOS audio processor avoids shell-owned audio-processing error vocabulary" \
  'enum +AudioProcessingError|"The audio file is invalid or corrupted"|"Failed to convert the audio format"|"The audio format is not supported"' \
  VoiceInk/Transcription/Engine/AudioFileProcessor.swift

require_pattern \
  "iOS live recording uses shared audio-meter history update plan" \
  'VoiceInkAudioMeterLevel\.iOSMeterHistoryUpdatePlan' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "shared audio-meter update plans live in VoiceInkCore" \
  'VoiceInk(MacOSAudioMeterUpdatePlan|IOSAudioMeterHistoryUpdatePlan)|macOSMeterUpdatePlan|iOSMeterHistoryUpdatePlan' \
  VoiceInkCore/Sources/VoiceInkCore/AudioMeterLevel.swift

require_pattern \
  "shared audio-meter update cadences live in VoiceInkCore" \
  'macOSUpdateIntervalMilliseconds|iOSUpdateInterval' \
  VoiceInkCore/Sources/VoiceInkCore/AudioMeterLevel.swift

require_pattern \
  "macOS audio-meter timer uses shared update cadence" \
  'VoiceInkAudioMeterLevel\.macOSUpdateIntervalMilliseconds' \
  VoiceInk/Recorder.swift

require_pattern \
  "iOS audio-meter timer uses shared update cadence" \
  'VoiceInkAudioMeterLevel\.iOSUpdateInterval' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "macOS recorder applies shared audio-meter update plan" \
  'VoiceInkAudioMeterLevel\.macOSMeterUpdatePlan' \
  VoiceInk/Recorder.swift

require_pattern \
  "iOS recorder applies shared audio-meter update plan" \
  'VoiceInkAudioMeterLevel\.iOSMeterHistoryUpdatePlan' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "shared audio-meter visualizer accessibility label lives in VoiceInkCore" \
  'VoiceInkAudioMeterLevel|visualizerAccessibilityLabel' \
  VoiceInkCore/Sources/VoiceInkCore/AudioMeterLevel.swift

require_pattern \
  "shared audio-meter visualizer bar policy lives in VoiceInkCore" \
  'iOSVisualizerBarCount|iOSVisualizerBarSpacing|iOSVisualizerBarMinimumWidth|iOSVisualizerHorizontalPadding|iOSVisualizerWidthInset|iOSVisualizerFrameHeight|iOSVisualizerMinimumBarHeight|iOSVisualizerAnimationDuration|visualizerLevel|iOSVisualizerBarWidth|iOSVisualizerBarHeight' \
  VoiceInkCore/Sources/VoiceInkCore/AudioMeterLevel.swift

require_pattern \
  "shared macOS audio-meter visualizer policy lives in VoiceInkCore" \
  'macOSVisualizerBarCount|macOSVisualizerAnimationMinimumInterval|macOSVisualizerBarHeight' \
  VoiceInkCore/Sources/VoiceInkCore/AudioMeterLevel.swift

require_pattern \
  "shared audio-meter visualizer checks run in VoiceInkCore" \
  'testIOSVisualizer(Level|BarPolicy|BarWidth|BarHeight)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared macOS audio-meter visualizer checks run in VoiceInkCore" \
  'testMacOSVisualizer(Geometry|BarHeight)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared audio-meter update plan checks run in VoiceInkCore" \
  'AudioMeterLevelTests\.test(MacOSMeterUpdatePlanNormalizesAndSmoothsAverageAndPeak|IOSMeterHistoryUpdatePlanNormalizesAndBoundsHistory)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS audio visualizer uses shared geometry policy" \
  'VoiceInkAudioMeterLevel\.macOSVisualizer(BarCount|BarWidth|BarSpacing|MinimumBarHeight)' \
  VoiceInk/Views/Recorder/AudioVisualizerView.swift

require_pattern \
  "macOS audio visualizer uses shared animation cadence" \
  'VoiceInkAudioMeterLevel\.macOSVisualizerAnimationMinimumInterval' \
  VoiceInk/Views/Recorder/AudioVisualizerView.swift

require_pattern \
  "macOS audio visualizer uses shared bar-height policy" \
  'VoiceInkAudioMeterLevel\.macOSVisualizerBarHeight' \
  VoiceInk/Views/Recorder/AudioVisualizerView.swift

require_pattern \
  "iOS audio visualizer uses shared accessibility label" \
  'VoiceInkAudioMeterLevel\.visualizerAccessibilityLabel' \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

require_pattern \
  "iOS audio visualizer uses shared bar count policy" \
  'VoiceInkAudioMeterLevel\.iOSVisualizerBarCount' \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

require_pattern \
  "iOS audio visualizer consumes shared geometry policy" \
  'VoiceInkAudioMeterLevel\.(iOSVisualizerBarSpacing|iOSVisualizerHorizontalPadding|iOSVisualizerFrameHeight|iOSVisualizerAnimationDuration|iOSVisualizerBarWidth|iOSVisualizerBarHeight)' \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

reject_pattern \
  "iOS audio visualizer avoids shell-only geometry constants and math" \
  'barSpacing: CGFloat = 3|duration: 0\.12|\.padding\(\.horizontal, 2\)|\.frame\(height: 48\)|size\.width - 16|max\(2,|size\.height - minHeight' \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

require_pattern \
  "iOS audio visualizer uses shared bar-height policy" \
  'VoiceInkAudioMeterLevel\.iOSVisualizerBarHeight' \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

reject_pattern \
  "iOS live recording avoids shell-only audio-meter history limit" \
  'VoiceInkAudioMeterLevel\.boundedHistory|levelsHistory\.count >|removeFirst\(self\.levelsHistory\.count -|0\.\.<40' \
  iOS/VoiceInk-ios/AudioRecorder.swift \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

reject_pattern \
  "platform recorders avoid shell-owned audio-meter normalization composition" \
  'VoiceInkAudioMeterLevel\.(normalizedLevel|smoothedLevel|boundedHistory)' \
  VoiceInk/Recorder.swift \
  iOS/VoiceInk-ios/AudioRecorder.swift

reject_pattern \
  "iOS audio visualizer avoids shell-owned sample selection policy" \
  'guard +!levels\.isEmpty|levels\.count / span|sourceIndex|max\(0, min\(1, levels\[sourceIndex\]\)\)' \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

reject_pattern \
  "macOS audio visualizer avoids shell-owned bar geometry and waveform math" \
  'private let barCount = 15|private let barWidth: CGFloat = 3|private let barSpacing: CGFloat = 2|private let minHeight: CGFloat = 4|private let maxHeight: CGFloat = 28|minimumInterval: 0\.016|pow\(audioMeter\.averagePower, 0\.7\)|sin\(time \* 8|phases\[index\]' \
  VoiceInk/Views/Recorder/AudioVisualizerView.swift

reject_pattern \
  "platform audio-meter timers avoid shell-only update cadences" \
  'withTimeInterval: +0\.1|repeating: +\.milliseconds\(17\)' \
  VoiceInk/Recorder.swift \
  iOS/VoiceInk-ios/AudioRecorder.swift

reject_pattern \
  "iOS audio visualizer avoids duplicate accessibility copy" \
  '"Audio level visualizer"' \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

require_pattern \
  "shared audio input priority policy lives in VoiceInkCore" \
  'VoiceInkAudioInputMode|VoiceInkAudioInputPriorityDevice|VoiceInkAudioInputAvailableDevice|VoiceInkAudioInputPriorityPolicy|VoiceInkAudioInputPriorityMoveDirection|firstAvailablePriorityDevice|firstAvailablePriorityDeviceID|VoiceInkAudioInputSelectionPolicy|VoiceInkAudioInputRecordingSwitchPlan|currentDeviceID|deviceIDToSelectWhenChangingMode|recordingSwitchPlan|reindexed|defaultMode|iconSystemName|VoiceInkAudioInputAutomaticSelectionPolicy|VoiceInkAudioInputAutomaticDevice|VoiceInkAudioInputAutomaticSelection|isSafeAutomaticDevice|builtInUIDMarker|unsafeAirPodsNameMarker' \
  VoiceInkCore/Sources/VoiceInkCore/AudioInputPriorityPolicy.swift

require_pattern \
  "shared audio input preference storage lives in VoiceInkCore" \
  'VoiceInkAudioInputPreference|inputModeKey = "audioInputMode"|selectedDeviceUIDKey = "selectedAudioDeviceUID"|prioritizedDevicesKey = "prioritizedDevices"|lastUsedMicrophoneDeviceIDKey = "lastUsedMicrophoneDeviceID"|saveInputMode|saveSelectedDeviceUID|savePrioritizedDevices|saveLastUsedMicrophoneDeviceID|shouldAnnounceMicrophoneChange' \
  VoiceInkCore/Sources/VoiceInkCore/AudioInputPriorityPolicy.swift

require_pattern \
  "shared macOS audio device change request lives in VoiceInkCore" \
  'VoiceInkMacOSAudioDeviceChangeRequest|deviceChangedNotificationName = Notification\.Name\("AudioDeviceChanged"\)|switchRequiredNotificationName = Notification\.Name\("audioDeviceSwitchRequired"\)|newDeviceIDUserInfoKey = "newDeviceID"|switchRequiredUserInfo|newDeviceID\(from notification: Notification\)' \
  VoiceInkCore/Sources/VoiceInkCore/AudioInputPriorityPolicy.swift

require_pattern \
  "shared macOS audio input settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSAudioInputSettingsPresentation|heroTitle|prioritizedDevicesDescription|priorityDisplayText' \
  VoiceInkCore/Sources/VoiceInkCore/AudioInputPriorityPolicy.swift

require_patterns \
  "core audio input automatic selection tests are in runner" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'testMacOSAudioDeviceChangeRequestPreservesNotificationContract' \
  'testAutomaticSelectionPolicyPreservesBuiltInDetection' \
  'testAutomaticSelectionPolicyRefusesUnsafeAutomaticDevices' \
  'testSelectionPolicyResolvesCurrentDeviceByMode' \
  'testSelectionPolicyPreservesModeChangeSelectionBehavior' \
  'testSelectionPolicyPlansRecordingDeviceSwitches'

require_pattern \
  "macOS audio device manager uses shared input mode" \
  'VoiceInkAudioInputMode|VoiceInkAudioInputPreference\.inputMode|VoiceInkAudioInputPreference\.saveInputMode' \
  VoiceInk/Services/AudioDeviceManager.swift

require_pattern \
  "macOS audio device manager uses shared input priority policy" \
  'VoiceInkAudioInputPriorityDevice|VoiceInkAudioInputPriorityPolicy\.(addDevice|removeDevice|reindexed|sortedDevices|firstAvailablePriorityDeviceID)' \
  VoiceInk/Services/AudioDeviceManager.swift

require_pattern \
  "macOS audio device manager uses shared automatic input selection policy" \
  'VoiceInkAudioInputAutomaticSelectionPolicy\.(selection|isBuiltInDevice)|VoiceInkAudioInputAutomaticDevice' \
  VoiceInk/Services/AudioDeviceManager.swift

require_pattern \
  "macOS audio device manager uses shared audio input selection policy" \
  'VoiceInkAudioInputSelectionPolicy\.(currentDeviceID|deviceIDToSelectWhenChangingMode|recordingSwitchPlan)|VoiceInkAudioInputAvailableDevice|firstAvailablePriorityDevice' \
  VoiceInk/Services/AudioDeviceManager.swift

require_pattern \
  "macOS audio device manager uses shared audio input preference storage" \
  'VoiceInkAudioInputPreference\.(selectedDeviceUID|saveSelectedDeviceUID|clearSelectedDeviceUID|prioritizedDevices|savePrioritizedDevices)' \
  VoiceInk/Services/AudioDeviceManager.swift

require_patterns \
  "macOS audio device manager uses shared audio device change request" \
  VoiceInk/Services/AudioDeviceManager.swift \
  'VoiceInkMacOSAudioDeviceChangeRequest\.switchRequiredUserInfo' \
  '\.audioDeviceChanged'

require_patterns \
  "macOS recorder uses shared audio device change request" \
  VoiceInk/Recorder.swift \
  'VoiceInkMacOSAudioDeviceChangeRequest\.newDeviceID' \
  '\.audioDeviceChanged'

require_patterns \
  "macOS app notifications use shared audio device change request names" \
  VoiceInk/Notifications/AppNotifications.swift \
  'audioDeviceSwitchRequired = VoiceInkMacOSAudioDeviceChangeRequest\.switchRequiredNotificationName' \
  'audioDeviceChanged = VoiceInkMacOSAudioDeviceChangeRequest\.deviceChangedNotificationName'

require_pattern \
  "macOS audio input settings uses shared mode and priority policy" \
  'VoiceInkAudioInputMode\.allCases|VoiceInkAudioInputPriorityPolicy\.(sortedDevices|moveDevice)|VoiceInkAudioInputPriorityDevice|mode\.(title|iconSystemName|description)|VoiceInkMacOSAudioInputSettingsPresentation\.macOS|presentation\.(heroTitle|activeStatusTitle|priorityDisplayText)' \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift

require_pattern \
  "macOS defaults register shared audio input defaults" \
  'VoiceInkAudioInputPreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS recorder uses shared last-used microphone preference" \
  'VoiceInkAudioInputPreference\.(shouldAnnounceMicrophoneChange|saveLastUsedMicrophoneDeviceID)' \
  VoiceInk/Recorder.swift

require_pattern \
  "shared preference reset clears last-used microphone state" \
  'VoiceInkAudioInputPreference\.clearLastUsedMicrophoneDeviceID' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

reject_pattern \
  "macOS audio input avoids shell-only mode and priority policy" \
  'enum +AudioInputMode|"(System Default|Custom Device|Prioritized|Use your Mac'\''s default input|Select a specific input device|Set up device priority order)"|return "(display|mic\.circle\.fill|list\.number)"|struct +PrioritizedDevice|prioritizedDevices\.sorted|sorted *\{ *\$0\.priority < \$1\.priority *\}|swapAt\(currentIndex|prioritizedDevices\.append|prioritizedDevices\.removeAll|map *\{ *\$0\.priority *\}\.max' \
  VoiceInk/Services/AudioDeviceManager.swift \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift

reject_pattern \
  "macOS audio input avoids shell-owned automatic selection policy" \
  'localizedCaseInsensitiveContains\("BuiltIn"\)|localizedCaseInsensitiveContains\("airpods"\)|private func isSafeAutomaticDevice' \
  VoiceInk/Services/AudioDeviceManager.swift

reject_pattern \
  "macOS audio device manager avoids shell-owned priority mode resolution" \
  'sortedDevices\(prioritizedDevices\)|availableDeviceUIDs|flatMap *\{ *priorityUID|let +newDeviceID: +AudioDeviceID\?|VoiceInkAudioInputPriorityPolicy\.firstAvailablePriorityDeviceID' \
  VoiceInk/Services/AudioDeviceManager.swift

reject_pattern \
  "macOS audio input avoids shell-owned storage keys" \
  'UserDefaultsKey|"(audioInputMode|selectedAudioDeviceUID|prioritizedDevices|lastUsedMicrophoneDeviceID)"|JSONDecoder\(\)\.decode\(\[VoiceInkAudioInputPriorityDevice\]|JSONEncoder\(\)\.encode\(prioritizedDevices\)' \
  VoiceInk/Services/AudioDeviceManager.swift \
  VoiceInk/Recorder.swift

reject_pattern \
  "macOS audio device shell avoids duplicate notification contracts" \
  '(NS)?Notification\.Name\("AudioDeviceChanged"\)|Notification\.Name\("audioDeviceSwitchRequired"\)|\["newDeviceID"\]|userInfo\["newDeviceID"\]' \
  VoiceInk/Services/AudioDeviceManager.swift \
  VoiceInk/Recorder.swift \
  VoiceInk/Notifications/AppNotifications.swift

reject_pattern \
  "macOS audio input settings avoid shell-only presentation copy" \
  '"(Audio Input|Configure your microphone preferences|Input Mode|Current Device|No device available|Active|Available Devices|Refresh|Prioritized Devices|Devices will be used in order of priority\. If a device is unavailable, the next one will be tried\. If no prioritized device is available, the built-in microphone will be used\.|No prioritized devices|No additional devices available|No Audio Devices|Connect an audio input device to get started|Unavailable)"|"waveform"|"wave\.3\.right"|"arrow\.clockwise"|"mic\.slash\.circle\.fill"|"exclamationmark\.triangle"|"plus\.circle\.fill"|"minus\.circle\.fill"|"chevron\.up"|"chevron\.down"|Text\("-"\)|Text\("\\\(\(priority \+ 1\)\\\)"\)' \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift

require_pattern \
  "migration checklist tracks shared audio input preference gate" \
  'macOS audio-input storage keys, selected-device UID persistence, last-used microphone notification suppression, priority-device JSON storage, audio-device change/switch notification contract, settings labels, status copy, empty states, action icons, priority display text, current-device and mode-change selection planning, recording-device switch planning, and safe automatic input selection route through `VoiceInkAudioInputPreference`/`VoiceInkMacOSAudioDeviceChangeRequest`/`VoiceInkMacOSAudioInputSettingsPresentation`/`VoiceInkAudioInputSelectionPolicy`/`VoiceInkAudioInputAutomaticSelectionPolicy`' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "iOS note views avoid shell-only transcript presentation wrappers" \
  'private var +(transcriptText|statusBadgeText|relativeTimestamp|displayedTranscriptText|transcriptionStatusTitle) *:' \
  iOS/VoiceInk-ios/NoteRowView.swift \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "shared date presentation owns macOS detail timestamp format" \
  'abbreviatedTimestamp' \
  VoiceInkCore/Sources/VoiceInkCore/DurationPresentation.swift

require_pattern \
  "shared date presentation owns macOS history timestamp format" \
  'compactTimestamp' \
  VoiceInkCore/Sources/VoiceInkCore/DurationPresentation.swift

section "obsolete standalone date presentation module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/DatePresentation.swift

require_pattern \
  "shared date and duration presentation live together" \
  'VoiceInkDatePresentation|VoiceInkDurationPresentation|relativeTimestamp|minutesSeconds' \
  VoiceInkCore/Sources/VoiceInkCore/DurationPresentation.swift

require_pattern \
  "macOS transcription details use shared timestamp presentation" \
  'VoiceInkDatePresentation\.abbreviatedTimestamp' \
  VoiceInk/Views/Common/TranscriptionInfoPanel.swift

require_pattern \
  "macOS history rows use shared timestamp presentation" \
  'VoiceInkDatePresentation\.compactTimestamp' \
  VoiceInk/Views/History/TranscriptionListItem.swift

require_pattern \
  "macOS inline history rows use shared timestamp presentation" \
  'VoiceInkDatePresentation\.compactTimestamp' \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS transcript timestamp views avoid shell-owned date formats" \
  'format: \.dateTime\.month\(\.abbreviated\)\.day\(\)\.hour\(\)\.minute\(\)|formatted\(date: \.abbreviated, time: \.shortened\)' \
  VoiceInk/Views/Common/TranscriptionInfoPanel.swift \
  VoiceInk/Views/History/TranscriptionListItem.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "shared transcription metadata presentation policy lives in VoiceInkCore" \
  'VoiceInkTranscriptionMetadataPresentation|VoiceInkTranscriptionMetadataRowPresentation|fullAIRequestText|shouldShowAIRequestSection' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcription metadata presentation owns macOS detail rows" \
  'dateRow|durationRow|transcriptionModelRow|transcriptionTimeRow|enhancementModelRow|enhancementTimeRow|promptRow|powerModeRow' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcription metadata presentation owns AI request copy" \
  'detailsSectionTitle = "Details"|aiRequestSectionTitle = "AI Request"|systemPromptLabel = "System Prompt"|userMessageLabel = "User Message"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "macOS transcription details use shared metadata presentation" \
  'VoiceInkTranscriptionMetadataPresentation\.(dateRow|durationRow|transcriptionModelRow|transcriptionTimeRow|enhancementModelRow|enhancementTimeRow|promptRow|powerModeRow|detailsSectionTitle|aiRequestSectionTitle|systemPromptLabel|userMessageLabel|fullAIRequestText|shouldShowAIRequestSection)' \
  VoiceInk/Views/Common/TranscriptionInfoPanel.swift

require_pattern \
  "core tests pin transcription metadata presentation copy" \
  'testTranscriptionMetadataPresentationPreservesMacOSDetailRows|testFullAIRequestTextPreservesMacOSCopyComposition' \
  VoiceInkCore/Tests/VoiceInkCoreTests/TranscriptPresentationTests.swift

require_pattern \
  "core check runner executes transcription metadata presentation tests" \
  'testTranscriptionMetadataPresentationPreservesMacOSDetailRows|testFullAIRequestTextPreservesMacOSCopyComposition' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS transcription details avoid shell-owned metadata copy and icons" \
  '"(Date|Duration|Transcription Model|Transcription Time|Enhancement Model|Enhancement Time|Prompt|Power Mode|Details|AI Request|System Prompt|User Message|calendar|hourglass|cpu\.fill|clock\.fill|sparkles|text\.bubble\.fill|bolt\.fill)"|System Prompt:\\n|User Message:\\n' \
  VoiceInk/Views/Common/TranscriptionInfoPanel.swift

require_pattern \
  "shared transcript status presentation policy lives in VoiceInkCore" \
  'VoiceInkTranscriptStatusPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcript status metadata lives in VoiceInkCore" \
  'panelSystemImageName|inlineAccessory|Tone' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcript status panel visibility lives in VoiceInkCore" \
  'shouldShowStatusPanel' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared completed transcript content visibility lives in VoiceInkCore" \
  'shouldShowCompletedContent' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcript text variant presentation lives in VoiceInkCore" \
  'VoiceInkTranscriptTextVariant|case original|case enhanced|var title|shouldShowTabs|displayText' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcript action text policy lives in VoiceInkCore" \
  'transcriptActionText' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcript delete-confirmation copy lives in VoiceInkCore" \
  'deleteConfirmationMessage' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcript deletion target selection lives in VoiceInkCore" \
  'deletionTargets.*atOffsets' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "core tests pin transcript deletion target selection" \
  'testDeletionTargetsUseDisplayedListOffsets|testDeletionTargetsIgnoreStaleOffsets' \
  VoiceInkCore/Tests/VoiceInkCoreTests/TranscriptPresentationTests.swift

require_pattern \
  "core check runner executes transcript deletion target tests" \
  'testDeletionTargetsUseDisplayedListOffsets|testDeletionTargetsIgnoreStaleOffsets' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared transcript detail presentation copy lives in VoiceInkCore" \
  'noteDetailNavigationTitle|transcriptTitle|copyTranscriptSystemImageName|retranscribingDisplayText|retryTranscriptionButtonTitle|retryTranscriptionSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_patterns \
  "shared transcript action control presentation lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift \
  'actionSucceededSystemImageName = "checkmark"' \
  'copyToClipboardHelp = "Copy to clipboard"' \
  'saveTranscriptSystemImageName = "square\.and\.arrow\.down"' \
  'saveTranscriptAsPlainTextButtonTitle = "Save as TXT"' \
  'saveTranscriptAsMarkdownButtonTitle = "Save as MD"' \
  'saveTranscriptHelp = "Save to file"' \
  'saveTranscriptPanelTitle = "Save Transcription"' \
  'saveTranscriptFailureConsolePrefix = "Failed to save file:"'

require_pattern \
  "shared transcript retry controls presentation lives in VoiceInkCore" \
  'VoiceInkTranscriptRetryControlsPresentation|VoiceInkTranscriptRetryControlAction|retryControls\(isRetranscribing:' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcript status error detail visibility lives in VoiceInkCore" \
  'statusErrorDetail' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "core checks execute transcript retry controls presentation tests" \
  'testRetryControlsPresentationShows(RetryControlsWhenIdle|ProgressWhenRetranscribing)|testStatusErrorDetailShowsOnlyNonEmptyErrors' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute transcript action control presentation test" \
  'testTranscriptActionControlPresentationPreservesMacOSCopyAndSaveCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute transcript export file extension test" \
  'testTranscriptFileExportPreservesMacOSFileExtensions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared last-transcription notification copy lives in VoiceInkCore" \
  'noTranscriptionAvailableTitle|lastTranscriptionCopiedTitle|failedToCopyTranscriptionTitle|cannotRetryTitle|retryFailedTitle' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_file \
  VoiceInkCore/Sources/VoiceInkCore/LastTranscriptionPolicy.swift

require_patterns \
  "shared last-transcription policy lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/LastTranscriptionPolicy.swift \
  'VoiceInkLastTranscriptionPolicy' \
  'firstPasteableCandidate' \
  'VoiceInkLastTranscriptionTextPreference' \
  'VoiceInkLastTranscriptionNotificationPresentation' \
  'VoiceInkLastTranscriptionRetryPreflightFailure' \
  'fetchFailedDiagnosticMessage' \
  'noTranscriptionNotification' \
  'copyCompletionNotification' \
  'retryPreflightFailureNotification' \
  'retrySuccessNotification' \
  'retryFailureNotification'

require_patterns \
  "core tests pin last-transcription policy" \
  VoiceInkCore/Tests/VoiceInkCoreTests/LastTranscriptionPolicyTests.swift \
  'testFirstPasteableCandidateSkipsExcludedPendingBlankAndCanceledCandidates' \
  'testPasteTextUsesOriginalOrEnhancedFallbackPolicy' \
  'testFetchLimitPreservesMacOSLastTranscriptionFetchWindow' \
  'testFetchFailureDiagnosticPreservesMacOSCopy' \
  'testLastTranscriptionNotificationPresentationsPreserveCopyOutcomes' \
  'testLastTranscriptionRetryNotificationPresentationsPreserveMacOSCopy'

require_patterns \
  "core check runner executes last-transcription policy tests" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'LastTranscriptionPolicyTests\.testFirstPasteableCandidateSkipsExcludedPendingBlankAndCanceledCandidates' \
  'LastTranscriptionPolicyTests\.testPasteTextUsesOriginalOrEnhancedFallbackPolicy' \
  'LastTranscriptionPolicyTests\.testFetchLimitPreservesMacOSLastTranscriptionFetchWindow' \
  'LastTranscriptionPolicyTests\.testFetchFailureDiagnosticPreservesMacOSCopy' \
  'LastTranscriptionPolicyTests\.testLastTranscriptionNotificationPresentationsPreserveCopyOutcomes' \
  'LastTranscriptionPolicyTests\.testLastTranscriptionRetryNotificationPresentationsPreserveMacOSCopy'

require_pattern \
  "iOS note row uses shared transcript status presentation" \
  'VoiceInkTranscriptPresentation\.statusPresentation' \
  iOS/VoiceInk-ios/NoteRowView.swift

reject_pattern \
  "iOS note row avoids shallow status presentation wrapper" \
  'private var +statusPresentation\b' \
  iOS/VoiceInk-ios/NoteRowView.swift

require_pattern \
  "iOS note row uses shared transcript status metadata" \
  'inlineAccessory|\.tone' \
  iOS/VoiceInk-ios/NoteRowView.swift

require_pattern \
  "iOS note detail uses shared transcript status presentation" \
  'VoiceInkTranscriptPresentation\.statusPresentation' \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_pattern \
  "iOS note detail avoids shallow status presentation wrapper" \
  'private var +statusPresentation\b' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS note detail uses shared transcript status metadata" \
  'panelSystemImageName|\.tone' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS transcript status tone colors live in one shell adapter" \
  'extension VoiceInkTranscriptStatusPresentation\.Tone|statusColor|badgeColor|badgeBackgroundColor' \
  iOS/VoiceInk-ios/TranscriptStatusTone+iOS.swift

reject_pattern \
  "iOS note views avoid duplicate transcript status tone color adapters" \
  'extension VoiceInkTranscriptStatusPresentation\.Tone|var +(statusColor|badgeColor|badgeBackgroundColor): Color' \
  iOS/VoiceInk-ios/NoteRowView.swift \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS note detail uses shared status panel visibility" \
  'VoiceInkTranscriptPresentation\.shouldShowStatusPanel' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS note detail uses shared completed transcript visibility" \
  'VoiceInkTranscriptPresentation\.shouldShowCompletedContent' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS note detail uses shared transcript detail presentation copy" \
  'VoiceInkTranscriptPresentation\.(noteDetailNavigationTitle|transcriptTitle|copyTranscriptSystemImageName|retranscribingDisplayText|retryTranscriptionButtonTitle|retryTranscriptionSystemImageName)' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS note detail delegates retry control presentation to shared core" \
  'VoiceInkTranscriptPresentation\.retryControls' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS note detail delegates status error visibility to shared core" \
  'VoiceInkTranscriptPresentation\.statusErrorDetail' \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_pattern \
  "iOS note detail avoids shell-owned retry control branching" \
  'if +!?isRetranscribing' \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_pattern \
  "iOS note detail avoids shell-owned empty status error filtering" \
  'note\.transcriptionError, +!error\.isEmpty' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "macOS transcription detail uses shared transcript text variant" \
  'VoiceInkTranscriptTextVariant\.(original|enhanced)\.(title|displayText)|VoiceInkTranscriptTextVariant\.shouldShowTabs' \
  VoiceInk/Views/History/TranscriptionDetailView.swift

require_pattern \
  "macOS audio file row uses shared transcript text variant" \
  'VoiceInkTranscriptTextVariant|tab\.title|selectedTab\.displayText|VoiceInkTranscriptTextVariant\.shouldShowTabs' \
  VoiceInk/Views/AudioFileRow.swift

require_pattern \
  "macOS audio file row uses shared transcript action text policy" \
  'VoiceInkTranscriptPresentation\.transcriptActionText' \
  VoiceInk/Views/AudioFileRow.swift

require_pattern \
  "macOS inline history uses shared transcript text variant" \
  'VoiceInkTranscriptTextVariant|tab\.title|selectedTab\.displayText|VoiceInkTranscriptTextVariant\.shouldShowTabs' \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history delete confirmation uses shared transcript presentation" \
  'VoiceInkTranscriptPresentation\.deleteConfirmationMessage' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "iOS note list uses shared deletion target selection" \
  'VoiceInkTranscriptPresentation\.deletionTargets\(atOffsets: offsets, from: filteredNotes\)' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "shared history empty-state presentation lives in VoiceInkCore" \
  'public struct VoiceInkHistoryEmptyStatePresentation' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history empty-state presentation owns iOS notes state" \
  'iOSNotesEmptyState' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history empty-state presentation owns iOS notes title" \
  'title: "No notes yet"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history empty-state presentation owns iOS notes message" \
  'message: "Tap Start Recording to capture your first note\."' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history empty-state presentation owns macOS inline search policy" \
  'macOSInlineHistoryEmptyState' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history empty-state presentation owns macOS inline empty title" \
  'title: "No transcriptions yet"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history empty-state presentation owns macOS inline search title" \
  'title: "No results found"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "iOS note list uses shared history empty-state presentation" \
  'VoiceInkHistoryPresentation\.iOSNotesEmptyState' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "macOS full history uses shared history empty-state presentation" \
  'VoiceInkHistoryPresentation\.macOSHistoryListEmptyState' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift

require_pattern \
  "macOS full history uses shared no-selection presentation" \
  'VoiceInkHistoryPresentation\.macOSNoSelectionEmptyState' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift

require_pattern \
  "macOS full history uses shared no-metadata presentation" \
  'VoiceInkHistoryPresentation\.macOSNoMetadataEmptyState' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift

require_pattern \
  "macOS inline history uses shared history empty-state presentation" \
  'VoiceInkHistoryPresentation\.macOSInlineHistoryEmptyState' \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "shared history presentation owns macOS search prompts" \
  'macOSHistorySearchPrompt|macOSInlineHistorySearchPrompt' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history presentation owns macOS paging labels" \
  'loadingOrLoadMoreText|loadingText = "Loading\.\.\."|loadMoreButtonTitle = "Load More"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history presentation owns macOS selection labels" \
  'selectAllButtonTitle = "Select All"|deselectAllButtonTitle = "Deselect All"|selectedCountText' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history presentation owns macOS selection action metadata" \
  'analyzeAction|exportAction|deleteAction|chart\.bar\.xaxis|square\.and\.arrow\.up|systemImageName: "trash"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_patterns \
  "shared history presentation owns macOS shortcut tip copy and icon" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift \
  'VoiceInkHistoryShortcutTipPresentation' \
  'macOSShortcutTip' \
  'title: "Quick Access"' \
  'subtitle: "Open history from anywhere with a global shortcut"' \
  'shortcutLabel: "Open History Window"' \
  'systemImageName: "command\.circle"'

require_pattern \
  "shared history presentation owns macOS delete alert copy" \
  'deleteConfirmationTitle = "Delete Selected Items\?"|deleteConfirmationPrimaryButtonTitle = "Delete"|deleteConfirmationCancelButtonTitle = "Cancel"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared history diagnostics own macOS console copy" \
  'VoiceInkHistoryDiagnostics|initialLoadFailedMessage|loadMoreFailedMessage|saveDeletionFailedMessage|selectAllFailedMessage' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "core checks execute history diagnostic copy test" \
  'TranscriptPresentationTests\.testHistoryDiagnosticsPreserveMacOSConsoleCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute history shortcut tip presentation test" \
  'TranscriptPresentationTests\.testHistoryShortcutTipPresentationPreservesMacOSCopyAndIcon' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS full history uses shared history search prompt" \
  'VoiceInkHistoryPresentation\.macOSHistorySearchPrompt' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift

require_pattern \
  "macOS inline history uses shared history search prompt" \
  'VoiceInkHistoryPresentation\.macOSInlineHistorySearchPrompt' \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared paging labels" \
  'VoiceInkHistoryPresentation\.loadingOrLoadMoreText' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared selected-count text" \
  'VoiceInkHistoryPresentation\.selectedCountText' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared selection labels" \
  'VoiceInkHistoryPresentation\.(selectAllButtonTitle|deselectAllButtonTitle)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared action metadata" \
  'VoiceInkHistoryPresentation\.(analyzeAction|exportAction|deleteAction)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_patterns \
  "macOS history shortcut tip uses shared presentation" \
  VoiceInk/Views/History/HistoryShortcutTipView.swift \
  'VoiceInkHistoryPresentation\.macOSShortcutTip\.systemImageName' \
  'VoiceInkHistoryPresentation\.macOSShortcutTip\.title' \
  'VoiceInkHistoryPresentation\.macOSShortcutTip\.subtitle' \
  'VoiceInkHistoryPresentation\.macOSShortcutTip\.shortcutLabel'

require_pattern \
  "macOS shortcut action display name uses shared action presentation" \
  'VoiceInkShortcutActionPresentation\.displayName' \
  VoiceInk/Shortcuts/ShortcutAction.swift

require_pattern \
  "macOS history views use shared delete alert copy" \
  'VoiceInkHistoryPresentation\.deleteConfirmation(Title|PrimaryButtonTitle|CancelButtonTitle)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared history diagnostics" \
  'VoiceInkHistoryDiagnostics\.(initialLoadFailedMessage|loadMoreFailedMessage|saveDeletionFailedMessage|selectAllFailedMessage)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history query adapter owns latest indicator descriptor" \
  'latestIndicatorDescriptor' \
  VoiceInk/Views/History/TranscriptionHistoryQuery.swift

require_pattern \
  "macOS history query adapter owns cursor descriptor" \
  'cursorDescriptor' \
  VoiceInk/Views/History/TranscriptionHistoryQuery.swift

require_pattern \
  "macOS history query adapter owns select-all descriptor" \
  'selectionDescriptor' \
  VoiceInk/Views/History/TranscriptionHistoryQuery.swift

require_pattern \
  "macOS history query adapter owns SwiftData search predicate" \
  'localizedStandardContains\(searchText\)' \
  VoiceInk/Views/History/TranscriptionHistoryQuery.swift

require_pattern \
  "macOS history views delegate SwiftData query construction" \
  'TranscriptionHistoryQuery\.(latestIndicatorDescriptor|cursorDescriptor|selectionDescriptor)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared pagination state policy" \
  'VoiceInkHistoryPaginationPolicy\.(initialPage|appendingPage|reset|loadMoreCursor)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared selection state policy" \
  'VoiceInkHistorySelectionPolicy\.(areAllDisplayedItemsSelected|toggling|selectingAll)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared deletion state policy" \
  'VoiceInkHistoryDeletionPolicy\.selectedItemsDeletionPlan' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS history views use shared refresh policy" \
  'VoiceInkHistoryRefreshPolicy\.(searchTextDidChange|latestItemDidChange)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "history and notes views avoid shell-only empty-state copy" \
  'No notes yet|Tap Start Recording to capture your first note\.|No transcriptions yet|No transcriptions|No results found|Your transcription history will appear here|Try a different search term|No Selection|Select a transcription to view details|No Metadata' \
  iOS/VoiceInk-ios/NotesListView.swift \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS history views avoid shell-only history control copy" \
  '"(Search transcriptions|Search transcriptions\.\.\.|Loading\.\.\.|Load More|Select All|Deselect All|Analyze|Export|Delete|Cancel|Delete Selected Items\?)"' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS history shortcut tip avoids shell-owned presentation copy and icon" \
  '"(Quick Access|Open history from anywhere with a global shortcut|Open History Window|command\.circle)"' \
  VoiceInk/Views/History/HistoryShortcutTipView.swift

reject_pattern \
  "macOS shortcut action avoids duplicate history shortcut display name" \
  '"Open History Window"' \
  VoiceInk/Shortcuts/ShortcutAction.swift

require_pattern \
  "migration checklist tracks shared history shortcut tip presentation" \
  'macOS history shortcut-tip copy/icon.*VoiceInkHistoryPresentation' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS history views avoid shell-owned console diagnostics" \
  'Error (loading transcriptions|loading more transcriptions|saving deletion|selecting all transcriptions)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS history views avoid duplicate delete-confirmation pluralization copy" \
  'This action cannot be undone\. Are you sure you want to delete|selectedTranscriptions\.count == 1 \? "" : "s"' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS history views avoid duplicate SwiftData search predicate construction" \
  '#Predicate<Transcription>|localizedStandardContains\(searchText\)' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS history views avoid duplicate pagination state math" \
  'displayedTranscriptions\.append\(contentsOf:|items\.last\?\.timestamp|newItems\.last\?\.timestamp|items\.count == pageSize|newItems\.count == pageSize' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS history views avoid duplicate selection state math" \
  'if selectedTranscriptions\.contains\(transcription\)|Set\(displayedTranscriptions\.map|visibleIds' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS history views avoid duplicate deletion focus and selection state repair" \
  'for transcription in selectedTranscriptions|selectedTranscriptions\.remove\(transcription\)|if selectedTranscription == transcription|if expandedId == transcription\.id|if panelTranscriptionId == transcription\.id' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "macOS history views avoid duplicate refresh visibility and latest-id policy" \
  'guard isViewCurrentlyVisible|newId != oldId|oldId != newId|newId == oldId|oldId == newId' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "iOS note list avoids shell-owned filtered deletion indexing" \
  'filteredNotes\[index\]' \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "macOS audio file row avoids shell-owned transcript action text policy" \
  'return displayText|guard let transcription = item\.transcription' \
  VoiceInk/Views/AudioFileRow.swift

reject_pattern \
  "macOS transcript variant views avoid shell-owned variant selection rules" \
  'switch selectedTab|case \.(original|enhanced):|enhancedText != nil' \
  VoiceInk/Views/AudioFileRow.swift \
  VoiceInk/Views/History/InlineHistoryView.swift \
  VoiceInk/Views/History/TranscriptionDetailView.swift

reject_pattern \
  "iOS note views avoid shell-only transcript status branching" \
  'note\.transcriptionStatus *[!=]= *\.(pending|failed|completed|canceled)|transcriptionStatus\.needsTranscription|VoiceInkTranscriptPresentation\.status(Title|BadgeText)|statusPresentation\??\.(is(Failure|Processing)|shouldShow(InlineProgress|Badge))' \
  iOS/VoiceInk-ios/NoteRowView.swift \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_file VoiceInk/Views/TranscriptionResultView.swift

reject_pattern \
  "transcript detail views avoid shell-only presentation copy" \
  '"(Note|Transcript|Retranscribing\.\.\.|Retry Transcription|Original|Enhanced)"' \
  iOS/VoiceInk-ios/NoteDetailView.swift \
  VoiceInk/Views/History/TranscriptionDetailView.swift \
  VoiceInk/Views/AudioFileRow.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "iOS note detail avoids duplicate action and unavailable icon names" \
  '"(doc\.on\.doc|arrow\.clockwise|exclamationmark)"' \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_pattern \
  "iOS API-key view avoids shell-only stored-key presentation wrappers" \
  'private func +(currentAPIKey|obfuscatedKey)\(' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shell-only verifier pass-through wrappers" \
  'private func +verifiedAPIKey\(' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shallow shared-form pass-through properties" \
  'private var +(hasEnteredAPIKey|canVerifyAPIKey|formPresentation)\b' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shallow key-state pass-through properties" \
  'private var +(isKeyVerified|apiKeyDraft)\b' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS API-key view delegates verification persistence to settings adapter" \
  'settings\.applyAPIKeyVerificationPlan\(plan, for: provider\)' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shell-owned verification persistence sequencing" \
  'plan\.shouldMarkKeyVerified|plan\.keyToSave|settings\.setKeyVerified\(true' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "shared provider API-key verification progress presentation lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyVerificationProgress|macOSVerifyButtonTitle|iOSResultFeedback|effectiveSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key verification application plan lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyVerificationApplicationPlan|verificationApplicationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key verification persistence plan lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyVerificationPersistencePlan|successPersistencePlan' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key verification persistence action plan lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyVerificationPersistenceAction|VoiceInkProviderAPIKeyVerificationPersistenceApplicationPlan|successPersistenceApplicationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key form state lives in VoiceInkCore" \
  'struct +VoiceInkProviderAPIKeyFormState' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key form state owns editing transitions" \
  'editingStoredKey|applyingVerificationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key form state owns iOS stored-key edit plan" \
  'VoiceInkProviderAPIKeyEditPlan|iOSStoredKeyEditPlan\(storedKey:|verificationFlagToPersist' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key form state owns iOS result feedback visibility" \
  'iOSVisibleResultFeedback\(isKeyVerified:' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key form state owns iOS control presentation" \
  'VoiceInkProviderAPIKeyFormControlPresentation|VoiceInkProviderAPIKeyVerificationControl|iOSControlPresentation\(storedRuntimeKey:' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key verification start plan lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyVerificationStartPlan|verificationStartPlan|VoiceInkProviderAPIKeyMissingVerificationCandidatePolicy' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "core checks execute provider API-key verification start plan tests" \
  'ProviderAccessRequirementTests\.testProviderAPIKeyVerificationStartPlan(BeginsWhenCandidateExists|CanKeepStateForMissingCandidate|CanApplyFailureForMissingCandidate)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute provider API-key verification persistence plan test" \
  'ProviderAccessRequirementTests\.testProviderAPIKeyVerificationApplicationPlanBuildsSuccessPersistencePlan' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute provider API-key verification persistence action plan test" \
  'ProviderAccessRequirementTests\.testProviderAPIKeyVerificationApplicationPlanBuildsOrderedPersistenceActions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute provider API-key iOS feedback visibility test" \
  'ProviderAccessRequirementTests\.testProviderAPIKeyFormStateOwnsIOSResultFeedbackVisibility' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute provider API-key iOS edit plan test" \
  'ProviderAccessRequirementTests\.testProviderAPIKeyFormStateEditPlanOwnsIOSVerificationReset' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute provider API-key iOS control presentation test" \
  'ProviderAccessRequirementTests\.testProviderAPIKeyFormStateOwnsIOSControlPresentation' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared provider API-key form presentation lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyFormPresentation|apiKeyFormPresentation|saveButtonSystemImageName|verifyButtonSystemImageName|consoleLeadingSystemImageName|consoleTrailingSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "iOS API-key view uses shared API-key form state" \
  'VoiceInkProviderAPIKeyFormState|apiKeyFormState' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS API-key view uses shared stored-key edit plan" \
  'iOSStoredKeyEditPlan|editPlan\.formState|editPlan\.verificationFlagToPersist' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS API-key view uses shared progress presentation through form state" \
  'apiKeyFormState\.(iOSControlPresentation|iOSVisibleResultFeedback)|iOSVerifiedKeyFeedback|iOSResultFeedback|effectiveSystemImageName' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shell-owned result feedback visibility gate" \
  'iOSResultFeedback.*isKeyVerified|isKeyVerified.*iOSResultFeedback' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shell-owned API-key control derivation" \
  'let +apiKeyDraft|apiKeyDraft\.|verificationProgress\.isVerifying|!apiKeyDraft\.(hasEnteredKey|canVerify)' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shell-owned stored-key edit sequencing" \
  'apiKeyFormState = apiKeyFormState\.editingStoredKey|setKeyVerified\(false' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS API-key view uses shared verification application plan" \
  'verificationApplicationPlan|VoiceInkProviderAPIKeyDraft[[:space:]]*\.[[:space:]]*missingVerificationCandidatePlan' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS API-key view uses shared verification start plan" \
  'verificationStartPlan|missingCandidatePolicy: \.applyFailurePlan' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS API-key view uses shared form presentation" \
  'apiKeyFormPresentation|VoiceInkProviderAPIKeyFormPresentation|saveButtonSystemImageName|verifyButtonSystemImageName|consoleLeadingSystemImageName|consoleTrailingSystemImageName' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS provider API-key tone colors live in one shell adapter" \
  'extension VoiceInkProviderAPIKeyListRowTone|extension VoiceInkProviderAPIKeyVerificationTone|statusColor' \
  iOS/VoiceInk-ios/ProviderAPIKeyTone+iOS.swift

reject_pattern \
  "iOS API-key views avoid duplicate tone color adapters" \
  'extension VoiceInkProviderAPIKeyListRowTone|func +color\(for tone: VoiceInkProviderAPIKeyVerificationTone\)|var +statusColor: Color' \
  iOS/VoiceInk-ios/APIKeysView.swift \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "shared API-key obfuscation fallback lives in VoiceInkCore" \
  'obfuscatedAPIKeyOrPlaceholder|obfuscatedAPIKeyPlaceholder' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

section "obsolete standalone secret presentation module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/SecretPresentation.swift

require_pattern \
  "shared secret presentation lives with provider-key form policy" \
  'VoiceInkSecretPresentation|obfuscatedAPIKey|obfuscatedAPIKeyOrPlaceholder' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key list row presentation lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyListRow|VoiceInkProviderAPIKeyListRowPresentation|listRows|listRowPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyState.swift

require_pattern \
  "shared provider API-key state loader lives in VoiceInkCore" \
  'loadingStoredKeys' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyState.swift

require_pattern \
  "shared provider API-key state mutation plans live in VoiceInkCore" \
  'VoiceInkProviderAPIKeyStorageMutationPlan|VoiceInkProviderAPIKeyVerificationMutationPlan|VoiceInkProviderAPIKeyStatePersistenceAction|applyStoredAPIKey|applyVerification|persistenceActions|verificationFlagToPersist|shouldPersistVerificationFlag' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyState.swift

require_pattern \
  "core checks execute provider API-key state persistence action tests" \
  'ProviderAccessRequirementTests\.testProviderAPIKeyState(Storage|Verification)MutationPlanBuildsPersistenceActions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared provider API-key storage lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyStorage|storedKey\(|saveStoredKey|deleteStoredKey|shouldReportFailure|VoiceInkProviderAPIKeyStorageDiagnostics|saveFailureMessage' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyStorage.swift

require_pattern \
  "iOS app settings consumes shared startup provider API-key state" \
  'startupState\.apiKeyState' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS app settings applies shared provider API-key mutation plans" \
  'applyStoredAPIKey|applyVerification|applyAPIKeyVerificationPlan|successPersistenceApplicationPlan|persistenceActions|applyProviderAPIKeyStatePersistenceActions' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS app settings avoids shell-owned provider verification success interpretation" \
  'plan\.shouldMarkKeyVerified|plan\.keyToSave|setKeyVerified\(true' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS app settings avoids shell-owned provider verification persistence field reads" \
  'persistencePlan\.keyToSave|persistencePlan\.verificationFlagToPersist' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS app settings avoids shell-owned provider API-key state mutation field reads" \
  'plan\.shouldPersistStoredKey|plan\.verificationFlagToPersist|plan\.shouldPersistVerificationFlag' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS app settings delegates provider API-key storage to shared core" \
  'VoiceInkProviderAPIKeyStorage\.(storedKey|saveStoredKey|deleteStoredKey)' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS app settings adapts shared provider API-key storage diagnostics" \
  'VoiceInkProviderAPIKeyStorageDiagnostics\.saveFailureMessage' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS app settings avoids shell-owned provider API-key state loading loop" \
  'uniqueKeysWithValues|userAPIKeyProviders\.map|storedKeysByProvider:' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS app settings avoids shell-owned provider API-key mutation decisions" \
  'didResetVerification|setStoredAPIKey|guard +updatedState\.setVerified|provider\.requiresUserAPIKey else' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS app settings avoids direct provider API-key account and Keychain storage mapping" \
  'provider\.apiKeyAccount|VoiceInkKeychainValueStore\.(saveString|loadString|deleteValue)' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS app settings uses shared provider API-key list rows" \
  'listRows' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS API-key list uses shared row list" \
  'apiKeyListRows' \
  iOS/VoiceInk-ios/APIKeysView.swift

reject_pattern \
  "iOS API-key list avoids shell-owned provider list and row presentation" \
  'VoiceInkProviderKind\.userAPIKeyProviders|apiKeyListRowPresentation' \
  iOS/VoiceInk-ios/APIKeysView.swift \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "shared Keychain query and data-store policy lives in VoiceInkCore" \
  'VoiceInkKeychainQuery|VoiceInkKeychainDataStore|VoiceInkKeychainValueStore|SecItem(Add|CopyMatching|Delete)' \
  VoiceInkCore/Sources/VoiceInkCore/KeychainQuery.swift

require_pattern \
  "shared Keychain string value policy lives in VoiceInkCore" \
  'VoiceInkKeychainValueStore|VoiceInkKeychainStringLoadResult|data\(forString:|string\(from:|isSuccessfulDeleteStatus' \
  VoiceInkCore/Sources/VoiceInkCore/KeychainQuery.swift

require_pattern \
  "macOS Keychain adapter uses shared data-store policy" \
  'VoiceInkKeychainDataStore\.(saveData|loadData|delete|exists)' \
  VoiceInk/Services/KeychainService.swift

require_pattern \
  "macOS Keychain adapter uses shared string value policy" \
  'VoiceInkKeychainValueStore\.(data\(forString:|saveString|loadString|deleteValue|isSuccessfulDeleteStatus|string\(from:)' \
  VoiceInk/Services/KeychainService.swift

require_pattern \
  "shared provider API-key storage uses shared string value policy" \
  'VoiceInkKeychainValueStore\.(saveString|loadString|deleteValue)' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyStorage.swift

require_pattern \
  "core checks execute provider API-key storage tests" \
  'ProviderAPIKeyStorageTests\.test(AccountUsesSharedProviderAccessRequirement|StoredKeyLoadsThroughProviderAccountAndDefaultsToEmpty|SaveStoredKeyTargetsProviderAccountAndReportsFailureStatus|ProviderAPIKeyStorageDiagnosticsPreserveIOSLogCopy)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "iOS app settings avoids shell-owned provider API-key storage diagnostic copy" \
  '"Error saving API key to keychain:' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS API-key settings avoid account-string keychain wrapper helpers" \
  'private +(static +)?func +(saveAPIKey|loadAPIKey)\([^)]*forKey' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "platform API-key string adapters avoid shell-owned UTF-8 storage policy" \
  'data\(using: +\.utf8\)|String\(data:.*encoding: +\.utf8\)' \
  VoiceInk/Services/KeychainService.swift \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "platform Keychain adapters avoid duplicate service and syncability query policy" \
  'kSecAttrService|kSecAttrSynchronizable|kSecUseDataProtectionKeychain|com\.prakashjoshipax\.VoiceInk' \
  VoiceInk/Services/KeychainService.swift \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "platform Keychain shells avoid shell-owned query shape and SecItem execution" \
  'VoiceInkKeychainQuery\.|SecItem(Add|CopyMatching|Delete)' \
  VoiceInk/Services/KeychainService.swift \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS API-key view avoids shell-only verification state and copy" \
  '@State private var isVerifying|verifyResult|Key verified|Verification failed|keyToSaveAfterSuccessfulVerification|verificationProgress = ok \?|result\.isValid' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shell-owned verification start branching" \
  'apiKeyFormState = apiKeyFormState\.verifying\(\)|VoiceInkProviderAPIKeyDraft[[:space:]]*\.[[:space:]]*missingVerificationCandidatePlan' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shell-owned API-key form state machine fields" \
  '@State private var +(tempKey|verificationProgress|editingKey)' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids shell-only form presentation copy" \
  '"([^"]*API Key[^"]*|[^"]*API Console[^"]*|Save|Verify|Change)"' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key view avoids duplicate form and feedback icon names" \
  '"(checkmark\.circle\.fill|checkmark\.seal|checkmark\.seal\.fill|info\.circle|link|arrow\.up\.right\.square)"' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

reject_pattern \
  "iOS API-key list avoids shell-only provider readiness icons" \
  'isKeyVerified|checkmark\.seal\.fill|exclamationmark\.triangle\.fill' \
  iOS/VoiceInk-ios/APIKeysView.swift

require_pattern \
  "macOS local Whisper uses shared runtime invocation policy" \
  'VoiceInkWhisperRuntimeInvocationPlan\.current|withUnsafeCStringPointers' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper uses shared runtime invocation policy" \
  'VoiceInkWhisperRuntimeInvocationPlan\.current|withUnsafeCStringPointers' \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "shared local Whisper runtime invocation plan lives in VoiceInkCore" \
  'VoiceInkWhisperRuntimeInvocationPlan|withUnsafeCStringPointers|VoiceInkWhisperRuntimeConfiguration\.current' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperRuntimeDefaults.swift

require_pattern \
  "shared local Whisper runtime parameter sink lives in VoiceInkCore" \
  'VoiceInkWhisperRuntimeFullParameterSink|VoiceInkWhisperRuntimeVADParameterSink|func apply<Parameters: VoiceInkWhisperRuntimeFullParameterSink>' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperRuntimeDefaults.swift

require_pattern \
  "core tests cover shared local Whisper runtime invocation plan" \
  'testRuntimeInvocationPlanKeepsWhisperCStringInputsAlive|testRuntimeInvocationPlanOmitsDisabledWhisperInputs' \
  VoiceInkCore/Tests/VoiceInkCoreTests/WhisperRuntimeDefaultsTests.swift

require_pattern \
  "core tests cover shared local Whisper runtime parameter sink" \
  'testRuntimeConfigurationAppliesSharedWhisperFullParameterSink|testRuntimeConfigurationAppliesSharedWhisperVADParameterSink' \
  VoiceInkCore/Tests/VoiceInkCoreTests/WhisperRuntimeDefaultsTests.swift

require_pattern \
  "core check runner executes shared local Whisper runtime invocation tests" \
  'testRuntimeInvocationPlanKeepsWhisperCStringInputsAlive|testRuntimeInvocationPlanOmitsDisabledWhisperInputs' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core check runner executes shared local Whisper runtime parameter sink tests" \
  'testRuntimeConfigurationAppliesSharedWhisperFullParameterSink|testRuntimeConfigurationAppliesSharedWhisperVADParameterSink' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS local Whisper adapts whisper.cpp params to shared runtime sink" \
  'whisper_full_params: VoiceInkWhisperRuntimeFullParameterSink|whisper_vad_params: VoiceInkWhisperRuntimeVADParameterSink|runtimeConfiguration\.apply\(to: &params, makeVADParameters: whisper_vad_default_params\)' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper adapts whisper.cpp params to shared runtime sink" \
  'whisper_full_params: VoiceInkWhisperRuntimeFullParameterSink|whisper_vad_params: VoiceInkWhisperRuntimeVADParameterSink|runtimeConfiguration\.apply\(to: &params, makeVADParameters: whisper_vad_default_params\)' \
  iOS/VoiceInk-ios/LibWhisper.swift

reject_pattern \
  "local Whisper adapters avoid shell-owned runtime parameter assignments" \
  'params\.(print_realtime|print_progress|print_timestamps|print_special|translate|n_threads|offset_ms|no_context|single_segment|temperature|vad_params)[[:space:]]*=|params\.vad[[:space:]]*=|vadParams\.' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

section "obsolete standalone Whisper transcript segments module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/WhisperTranscriptSegments.swift

require_pattern \
  "shared local Whisper transcript segment policy lives with runtime policy" \
  'VoiceInkWhisperTranscriptSegments|joinedText\(segmentCount:' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperRuntimeDefaults.swift

require_pattern \
  "core tests cover shared local Whisper transcript segment policy" \
  'testJoinedTextFromSegmentLookupPreservesRawOrderAndSkipsMissingSegments|testJoinedTextFromSegmentLookupReturnsEmptyForNonPositiveCounts' \
  VoiceInkCore/Tests/VoiceInkCoreTests/WhisperTranscriptSegmentsTests.swift

require_pattern \
  "core check runner executes shared local Whisper transcript segment policy tests" \
  'testJoinedTextFromSegmentLookupPreservesRawOrderAndSkipsMissingSegments|testJoinedTextFromSegmentLookupReturnsEmptyForNonPositiveCounts' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS local Whisper delegates raw segment lookup to shared core" \
  'VoiceInkWhisperTranscriptSegments\.joinedText\(segmentCount:' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper delegates raw segment lookup to shared core" \
  'VoiceInkWhisperTranscriptSegments\.joinedText\(segmentCount:' \
  iOS/VoiceInk-ios/LibWhisper.swift

reject_pattern \
  "local Whisper adapters avoid shell-owned raw segment loops" \
  'var +segments: +\[String\]|for +.*whisper_full_n_segments|segments\.append' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

reject_pattern \
  "local Whisper adapters avoid shell-owned optional CString lifetime wiring" \
  'runWithPrompt|runWithLanguage|utf8CString' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "shared local Whisper failure policy lives in VoiceInkCore" \
  'VoiceInkLocalWhisperFailurePolicy|VoiceInkLocalWhisperFailure|VoiceInkLocalWhisperPlatform' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperRuntimeDefaults.swift

section "obsolete standalone error-description module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/ErrorDescription.swift

require_pattern \
  "shared error-description fallback lives with engine error vocabulary" \
  'VoiceInkErrorDescription|LocalizedError|localizedDescription' \
  VoiceInkCore/Sources/VoiceInkCore/VoiceInkEngineError.swift

require_pattern \
  "shared local Whisper transcription flow lives in VoiceInkCore" \
  'VoiceInkLocalWhisperTranscriptionFlow|VoiceInkLocalWhisperTranscriptionActions|VoiceInkLocalWhisperContextPlan' \
  VoiceInkCore/Sources/VoiceInkCore/LocalWhisperTranscriptionFlow.swift

require_pattern \
  "core tests cover shared local Whisper transcription flow" \
  'LocalWhisperTranscriptionFlowTests' \
  VoiceInkCore/Tests/VoiceInkCoreTests/LocalWhisperTranscriptionFlowTests.swift

require_pattern \
  "core check runner executes shared local Whisper transcription flow tests" \
  'LocalWhisperTranscriptionFlowTests' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared local Whisper transcription diagnostics live in VoiceInkCore" \
  'VoiceInkLocalWhisperTranscriptionDiagnostics|macOSInitiatingLocalTranscriptionMessage|macOSAudioSamplesProcessingFailedMessage|iOSStartingLocalTranscriptionMessage|iOSProcessedAudioSamplesMessage' \
  VoiceInkCore/Sources/VoiceInkCore/LocalWhisperTranscriptionFlow.swift

require_patterns \
  "shared local Whisper request defaults live in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/LocalWhisperTranscriptionFlow.swift \
  'static func macOS' \
  'VoiceInkTranscriptionLanguagePreference\.selectedLanguage' \
  'VoiceInkTranscriptionPromptPreference\.localWhisperPromptForSelectedLanguage' \
  'mapsThrownAudioSampleErrors: false' \
  'static func iOS' \
  'prompt: prompt \?\? ""'

require_pattern \
  "core tests cover shared local Whisper request defaults" \
  'testRequestBuildersPreservePlatformDefaults' \
  VoiceInkCore/Tests/VoiceInkCoreTests/LocalWhisperTranscriptionFlowTests.swift

require_pattern \
  "core check runner executes shared local Whisper request default tests" \
  'testRequestBuildersPreservePlatformDefaults' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core tests cover shared local Whisper transcription diagnostics" \
  'testTranscriptionDiagnosticsPreservePlatformLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/LocalWhisperTranscriptionFlowTests.swift

require_pattern \
  "core check runner executes shared local Whisper transcription diagnostics tests" \
  'testTranscriptionDiagnosticsPreservePlatformLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS local Whisper service maps failures through shared policy" \
  'VoiceInkLocalWhisperFailurePolicy\.error' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

require_pattern \
  "iOS local Whisper service maps failures through shared policy" \
  'VoiceInkLocalWhisperFailurePolicy\.error' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

require_pattern \
  "macOS local Whisper context maps load failures through shared policy" \
  'VoiceInkLocalWhisperFailurePolicy\.error' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper context maps load failures through shared policy" \
  'VoiceInkLocalWhisperFailurePolicy\.error' \
  iOS/VoiceInk-ios/LibWhisper.swift

reject_pattern \
  "local Whisper adapters avoid shell-owned failure mapping" \
  'VoiceInkEngineError\.(modelLoadFailed|localModelUnavailable|localModelLoadFailed|audioProcessingFailed|whisperCoreFailed|whisperTranscriptionFailed)' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "macOS local Whisper service uses shared transcription flow" \
  'VoiceInkLocalWhisperTranscriptionFlow\.transcribe|VoiceInkLocalWhisperTranscriptionActions<WhisperContext>' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

require_pattern \
  "macOS local Whisper service uses shared request defaults" \
  'VoiceInkLocalWhisperTranscriptionRequest\.macOS\(audioURL: audioURL\)' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

require_pattern \
  "macOS local Whisper preserves borrowed context lifetime through shared flow" \
  'shouldReleaseContext: false' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

require_pattern \
  "macOS local Whisper preserves thrown sample-read behavior through shared request defaults" \
  'mapsThrownAudioSampleErrors: false' \
  VoiceInkCore/Sources/VoiceInkCore/LocalWhisperTranscriptionFlow.swift

require_pattern \
  "macOS local Whisper preserves owned context failure lifetime through shared flow" \
  'shouldReleaseContextOnFailure: false' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

require_pattern \
  "iOS local Whisper service uses shared transcription flow" \
  'VoiceInkLocalWhisperTranscriptionFlow\.transcribe|VoiceInkLocalWhisperTranscriptionActions<WhisperContext>' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

require_pattern \
  "iOS local Whisper service uses shared request defaults" \
  'VoiceInkLocalWhisperTranscriptionRequest\.iOS\(' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

require_pattern \
  "macOS local Whisper service uses shared transcription diagnostics" \
  'VoiceInkLocalWhisperTranscriptionDiagnostics\.macOS' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

require_pattern \
  "iOS local Whisper service uses shared transcription diagnostics" \
  'VoiceInkLocalWhisperTranscriptionDiagnostics\.iOS' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

require_pattern \
  "iOS local Whisper releases owned contexts through shared flow" \
  'shouldReleaseContext: true' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

reject_pattern \
  "local Whisper services avoid shell-owned sample and transcription failure mapping" \
  'for: \.(audioProcessingFailed|transcriptionFailed)' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

reject_pattern \
  "local Whisper services avoid shell-owned request default construction" \
  'VoiceInkLocalWhisperTranscriptionRequest\(' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

reject_pattern \
  "local Whisper services avoid shell-owned transcription diagnostics" \
  '"(Initiating local transcription for model:|Using already loaded model:|Model file not found for:|Loading model:|Failed to load model:|Failed to process audio samples for local Whisper transcription\.|Core transcription engine failed \(whisper_full\)\.|Whisper transcription completed successfully\.|Starting local transcription\.|Using model at|Audio processing failed\.|Audio processing failed:|Processed .* audio samples\.|Transcription failed\.|Whisper context resources released\.|Transcription completed successfully\.)' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

require_pattern \
  "shared local Whisper context runtime plan lives in VoiceInkCore" \
  'VoiceInkWhisperContextRuntimePlan|VoiceInkWhisperContextParameterSink|func apply<Parameters: VoiceInkWhisperContextParameterSink>' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperRuntimeDefaults.swift

require_pattern \
  "core tests cover shared local Whisper context parameter sink" \
  'testContextRuntimePlanAppliesSimulatorParametersWithoutOverwritingFlashAttention|testContextRuntimePlanAppliesDeviceParametersWithoutOverwritingGPUDefault' \
  VoiceInkCore/Tests/VoiceInkCoreTests/WhisperRuntimeDefaultsTests.swift

require_pattern \
  "core check runner executes shared local Whisper context parameter sink tests" \
  'testContextRuntimePlanAppliesSimulatorParametersWithoutOverwritingFlashAttention|testContextRuntimePlanAppliesDeviceParametersWithoutOverwritingGPUDefault' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS local Whisper uses shared context runtime plan" \
  'VoiceInkWhisperContextRuntimePlan\.current|whisper_context_params: VoiceInkWhisperContextParameterSink|runtimePlan\.apply\(to: &params\)' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper uses shared context runtime plan" \
  'VoiceInkWhisperContextRuntimePlan\.current|whisper_context_params: VoiceInkWhisperContextParameterSink|runtimePlan\.apply\(to: &params\)' \
  iOS/VoiceInk-ios/LibWhisper.swift

reject_pattern \
  "local Whisper adapters avoid shell-owned context parameter assignments" \
  'params\.(use_gpu|flash_attn)[[:space:]]*=' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "macOS local Whisper uses shared local model URL resolution" \
  'VoiceInkWhisperModelFiles\.availableLocalModelFileURL' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

reject_pattern \
  "macOS local Whisper avoids shell-owned local model URL resolution" \
  'availableModels\.first\(where:|FileManager\.default\.fileExists\(atPath: modelURL\.path\)' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

reject_pattern \
  "local Whisper adapters avoid shell-only context runtime policy" \
  'params\.(use_gpu|flash_attn) = (false|true)|#if targetEnvironment\(simulator\)' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "shared local Whisper diagnostics live in VoiceInkCore" \
  'VoiceInkWhisperRuntimeDiagnostics|logCategory = "WhisperContext"|simulatorCPUModeMessage = "Running on the simulator, using CPU"|metalFlashAttentionMessage = "Flash attention enabled for Metal"|vadBundleModelLoadedMessage = "VAD model loaded from bundle resources"|vadModelPathMissingWarningMessage = "VAD model path not found, VAD will be disabled\."|transcriptionFailedMessage|modelLoadFailedMessagePrefix' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperRuntimeDefaults.swift

require_patterns \
  "core tests cover shared local Whisper runtime failure diagnostics" \
  VoiceInkCore/Tests/VoiceInkCoreTests/WhisperRuntimeDefaultsTests.swift \
  'VoiceInkWhisperRuntimeDiagnostics\.transcriptionFailedMessage' \
  'VoiceInkWhisperRuntimeDiagnostics\.modelLoadFailedMessagePrefix'

require_pattern \
  "macOS local Whisper uses shared diagnostics" \
  'VoiceInkWhisperRuntimeDiagnostics\.(logCategory|simulatorCPUModeMessage|metalFlashAttentionMessage|vadBundleModelLoadedMessage)' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_patterns \
  "macOS local Whisper uses shared runtime failure diagnostics" \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  'VoiceInkWhisperRuntimeDiagnostics\.transcriptionFailedMessage\(isVADEnabled: params\.vad, platform: \.macOS\)' \
  'VoiceInkWhisperRuntimeDiagnostics\.modelLoadFailedMessagePrefix\(platform: \.macOS\)'

require_pattern \
  "iOS local Whisper uses shared diagnostics" \
  'VoiceInkWhisperRuntimeDiagnostics\.(logCategory|simulatorCPUModeMessage|metalFlashAttentionMessage|vadBundleModelLoadedMessage|vadModelPathMissingWarningMessage)' \
  iOS/VoiceInk-ios/LibWhisper.swift

require_patterns \
  "iOS local Whisper uses shared runtime failure diagnostics" \
  iOS/VoiceInk-ios/LibWhisper.swift \
  'VoiceInkWhisperRuntimeDiagnostics\.transcriptionFailedMessage\(isVADEnabled: params\.vad, platform: \.iOS\)' \
  'VoiceInkWhisperRuntimeDiagnostics\.modelLoadFailedMessagePrefix\(platform: \.iOS\)'

reject_pattern \
  "local Whisper adapters avoid duplicate shared diagnostics literals" \
  '"(WhisperContext|Running on the simulator, using CPU|Flash attention enabled for Metal|VAD model loaded from bundle resources|VAD model path not found, VAD will be disabled\.|Failed to run whisper_full\. VAD enabled:|Couldn.t load model at)"' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

section "obsolete standalone VAD model resource module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/VADModelFiles.swift

require_patterns \
  "VAD resource helper lives with Whisper model-file policy" \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift \
  'VoiceInkVADModelFiles' \
  'ggml-silero-v5\.1\.2' \
  'VoiceInkWhisperModelFiles'

require_pattern \
  "macOS local Whisper uses shared VAD resource policy" \
  'VoiceInkVADModelFiles\.sileroPath' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper uses shared VAD resource policy" \
  'VoiceInkVADModelFiles\.sileroPath' \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "macOS local Whisper reads samples through shared Whisper audio policy" \
  'VoiceInkWhisperAudioSamples\.floatSamples\(fromWAVFileAt:' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

reject_pattern \
  "macOS local Whisper avoids shell-only PCM16 sample wrapper" \
  'private +func +readAudioSamples\(' \
  VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift

require_pattern \
  "iOS local Whisper reads samples through shared Whisper audio policy" \
  'VoiceInkWhisperAudioSamples\.floatSamples\(fromWAVFileAt:' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

reject_pattern \
  "iOS local Whisper uses shared engine errors for audio processing failures" \
  'NSError|Invalid WAV file - too small' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

require_pattern \
  "macOS quick-release duration uses shared PCM16 policy" \
  'VoiceInkPCM16Audio\.duration\(forMono16kData:' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS rolling preload uses shared PCM16 byte-count policy" \
  'VoiceInkPCM16Audio\.byteCount\(forMono16kDuration:' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadCoordinator.swift

reject_pattern \
  "macOS rolling preload avoids shell-only PCM16 byte-count wrapper" \
  'private +static +func +bytes\(forDuration' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadCoordinator.swift

reject_pattern \
  "macOS quick-release avoids shell-only PCM16 duration wrapper" \
  'durationForMono16kPCMData' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS and iOS model downloads use shared HTTP response policy" \
  '200\.\.\.299' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "shared Whisper model download completion policy lives in VoiceInkCore" \
  'Completion|missingTemporaryFile|completion\(temporaryURL:' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "macOS Whisper download uses shared completion policy" \
  'VoiceInkWhisperModelDownloadResponsePolicy\.completion\(' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

require_pattern \
  "iOS local model manager uses shared completion policy" \
  'VoiceInkWhisperModelSimpleDownloadCompletionPlan\.completion\(' \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "shared Whisper model download progress policy lives in VoiceInkCore" \
  'VoiceInkWhisperModelDownloadProgress|VoiceInkWhisperModelDownloadState' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model download state policy lives in VoiceInkCore" \
  'VoiceInkWhisperModelDownloadState' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper simple download tracking state lives in VoiceInkCore" \
  'VoiceInkWhisperModelSimpleDownloadTrackingState|startDownload\(for:|finishDownload\(for:|downloadState\(for:' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model download row presentation lives in VoiceInkCore" \
  'VoiceInkWhisperModelDownloadRowPresentation|rowPresentation|actionSystemImageName|downloadButtonSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model management rows live in VoiceInkCore" \
  'VoiceInkWhisperModelManagement(Row|List)|downloadConfirmation|deleteConfirmation' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model operation alert presentation lives in VoiceInkCore" \
  'VoiceInkWhisperModelOperationAlertPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model management diagnostics live in VoiceInkCore" \
  'VoiceInkWhisperModelManagementDiagnostics|alreadyDownloadingMessage|startingDownloadMessage|downloadFailedMessage|downloadCancelledMessage|downloadedMessage|saveFailedMessage|notDownloadedMessage|deletedMessage|deleteFailedMessage|deleteActionFailedMessage' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper simple download completion plan lives in VoiceInkCore" \
  'VoiceInkWhisperModelSimpleDownloadCompletionPlan|installTemporaryFile|presentFailure|ignoreCancellation' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper simple download completion plan owns cancellation outcome" \
  'ignoreCancellation|NSURLErrorCancelled|CancellationError' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "core checks cover iOS download cancellation completion planning" \
  'WhisperModelFilesTests\.testSimpleDownloadCompletionPlanIgnoresCancellation' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks cover iOS local model management diagnostics" \
  'WhisperModelFilesTests\.testModelManagementDiagnosticsPreserveIOSLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared Whisper model operation confirmation presentation lives in VoiceInkCore" \
  'VoiceInkWhisperModelOperationConfirmationPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper local model import extension policy lives in VoiceInkCore" \
  'modelFileExtension|isImportableModelFile' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared Whisper local model import plan lives in VoiceInkCore" \
  'VoiceInkWhisperLocalModelImportPlan|localModelImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared Whisper local model import plan owns destination filename" \
  'let modelFilename = filename\(forModelName: modelName\)' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared Whisper local model import plan owns destination URL" \
  'let destinationURL = fileURL\(forFilename: modelFilename, in: modelsDirectory\)' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared Whisper local model import plan owns local model record" \
  'localModelFile: VoiceInkWhisperLocalModelFile\(name: modelName, url: destinationURL\)' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared Whisper local model import plan owns duplicate detection" \
  'isDuplicate: fileManager\.fileExists\(atPath: destinationURL\.path\)' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared Whisper downloaded local model data builds local model record" \
  'writeDownloadedLocalModelData|VoiceInkWhisperLocalModelFile\(name: modelName, url: destinationURL\)' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared Whisper imported local model merge plan lives in VoiceInkCore" \
  'importedLocalModelNamesToAdd|existingModelNames|downloadedLocalModels' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared Whisper downloaded local model lookup lives in VoiceInkCore" \
  'downloadedLocalModelFile|localModels\.first' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "macOS transcription model manager uses shared imported local model merge plan" \
  'VoiceInkWhisperModelFiles\.importedLocalModelNamesToAdd' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

require_pattern \
  "core checks execute imported local model merge plan test" \
  'WhisperModelFilesTests\.testImportedLocalModelNamesToAddSkipsExistingRegistryModelsAndDownloadedDuplicates|WhisperModelFilesTests\.testDownloadedLocalModelFileUsesFirstDownloadedNameMatch' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS transcription model manager avoids shell-owned imported local model duplicate scan" \
  'for +whisperModel in whisperModelManager\?\.availableModels|models\.contains\(where: \{ \$0\.name == whisperModel\.name \}\)' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

require_pattern \
  "shared Whisper available local model URL resolution lives in VoiceInkCore" \
  'availableLocalModelFileURL|downloadedLocalModelFile\(forModelName: modelName, in: localModels\)|fileManager\.fileExists\(atPath: model\.url\.path\)' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelFiles.swift

require_pattern \
  "shared model management filter lives in VoiceInkCore" \
  'enum VoiceInkModelManagementFilter' \
  VoiceInkCore/Sources/VoiceInkCore/ModelManagementPresentation.swift

require_pattern \
  "shared model management filter owns model facts and recommended order" \
  'VoiceInkModelManagementModelFacts|VoiceInkModelManagementModelCategory|recommendedModelNames|func +includes' \
  VoiceInkCore/Sources/VoiceInkCore/ModelManagementPresentation.swift

require_pattern \
  "shared model management copy presentation lives in VoiceInkCore" \
  'enum VoiceInkModelManagementPresentation|downloadButtonTitle|editModelButtonTitle|deleteModelButtonTitle|deleteButtonTitle|deleteCustomModelAlertTitle|deleteCustomModelAlertMessage|deleteModelAlertMessage|showInFinderButtonTitle|speedLabel|accuracyLabel|languageLabel|multilingualLanguageLabel|englishOnlyLanguageLabel|importedLocalModelDescription|customProviderLabel|openAICompatibleLabel|nativeAppleProviderLabel|onDeviceLabel|macOS26RequiredLabel|importLocalModelHelpText|importLocalModelLearnMoreURLString|importLocalModelPanelTitle|intelMacLocalModelsWarningText|intelMacUseCloudButtonTitle|importedLocalModelFailureTitle' \
  VoiceInkCore/Sources/VoiceInkCore/ModelManagementPresentation.swift

require_pattern \
  "macOS transcription models use shared model language and imported-local copy" \
  'VoiceInkModelManagementPresentation\.(languageLabel|importedLocalModelDescription)' \
  VoiceInk/Models/TranscriptionModel.swift

reject_pattern \
  "macOS transcription models avoid shell-only model language and imported-local copy" \
  '"(Multilingual|English-only|Imported local model)"' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "shared Whisper compact download status text lives in VoiceInkCore" \
  'compactStatusText' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "macOS Whisper downloads use shared progress keys" \
  'VoiceInkWhisperModelDownloadProgress\.(mainProgressKey|coreMLProgressKey)' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

require_pattern \
  "macOS Whisper main model download uses shared local model record" \
  'VoiceInkWhisperModelFiles\.writeDownloadedLocalModelData\(' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

reject_context_pattern \
  "macOS Whisper main model download avoids shell-owned local model record" \
  'private func downloadMainModel' \
  'VoiceInkWhisperLocalModelFile\(name:' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

require_pattern \
  "macOS Whisper local model import uses shared import plan" \
  'VoiceInkWhisperModelFiles\.localModelImportPlan\(' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

reject_context_pattern \
  "macOS Whisper local model import avoids shell-owned import planning" \
  'func importWhisperModel' \
  'deletingPathExtension\(\)\.lastPathComponent|fileURL\(forModelName:|VoiceInkWhisperLocalModelFile\(name:|fileExists\(atPath:' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

reject_pattern \
  "macOS Whisper local model import avoids shell-owned extension policy" \
  'pathExtension\.lowercased\(\) == "bin"|"\.bin already exists"' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

require_pattern \
  "macOS Whisper model card uses shared download-state predicate" \
  'VoiceInkWhisperModelDownloadProgress\.isMacOSDownloading' \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift

require_pattern \
  "macOS Whisper model card uses shared compact download status copy" \
  'VoiceInkWhisperModelDownloadProgress\.compactDownloadingStatusText' \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift

require_pattern \
  "macOS FluidAudio model card uses shared compact download status copy" \
  'VoiceInkFluidAudioDownloadStatus\.compactDownloadingStatusText' \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

require_pattern \
  "macOS Whisper model card uses shared model-card presentation copy" \
  'VoiceInkModelManagementPresentation\.(speedLabel|accuracyLabel|downloadButtonTitle|deleteModelButtonTitle|showInFinderButtonTitle|importedLocalModelDescription)' \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift

require_pattern \
  "macOS FluidAudio model card uses shared model-card presentation copy" \
  'VoiceInkModelManagementPresentation\.(speedLabel|accuracyLabel|downloadButtonTitle|deleteModelButtonTitle|showInFinderButtonTitle)' \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

require_pattern \
  "macOS cloud model card uses shared model-card metric labels" \
  'VoiceInkModelManagementPresentation\.(speedLabel|accuracyLabel)' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS custom model card uses shared model-card presentation copy" \
  'VoiceInkModelManagementPresentation\.(customProviderLabel|openAICompatibleLabel|editModelButtonTitle|deleteModelButtonTitle)' \
  VoiceInk/Views/AI\ Models/CustomModelCardView.swift

require_pattern \
  "macOS Native Apple model card uses shared model-card badge copy" \
  'VoiceInkModelManagementPresentation\.(nativeAppleProviderLabel|onDeviceLabel|macOS26RequiredLabel)' \
  VoiceInk/Views/AI\ Models/NativeModelCardView.swift

require_pattern \
  "macOS Whisper download progress view uses shared progress presentation" \
  'VoiceInkWhisperModelDownloadProgress\.macOS' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

reject_pattern \
  "macOS Whisper download progress view avoids shallow progress presentation wrappers" \
  'private var +progressPresentation\b' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

require_pattern \
  "macOS model management uses shared filter presentation" \
  'VoiceInkModelManagementFilter\.allCases|filter\.title' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

require_pattern \
  "macOS TranscriptionModel adapts shared model-management facts" \
  'modelManagementFacts|VoiceInkModelManagementModelFacts|modelManagementCategory' \
  VoiceInk/Models/TranscriptionModel.swift

require_patterns \
  "shared transcription model provider role owns category route availability and language source" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift \
  'VoiceInkTranscriptionModelProviderRole' \
  'modelManagementCategory' \
  'transcriptionServiceRoute' \
  'transcriptionModelAvailabilityRequirement' \
  'transcriptionLanguageSource' \
  'transcriptionLanguageOptions' \
  'apiKeyProviderName' \
  'streamingConnectionModelName' \
  'mapsStreamingTransportTimeoutToFinalTimeout'

require_pattern \
  "macOS ModelProvider adapts shared transcription model provider role" \
  'coreTranscriptionModelProviderRole' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS TranscriptionModel uses shared provider-role language options" \
  'coreTranscriptionModelProviderRole\.transcriptionLanguageOptions' \
  VoiceInk/Models/TranscriptionModel.swift

require_patterns \
  "macOS TranscriptionModel uses shared provider-role streaming facts" \
  VoiceInk/Models/TranscriptionModel.swift \
  'coreTranscriptionModelProviderRole\.apiKeyProviderName' \
  'coreTranscriptionModelProviderRole\.supportsRecordedFileTranscription' \
  'coreTranscriptionModelProviderRole\.isStreamingOnly' \
  'coreTranscriptionModelProviderRole\.streamingConnectionModelName' \
  'coreTranscriptionModelProviderRole\.mapsStreamingTransportTimeoutToFinalTimeout'

require_pattern \
  "core checks execute transcription model provider role tests" \
  'TranscriptionModelCatalogTests\.testProviderRoleOwnsModelCategoryRouteAvailabilityAndLanguageSource' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_context_pattern \
  "macOS ModelProvider avoids shell-only language-source switch" \
  'fileprivate var transcriptionLanguageSource' \
  'switch self|guard let coreProvider' \
  VoiceInk/Models/TranscriptionModel.swift

reject_context_pattern \
  "macOS ModelProvider avoids shell-only model-management category switch" \
  'var modelManagementCategory' \
  'switch self|case \.whisper, \.nativeApple, \.fluidAudio|case \.custom' \
  VoiceInk/Models/TranscriptionModel.swift

reject_context_pattern \
  "macOS ModelProvider avoids shell-only service-route switch" \
  'var transcriptionServiceRoute' \
  'switch self|case \.whisper|case \.fluidAudio|case \.nativeApple' \
  VoiceInk/Models/TranscriptionModel.swift

reject_context_pattern \
  "macOS ModelProvider avoids shell-only availability switch" \
  'var transcriptionModelAvailabilityRequirement' \
  'switch self|downloadedLocalWhisperModel|downloadedLocalFluidAudioModel|currentOSSupport|alwaysAvailable|configuredAPIKey' \
  VoiceInk/Models/TranscriptionModel.swift

reject_pattern \
  "macOS TranscriptionModel avoids shell-only AssemblyAI language-option branching" \
  'provider == \.assemblyAI|assemblyAIUsesRealtime:' \
  VoiceInk/Models/TranscriptionModel.swift

reject_pattern \
  "macOS TranscriptionModel avoids shell-only optional cloud-provider fallback facts" \
  'coreTranscriptionModelProvider\?\.(providerKind\?\.displayName|supportsRecordedFileTranscription|isStreamingOnly|streamingConnectionModelName|mapsStreamingTransportTimeoutToFinalTimeout)' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS model management uses shared filter membership" \
  'selectedFilter\.includes|sortRank\(forModelName:|modelManagementFacts\(for:' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

require_pattern \
  "macOS model management uses shared downloaded local model lookup" \
  'VoiceInkWhisperModelFiles\.downloadedLocalModelFile' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

reject_pattern \
  "macOS model management avoids shell-owned downloaded local model lookup" \
  'availableModels\.(contains|first)\s*(\(|\{)' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

require_pattern \
  "macOS model management uses shared settings title copy" \
  'VoiceInkModelManagementPresentation\.settingsTitle' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

require_pattern \
  "macOS model management uses shared default-model fallback copy" \
  'VoiceInkModelManagementPresentation\.noModelSelectedText' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

require_pattern \
  "macOS model management uses shared import and custom-model copy" \
  'VoiceInkModelManagementPresentation\.(importLocalModelTitle|importLocalModelHelpText|importLocalModelLearnMoreURLString|importLocalModelLearnMoreHelpText|importLocalModelPanelTitle|customModelsLimitationText|intelMacLocalModelsWarningText|intelMacUseCloudButtonTitle)' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

reject_pattern \
  "macOS model management avoids shell-owned local import copy and file extension" \
  'filenameExtension: "bin"|"Select a Whisper ggml \.bin model"|"Add a custom fine-tuned whisper model to use with VoiceInk\. Select the downloaded \.bin file\."|"https://tryvoiceink\.com/docs/custom-local-whisper-models"|"Read more about custom local models"|"Local models don'"'"'t work reliably on Intel Macs"|"Use Cloud"' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

require_pattern \
  "macOS model management uses shared delete-confirmation copy" \
  'VoiceInkModelManagementPresentation\.(deleteButtonTitle|deleteCustomModelAlertTitle|deleteCustomModelAlertMessage|deleteModelButtonTitle|deleteModelAlertMessage)' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

require_pattern \
  "iOS settings use shared local model management presentation" \
  'VoiceInkModelManagementFilter\.local\.(settingsSectionTitle|manageSettingsTitle)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS settings use shared cloud model management presentation" \
  'VoiceInkModelManagementFilter\.cloud\.(settingsSectionTitle|manageSettingsTitle)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS local model destination uses shared navigation title" \
  'VoiceInkModelManagementFilter\.local\.settingsSectionTitle' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS cloud model destination uses shared navigation title" \
  'VoiceInkModelManagementFilter\.cloud\.settingsSectionTitle' \
  iOS/VoiceInk-ios/APIKeysView.swift

require_pattern \
  "iOS local model manager uses shared download tracking state" \
  'VoiceInkWhisperModelSimpleDownloadTrackingState|downloadTrackingState|downloadState\(for:' \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "iOS local model manager exposes shared management rows" \
  'VoiceInkWhisperModelManagementList\.(row|rows)|managementRow' \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "iOS local model manager delegates delete planning to shared core" \
  'VoiceInkWhisperModelDeletionPolicy\.plan' \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "iOS local model manager applies shared delete refresh intent" \
  'deletionPlan\.shouldRefreshAfterSuccessfulDelete' \
  iOS/VoiceInk-ios/LocalModelManager.swift

reject_pattern \
  "iOS local model manager avoids shell-owned download state dictionaries" \
  '@Published var +(downloadProgress|isDownloading)|isDownloading\[[^]]+\]|downloadProgress\[[^]]+\]' \
  iOS/VoiceInk-ios/LocalModelManager.swift

reject_pattern \
  "iOS local model manager avoids shallow setup wrapper" \
  'private func +setupModelsDirectory\(' \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "iOS local model management uses shared management rows" \
  'modelManager\.managementRows\(\)' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model management uses shared row confirmations" \
  'row\.(downloadConfirmation|deleteConfirmation)' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model management uses shared compact download status text" \
  '\.progress\.compactStatusText' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model management uses shared model row presentation" \
  'row\.presentation|actionSystemImageName' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model management uses shared row action enum" \
  'presentation\.action' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

reject_pattern \
  "iOS local model management avoids shallow row action booleans" \
  'presentation\.(isDownloaded|canStartDownload|canCancelDownload|canDeleteDownloadedModel)\b' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

reject_pattern \
  "iOS local model management avoids shell-owned model row assembly" \
  'VoiceInkWhisperModelFiles\.bootstrapModels|modelManager\.downloadState\(for: model\)|private var +(downloadConfirmation|deleteConfirmation|rowPresentation)|VoiceInkWhisperModelOperationConfirmationPresentation' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model manager uses shared operation alert presentation" \
  'VoiceInkWhisperModelOperationAlertPresentation|\.(downloadFailed|serverErrorDuringDownload|noFileReceived|saveFailed)' \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "iOS local model manager uses shared management diagnostics" \
  'VoiceInkWhisperModelManagementDiagnostics\.(alreadyDownloadingMessage|startingDownloadMessage|downloadFailedMessage|downloadCancelledMessage|downloadedMessage|saveFailedMessage|notDownloadedMessage|deletedMessage|deleteFailedMessage)' \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "iOS local model management view uses shared management diagnostics" \
  'VoiceInkWhisperModelManagementDiagnostics\.deleteActionFailedMessage' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model manager applies shared download cancellation outcome" \
  'ignoreCancellation' \
  iOS/VoiceInk-ios/LocalModelManager.swift

reject_pattern \
  "iOS local model manager avoids shell-owned download completion failure mapping" \
  'VoiceInkWhisperModelDownloadResponsePolicy\.completion|serverErrorDuringDownload|noFileReceived|downloadFailed\(for:|NSURLErrorCancelled|CancellationError' \
  iOS/VoiceInk-ios/LocalModelManager.swift

reject_pattern \
  "iOS local model manager avoids shell-owned delete downloaded gate" \
  'model\.isDownloaded\(in:' \
  iOS/VoiceInk-ios/LocalModelManager.swift

reject_pattern \
  "iOS local model manager avoids shell-owned management diagnostics" \
  '"(Model |Starting download of|Download failed for|Download cancelled for|Successfully downloaded|Failed to save|Successfully deleted model|Failed to delete model)' \
  iOS/VoiceInk-ios/LocalModelManager.swift

reject_pattern \
  "iOS local model management view avoids shell-owned management diagnostics" \
  '"Delete failed:' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model deletion uses shared operation alert presentation" \
  '\.deleteFailed' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

reject_pattern \
  "iOS local model row avoids duplicate post-delete refresh" \
  'DispatchQueue\.main\.asyncAfter|Force UI update by triggering objectWillChange' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model views render shared operation alert presentation" \
  'alert\(item: +\$modelManager\.downloadError' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS onboarding renders shared operation alert presentation" \
  'alert\(item: +\$modelManager\.downloadError' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared model management row" \
  'modelManager\.managementRow\(for: baseModel\)|row\.presentation' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared model download confirmation" \
  'row\.downloadConfirmation' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared compact download status text" \
  '\.progress\.compactStatusText' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared model row presentation" \
  'row\.presentation|actionSystemImageName|downloadButtonSystemImageName' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared model row action enum" \
  'presentation\.action' \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS onboarding avoids shallow row action booleans" \
  'presentation\.(isDownloaded|canStartDownload|canCancelDownload|canDeleteDownloadedModel)\b' \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS onboarding avoids shell-owned model row assembly" \
  'baseModelDownloadState|private var +(downloadConfirmation|rowPresentation)|VoiceInkWhisperModel(OperationConfirmation|DownloadRow)Presentation' \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS onboarding avoids shallow base model row wrapper" \
  'private var +baseModelRow\b' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "shared iOS onboarding presentation lives in VoiceInkCore" \
  'VoiceInkIOSOnboardingStep|VoiceInkIOSOnboardingPresentation|VoiceInkOnboardingFeaturePresentation|VoiceInkOnboardingStepPresentation|VoiceInkIOSAppIconSource|VoiceInkIOSAppIconPolicy|appIconFallbackSystemImageName|bundleIconFiles\(from infoDictionary:' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "iOS onboarding uses shared onboarding presentation" \
  'VoiceInkIOSOnboardingPresentation\.(appIconFallbackSystemImageName|welcome|modelDownload|ready)|VoiceInkIOSAppIconPolicy\.(bundleIconFiles|source)' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared onboarding step state" \
  'VoiceInkIOSOnboardingStep\.initial|@Binding var currentStep: VoiceInkIOSOnboardingStep' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding advances through shared step policy" \
  'currentStep\.advance\(\)' \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS onboarding avoids shell-owned integer step flow" \
  '@State private var currentStep = +0|@Binding var currentStep: Int|currentStep == +(0|1|2)|currentStep = +(1|2)' \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS onboarding avoids shell-owned app icon source decision" \
  'let +lastIcon += +iconFiles\.last|UIImage\(named: +lastIcon\)|CFBundle(Icons|PrimaryIcon|IconFiles)' \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS onboarding avoids shell-only onboarding copy" \
  '"(Transform your thoughts into text effortlessly\.|Instant Recording|Capture your thoughts with a single tap, anytime, anywhere\.|Accurate Transcription|Leverage powerful AI models for precise speech-to-text conversion\.|Works Offline|Transcribe without an internet connection using local models\.|Get Started|Offline Transcription|Download a local model to transcribe audio even without an internet connection\.|Continue|You'\''re All Set!|Start recording your thoughts and ideas\.|Tap the record button to capture your thoughts\.|AI converts your speech to text automatically\.|Your notes are saved and ready for review\.)"' \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS onboarding avoids duplicate app icon fallback symbol" \
  '"app\.fill"' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "shared macOS welcome onboarding presentation lives in VoiceInkCore" \
  'VoiceInkMacOSOnboardingWelcomePresentation|welcome|typewriterRoles' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS welcome onboarding uses shared presentation" \
  'VoiceInkMacOSOnboardingPresentation\.welcome|presentation\.(title|subtitle|primaryButtonTitle|skipButtonTitle|typewriterRoles)' \
  VoiceInk/Views/Onboarding/OnboardingView.swift

reject_pattern \
  "macOS welcome onboarding avoids shell-only presentation copy" \
  '"(Welcome to the Future of Typing|A New Way to Type|Get Started|Skip Tour|Your Writing Assistant|Your Vibe-Coding Assistant|Works Everywhere on Mac with a click|100% offline & private)"' \
  VoiceInk/Views/Onboarding/OnboardingView.swift

require_pattern \
  "shared macOS model-download onboarding presentation lives in VoiceInkCore" \
  'VoiceInkMacOSOnboardingPresentation|VoiceInkMacOSOnboardingModelDownloadPresentation|modelDownload|skipButtonTitle|speedLabel|ramLabel|buttonTitle' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS model-download onboarding uses shared presentation" \
  'VoiceInkMacOSOnboardingPresentation\.modelDownload|presentation\.(title|subtitle|skipButtonTitle|speedLabel|accuracyLabel|ramLabel)|buttonTitle\(isModelSet:' \
  VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift

require_pattern \
  "macOS model-download onboarding uses shared default FluidAudio model" \
  'TranscriptionModelRegistry\.defaultMacOSFluidAudioModel' \
  VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift

reject_pattern \
  "macOS model-download onboarding avoids shell-only presentation copy" \
  '"(Download AI Model|We'\''ll download the optimized model to get you started\.|Skip for now|Downloading\.\.\.|Set as Default|Download Model|Speed|Accuracy|RAM)"' \
  VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift

reject_pattern \
  "macOS model-download onboarding avoids hardcoded default FluidAudio model" \
  '"parakeet-tdt-0\.6b-v2"|TranscriptionModelRegistry\.models\.first' \
  VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift

reject_pattern \
  "macOS model-download onboarding avoids shallow button-title wrappers" \
  'private func +getButtonTitle\(' \
  VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift

require_pattern \
  "shared macOS onboarding tutorial presentation lives in VoiceInkCore" \
  'VoiceInkMacOSOnboardingTutorialPresentation|tutorial|shortcutTitle|instructionSteps|placeholderIconSystemName|placeholderText' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS onboarding tutorial uses shared presentation" \
  'VoiceInkMacOSOnboardingPresentation\.tutorial|presentation\.(title|subtitle|shortcutTitle|instructionSteps|completeButtonTitle|skipButtonTitle|placeholderIconSystemName|placeholderText)' \
  VoiceInk/Views/Onboarding/OnboardingTutorialView.swift

reject_pattern \
  "macOS onboarding tutorial avoids shell-only presentation copy" \
  '"(Try It Out!|Let'\''s test your roma-just-talk setup\.|Your Shortcut|Complete Setup|Skip for now|Click here and start speaking\.\.\.|Click the text area on the right|Press your shortcut key|Speak something|Press your shortcut key again)"|systemName: "wand\.and\.stars"' \
  VoiceInk/Views/Onboarding/OnboardingTutorialView.swift

require_pattern \
  "shared macOS reset-onboarding settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSResetOnboardingPresentation|resetSettingsAlert|confirmButtonTitle|message' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS settings reset onboarding uses shared presentation" \
  'VoiceInkMacOSOnboardingPresentation\.resetSettingsAlert|resetOnboardingPresentation\.(buttonTitle|alertTitle|cancelButtonTitle|confirmButtonTitle|message)' \
  VoiceInk/Views/Settings/SettingsView.swift

reject_pattern \
  "macOS settings reset onboarding avoids shell-only alert copy" \
  '"Reset Onboarding"|"You'\''ll see the introduction screens again the next time you launch the app\."' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "shared macOS setup presentation lives in VoiceInkCore" \
  'VoiceInkMacOSSetupPresentation|VoiceInkMacOSSetupStepPresentation|actionButtonTitle' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS metrics setup uses shared setup presentation" \
  'VoiceInkMacOSSetupPresentation\.(title|subtitle|steps|actionButtonTitle|helpText|completedSystemImageName|optionalSystemImageName|requiredSystemImageName)' \
  VoiceInk/Views/Metrics/MetricsSetupView.swift

require_pattern \
  "core tests pin macOS setup presentation copy and policy" \
  'testMacOSSetupPresentationPreservesHeaderAndStepOrder|testMacOSSetupPresentationPreservesActionTitlePolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/OnboardingPresentationTests.swift

require_pattern \
  "core tests pin iOS onboarding step flow" \
  'testIOSOnboardingStepOrderPreservesExistingFlow' \
  VoiceInkCore/Tests/VoiceInkCoreTests/OnboardingPresentationTests.swift

require_pattern \
  "core tests pin iOS app icon source policy" \
  'testIOSAppIconPolicyExtractsBundleIconFilesFromInfoDictionary|testIOSAppIconPolicyUsesLoadableLastBundleIcon|testIOSAppIconPolicyFallsBackWhenLastBundleIconIsMissing|testIOSAppIconPolicyFallsBackWithoutBundleIconFiles' \
  VoiceInkCore/Tests/VoiceInkCoreTests/OnboardingPresentationTests.swift

require_pattern \
  "core check runner executes iOS app icon source policy tests" \
  'testIOSAppIconPolicyExtractsBundleIconFilesFromInfoDictionary|testIOSAppIconPolicyUsesLoadableLastBundleIcon|testIOSAppIconPolicyFallsBackWhenLastBundleIconIsMissing|testIOSAppIconPolicyFallsBackWithoutBundleIconFiles' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core check runner executes macOS setup presentation tests" \
  'testMacOSSetupPresentationPreservesHeaderAndStepOrder|testMacOSSetupPresentationPreservesActionTitlePolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core check runner executes iOS onboarding step flow test" \
  'testIOSOnboardingStepOrderPreservesExistingFlow' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS metrics setup avoids shell-only setup presentation copy" \
  '"(Welcome to VoiceInk|Complete the setup to get started|Set Keyboard Shortcut|Use VoiceInk anywhere with a shortcut\.|Enable Accessibility|Paste transcribed text at your cursor\.|Screen Context \(Optional\)|Use visible text for better transcript enhancement when you choose\.|Download Model|Choose an AI model to start transcribing\.|Configure Shortcut|Get Started|Need help\? Check the Help menu for support options)"|systemName: "(command|hand\.raised\.fill|video\.fill|arrow\.down\.to\.line|checkmark\.circle\.fill|circle|chevron\.right)"' \
  VoiceInk/Views/Metrics/MetricsSetupView.swift

reject_pattern \
  "macOS metrics setup avoids shallow action-title wrapper" \
  'private var +actionButtonTitle[[:space:]]*:' \
  VoiceInk/Views/Metrics/MetricsSetupView.swift

require_pattern \
  "migration checklist tracks shared macOS reset onboarding alert presentation" \
  'macOS reset-onboarding settings alert presentation|VoiceInkMacOSOnboardingPresentation\.resetSettingsAlert' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared macOS setup presentation" \
  'macOS metrics setup step order, icons, labels, help text, and action-title policy route through `VoiceInkMacOSSetupPresentation`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared macOS welcome onboarding presentation" \
  'macOS onboarding welcome presentation|VoiceInkMacOSOnboardingPresentation\.welcome' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared macOS onboarding permission presentation lives in VoiceInkCore" \
  'VoiceInkMacOSOnboardingPermissionPresentation|VoiceInkMacOSOnboardingPermissionKind|VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation|audioDeviceSelectionPresentation|skipButtonTitle|relaunchRequiredMessage|canSkipWhenNotGranted|buttonTitle' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS onboarding permissions use shared permission presentation" \
  'VoiceInkMacOSOnboardingPermissionPresentation\.all|audioDeviceSelectionPresentation\.(emptyStateTitle|pickerLabel|selectedDevicePlaceholder|unknownDeviceName|recommendationText)|skipButtonTitle|canSkipWhenNotGranted|buttonTitle\(isGranted:|screenContextInfoMessage' \
  VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift

require_patterns \
  "macOS onboarding permissions use shared permission timing policy" \
  VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift \
  'VoiceInkMacOSPermissionTimingPolicy\.pollingInterval' \
  'VoiceInkMacOSPermissionTimingPolicy\.relaunchRequiredDelay'

reject_pattern \
  "macOS onboarding permissions avoid shell-only permission presentation copy" \
  'struct +OnboardingPermission[[:space:]:{]|enum +PermissionType|"(Microphone Access|Microphone Selection|Accessibility Access|Input Monitoring|Screen Context \(Optional\)|Keyboard Shortcut|Enable your microphone to start speaking and converting your voice to text instantly\.|Select the audio input device you want to use with roma-just-talk\.|Add roma-just-talk to Accessibility, then turn its switch on\.|Allow roma-just-talk to detect your recording shortcut while other apps are active\.|Enable screen context only if you want roma-just-talk to use visible text for transcript enhancement\.|Set up a keyboard shortcut to quickly access roma-just-talk from anywhere\.|No microphones found|Microphone:|Select Device|Unknown Device|For best results, using your Mac'\''s built-in microphone is recommended\.|Skip for now|Relaunch to Apply|Set Shortcut|Grant|Enable)"' \
  VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift

reject_pattern \
  "macOS onboarding permissions avoid shallow button-title wrappers" \
  'private func +getButtonTitle\(' \
  VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift

require_pattern \
  "shared macOS permission settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSPermissionSettingsPresentation|VoiceInkMacOSPermissionSettingsCardPresentation|VoiceInkMacOSPermissionTimingPolicy|VoiceInkMacOSPermissionPollingState|headerIconSystemName|inputMonitoringCard|screenContextCard|relaunchRequiredMessage|pollingInterval|refreshPollLimit|consumePoll' \
  VoiceInkCore/Sources/VoiceInkCore/PermissionPresentation.swift

require_pattern \
  "macOS permissions settings uses shared presentation" \
  'VoiceInkMacOSPermissionSettingsPresentation\.(headerIconSystemName|inputMonitoringCard|microphoneCard|accessibilityCard|screenContextCard)|presentation\.buttonTitle\(requiresRelaunch:' \
  VoiceInk/Views/PermissionsView.swift

require_patterns \
  "macOS permissions settings uses shared permission timing and polling state" \
  VoiceInk/Views/PermissionsView.swift \
  'VoiceInkMacOSPermissionTimingPolicy\.pollingInterval' \
  'VoiceInkMacOSPermissionTimingPolicy\.relaunchRequiredDelay' \
  'VoiceInkMacOSPermissionTimingPolicy\.manualRefreshAnimationResetDelay' \
  'VoiceInkMacOSPermissionPollingState\.stopped' \
  'permissionRefreshPollingState = \.started\(\)' \
  'permissionRefreshPollingState\.consumePoll\(\)'

require_patterns \
  "macOS permission refresh center uses shared permission timing and polling state" \
  VoiceInk/Services/PermissionFlowGuide.swift \
  'VoiceInkMacOSPermissionTimingPolicy\.pollingInterval' \
  'VoiceInkMacOSPermissionTimingPolicy\.floatingAuthorizationPanelDelay' \
  'VoiceInkMacOSPermissionTimingPolicy\.openPermissionsGrantMicrophoneDelay' \
  'VoiceInkMacOSPermissionPollingState\.stopped' \
  'pollingState = \.started\(\)' \
  'pollingState\.consumePoll\(\)'

require_pattern \
  "core checks execute permission timing and polling tests" \
  'PermissionPresentationTests\.testMacOSPermissionTimingPolicyPreservesPollingAndRelaunchDelays|PermissionPresentationTests\.testMacOSPermissionPollingStateStopsAfterConfiguredPollLimit' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared permission timing and polling policy" \
  'macOS permission polling countdown/timing policy|VoiceInkMacOSPermissionPollingState' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS permissions settings avoids shell-only permission presentation copy" \
  '"(App Permissions|Microphone and shortcut access are needed for recording\. Screen context is optional\.|Input Monitoring Access|Allow roma-just-talk to listen for your recording hotkey globally|Microphone Access|Allow roma-just-talk to record your voice for transcription|Accessibility Access|Add roma-just-talk to Accessibility, then turn its switch on|Screen Context \(Optional\)|Use visible screen text to improve transcript enhancement when you choose\.|Relaunch to Apply|Grant|Enable|If you already turned this on in System Settings, relaunch roma-just-talk to activate it\.)"|systemName: "arrow\.clockwise"|systemName: "checkmark\.seal\.fill"|systemName: "xmark\.seal\.fill"|systemName: "arrow\.right"' \
  VoiceInk/Views/PermissionsView.swift

reject_pattern \
  "macOS permission shells avoid duplicate polling and relaunch timing literals" \
  'withTimeInterval: 0\.5|deadline: \.now\(\) \+ (0\.25|0\.2|6\.0)|pollsRemaining = 120|permissionRefreshPollsRemaining' \
  VoiceInk/Services/PermissionFlowGuide.swift \
  VoiceInk/Views/PermissionsView.swift \
  VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift

reject_pattern \
  "iOS model download views avoid shell-only downloaded/progress state assembly" \
  'VoiceInkWhisperModelDownloadState\.simple|isDownloadingByModelID|downloadProgressByModelID|model\.isDownloaded\(in:|modelManager\.isDownloading\[[^]]+\] == true|modelManager\.downloadProgress\[[^]]+\]' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS model download views avoid raw download-state presentation branching" \
  '(downloadState|baseModelDownloadState)\.(isDownloaded|isDownloading|progress\.isActive|progress\.compactStatusText|progress\.percentText|progress\.fraction)|VoiceInkWhisperModelDownloadProgress\.downloadActionTitle' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "shared local model row presentation exposes one action enum" \
  'VoiceInkWhisperModelDownloadRowAction' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared local model deletion policy lives in VoiceInkCore" \
  'VoiceInkWhisperModelDeletion(Policy|Plan|Action)' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared local model deletion policy owns downloaded-state lookup" \
  'for model: VoiceInkWhisperModelFileSpec' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "core check runner executes local model deletion policy test" \
  'testSimpleDownloadDeletionPolicyPreservesIOSDeleteIntent' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "shared local model row presentation avoids shallow action booleans" \
  'public var +(isDownloaded|canStartDownload|canCancelDownload|canDeleteDownloadedModel)\b' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "iOS model download views switch on shared row action" \
  'switch presentation\.action' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS model download views avoid shallow row action booleans" \
  'presentation\.(isDownloaded|canStartDownload|canCancelDownload|canDeleteDownloadedModel)\b' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "platform model download progress avoids shell-only key math" \
  '"_(main|coreml)"|modelName \+ "_|model\.name \+ "_|Int\(\(modelManager\.downloadProgress' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS model download views avoid duplicate prompt copy" \
  'To enable offline transcription, a .* model needs to be downloaded|Download Model \(' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS model download views avoid shallow download task wrappers" \
  'private func +downloadModel\(' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS model download views avoid duplicate action icon names" \
  '"(checkmark\.circle\.fill|xmark\.circle\.fill|icloud\.and\.arrow\.down|arrow\.down\.circle\.fill)"' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS local model views avoid duplicate operation confirmation copy" \
  '\.alert\("Download Model"|\.alert\("Delete Model"|This will remove the model from your device|Button\("Download"\)|Button\("Delete"\)|Button\("Cancel"' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS model download views avoid duplicate compact status copy" \
  'Downloading\.\.\.' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "macOS model cards avoid duplicate compact status copy" \
  'Downloading\.\.\.' \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

reject_pattern \
  "macOS model cards avoid shell-only model-card presentation copy" \
  '"(Speed|Accuracy|Download|Edit Model|Delete Model|Show in Finder|Imported local model|Custom Provider|OpenAI Compatible|Native Apple|On-Device|macOS 26\+)"' \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  VoiceInk/Views/AI\ Models/CustomModelCardView.swift \
  VoiceInk/Views/AI\ Models/NativeModelCardView.swift

reject_pattern \
  "macOS model management avoids shell-only delete-confirmation copy" \
  '"(Delete|Delete Model|Delete Custom Model)"|Are you sure you want to delete the (custom )?model' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

reject_pattern \
  "iOS local model shell avoids duplicate operation alert copy" \
  'Download Error|Download failed:|Server error during download|No file received|Failed to save model:|Failed to delete model:|An unknown error occurred\.' \
  iOS/VoiceInk-ios/LocalModelManager.swift \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "platform model management avoids shell-only filter enum" \
  'enum ModelFilter' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

reject_pattern \
  "macOS model management avoids shell-owned filter membership policy" \
  'recommendedNames|recommendedOrder|provider == \.(whisper|nativeApple|fluidAudio|custom)|CloudProviderRegistry\.provider\(for:' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

reject_pattern \
  "platform model management avoids duplicate shared model copy" \
  '"(Model Settings|Default Model|Set as Default|No model selected|Import Local Model…|Only OpenAI-compatible transcription APIs are supported\.|Local Models|Manage Local Models|Cloud Models|Manage Cloud Models|Speed|Accuracy|Download|Edit Model|Delete Model|Delete Custom Model|Show in Finder|Imported local model|Custom Provider|OpenAI Compatible|Native Apple|On-Device|macOS 26\+)"|Are you sure you want to delete the (custom )?model' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift \
  VoiceInk/Views/AI\ Models/CustomModelCardView.swift \
  VoiceInk/Views/AI\ Models/NativeModelCardView.swift \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift \
  iOS/VoiceInk-ios/SettingsView.swift \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/APIKeysView.swift

require_patterns \
  "macOS cloud model card uses shared provider-role display name" \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  'VoiceInkProviderAPIKeyCardPresentation\(providerDisplayName: model\.provider\.apiKeyProviderName\)' \
  'Label\(model\.provider\.apiKeyProviderName, systemImage: "cloud"\)'

reject_pattern \
  "macOS cloud model card avoids shell-only provider raw display" \
  'model\.provider\.rawValue' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared draft policy" \
  'apiKeyFormState\.draft' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared API-key form state" \
  'VoiceInkProviderAPIKeyFormState|apiKeyFormState' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card reads verification progress through shared form state" \
  'apiKeyFormState\.verificationProgress' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared verification progress presentation" \
  'macOSVerifyButtonTitle|macOSInlineFeedback' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS provider API-key verification tone color lives in shell adapter" \
  'extension VoiceInkProviderAPIKeyVerificationTone' \
  VoiceInk/Views/AI\ Models/ProviderTone+macOS.swift

require_pattern \
  "macOS AI connection tone color lives in shell adapter" \
  'extension VoiceInkAIEnhancementConnectionStatusTone' \
  VoiceInk/Views/AI\ Models/ProviderTone+macOS.swift

require_pattern \
  "macOS provider tone adapter exposes status colors" \
  'macOSStatusColor' \
  VoiceInk/Views/AI\ Models/ProviderTone+macOS.swift

reject_pattern \
  "macOS provider views avoid duplicate tone color adapters" \
  'func +color\(for tone: VoiceInkProviderAPIKeyVerificationTone\)|extension VoiceInkAIEnhancementConnectionStatusTone|var +macOSStatusColor: Color' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS cloud API-key card uses shared verification application plan" \
  'verificationApplicationPlan' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS API-key manager applies shared provider verification plan" \
  'applyProviderVerificationPlan|VoiceInkProviderAPIKeyVerificationApplicationPlan|successPersistenceApplicationPlan|persistenceApplicationPlan\.actions|persistVerificationFlag' \
  VoiceInk/Services/APIKeyManager.swift

require_pattern \
  "macOS API-key manager applies shared AI enhancement verification plan" \
  'applyAIEnhancementVerificationPlan|VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan|plan\.runtimeAPIKey|plan\.keyToSave' \
  VoiceInk/Services/APIKeyManager.swift

require_pattern \
  "shared AI enhancement provider-key change request lives in VoiceInkCore" \
  'VoiceInkAIEnhancementProviderKeyChangeRequest|notificationName = Notification\.Name\("aiProviderKeyChanged"\)' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS app notifications use shared AI enhancement provider-key request name" \
  'aiProviderKeyChanged = VoiceInkAIEnhancementProviderKeyChangeRequest\.notificationName' \
  VoiceInk/Notifications/AppNotifications.swift

reject_pattern \
  "macOS app notification shell avoids duplicate AI enhancement provider-key request name" \
  'Notification\.Name\("aiProviderKeyChanged"\)' \
  VoiceInk/Notifications/AppNotifications.swift

require_pattern \
  "core checks execute AI enhancement provider-key request test" \
  'AIProviderCatalogTests\.testAIEnhancementProviderKeyChangeRequestPreservesMacOSNotificationName' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS cloud API-key card delegates verification persistence to API-key manager" \
  'APIKeyManager\.shared\.applyProviderVerificationPlan\(' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shell-owned verification persistence sequencing" \
  'plan\.shouldMarkKeyVerified|plan\.keyToSave|saveAPIKey\(keyToSave' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared verification start plan" \
  'verificationStartPlan|missingCandidatePolicy: \.keepCurrentState' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared stored-key verifier" \
  'verifyStoredAPIKeyDetailed\(keyToVerify, for: provider\)' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shell-owned API-key form state machine fields" \
  '@State private var +(apiKey|verificationProgress)\b' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shallow API-key verification wrappers" \
  'private var +(isVerifying|canVerifyAPIKey)\b' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shallow shared API-key pass-through properties" \
  'private var +(apiKeyDraft|apiKeyCardPresentation)\b' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shell-owned verification start branching" \
  'apiKeyFormState = apiKeyFormState\.verifying\(\)|guard let keyToVerify = [A-Za-z0-9]+\.verificationCandidate' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "shared cloud API-key card presentation lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyCardPresentation|apiKeyFieldPlaceholder|configureButtonSystemImageName|removeAPIKeyButtonSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "macOS cloud API-key card uses shared card presentation" \
  'VoiceInkProviderAPIKeyCardPresentation|apiKeyCardPresentation\.(configureButtonTitle|apiKeyFieldPlaceholder|removeAPIKeyButtonTitle)' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shell-only verification status and copy" \
  'enum +VerificationStatus|verificationStatus|verificationError|Verifying\.\.\.|Verification failed|API key verified successfully!|Unsupported provider|keyToSaveAfterSuccessfulVerification|result\.isValid' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shell-only card copy" \
  '"(Configure|Remove API Key|API Key Configuration|Enter your .* API key)"|systemName: "gear"|systemImage: "trash"' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shell-only stored-key resolution" \
  'VoiceInkAPIKeyReference\.resolvedValue|func +verifyAPIKey\(_ key: String\)|cloudProvider\.verifyAPIKey' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  VoiceInk/Transcription/Cloud/CloudProvider.swift

require_patterns \
  "shared transcription provider recorded-file and streaming-only support lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift \
  'supportsRecordedFileTranscription' \
  'isStreamingOnly'

require_pattern \
  "macOS transcription model uses shared recorded-file support policy" \
  'coreTranscriptionModelProviderRole\.supportsRecordedFileTranscription' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS transcription model uses shared streaming-only support policy" \
  'coreTranscriptionModelProviderRole\.isStreamingOnly' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS cloud provider uses shared streaming-only support policy" \
  'provider\.isStreamingOnly' \
  VoiceInk/Transcription/Cloud/CloudProvider.swift

reject_pattern \
  "macOS transcription model avoids cloud-registry model facts" \
  'CloudProviderRegistry\.provider\(for: provider\)' \
  VoiceInk/Models/TranscriptionModel.swift

reject_context_pattern \
  "macOS transcription model avoids shell-only recorded-file support registry lookup" \
  'var supportsRecordedFileTranscription' \
  'guard let cloudProvider|cloudProvider\.isStreamingOnly' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "shared transcription provider API error domains live in VoiceInkCore" \
  'apiErrorDomain|requiredAPIErrorDomain' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift

require_pattern \
  "shared remote transcription service uses provider API error-domain metadata" \
  'defaultOpenAICompatibleErrorDomain|providerAPIErrorDomain\(defaultingTo:' \
  VoiceInkCore/Sources/VoiceInkCore/AudioTranscriptionService.swift

require_pattern \
  "macOS cloud provider uses shared API error-domain mapping" \
  'coreTranscriptionModelProvider\?\.apiErrorDomain' \
  VoiceInk/Transcription/Cloud/CloudProvider.swift

reject_pattern \
  "macOS cloud provider avoids shell-only API error-domain mapping" \
  '"(GroqAPI|DeepgramAPI|GeminiAPI|MistralAPI|ElevenLabsAPI|SonioxAPI|SpeechmaticsAPI|AssemblyAIAPI|XAIAPI)"' \
  VoiceInk/Transcription/Cloud/CloudProvider.swift

reject_pattern \
  "shared remote transcription service avoids provider API error-domain literals" \
  '"(MistralAPI|AssemblyAIAPI|XAIAPI)"' \
  VoiceInkCore/Sources/VoiceInkCore/AudioTranscriptionService.swift

reject_pattern \
  "shared remote transcription clients avoid provider API error-domain literals" \
  '"(DeepgramAPI|GeminiAPI|MistralAPI|ElevenLabsAPI|SonioxAPI|SpeechmaticsAPI|AssemblyAIAPI|XAIAPI)"' \
  VoiceInkCore/Sources/VoiceInkCore/DeepgramTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/GeminiTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/MistralTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/ElevenLabsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SonioxTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SpeechmaticsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/AssemblyAITranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/XAITranscriptionClient.swift

require_pattern \
  "shared API-key verification policy owns common verification result mapping" \
  'VoiceInkAPIKeyVerificationPolicy|missingAPIKeyResult|verificationResult|missingHTTPResponseMessage|failureResult|errorMessage\(data:' \
  VoiceInkCore/Sources/VoiceInkCore/APIKeyVerificationPolicy.swift

require_pattern \
  "shared provider verification clients use shared API-key verification policy" \
  'VoiceInkAPIKeyVerificationPolicy\.verify' \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/DeepgramTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/GeminiTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/MistralTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/ElevenLabsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SonioxTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SpeechmaticsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/AssemblyAITranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/XAITranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyVerifier.swift

section "obsolete standalone Cartesia API-key client module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/CartesiaAPIKeyClient.swift

require_pattern \
  "Cartesia API-key request builder lives with provider verifier" \
  'VoiceInkCartesiaRequestBuilder|VoiceInkCartesiaClient|Cartesia-Version|cartesiaVoicesURL' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyVerifier.swift

section "obsolete standalone OpenAI-compatible models request module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleModelsRequest.swift

require_patterns \
  "OpenAI-compatible models request builder lives with its client" \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleClient.swift \
  'VoiceInkOpenAICompatibleModelsRequestBuilder' \
  'openAICompatibleModelsURL' \
  'Authorization' \
  'VoiceInkOpenAICompatibleClient'

require_pattern \
  "core checks execute API-key verification policy tests" \
  'APIKeyVerificationPolicyTests\.testBlankAPIKeyResultPreservesSharedFailureCopy|APIKeyVerificationPolicyTests\.testVerificationResultRejectsMissingHTTPResponse|APIKeyVerificationPolicyTests\.testVerificationResultAcceptsHTTP2xxResponses|APIKeyVerificationPolicyTests\.testVerificationResultReturnsHTTPBodyForFailure|APIKeyVerificationPolicyTests\.testVerificationResultFallsBackToHTTPStatusForNonUTF8FailureBody|APIKeyVerificationPolicyTests\.testFailureResultUsesLocalizedDescription' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "shared provider verification clients avoid duplicate API-key verification result mapping" \
  'API key is missing or empty\.|No HTTP response received\.|String\(data: data, encoding: \.utf8\) \?\? "HTTP \(http\.statusCode\)"|guard !apiKey\.trimmingCharacters' \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/DeepgramTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/GeminiTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/MistralTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/ElevenLabsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SonioxTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SpeechmaticsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/AssemblyAITranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/XAITranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyVerifier.swift

require_pattern \
  "shared remote HTTP response policy owns success, retry, and provider-domain errors" \
  'VoiceInkRemoteHTTPResponsePolicy|successStatusCodeRange|retryableStatusCode|apiError|responseBodyText|URLError\(\.badServerResponse\)' \
  VoiceInkCore/Sources/VoiceInkCore/RemoteTransport.swift

require_pattern \
  "direct remote clients use shared validated request helper" \
  'VoiceInkRetriedRequest\.validatedData' \
  VoiceInkCore/Sources/VoiceInkCore/DeepgramTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/GeminiTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleClient.swift

require_pattern \
  "shared remote retry helper owns retry classification and validated responses" \
  'VoiceInkRemoteHTTPResponsePolicy\.(retryableStatusCode|apiError|validateSuccess)|validatedData|validatedUpload' \
  VoiceInkCore/Sources/VoiceInkCore/RemoteTransport.swift

require_pattern \
  "shared retried remote transcription clients use validated retry helper" \
  'VoiceInkRetriedRequest\.validated(Data|Upload)' \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/MistralTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/ElevenLabsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SonioxTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SpeechmaticsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/AssemblyAITranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/XAITranscriptionClient.swift

require_pattern \
  "shared remote polling policy owns timeout, cadence, and HTTP validation" \
  'VoiceInkRemotePollingPolicy|defaultIntervalNanoseconds|pollValidatedData|VoiceInkRemoteHTTPResponsePolicy\.validateSuccess|URLError\(\.timedOut\)' \
  VoiceInkCore/Sources/VoiceInkCore/RemoteTransport.swift

reject_file VoiceInkCore/Sources/VoiceInkCore/RemoteHTTPResponsePolicy.swift
reject_file VoiceInkCore/Sources/VoiceInkCore/RemotePollingPolicy.swift
reject_file VoiceInkCore/Sources/VoiceInkCore/RetriedUpload.swift

require_pattern \
  "shared long-running remote transcription clients use shared polling policy" \
  'VoiceInkRemotePollingPolicy\.pollValidatedData' \
  VoiceInkCore/Sources/VoiceInkCore/SonioxTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SpeechmaticsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/AssemblyAITranscriptionClient.swift

require_pattern \
  "shared OpenAI-compatible transcription client uses shared retry helper" \
  'VoiceInkRetriedRequest\.validatedData' \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleTranscriptionClient.swift

require_pattern \
  "core checks execute remote HTTP response policy tests" \
  'RemoteHTTPResponsePolicyTests\.testValidateSuccessAcceptsHTTP2xxResponses|RemoteHTTPResponsePolicyTests\.testValidateSuccessRejectsNonHTTPResponses|RemoteHTTPResponsePolicyTests\.testValidateSuccessThrowsProviderNSErrorForNon2xxBody|RemoteHTTPResponsePolicyTests\.testAPIErrorUsesEmptyMessageForNonUTF8Body|RemoteHTTPResponsePolicyTests\.testRetryableStatusCodeMatchesSharedRemoteRetryPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute validated retried request tests" \
  'RetriedRequestTests\.testValidatedDataReturnsBodyAfterHTTP2xx|RetriedRequestTests\.testValidatedDataThrowsProviderNSErrorForNon2xx' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute remote polling policy tests" \
  'RemotePollingPolicyTests\.testPollReturnsFinishedResultWithoutSleeping|RemotePollingPolicyTests\.testPollSleepsAndRetriesUntilFinished|RemotePollingPolicyTests\.testPollTimesOutAfterPendingDecision' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute OpenAI-compatible transcription retry helper test" \
  'RemoteProviderRequestTests\.testOpenAICompatibleTranscriptionClientUsesSharedRetryRequest' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute OpenAI-compatible chat HTTP response validation test" \
  'RemoteProviderRequestTests\.testOpenAICompatibleClientUsesSharedHTTPResponseValidationForChatErrors' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "direct remote clients avoid duplicate HTTP response validation" \
  'URLSession\.shared\.data\(for: request\)|VoiceInkRemoteHTTPResponsePolicy\.validateSuccess|guard let http = response as\? HTTPURLResponse|guard \(200..<300\)\.contains\(http\.statusCode\)|String\(data: data, encoding: \.utf8\) \?\? ""|NSError\(' \
  VoiceInkCore/Sources/VoiceInkCore/DeepgramTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/GeminiTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleClient.swift

reject_pattern \
  "shared OpenAI-compatible transcription client avoids duplicate retry loop" \
  'private static func data\(|Task\.sleep|pow\(2\.0|URLSessionConfiguration\.ephemeral|VoiceInkRemoteHTTPResponsePolicy\.(retryableStatusCode|apiError)' \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleTranscriptionClient.swift

reject_pattern \
  "retried remote transcription clients avoid raw retried response handling" \
  'VoiceInkRetriedRequest\.(data|upload)\(|VoiceInkRemoteHTTPResponsePolicy\.validateSuccess' \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/MistralTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/ElevenLabsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SonioxTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SpeechmaticsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/AssemblyAITranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/XAITranscriptionClient.swift

reject_pattern \
  "shared remote transcription clients avoid provider-local HTTP response validators" \
  'private static func validate\(' \
  VoiceInkCore/Sources/VoiceInkCore/SonioxTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SpeechmaticsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/AssemblyAITranscriptionClient.swift

reject_pattern \
  "long-running remote transcription clients avoid provider-local polling loops" \
  'while true|let start = Date\(\)|Date\(\)\.timeIntervalSince\(start\)|Task\.sleep\(nanoseconds: 1_000_000_000\)|URLSession\.shared\.data\(for: request\)' \
  VoiceInkCore/Sources/VoiceInkCore/SonioxTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/SpeechmaticsTranscriptionClient.swift \
  VoiceInkCore/Sources/VoiceInkCore/AssemblyAITranscriptionClient.swift

reject_pattern \
  "shared remote retry helpers avoid duplicate retry status sets" \
  'private static let retryableStatusCodes' \
  VoiceInkCore/Sources/VoiceInkCore/RemoteTransport.swift \
  VoiceInkCore/Sources/VoiceInkCore/OpenAICompatibleTranscriptionClient.swift

require_pattern \
  "shared custom cloud model backup record owns export/import shape" \
  'struct VoiceInkCustomCloudModelBackup' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model import plan exists" \
  'struct VoiceInkCustomCloudModelImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model backup exposes import plan" \
  'var importPlan: VoiceInkCustomCloudModelImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model import plan owns API-key restore decision" \
  'apiKeyToRestore' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model stored record owns persistence shape and legacy API-key migration policy" \
  'struct VoiceInkCustomCloudModelStoredRecord|legacyAPIKeyForKeychainMigration|decodeIfPresent\(String\.self, forKey: \.apiKey\)' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage owns defaults key and JSON load-save loop" \
  'VoiceInkCustomCloudModelStorage' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage owns raw defaults key" \
  'userDefaultsKey = "customCloudModels"' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage exposes JSON load helper" \
  'func loadModels' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage reads raw defaults data" \
  'defaults\.data\(forKey: userDefaultsKey\)' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage decodes model arrays" \
  'decoder\.decode\(\[Model\]\.self, from: data\)' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage exposes JSON save helper" \
  'func saveModels' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage encodes model arrays" \
  'encoder\.encode\(models\)' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage writes raw defaults data" \
  'defaults\.set\(data, forKey: userDefaultsKey\)' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage exposes clear helper" \
  'func clear' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model storage clears raw defaults key" \
  'defaults\.removeObject\(forKey: userDefaultsKey\)' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model form presentation owns defaults and copy" \
  'VoiceInkCustomCloudModelFormPresentation|defaultAPIEndpoint|defaultModelName|keychainSaveFailureMessage|submitButtonSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud transcription policy lives in VoiceInkCore" \
  'VoiceInkCustomCloudTranscriptionPolicy|openAICompatibleOptions' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud transcription policy owns OpenAI-compatible request defaults" \
  'openAICompatibleResponseFormat: "json"|openAICompatibleTemperature: "0"|openAICompatibleAllowsPlainTextFallback: false' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud transcription policy owns custom endpoint and error domain copy" \
  'apiErrorDomain = "CustomWhisperTranscriptionService"|invalidEndpointDescription = "Invalid API endpoint URL"|endpointURL' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud transcription policy owns empty-result policy" \
  'acceptsTranscriptionText' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "macOS custom cloud transcription uses shared request policy" \
  'VoiceInkCustomCloudTranscriptionPolicy\.(endpointURL|openAICompatibleOptions|acceptsTranscriptionText|apiErrorDomain)' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift

require_pattern \
  "core checks execute custom cloud transcription policy tests" \
  'CustomCloudModelPolicyTests\.testCustomCloudTranscriptionPolicyPreservesOpenAICompatibleRequestDefaults|CustomCloudModelPolicyTests\.testCustomCloudTranscriptionPolicyClassifiesEndpointAndText' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute custom cloud model storage round-trip test" \
  'CustomCloudModelPolicyTests\.testCustomCloudModelStorageUsesSharedDefaultsKeyAndRoundTripsRecords' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute custom cloud model storage clear test" \
  'CustomCloudModelPolicyTests\.testCustomCloudModelStorageCanClearSharedDefaultsKey' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS custom cloud transcription avoids shell-owned request policy" \
  '"CustomWhisperTranscriptionService"|"Invalid API endpoint URL"|responseFormat: "json"|temperature: "0"|allowPlainTextFallback: false|!text\.isEmpty|\(100\.\.\.599\)\.contains\(error\.code\)' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift

require_pattern \
  "macOS custom cloud model form uses shared presentation" \
  'VoiceInkCustomCloudModelFormPresentation\.macOS|presentation\.(defaultAPIEndpoint|defaultModelName|buttonTitle|title|compatibilityWarningText|displayNameFieldTitle|apiEndpointFieldTitle|apiKeyFieldTitle|modelNameFieldTitle|multilingualToggleTitle|cancelButtonTitle|submitButtonTitle|submitButtonSystemImageName|validationAlertTitle|validationAlertDismissButtonTitle|defaultModelDescription|keychainSaveFailureMessage)' \
  "VoiceInk/Views/AI Models/AddCustomModelView.swift"

require_pattern \
  "macOS custom cloud model form uses shared required-field policy" \
  'VoiceInkCustomCloudModelPolicy\.hasRequiredFields\(currentDraft\)' \
  "VoiceInk/Views/AI Models/AddCustomModelView.swift"

reject_pattern \
  "macOS custom cloud model form avoids shallow validity wrapper" \
  'private +var +isFormValid\b' \
  "VoiceInk/Views/AI Models/AddCustomModelView.swift"

reject_pattern \
  "macOS custom cloud model form avoids shell-only defaults and copy" \
  '"(https://api\.example\.com/v1/audio/transcriptions|large-v3-turbo|Add Model|Edit Model|Add Custom Model|Edit Custom Model|Only OpenAI-compatible transcription APIs are supported|Display Name|My Custom Model|API Endpoint|API Key|your-api-key|Model Name|whisper-1|Multilingual Model|Cancel|Update Model|Validation Errors|OK|Custom transcription model|Failed to securely save API Key to Keychain\. Please check your system settings or try again\.)"' \
  "VoiceInk/Views/AI Models/AddCustomModelView.swift"

reject_pattern \
  "macOS custom cloud model form avoids duplicate action icon names" \
  '"(plus|xmark|exclamationmark\.triangle\.fill|plus\.circle\.fill|checkmark\.circle\.fill)"' \
  "VoiceInk/Views/AI Models/AddCustomModelView.swift"

require_pattern \
  "macOS custom cloud model Codable delegates stored shape to shared core" \
  'VoiceInkCustomCloudModelStoredRecord\(from: decoder\)|legacyAPIKeyForKeychainMigration|VoiceInkCustomCloudModelStoredRecord\(' \
  VoiceInk/Models/TranscriptionModel.swift

reject_pattern \
  "macOS custom cloud model Codable avoids shell-owned legacy API-key decode policy" \
  'decodeIfPresent\(String\.self, forKey: \.apiKey\)|case +apiKey' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS custom cloud model manager uses shared storage load" \
  'VoiceInkCustomCloudModelStorage\.loadModels' \
  VoiceInk/Transcription/Cloud/CustomCloudModelManager.swift

require_pattern \
  "macOS custom cloud model manager uses shared storage save" \
  'VoiceInkCustomCloudModelStorage\.saveModels' \
  VoiceInk/Transcription/Cloud/CustomCloudModelManager.swift

reject_pattern \
  "macOS custom cloud model manager avoids shell-owned defaults key and JSON persistence loop" \
  'customModelsKey|"customCloudModels"|UserDefaults\.standard|data\(forKey:|set\(data, forKey:|JSONDecoder\(\)\.decode|JSONEncoder\(\)\.encode' \
  VoiceInk/Transcription/Cloud/CustomCloudModelManager.swift

require_pattern \
  "macOS backup file uses shared custom cloud model backup record" \
  'VoiceInkCustomCloudModelBackup' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS custom model export adapts to shared backup record" \
  'VoiceInkCustomCloudModelBackup\(model: \$0\)' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS custom model import consumes shared import plan" \
  'let importPlan = self\.importPlan' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS custom model import restores API key from shared import plan" \
  'importPlan\.apiKeyToRestore' \
  VoiceInk/Services/BackupTypes.swift

reject_pattern \
  "macOS backup types avoid shell-only custom model backup policy" \
  'struct +CustomModelBackup|apiEndpoint\.trimmingCharacters|modelName\.trimmingCharacters|if let apiKey, !apiKey\.isEmpty|normalizedAPIEndpointForImport|normalizedModelNameForImport|apiKeyForImport' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "shared settings backup policy owns taxonomy, presentation, import diagnostics, and import summary" \
  'VoiceInkSettingsBackupCategory|VoiceInkSettingsBackupImportPolicy|VoiceInkSettingsBackupImportDiagnostics|VoiceInkSettingsBackupImportError|VoiceInkSettingsBackupPresentation|categorySummary|needsAPIKeyReminder|defaultFileName|importSuccessInformativeText|customPromptsImportedMessage|dictionaryEntriesImportedMessage|Custom Model Definitions' \
  VoiceInkCore/Sources/VoiceInkCore/SettingsBackupPolicy.swift

require_pattern \
  "macOS import/export uses shared settings backup policy and presentation" \
  'VoiceInkSettingsBackupCategory|VoiceInkSettingsBackupImportPolicy\.needsAPIKeyReminder|VoiceInkSettingsBackupPresentation\.macOS|backupPresentation\.(defaultFileName|exportPanelTitle|exportSuccessMessage|importPanelTitle|versionMismatchMessage|importSuccessInformativeText)' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup importer accepts shared settings backup categories" \
  'Set<VoiceInkSettingsBackupCategory>' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "macOS backup importer uses shared import diagnostics" \
  'VoiceInkSettingsBackupImport(Diagnostics|Error)\.(saveFailed|customPromptsImportedMessage|powerModeConfigurationsImportedMessage|noGeneralSettingsMessage|generalSettingsImportedMessage|noVocabularyWordsMessage|noWordReplacementsMessage|noDictionaryEntriesImportedMessage|skippedInvalidReplacementsMessage|dictionaryEntriesImportedMessage|noCustomModelsMessage|customModelsImportedMessage)' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup importer avoids shell-owned import error wrapper" \
  'enum +BackupImportError|saveFailedDescription' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup types avoid shell-only backup category taxonomy" \
  'enum +BackupCategory|"General Settings"|"Custom Prompts"|"Power Mode"|"Dictionary"|"Custom Model Definitions"' \
  VoiceInk/Services/BackupTypes.swift

reject_pattern \
  "macOS import/export avoids shell-only backup presentation copy" \
  '"(VoiceInk_Settings_Backup\.json|Export VoiceInk Settings|Choose a location to save your settings\.|Export Successful|Your settings have been successfully exported to|Export Error|Could not save settings to file|Export Canceled|The settings export operation was canceled\.|Could not encode settings to JSON|Import VoiceInk Settings|Choose a settings backup, then select what you want to import\.|Import Canceled|The settings import operation was canceled\.|Import Error|Could not get the file URL from the open panel\.|Version Mismatch|Proceeding with import, but be aware of potential incompatibilities\.|No settings were imported\.|Select at least one category to import\.|Error importing settings:|The file might be corrupted or not in the correct format\.|Import Settings|Choose what to import from this backup\.|All|Individual categories|Import Successful|IMPORTANT: If you were using AI enhancement features|It is recommended to restart VoiceInk|Configure API Keys)"' \
  VoiceInk/Services/ImportExportService.swift

reject_pattern \
  "macOS backup importer avoids shell-only import diagnostics copy" \
  '"(Failed to save imported|Successfully imported .*custom prompts|Successfully imported .*Power Mode configurations|No general settings found in the imported file\.|Successfully imported general settings\.|No vocabulary words found in the imported file\. Existing items remain unchanged\.|No word replacements found in the imported file\. Existing replacements remain unchanged\.|No new dictionary entries were imported\.|Skipped .* invalid word replacements from the imported file\.|Successfully imported .* vocabulary words and .* word replacements to SwiftData\.|No custom models found in the imported file\.|Successfully imported .* custom model definitions\.)"' \
  VoiceInk/Services/BackupImporter.swift

require_patterns \
  "core checks execute settings backup policy tests" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'SettingsBackupPolicyTests\.testBackupCategoriesPreserveMacOSImportOrderAndTitles' \
  'SettingsBackupPolicyTests\.testBackupImportPolicySummarizesAllAndSelectedCategories' \
  'SettingsBackupPolicyTests\.testBackupImportPolicyRemindsOnlyForAPIKeyDependentCategories' \
  'SettingsBackupPolicyTests\.testBackupImportDiagnosticsPreserveMacOSStatusCopy' \
  'SettingsBackupPolicyTests\.testBackupImportErrorPreservesMacOSSaveFailureCopy' \
  'SettingsBackupPolicyTests\.testBackupPresentationPreservesMacOSPanelAndAlertCopy' \
  'SettingsBackupPolicyTests\.testBackupPresentationBuildsDynamicExportAndImportMessages' \
  'SettingsBackupPolicyTests\.testBackupPresentationBuildsImportSuccessTextWithOptionalAPIKeyReminder'

require_pattern \
  "migration checklist tracks shared settings backup policy" \
  'settings backup category taxonomy, ordered category titles, import/export panel copy, import status/error diagnostic copy, save-failure import error, alert titles/messages, version-mismatch warning, import summary text, API-key-reminder gate, and restart recommendation use `VoiceInkSettingsBackupCategory`/`VoiceInkSettingsBackupImportPolicy`/`VoiceInkSettingsBackupImportDiagnostics`/`VoiceInkSettingsBackupImportError`/`VoiceInkSettingsBackupPresentation`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared general settings backup preferences live in VoiceInkCore" \
  'VoiceInkGeneralSettingsBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings backup import plans live in VoiceInkCore" \
  'VoiceInkGeneralSettingsBackupImportPlans' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings backup policy builds grouped preferences" \
  'static func backupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings backup policy builds import plans" \
  'static func importPlans' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings backup policy applies core preference import plans" \
  'VoiceInkGeneralSettingsCorePreferenceImportResult|static func applyCorePreferenceImportPlans|applyTranscriptionAutoCleanupImportPlan|applyAudioCleanupImportPlan|applyRecordingFeedbackCorePreferenceImportPlan|applyTranscriptionCleanupImportPlan|applyPasteImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "macOS general backup adapts to shared general settings preferences" \
  'generalSettingsBackupPreferences' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS general backup export builds shared general settings preferences" \
  'VoiceInkGeneralSettingsBackupPolicy\.backupPreferences' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS general backup export passes shared general settings preferences" \
  'preferences: generalSettingsBackupPreferences' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS general backup import uses shared general settings import plans" \
  'VoiceInkGeneralSettingsBackupPolicy\.importPlans|generalImportPlans\.(recordingShortcut|macOSShell|transcriptionAutoCleanup|audioCleanup|recordingFeedback|transcriptionCleanup|paste|rollingBuffer)' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "macOS general backup import delegates portable preference writes to shared policy" \
  'VoiceInkGeneralSettingsBackupPolicy\.applyCorePreferenceImportPlans|corePreferenceImportResult\.didImportRollingBufferSetting' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup importer avoids shell-owned general settings sub-plan routing" \
  'VoiceInk(RecordingShortcutPreference|MacOSShellBackupPreference|TranscriptionAutoCleanupPreference|AudioCleanupPreference|RecordingFeedbackPreference|TranscriptionCleanupSettings|PastePreference|RollingBufferPreloadSettings)\.backupImportPlan' \
  VoiceInk/Services/BackupImporter.swift

reject_context_pattern \
  "macOS backup export avoids shell-owned GeneralBackup field emission" \
  'GeneralBackup\(' \
  'primaryRecordingShortcut:|primaryRecordingShortcutRawValue:|isTranscriptionCleanupEnabled:|isSoundFeedbackEnabled:|restoreClipboardAfterPaste:|rollingBufferPreloadModeRawValue:' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "core checks execute general settings backup policy tests" \
  'GeneralSettingsBackupPolicyTests\.testBackupPreferencesPreserveGroupedExportShape|GeneralSettingsBackupPolicyTests\.testImportPlansApplySharedSubPolicies|GeneralSettingsBackupPolicyTests\.testApplyCorePreferenceImportPlansWritesPortablePreferences|GeneralSettingsBackupPolicyTests\.testApplyCorePreferenceImportPlansIgnoresMissingFields' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared general settings backup policy" \
  'general settings backup.*VoiceInkGeneralSettingsBackupPolicy' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared custom prompt presentation owns icon catalog and copy" \
  'VoiceInkCustomPromptPresentation|iconSystemNames|promptGridInfoSystemImageName|promptGridHelpText|deletePromptConfirmationMessage|triggerSummary|addPromptSystemImageName|editActionSystemImageName|deleteActionSystemImageName|closeSystemImageName|addTriggerWordSystemImageName|removeTriggerWordSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPromptPresentation.swift

require_pattern \
  "macOS custom prompt cards use shared presentation" \
  'VoiceInkCustomPromptPresentation\.(triggerSummary|editActionTitle|editActionSystemImageName|deletePromptConfirmationTitle|deletePromptConfirmationMessage|deleteActionTitle|deleteActionSystemImageName|cancelActionTitle|addPromptTitle|addPromptSystemImageName)' \
  VoiceInk/Models/CustomPrompt.swift

require_pattern \
  "macOS prompt editor uses shared presentation" \
  'VoiceInkCustomPromptPresentation\.(editorTitle|closeSystemImageName|defaultIconSystemName|promptNamePlaceholder|promptInstructionsPlaceholder|useSystemTemplateTitle|startWithTemplateTitle|triggerWordPlaceholder|addTriggerWordSystemImageName|removeTriggerWordSystemImageName|noTriggerWordsText|iconSystemNames)' \
  VoiceInk/Views/PromptEditorView.swift

require_pattern \
  "shared prompt trigger-word draft validation lives in VoiceInkCore" \
  'hasTriggerWordDraft' \
  VoiceInkCore/Sources/VoiceInkCore/PromptTriggerPolicy.swift

require_pattern \
  "shared prompt trigger-word add policy lives in VoiceInkCore" \
  'addingTriggerWord' \
  VoiceInkCore/Sources/VoiceInkCore/PromptTriggerPolicy.swift

require_pattern \
  "shared prompt trigger-word removal policy lives in VoiceInkCore" \
  'removingTriggerWord' \
  VoiceInkCore/Sources/VoiceInkCore/PromptTriggerPolicy.swift

require_pattern \
  "shared prompt-trigger settings application state lives in VoiceInkCore" \
  'VoiceInkAIEnhancementPromptSettingsState|settingsStateAfterEnhancementEnabledChange' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "shared AI enhancement API-key validity state planning lives in VoiceInkCore" \
  'settingsStateAfterAPIKeyValidityChange' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "shared prompt-trigger detection settings application uses shared prompt state" \
  'applyingSettingsState|restoringSettingsState|VoiceInkAIEnhancementPromptSettingsState' \
  VoiceInkCore/Sources/VoiceInkCore/PromptTriggerPolicy.swift

require_pattern \
  "macOS prompt editor consumes shared trigger-word draft validation" \
  'VoiceInkPromptTriggerPolicy\.hasTriggerWordDraft' \
  VoiceInk/Views/PromptEditorView.swift

require_pattern \
  "macOS prompt editor consumes shared trigger-word add policy" \
  'VoiceInkPromptTriggerPolicy\.addingTriggerWord' \
  VoiceInk/Views/PromptEditorView.swift

require_pattern \
  "macOS prompt editor consumes shared trigger-word removal policy" \
  'VoiceInkPromptTriggerPolicy\.removingTriggerWord' \
  VoiceInk/Views/PromptEditorView.swift

require_pattern \
  "core checks execute prompt trigger-word removal policy test" \
  'PromptTriggerPolicyTests\.testRemovingTriggerWordPreservesExactMacOSEditingRule' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute prompt-trigger settings state tests" \
  'PromptTriggerPolicyTests\.testDetectedPromptResultAppliesSettingsState|PromptTriggerPolicyTests\.testDetectedPromptResultRestoresSettingsStateIncludingNilPrompt|PromptTriggerPolicyTests\.testNoMatchPromptResultReturnsNoSettingsState' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute enhancement prompt settings state test" \
  'CustomPromptTests\.testCustomPromptPolicyPlansPromptSelectionWhenEnablingEnhancement' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute AI enhancement API-key validity state test" \
  'CustomPromptTests\.testCustomPromptPolicyPlansEnhancementDisableWhenAPIKeyIsInvalid' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute active prompt lookup and icon fallback tests" \
  'CustomPromptTests\.testCustomPromptPolicyFindsActivePromptBySelectedId|CustomPromptTests\.testCustomPromptPolicyBuildsActivePromptIconFallbacks' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute prompt shortcut selection tests" \
  'CustomPromptTests\.testCustomPromptPolicyPlansPromptShortcutSelectionByIndex|CustomPromptTests\.testCustomPromptPolicyRejectsPromptShortcutSelectionOutsidePromptList' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS AI enhancement service consumes shared prompt-trigger settings state" \
  'settingsStateAfterEnhancementEnabledChange|applyingSettingsState|restoringSettingsState|VoiceInkAIEnhancementPromptSettingsState' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service consumes shared API-key validity state planning" \
  'settingsStateAfterAPIKeyValidityChange' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "shared custom prompt policy owns active prompt lookup" \
  'func activePrompt\(' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "shared custom prompt policy owns active prompt icon fallback" \
  'func activePromptIcon\(' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "macOS AI enhancement service consumes shared active prompt lookup" \
  'VoiceInkCustomPromptPolicy\.activePrompt' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS recorder prompt button consumes shared active prompt icon fallback" \
  'VoiceInkCustomPromptPolicy\.activePromptIcon' \
  VoiceInk/Views/Recorder/RecorderComponents.swift

require_pattern \
  "macOS audio import prompt picker consumes shared selection fallback" \
  'VoiceInkCustomPromptPolicy\.selectedPromptIdAfterEnablingEnhancement' \
  VoiceInk/Views/AudioTranscribeView.swift

require_pattern \
  "shared custom prompt policy owns mini-recorder prompt shortcut selection" \
  'settingsStateAfterPromptShortcutSelection' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "macOS AI enhancement service consumes shared prompt shortcut selection" \
  'VoiceInkCustomPromptPolicy\.settingsStateAfterPromptShortcutSelection' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS mini recorder prompt shortcut uses AI enhancement prompt shortcut adapter" \
  'selectPromptFromShortcut' \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift

require_pattern \
  "core checks execute mini-recorder power mode shortcut selection tests" \
  'PowerModePolicyTests\.testPowerModeConfigurationListSelectsMiniRecorderShortcutByEnabledIndex|PowerModePolicyTests\.testPowerModeConfigurationListRejectsMiniRecorderShortcutOutsideEnabledRange' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared Power Mode policy owns mini-recorder shortcut selection" \
  'powerModeConfigurationForMiniRecorderShortcut' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS mini recorder consumes shared Power Mode shortcut selection" \
  'powerModeConfigurationForMiniRecorderShortcut' \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned prompt-trigger settings application policy" \
  'result\.shouldEnableAI|restoredEnhancementState|restoredPromptId|selectedPromptId = result\.selectedPromptId|isEnhancementEnabled && selectedPromptId|VoiceInkCustomPromptPolicy\.selectedPromptIdAfterEnablingEnhancement' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned active prompt lookup" \
  'allPrompts\.first \{ \$0\.id == selectedPromptId \}' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS recorder prompt button avoids shell-owned default prompt icon fallback" \
  'VoiceInkPredefinedPrompts\.defaultPromptId|"checkmark\.seal\.fill"|allPrompts\.first\(where:' \
  VoiceInk/Views/Recorder/RecorderComponents.swift

reject_pattern \
  "macOS audio import prompt picker avoids shell-owned first-prompt fallback" \
  'allPrompts\.first\?\.id' \
  VoiceInk/Views/AudioTranscribeView.swift

reject_pattern \
  "macOS mini recorder avoids shell-owned prompt shortcut selection policy" \
  'allPrompts\.count|allPrompts\[index\]|index < enhancementService\.allPrompts\.count|isEnhancementEnabled = true|setActivePrompt' \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift

reject_pattern \
  "macOS mini recorder avoids shell-owned Power Mode shortcut selection policy" \
  'availableConfigurations\.count|availableConfigurations\[index\]|index < availableConfigurations\.count' \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned API-key invalid disable policy" \
  '!self\.aiService\.isAPIKeyValid|self\.isEnhancementEnabled = false' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS prompt grids use shared presentation" \
  'VoiceInkCustomPromptPresentation\.(promptGridEmptyText|promptGridInfoSystemImageName|promptGridHelpText|addPromptHelpText)' \
  VoiceInk/Views/Components/PromptSelectionGrid.swift

require_pattern \
  "macOS enhancement prompt grid uses shared presentation" \
  'VoiceInkCustomPromptPresentation\.(promptGridEmptyText|promptGridInfoSystemImageName|promptGridHelpText|addPromptSystemImageName)' \
  VoiceInk/Views/EnhancementSettingsView.swift

reject_pattern \
  "macOS custom prompt shell avoids local icon catalog" \
  'enum +PromptIcons|PromptIcons\.allCases|"hand\.thumbsup\.fill"' \
  VoiceInk/Models/CustomPrompt.swift \
  VoiceInk/Views/PromptEditorView.swift

reject_pattern \
  "macOS prompt editor avoids shell-only trigger-word list editing" \
  'triggerWords\.(append|removeAll)' \
  VoiceInk/Views/PromptEditorView.swift

reject_pattern \
  "macOS custom prompt shell avoids duplicate prompt presentation copy" \
  '"(Add New|No prompts available|Double-click to edit • Right-click for more options|Add new prompt|Edit Trigger Words|New Prompt|Edit Prompt|You can only customize the trigger words for system prompts\.|Prompt Name|Brief description|Enter your custom prompt instructions here\.\.\.|Use System Template|Trigger Words|Start with Template|Add trigger word|No trigger words added|Delete Prompt\\?|This action cannot be undone)"' \
  VoiceInk/Models/CustomPrompt.swift \
  VoiceInk/Views/PromptEditorView.swift \
  VoiceInk/Views/Components/PromptSelectionGrid.swift \
  VoiceInk/Views/EnhancementSettingsView.swift

reject_pattern \
  "macOS custom prompt card and editor avoid shell-only action symbols" \
  '"(pencil|trash|plus\.circle\.fill|xmark)"' \
  VoiceInk/Models/CustomPrompt.swift \
  VoiceInk/Views/PromptEditorView.swift

reject_pattern \
  "macOS prompt grids avoid shell-only prompt grid action symbols" \
  '"(info\.circle|plus\.circle\.fill)"' \
  VoiceInk/Views/Components/PromptSelectionGrid.swift \
  VoiceInk/Views/EnhancementSettingsView.swift

require_pattern \
  "migration checklist tracks shared custom prompt presentation gate" \
  'macOS custom prompt icon catalog, prompt-card trigger summary/action symbols, grid empty/help copy and info icon, editor labels/placeholders/help/action symbols, and delete confirmation copy route through `VoiceInkCustomPromptPresentation`' \
  docs/ios-single-repo-migration.md

section "obsolete standalone predefined prompts module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/PredefinedPrompts.swift

require_pattern \
  "predefined prompt metadata lives with custom prompt policy" \
  'VoiceInkPredefinedPrompt|VoiceInkPredefinedPrompts|defaultPromptId|assistantPromptId|VoiceInkPromptTemplates\.macTemplate|VoiceInkAIPrompts\.assistantMode' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "shared custom prompt policy owns startup prompt-store repair" \
  'startupStoreState' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "shared custom prompt policy preserves startup repair ordering" \
  'repairedPredefinedPrompts\(in: loadedPrompts\)' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "macOS AI enhancement service calls shared startup prompt store state" \
  'VoiceInkCustomPromptPolicy\.startupStoreState' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service applies shared startup prompt list" \
  'promptStoreState\.prompts' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service applies shared startup selected prompt" \
  'promptStoreState\.selectedPromptId' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned startup prompt repair" \
  'VoiceInkCustomPromptPolicy\.(repairedSelectedPromptId|repairedPredefinedPrompts)\(' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "core checks execute prompt startup store-state tests" \
  'CustomPromptTests\.testCustomPromptPolicyBuildsStartupStoreStateInMacOSRepairOrder' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared startup prompt-store repair" \
  'startup prompt-store repair ordering' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared active prompt lookup and icon fallback" \
  'active prompt lookup, recorder-button prompt icon fallback, and audio-import prompt picker fallback' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared mini-recorder prompt shortcut selection" \
  'mini-recorder prompt shortcut selection delegates index validation and enable/select state planning to `VoiceInkCustomPromptPolicy`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared API-key validity state planning" \
  'provider-key validity changes delegate enhancement-disable state planning to `VoiceInkCustomPromptPolicy`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared custom prompt policy owns backup export filtering" \
  'exportedCustomPrompts' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "shared custom prompt policy owns backup import merge ordering" \
  'promptsAfterImportingCustomPrompts' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPrompt.swift

require_pattern \
  "macOS settings export uses shared custom prompt export policy" \
  'VoiceInkCustomPromptPolicy\.exportedCustomPrompts' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS settings import uses shared custom prompt import policy" \
  'VoiceInkCustomPromptPolicy\.promptsAfterImportingCustomPrompts' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup shells avoid shell-owned custom prompt import/export policy" \
  'customPrompts\.filter \{ !?\$0\.isPredefined \}|predefinedPrompts \+ backup\.customPrompts' \
  VoiceInk/Services/ImportExportService.swift \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "core checks execute custom prompt backup export policy tests" \
  'CustomPromptTests\.testCustomPromptPolicyExportsOnlyCustomPromptsInStoredOrder' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute custom prompt backup import policy tests" \
  'CustomPromptTests\.testCustomPromptPolicyImportsBackupPromptsAfterCurrentPredefinedPrompts' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared custom prompt backup policy" \
  'backup export filtering and import merge ordering' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS and iOS filler-word settings use shared draft policy" \
  'VoiceInkFillerWords\.normalizedWord' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "shared filler-word insert policy owns duplicate message" \
  'duplicateWordMessage = "This filler word is already in the list\."' \
  VoiceInkCore/Sources/VoiceInkCore/FillerWords.swift

require_pattern \
  "shared filler-word submission policy owns draft and alert plan" \
  'VoiceInkFillerWordSubmissionPlan|submissionPlan|draftAfterSubmit|alertPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/FillerWords.swift

require_pattern \
  "shared filler-word submission policy owns changed-list application" \
  'func updatedWordsIfChanged\(from currentWords: \[String\]\)' \
  VoiceInkCore/Sources/VoiceInkCore/FillerWords.swift

require_pattern \
  "shared filler-word draft state lives in core" \
  'public struct VoiceInkFillerWordDraftState' \
  VoiceInkCore/Sources/VoiceInkCore/FillerWords.swift

require_pattern \
  "shared filler-word draft submission lives in core" \
  'public struct VoiceInkFillerWordDraftSubmission' \
  VoiceInkCore/Sources/VoiceInkCore/FillerWords.swift

require_pattern \
  "shared filler-word draft state owns submit availability" \
  'public var canSubmit: Bool' \
  VoiceInkCore/Sources/VoiceInkCore/FillerWords.swift

require_pattern \
  "shared filler-word draft state owns submission" \
  'public func submitting\(existingWords: \[String\]\) -> VoiceInkFillerWordDraftSubmission' \
  VoiceInkCore/Sources/VoiceInkCore/FillerWords.swift

require_pattern \
  "macOS filler-word storage receives shared submission plan" \
  'func applySubmissionPlan\(_ plan: VoiceInkFillerWordSubmissionPlan\)' \
  VoiceInk/Transcription/Processing/FillerWordManager.swift

require_pattern \
  "macOS filler-word storage applies shared updated words" \
  'plan\.updatedWordsIfChanged\(from: fillerWords\)' \
  VoiceInk/Transcription/Processing/FillerWordManager.swift

require_pattern \
  "iOS filler-word storage receives shared submission plan" \
  'func applyFillerWordSubmissionPlan\(_ plan: VoiceInkFillerWordSubmissionPlan\)' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS filler-word storage applies shared updated words" \
  'plan\.updatedWordsIfChanged\(from: fillerWords\)' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "platform filler-word insertion avoids shell-only insert-plan unpacking" \
  'VoiceInkFillerWords\.insertPlan\(|wordToInsert|duplicateWordMessage' \
  VoiceInk/Transcription/Processing/FillerWordManager.swift \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "platform filler-word storage avoids shell-owned changed-list comparison" \
  'fillerWords != plan\.updatedWords|fillerWords = plan\.updatedWords' \
  VoiceInk/Transcription/Processing/FillerWordManager.swift \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "macOS filler-word view consumes shared draft state submission result" \
  'VoiceInkFillerWordDraftState|draftState\.submitting|draftStateAfterSubmit|alertPresentation' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift

require_pattern \
  "iOS filler-word view consumes shared draft state submission result" \
  'VoiceInkFillerWordDraftState|fillerWordDraftState\.submitting|draftStateAfterSubmit|alertPresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "platform filler-word views avoid shell-owned duplicate alert branching" \
  'duplicateFillerWord' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "shared transcription cleanup presentation lives in VoiceInkCore" \
  'VoiceInkTranscriptionCleanupPresentation|paragraphBreaksToggleTitle|addFillerWordPlaceholder' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "iOS transcription cleanup settings use shared presentation" \
  'VoiceInkTranscriptionCleanupPresentation\.iOS|cleanupPresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS model settings use shared transcription cleanup presentation" \
  'VoiceInkTranscriptionCleanupPresentation\.macOS|cleanupPresentation' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "macOS filler-word settings use shared transcription cleanup presentation" \
  'VoiceInkTranscriptionCleanupPresentation\.macOS|cleanupPresentation' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift

require_pattern \
  "macOS Power Mode settings use shared transcription cleanup presentation" \
  'VoiceInkTranscriptionCleanupPresentation\.macOS|cleanupPresentation' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared macOS cleanup settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSCleanupSettingsPresentation|transcriptRetentionOptions|audioCleanupResultMessage' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "shared macOS cleanup settings owns file-size presentation" \
  'audioCleanupFileSizeText|allowedUnits = \[\.useKB, \.useMB, \.useGB\]' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "shared transcription cleanup backup preferences live in VoiceInkCore" \
  'struct VoiceInkTranscriptionCleanupBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "shared transcription cleanup backup import plan lives in VoiceInkCore" \
  'struct VoiceInkTranscriptionCleanupBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "shared transcription cleanup backup export policy lives in VoiceInkCore" \
  'var backupPreferences: VoiceInkTranscriptionCleanupBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "shared transcription cleanup backup import policy lives in VoiceInkCore" \
  'backupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "shared transcription cleanup backup import prefers modern punctuation mode" \
  'punctuationCleanupMode: preferences\.punctuationCleanupMode' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "shared transcription cleanup backup import keeps legacy punctuation fallback" \
  'removePunctuation\.map' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionCleanupPreferences.swift

require_pattern \
  "shared transcription auto-cleanup backup preferences live in VoiceInkCore" \
  'struct VoiceInkTranscriptionAutoCleanupBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared transcription auto-cleanup backup import plan lives in VoiceInkCore" \
  'struct VoiceInkTranscriptionAutoCleanupBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared transcription auto-cleanup completion action lives in VoiceInkCore" \
  'enum VoiceInkTranscriptionAutoCleanupCompletionAction' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared transcription auto-cleanup completion action policy lives in VoiceInkCore" \
  'completionAction' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared transcription auto-cleanup backup export policy lives in VoiceInkCore" \
  'VoiceInkTranscriptionAutoCleanupBackupPreferences\(' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared transcription auto-cleanup backup import policy lives in VoiceInkCore" \
  'VoiceInkTranscriptionAutoCleanupBackupImportPlan\(' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio cleanup backup preferences live in VoiceInkCore" \
  'struct VoiceInkAudioCleanupBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio cleanup backup import plan lives in VoiceInkCore" \
  'struct VoiceInkAudioCleanupBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio cleanup backup export policy lives in VoiceInkCore" \
  'VoiceInkAudioCleanupBackupPreferences\(' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio cleanup backup import policy lives in VoiceInkCore" \
  'VoiceInkAudioCleanupBackupImportPlan\(' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS audio cleanup settings use shared presentation" \
  'VoiceInkMacOSCleanupSettingsPresentation\.macOS|presentation\.(transcriptToggleTitle|audioRetentionOptions|audioCleanupResultMessage|audioCleanupFileSizeText)' \
  VoiceInk/Views/Settings/AudioCleanupSettingsView.swift

require_pattern \
  "macOS backup export uses shared transcription auto-cleanup backup preferences" \
  'VoiceInkTranscriptionAutoCleanupPreference\.backupPreferences' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup export applies shared transcription auto-cleanup enabled preference" \
  'isTranscriptionCleanupEnabled: preferences\.transcriptionAutoCleanup\.isEnabled' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup export applies shared transcription auto-cleanup retention preference" \
  'transcriptionRetentionMinutes: preferences\.transcriptionAutoCleanup\.retentionMinutes' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup export uses shared audio cleanup backup preferences" \
  'VoiceInkAudioCleanupPreference\.backupPreferences' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup export applies shared audio cleanup enabled preference" \
  'isAudioCleanupEnabled: preferences\.audioCleanup\.isEnabled' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup export applies shared audio cleanup retention preference" \
  'audioRetentionPeriod: preferences\.audioCleanup\.retentionDays' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup export uses shared transcription cleanup backup preferences" \
  'cleanupSettings\.backupPreferences' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup export applies shared transcription cleanup text preference" \
  'isTextFormattingEnabled: preferences\.transcriptionCleanup\.isTextFormattingEnabled' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup export applies shared transcription cleanup punctuation preference" \
  'punctuationCleanupMode: preferences\.transcriptionCleanup\.punctuationCleanupMode' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup export applies shared transcription cleanup legacy punctuation preference" \
  'removePunctuation: preferences\.transcriptionCleanup\.removePunctuation' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup export applies shared transcription cleanup lowercase preference" \
  'lowercaseTranscription: preferences\.transcriptionCleanup\.lowercaseTranscription' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "shared general settings core import reads transcription auto-cleanup plan" \
  'applyTranscriptionAutoCleanupImportPlan\(importPlans\.transcriptionAutoCleanup' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import applies transcription auto-cleanup enabled plan" \
  'VoiceInkTranscriptionAutoCleanupPreference\.saveIsEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "macOS transcription auto cleanup uses shared completion action" \
  'cleanupConfiguration\.completionAction' \
  VoiceInk/Services/TranscriptionAutoCleanupService.swift

reject_pattern \
  "macOS transcription auto cleanup avoids shell-owned completion retention branch" \
  'shouldDeleteCompletedTranscriptionImmediately' \
  VoiceInk/Services/TranscriptionAutoCleanupService.swift

require_pattern \
  "shared general settings core import applies transcription auto-cleanup retention plan" \
  'VoiceInkTranscriptionAutoCleanupPreference\.saveRetentionMinutes' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import reads audio cleanup plan" \
  'applyAudioCleanupImportPlan\(importPlans\.audioCleanup' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import applies audio cleanup enabled plan" \
  'VoiceInkAudioCleanupPreference\.saveIsEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import applies audio cleanup retention plan" \
  'VoiceInkAudioCleanupPreference\.saveRetentionDays' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import reads transcription cleanup plan" \
  'applyTranscriptionCleanupImportPlan\(importPlans\.transcriptionCleanup' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import applies transcription cleanup text plan" \
  'VoiceInkTranscriptionCleanupPreferenceStorage\.saveTextFormattingEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import applies transcription cleanup punctuation plan" \
  'PunctuationCleanupMode\.setCurrent' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import applies transcription cleanup lowercase plan" \
  'VoiceInkTranscriptionCleanupPreferenceStorage\.saveLowercaseTranscription' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

reject_pattern \
  "macOS backup import avoids shell-owned cleanup backup planning" \
  'general\.(isTranscriptionCleanupEnabled|transcriptionRetentionMinutes|isAudioCleanupEnabled|audioRetentionPeriod|isTextFormattingEnabled|punctuationCleanupMode|removePunctuation|lowercaseTranscription)' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import delegates cleanup preference writes to shared policy" \
  'VoiceInkTranscriptionAutoCleanupPreference\.save|VoiceInkAudioCleanupPreference\.save|VoiceInkTranscriptionCleanupPreferenceStorage\.save|PunctuationCleanupMode\.setCurrent' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "shared Power Mode transcription selection lives in VoiceInkCore" \
  'VoiceInkPowerModeTranscriptionSelection|VoiceInkPowerModeTranscriptionModelFacts|VoiceInkPowerModeLanguageControl' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode transcription facts classify provider source policy" \
  'disablesTranscriptionLanguageSelection|prefersNativeAppleEnglishFallback|loadsLocalWhisperModelResource' \
  VoiceInkCore/Sources/VoiceInkCore/LanguageCatalog.swift

require_pattern \
  "shared Power Mode transcription model resource plan lives in VoiceInkCore" \
  'VoiceInkPowerModeTranscriptionModelResourcePlan|VoiceInkPowerModeTranscriptionModelResourceAction|VoiceInkPowerModeTranscriptionModelResourceFacts' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode language application plan lives in VoiceInkCore" \
  'VoiceInkPowerModeLanguageApplicationPlan|modelForLanguageApplication|shouldPostLanguageDidChange' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS Power Mode transcription settings use shared selection policy" \
  'VoiceInkPowerModeTranscriptionSelection|VoiceInkPowerModeTranscriptionModelFacts|languageControl' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS TranscriptionModel adapts Power Mode facts through shared policy" \
  'powerModeTranscriptionModelFacts|powerModeTranscriptionModelResourceFacts' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS Power Mode session uses shared model resource plan" \
  'modelResourcePlan\(for:|applyModelResourcePlan' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session uses shared language application plan" \
  'languageApplicationPlan\(|applyLanguageApplicationPlan' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode transcription settings avoid shell-only language repair branching" \
  'languageSelectionDisabled\(|availableLanguages\(for:|useCompatibleLanguage\(|if +model\.provider == \.gemini|modelInfo\.isMultilingualModel|!modelInfo\.isMultilingualModel|validTranscriptionLanguageOrFallback' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode shells avoid duplicate provider fact classification" \
  'model\.provider == \.(gemini|nativeApple|whisper)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session avoids shell-only model resource branching" \
  'handleModelChange|switch +newModel\.provider|case +\.whisper|case +\.fluidAudio|stateProvider\.currentTranscriptionModel\?\.name != modelName' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session avoids shell-only compatible-language branching" \
  'applyCompatibleLanguage|model\(named:|saveCompatibleLanguage\(|validTranscriptionLanguageOrFallback' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "shared dictionary alert presentation lives in VoiceInkCore" \
  'VoiceInkDictionaryAlertPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared dictionary settings presentation lives in VoiceInkCore" \
  'VoiceInkDictionarySettingsPresentation|vocabularyPlaceholder|wordReplacementHelpText|wordReplacementArrowSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared dictionary settings section selector lives in VoiceInkCore" \
  'VoiceInkDictionarySettingsSection|defaultSelection|presentation\(|in presentation: VoiceInkDictionarySettingsPresentation|case wordReplacements|case vocabulary' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared dictionary quick-add presentation lives in VoiceInkCore" \
  'VoiceInkDictionaryQuickAddPresentation|vocabularyPlaceholder|dismissHintTitle' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement info presentation lives in VoiceInkCore" \
  'VoiceInkWordReplacementInfoPresentation|multipleOriginalsHelpText|examplesTitle' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement edit presentation lives in VoiceInkCore" \
  'VoiceInkWordReplacementEditPresentation|originalFieldTitle|replacementFieldTitle' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary list presentation lives in VoiceInkCore" \
  'VoiceInkVocabularyListPresentation|wordsTitlePrefix|sortHelpText' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary submission policy owns draft and alert plan" \
  'VoiceInkVocabularySubmissionPlan|vocabularySubmissionPlan|draftAfterSubmit|shouldComplete' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary submission policy owns list application" \
  'func updatedWordsIfChanged\(from existingWords: \[String\]\)' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary draft state lives in VoiceInkCore" \
  'public struct VoiceInkVocabularyDraftState' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary draft submission lives in VoiceInkCore" \
  'public struct VoiceInkVocabularyDraftSubmission' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary draft submission preserves submitted draft" \
  'public let submittedDraft: String' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary draft state owns submit availability" \
  'public var canSubmit: Bool' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary draft state owns submission" \
  'public func submitting\(existingWords: \[String\]\) -> VoiceInkVocabularyDraftSubmission' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement submission policy owns draft and alert plan" \
  'VoiceInkWordReplacementSubmissionPlan|wordReplacementSubmissionPlan|originalDraftAfterSubmit|replacementDraftAfterSubmit|shouldComplete' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement submission policy owns list application" \
  'func updatedRulesIfChanged' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement draft state lives in VoiceInkCore" \
  'public struct VoiceInkWordReplacementDraftState' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement draft submission lives in VoiceInkCore" \
  'public struct VoiceInkWordReplacementDraftSubmission' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement draft submission preserves submitted original draft" \
  'public let submittedOriginal: String' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement draft submission preserves submitted replacement draft" \
  'public let submittedReplacement: String' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement draft state owns visible draft policy" \
  'public var hasDraft: Bool' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement draft state owns submit availability" \
  'VoiceInkDictionaryPolicy\.canSaveWordReplacementDraft' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement draft state owns submission" \
  'public func submitting\(existingOriginalTexts: \[String\]\) -> VoiceInkWordReplacementDraftSubmission' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement edit state lives in VoiceInkCore" \
  'public struct VoiceInkWordReplacementEditState' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement edit submission lives in VoiceInkCore" \
  'public struct VoiceInkWordReplacementEditSubmission|shouldComplete' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared dictionary submission application refuses alert plans" \
  'alertPresentation == nil, (shouldInsert|let ruleToInsert)' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement list presentation lives in VoiceInkCore" \
  'VoiceInkWordReplacementListPresentation|originalColumnTitle|editButtonHelp' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared dictionary list sort modes live in VoiceInkCore" \
  'VoiceInkVocabularySortMode|VoiceInkWordReplacementSortMode|VoiceInkWordReplacementSortColumn|indicatorSystemImageName|toggled' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared dictionary list sort preferences live in VoiceInkCore" \
  'VoiceInkDictionaryListSortPreference|vocabularySortModeKey = "vocabularySortMode"|wordReplacementSortModeKey = "wordReplacementSortMode"|saveVocabularySortMode|saveWordReplacementSortMode|clear\(from defaults:' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared preference reset clears dictionary sort preferences" \
  'VoiceInkDictionaryListSortPreference\.clear' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared dictionary list sort policy lives in VoiceInkCore" \
  'VoiceInkDictionaryListSortPolicy|sortedVocabulary|sortedWordReplacements|localizedCaseInsensitiveCompare' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary sorted deletion policy lives in VoiceInkCore" \
  'removingVocabulary<Item>' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared word-replacement sorted deletion policy lives in VoiceInkCore" \
  'removingWordReplacements<Item>' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared vocabulary sorted deletion check runs in VoiceInkCore" \
  'testDictionaryListSortPolicyRemovesDisplayedSortedVocabularyRows' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared word-replacement sorted deletion check runs in VoiceInkCore" \
  'testDictionaryListSortPolicyRemovesDisplayedSortedWordReplacementRows' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "iOS settings uses shared dictionary alert presentation" \
  'VoiceInkDictionaryAlertPresentation|dictionaryAlert|\.vocabulary|\.wordReplacement' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS settings uses shared dictionary settings presentation" \
  'VoiceInkDictionarySettingsPresentation\.iOS|dictionaryPresentation|wordReplacementArrowSystemImageName' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS vocabulary submission uses shared draft state" \
  'VoiceInkVocabularyDraftState|customVocabularyDraftState\.submitting|draftStateAfterSubmit|alertPresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS vocabulary adapter receives shared submission plan" \
  'applyCustomVocabularySubmissionPlan\(_ plan: VoiceInkVocabularySubmissionPlan\)' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS vocabulary adapter applies shared submission result" \
  'plan\.updatedWordsIfChanged\(from: customVocabularyTerms\)' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS vocabulary settings reads shared sort preference" \
  'VoiceInkDictionaryListSortPreference\.vocabularySortMode' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS vocabulary adapter sorts through shared list policy" \
  'VoiceInkDictionaryListSortPolicy\.sortedVocabulary' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS vocabulary adapter deletes displayed rows through shared list policy" \
  'VoiceInkDictionaryListSortPolicy\.removingVocabulary' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS vocabulary view renders sorted settings rows" \
  'settings\.sortedCustomVocabularyTerms\(mode: vocabularySortMode\)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS vocabulary view deletes displayed sorted rows" \
  'removeCustomVocabularyTerms\(atSortedOffsets: offsets, mode: vocabularySortMode\)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS word-replacement submission uses shared draft state" \
  'VoiceInkWordReplacementDraftState|wordReplacementDraftState\.submitting|draftStateAfterSubmit|alertPresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS word-replacement adapter receives shared submission plan" \
  'applyWordReplacementSubmissionPlan\(_ plan: VoiceInkWordReplacementSubmissionPlan\)' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS word-replacement adapter applies shared submission result" \
  'plan\.updatedRulesIfChanged\(from: wordReplacements\)' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS dictionary adapters avoid shell-owned changed-list comparison" \
  'let updated(Rules|Terms) = plan\.applying|wordReplacements != updatedRules|customVocabularyTerms != updatedTerms' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS word-replacement settings reads shared sort preference" \
  'VoiceInkDictionaryListSortPreference\.wordReplacementSortMode' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS word-replacement adapter sorts through shared list policy" \
  'VoiceInkDictionaryListSortPolicy\.sortedWordReplacements' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS word-replacement adapter deletes displayed rows through shared list policy" \
  'VoiceInkDictionaryListSortPolicy\.removingWordReplacements' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS word-replacement view renders sorted settings rows" \
  'settings\.sortedWordReplacements\(mode: wordReplacementSortMode\)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS word-replacement view deletes displayed sorted rows" \
  'removeWordReplacements\(atSortedOffsets: offsets, mode: wordReplacementSortMode\)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS filler-word settings consumes shared dictionary alert presentation" \
  'VoiceInkDictionaryAlertPresentation|alertPresentation|plan\.alertPresentation' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift

require_pattern \
  "macOS vocabulary adapter receives shared draft submission" \
  'static func applyVocabularySubmission' \
  VoiceInk/Services/DictionaryService.swift

require_pattern \
  "macOS vocabulary adapter accepts shared draft submission type" \
  '_ submission: VoiceInkVocabularyDraftSubmission' \
  VoiceInk/Services/DictionaryService.swift

require_pattern \
  "macOS word-replacement adapter receives shared draft submission" \
  'static func applyWordReplacementSubmission' \
  VoiceInk/Services/DictionaryService.swift

require_pattern \
  "macOS word-replacement adapter accepts shared draft submission type" \
  '_ submission: VoiceInkWordReplacementDraftSubmission' \
  VoiceInk/Services/DictionaryService.swift

require_pattern \
  "macOS vocabulary view consumes shared draft state submission result" \
  'VoiceInkVocabularyDraftState|vocabularyDraftState\.submitting|draftStateAfterSubmit|alertPresentation = appliedSubmission\.alertPresentation' \
  VoiceInk/Views/Dictionary/VocabularyView.swift

reject_pattern \
  "platform vocabulary settings views avoid shell-owned draft submit policy" \
  'VoiceInkDictionaryPolicy\.hasVocabularyDraft|@State private var (newWord|newCustomVocabularyTerm)\b' \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS quick-add vocabulary consumes shared draft state submission result" \
  'VoiceInkVocabularyDraftState|vocabularyDraftState\.submitting|appliedSubmission\.alertPresentation|appliedSubmission\.plan\.shouldComplete' \
  VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift

require_pattern \
  "macOS word-replacement view consumes shared draft state submission result" \
  'VoiceInkWordReplacementDraftState|wordReplacementDraftState\.submitting|draftStateAfterSubmit|alertPresentation = appliedSubmission\.alertPresentation' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

reject_pattern \
  "platform word-replacement settings views avoid shell-owned draft submit policy" \
  'VoiceInkDictionaryPolicy\.canSaveWordReplacementDraft|@State private var (originalWord|replacementWord|newReplacementOriginal|newReplacementText)\b' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS quick-add word replacement consumes shared draft state submission result" \
  'VoiceInkWordReplacementDraftState|wordReplacementDraftState\.submitting|appliedSubmission\.alertPresentation|appliedSubmission\.plan\.shouldComplete' \
  VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift

reject_pattern \
  "macOS quick-add avoids shell-owned dictionary draft submit policy" \
  'VoiceInkDictionaryPolicy\.(hasVocabularyDraft|canSaveWordReplacementDraft)|@State private var (wordInput|originalInput|replacementInput)\b|submitVocabularyDraft|submitWordReplacementDraft|guard +(vocabularyDraftState|wordReplacementDraftState)\.canSubmit' \
  VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift

reject_pattern \
  "iOS dictionary settings avoids shell-owned draft submit guards" \
  'guard +wordReplacementDraftState\.canSubmit' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "platform vocabulary submission avoids old insert-plan and shell-owned add wrappers" \
  'VoiceInkDictionaryPolicy\.vocabularyInsertPlan|VoiceInkVocabularyInsertPlan|addVocabularyWords|addCustomVocabularyTerms' \
  VoiceInk/Services/DictionaryService.swift \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift \
  iOS/VoiceInk-ios/AppSettings.swift \
  iOS/VoiceInk-ios/SettingsView.swift \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

reject_pattern \
  "platform word-replacement submission avoids shell-owned add wrappers" \
  'DictionaryService\.addWordReplacement|settings\.addWordReplacement|func addWordReplacement\(' \
  VoiceInk/Services/DictionaryService.swift \
  VoiceInk/Views/Dictionary/WordReplacementView.swift \
  VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift \
  iOS/VoiceInk-ios/AppSettings.swift \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS dictionary adapter avoids shell-owned submission-plan branching" \
  'guard +plan\.shouldInsert|guard +let +rule += +plan\.ruleToInsert|wordReplacements\.append\(rule\)|customVocabularyTerms\.append\(contentsOf: +plan\.wordsToInsert\)' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS dictionary settings avoid raw-storage list deletes" \
  'onDelete\(perform: settings\.remove(CustomVocabularyTerms|WordReplacements)\)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS vocabulary view uses shared dictionary alert presentation" \
  'VoiceInkDictionaryAlertPresentation|\.vocabulary|failedToRemoveVocabularyWord' \
  VoiceInk/Views/Dictionary/VocabularyView.swift

require_pattern \
  "macOS vocabulary view uses shared dictionary settings presentation" \
  'VoiceInkDictionarySettingsPresentation\.macOS|dictionaryPresentation' \
  VoiceInk/Views/Dictionary/VocabularyView.swift

require_pattern \
  "macOS vocabulary list uses shared list presentation" \
  'VoiceInkVocabularyListPresentation\.macOS|listPresentation|wordsTitle\(count:' \
  VoiceInk/Views/Dictionary/VocabularyView.swift

require_pattern \
  "macOS vocabulary list uses shared sort policy" \
  'VoiceInkDictionaryListSortPreference\.vocabularySortMode|VoiceInkDictionaryListSortPolicy\.sortedVocabulary|saveVocabularySortMode|indicatorSystemImageName' \
  VoiceInk/Views/Dictionary/VocabularyView.swift

require_pattern \
  "macOS word-replacement view uses shared dictionary alert presentation" \
  'VoiceInkDictionaryAlertPresentation|\.wordReplacement|failedToRemoveWordReplacement' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

require_pattern \
  "macOS word-replacement view uses shared dictionary settings presentation" \
  'VoiceInkDictionarySettingsPresentation\.macOS|dictionaryPresentation' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

require_pattern \
  "macOS word-replacement list uses shared list presentation" \
  'VoiceInkWordReplacementListPresentation\.macOS|listPresentation|editButtonHelp' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

require_pattern \
  "macOS word-replacement list uses shared sort policy" \
  'VoiceInkDictionaryListSortPreference\.wordReplacementSortMode|VoiceInkDictionaryListSortPolicy\.sortedWordReplacements|saveWordReplacementSortMode|activeColumn|indicatorSystemImageName' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

require_pattern \
  "macOS word-replacement info popover uses shared presentation" \
  'VoiceInkWordReplacementInfoPresentation\.macOS|infoPresentation|WordReplacementInfoExampleRow' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

require_pattern \
  "macOS dictionary settings chrome uses shared dictionary settings presentation" \
  'VoiceInkDictionarySettingsPresentation\.macOS|VoiceInkDictionarySettingsSection\.allCases|section\.presentation\(in: dictionaryPresentation\)' \
  VoiceInk/Views/Dictionary/DictionarySettingsView.swift

reject_pattern \
  "macOS dictionary settings avoids shell-owned section selector policy" \
  'enum DictionarySection|case +(replacements|spellings)|section\.presentation[^(\n]' \
  VoiceInk/Views/Dictionary/DictionarySettingsView.swift

require_pattern \
  "macOS dictionary settings panel uses shared dictionary settings presentation" \
  'VoiceInkDictionarySettingsPresentation\.macOS|dictionaryPresentation' \
  VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift

require_pattern \
  "macOS dictionary quick-add uses shared dictionary quick-add presentation" \
  'VoiceInkDictionaryQuickAddPresentation\.macOS|quickAddPresentation|modePresentation' \
  VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift

require_pattern \
  "macOS edit replacement sheet uses shared dictionary alert presentation" \
  'VoiceInkDictionaryAlertPresentation|\.wordReplacement' \
  VoiceInk/Views/Dictionary/EditReplacementSheet.swift

require_pattern \
  "macOS edit replacement sheet uses shared edit presentation" \
  'VoiceInkWordReplacementEditPresentation\.macOS|editPresentation' \
  VoiceInk/Views/Dictionary/EditReplacementSheet.swift

require_pattern \
  "macOS edit replacement sheet uses shared edit state" \
  'VoiceInkWordReplacementEditState|editState\.canSave|editState: editState' \
  VoiceInk/Views/Dictionary/EditReplacementSheet.swift

require_pattern \
  "macOS dictionary adapter receives shared edit state" \
  'editState: VoiceInkWordReplacementEditState|VoiceInkWordReplacementEditSubmission' \
  VoiceInk/Services/DictionaryService.swift

require_pattern \
  "macOS dictionary persistence failures use shared dictionary alert copy" \
  'VoiceInkDictionaryAlertPresentation\.(failedToAddVocabularyWord|failedToAddWordReplacement|failedToSaveWordReplacementChanges)' \
  VoiceInk/Services/DictionaryService.swift

reject_pattern \
  "filler-word duplicate copy stays out of platform views" \
  'This filler word is already in the list\.' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS transcription cleanup settings avoid shell-only presentation copy" \
  '"(Transcription Cleanup|Punctuation|Paragraph Breaks|Lowercase Transcription|Remove Filler Words|Add filler word)"' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "macOS transcription cleanup settings avoid shell-only presentation copy" \
  '"(Transcript Formatting|Paragraph breaks|Lowercase output|Remove filler words|Add filler word|Apply intelligent text formatting to break large block of text into paragraphs\.|Keep preserves punctuation as transcribed\. Remove all strips punctuation marks from the transcribed text\. Remove trailing period only removes a final period from the transcribed text\.|Convert transcription output to lowercase\.|Automatically remove filler words like '\''uh'\'', '\''um'\'', '\''hmm'\'' from transcriptions\.)"' \
  VoiceInk/Views/ModelSettingsView.swift \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift

section "obsolete standalone transcript text normalizer module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/TranscriptTextNormalizer.swift

require_patterns \
  "transcript text normalizer lives with output filtering" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionOutputFilter.swift \
  'VoiceInkTranscriptTextNormalizer' \
  'collapseWhitespaceRunsAndTrim' \
  'normalizeParagraphSpacing' \
  'VoiceInkTranscriptionOutputFilter'

reject_pattern \
  "macOS audio cleanup settings avoid shell-only presentation copy" \
  '"(Auto-delete Transcripts|Automatically delete transcript history based on the retention period you set\.|Delete After|Immediately|1 hour|1 day|3 days|7 days|Run Cleanup Now|Transcript Cleanup|Cleanup complete\.|Auto-delete Audio Files|Automatically delete audio recordings while keeping text transcripts intact\.|Keep Audio For|14 days|30 days|Analyzing\.\.\.|Audio Cleanup|Cancel|Cleanup Complete)"|Delete \\\(cleanupInfo\.fileCount\\\) Files|This will delete \\\(cleanupInfo\.fileCount\\\) audio files|No audio files found older than|Deleted \\\(cleanupResult\.deletedCount\\\)' \
  VoiceInk/Views/Settings/AudioCleanupSettingsView.swift

reject_pattern \
  "iOS dictionary settings avoid shell-only presentation copy" \
  '"(Dictionary|Vocabulary term|Original text|Replacement text|Add Replacement)"' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS dictionary settings avoid duplicate word-replacement row arrow icon" \
  '"arrow\.right"' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "macOS dictionary form views avoid shell-only presentation copy" \
  '"(Add words to help VoiceInk recognize them properly\. \(Requires AI enhancement\)|Add word to vocabulary|Add word|Define word replacements to automatically replace specific words or phrases|Original text \(use commas for multiple\)|Replacement text|Add word replacement)"' \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

reject_pattern \
  "macOS dictionary settings chrome avoids shell-only presentation copy" \
  '"(Word Replacements|Vocabulary|Add words to help VoiceInk recognize them properly|Automatically replace specific words/phrases with custom formatted text |Dictionary Settings|Enhance VoiceInk'\''s transcription accuracy by teaching it your vocabulary|Select Section|Dictionary settings|Quick Add to Dictionary|Shortcuts|Close)"' \
  VoiceInk/Views/Dictionary/DictionarySettingsView.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift

reject_pattern \
  "macOS dictionary quick-add avoids shell-only presentation copy" \
  '"(Vocabulary|Word Replacement|e\.g\. Prakash, VoiceInk|Replace|e\.g\. my email, my mail|With|e\.g\. support@tryvoiceink\.com|Add|Dismiss)"' \
  VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift

reject_pattern \
  "macOS word-replacement info popover avoids shell-only presentation copy" \
  '"(How to use Word Replacements|Separate multiple originals with commas:|Voicing, Voice ink, Voiceing|Examples|Original:|Replacement:|my website link|https://tryvoiceink\.com|Voicing, Voice ink|VoiceInk)"' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

reject_pattern \
  "macOS edit replacement sheet avoids shell-only presentation copy" \
  '"(Cancel|Edit Word Replacement|Save|Update the word or phrase that should be automatically replaced\.|Original Text|Required|Enter word or phrase to replace \(use commas for multiple\)|Replacement Text)"' \
  VoiceInk/Views/Dictionary/EditReplacementSheet.swift

reject_pattern \
  "macOS edit replacement sheet avoids shell-owned edit policy" \
  'VoiceInkDictionaryPolicy\.canSaveWordReplacementDraft|@State private var (originalWord|replacementWord)\b|private var +canSave\b|guard +editState\.canSave' \
  VoiceInk/Views/Dictionary/EditReplacementSheet.swift

reject_pattern \
  "macOS dictionary adapter avoids obsolete draft submit wrappers" \
  'submitVocabularyDraft|submitWordReplacementDraft' \
  VoiceInk/Services/DictionaryService.swift

reject_pattern \
  "macOS dictionary list views avoid shell-only presentation copy" \
  '"(Vocabulary Words|Sort alphabetically|Remove word|Original|Replacement|Sort by original|Sort by replacement|Edit replacement|Remove replacement)"' \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

reject_pattern \
  "macOS dictionary list views avoid shell-owned sort policy" \
  'enum +(VocabularySortMode|SortMode|SortColumn)|"(vocabularySortMode|wordReplacementSortMode)"|localizedCaseInsensitiveCompare|UserDefaults\.standard\.(string|set)\(forKey:' \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

reject_pattern \
  "macOS dictionary list views avoid shallow sorted-list wrappers" \
  'private var +(sortedItems|sortedReplacements)\b' \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

reject_pattern \
  "macOS dictionary form views avoid shallow add-button visibility wrappers" \
  'private var +shouldShowAddButton\b' \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

require_pattern \
  "migration checklist tracks shared dictionary sort gate" \
  'section order/default selection.*`VoiceInkDictionarySettingsPresentation`/`VoiceInkDictionarySettingsSection`.*`VoiceInkDictionaryListSortPreference`/`VoiceInkDictionaryListSortPolicy`.*local section enums' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration docs track dictionary sort reset coverage" \
  'VoiceInkSharedPreferenceReset`, including modes, onboarding, verification flags, transcription prompt/language/model settings, cleanup settings, AI-enhancement provider/model settings, dynamic provider caches, custom prompts, VAD, dictionary sort preferences, and filler-word overrides' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "platform dictionary surfaces avoid duplicate alert titles and persistence failure copy" \
  '\.alert\("Duplicate Word"|\.alert\("Vocabulary"|\.alert\("Word Replacement"|Failed to add '\''|Failed to add replacement|Failed to save changes|Failed to remove word|Failed to remove replacement' \
  VoiceInk/Services/DictionaryService.swift \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  VoiceInk/Views/Dictionary/WordReplacementView.swift \
  VoiceInk/Views/Dictionary/EditReplacementSheet.swift \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "shared word-replacement engine owns rule ordering" \
  'for rule in orderedRules\(rules\)' \
  VoiceInkCore/Sources/VoiceInkCore/WordReplacementEngine.swift

reject_pattern \
  "shared word-replacement engine does not expose shell ordering helper" \
  'public static func sortedRules' \
  VoiceInkCore/Sources/VoiceInkCore/WordReplacementEngine.swift

reject_pattern \
  "iOS retry passes stored word replacements into shared engine" \
  'runtimeWordReplacementRules|VoiceInkWordReplacementEngine\.sortedRules' \
  iOS/VoiceInk-ios/AppSettings.swift \
  iOS/VoiceInk-ios/TranscriptionRetryService.swift

reject_pattern \
  "macOS word-replacement service leaves rule ordering to shared engine" \
  'VoiceInkWordReplacementEngine\.sortedRules|let sortedRules' \
  VoiceInk/Transcription/Processing/WordReplacementService.swift

reject_pattern \
  "macOS dictionary adapters leave empty input behavior to shared modules" \
  'guard !customWords\.isEmpty|guard !replacements\.isEmpty' \
  VoiceInk/Services/CustomVocabularyService.swift \
  VoiceInk/Transcription/Processing/WordReplacementService.swift

require_pattern \
  "shared dictionary backup import plan lives in VoiceInkCore" \
  'VoiceInkDictionaryBackupImportPlan|dictionaryBackupImportPlan\(' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "shared dictionary backup export plan lives in VoiceInkCore" \
  'VoiceInkDictionaryBackupExportPlan|dictionaryBackupExportPlan\(' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "macOS backup export uses shared dictionary export plan" \
  'VoiceInkDictionaryPolicy\.dictionaryBackupExportPlan\(' \
  VoiceInk/Services/ImportExportService.swift

reject_pattern \
  "macOS backup export avoids shell-owned dictionary export planning" \
  'var exported(DictionaryItems|WordReplacements)|vocabularyBackupRecords\(from: items\.map|Dictionary\(replacements\.map' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup import uses shared dictionary import plan" \
  'VoiceInkDictionaryPolicy\.dictionaryBackupImportPlan\(' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import avoids shell-owned dictionary import counters and subplans" \
  'var +(insertedWords|insertedReplacements|skippedInvalidReplacements)\b|VoiceInkDictionaryPolicy\.(vocabularyWordsToInsert|wordReplacementBackupImportPlan)\(' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import avoids shell-only word-replacement import planning" \
  'for \(original, replacement\) in replacements|VoiceInkDictionaryPolicy\.wordReplacementInsertPlan\(|plan\.errorMessage|plan\.shouldInsert|existingOriginalTexts\.append' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "core checks execute dictionary backup export nil-shape test" \
  'testDictionaryBackupExportPlanPreservesMacOSNilAndRecordShape' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute dictionary backup export duplicate-replacement test" \
  'testDictionaryBackupExportPlanKeepsLastDuplicateReplacement' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute dictionary backup import plan tests" \
  'testDictionaryBackupImportPlanCombinesVocabularyAndReplacementsForMacOSImport|testDictionaryBackupImportPlanPreservesNoDataNoSaveDecision|testDictionaryBackupImportPlanDoesNotInvalidateReplacementCacheForVocabularyOnlyImport' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "iOS retry passes stored vocabulary into shared run processor" \
  'runtimeCustomVocabularyTerms' \
  iOS/VoiceInk-ios

reject_pattern \
  "macOS transcription adapters avoid provider-local vocabulary and prompt wrappers" \
  'private func +(selectedLanguage|transcriptionPrompt|getCustom(Dictionary|Vocabulary)Terms)\(' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SonioxStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/DeepgramStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SpeechmaticsStreamingProvider.swift

require_pattern \
  "shared remote transcription options use shared prompt use policy" \
  'VoiceInkTranscriptionPromptUse\.recordedFileTranscription' \
  VoiceInkCore/Sources/VoiceInkCore/AudioTranscriptionService.swift

require_pattern \
  "shared audio transcription service factory owns provider dispatch" \
  'VoiceInkAudioTranscriptionServiceFactory' \
  VoiceInkCore/Sources/VoiceInkCore/AudioTranscriptionService.swift

require_pattern \
  "iOS retry transcription uses shared audio transcription service factory" \
  'VoiceInkAudioTranscriptionServiceFactory' \
  iOS/VoiceInk-ios/TranscriptionRetryService.swift

reject_pattern \
  "iOS retry transcription avoids shell-only provider dispatch" \
  'transcriptionServiceKind|VoiceInkRemoteTranscriptionService\(provider:' \
  iOS/VoiceInk-ios/TranscriptionRetryService.swift

require_patterns \
  "shared transcription run settings snapshot lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift \
  'VoiceInkTranscriptionRunSettings' \
  'VoiceInkTranscriptionRunSettingsPolicy' \
  'iOSAppSettingsSnapshot' \
  'VoiceInkTranscriptionCleanupConfiguration\.current' \
  'VoiceInkPostProcessingSkipConfiguration\.current' \
  'VoiceInkTranscriptionPromptPreference\.localWhisperPrompt' \
  'wordReplacementRules' \
  'customVocabulary' \
  'processor: VoiceInkTranscriptionRunProcessor' \
  'VoiceInkWordReplacementEngine\.apply\(wordReplacementRules'

require_patterns \
  "iOS AppSettings exposes shared transcription run settings snapshot" \
  iOS/VoiceInk-ios/AppSettings.swift \
  'var transcriptionRunSettings: VoiceInkTranscriptionRunSettings' \
  'VoiceInkTranscriptionRunSettingsPolicy\.iOSAppSettingsSnapshot' \
  'modes: modes' \
  'selectedTranscriptionLanguage: selectedTranscriptionLanguage' \
  'wordReplacementRules: wordReplacements' \
  'customVocabulary: customVocabularyTerms'

reject_context_pattern \
  "iOS AppSettings avoids shell-owned transcription run snapshot assembly" \
  'var transcriptionRunSettings' \
  'modes\.runtimeConfiguration|VoiceInkTranscriptionCleanupConfiguration\.current|VoiceInkPostProcessingSkipConfiguration\.current|VoiceInkTranscriptionPromptPreference\.localWhisperPromptForSelectedLanguage|configuration:|cleanupConfiguration:|postProcessingSkipConfiguration:' \
  iOS/VoiceInk-ios/AppSettings.swift

require_patterns \
  "iOS retry transcription uses shared run settings snapshot" \
  iOS/VoiceInk-ios/TranscriptionRetryService.swift \
  'let runSettings = await settings\.transcriptionRunSettings' \
  'try await runSettings\.transcribe\('

require_pattern \
  "core checks execute shared transcription run settings snapshot test" \
  'TranscriptionRunProcessorTests\.testTranscriptionRunSettingsApplySnapshotFieldsThroughSharedProcessor' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute iOS app settings snapshot policy test" \
  'TranscriptionRunProcessorTests\.testIOSAppSettingsSnapshotBuildsRunSettingsFromSharedPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "iOS retry transcription avoids shell-owned run settings assembly" \
  'let (modeConfiguration|cleanupConfiguration|transcriptionLanguage|transcriptionPrompt|wordReplacementRules|customVocabulary) = await settings\.|applyingWordReplacements:|VoiceInkPostProcessingSkipConfiguration\.current\(\)' \
  iOS/VoiceInk-ios/TranscriptionRetryService.swift

require_pattern \
  "shared run processor uses shared prompt use policy" \
  'VoiceInkTranscriptionPromptUse\.recordedFileTranscription' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift

require_pattern \
  "macOS AssemblyAI streaming uses shared prompt use policy" \
  'VoiceInkTranscriptionPromptUse\.streamingTranscription\(\.assemblyAI\)' \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift

reject_pattern \
  "macOS AssemblyAI streaming avoids raw request-prompt forwarding" \
  'prompt: VoiceInkTranscriptionPromptPreference\.requestPrompt\(\)' \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift

require_pattern \
  "macOS Deepgram streaming uses shared vocabulary use policy" \
  'VoiceInkCustomVocabularyUse\.streamingTranscription\(\.deepgram\)|\.streamingTranscription\(\.deepgram\)' \
  VoiceInk/Transcription/Streaming/DeepgramStreamingProvider.swift

require_pattern \
  "macOS Soniox streaming uses shared vocabulary use policy" \
  'VoiceInkCustomVocabularyUse\.streamingTranscription\(\.soniox\)|\.streamingTranscription\(\.soniox\)' \
  VoiceInk/Transcription/Streaming/SonioxStreamingProvider.swift

require_pattern \
  "macOS Speechmatics streaming uses shared vocabulary use policy" \
  'VoiceInkCustomVocabularyUse\.streamingTranscription\(\.speechmatics\)|\.streamingTranscription\(\.speechmatics\)' \
  VoiceInk/Transcription/Streaming/SpeechmaticsStreamingProvider.swift

require_pattern \
  "macOS AssemblyAI streaming uses shared vocabulary use policy" \
  'VoiceInkCustomVocabularyUse\.streamingTranscription\(\.assemblyAI\)|\.streamingTranscription\(\.assemblyAI\)' \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift

section "obsolete standalone streaming event module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/StreamingTranscriptionEvent.swift
reject_file VoiceInkCore/Sources/VoiceInkCore/StreamingTranscriptionError.swift

require_patterns \
  "shared streaming event and error taxonomy live with streaming route policy in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionStreamingPreference.swift \
  'VoiceInkStreamingTranscriptionEvent' \
  'case sessionStarted' \
  'case partial\(text: String\)' \
  'case committed\(text: String\)' \
  'case error\(Error\)' \
  'VoiceInkStreamingTranscriptionError' \
  'missingAPIKey' \
  'connectionFailed' \
  'timeout' \
  'serverError' \
  'notConnected'

require_pattern \
  "shared streaming connection model policy lives in VoiceInkCore" \
  'streamingConnectionModelName\(for selectedModelName: String\)|scribe_v2_realtime|stt-rt-v4|voxtral-mini-transcribe-realtime-2602|selectedModelName\.contains\("standard"\) \? "standard" : "enhanced"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift

require_pattern \
  "core checks execute streaming connection model policy tests" \
  'TranscriptionModelCatalogTests\.testStreamingConnectionModelNamesAreSharedProviderPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS transcription model adapter exposes shared streaming connection model policy" \
  'coreTranscriptionModelProviderRole\.streamingConnectionModelName\(for: name\)' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS cloud streaming adapters use shared connection model policy" \
  'model\.streamingConnectionModelName' \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/CartesiaStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/DeepgramStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/ElevenLabsStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/MistralStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SonioxStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SpeechmaticsStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/XAIStreamingProvider.swift

require_pattern \
  "shared streaming timeout mapping policy lives in VoiceInkCore" \
  'mapsStreamingTransportTimeoutToFinalTimeout|case \.assemblyAI:[[:space:]]*return true' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift

require_pattern \
  "core checks execute streaming timeout mapping policy tests" \
  'TranscriptionModelCatalogTests\.testStreamingTimeoutMappingIsSharedProviderPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS transcription model adapter exposes shared streaming timeout mapping policy" \
  'coreTranscriptionModelProviderRole\.mapsStreamingTransportTimeoutToFinalTimeout' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS AssemblyAI streaming uses shared timeout mapping policy" \
  'model\.mapsStreamingTransportTimeoutToFinalTimeout|treatsTimeoutAsStreamingTimeout: mapsTransportTimeoutToFinalTimeout' \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift

reject_pattern \
  "macOS cloud streaming adapters avoid shell-owned timeout mapping policy" \
  'treatsTimeoutAsStreamingTimeout: true' \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/CartesiaStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/DeepgramStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/ElevenLabsStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/MistralStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SonioxStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SpeechmaticsStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/XAIStreamingProvider.swift

reject_pattern \
  "macOS cloud streaming adapters avoid shell-owned connection model policy" \
  '"scribe_v2_realtime"|"stt-rt-v4"|"voxtral-mini-transcribe-realtime-2602"|model\.name\.contains\("standard"\)|let +operatingPoint|model: model\.name' \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/CartesiaStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/DeepgramStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/ElevenLabsStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/MistralStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SonioxStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SpeechmaticsStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/XAIStreamingProvider.swift

reject_pattern \
  "macOS Deepgram streaming avoids shell-only vocabulary term limit" \
  'limit: 50|prefix\(50\)' \
  VoiceInk/Transcription/Streaming/DeepgramStreamingProvider.swift

reject_pattern \
  "macOS streaming adapters avoid unnamed custom-vocabulary use" \
  'getCustomVocabularyTerms\(from: modelContext\)' \
  VoiceInk/Transcription/Streaming/AssemblyAIStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SonioxStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/DeepgramStreamingProvider.swift \
  VoiceInk/Transcription/Streaming/SpeechmaticsStreamingProvider.swift

require_pattern \
  "macOS cloud batch transcription passes raw vocabulary into shared batch options" \
  'rawCustomVocabularyTerms\(from: modelContext\)' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift

reject_file VoiceInkCore/Sources/VoiceInkCore/CloudTranscriptionError.swift

require_pattern \
  "shared cloud transcription error lives with audio transcription service" \
  'VoiceInkCloudTranscriptionError|CloudTranscriptionError|apiRequestFailure|apiStatusCodeRange|apiRequestFailed|networkError|noTranscriptionReturned' \
  VoiceInkCore/Sources/VoiceInkCore/AudioTranscriptionService.swift

require_pattern \
  "shared cloud transcription error checks run in VoiceInkCore" \
  'CloudTranscriptionErrorTests\.testErrorDescriptionsPreserveMacOSCloudTranscriptionCopy|CloudTranscriptionErrorTests\.testNoTranscriptionReturnedUsesSharedRunErrorDescription|CloudTranscriptionErrorTests\.testAPIRequestFailureMapsMatchingHTTPNSError|CloudTranscriptionErrorTests\.testAPIRequestFailureFallsBackToLocalizedDescription|CloudTranscriptionErrorTests\.testAPIRequestFailureRejectsWrongDomainMissingDomainAndNonHTTPStatus|CloudTranscriptionErrorTests\.testLegacyCloudTranscriptionErrorAliasResolvesToSharedCoreError' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS cloud batch transcription uses shared cloud transcription error" \
  'CloudTranscriptionError\.(unsupportedProvider|missingAPIKey|audioFileNotFound|apiRequestFailure|networkError|noTranscriptionReturned)' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift \
  VoiceInk/Transcription/Cloud/CloudProvider.swift

require_pattern \
  "shared cloud transcription error uses shared run error description" \
  'VoiceInkTranscriptionRunError\.noTranscriptionReturned\.errorDescription' \
  VoiceInkCore/Sources/VoiceInkCore/AudioTranscriptionService.swift

reject_pattern \
  "macOS cloud batch transcription avoids pre-normalized vocabulary terms" \
  'getCustomVocabularyTerms\(from: modelContext\)' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift \
  VoiceInk/Services/CustomVocabularyService.swift

reject_pattern \
  "macOS custom cloud avoids duplicate empty-response error copy" \
  'The API returned an empty or invalid response\.' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift

reject_pattern \
  "macOS cloud transcription avoids shell-local cloud error enum" \
  'enum +CloudTranscriptionError|var +errorDescription: +String\?' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift

reject_pattern \
  "macOS cloud transcription avoids shell-owned HTTP API error mapping" \
  '100\.\.\.599|userInfo\[NSLocalizedDescriptionKey\]|apiRequestFailed\(statusCode:' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift \
  VoiceInk/Transcription/Cloud/CloudProvider.swift

require_pattern \
  "shared AI enhancement vocabulary context normalizes post-processing terms" \
  'VoiceInkCustomVocabularyTerms\.normalized\(terms, for: \.postProcessingContext\)' \
  VoiceInkCore/Sources/VoiceInkCore/AIPrompts.swift

require_pattern \
  "shared run processor uses shared transcription run preparation" \
  'VoiceInkTranscriptionRunPreparation\.prepareRawText' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift

require_pattern \
  "shared audio-file transcription draft plan lives in VoiceInkCore" \
  'VoiceInkAudioFileTranscriptionDraftContext|VoiceInkAudioFileTranscriptionEnhancementOutcome|VoiceInkAudioFileTranscriptionDraft' \
  VoiceInkCore/Sources/VoiceInkCore/CompletedTranscriptionDraft.swift

require_pattern \
  "shared transcription enhancement text plan type lives in VoiceInkCore" \
  'VoiceInkTranscriptionEnhancementTextPlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunPreparation.swift

require_pattern \
  "shared audio-file transcription text plan aliases enhancement text plan" \
  'VoiceInkAudioFileTranscriptionTextPlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunPreparation.swift

require_pattern \
  "shared transcription enhancement raw text preparation helper lives in VoiceInkCore" \
  'prepareRawTextForEnhancement' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunPreparation.swift

require_pattern \
  "shared audio-file transcription text preparation helper lives in VoiceInkCore" \
  'prepareAudioFileText' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunPreparation.swift

require_pattern \
  "shared audio-file transcription enhancement skip helper lives in VoiceInkCore" \
  'shouldSkipEnhancement' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunPreparation.swift

section "obsolete standalone post-processing skip policy module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/PostProcessingSkipPolicy.swift

require_pattern \
  "shared post-processing skip policy lives with transcription run preparation" \
  'VoiceInkPostProcessingSkipConfiguration|VoiceInkPostProcessingSkipPolicy|shouldSkipPostProcessing' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunPreparation.swift

require_pattern \
  "shared transcription enhancement request planning lives in VoiceInkCore" \
  'VoiceInkTranscriptionEnhancementRequest' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunPreparation.swift

require_pattern \
  "macOS live recording uses shared enhancement text plan" \
  'VoiceInkTranscriptionRunPreparation\.prepareRawTextForEnhancement' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS audio-file import uses shared audio-file text plan" \
  'VoiceInkTranscriptionRunPreparation\.prepareAudioFileText' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS retry transcription uses shared audio-file text plan" \
  'VoiceInkTranscriptionRunPreparation\.prepareAudioFileText' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "macOS live recording uses shared enhancement request planning" \
  'textPlan\.enhancementRequest' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS audio-file import uses shared enhancement request planning" \
  'textPlan\.enhancementRequest' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS retry transcription uses shared enhancement request planning" \
  'textPlan\.enhancementRequest' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

reject_pattern \
  "macOS transcription enhancement callers avoid shell-owned raw text preparation and skip role" \
  'filterRawOutput|prepareFilteredText|transcriptRole: \.wordReplacedText' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift

reject_pattern \
  "macOS transcription enhancement callers delegate enhancement request planning to VoiceInkCore" \
  'shouldSkipEnhancement|promptDetectionResult\?\.processedText \?\? text|!shouldSkipEnhancement' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "macOS recorder records use shared Power Mode transcription metadata" \
  'VoiceInkPowerModeTranscriptionMetadata\.active' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS audio-file import uses shared Power Mode transcription metadata" \
  'VoiceInkPowerModeTranscriptionMetadata\.active' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS retry transcription uses shared Power Mode transcription metadata" \
  'VoiceInkPowerModeTranscriptionMetadata\.active' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "core tests pin Power Mode transcription metadata selection" \
  'testTranscriptionMetadataUsesOnlyEnabledPowerModeConfig' \
  VoiceInkCore/Tests/VoiceInkCoreTests/PowerModePolicyTests.swift

require_pattern \
  "core tests pin shared enhancement text plan output" \
  'testEnhancementTextPlanFiltersPreparesAndSelectsEnhancementText|testEnhancementTextPlanCanUseAlreadyFilteredText' \
  VoiceInkCore/Tests/VoiceInkCoreTests/TranscriptionRunPreparationTests.swift

require_pattern \
  "core tests pin audio-file transcription text plan output" \
  'testAudioFileTextPlanFiltersPreparesAndSelectsEnhancementText' \
  VoiceInkCore/Tests/VoiceInkCoreTests/TranscriptionRunPreparationTests.swift

require_pattern \
  "core tests pin audio-file transcription text plan skip policy" \
  'testAudioFileTextPlanSkipUsesEnhancementTextAndPromptTrigger' \
  VoiceInkCore/Tests/VoiceInkCoreTests/TranscriptionRunPreparationTests.swift

require_pattern \
  "core check runner executes Power Mode transcription metadata selection test" \
  'testTranscriptionMetadataUsesOnlyEnabledPowerModeConfig' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core check runner executes shared enhancement text plan tests" \
  'testEnhancementTextPlanFiltersPreparesAndSelectsEnhancementText|testEnhancementTextPlanCanUseAlreadyFilteredText' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core check runner executes audio-file transcription text plan output test" \
  'testAudioFileTextPlanFiltersPreparesAndSelectsEnhancementText' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core check runner executes audio-file transcription text plan skip policy test" \
  'testAudioFileTextPlanSkipUsesEnhancementTextAndPromptTrigger' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS transcription callers avoid shell-only Power Mode metadata selection" \
  'activePowerModeConfig|currentPowerModeMetadata|\?\.isEnabled == true' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "macOS audio-file import builds completed records through shared completion result" \
  'VoiceInkAudioFileTranscriptionDraft\.completionResult' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS retry transcription builds completed records through shared completion result" \
  'VoiceInkAudioFileTranscriptionDraft\.completionResult' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

reject_pattern \
  "macOS audio-file transcription callers avoid shell-owned completed draft construction" \
  'VoiceInkCompletedTranscriptionDraft\(' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift

reject_pattern \
  "macOS transcription run callers use shared post-processing skip decision" \
  'VoiceInkPostProcessingSkipPolicy\.shouldSkipPostProcessing' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "shared enhancement settings presentation lives in VoiceInkCore" \
  'VoiceInkEnhancementSettingsPresentation|generalSectionTitle|enableEnhancementTitle|enableEnhancementHelp|enableEnhancementLearnMoreURLString|settingsButtonSystemImageName|settingsButtonHelp|promptsSectionTitle|toggleEnhancementShortcutTitle|toggleEnhancementShortcutHelp|switchPromptShortcutTitle|switchPromptShortcutHelp|shortcutLearnMoreURLString|switchPromptKeyChipTitles|shortEnhancementWordOptions|timeoutRetryOptions' \
  VoiceInkCore/Sources/VoiceInkCore/EnhancementSettingsPresentation.swift

require_pattern \
  "macOS enhancement settings outer view uses shared presentation" \
  'VoiceInkEnhancementSettingsPresentation\.macOS|presentation\.(generalSectionTitle|enableEnhancementTitle|enableEnhancementHelp|enableEnhancementLearnMoreURLString|settingsButtonSystemImageName|settingsButtonHelp|promptsSectionTitle)' \
  VoiceInk/Views/EnhancementSettingsView.swift

require_pattern \
  "macOS enhancement shortcuts use shared presentation" \
  'VoiceInkEnhancementSettingsPresentation\.macOS|presentation\.(toggleEnhancementShortcutTitle|toggleEnhancementShortcutHelp|switchPromptShortcutTitle|switchPromptShortcutHelp|shortcutLearnMoreURLString|switchPromptKeyChipTitles)' \
  VoiceInk/Views/Settings/EnhancementShortcutsView.swift

require_pattern \
  "macOS enhancement settings use shared presentation" \
  'VoiceInkEnhancementSettingsPresentation\.macOS|presentation\.(skipShortEnhancementTitle|timeoutOptions|timeoutRetryOptions)' \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift

reject_pattern \
  "macOS enhancement settings avoid shell-only presentation copy and option ranges" \
  '"(Enhancement Settings|Close|Clipboard Context|Use clipboard text to understand context for better enhancement\.|Screen Context|Capture on-screen text to understand context for better enhancement\.|Context|Skip short transcriptions|Minimum words|Timeout duration|On timeout|Fail immediately|Retry|Request Timeout|Set how long to wait for the AI provider to respond\.|Shortcuts)"|ForEach\(1\.\.\.15|\[3, 5, 7, 10, 15, 20, 30, 40, 50, 60\]' \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift

require_pattern \
  "shared AI enhancement transport failure policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementTransportFailure|transportFailure|missingAPIKey|noResultReturned|invalidRequest' \
  VoiceInkCore/Sources/VoiceInkCore/AIEnhancementError.swift

require_pattern \
  "core tests pin shared AI enhancement transport failure policy" \
  'testTransportFailureMappingPreservesMacOSLLMKitCategories' \
  VoiceInkCore/Tests/VoiceInkCoreTests/AIEnhancementErrorTests.swift

require_pattern \
  "core check runner executes shared AI enhancement transport failure policy test" \
  'AIEnhancementErrorTests\.testTransportFailureMappingPreservesMacOSLLMKitCategories' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS AI enhancement service adapts LLMKit transport failures through shared policy" \
  'VoiceInkAIEnhancementError\.transportFailure|VoiceInkAIEnhancementTransportFailure|voiceInkAIEnhancementTransportFailure' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned LLMKit error mapping" \
  'mapLLMKitError|VoiceInkAIEnhancementError\.httpError\(statusCode: statusCode, message: message\)|VoiceInkAIEnhancementError\.timeout|return \.(notConfigured|enhancementFailed|networkError)|An unknown error occurred\.' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "shared Ollama enhancement failure policy lives in VoiceInkCore" \
  'VoiceInkOllamaEnhancementFailure|VoiceInkOllamaTransportFailure|transportFailure|httpFailure|enhancementError|VoiceInkOllamaServiceDiagnostics|modelFetchFailedMessage|Ollama request timed out' \
  VoiceInkCore/Sources/VoiceInkCore/AIEnhancementError.swift

require_pattern \
  "core tests pin shared Ollama enhancement failure policy" \
  'testOllamaEnhancementFailurePolicyPreservesMacOSMessagesAndRetryShape|testOllamaTransportFailuresMapToSharedFailurePolicy|testOllamaServiceDiagnosticsPreserveMacOSConsoleCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/AIEnhancementErrorTests.swift

require_pattern \
  "core check runner executes shared Ollama enhancement failure policy test" \
  'testOllamaEnhancementFailurePolicyPreservesMacOSMessagesAndRetryShape|testOllamaTransportFailuresMapToSharedFailurePolicy|testOllamaServiceDiagnosticsPreserveMacOSConsoleCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS Ollama service uses shared enhancement failure policy" \
  'VoiceInkOllamaEnhancementFailure|VoiceInkOllamaTransportFailure|voiceInkOllamaTransportFailure|VoiceInkOllamaServiceDiagnostics' \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS Ollama service avoids shell-owned enhancement failure policy" \
  'LocalAIError|VoiceInkOllamaEnhancementFailure\.httpFailure|"(Invalid Ollama server URL|Ollama service is not available|Invalid response from Ollama server|Selected model not found|Ollama server error|System prompt is required|Ollama request timed out|Invalid Ollama base URL|Error fetching models:)"' \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS enhancement settings outer view avoids shell-only chrome copy" \
  '"(Enable Enhancement|AI enhancement lets you pass the transcribed audio through LLMs to post-process using different prompts suitable for different use cases like e-mails, summary, writing, etc\.|https://tryvoiceink.com/docs/enhancements-configuring-models|General|Enhancement settings|Enhancement Prompts|gear)"' \
  VoiceInk/Views/EnhancementSettingsView.swift

reject_pattern \
  "macOS enhancement shortcuts avoid shell-only row presentation copy" \
  '"(Toggle AI Enhancement|Quickly enable or disable AI enhancement while recording|Switch Enhancement Prompt|Switch between your saved prompts using ⌘1 through ⌘0|https://tryvoiceink.com/docs/enhancement-shortcuts|⌘|1 – 0)"' \
  VoiceInk/Views/Settings/EnhancementShortcutsView.swift

require_pattern \
  "migration checklist tracks shared enhancement settings presentation gate" \
  'macOS enhancement settings outer chrome, labels, shortcut row copy/key-chip labels, short-transcript threshold options, timeout options, and timeout retry labels route through `VoiceInkEnhancementSettingsPresentation`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared core owns transcription session route planning" \
  'VoiceInkTranscription(SessionRouteFacts|SessionRoutePlan)|VoiceInkTranscriptionStreamingAdapterKind' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionStreamingPreference.swift

section "obsolete standalone streaming final-commit timeout module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/StreamingFinalCommitTimeout.swift

require_patterns \
  "streaming final-commit timeout lives with route planning" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionStreamingPreference.swift \
  'VoiceInkStreamingFinalCommitSource' \
  'VoiceInkStreamingFinalCommitTimeout' \
  'VoiceInkTranscriptionSessionRoutePlan'

require_pattern \
  "shared core owns transcription session execution planning" \
  'VoiceInkTranscriptionSessionExecutionPlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionStreamingPreference.swift

require_pattern \
  "shared transcription session route plan packages concrete execution plan" \
  'var executionPlan: VoiceInkTranscriptionSessionExecutionPlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionStreamingPreference.swift

require_pattern \
  "macOS model adapts shared transcription session route facts" \
  'transcription(SessionRouteFacts|ServiceRoute)' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS session creation uses shared transcription route plan" \
  'transcriptionSessionRouteFacts\.plan\(forceStreaming: forceStreaming\)' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

require_pattern \
  "macOS transcription service registry consumes shared session execution plan" \
  'routePlan\.executionPlan|case \.streaming|case \.file' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

require_pattern \
  "macOS session creation passes shared streaming adapter kind" \
  'streamingAdapterKind: streamingAdapterKind' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

require_pattern \
  "macOS streaming service uses shared streaming adapter kind" \
  'VoiceInkTranscriptionStreamingAdapterKind|streamingAdapterKind' \
  VoiceInk/Transcription/Streaming/StreamingTranscriptionService.swift

require_pattern \
  "shared FluidAudio transcription policy lives in VoiceInkCore" \
  'VoiceInkFluidAudioTranscriptionPolicy' \
  VoiceInkCore/Sources/VoiceInkCore/FluidAudioTranscriptionPolicy.swift

require_pattern \
  "shared FluidAudio transcription policy owns trailing-silence default" \
  'trailingSilenceSeconds: Double = 1' \
  VoiceInkCore/Sources/VoiceInkCore/FluidAudioTranscriptionPolicy.swift

require_pattern \
  "shared FluidAudio transcription policy owns max chunk limit" \
  'maxSingleChunkSamples = 240_000' \
  VoiceInkCore/Sources/VoiceInkCore/FluidAudioTranscriptionPolicy.swift

require_pattern \
  "shared FluidAudio transcription policy owns local ASR helper interface" \
  'paddedSamplesForTranscription|shouldScheduleImmediatePass|shouldRunTranscriptionPass|seekSample|bufferRelativeSeek|cachedFinalTextPlan' \
  VoiceInkCore/Sources/VoiceInkCore/FluidAudioTranscriptionPolicy.swift

require_pattern \
  "shared FluidAudio model runtime version policy lives in VoiceInkCore" \
  'VoiceInkFluidAudioModelVersion|modelVersion|fluidAudioModelVersion\(forModelName:|fluidAudioLanguageHintCode' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift

require_pattern \
  "shared FluidAudio default model policy lives in VoiceInkCore" \
  'defaultMacOSFluidAudioModelName|defaultMacOSFluidAudioModel' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift

require_pattern \
  "core checks execute FluidAudio model runtime version policy test" \
  'TranscriptionModelCatalogTests\.testFluidAudioRuntimeVersionAndLanguageHintPolicyIsShared' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks pin shared FluidAudio default model policy" \
  'defaultMacOSFluidAudioModelName|defaultMacOSFluidAudioModel' \
  VoiceInkCore/Tests/VoiceInkCoreTests/TranscriptionModelCatalogTests.swift

require_pattern \
  "shared FluidAudio download status presentation lives in VoiceInkCore" \
  'VoiceInkFluidAudioDownloadStatus|VoiceInkFluidAudioDownloadPhase|preparingDownload|downloadingFiles|percentText' \
  VoiceInkCore/Sources/VoiceInkCore/FluidAudioTranscriptionPolicy.swift

require_pattern \
  "macOS model registry adapts shared FluidAudio default model" \
  'defaultMacOSFluidAudioModelName|defaultMacOSFluidAudioModel' \
  VoiceInk/Models/TranscriptionModelRegistry.swift

require_pattern \
  "macOS FluidAudio model manager adapts shared runtime version policy" \
  'VoiceInkTranscriptionModelCatalog\.fluidAudioModelVersion|fluidAudioLanguageHintCode|init\(_ version: VoiceInkFluidAudioModelVersion\)' \
  VoiceInk/Transcription/FluidAudio/FluidAudioModelManager.swift

require_pattern \
  "macOS FluidAudio model manager maps SDK progress into shared download phases" \
  'VoiceInkFluidAudioDownloadStatus|downloadPhase\(for:|\.preparingDownload|\.downloadingFiles' \
  VoiceInk/Transcription/FluidAudio/FluidAudioModelManager.swift

require_pattern \
  "macOS FluidAudio model card uses shared download status presentation" \
  'status\.percentText|VoiceInkFluidAudioDownloadStatus\.compactDownloadingStatusText' \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

require_pattern \
  "macOS FluidAudio batch transcription uses shared local ASR policy" \
  'VoiceInkFluidAudioTranscriptionPolicy\.paddedSamplesForTranscription' \
  VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift

require_pattern \
  "macOS FluidAudio streaming uses shared local ASR policy" \
  'VoiceInkFluidAudioTranscriptionPolicy\.(shouldScheduleImmediatePass|shouldRunTranscriptionPass|seekSample|bufferRelativeSeek|paddedSamplesForTranscription|cachedFinalTextPlan)' \
  VoiceInk/Transcription/Streaming/FluidAudioStreamingProvider.swift

require_pattern \
  "core checks execute FluidAudio transcription policy tests" \
  'FluidAudioTranscriptionPolicyTests\.testDownloadStatusPresentationPreservesFluidAudioDownloadCopy|FluidAudioTranscriptionPolicyTests\.testTrailingSilenceDefaultsPreserveFluidAudioChunkPolicy|FluidAudioTranscriptionPolicyTests\.testImmediatePassSchedulingRequiresEnabledConfigNoInFlightTaskAndEnoughNewAudio|FluidAudioTranscriptionPolicyTests\.testCachedFinalTextPlanRejectsBlankAndStaleHypotheses' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared FluidAudio local ASR policy" \
  'FluidAudio batch/streaming adapters consume shared local ASR pass scheduling, seek, cached-final, trailing-silence padding policy, and download status presentation' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS FluidAudio adapters avoid shell-owned local ASR policy" \
  '240_000|sampleCount\(forMono16kDuration: 1\)|runsImmediatePassOnBufferedAudio &&|absoluteSampleCount - last(ImmediatePassScheduled|Transcribed)SampleCount|hypothesisStartTime > 0|maxSingleChunkSamples|trailingSilenceSamples' \
  VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift \
  VoiceInk/Transcription/Streaming/FluidAudioStreamingProvider.swift

reject_pattern \
  "macOS FluidAudio download UI avoids shell-owned status copy and percent formatting" \
  '"(Preparing FluidAudio download|Listing files from repository|Checking cached models|Downloading models:|Finalizing models|Compiling )|replacingOccurrences\(of: "\.mlmodelc"|Int\(status\.fractionCompleted \* 100\)|VoiceInkWhisperModelDownloadProgress\.compactDownloadingStatusText' \
  VoiceInk/Transcription/FluidAudio/FluidAudioModelManager.swift \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

reject_pattern \
  "macOS FluidAudio adapters avoid shell-owned model version and language-hint policy" \
  'modelVersionMap|"parakeet-tdt-0\.6b-v[23]"|languageCode != "auto"|asrVersion\(for: modelName\) == \.v3' \
  VoiceInk/Transcription/FluidAudio/FluidAudioModelManager.swift \
  VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift \
  VoiceInk/Transcription/Streaming/FluidAudioStreamingProvider.swift

require_patterns \
  "shared core owns transcription runtime resource planning" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRuntimeResourcePolicy.swift \
  'VoiceInkTranscriptionRuntimeResourcePlan' \
  'VoiceInkTranscriptionRecordingStartupLoadAction' \
  'VoiceInkLocalWhisperRuntimeUpdate' \
  'VoiceInkTranscriptionModelDeletionPlan' \
  'localWhisperRuntimeUpdate'

require_pattern \
  "macOS model adapts shared transcription runtime resource plan" \
  'transcriptionRuntimeResourcePlan' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS prewarm uses shared transcription runtime resource plan" \
  'transcriptionRuntimeResourcePlan\.shouldPrewarmModel' \
  VoiceInk/Services/ModelPrewarmService.swift

require_pattern \
  "macOS recording startup uses shared transcription runtime load action" \
  'transcriptionRuntimeResourcePlan\.recordingStartupLoadAction' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_patterns \
  "shared core owns transcription model availability policy" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift \
  'VoiceInkTranscriptionModelAvailability(Facts|Requirement)' \
  'requiresConfiguredAPIKey' \
  'requiresCurrentOSSupport'

require_pattern \
  "shared core owns Native Apple transcription policy" \
  'VoiceInkNativeAppleTranscriptionPolicy|VoiceInkNativeAppleTranscriptionFailureKind|errorDescription|resultStreamTimeout|requiresMacOS26Title' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelCatalog.swift

reject_file VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelAvailability.swift

require_pattern \
  "macOS model adapts shared transcription model availability facts" \
  'transcriptionModelAvailability(Facts|Requirement)' \
  VoiceInk/Models/TranscriptionModel.swift

require_patterns \
  "macOS transcription model manager uses shared availability facts" \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift \
  'availabilityFacts\(for: .*\)\.isUsable|transcriptionModelAvailabilityFacts' \
  'VoiceInkWhisperModelFiles\.downloadedLocalModelFile' \
  'requiresConfiguredAPIKey' \
  'requiresCurrentOSSupport'

require_pattern \
  "core checks execute transcription availability requirement predicate tests" \
  'TranscriptionModelAvailabilityTests\.testAvailabilityRequirementPredicatesIdentifyShellFactsNeeded' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS transcription model manager uses shared Native Apple transcription policy" \
  'VoiceInkNativeAppleTranscriptionPolicy\.requiresMacOS26Title' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

require_pattern \
  "macOS Native Apple transcription uses shared failure presentation" \
  'VoiceInkNativeAppleTranscriptionPolicy\.errorDescription|VoiceInkNativeAppleTranscriptionFailureKind' \
  VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift

reject_pattern \
  "macOS Native Apple transcription avoids shell-owned failure wrapper" \
  'enum +ServiceError|failureKind' \
  VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift

require_pattern \
  "macOS Native Apple transcription uses shared result-stream timeout policy" \
  'VoiceInkNativeAppleTranscriptionPolicy\.resultStreamTimeout' \
  VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift

require_patterns \
  "core checks execute Native Apple transcription policy tests" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'TranscriptionModelAvailabilityTests\.testNativeAppleTranscriptionPolicyPreservesMacOSErrorCopy' \
  'TranscriptionModelAvailabilityTests\.testNativeAppleFailureKindIsSharedThrowableLocalizedError' \
  'TranscriptionModelAvailabilityTests\.testNativeAppleTranscriptionPolicyPreservesSelectionAndTimeoutCopy'

require_patterns \
  "macOS transcription model manager applies shared local Whisper runtime update" \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift \
  'localWhisperRuntimeUpdate' \
  'shouldClearLoadedModel' \
  'isModelLoadedAfterUpdate'

require_patterns \
  "macOS transcription model manager delegates deletion cleanup to shared plan" \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift \
  'VoiceInkTranscriptionModelDeletionPlan' \
  'deletionPlan\.shouldClearCurrentModel' \
  'deletionPlan\.localWhisperRuntimeUpdate'

require_patterns \
  "core checks execute transcription runtime resource update tests" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'TranscriptionRuntimeResourcePolicyTests\.testModelSelectionResourceActionOwnsLocalWhisperRuntimeUpdate' \
  'TranscriptionRuntimeResourcePolicyTests\.testDeletedCurrentModelPlanClearsSelectionAndMarksLocalWhisperUnloaded' \
  'TranscriptionRuntimeResourcePolicyTests\.testDeletedNonCurrentModelPlanPreservesSelectionAndLocalWhisperRuntime'

reject_pattern \
  "macOS transcription model manager avoids shell-owned selection resource case check" \
  'modelSelectionResourceAction == \.clearLocalWhisperModelAndMarkLoaded' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

reject_pattern \
  "macOS transcription model manager avoids shell-owned deleted-current-model comparison" \
  'currentTranscriptionModel\?\.name == modelName' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

reject_pattern \
  "macOS streaming session route avoids shell-only FluidAudio provider checks" \
  'model\.provider == \.fluidAudio' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift \
  VoiceInk/Transcription/Streaming/StreamingTranscriptionService.swift

reject_pattern \
  "macOS runtime resource routing avoids shell-only provider checks" \
  'switch +model\.provider|model\.provider == \.whisper|case +\.whisper, +\.fluidAudio' \
  VoiceInk/Services/ModelPrewarmService.swift \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recording startup uses shared local Whisper model lookup" \
  'VoiceInkWhisperModelFiles\.downloadedLocalModelFile' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS recording startup avoids shell-owned local Whisper model lookup" \
  'availableModels\.first\(where:' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS transcription model manager avoids shell-owned provider availability routing" \
  'switch +model\.provider|model\.provider != \.whisper|availableModels\.contains|CloudProviderRegistry\.provider\(for: model\.provider\)|case +\.nativeApple|case +\.custom|transcriptionModelAvailabilityRequirement == \.(currentOSSupport|configuredAPIKey)' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

reject_pattern \
  "macOS Native Apple runtime policy avoids shell-owned literals and timeout math" \
  '"(SpeechAnalyzer requires macOS 26 or later\.|Transcription failed using SpeechAnalyzer\.|The selected language is not supported by SpeechAnalyzer\.|Invalid model type provided for Native Apple transcription\.|Download required for|Apple Speech did not finish returning transcription results\.)"|max\(20\.0|audioDuration \* 4\.0 \+ 10\.0' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift \
  VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift

reject_pattern \
  "macOS session creation avoids shell-only streaming support wrapper" \
  'private func supportsStreaming\(model:' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

reject_pattern \
  "macOS transcription service registry avoids shell-owned streaming route invariant" \
  'fatalError\("Streaming route plan missing streaming adapter details\."\)|guard let streamingAdapterKind = routePlan\.streamingAdapterKind|routePlan\.usesStreaming' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

require_pattern \
  "core checks execute transcription session execution plan tests" \
  'TranscriptionStreamingPreferenceTests\.testSessionRouteExecutionPlanUsesFileServiceWhenStreamingDisabled|TranscriptionStreamingPreferenceTests\.testSessionRouteExecutionPlanPackagesStreamingAdapterPreloadAndTimeout' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared transcription session execution plan" \
  'VoiceInkTranscriptionSessionExecutionPlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS AI API-key view uses shared AI draft policy" \
  'apiKeyFormState\.draft' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared macOS AI API-key form state lives in VoiceInkCore" \
  'struct +VoiceInkAIEnhancementAPIKeyFormState' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key form state owns verification start" \
  'verifying\(\)' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key form state owns verification completion" \
  'completedVerification' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key form state owns failure copy" \
  'verificationFailureAlertMessage' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI API-key view uses shared AI form state" \
  'VoiceInkAIEnhancementAPIKeyFormState' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS AI API-key view routes entry through shared AI form state" \
  'apiKeyFormState\.(draft|enteredKey|isVerifying|verifying|completedVerification)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared macOS AI API-key failure messages live in VoiceInkCore" \
  'missingVerificationCandidateMessage|invalidOrMissingBaseURLConfigurationMessage|unsupportedAPIKeyVerificationMessage' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key form state uses shared verification progress type" \
  'VoiceInkProviderAPIKeyVerificationProgress\.failure' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key form state uses shared verification feedback copy" \
  'macOSInlineFeedback' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI API-key view uses shared obfuscated-key fallback" \
  'VoiceInkSecretPresentation\.obfuscatedAPIKeyOrPlaceholder' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI API-key view avoids shallow draft-key wrapper" \
  'private +var +(hasDraftAPIKey|apiKeyDraft)\b' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI API-key view avoids shallow obfuscated-key wrapper" \
  'private +var +obfuscatedSelectedAPIKey\b' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS AI service resolves keys through shared AI draft policy" \
  'VoiceInkAIEnhancementAPIKeyDraft' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "shared macOS AI API-key verification application plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan|verificationApplicationPlan\(|providerKeyStorageNameToSave' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key verification persistence plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementAPIKeyVerificationPersistencePlan|successPersistencePlan' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key verification service-state plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan|serviceStateApplicationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key verification request plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementAPIKeyVerificationRequestPlan|verificationRequestPlan|resolvedKeyToVerify|immediateResult' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key verification dispatch plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan|VoiceInkAIEnhancementAPIKeyVerificationDispatch|openAICompatibleModels\(requestURL:|openRouterModels\(model:' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "core checks execute shared macOS AI API-key verification request plan test" \
  'AIProviderCatalogTests\.testMacOSAIEnhancementAPIKeyVerificationRequestPlanIsShared' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared macOS AI API-key verification dispatch plan test" \
  'AIProviderCatalogTests\.testMacOSAIEnhancementAPIKeyVerificationDispatchPlanIsShared' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared macOS AI API-key verification persistence plan test" \
  'AIProviderCatalogTests\.testMacOSAIEnhancementAPIKeyVerificationPlanBuildsSuccessPersistencePlan' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared macOS AI API-key verification service-state plan test" \
  'AIProviderCatalogTests\.testMacOSAIEnhancementAPIKeyVerificationPlanBuildsServiceStateApplicationPlan' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared macOS AI API-key clear plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementAPIKeyClearPlan|credentialStateAfterClear|providerKeyStorageNameToDelete|clearing\(provider:' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key clear persistence plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementAPIKeyClearPersistencePlan|persistencePlan' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared macOS AI API-key clear service-state plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementAPIKeyClearServiceStatePlan|serviceStateApplicationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "core checks execute shared macOS AI API-key clear plan test" \
  'AIProviderCatalogTests\.testMacOSAIEnhancementAPIKeyClearPlanIsShared' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared macOS AI API-key clear persistence and state plan test" \
  'AIProviderCatalogTests\.testMacOSAIEnhancementAPIKeyClearPlanBuildsPersistenceAndStatePlans' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS AI service applies API-key verification through shared plan" \
  'verificationApplicationPlan\(|serviceStateApplicationPlan|completionResult' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service starts API-key verification through shared request plan" \
  'verificationRequestPlan\(\)|resolvedKeyToVerify\(from:' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service dispatches API-key verification through shared plan" \
  'VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan\.plan|dispatchPlan\.action' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service applies API-key clear through shared plan" \
  'VoiceInkAIEnhancementAPIKeyClearPlan\.clearing|applyTextEnhancementAPIKeyClearPlan|serviceStateApplicationPlan|applyAIEnhancementAPIKeyClearPlan' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS API-key manager applies AI clear persistence through shared plan" \
  'applyAIEnhancementAPIKeyClearPlan|persistencePlan\.providerKeyStorageNameToDelete|deleteAPIKey\(forProvider: persistencePlan\.providerKeyStorageNameToDelete\)' \
  VoiceInk/Services/APIKeyManager.swift

require_pattern \
  "migration checklist tracks shared macOS AI API-key verification request plan" \
  'verification-request planning.*VoiceInkAIEnhancementAPIKeyVerificationRequestPlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared macOS AI API-key verification dispatch plan" \
  'verification-dispatch planning.*VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared macOS AI API-key verification service-state plan" \
  'verification service-state application planning.*VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared macOS AI API-key clear plan" \
  'clear-key planning.*VoiceInkAIEnhancementAPIKeyClearPlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared macOS AI API-key clear storage-name plan" \
  'clear-key storage-name planning.*VoiceInkAIEnhancementAPIKeyClearPersistencePlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared macOS AI API-key clear service-state plan" \
  'clear-key service-state application planning.*VoiceInkAIEnhancementAPIKeyClearServiceStatePlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS AI service delegates verified-key persistence to API-key manager" \
  'APIKeyManager\.shared\.applyAIEnhancementVerificationPlan\(' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS API-key manager applies AI verified-key persistence storage name from shared plan" \
  'successPersistencePlan|persistencePlan\.providerKeyStorageNameToSave|saveAPIKey\(keyToSave, forProvider: providerKeyStorageNameToSave\)' \
  VoiceInk/Services/APIKeyManager.swift

reject_pattern \
  "macOS API-key manager avoids shell-owned AI verification persistence field reads" \
  'plan\.runtimeAPIKey|plan\.providerKeyStorageNameToSave|plan\.keyToSave' \
  VoiceInk/Services/APIKeyManager.swift

require_pattern \
  "migration checklist tracks shared macOS AI verified-key persistence storage-name plan" \
  'verified-key persistence storage-name planning.*VoiceInkAIEnhancementAPIKeyDraft' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS AI service avoids shell-owned verified-key persistence sequencing" \
  'plan\.keyToSave|saveAPIKey\(keyToSave' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned AI API-key storage-name mapping" \
  'selectedProvider\.rawValue|plan\.provider\.rawValue' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned API-key verification start policy" \
  'resolvedVerificationCandidate|missingVerificationCandidateMessage|guard selectedProvider\.requiresUserAPIKey' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned API-key verification result field reads" \
  'plan\.isValid|plan\.errorMessage' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned API-key clear policy" \
  'apiKey = ""|isAPIKeyValid = false|deleteAPIKey\(forProvider: (selectedProvider|plan\.provider)\.rawValue\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned API-key clear plan field reads" \
  'plan\.credentialStateAfterClear|plan\.providerKeyStorageNameToDelete' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service keeps private verification adapter on shared result type" \
  'completion: @escaping \(VoiceInkAPIKeyVerificationResult\) -> Void' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids tuple-shaped API-key verification completions" \
  'completion: @escaping \(Bool, String\?\) -> Void' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids tuple-shaped API-key verification adapter results" \
  'let result: \(isValid: Bool, errorMessage: String\?\)|VoiceInkAPIKeyVerificationResult\(isValid: isValid, errorMessage: errorMessage\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI API-key view submits shared AI form state key" \
  'saveAPIKey\(apiKeyFormState\.enteredKey\)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS AI API-key view handles save failures through shared form state" \
  'verificationFailureAlertMessage\(for: result\)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI API-key view avoids tuple-shaped save result handling" \
  'saveAPIKey\(apiKey\) \{ success, errorMessage|showAPIKeyVerificationFailure\(errorMessage\)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI API-key view avoids shell-owned API-key form state machine fields" \
  '@State private var +(apiKey|isVerifying)\b' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI API-key view avoids shell-owned verification failure presentation" \
  'VoiceInkProviderAPIKeyVerificationProgress\.failure|macOSInlineFeedback' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI service avoids shell-only API-key verification success branching" \
  'if isValid \{|self\.apiKey = resolvedKey|APIKeyManager\.shared\.saveAPIKey\(key,' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned API-key verification dispatch failure policy" \
  'selectedProvider\.unsupportedAPIKeyVerificationMessage|invalidOrMissingBaseURLConfigurationMessage|guard let route = selectedProvider\.apiKeyVerificationRoute' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "shared AI enhancement credential-state policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementCredentialState|VoiceInkAIEnhancementCredentialStateResolutionPlan|textEnhancementCredentialState|providerKeyStorageNameToLoad|userAPIKeyStorageName' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "core checks execute shared AI enhancement credential-state resolution plan test" \
  'AIProviderCatalogTests\.testMacOSAIEnhancementCredentialStateResolutionPlanIsShared' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared AI enhancement provider-selection plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementProviderSelectionPlan|shouldRefreshOllamaRuntimeModels|selectedProviderToSave' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared AI enhancement provider-selection persistence application lives in VoiceInkCore" \
  'applyProviderSelectionPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "core tests pin shared AI enhancement provider-selection planning" \
  'testMacOSAIEnhancementProviderSelectionPlanIsShared|testAIEnhancementProviderPreferenceAppliesProviderSelectionPlan' \
  VoiceInkCore/Tests/VoiceInkCoreTests/AIProviderCatalogTests.swift \
  VoiceInkCore/Tests/VoiceInkCoreTests/UserDefaultsPreferencesTests.swift \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS AI service selected-provider mutation uses shared plan" \
  'VoiceInkAIEnhancementProviderSelectionPlan\.selecting|applyTextEnhancementProviderSelectionPlan|VoiceInkAIEnhancementProviderPreference\.applyProviderSelectionPlan|shouldRefreshOllamaRuntimeModels' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "migration checklist tracks shared AI enhancement provider-selection planning" \
  'selected-provider mutation planning.*VoiceInkAIEnhancementProviderSelectionPlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared AI enhancement connected-provider key storage selection lives in VoiceInkCore" \
  'textEnhancementProviderKeyStorageNamesToCheck|providerKeyStorageNamesWithKeys|userAPIKeyStorageName' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI service connected-provider key checks use shared storage names" \
  'textEnhancementProviderKeyStorageNamesToCheck|providerKeyStorageNamesWithKeys|connectedTextEnhancementProviders' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned connected-provider key storage mapping" \
  'hasUserAPIKey:|hasAPIKey\(forProvider: \$0\.rawValue\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "migration checklist tracks shared connected-provider key storage selection" \
  'connected-provider key-storage name selection' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS AI service credential-state selection uses shared policy" \
  'VoiceInkAIEnhancementCredentialStateResolutionPlan\.resolving|providerKeyStorageNameToLoad|plan\.credentialState' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned credential-state key lookup policy" \
  'selectedProvider\.requiresUserAPIKey|APIKeyManager\.shared\.getAPIKey\(forProvider: selectedProvider\.rawValue\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service Local CLI credential refresh uses shared policy" \
  'applyCredentialStateForSelectedProvider' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "migration checklist tracks shared AI enhancement credential-state resolution planning" \
  'credential-state resolution planning.*VoiceInkAIEnhancementCredentialStateResolutionPlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared Local CLI configuration lives in VoiceInkCore" \
  'VoiceInkMacOSLocalCLISettingsPresentation|macOSSettingsPresentation|VoiceInkLocalCLITemplate|VoiceInkLocalCLIExecutionError|VoiceInkLocalCLIPreference|commandTemplateKey = "localCLICommandTemplate"|selectedTemplateKey = "localCLISelectedTemplate"|timeoutSecondsKey = "localCLITimeoutSeconds"|defaultTimeoutSeconds|timeoutOptions|boundedTimeoutSeconds|isCommandConfigured|cleanedOutput|commandFailureError|fullPrompt' \
  VoiceInkCore/Sources/VoiceInkCore/LocalCLIConfiguration.swift

require_pattern \
  "macOS Local CLI service uses shared configuration policy" \
  'VoiceInkLocalCLIPreference\.(saveCommandTemplate|saveSelectedTemplate|boundedTimeoutSeconds|saveTimeoutSeconds|isCommandConfigured|selectedTemplate|commandTemplate|timeoutSeconds|fullPrompt|cleanedOutput|commandFailureError)|VoiceInkLocalCLIExecutionError' \
  VoiceInk/Services/AIEnhancement/LocalCLIService.swift

require_pattern \
  "core checks execute Local CLI execution error tests" \
  'LocalCLIConfigurationTests\.testLocalCLIExecutionErrorsPreserveMacOSCopyAndFailureClassification' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS AI service exposes shared Local CLI template type" \
  'VoiceInkLocalCLITemplate' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI settings use shared Local CLI templates and timeout options" \
  'VoiceInkLocalCLITemplate\.allCases|VoiceInkLocalCLIPreference\.(defaultTimeoutSeconds|timeoutOptions|timeoutLabel|macOSSettingsPresentation)|localCLIPresentation\.(commandTitle|loadTemplateButtonTitle|timeoutPickerTitle|environmentHelpText|configurationRequiredHelpText)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI settings avoid shell-owned Local CLI settings copy" \
  '"(Command|Load Template|Timeout|Environment variables available: VOICEINK_SYSTEM_PROMPT, VOICEINK_USER_PROMPT, VOICEINK_FULL_PROMPT\. VoiceInk also writes VOICEINK_FULL_PROMPT to stdin for every command\.|Load a template or enter a command to enable Local CLI enhancement\.)"' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared preference reset clears Local CLI settings" \
  'VoiceInkLocalCLIPreference\.clear' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "migration checklist tracks shared Local CLI configuration gate" \
  'macOS Local CLI template identity, settings labels/help, command template catalog, command/selected-template/timeout storage, timeout default/options/clamp, configured-command predicate, full-prompt wrapper, stdout/stderr cleanup, command-failure classification, and execution error copy route through `VoiceInkLocalCLITemplate`/`VoiceInkLocalCLIPreference`/`VoiceInkLocalCLIExecutionError`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared AI enhancement default text model policy lives in VoiceInkCore" \
  'defaultTextEnhancementModel|defaultOllamaTextEnhancementModel|legacyOllamaServiceSelectedModelFallback|ollamaTextEnhancementRequestTemperature|localCLITextEnhancementModel' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared AI enhancement selected-provider default lives in VoiceInkCore" \
  'defaultSelectedProvider = VoiceInkAIEnhancementProviderKind\.gemini' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS AI service reads selected provider through shared default policy" \
  'VoiceInkAIEnhancementProviderPreference\.selectedProvider\(from: userDefaults\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned selected-provider default" \
  'selectedProvider\(.*default: *\.gemini|default: *VoiceInkAIEnhancementProviderKind\.gemini' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service default text model selection uses shared policy" \
  'defaultTextEnhancementModel' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS Power Mode AI default text model selection uses shared policy" \
  'defaultTextEnhancementModel' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS AI settings Ollama default model selection uses shared policy" \
  'defaultOllamaTextEnhancementModel' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS Ollama service selected-model fallback uses shared policy" \
  'VoiceInkDynamicAIProviderPreference\.ollamaRuntimeSelectedModel\(\)' \
  VoiceInk/Services/OllamaService.swift

require_pattern \
  "macOS Ollama service request temperature uses shared policy" \
  'ollamaTextEnhancementRequestTemperature' \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS Ollama service avoids duplicate request temperature policy" \
  'defaultTemperature|temperature: +0\.3' \
  VoiceInk/Services/OllamaService.swift

require_pattern \
  "shared AI enhancement static text model list policy lives in VoiceInkCore" \
  'staticTextEnhancementModels' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared AI enhancement available-model source policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementModelCatalogSource|textEnhancementModelCatalogSource|textEnhancementAvailableModels' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI service available-model source selection uses shared policy" \
  'textEnhancementAvailableModels' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service dynamic-provider orchestration uses shared classification policy" \
  'textEnhancementModelCatalogSource|textEnhancementSettingsSurface' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI settings model-source display uses shared policy" \
  'supportsUserInitiatedTextEnhancementModelRefresh|textEnhancementModelCatalogSource' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared AI enhancement settings surface policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementSettingsSurface|textEnhancementSettingsSurface' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI settings provider surfaces use shared policy" \
  'textEnhancementSettingsSurface|selectedProviderSettingsSurface' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared AI enhancement provider connection status presentation lives in VoiceInkCore" \
  'VoiceInkAIEnhancementProviderSettingsPresentation|VoiceInkAIEnhancementConnectionStatusPresentation|connectionStatus\(' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI settings provider connection status uses shared presentation" \
  'connectionStatusPresentation|VoiceInkAIEnhancementProviderSettingsPresentation\.macOS|tone\.macOSStatusColor' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI settings avoid shallow connection-status presentation wrappers" \
  'private var +connectionStatusPresentation\b' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI settings avoid shallow provider-surface wrappers" \
  'private var +selectedProviderSettingsSurface\b' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI settings avoid duplicate provider connection status copy and branching" \
  '"(Connected|Disconnected)"|selectedProviderSettingsSurface != \.ollama|else if !ollamaModels\.isEmpty' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared AI provider settings chrome and Ollama presentation lives in VoiceInkCore" \
  'sectionTitle|providerPickerTitle|modelPickerTitle|noModelsLoadedText|refreshButtonTitle|defaultAPIKeyRemoveButtonTitle|getAPIKeyButtonTitle|errorAlertTitle|errorAlertDismissButtonTitle|ollamaBaseURLFieldTitle|ollamaSaveButtonTitle|ollamaEditButtonTitle|ollamaResetButtonHelp|ollamaConnectionFailureMessage|ollamaServerText' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI settings chrome and Ollama form use shared presentation" \
  'providerSettingsPresentation\.(sectionTitle|providerPickerTitle|modelPickerTitle|noModelsLoadedText|refreshButtonTitle|defaultAPIKeyRemoveButtonTitle|getAPIKeyButtonTitle|errorAlertTitle|errorAlertDismissButtonTitle|ollamaBaseURLFieldTitle|ollamaSaveButtonTitle|ollamaEditButtonTitle|ollamaResetButtonHelp|ollamaConnectionFailureMessage|ollamaServerText)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI settings avoid duplicate provider chrome and Ollama presentation copy" \
  '"(AI Provider Integration|Provider|No models loaded|Refresh|Model|Base URL|Save|Edit|Reset to default|Remove|Get API Key|Error|OK)"|Server:|Could not connect to Ollama' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared custom provider settings presentation and submit policy lives in VoiceInkCore" \
  'apiKeyFieldTitle|verifyAndSaveButtonTitle|customProviderBaseURLFieldTitle|customProviderBaseURLPlaceholder|customProviderModelFieldTitle|customProviderModelPlaceholder|customProviderAPIKeySetText|customProviderRemoveKeyButtonTitle|canSubmitCustomProvider' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI settings custom provider form uses shared presentation and submit policy" \
  'providerSettingsPresentation\.(apiKeyFieldTitle|verifyAndSaveButtonTitle|customProviderBaseURLFieldTitle|customProviderBaseURLPlaceholder|customProviderModelFieldTitle|customProviderModelPlaceholder|customProviderAPIKeySetText|customProviderRemoveKeyButtonTitle|canSubmitCustomProvider)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI settings avoid duplicate custom provider form copy and submit branching" \
  '"(API Endpoint URL|Model Name|API Key Set|API Key|Remove Key|Verify and Save)"|"e\.g\. https://api\.openai\.com/v1/chat/completions"|"e\.g\. gemini-3\.1-pro-preview, gpt-5\.5"|customBaseURL\.isEmpty \|\| aiService\.customModel\.isEmpty' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS Power Mode model refresh display uses shared policy" \
  'supportsUserInitiatedTextEnhancementModelRefresh' \
  VoiceInk/PowerMode/PowerModeConfigView.swift \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "macOS Power Mode model section display uses shared AI settings surface policy" \
  'textEnhancementSettingsSurface' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared AI enhancement request URL selection lives in VoiceInkCore" \
  'textEnhancementRequestURLString|textEnhancementRequestURL|invalidTextEnhancementRequestURLMessage|postProcessingRequestURL' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI service request URL selection uses shared policy" \
  'textEnhancementRequestURL' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI enhancement service request URL selection uses shared policy" \
  'openAICompatibleRequestOrThrow|requestPlan\.requestURL' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "shared AI enhancement model-selection plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementModelSelectionPlan|ollamaModelToApply|selectedModelToSave' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared AI enhancement model-selection persistence application lives in VoiceInkCore" \
  'applyModelSelectionPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "core tests pin shared AI enhancement model-selection planning" \
  'testMacOSAIEnhancementModelSelectionPlanIsShared|testAIEnhancementProviderPreferenceAppliesModelSelectionPlan' \
  VoiceInkCore/Tests/VoiceInkCoreTests/AIProviderCatalogTests.swift \
  VoiceInkCore/Tests/VoiceInkCoreTests/UserDefaultsPreferencesTests.swift \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS AI service selected-model mutation uses shared plan" \
  'VoiceInkAIEnhancementModelSelectionPlan\.selecting|applyTextEnhancementModelSelectionPlan|VoiceInkAIEnhancementProviderPreference\.applyModelSelectionPlan|ollamaModelToApply' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "migration checklist tracks shared AI enhancement model-selection planning" \
  'selected-model mutation planning.*VoiceInkAIEnhancementModelSelectionPlan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared AI enhancement refresh model-selection policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementModelRefreshPlan|textEnhancementModelToSelectAfterRefresh' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "shared AI enhancement refresh persistence application lives in VoiceInkCore" \
  'applyModelRefreshPlan|applyOpenRouterModelRefreshPlan|applyOllamaModelRefreshPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "core tests pin shared AI enhancement refresh persistence application" \
  'testAIEnhancementProviderPreferenceAppliesModelRefreshPlan|testDynamicAIProviderPreferenceAppliesOpenRouterModelRefreshPlan|testDynamicAIProviderPreferenceAppliesOllamaModelRefreshPlan' \
  VoiceInkCore/Tests/VoiceInkCoreTests/UserDefaultsPreferencesTests.swift \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS AI service refresh model application uses shared policy" \
  'VoiceInkAIEnhancementModelRefreshPlan\.(refreshed|failed)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service refresh persistence uses shared application policy" \
  'VoiceInkDynamicAIProviderPreference\.applyOpenRouterModelRefreshPlan' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS Ollama service refresh model application uses shared policy" \
  'VoiceInkAIEnhancementModelRefreshPlan\.refreshed' \
  VoiceInk/Services/OllamaService.swift

require_pattern \
  "macOS Ollama service refresh persistence uses shared application policy" \
  'VoiceInkDynamicAIProviderPreference\.applyOllamaModelRefreshPlan' \
  VoiceInk/Services/OllamaService.swift

require_pattern \
  "shared AI enhancement execution route policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementExecutionRoute|VoiceInkAIEnhancementRequestExecutionPlan|textEnhancementExecutionRoute|openAICompatibleRequestOrThrow' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI enhancement service execution routing uses shared policy" \
  'VoiceInkAIEnhancementRequestExecutionPlan\.planning|executionPlan\.route|openAICompatibleRequestOrThrow' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "shared AI chat request parameter planning lives in VoiceInkCore" \
  'VoiceInkAIChatRequestParameters|chatRequestParameters' \
  VoiceInkCore/Sources/VoiceInkCore/AIReasoningConfig.swift

require_pattern \
  "macOS AI enhancement request tuning uses shared execution plan" \
  'requestPlan\.requestParameters\.(temperature|reasoningEffort|extraBodyParameters)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service reads shared timeout preference directly" \
  'VoiceInkAIEnhancementRequestPreference\.timeoutSeconds\(\)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service reads shared retry-on-timeout preference directly" \
  'VoiceInkAIEnhancementRequestPreference\.shouldRetryOnTimeout\(\)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "iOS post-processing request tuning uses shared policy" \
  'chatRequestParameters' \
  VoiceInkCore/Sources/VoiceInkCore/PostProcessingClient.swift

section "obsolete standalone post-processing request module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/PostProcessingRequest.swift

require_pattern \
  "shared post-processing request policy lives with post-processing client" \
  'VoiceInkPostProcessingRequest|finalizedTranscript|defaultTemperature' \
  VoiceInkCore/Sources/VoiceInkCore/PostProcessingClient.swift

reject_pattern \
  "macOS AI API-key path avoids shell-only key-reference and blank-key policy" \
  'VoiceInkAPIKeyReference\.resolvedValue|VoiceInkProviderCredential\.nonBlank\(apiKey\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI service avoids duplicate API-key failure copy" \
  'Environment variable is missing or empty|Invalid or missing base URL configuration|does not support API key verification' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids duplicate credential-state policy" \
  'selectedProvider == \.localCLI \? localCLIService\.isConfigured : true|isAPIKeyValid = localCLIService\.isConfigured' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned selected-provider mutation policy" \
  'VoiceInkAIEnhancementProviderPreference\.saveSelectedProvider\(|selectedProvider\.textEnhancementModelCatalogSource == \.ollamaRuntime' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS Local CLI adapter avoids shell-owned template and preference policy" \
  'enum +LocalCLITemplate|enum +LocalCLIError|"(localCLICommandTemplate|localCLISelectedTemplate|localCLITimeoutSeconds|Local CLI command is not configured|Local CLI command was not found|Local CLI command timed out|Local CLI command failed with exit code|Local CLI command returned empty output|Failed to execute Local CLI command)"|defaultTimeoutSeconds|max\(5, timeoutSeconds\)|makeFullPrompt|cleanOutput\(' \
  VoiceInk/Services/AIEnhancement/LocalCLIService.swift

reject_pattern \
  "macOS AI settings avoid duplicate Local CLI timeout options" \
  'Text\("(15|30|45|60|90|120|180|300)s"\)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI service avoids duplicate default text model policy" \
  '"(mistral|local-cli)"|ollamaSelectedModel\(fallback:' \
  VoiceInk/Services/AIEnhancement/AIService.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS AI settings avoids duplicate default text model literals" \
  '"(mistral|local-cli)"' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI service avoids duplicate static text model list policy" \
  'extension +VoiceInkAIEnhancementProviderKind|VoiceInkAIModelCatalog\.availableModels\(for: provider\)|provider\.availableModels' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids duplicate available-model source policy" \
  'provider == \.(ollama|openRouter)|return +openRouterModels|return +provider\.staticTextEnhancementModels' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids duplicate dynamic-provider classification policy" \
  'selectedProvider == \.(ollama|localCLI)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-owned selected-model mutation policy" \
  'selectedModels\[selectedProvider\] = model|VoiceInkAIEnhancementProviderPreference\.saveSelectedModel\(|updateSelectedOllamaModel\(model\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shallow OpenRouter model-loading wrapper" \
  'private +func +loadSavedOpenRouterModels\(' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shallow OpenRouter model-saving wrapper" \
  'private +func +saveOpenRouterModels\(' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI settings avoid duplicate OpenRouter model-source policy" \
  'selectedProvider == \.openRouter|selectedProvider != \.custom|provider == \.openRouter' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

reject_pattern \
  "macOS AI settings avoid duplicate provider settings-surface policy" \
  'selectedProvider (==|!=) \.(ollama|localCLI|custom)' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS Power Mode avoids duplicate Custom model-section policy" \
  'provider != \.custom' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS AI service avoids duplicate refresh model-selection policy" \
  'currentModel == .*defaultTextEnhancementModel|models\.first!|textEnhancementModelToSelectAfterRefresh' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI services avoid shell-owned refresh selected-model persistence policy" \
  'plan\.selectedModelToSave|saveOpenRouterModels\(plan\.refreshedModelNames|saveOllamaSelectedModel\(plan\.selectedModelToSave' \
  VoiceInk/Services/AIEnhancement/AIService.swift \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS AI service avoids shell-owned OpenRouter refresh cache decisions" \
  'self\.openRouterModels = models|self\.openRouterModels = \[\]' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS Ollama service avoids duplicate refresh model-selection policy" \
  'models\.contains\(where: \{ \$0\.name == selectedModel \}\)|models\[0\]\.name|textEnhancementModelToSelectAfterRefresh' \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS AI services avoid duplicate request URL selection policy" \
  'var +baseURL: +String|selectedProvider\.baseURL|URL\(string: .*textEnhancementRequestURLString|invalid API endpoint URL' \
  VoiceInk/Services/AIEnhancement/AIService.swift \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids duplicate execution route policy" \
  'selectedProvider == \.(ollama|localCLI)|switch +aiService\.selectedProvider|case +\.anthropic:' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shallow timeout preference wrapper" \
  'private +var +baseTimeout\b' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS Ollama enhancement avoids shell-owned timeout fallback" \
  'timeout: +TimeInterval += +30' \
  VoiceInk/Services/AIEnhancement/AIService.swift \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS AI enhancement service avoids shallow retry-on-timeout preference wrapper" \
  'private +var +retryOnTimeout\b|case +\.timeout +where +retryOnTimeout\b' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS/iOS AI request tuning avoids duplicate reasoning parameter assembly" \
  'VoiceInkAIReasoningConfig\.(temperature|reasoningEffort|extraBodyParameters)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift \
  VoiceInkCore/Sources/VoiceInkCore/PostProcessingClient.swift

reject_pattern \
  "macOS AI API-key view avoids duplicate verification failure copy" \
  'Verification failed' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS AI API-key view avoids duplicate obfuscated-key fallback copy" \
  '••••••••' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared AI enhancement rate-limit policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementRateLimitPolicy|delaySinceLastRequest' \
  VoiceInkCore/Sources/VoiceInkCore/AIEnhancementRetryPolicy.swift

require_pattern \
  "shared AI enhancement non-enhancement error retry plan lives in VoiceInkCore" \
  'VoiceInkAIEnhancementNonEnhancementErrorRetryPlan|recordNonEnhancementError' \
  VoiceInkCore/Sources/VoiceInkCore/AIEnhancementRetryPolicy.swift

require_pattern \
  "core checks execute AI enhancement retry default policy test" \
  'AIEnhancementRetryPolicyTests\.testDefaultRetryStatePreservesMacOSAttemptAndDelayDefaults' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared AI enhancement retry-failure presentation lives in VoiceInkCore" \
  'VoiceInkAIEnhancementRetryFailurePresentation|diagnosticMessage' \
  VoiceInkCore/Sources/VoiceInkCore/AIEnhancementRetryPolicy.swift

require_pattern \
  "shared AI enhancement retry-progress presentation lives in VoiceInkCore" \
  'VoiceInkAIEnhancementRetryProgressPresentation|diagnosticMessage' \
  VoiceInkCore/Sources/VoiceInkCore/AIEnhancementRetryPolicy.swift

require_pattern \
  "shared AI enhancement request payload lives in VoiceInkCore" \
  'VoiceInkAIEnhancementRequestPayload|VoiceInkAIEnhancementRequestPreparation|taggedTranscript|enhancedText' \
  VoiceInkCore/Sources/VoiceInkCore/AIPrompts.swift

section "obsolete standalone AI request prompts module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/AIRequestPrompts.swift

require_pattern \
  "macOS AI enhancement service uses shared request payload" \
  'VoiceInkAIEnhancementRequestPreparation\.preparing|requestPayload\.userMessage|VoiceInkAIEnhancementRequestPayload\.enhancedText' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "core checks execute AI enhancement request preparation test" \
  'AIPromptsTests\.testEnhancementRequestPreparationPreservesMacOSPreflightPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

section "obsolete standalone AI enhancement output filter module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/AIEnhancementOutputFilter.swift

require_patterns \
  "AI enhancement output filter lives with request preparation policy" \
  VoiceInkCore/Sources/VoiceInkCore/AIPrompts.swift \
  'VoiceInkAIEnhancementOutputFilter' \
  'codex_follow_up' \
  'VoiceInkAIEnhancementRequestPayload'

require_pattern \
  "core checks execute AI enhancement retry-failure presentation test" \
  'AIEnhancementRetryPolicyTests\.testRetryFailurePresentationPreservesMacOSLogMessages' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute AI enhancement retry-progress presentation test" \
  'AIEnhancementRetryPolicyTests\.testRetryProgressPresentationPreservesMacOSLogMessages' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute AI enhancement non-enhancement error retry plan test" \
  'AIEnhancementRetryPolicyTests\.testNonEnhancementErrorRetryPlanHandlesOnlyRetryableTransportFailures' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned request payload and output filtering" \
  'guard +!text\.isEmpty|guard +isConfigured|VoiceInkAIEnhancementRequestPayload\(transcript: text\)|VoiceInkAIRequestPrompts\.taggedTranscript|VoiceInkAIEnhancementOutputFilter\.filter' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service uses shared rate-limit policy" \
  'VoiceInkAIEnhancementRateLimitPolicy|delaySinceLastRequest' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service uses shared non-enhancement error retry plan" \
  'recordNonEnhancementError|retryPlan\.decision|retryPlan\.isTransportNetworkFailure' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids duplicate retry attempt and delay defaults" \
  'maxRetries|initialDelay' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service uses shared retry-failure presentation" \
  'VoiceInkAIEnhancementRetryFailurePresentation\.diagnosticMessage' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service uses shared retry-progress presentation" \
  'VoiceInkAIEnhancementRetryProgressPresentation\.diagnosticMessage' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned rate-limit timing math" \
  'rateLimitInterval|timeSinceLastRequest|minimumInterval -' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned retry-failure log messages" \
  'Request timed out after|Request failed after|retry disabled' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned retry-progress log messages" \
  'Request failed, retrying|Request timed out, retrying immediately' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned non-enhancement transport retry policy" \
  'transportNetworkError\(for: error\)|recordTransportNetworkFailure\(\)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service returns shared enhancement result" \
  'VoiceInkAIEnhancementResult\.completed' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids shell-owned enhancement result duration math" \
  'timeIntervalSince\(startTime\)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "shared AI enhancement result construction lives in VoiceInkCore" \
  'static func completed|endDate\.timeIntervalSince\(startDate\)' \
  VoiceInkCore/Sources/VoiceInkCore/AIEnhancementResult.swift

require_pattern \
  "core checks execute shared AI enhancement result construction test" \
  'AIEnhancementResultTests\.testCompletedResultDerivesDurationAndPreservesMetadata' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS AI enhancement service saves enabled state through shared preference" \
  'VoiceInkAIEnhancementPreference\.saveIsEnabled' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service loads enabled state through shared preference" \
  'VoiceInkAIEnhancementPreference\.isEnabled\(\)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service saves context toggles through shared preference" \
  'VoiceInkAIEnhancementContextPreference\.saveUse(Clipboard|ScreenCapture)Context' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "macOS AI enhancement service loads context toggles through shared preference" \
  'VoiceInkAIEnhancementContextPreference\.use(Clipboard|ScreenCapture)Context\(\)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

reject_pattern \
  "macOS AI enhancement service avoids raw shared preference keys" \
  'VoiceInkUserDefaultsKey\.(isAIEnhancementEnabled|useClipboardContext|useScreenCaptureContext)' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "shared AI enhancement screen-context policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementScreenContext|VoiceInkScreenCaptureWindowFacts|preferredWindowIndex|contextText' \
  VoiceInkCore/Sources/VoiceInkCore/AIPrompts.swift

require_pattern \
  "core checks execute shared AI enhancement screen-context policy tests" \
  'AIPromptsTests\.testScreenContextPrefersFrontmostVisibleNonSelfWindow|AIPromptsTests\.testScreenContextFallsBackToFirstVisibleNonSelfWindow|AIPromptsTests\.testScreenContextTextPreservesMacOSCaptureCopy|AIPromptsTests\.testScreenContextTextUsesExistingFallbacks' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS screen capture service adapts shared screen-context policy" \
  'VoiceInkAIEnhancementScreenContext\.(preferredWindowIndex|contextText)|voiceInkScreenCaptureWindowFacts' \
  VoiceInk/Services/ScreenCaptureService.swift

reject_pattern \
  "macOS screen capture service avoids shell-owned screen-context copy and selection policy" \
  '"(Active Window:|Application:|Window Content:|No text detected via OCR|Unknown)"|content\.windows\.first|owningApplication\?\.processID == frontmostPID|owningApplication\?\.processID != currentPID|windowLayer == 0' \
  VoiceInk/Services/ScreenCaptureService.swift

require_pattern \
  "shared transcription paste output owns trial-expired prefix" \
  'trialExpiredPrefix = "Your trial has expired\. Upgrade to VoiceInk Pro at \\\(VoiceInkLicenseLinks\.purchaseDisplayURLString\)"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "shared transcription paste output owns trailing-space preference" \
  'VoiceInkAppendTrailingSpacePreference' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "shared transcription paste output owns cursor-context planning" \
  'public struct CursorPasteTextPlan|public static func cursorPasteTextPlan|shouldReadCursorContext|VoiceInkTranscriptionCleanupPreferenceStorage\.shouldLowercase' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "shared cursor text context policy owns macOS reader bounds and role filtering" \
  'VoiceInkCursorTextContextPolicy|defaultMaximumLength = 240|parentTraversalLimit = 4|textInputRoleNames|prefixLength|valueSuffix' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "shared trailing-space preference owns user-defaults key" \
  'userDefaultsKey' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "shared trailing-space preference owns default value" \
  'defaultIsEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "shared trailing-space preference owns registered defaults" \
  'registeredDefaults' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "shared trailing-space preference owns macOS settings presentation" \
  'VoiceInkMacOSAppendTrailingSpaceSettingsPresentation|macOSSettingsPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "macOS transcription pipeline uses shared paste output policy" \
  'VoiceInkTranscriptionPasteOutputPolicy\.finalPastedText' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS CursorPaster adapts shared cursor-context plan" \
  'VoiceInkTranscriptionPasteOutputPolicy\.cursorPasteTextPlan' \
  VoiceInk/Paste/CursorPaster.swift

reject_pattern \
  "macOS CursorPaster avoids shallow cursor-plan wrapper" \
  'private +static +func +cursorPasteTextPlan\(' \
  VoiceInk/Paste/CursorPaster.swift

require_pattern \
  "macOS CursorPaster owns paste text preparation" \
  'preparedTextForPaste|shouldReadCursorContext' \
  VoiceInk/Paste/CursorPaster.swift

require_pattern \
  "macOS cursor text reader adapts shared cursor-context reader policy" \
  'VoiceInkCursorTextContextPolicy\.(defaultMaximumLength|shouldAttemptRead|parentTraversalLimit|prefixLength|isTextInputRole|valueSuffix)' \
  VoiceInk/Services/CursorTextContextReader.swift

reject_pattern \
  "macOS cursor text reader avoids shell-owned cursor-context reader policy" \
  'defaultMaximumLength = 240|textInputRoles|0\.\.<4|min\(maximumLength, selectedRange\.location\)|String\(text\.suffix\(maximumLength\)\)' \
  VoiceInk/Services/CursorTextContextReader.swift

reject_pattern \
  "macOS transcription pipeline avoids shell-only paste output policy" \
  'Your trial has expired|"AppendTrailingSpace"|textToPaste \+ \(appendSpace \? " " : ""\)|VoiceInkContextualCapitalizationFormatter\.(needsCursorContext|format)|VoiceInkTranscriptionPasteOutputPolicy\.cursorPasteTextPlan' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "core checks execute preference-backed cursor paste plan test" \
  'TranscriptionPasteOutputPolicyTests\.testCursorPasteTextPlanReadsLowercaseCleanupPreference' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute cursor text context policy tests" \
  'TranscriptionPasteOutputPolicyTests\.testCursorTextContextPolicyPreservesMacOSAccessibilityReadBounds|TranscriptionPasteOutputPolicyTests\.testCursorTextContextPolicyOwnsTextInputRoles|TranscriptionPasteOutputPolicyTests\.testCursorTextContextPolicyBoundsPrefixLength|TranscriptionPasteOutputPolicyTests\.testCursorTextContextPolicyBoundsValueSuffixToTextInputRoles' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS transcription pipeline uses CursorPaster paste preparation" \
  'CursorPaster\.preparedTextForPaste' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS last-transcription paste uses CursorPaster paste preparation" \
  'CursorPaster\.preparedTextForPaste' \
  VoiceInk/Services/LastTranscriptionService.swift

require_pattern \
  "macOS defaults register shared trailing-space default" \
  'VoiceInkAppendTrailingSpacePreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS trailing-space settings use shared preference key" \
  'VoiceInkAppendTrailingSpacePreference\.userDefaultsKey|VoiceInkAppendTrailingSpacePreference\.defaultIsEnabled' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "macOS trailing-space settings use shared presentation" \
  'VoiceInkAppendTrailingSpacePreference\.macOSSettingsPresentation|appendTrailingSpacePresentation\.(toggleTitle|helpText)' \
  VoiceInk/Views/ModelSettingsView.swift

reject_pattern \
  "macOS trailing-space shells avoid raw preference key and copy" \
  'VoiceInkUserDefaultsKey\.appendTrailingSpace|VoiceInkPreferenceDefault\.appendTrailingSpace|"(AppendTrailingSpace|Add Space After Paste|Add a trailing space after pasted transcription output\.)"' \
  VoiceInk/AppDefaults.swift \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "migration checklist tracks shared paste output gate" \
  'macOS final paste text assembly routes cursor-context capitalization planning, cursor-context reader bounds/text-input role filtering, lowercase-cleanup preference gating, trial-expired prefix, trailing-space storage/default registration, and trailing-space settings labels/help through `VoiceInkTranscriptionPasteOutputPolicy`/`VoiceInkCursorTextContextPolicy`/`VoiceInkAppendTrailingSpacePreference`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared paste method preference owns raw storage key" \
  'userDefaultsKey = "pasteMethod"' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared paste method preference owns legacy AppleScript migration key" \
  'legacyAppleScriptPasteKey = "useAppleScriptPaste"' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared paste method preference owns display labels" \
  'public var displayName' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared clipboard restore preference owns enabled storage key" \
  'restoreClipboardAfterPasteKey = "restoreClipboardAfterPaste"' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared clipboard restore preference owns delay storage key" \
  'clipboardRestoreDelayKey = "clipboardRestoreDelay"' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared clipboard restore preference owns bounded delay" \
  'minimumClipboardRestoreDelay' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared paste backup preferences live in VoiceInkCore" \
  'struct VoiceInkPasteBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared paste backup import plan lives in VoiceInkCore" \
  'struct VoiceInkPasteBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared paste backup export policy lives in VoiceInkCore" \
  'static func backupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared paste backup import policy lives in VoiceInkCore" \
  'static func backupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "shared macOS paste settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSPasteSettingsPresentation|VoiceInkPasteDelayOption|macOSSettingsPresentation|restoreDelayOptions|pasteMethodHelpMessage' \
  VoiceInkCore/Sources/VoiceInkCore/PastePreferences.swift

require_pattern \
  "macOS paste adapter uses shared paste method preference" \
  'VoiceInkPasteMethod\.current\(\)' \
  VoiceInk/Paste/CursorPaster.swift

require_pattern \
  "macOS paste adapter uses shared clipboard restore preference" \
  'VoiceInkPastePreference\.(shouldRestoreClipboardAfterPaste|boundedClipboardRestoreDelay)' \
  VoiceInk/Paste/CursorPaster.swift

require_pattern \
  "macOS settings uses shared paste preferences" \
  'VoiceInkPastePreference\.(restoreClipboardAfterPasteKey|clipboardRestoreDelayKey|defaultRestoreClipboardAfterPaste|defaultClipboardRestoreDelay)|VoiceInkPasteMethod\.(userDefaultsKey|standard|allCases|setCurrent)' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS settings uses shared paste settings presentation" \
  'VoiceInkPastePreference\.macOSSettingsPresentation|pasteSettingsPresentation\.(keepClipboardContentLabel|keepClipboardContentInfoMessage|restoreDelayLabel|restoreDelayOptions|pasteMethodLabel|pasteMethodHelpMessage)' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS defaults register shared paste defaults" \
  'VoiceInkPastePreference\.registeredDefaults|VoiceInkStartupPreferenceMigration\.migrateLegacyPreferences\(for: \.macOS\)' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS diagnostics use shared paste preferences" \
  'VoiceInkPastePreference\.(shouldRestoreClipboardAfterPaste|clipboardRestoreDelay)|VoiceInkPasteMethod\.current' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS backup export uses shared paste preferences" \
  'VoiceInkPastePreference\.backupPreferences|pasteBackupPreferences\.(shouldRestoreClipboardAfterPaste|clipboardRestoreDelay)' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "shared general settings core import reads shared paste plan" \
  'applyPasteImportPlan\(importPlans\.paste' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import applies shared paste import plan" \
  'VoiceInkPastePreference\.saveShouldRestoreClipboardAfterPaste|VoiceInkPastePreference\.saveClipboardRestoreDelay' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

reject_pattern \
  "macOS backup import avoids shell-owned paste preference planning" \
  'general\.(restoreClipboardAfterPaste|clipboardRestoreDelay)' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import delegates paste preference writes to shared policy" \
  'VoiceInkPastePreference\.save(ShouldRestoreClipboardAfterPaste|ClipboardRestoreDelay)' \
  VoiceInk/Services/BackupImporter.swift

reject_file VoiceInk/Paste/PasteMethod.swift

reject_pattern \
  "macOS paste shells avoid raw paste preference keys" \
  '"(restoreClipboardAfterPaste|clipboardRestoreDelay|pasteMethod|useAppleScriptPaste)"|minimumClipboardRestoreDelay|(^|[^[:alnum:]_])PasteMethod([^[:alnum:]_]|$)' \
  VoiceInk/Paste/CursorPaster.swift \
  VoiceInk/Views/Settings/SettingsView.swift \
  VoiceInk/AppDefaults.swift \
  VoiceInk/Services/SystemInfoService.swift \
  VoiceInk/Services/ImportExportService.swift \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS settings avoids shell-only paste settings presentation copy" \
  '"(Keep Clipboard Content|Restore Delay|Paste Method|250ms|500ms|Default uses simulated Cmd\+V key events\. AppleScript can help when custom keyboard layouts do not paste correctly\.)"' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "migration checklist tracks shared paste preference gate" \
  'macOS paste method and clipboard restore settings route through `VoiceInkPasteMethod`/`VoiceInkPastePreference`, including settings labels/options/help and backup import/export plans' \
  docs/ios-single-repo-migration.md

require_file \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback preference owns system mute mode raw values" \
  'enum VoiceInkSystemMuteMode: String, CaseIterable, Identifiable' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback preference owns display labels" \
  'public var displayName' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared macOS recording feedback settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSRecordingFeedbackSettingsPresentation|VoiceInkRecordingFeedbackDelayOption|macOSSettingsPresentation|audioResumptionDelayOptions|pauseMediaInfoMessage' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback preference owns macOS storage keys" \
  'systemMuteModeKey = "systemMuteMode"|isPauseMediaEnabledKey = "isPauseMediaEnabled"|isSoundFeedbackEnabledKey = "isSoundFeedbackEnabled"|experimentalFeaturesEnabledKey = "isExperimentalFeaturesEnabled"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback preference owns system mute schedule delay" \
  'defaultSystemMuteScheduleDelayNanoseconds' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback preference owns pause-media command delay" \
  'defaultPauseMediaCommandDelayNanoseconds' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "macOS playback controller consumes shared pause-media command delay" \
  'VoiceInkRecordingFeedbackPreference\.defaultPauseMediaCommandDelayNanoseconds' \
  VoiceInk/PlaybackController.swift

reject_pattern \
  "macOS playback controller avoids shell-only pause-media command delay" \
  '50_000_000' \
  VoiceInk/PlaybackController.swift

require_pattern \
  "core checks pin pause-media command delay policy" \
  'defaultPauseMediaCommandDelayNanoseconds' \
  VoiceInkCore/Tests/VoiceInkCoreTests/RecordingFeedbackPreferenceTests.swift

require_pattern \
  "macOS recorder consumes shared system mute schedule delay" \
  'VoiceInkRecordingFeedbackPreference\.defaultSystemMuteScheduleDelayNanoseconds' \
  VoiceInk/Recorder.swift

reject_pattern \
  "macOS recorder avoids shell-only system mute schedule delay" \
  '250_000_000' \
  VoiceInk/Recorder.swift

require_pattern \
  "shared recording feedback preference preserves legacy mute boolean compatibility" \
  'legacyIsSystemMuteEnabledKey = "isSystemMuteEnabled"|saveSystemMuteEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback backup preferences live in VoiceInkCore" \
  'struct VoiceInkRecordingFeedbackBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback backup preferences carry experimental flag" \
  'isExperimentalFeaturesEnabled: Bool\?' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback backup import plan lives in VoiceInkCore" \
  'struct VoiceInkRecordingFeedbackBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback backup export policy lives in VoiceInkCore" \
  'static func backupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback backup import policy lives in VoiceInkCore" \
  'static func backupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback backup import policy maps legacy mute boolean" \
  'systemMuteMode: preferences\.isSystemMuteEnabled\.map' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback backup import policy handles experimental pause-media fallback" \
  'shouldDisablePauseMediaForExperimentalImport' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback backup import policy reads experimental flag from preferences" \
  'preferences\.isExperimentalFeaturesEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared custom recording sound catalog lives in VoiceInkCore" \
  'enum VoiceInkBuiltInRecordingSound: String, CaseIterable, Identifiable|case sound1|case sound7|fileExtension|displayName' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared custom recording sound preference owns storage keys and defaults" \
  'enum VoiceInkCustomSoundType: String, CaseIterable|isUsingKey|filenameKey|builtInSoundKey|defaultBuiltInSound|VoiceInkCustomSoundPreference|registeredDefaults|customSoundsRelativeDirectory|changedNotificationName' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_patterns \
  "shared custom recording sound settings presentation lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift \
  'VoiceInkCustomSoundMenuSelection' \
  'VoiceInkCustomSoundSettingsPresentation' \
  'label\(for type:' \
  'customMenuTitle' \
  'openPanelTitle' \
  'testButtonSystemImageName' \
  'chooseButtonSystemImageName' \
  'resetButtonSystemImageName' \
  'invalidAudioAlertTitle'

require_pattern \
  "shared custom recording sound validation and file-operation planning lives in VoiceInkCore" \
  'enum VoiceInkCustomSoundError: LocalizedError|durationTooLong|preflightValidationError|maxDuration|copiedFilename|customSoundURL|storedCustomSoundURL|VoiceInkCustomSoundCopyPlan|copyPlan|Audio file is' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording sound playback policy lives in VoiceInkCore" \
  'VoiceInkRecordingSoundCue|VoiceInkRecordingSoundPlayerSlot|VoiceInkRecordingSoundPlaybackPolicy|setupSlots|playbackSlots|volume' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "core checks cover custom sound URL and copy planning" \
  'RecordingFeedbackPreferenceTests\.testCustomSoundPreferenceBuildsCustomSoundURLs|RecordingFeedbackPreferenceTests\.testCustomSoundPreferencePlansCopyActions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks cover custom sound settings presentation" \
  'RecordingFeedbackPreferenceTests\.testCustomSoundSettingsPresentationPreservesMacOSCopyAndActions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks cover recording sound playback policy" \
  'RecordingFeedbackPreferenceTests\.testRecordingSoundPlaybackPolicyPreservesMacOSSlotsVolumesAndFallbacks' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS media controller uses shared recording feedback preferences" \
  'VoiceInkRecordingFeedbackPreference\.(systemMuteMode|saveSystemMuteMode|audioResumptionDelay|saveAudioResumptionDelay)' \
  VoiceInk/MediaController.swift

require_pattern \
  "macOS playback controller uses shared pause-media preference" \
  'VoiceInkRecordingFeedbackPreference\.(isPauseMediaEnabled|savePauseMediaEnabled)' \
  VoiceInk/PlaybackController.swift

require_pattern \
  "macOS sound manager uses shared sound-feedback preference key" \
  'VoiceInkRecordingFeedbackPreference\.isSoundFeedbackEnabledKey' \
  VoiceInk/SoundManager.swift

require_pattern \
  "macOS custom sound manager uses shared custom sound policy" \
  'VoiceInkCustomSoundPreference\.(saveIsUsingCustomSound|saveSelectedBuiltInSound|saveCustomFilename|isUsingCustomSound|selectedBuiltInSound|customFilename|customSoundsRelativeDirectory|changedNotificationName|isDefaultSelection|customSoundURL|storedCustomSoundURL|copyPlan|preflightValidationError)|VoiceInkBuiltInRecordingSound|VoiceInkCustomSoundType|VoiceInkCustomSoundError' \
  VoiceInk/CustomSoundManager.swift

reject_pattern \
  "macOS custom sound manager avoids shallow shared-type aliases" \
  'typealias +(CustomSoundError|BuiltInSound|SoundType)' \
  VoiceInk/CustomSoundManager.swift

reject_pattern \
  "macOS custom sound manager avoids shell-owned URL and copy planning" \
  'VoiceInkCustomSoundPreference\.copiedFilename|resolvingSymlinksInPath|appendingPathComponent\(filename\)|let destinationURL =|sourceURL\.pathExtension' \
  VoiceInk/CustomSoundManager.swift

require_pattern \
  "macOS sound reload uses shared custom sound notification name" \
  'VoiceInkCustomSoundPreference\.changedNotificationName' \
  VoiceInk/SoundManager.swift

require_pattern \
  "macOS sound manager wires URLs by shared playback slots" \
  'soundURLs:|\.defaultStart|\.defaultStop|\.defaultEsc|\.customStart|\.customStop' \
  VoiceInk/SoundManager.swift

require_pattern \
  "macOS sound playback engine uses shared playback policy" \
  'VoiceInkRecordingSoundPlaybackPolicy\.(setupSlots|playbackSlots)|VoiceInkRecordingSoundPlayerSlot|VoiceInkRecordingSoundCue|slot\.volume' \
  VoiceInk/SoundPlaybackEngine.swift

require_patterns \
  "macOS custom sound settings view uses shared presentation" \
  VoiceInk/Views/Settings/CustomSoundSettingsView.swift \
  'VoiceInkCustomSoundSettingsPresentation\.label' \
  'VoiceInkCustomSoundSettingsPresentation\.pickerTitle' \
  'VoiceInkCustomSoundSettingsPresentation\.customMenuTitle' \
  'VoiceInkCustomSoundSettingsPresentation\.selectSoundHelpText' \
  'VoiceInkCustomSoundSettingsPresentation\.testButtonHelpText' \
  'VoiceInkCustomSoundSettingsPresentation\.chooseButtonHelpText' \
  'VoiceInkCustomSoundSettingsPresentation\.resetButtonHelpText' \
  'VoiceInkCustomSoundSettingsPresentation\.testButtonSystemImageName' \
  'VoiceInkCustomSoundSettingsPresentation\.chooseButtonSystemImageName' \
  'VoiceInkCustomSoundSettingsPresentation\.resetButtonSystemImageName' \
  'VoiceInkCustomSoundSettingsPresentation\.openPanelTitle' \
  'VoiceInkCustomSoundSettingsPresentation\.openPanelMessage' \
  'VoiceInkCustomSoundSettingsPresentation\.invalidAudioAlertTitle' \
  'VoiceInkCustomSoundSettingsPresentation\.alertDismissButtonTitle' \
  'VoiceInkCustomSoundMenuSelection' \
  'VoiceInkBuiltInRecordingSound\.allCases'

reject_pattern \
  "macOS custom sound settings view avoids shell-only presentation copy and aliases" \
  '"(Start Sound|Stop Sound|Sound|Custom:|Custom|Select sound|Test|Choose|Reset|Choose Start Sound|Choose Stop Sound|Select an audio file|Invalid Audio File|OK|play\.fill|folder|arrow\.uturn\.backward)"|private enum SoundMenuSelection|CustomSoundManager\.(BuiltInSound|SoundType)' \
  VoiceInk/Views/Settings/CustomSoundSettingsView.swift

reject_pattern \
  "macOS sound playback engine avoids shell-owned cue fallback and volume policy" \
  'private enum Sound|startSound|stopSound|escSound|customStartSound|customStopSound|customStartSound \?\? startSound|customStopSound \?\? stopSound|volume: 0\.[34]' \
  VoiceInk/SoundPlaybackEngine.swift

require_pattern \
  "macOS defaults register shared recording feedback defaults" \
  'VoiceInkRecordingFeedbackPreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS defaults register shared custom sound defaults" \
  'VoiceInkCustomSoundPreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS diagnostics use shared recording feedback preferences" \
  'VoiceInkRecordingFeedbackPreference\.(isSoundFeedbackEnabled|isPauseMediaEnabled|systemMuteMode|audioResumptionDelay)' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS backup export uses shared recording feedback backup preferences" \
  'VoiceInkRecordingFeedbackPreference\.backupPreferences|recordingFeedbackBackupPreferences\.(isSoundFeedbackEnabled|isSystemMuteEnabled|isPauseMediaEnabled|audioResumptionDelay)' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup export emits experimental flag from shared recording feedback preferences" \
  'preferences\.recordingFeedback\.isExperimentalFeaturesEnabled' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup import reads shared recording feedback plan from grouped general settings" \
  'generalImportPlans\.recordingFeedback' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "macOS backup import applies shared recording feedback import plan" \
  'recordingFeedbackImportPlan\.(isSoundFeedbackEnabled|systemMuteMode|isPauseMediaEnabled|audioResumptionDelay|isExperimentalFeaturesEnabled|shouldDisablePauseMediaForExperimentalImport)' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "shared general settings core import applies experimental recording feedback flag" \
  'applyRecordingFeedbackCorePreferenceImportPlan\(importPlans\.recordingFeedback|VoiceInkRecordingFeedbackPreference\.saveExperimentalFeaturesEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

reject_pattern \
  "macOS backup import avoids shell-owned recording feedback planning" \
  'general\.(isSoundFeedbackEnabled|isSystemMuteEnabled|isPauseMediaEnabled|audioResumptionDelay|isExperimentalFeaturesEnabled)|mediaController\.isSystemMuteEnabled' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import delegates experimental recording feedback preference write to shared policy" \
  'VoiceInkRecordingFeedbackPreference\.saveExperimentalFeaturesEnabled' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import/export avoid raw experimental recording feedback key" \
  '"isExperimentalFeaturesEnabled"|UserDefaults\.standard\.(bool|set)\(.*isExperimentalFeaturesEnabled' \
  VoiceInk/Services/ImportExportService.swift \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "macOS settings uses shared system mute mode" \
  'VoiceInkSystemMuteMode\.allCases' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS settings uses shared recording feedback settings presentation" \
  'VoiceInkRecordingFeedbackPreference\.macOSSettingsPresentation|recordingFeedbackPresentation\.(sectionTitle|soundFeedbackLabel|systemMuteModeLabel|audioResumptionDelayLabel|audioResumptionDelayOptions)|presentation\.(experimentalSectionTitle|pauseMediaLabel|pauseMediaInfoMessage|pauseMediaResumeDelayLabel|audioResumptionDelayOptions)' \
  VoiceInk/Views/Settings/SettingsView.swift

reject_pattern \
  "macOS recording feedback shells avoid raw preference keys and shell-only mute enum" \
  '"(systemMuteMode|isSystemMuteEnabled|audioResumptionDelay|isPauseMediaEnabled|isSoundFeedbackEnabled)"|enum +SystemMuteMode|(^|[^[:alnum:]_])SystemMuteMode\.' \
  VoiceInk/MediaController.swift \
  VoiceInk/PlaybackController.swift \
  VoiceInk/SoundManager.swift \
  VoiceInk/AppDefaults.swift \
  VoiceInk/Services/SystemInfoService.swift \
  VoiceInk/Views/Settings/SettingsView.swift

reject_pattern \
  "macOS custom sound shells avoid raw custom sound policy" \
  '"(isUsingCustomStartSound|isUsingCustomStopSound|customStartSoundFilename|customStopSoundFilename|selectedStartBuiltInSound|selectedStopBuiltInSound|CustomStartSound|CustomStopSound|VoiceInk/CustomSounds|CustomSoundsChanged|Audio file not found|Invalid audio file format|Failed to create custom sounds directory|Failed to copy audio file)"|enum +CustomSoundError|enum +BuiltInSound|enum +SoundType|maxSoundDuration' \
  VoiceInk/CustomSoundManager.swift \
  VoiceInk/AppDefaults.swift \
  VoiceInk/SoundManager.swift

reject_pattern \
  "macOS settings avoids shell-only recording feedback settings presentation copy" \
  '"(Recording Feedback|Sound Feedback|Mute Audio While Recording|Audio Resume Delay|Experimental|Pause Media While Recording|Pauses playing media when recording starts and resumes when done\.|Resume Delay|0s|5s)"' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "migration checklist tracks shared recording feedback preference gate" \
  'macOS recording feedback preferences route through `VoiceInkSystemMuteMode`/`VoiceInkRecordingFeedbackPreference`, including experimental-feature backup import/export, pause-media fallback.*VoiceInkCustomSoundPreference' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared VAD preference user-defaults key lives in VoiceInkCore" \
  'public static let userDefaultsKey = VoiceInkUserDefaultsKey\.isVADEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared VAD preference default lives in VoiceInkCore" \
  'public static let defaultIsEnabled = VoiceInkPreferenceDefault\.isVADEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared VAD preference settings presentation lives in VoiceInkCore" \
  'public static let macOSSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation\.macOS\.vad' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared advanced transcription settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSAdvancedTranscriptionSettingsPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared advanced transcription settings toggle presentation lives in VoiceInkCore" \
  'VoiceInkSettingsTogglePresentation' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared model runtime preference key lives in VoiceInkCore" \
  'public static let userDefaultsKey = VoiceInkUserDefaultsKey\.prewarmModelOnWake' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recorder preview preference key lives in VoiceInkCore" \
  'public static let userDefaultsKey = VoiceInkUserDefaultsKey\.showLiveTextPreview' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared model runtime preference module lives in VoiceInkCore" \
  'public enum VoiceInkModelRuntimePreference' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared model runtime preference default lives in VoiceInkCore" \
  'public static let defaultShouldPrewarmModelOnWake = VoiceInkPreferenceDefault\.prewarmModelOnWake' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared model runtime preference settings presentation lives in VoiceInkCore" \
  'public static let macOSSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation\.macOS\.modelPrewarm' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared model runtime prewarm delay lives in VoiceInkCore" \
  'public static let prewarmScheduleDelay: Duration = \.seconds\(3\)' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_patterns \
  "shared model prewarm and warmup policy lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRuntimeResourcePolicy.swift \
  'VoiceInkModelPrewarmSamplePolicy' \
  'VoiceInkModelPrewarmPlan' \
  'VoiceInkModelPrewarmSkipReason' \
  'VoiceInkWhisperModelWarmupPolicy' \
  'VoiceInkModelPrewarmDiagnostics' \
  'VoiceInkWhisperModelWarmupDiagnostics'

require_pattern \
  "core checks execute model prewarm and warmup policy tests" \
  'testModelPrewarmSamplePolicyPreservesMacOSLookupOrder|testModelPrewarmPlanPreservesMacOSSkipOrderAndDiagnostics|testWhisperModelWarmupPolicySchedulesOnlyCoreMLModelsNotAlreadyWarming|testModelPrewarmDiagnosticsPreserveMacOSLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared model runtime preference reads policy in VoiceInkCore" \
  'shouldPrewarmModelOnWake' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared model runtime preference saves policy in VoiceInkCore" \
  'saveShouldPrewarmModelOnWake' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recorder preview preference module lives in VoiceInkCore" \
  'public enum VoiceInkRecorderPreviewPreference' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recorder preview preference default lives in VoiceInkCore" \
  'public static let defaultIsLiveTextPreviewEnabled = VoiceInkPreferenceDefault\.showLiveTextPreview' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recorder preview preference settings presentation lives in VoiceInkCore" \
  'public static let macOSSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation\.macOS\.liveTextPreview' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recorder preview preference reads policy in VoiceInkCore" \
  'isLiveTextPreviewEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recorder preview preference saves policy in VoiceInkCore" \
  'saveIsLiveTextPreviewEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS defaults register shared model runtime defaults" \
  'VoiceInkModelRuntimePreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS defaults register shared recorder preview defaults" \
  'VoiceInkRecorderPreviewPreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS model prewarm uses shared model runtime preference" \
  'VoiceInkModelRuntimePreference\.shouldPrewarmModelOnWake' \
  VoiceInk/Services/ModelPrewarmService.swift

require_pattern \
  "macOS model prewarm uses shared prewarm trigger delay" \
  'VoiceInkModelRuntimePreference\.prewarmScheduleDelay' \
  VoiceInk/Services/ModelPrewarmService.swift

require_pattern \
  "macOS model prewarm uses shared prewarm plan" \
  'VoiceInkModelPrewarmPlan\.plan' \
  VoiceInk/Services/ModelPrewarmService.swift

require_pattern \
  "macOS model prewarm uses shared sample lookup policy" \
  'VoiceInkModelPrewarmSamplePolicy\.firstAvailableURL' \
  VoiceInk/Services/ModelPrewarmService.swift \
  VoiceInk/Transcription/Whisper/WhisperModelWarmupCoordinator.swift

require_pattern \
  "macOS Whisper warmup uses shared scheduling policy" \
  'VoiceInkWhisperModelWarmupPolicy\.shouldScheduleWarmup' \
  VoiceInk/Transcription/Whisper/WhisperModelWarmupCoordinator.swift

reject_pattern \
  "macOS model prewarm avoids shell-owned prewarm delay literal" \
  '\.seconds\(3\)' \
  VoiceInk/Services/ModelPrewarmService.swift

reject_pattern \
  "macOS model prewarm avoids shell-owned prewarm diagnostics and sample policy" \
  '"(ModelPrewarmService initialized - listening for wake and app launch|App launched, scheduling prewarm|Mac activity detected \(wake/unlock\), scheduling prewarm|Prewarm disabled by user|Skipping prewarm - cloud models don.?t need it|Prewarm audio file|Prewarming |Prewarm completed in|Prewarm failed:|sound7|wav)"' \
  VoiceInk/Services/ModelPrewarmService.swift \
  VoiceInk/Transcription/Whisper/WhisperModelWarmupCoordinator.swift

reject_pattern \
  "macOS Whisper warmup avoids shell-owned Core ML warmup gate" \
  'guard +VoiceInkWhisperModelFiles\.supportsCoreML\(forModelName: model\.name\)|!warmingModels\.contains\(model\.name\)' \
  VoiceInk/Transcription/Whisper/WhisperModelWarmupCoordinator.swift

require_pattern \
  "macOS model settings observes shared VAD preference key" \
  'VoiceInkVADPreference\.userDefaultsKey|VoiceInkVADPreference\.defaultIsEnabled' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "macOS model settings observes shared model runtime key" \
  'VoiceInkModelRuntimePreference\.userDefaultsKey|VoiceInkModelRuntimePreference\.defaultShouldPrewarmModelOnWake' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "macOS model settings observes shared recorder preview key" \
  'VoiceInkRecorderPreviewPreference\.userDefaultsKey|VoiceInkRecorderPreviewPreference\.defaultIsLiveTextPreviewEnabled' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "macOS model settings uses shared advanced transcription presentation" \
  'VoiceInkMacOSAdvancedTranscriptionSettingsPresentation\.macOS|advancedSettingsPresentation\.(sectionTitle|vad|modelPrewarm|liveTextPreview)' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "macOS mini recorder observes shared recorder preview key" \
  'VoiceInkRecorderPreviewPreference\.userDefaultsKey|VoiceInkRecorderPreviewPreference\.defaultIsLiveTextPreviewEnabled' \
  VoiceInk/Views/Recorder/MiniRecorderView.swift

require_pattern \
  "macOS notch recorder observes shared recorder preview key" \
  'VoiceInkRecorderPreviewPreference\.userDefaultsKey|VoiceInkRecorderPreviewPreference\.defaultIsLiveTextPreviewEnabled' \
  VoiceInk/Views/Recorder/NotchRecorderView.swift

reject_pattern \
  "macOS advanced transcription shells avoid raw runtime preference keys" \
  'VoiceInkUserDefaultsKey\.(isVADEnabled|prewarmModelOnWake|showLiveTextPreview)|VoiceInkPreferenceDefault\.(isVADEnabled|prewarmModelOnWake|showLiveTextPreview)|"(IsVADEnabled|PrewarmModelOnWake|showLiveTextPreview)"' \
  VoiceInk/AppDefaults.swift \
  VoiceInk/Services/ModelPrewarmService.swift \
  VoiceInk/Views/ModelSettingsView.swift \
  VoiceInk/Views/Recorder/MiniRecorderView.swift \
  VoiceInk/Views/Recorder/NotchRecorderView.swift

reject_pattern \
  "macOS model settings avoids shell-only advanced transcription settings copy" \
  '"(Advanced|Voice Activity Detection \(VAD\)|Use VAD inside batch/final transcription when supported\. Buffer preload has its own VAD model in Rolling Buffer settings\.|Prewarm model \(Experimental\)|Turn this on if transcriptions with local models are taking longer than expected\. Runs silent background transcription on app launch and wake to trigger optimization\.|Show Transcript Preview|Displays in-progress transcript text when a model or buffer preload can provide it\.)"' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "migration checklist tracks shared model runtime preference gate" \
  'macOS VAD, model prewarm, and recorder transcript-preview preferences route through `VoiceInkVADPreference`/`VoiceInkModelRuntimePreference`/`VoiceInkRecorderPreviewPreference` plus `VoiceInkMacOSAdvancedTranscriptionSettingsPresentation`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared primary recording shortcut selection key lives in VoiceInkCore" \
  'primaryRecordingShortcut = "primaryRecordingShortcut"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared secondary recording shortcut selection key lives in VoiceInkCore" \
  'secondaryRecordingShortcut = "secondaryRecordingShortcut"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared primary recording shortcut mode key lives in VoiceInkCore" \
  'primaryRecordingShortcutMode = "primaryRecordingShortcutMode"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared secondary recording shortcut mode key lives in VoiceInkCore" \
  'secondaryRecordingShortcutMode = "secondaryRecordingShortcutMode"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared middle-click enabled key lives in VoiceInkCore" \
  'isMiddleClickToggleEnabled = "isMiddleClickToggleEnabled"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared middle-click delay key lives in VoiceInkCore" \
  'middleClickActivationDelay = "middleClickActivationDelay"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared special shortcut empty-tap key lives in VoiceInkCore" \
  'specialShortcutPasteLastTranscriptOnEmptyTap = "specialShortcutPasteLastTranscriptOnEmptyTap"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

section "obsolete standalone special shortcut key-evidence policy module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/SpecialShortcutKeyEvidencePolicy.swift

require_patterns \
  "special shortcut key-evidence policy lives with empty-tap fallback policy" \
  VoiceInkCore/Sources/VoiceInkCore/SpecialShortcutEmptyFallbackPolicy.swift \
  'VoiceInkShortcutPressContext' \
  'VoiceInkSpecialShortcutKeyEvidencePolicy' \
  'VoiceInkShortcutInterruptionPolicy' \
  'interruptionWindow: TimeInterval = 1\.0' \
  'VoiceInkRecordingShortcutTimingPolicy' \
  'pressCooldown: TimeInterval = 0\.08' \
  'hybridPushToTalkThreshold: TimeInterval = 0\.5' \
  'isPressWithinCooldown' \
  'shouldStopHybridRecording' \
  'sleepNanoseconds' \
  'VoiceInkSpecialShortcutEmptyFallbackPolicy'

require_pattern \
  "macOS shortcut monitor delegates interruption timing to shared policy" \
  'VoiceInkShortcutInterruptionPolicy\.isWithinInterruptionWindow' \
  VoiceInk/Shortcuts/ShortcutMonitor.swift

reject_pattern \
  "macOS shortcut monitor avoids shell-owned interruption timing policy" \
  'shortcutInterruptionWindow|eventTime - pressedAt <=|interruptionWindow' \
  VoiceInk/Shortcuts/ShortcutMonitor.swift

require_patterns \
  "macOS recording shortcut mode handler delegates timing to shared policy" \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift \
  'VoiceInkRecordingShortcutTimingPolicy\.isPressWithinCooldown' \
  'VoiceInkRecordingShortcutTimingPolicy\.shouldStopHybridRecording' \
  'VoiceInkRecordingShortcutTimingPolicy\.sleepNanoseconds'

reject_pattern \
  "macOS recording shortcut mode handler avoids shell-owned timing constants" \
  'shortcutPressCooldown|hybridPressThreshold|1_000_000_000|pressDuration >=|Date\(\)\.timeIntervalSince\(lastTrigger\)' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "core checks execute shared recording shortcut timing policy tests" \
  'SpecialShortcutEmptyFallbackPolicyTests\.testRecordingShortcutTimingPolicy(PreservesMacOSThresholds|DetectsPressCooldown|HybridStopRequiresThresholdAndRecordingState|ConvertsSleepDelaySafely)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared shortcut interruption policy tests" \
  'SpecialShortcutKeyEvidencePolicyTests\.testShortcutInterruptionPolicyPreservesMacOSWindow' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration docs track shared recording shortcut timing policy" \
  'shortcut interruption timing to `VoiceInkShortcutInterruptionPolicy`.*recording shortcut mode handling delegates cooldown, hybrid push-to-talk threshold, and hold-delay sleep conversion to `VoiceInkRecordingShortcutTimingPolicy`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared recording shortcut selection values live in VoiceInkCore" \
  'public enum VoiceInkRecordingShortcutSelection' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut mode values live in VoiceInkCore" \
  'public enum VoiceInkRecordingShortcutMode' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut mode monitor policy lives in VoiceInkCore" \
  'tracksKeyUpEvidence|allowsShortcutInterruption' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS recording shortcut manager consumes shared mode monitor policy" \
  'tracksKeyUpEvidence|allowsShortcutInterruption' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS Power Mode shortcut manager consumes shared mode monitor policy" \
  'tracksKeyUpEvidence|allowsShortcutInterruption' \
  VoiceInk/Shortcuts/PowerModeShortcutManager.swift

require_pattern \
  "core checks execute recording shortcut mode monitor policy test" \
  'UserDefaultsPreferencesTests\.testRecordingShortcutModePreservesMonitorPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS shortcut managers avoid shell-owned special-mode monitor policy" \
  'primaryRecordingShortcutMode != \.special|secondaryRecordingShortcutMode != \.special|recordingMode\(for: \$0\) == \.special|recordingMode\(for: action\) == \.special|modeProvider\(\) == \.special' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift \
  VoiceInk/Shortcuts/PowerModeShortcutManager.swift

require_pattern \
  "shared recording shortcut preference module lives in VoiceInkCore" \
  'public enum VoiceInkRecordingShortcutPreference' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared shortcut storage preference lives in VoiceInkCore" \
  'VoiceInkShortcutStorageState|VoiceInkShortcutStoragePreference|clearedKey\(for shortcutKey: String\)' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared macOS recording shortcut settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSRecordingShortcutSettingsPresentation|macOSSettingsPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_patterns \
  "shared macOS shortcut recorder presentation lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkMacOSShortcutRecorderPresentation' \
  'macOSRecorderPresentation' \
  'recordingPlaceholderText: "Press shortcut"' \
  'idleAccessibilityLabel: "Record shortcut"' \
  'idleButtonText: "Record"'

require_patterns \
  "shared macOS shortcut event notification names live in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'shortcutDidChangeNotificationName = Notification\.Name\("ShortcutStoreShortcutDidChange"\)' \
  'shortcutRecordingDidStartNotificationName = Notification\.Name\("ShortcutRecorderRecordingDidStart"\)'

require_patterns \
  "shared shortcut action display-name presentation lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkShortcutActionPresentation' \
  'displayName\(' \
  'primaryRecordingDisplayName = "Primary Shortcut"' \
  'pasteLastEnhancementDisplayName = "Paste Last Enhanced Transcription"' \
  'quickAddToDictionaryDisplayName = "Quick Add to Dictionary"' \
  'toggleEnhancementDisplayName = "Toggle Enhancement"' \
  'fallbackPowerModeDisplayName = "Power Mode"' \
  'miniRecorderEscapeDisplayName = "Mini Recorder Cancel"' \
  'displayNumber\(forMiniRecorderIndex:'

require_patterns \
  "shared shortcut validation notification presentation lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkShortcutValidationIssue' \
  'VoiceInkShortcutValidationPresentation' \
  'notificationTitle' \
  'Shortcut not allowed:' \
  'Shortcut reserved by macOS:' \
  'Shortcut already used by'

require_patterns \
  "shared macOS shortcut notification presentation lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkMacOSShortcutNotificationPresentation' \
  'inputMonitoringPermissionRequired' \
  'accessibilityPermissionRequired' \
  'monitorStartFailed' \
  'miniRecorderEscapeConfirmation' \
  'Enable Input Monitoring for shortcuts' \
  'Enable Accessibility for shortcuts' \
  'Keyboard shortcut monitor could not start' \
  'Press ESC again to cancel recording' \
  'actionButtonLabel: "Open Settings"'

require_patterns \
  "shared mini recorder escape shortcut policy lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkMiniRecorderEscapeShortcutPolicy' \
  'doublePressThreshold: TimeInterval = 1\.5' \
  'confirmationPresentation' \
  'isSecondPress' \
  'timeoutNanoseconds' \
  'VoiceInkRecordingShortcutTimingPolicy\.sleepNanoseconds'

require_pattern \
  "shared recording shortcut preference owns selection keys" \
  'selectionKey' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference owns mode keys" \
  'modeKey' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference owns default selection policy" \
  'defaultSelection' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference owns default mode policy" \
  'defaultMode' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference owns middle-click enabled helper" \
  'isMiddleClickToggleEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference owns middle-click delay helper" \
  'middleClickActivationDelay' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference owns middle-click delay minimum" \
  'minimumMiddleClickActivationDelay = 0' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference normalizes middle-click delay" \
  'normalizedMiddleClickActivationDelay' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference saves middle-click delay" \
  'saveMiddleClickActivationDelay' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut backup import normalizes middle-click delay" \
  'middleClickActivationDelay: backup\.middleClickActivationDelay\.map\(Self\.normalizedMiddleClickActivationDelay\)' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference owns special empty-tap helper" \
  'shouldPasteLastTranscriptOnEmptyTap' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference saves special empty-tap setting" \
  'saveShouldPasteLastTranscriptOnEmptyTap' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut backup preferences live in VoiceInkCore" \
  'VoiceInkRecordingShortcutBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut backup import plan lives in VoiceInkCore" \
  'VoiceInkRecordingShortcutBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared shortcut backup action import plan lives in VoiceInkCore" \
  'VoiceInkShortcutBackupImport' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared shortcut backup policy owns general backup action order" \
  'VoiceInkShortcutBackupPolicy|generalBackupShortcutActionIdentifiers|generalBackupShortcutExportPlan|generalBackupShortcutImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared shortcut backup policy marks imported recording shortcuts custom" \
  'recordingShortcutSelection: slot == nil \? nil : \.custom' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference exports backup values" \
  'backupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference parses backup import values" \
  'backupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS defaults register shared recording shortcut defaults" \
  'VoiceInkRecordingShortcutPreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS recording shortcut manager uses shared shortcut selection type" \
  'typealias ShortcutSelection = VoiceInkRecordingShortcutSelection' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS recording shortcut manager uses shared shortcut mode type" \
  'typealias Mode = VoiceInkRecordingShortcutMode' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS recording shortcut manager saves selection through shared preference" \
  'VoiceInkRecordingShortcutPreference\.saveSelection' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS recording shortcut manager saves mode through shared preference" \
  'VoiceInkRecordingShortcutPreference\.saveMode' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS recording shortcut manager saves middle-click enabled through shared preference" \
  'VoiceInkRecordingShortcutPreference\.saveMiddleClickToggleEnabled' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS recording shortcut manager saves middle-click delay through shared preference" \
  'VoiceInkRecordingShortcutPreference\.saveMiddleClickActivationDelay' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS recording shortcut manager normalizes middle-click delay through shared preference" \
  'VoiceInkRecordingShortcutPreference\.normalizedMiddleClickActivationDelay' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS shortcut settings uses shared middle-click delay minimum" \
  'VoiceInkRecordingShortcutPreference\.minimumMiddleClickActivationDelay' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS recording shortcut manager reads special empty-tap setting through shared preference" \
  'VoiceInkRecordingShortcutPreference\.shouldPasteLastTranscriptOnEmptyTap' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS recording shortcut manager saves special empty-tap setting through shared preference" \
  'VoiceInkRecordingShortcutPreference\.saveShouldPasteLastTranscriptOnEmptyTap' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

require_pattern \
  "macOS shortcut store consumes shared shortcut storage preference" \
  'VoiceInkShortcutStoragePreference\.(shortcutData|saveShortcutData|markShortcutCleared|removeShortcutStorage|storedState|restoreStoredState|isShortcutCleared)' \
  VoiceInk/Shortcuts/ShortcutStore.swift

require_pattern \
  "macOS shortcut store uses shared shortcut-change notification name" \
  'shortcutDidChange = VoiceInkRecordingShortcutPreference\.shortcutDidChangeNotificationName' \
  VoiceInk/Shortcuts/ShortcutStore.swift

reject_pattern \
  "macOS shortcut store avoids shell-owned shortcut UserDefaults storage mechanics" \
  'UserDefaults\.standard|clearedUserDefaultsKey|"_cleared"' \
  VoiceInk/Shortcuts/ShortcutStore.swift

require_pattern \
  "macOS shortcut migration uses shared shortcut selection migration plan" \
  'VoiceInkRecordingShortcutPreference\.shortcutSelectionMigrationPlan' \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "macOS shortcut migration applies shared shortcut selection migration plan" \
  'VoiceInkRecordingShortcutPreference\.applyShortcutSelectionMigrationPlan' \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "macOS shortcut migration uses shared shortcut mode migration" \
  'VoiceInkRecordingShortcutPreference\.migrateShortcutMode' \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "macOS shortcut migration uses shared legacy shortcut cleanup" \
  'VoiceInkRecordingShortcutPreference\.(removeLegacyCustomRecordingShortcut|removeLegacyKeyboardShortcut)' \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "macOS diagnostics use shared middle-click enabled preference" \
  'VoiceInkRecordingShortcutPreference\.isMiddleClickToggleEnabled' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS diagnostics use shared middle-click delay preference" \
  'VoiceInkRecordingShortcutPreference\.middleClickActivationDelay' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS recording settings uses shared shortcut presentation" \
  'VoiceInkRecordingShortcutPreference\.macOSSettingsPresentation|recordingShortcutPresentation\.(sectionTitle|primaryShortcutLabel|secondaryShortcutLabel|addSecondaryShortcutButtonTitle|emptyTapPasteLastTranscriptLabel|additionalSectionTitle|pasteLastTranscriptionOriginalLabel|pasteLastTranscriptionEnhancedLabel|retryLastTranscriptionLabel|cancelRecordingLabel|resetToDefaultHelp|middleClickRecordingLabel|activationDelayLabel|activationDelayUnitLabel)' \
  VoiceInk/Views/Settings/SettingsView.swift

require_patterns \
  "macOS shortcut recorder uses shared recorder presentation" \
  VoiceInk/Shortcuts/ShortcutRecorder.swift \
  'VoiceInkRecordingShortcutPreference\.macOSRecorderPresentation' \
  'presentation\.recordingPlaceholderText' \
  'presentation\.idleAccessibilityLabel' \
  'presentation\.idleButtonText'

require_pattern \
  "macOS shortcut recorder uses shared recording-start notification name" \
  'shortcutRecordingDidStart = VoiceInkRecordingShortcutPreference\.shortcutRecordingDidStartNotificationName' \
  VoiceInk/Shortcuts/ShortcutRecorder.swift

require_pattern \
  "core checks execute recording shortcut notification-name test" \
  'UserDefaultsPreferencesTests\.testRecordingShortcutPreferencePreservesMacOSNotificationNames' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS shortcut shells avoid raw shortcut event notification names" \
  '"(ShortcutStoreShortcutDidChange|ShortcutRecorderRecordingDidStart)"' \
  VoiceInk/Shortcuts/ShortcutStore.swift \
  VoiceInk/Shortcuts/ShortcutRecorder.swift

require_patterns \
  "macOS shortcut action display names use shared presentation" \
  VoiceInk/Shortcuts/ShortcutAction.swift \
  'VoiceInkShortcutActionPresentation\.displayName' \
  'powerModeConfigurationName'

require_patterns \
  "macOS shortcut validator uses shared validation presentation" \
  VoiceInk/Shortcuts/ShortcutValidator.swift \
  'VoiceInkShortcutValidationIssue' \
  'VoiceInkShortcutValidationPresentation\.notificationTitle'

require_patterns \
  "macOS recording shortcut manager uses shared notification presentation" \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift \
  'VoiceInkMacOSShortcutNotificationPresentation\.inputMonitoringPermissionRequired' \
  'VoiceInkMacOSShortcutNotificationPresentation\.accessibilityPermissionRequired' \
  'VoiceInkMacOSShortcutNotificationPresentation\.monitorStartFailed'

require_patterns \
  "macOS mini recorder shortcut manager uses shared notification presentation" \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift \
  'VoiceInkMiniRecorderEscapeShortcutPolicy\.confirmationPresentation' \
  'presentation\.title' \
  'presentation\.duration'

require_patterns \
  "macOS mini recorder shortcut manager uses shared escape timing policy" \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift \
  'VoiceInkMiniRecorderEscapeShortcutPolicy\.isSecondPress' \
  'VoiceInkMiniRecorderEscapeShortcutPolicy\.timeoutNanoseconds'

require_pattern \
  "macOS general backup adapts recording shortcut values to shared preferences" \
  'recordingShortcutBackupPreferences' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS general backup adapts shortcut backup records for shared policy" \
  'shortcutBackupRecords' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup import reads shared recording shortcut plan from grouped general settings" \
  'generalImportPlans\.recordingShortcut' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "macOS backup import uses shared shortcut backup import plan" \
  'VoiceInkShortcutBackupPolicy\.generalBackupShortcutImportPlan' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "macOS backup export uses shared recording shortcut backup preferences" \
  'VoiceInkRecordingShortcutPreference\.backupPreferences' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup export uses shared shortcut backup export plan" \
  'VoiceInkShortcutBackupPolicy\.generalBackupShortcutExportPlan' \
  VoiceInk/Services/ImportExportService.swift

reject_pattern \
  "macOS recording shortcut shells avoid raw current shortcut preference keys" \
  '"(primaryRecordingShortcut|secondaryRecordingShortcut|primaryRecordingShortcutMode|secondaryRecordingShortcutMode|isMiddleClickToggleEnabled|middleClickActivationDelay|specialShortcutPasteLastTranscriptOnEmptyTap)"|enum +(Mode|ShortcutSelection)|SpecialShortcutSettings' \
  VoiceInk/AppDefaults.swift \
  VoiceInk/Services/SystemInfoService.swift \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift \
  VoiceInk/Shortcuts/ShortcutMigration.swift

reject_pattern \
  "macOS recording shortcut manager avoids raw middle-click delay UInt64 conversion" \
  'UInt64\(self\.middleClickActivationDelay\)' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift

reject_pattern \
  "macOS recording settings avoid shell-owned shortcut presentation copy" \
  '"(Primary Shortcut|Secondary Shortcut|Add Second Shortcut|Empty Tap Pastes Last|Additional Shortcuts|Paste Last Transcription \(Original\)|Paste Last Transcription \(Enhanced\)|Retry Last Transcription|Cancel Recording|Reset to default|Middle-Click Recording|Activation Delay|ms)"' \
  VoiceInk/Views/Settings/SettingsView.swift

reject_pattern \
  "macOS shortcut settings avoid shell-owned middle-click delay bounds" \
  'formatter\.minimum = 0' \
  VoiceInk/Views/Settings/SettingsView.swift

reject_pattern \
  "macOS shortcut recorder avoids shell-owned recorder presentation copy" \
  '"(Press shortcut|Record shortcut|Record)"' \
  VoiceInk/Shortcuts/ShortcutRecorder.swift

reject_pattern \
  "macOS shortcut action avoids shell-owned display-name copy and numbering" \
  '"(Primary Shortcut|Secondary Shortcut|Paste Last Transcription|Paste Last Enhanced Transcription|Retry Last Transcription|Cancel Recording|Open History Window|Quick Add to Dictionary|Toggle Enhancement|Power Mode|Mini Recorder Cancel|Select Prompt|Select Power Mode)"|displayNumber\(forMiniRecorderIndex:' \
  VoiceInk/Shortcuts/ShortcutAction.swift

reject_pattern \
  "macOS shortcut validator avoids shell-owned notification copy" \
  '"(Shortcut not allowed:|Shortcut reserved by macOS:|Shortcut already used by)"' \
  VoiceInk/Shortcuts/ShortcutValidator.swift

reject_pattern \
  "macOS shortcut managers avoid shell-owned notification copy" \
  '"(Enable Input Monitoring for shortcuts|Enable Accessibility for shortcuts|Keyboard shortcut monitor could not start|Press ESC again to cancel recording|Open Settings)"' \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift

reject_pattern \
  "macOS mini recorder shortcut manager avoids shell-owned escape timing policy" \
  'escapeDoublePressThreshold|1\.5|1_000_000_000|timeIntervalSince\(firstTime\)' \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift

reject_pattern \
  "macOS backup import avoids shell-only recording shortcut raw parsing" \
  'ShortcutSelection\(rawValue:|Mode\(rawValue:' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import avoids shell-owned general shortcut backup sequence" \
  'general\.(primaryRecordingShortcut|secondaryRecordingShortcut|pasteLastTranscriptionShortcut|pasteLastEnhancementShortcut|retryLastTranscriptionShortcut|cancelRecorderShortcut|openHistoryWindowShortcut|quickAddToDictionaryShortcut|toggleEnhancementShortcut)' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup export avoids shell-only recording shortcut raw emission" \
  'recordingShortcutManager\.(primaryRecordingShortcut|secondaryRecordingShortcut|primaryRecordingShortcutMode|secondaryRecordingShortcutMode)\.rawValue' \
  VoiceInk/Services/ImportExportService.swift

reject_pattern \
  "macOS backup export avoids shell-owned general shortcut backup sequence" \
  'ShortcutStore\.shortcut\(for: \.(primaryRecording|secondaryRecording|pasteLastTranscription|pasteLastEnhancement|retryLastTranscription|cancelRecorder|openHistoryWindow|quickAddToDictionary|toggleEnhancement)\)' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "core checks execute recording shortcut backup export policy tests" \
  'UserDefaultsPreferencesTests\.testRecordingShortcutPreferenceBuildsBackupPreferences' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute recording shortcut backup import policy tests" \
  'UserDefaultsPreferencesTests\.testRecordingShortcutPreferenceBackupImportPlanSkipsInvalidRawValues' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core tests pin middle-click delay normalization" \
  'saveMiddleClickActivationDelay\(-1|middleClickActivationDelay: -1' \
  VoiceInkCore/Tests/VoiceInkCoreTests/UserDefaultsPreferencesTests.swift

require_pattern \
  "core checks execute shortcut backup export policy tests" \
  'UserDefaultsPreferencesTests\.testShortcutBackupPolicyExportsGeneralShortcutsInStableOrder' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shortcut backup import policy tests" \
  'UserDefaultsPreferencesTests\.testShortcutBackupPolicyImportsGeneralShortcutsWithRecordingSelections' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shortcut storage preference tests" \
  'UserDefaultsPreferencesTests\.testShortcutStoragePreference(StoresDataAndClearedState|CapturesAndRestoresStoredState)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared shortcut action identifier tests" \
  'UserDefaultsPreferencesTests\.testShortcutActionIdentifierPreservesStorageAndLegacyKeys' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared shortcut action presentation tests" \
  'UserDefaultsPreferencesTests\.testShortcutActionPresentationPreservesMacOSDisplayNames' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared shortcut validation presentation tests" \
  'UserDefaultsPreferencesTests\.testShortcutValidationPresentationPreservesMacOSNotificationTitles' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared macOS shortcut notification presentation tests" \
  'UserDefaultsPreferencesTests\.testMacOSShortcutNotificationPresentationPreservesShellCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared mini recorder escape timing tests" \
  'UserDefaultsPreferencesTests\.testMiniRecorderEscapeShortcutPolicyPreservesMacOSTiming' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared shortcut recorder presentation test" \
  'UserDefaultsPreferencesTests\.testRecordingShortcutPreferencePreservesMacOSRecorderPresentation' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute shared shortcut migration plan tests" \
  'UserDefaultsPreferencesTests\.testRecordingShortcut(SelectionMigrationPlan|ModeMigration)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared recording shortcut preference gate" \
  'macOS recording shortcut action identifiers, action display names, validation and monitor notification copy, shortcut change/recording-start notification names, mini-recorder escape confirmation copy and double-press timing, selection/mode migration plans, legacy shortcut key names, raw shortcut storage, middle-click enablement and activation-delay normalization, special empty-tap preferences, settings labels/help, shortcut recorder labels, backup import/export value planning, general-backup shortcut action ordering, and recording-shortcut selection repair when importing backed-up shortcut records route through `VoiceInkShortcutActionIdentifier`/`VoiceInkShortcutActionPresentation`/`VoiceInkShortcutValidationPresentation`/`VoiceInkMacOSShortcutNotificationPresentation`/`VoiceInkMiniRecorderEscapeShortcutPolicy`/`VoiceInkLegacyRecordingShortcutPreset`/`VoiceInkRecordingShortcutSelection`/`VoiceInkRecordingShortcutMode`/`VoiceInkRecordingShortcutPreference`/`VoiceInkShortcutStoragePreference`/`VoiceInkShortcutBackupPolicy`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared transcription run result carries post-processing enhancement result" \
  'postProcessingResult: VoiceInkAIEnhancementResult\?' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift

require_pattern \
  "shared transcription run processor builds post-processing enhancement result" \
  'postProcessingResult = VoiceInkAIEnhancementResult\.completed' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift

require_pattern \
  "shared transcription run tests keep failed post-processing result absent" \
  'XCTAssertNil\(result\.postProcessingResult\)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/TranscriptionRunProcessorTests.swift

reject_pattern \
  "shared transcription run success derives from post-processing result" \
  'let postProcessingSucceeded|postProcessingSucceeded: Bool,|postProcessingSucceeded: (true|false)' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift \
  VoiceInkCore/Tests/VoiceInkCoreTests/TranscriptionRecordTests.swift

require_pattern \
  "shared transcription run enhancement duration derives from post-processing result" \
  'var enhancementDuration: TimeInterval\?' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift

reject_pattern \
  "shared transcription run does not store separate enhancement duration state" \
  'public let enhancementDuration|enhancementDuration: TimeInterval\? =|enhancementDuration: postProcessingResult' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift

require_patterns \
  "macOS recorder completion stores request metadata through shared completed draft" \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  'VoiceInkCompletedTranscriptionDraft\(' \
  'enhancementResult: enhancementResult' \
  'enhancementFailurePolicy: \.storeFailureText' \
  'transcription\.applyCompletedDraft\(completedDraft\)'

require_pattern \
  "macOS audio-file import enhancement completion preserves queue failure text policy" \
  'enhancementFailurePolicy: \.storeFailureText' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS retry enhancement completion preserves retry failure text policy" \
  'enhancementFailurePolicy: \.omitEnhancedText' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "shared completed transcription draft stores request metadata from shared result" \
  'enhancementResult\.requestSystemMessage' \
  VoiceInkCore/Sources/VoiceInkCore/CompletedTranscriptionDraft.swift

require_pattern \
  "core tests pin audio-file enhancement completion policy" \
  'testAudioFileTranscriptionCompletionSkipsMissingEnhancementRequest|testAudioFileTranscriptionCompletionStoresSuccessfulEnhancement|testAudioFileTranscriptionCompletionMapsEnhancementFailureToDraftAndReason' \
  VoiceInkCore/Tests/VoiceInkCoreTests/CompletedTranscriptionDraftTests.swift

require_pattern \
  "core check runner executes audio-file enhancement completion policy tests" \
  'testAudioFileTranscriptionCompletionSkipsMissingEnhancementRequest|testAudioFileTranscriptionCompletionStoresSuccessfulEnhancement|testAudioFileTranscriptionCompletionMapsEnhancementFailureToDraftAndReason' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS re-enhance action stores request metadata through shared record mutation" \
  'applyEnhancementResult\(enhancement\)' \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS enhancement callers avoid tuple metadata and mutable service side reads" \
  'let \(enhancedText, enhancementDuration, promptName\)|lastSystemMessageSent|lastUserMessageSent|getAIService\(\)\.currentModel' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS recorder pipeline avoids shell-owned enhancement record mutation" \
  'applyEnhancement(Result|Failure)\(' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "shared transcription failure plan type lives in core" \
  'public struct VoiceInkTranscriptionRecordFailurePlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "shared transcription cancellation plan type lives in core" \
  'public struct VoiceInkTranscriptionRecordCancellationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "shared transcription failure plan owns failed status" \
  'self\.status = \.failed' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "shared transcription failure plan owns macOS stored text" \
  'self\.failedTranscriptText = VoiceInkTranscriptPresentation\.failedTranscriptText\(reason: errorDescription\)' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "iOS mutable transcription records apply shared failure plan" \
  'let plan = VoiceInkTranscriptionRecordFailurePlan\(errorDescription: errorDescription\)' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "iOS mutable transcription records store shared failure status" \
  'transcriptionStatus = plan\.status' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "iOS mutable transcription records store shared failure detail" \
  'transcriptionError = plan\.errorDescription' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "mutable transcription records apply shared cancellation plan" \
  'func applyCancellationPlan\(_ plan: VoiceInkTranscriptionRecordCancellationPlan\)' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "mutable transcription records expose shared cancellation helper" \
  'func markTranscriptionCanceled\(' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "mutable transcription records expose shared enhancement result mutation" \
  'VoiceInkMutableTranscriptionEnhancementRecord|applyEnhancementResult' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "mutable transcription records expose shared enhancement failure mutation" \
  'applyEnhancementFailure' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRecord.swift

require_pattern \
  "core checks execute cancellation plan tests" \
  'TranscriptionRecordTests\.testCancellationPlanBuildsSharedCanceledStateAndMetadataClears|TranscriptionRecordTests\.testMarkTranscriptionCanceledClearsMutableRecordEnhancementState|TranscriptionRecordTests\.testMarkTranscriptionCanceledPreservesDurationAndModelWhenNotProvided' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute enhancement record mutation tests" \
  'TranscriptionRecordTests\.testApplyEnhancementResultStoresTextAndMetadata|TranscriptionRecordTests\.testApplyEnhancementFailureStoresFailureTextAndClearsMetadata|TranscriptionRecordTests\.testApplyEnhancementFailureCanOmitEnhancedText' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared cancellation plan" \
  'canceled-record mutation routes through `VoiceInkTranscriptionRecordCancellationPlan`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared completed draft and enhancement record mutation" \
  'VoiceInkCompletedTranscriptionDraft.*VoiceInkMutableTranscriptionEnhancementRecord' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS transcription model exposes shared enhancement metadata adapter" \
  'VoiceInkMutableTranscriptionEnhancementMetadataRecord' \
  VoiceInk/Models/Transcription.swift

require_pattern \
  "macOS transcription model exposes shared failure adapter" \
  'func markAsFailedTranscription\(reason: String\)' \
  VoiceInk/Models/Transcription.swift

require_pattern \
  "macOS transcription model builds shared failure plan" \
  'let plan = VoiceInkTranscriptionRecordFailurePlan\(errorDescription: reason\)' \
  VoiceInk/Models/Transcription.swift

require_pattern \
  "macOS transcription model stores shared failure text" \
  'text = plan\.failedTranscriptText' \
  VoiceInk/Models/Transcription.swift

require_pattern \
  "macOS transcription model stores shared failure status" \
  'transcriptionState = plan\.status' \
  VoiceInk/Models/Transcription.swift

require_pattern \
  "macOS transcription pipeline uses shared failed record adapter" \
  'markAsFailedTranscription\(reason: errorDescription\)' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS transcription pipeline applies live completion through shared completed draft" \
  'VoiceInkCompletedTranscriptionDraft\(' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS transcription pipeline preserves live enhancement failure text policy" \
  'enhancementFailurePolicy: \.storeFailureText' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS engine uses shared failed record adapter" \
  'markAsFailedTranscription\([^)]*VoiceInkModelManagementPresentation\.noModelSelectedText' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS diagnostics use shared no-model-selected copy" \
  'VoiceInkModelManagementPresentation\.noModelSelectedText' \
  VoiceInk/Services/SystemInfoService.swift

reject_pattern \
  "macOS recorder failure state avoids direct text/status duplication" \
  'VoiceInkTranscriptPresentation\.failedTranscriptText|transcriptionState = \.failed' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS model diagnostics avoid shell-only no-model-selected copy" \
  '"No model selected"' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift \
  VoiceInk/Services/SystemInfoService.swift

reject_pattern \
  "macOS recorder failure text prefix stays in shared presentation policy" \
  'Transcription Failed:' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS canceled transcription record uses shared cancellation plan" \
  'VoiceInkTranscriptionRecordCancellationPlan' \
  VoiceInk/Models/Transcription.swift

reject_pattern \
  "macOS canceled transcription record avoids direct canceled policy" \
  'VoiceInkTranscriptPresentation\.canceledTranscriptionText|transcriptionState = \.canceled|enhancedText = nil|aiEnhancementModelName = nil|promptName = nil|aiRequest(System|User)Message = nil' \
  VoiceInk/Models/Transcription.swift

reject_pattern \
  "macOS last-transcription shell avoids shared policy pass-through wrappers" \
  'private static func +(isPasteable|textForCursorPaste)\(|static func +shouldFallback\(|VoiceInkContextualCapitalizationFormatter\.(needsCursorContext|format)|VoiceInkTranscriptionPasteOutputPolicy\.cursorPasteTextPlan' \
  VoiceInk/Services/LastTranscriptionService.swift

require_patterns \
  "macOS last-transcription fetch and text selection use shared policy" \
  VoiceInk/Services/LastTranscriptionService.swift \
  'VoiceInkLastTranscriptionPolicy\.fetchLimit' \
  'VoiceInkLastTranscriptionPolicy\.fetchFailedDiagnosticMessage' \
  'VoiceInkLastTranscriptionPolicy\.firstPasteableCandidate' \
  'VoiceInkLastTranscriptionPolicy\.pasteText' \
  'VoiceInkLastTranscriptionPolicy\.noTranscriptionNotification' \
  'VoiceInkLastTranscriptionPolicy\.copyCompletionNotification' \
  'VoiceInkLastTranscriptionPolicy\.retryPreflightFailureNotification' \
  'VoiceInkLastTranscriptionPolicy\.retrySuccessNotification' \
  'VoiceInkLastTranscriptionPolicy\.retryFailureNotification'

reject_pattern \
  "macOS last-transcription service avoids shell-owned fetch diagnostic copy" \
  '"Error fetching last transcription:' \
  VoiceInk/Services/LastTranscriptionService.swift

reject_pattern \
  "macOS last-transcription service avoids shell-owned pasteability scan" \
  'VoiceInkTranscriptPresentation\.isPasteable|descriptor\.fetchLimit = 20' \
  VoiceInk/Services/LastTranscriptionService.swift

reject_pattern \
  "macOS last-transcription service avoids shell-owned preferred-text fallback" \
  'VoiceInkTranscriptPresentation\.preferredText\(' \
  VoiceInk/Services/LastTranscriptionService.swift

require_pattern \
  "macOS last-transcription notifications adapt shared notification presentation" \
  'showNotification\(_ presentation: VoiceInkLastTranscriptionNotificationPresentation\)|title: presentation\.title|type: presentation\.kind' \
  VoiceInk/Services/LastTranscriptionService.swift

require_pattern \
  "macOS audio player retranscribe no-model failure uses shared banner presentation" \
  'VoiceInkAudioPlaybackActionBannerPresentation\.retranscriptionNoModelFailure' \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS last-transcription retry avoids shell-owned error vocabulary mapping" \
  'VoiceInkEngineError\.(audioFileNotFound|noTranscriptionModelSelected)|VoiceInkErrorDescription\.text\(for: error\)|VoiceInkErrorDescription\.text\(for: VoiceInkEngineError' \
  VoiceInk/Services/LastTranscriptionService.swift

reject_pattern \
  "macOS last-transcription notifications avoid shell-only copy" \
  '"No transcription available"|"Last transcription copied"|"Failed to copy transcription"|"Copied to clipboard"|"Cannot retry:|"Retry failed:|VoiceInkTranscriptPresentation\.(noTranscriptionAvailableTitle|lastTranscriptionCopiedTitle|failedToCopyTranscriptionTitle|cannotRetryTitle|copiedToClipboardTitle|retryFailedTitle)' \
  VoiceInk/Services/LastTranscriptionService.swift

require_pattern \
  "migration checklist tracks shared last-transcription policy gate" \
  'last-transcription candidate selection, fetch window, fetch-failure diagnostic copy, original-vs-preferred copy/paste text selection, copy/retry notification presentation, and retry-preflight error presentation route through `VoiceInkLastTranscriptionPolicy`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS engine canceled recording uses shared canceled draft factory" \
  'VoiceInkRecordingTranscriptionDraft\.canceled' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS canceled transcription text shim stays deleted" \
  'static let canceledTranscriptionText' \
  VoiceInk/Models/Transcription.swift

require_pattern \
  "shared duration presentation owns positive-duration visibility" \
  'shouldShowPositiveDuration|metadataSeparatorText' \
  VoiceInkCore/Sources/VoiceInkCore/DurationPresentation.swift

require_pattern \
  "shared stored-audio presentation uses shared positive-duration visibility" \
  'VoiceInkDurationPresentation\.shouldShowPositiveDuration' \
  VoiceInkCore/Sources/VoiceInkCore/StoredAudioFile.swift

reject_pattern \
  "shared stored-audio presentation avoids duplicate positive-duration checks" \
  'duration > 0' \
  VoiceInkCore/Sources/VoiceInkCore/StoredAudioFile.swift

require_pattern \
  "iOS audio duration UI uses shared positive-duration visibility" \
  'VoiceInkDurationPresentation\.shouldShowPositiveDuration' \
  iOS/VoiceInk-ios/AudioPlayerView.swift

require_pattern \
  "iOS note row duration UI uses shared positive-duration visibility" \
  'VoiceInkDurationPresentation\.shouldShowPositiveDuration' \
  iOS/VoiceInk-ios/NoteRowView.swift

require_pattern \
  "iOS duration metadata uses shared separator text" \
  'VoiceInkDurationPresentation\.metadataSeparatorText' \
  iOS/VoiceInk-ios/AudioPlayerView.swift \
  iOS/VoiceInk-ios/NoteRowView.swift

require_pattern \
  "shared playback-rate policy lives in VoiceInkCore" \
  'VoiceInkAudioPlaybackRate' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_patterns \
  "shared iOS audio playback session configuration lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/IOSAudioConfiguration.swift \
  'VoiceInkIOSAudioPlaybackSessionConfiguration' \
  'notePlayback' \
  'playback' \
  'spokenAudio'

require_pattern \
  "shared audio playback timeline owns update cadence" \
  'updateInterval' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "shared audio playback presentation lives in VoiceInkCore" \
  'VoiceInkAudioPlaybackPresentation|timestampSystemImageName|durationSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "shared audio playback diagnostics live in VoiceInkCore" \
  'VoiceInkAudioPlaybackDiagnostics|loadFailedMessage|playFailedMessage|macOSWaveformReadFailedMessage|macOSLoadFailedMessage' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "shared audio playback presentation owns macOS action help copy" \
  'showInFinderHelpText|selectEnhancementPromptHelpText|retranscribeAudioHelpText|reEnhanceWithSelectedPromptHelpText|viewDetailsHelpText' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "shared audio playback presentation owns enhancement prompt icon fallback" \
  'enhancementPromptFallbackSystemImageName|enhancementPromptSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_patterns \
  "shared audio playback action banner presentation owns macOS retry copy" \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift \
  'VoiceInkAudioPlaybackActionBannerPresentation' \
  'retranscriptionSuccess' \
  'reEnhancementSuccess' \
  'retranscriptionNoModelFailure' \
  'retranscriptionFailure' \
  'reEnhancementFailure' \
  'reEnhancementUnavailable'

require_pattern \
  "shared audio playback action banner owns no-model error vocabulary" \
  'VoiceInkErrorDescription\.text\(for: VoiceInkEngineError\.noTranscriptionModelSelected\)' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "macOS audio player uses shared playback-rate policy" \
  'VoiceInkAudioPlaybackRate' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "iOS audio player shell uses shared playback-rate policy" \
  'VoiceInkAudioPlaybackRate' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_patterns \
  "iOS audio player delegates playback session activation" \
  iOS/VoiceInk-ios/AudioPlayer.swift \
  'sessionManager\.activateSessionForPlayback' \
  'sessionManager\.scheduleDeactivation'

require_patterns \
  "iOS audio-session manager centralizes playback session AVFoundation adapter" \
  iOS/VoiceInk-ios/AudioSessionManager.swift \
  'VoiceInkIOSAudioPlaybackSessionConfiguration\.notePlayback' \
  'configuration\.category\.avCategory' \
  'configuration\.mode\.avMode' \
  'extension VoiceInkIOSAudioPlaybackSessionConfiguration\.Category' \
  'extension VoiceInkIOSAudioPlaybackSessionConfiguration\.Mode'

reject_pattern \
  "iOS audio player avoids local playback session AVFoundation adapter" \
  'extension VoiceInkIOSAudioPlaybackSessionConfiguration\.Category|case \.playback:|return \.playback' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_pattern \
  "iOS audio player shell uses shared playback update cadence" \
  'VoiceInkAudioPlaybackTimeline\.updateInterval' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_pattern \
  "shared audio player timer tick plan lives in VoiceInkCore" \
  'VoiceInkAudioPlaybackTimerTickPlan|VoiceInkAudioPlaybackTimerTickAction' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "shared audio player tick plan exposes shell side-effect hints" \
  'shouldStopTimer|playerSeekTime' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "shared audio player state plan lives in VoiceInkCore" \
  'VoiceInkAudioPlaybackState' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "shared audio playback state applies timer tick plans" \
  'applyingTimerTickPlan' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "core checks execute audio player timer tick plan tests" \
  'AudioPlaybackTimelineTests\.testTimerTickPlanPreservesPlatformCompletionBehavior' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute iOS audio playback session configuration tests" \
  'AudioPlaybackTimelineTests\.testIOSAudioPlaybackSessionConfigurationPreservesPlaybackPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute iOS playback session lifecycle test" \
  'AudioSessionLifecycleStateTests\.testAudioSessionLifecycleStateCancelsPendingDeactivationForPlayback' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute audio player timer tick side-effect tests" \
  'AudioPlaybackTimelineTests\.testTimerTickPlanExposesShellSideEffectHints|AudioPlaybackTimelineTests\.testPlaybackStateAppliesTimerTickPlanActions' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute audio player state plan tests" \
  'AudioPlaybackTimelineTests\.testPlaybackState(LoadPreservesPlatformResetBehavior|PlansPlayPauseStopAndTickUpdates|SeekAndRateCycleUseSharedPolicies)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute audio playback diagnostics tests" \
  'AudioPlaybackTimelineTests\.testPlaybackDiagnosticsPreserveIOSLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute macOS audio playback diagnostics tests" \
  'AudioPlaybackTimelineTests\.testPlaybackDiagnosticsPreserveMacOSConsoleCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute macOS audio playback action banner tests" \
  'AudioPlaybackTimelineTests\.testPlaybackActionBannerPresentationPreservesMacOSActionCopy|AudioPlaybackTimelineTests\.testPlaybackActionBannerPresentationPreservesMacOSGuardCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS audio player consumes shared timer tick plan" \
  'VoiceInkAudioPlaybackTimerTickPlan\.macOS' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "iOS audio player shell consumes shared timer tick plan" \
  'VoiceInkAudioPlaybackTimerTickPlan\.iOS' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_pattern \
  "macOS audio player consumes shared playback state plan" \
  'VoiceInkAudioPlaybackState' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS audio player applies shared timer tick state plan" \
  'applyingTimerTickPlan' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "iOS audio player shell consumes shared playback state plan" \
  'VoiceInkAudioPlaybackState' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_pattern \
  "iOS audio player applies shared timer tick state plan" \
  'applyingTimerTickPlan' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_pattern \
  "migration docs track shared iOS playback session configuration" \
  'VoiceInkIOSAudioPlaybackSessionConfiguration` for the iOS playback category/mode policy.*enhancement prompt icon fallback' \
  docs/ios-single-repo-migration.md

require_pattern \
  "iOS audio player adapts shared playback diagnostics" \
  'VoiceInkAudioPlaybackDiagnostics\.(loadFailedMessage|playFailedMessage)' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_pattern \
  "macOS audio player adapts shared playback diagnostics" \
  'VoiceInkAudioPlaybackDiagnostics\.(macOSWaveformReadFailedMessage|macOSLoadFailedMessage)' \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "iOS audio player avoids shell-owned playback diagnostic copy" \
  '"(Failed to load audio:|Failed to play audio:)' \
  iOS/VoiceInk-ios/AudioPlayer.swift

reject_pattern \
  "iOS audio player avoids shell-owned playback session category literal" \
  'setCategory\(\.playback\)' \
  iOS/VoiceInk-ios/AudioPlayer.swift

reject_pattern \
  "macOS audio player avoids shell-owned playback diagnostic copy" \
  '"(Error reading audio file:|Error loading audio:)' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "iOS audio player view uses shared playback-rate policy" \
  'VoiceInkAudioPlaybackRate' \
  iOS/VoiceInk-ios/AudioPlayerView.swift

require_pattern \
  "macOS audio player uses shared playback presentation" \
  'VoiceInkAudioPlaybackPresentation' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS audio player uses shared audio action help copy" \
  'VoiceInkAudioPlaybackPresentation\.(showInFinderHelpText|selectEnhancementPromptHelpText|retranscribeAudioHelpText|reEnhanceWithSelectedPromptHelpText|viewDetailsHelpText)' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS audio player uses shared enhancement prompt icon fallback" \
  'VoiceInkAudioPlaybackPresentation\.enhancementPromptSystemImageName' \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS audio player avoids shell-owned enhancement prompt icon fallback" \
  'activePrompt\?\.icon \?\? "sparkles"|"sparkles"' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS inline history audio fallback uses shared details help copy" \
  'VoiceInkAudioPlaybackPresentation\.viewDetailsHelpText' \
  VoiceInk/Views/History/InlineHistoryView.swift

require_pattern \
  "macOS audio player uses shared playback update cadence" \
  'VoiceInkAudioPlaybackTimeline\.updateInterval' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS audio player action status adapts shared banner presentation" \
  'VoiceInkAudioPlaybackActionBannerPresentation\.(retranscriptionSuccess|reEnhancementSuccess|retranscriptionNoModelFailure|retranscriptionFailure|reEnhancementFailure|reEnhancementUnavailable)' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS audio player applies enhancement result through shared record mutation" \
  'applyEnhancementResult\(enhancement\)' \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS audio player avoids shell-only action status and re-enhance guard copy" \
  '"Retranscription successful"|"Re-enhancement successful"|"Retranscription failed"|"Re-enhancement failed"|"AI Enhancement is not enabled or configured"|VoiceInkTranscriptPresentation\.audioFile(ReEnhancement|Retranscription)(SuccessMessage|FailureMessage)|VoiceInkPostProcessingFailurePresentation\.enhancementUnavailableMessage|VoiceInkErrorDescription\.text\(for: VoiceInkEngineError\.noTranscriptionModelSelected\)|VoiceInkEngineError\.noTranscriptionModelSelected' \
  VoiceInk/Views/AudioPlayerView.swift

section "obsolete standalone post-processing failure presentation module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/PostProcessingFailurePresentation.swift

require_pattern \
  "post-processing failure presentation lives with transcript presentation" \
  'VoiceInkPostProcessingFailurePresentation' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

reject_pattern \
  "macOS enhancement record callers avoid shell-owned enhancement metadata mutation" \
  'transcription\.(enhancedText|aiEnhancementModelName|promptName|enhancementDuration|aiRequestSystemMessage|aiRequestUserMessage)\s*=' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "iOS audio player view uses shared playback presentation" \
  'VoiceInkAudioPlaybackPresentation' \
  iOS/VoiceInk-ios/AudioPlayerView.swift

require_pattern \
  "iOS audio player metadata uses shared playback icons" \
  'VoiceInkAudioPlaybackPresentation\.(timestampSystemImageName|durationSystemImageName)' \
  iOS/VoiceInk-ios/AudioPlayerView.swift

reject_pattern \
  "platform audio players avoid raw playback-rate storage key and labels" \
  '"audioPlaybackRate"|"1×"|"1\.5×"|"2×"' \
  VoiceInk/Views/AudioPlayerView.swift \
  iOS/VoiceInk-ios/AudioPlayer.swift \
  iOS/VoiceInk-ios/AudioPlayerView.swift

reject_pattern \
  "platform audio players avoid shell-only playback update cadence" \
  'withTimeInterval: +0\.1' \
  VoiceInk/Views/AudioPlayerView.swift \
  iOS/VoiceInk-ios/AudioPlayer.swift

reject_pattern \
  "platform audio players avoid shell-only completion tick policy" \
  'currentTime >= .*duration|!player\.isPlaying && self\.isPlaying' \
  VoiceInk/Views/AudioPlayerView.swift \
  iOS/VoiceInk-ios/AudioPlayer.swift

reject_pattern \
  "platform audio players avoid shell-owned timer tick action state branching" \
  'case \.markStopped|case \.markStoppedAndSeek|plan\.action' \
  VoiceInk/Views/AudioPlayerView.swift \
  iOS/VoiceInk-ios/AudioPlayer.swift

reject_pattern \
  "platform audio player shells avoid duplicate seek and rate state policy" \
  'VoiceInkAudioPlaybackTimeline\.clampedTime|VoiceInkAudioPlaybackRate\.next' \
  VoiceInk/Views/AudioPlayerView.swift \
  iOS/VoiceInk-ios/AudioPlayer.swift

reject_pattern \
  "platform audio player views avoid duplicate loading and play-pause presentation" \
  '"Loading\.\.\."|"pause\.fill"|"play\.fill"|"calendar"|"waveform"' \
  VoiceInk/Views/AudioPlayerView.swift \
  iOS/VoiceInk-ios/AudioPlayerView.swift

reject_pattern \
  "macOS audio player avoids shell-owned action help copy" \
  '"Show in Finder"|"Select enhancement prompt"|"Retranscribe this audio"|"Re-enhance with selected prompt"|"View details"' \
  VoiceInk/Views/AudioPlayerView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

reject_pattern \
  "iOS audio metadata views avoid duplicate separator text" \
  'Text\("•"\)' \
  iOS/VoiceInk-ios/AudioPlayerView.swift \
  iOS/VoiceInk-ios/NoteRowView.swift

require_pattern \
  "macOS audio-file duration UI uses shared positive-duration visibility" \
  'VoiceInkDurationPresentation\.shouldShowPositiveDuration' \
  VoiceInk/Views/AudioFileRow.swift

require_pattern \
  "macOS history duration UI uses shared positive-duration visibility" \
  'VoiceInkDurationPresentation\.shouldShowPositiveDuration' \
  VoiceInk/Views/History/TranscriptionListItem.swift

reject_pattern \
  "platform duration UI avoids shell-only positive-duration checks" \
  'duration > 0' \
  iOS/VoiceInk-ios/AudioPlayerView.swift \
  iOS/VoiceInk-ios/NoteRowView.swift \
  VoiceInk/Views/AudioFileRow.swift \
  VoiceInk/Views/History/TranscriptionListItem.swift

require_pattern \
  "macOS filler-word add button uses shared draft state" \
  'draftState\.canSubmit' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift

require_pattern \
  "iOS filler-word add button uses shared draft state" \
  'fillerWordDraftState\.canSubmit' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "platform filler-word views avoid shell-owned draft submit policy" \
  '@State private var (newWord|newFillerWord)\b|VoiceInkFillerWords\.hasDraft' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS mode provider availability comes from shared provider-key state" \
  'VoiceInkProviderKind\.availableProviders' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "iOS mode provider availability uses settings adapter" \
  'settings\.modeFormProviderAvailability' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "iOS settings adapter builds mode provider availability from provider-key state" \
  'availableProviders\(for: \.(transcription|postProcessing)\)' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "shared provider model selection presentation lives in VoiceInkCore" \
  'VoiceInkProviderModelSelectionPresentation|modelSelectionPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "iOS mode model selection uses shared presentation adapter" \
  'ProviderModelSelectionView|modelSelectionPresentation' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

reject_pattern \
  "iOS mode model selection avoids duplicate provider model branching" \
  'fixedModel\(for:|models\(for:' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "iOS mode prompt-template editing uses shared mode state" \
  '\$mode\.promptTemplate\.' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

section "obsolete standalone post-processing template module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/PostProcessingTemplate.swift
reject_file VoiceInkCore/Sources/VoiceInkCore/PostProcessingPromptTemplate.swift

require_patterns \
  "post-processing template type lives with mode policy" \
  VoiceInkCore/Sources/VoiceInkCore/Mode.swift \
  'VoiceInkPostProcessingTemplateType' \
  'VoiceInkPostProcessingPromptTemplate' \
  'transcriptCleanup'

reject_pattern \
  "iOS mode prompt-template editing avoids duplicate shell draft state" \
  'selectedTemplateType|customPromptText|mode\.promptTemplate = VoiceInkPostProcessingPromptTemplate' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "shared streaming mode presentation lives in VoiceInkCore" \
  'VoiceInkTranscriptionStreamingModePresentation|streamingToggleHelp|preloadToggleHelp' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionStreamingPreference.swift

require_pattern \
  "macOS cloud model card uses shared streaming mode presentation" \
  'VoiceInkTranscriptionStreamingModePresentation|streamingModePresentation\.(streamingToggleTitle|streamingToggleHelp|preloadToggleHelp)' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS FluidAudio model card uses shared streaming mode presentation" \
  'VoiceInkTranscriptionStreamingModePresentation|streamingModePresentation\.(streamingToggleTitle|streamingToggleHelp|preloadToggleHelp)' \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

reject_pattern \
  "macOS cloud model card avoids shallow streaming presentation wrappers" \
  'private var +(streamingModePresentation|isStreamingOnly)\b' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud model card avoids shell-only streaming presentation and registry lookup" \
  'CloudProviderRegistry\.provider\(for: model\.provider\)|"Streaming"|"Buffer Preload"|active-recording streaming|Saved-file batch mode|Rolling buffer can pre-run|Rolling buffer preload disabled' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud model card delegates selected-language repair planning to shared core" \
  'transcriptionLanguageSelectionFacts\.repairPlan' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud model card avoids shell-owned selected-language repair comparisons" \
  'validTranscriptionLanguageOrFallback|selectedLanguage !=' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS FluidAudio model card avoids shell-only streaming presentation copy" \
  '"Streaming"|"Buffer Preload"|active-recording streaming|Saved-file batch mode|Rolling buffer can pre-run|Rolling buffer preload disabled' \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

reject_pattern \
  "macOS model cards use shared per-model preload preference API" \
  'perModelPreloadEnabledKey|UserDefaults\.standard\.object\(forKey: preload|UserDefaults\.standard\.set\([^)]*forKey: preload' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

require_pattern \
  "macOS cloud model card reads shared per-model preload preference" \
  'VoiceInkRollingBufferPreloadSettings\.perModelPreloadEnabled\(forModelName: model\.name\)' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud model card saves shared per-model preload preference" \
  'VoiceInkRollingBufferPreloadSettings\.savePerModelPreloadEnabled\(newValue, forModelName: model\.name\)' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS FluidAudio model card reads shared per-model preload preference" \
  'VoiceInkRollingBufferPreloadSettings\.perModelPreloadEnabled\(forModelName: model\.name\)' \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

require_pattern \
  "macOS FluidAudio model card saves shared per-model preload preference" \
  'VoiceInkRollingBufferPreloadSettings\.savePerModelPreloadEnabled\(newValue, forModelName: model\.name\)' \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

require_pattern \
  "iOS app launch registers shared default values" \
  'VoiceInkDefaultSettings\.iOS\.registerUserDefaults\(\)' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

section "obsolete standalone startup preference migration module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/StartupPreferenceMigration.swift

require_pattern \
  "shared startup preference migration lives with UserDefaults preference policy" \
  'VoiceInkStartupPreferenceMigration|VoiceInkStartupPreferenceMigrationPlatform|PunctuationCleanupMode\.migrateLegacyUserDefaultIfNeeded|VoiceInkPasteMethod\.migrateLegacyUserDefaultIfNeeded' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "core tests cover shared startup preference migration platform sets" \
  'testStartupPreferenceMigrationUsesIOSMigrationSet|testStartupPreferenceMigrationUsesMacOSMigrationSet' \
  VoiceInkCore/Tests/VoiceInkCoreTests/UserDefaultsPreferencesTests.swift

require_pattern \
  "core check runner executes shared startup preference migration tests" \
  'testStartupPreferenceMigrationUsesIOSMigrationSet|testStartupPreferenceMigrationUsesMacOSMigrationSet' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "iOS app launch runs shared startup preference migration" \
  'VoiceInkStartupPreferenceMigration\.migrateLegacyPreferences\(for: \.iOS\)' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

reject_pattern \
  "platform shells avoid shell-owned legacy preference migration lists" \
  'PunctuationCleanupMode\.migrateLegacyUserDefaultIfNeeded|VoiceInkPasteMethod\.migrateLegacyUserDefaultIfNeeded' \
  VoiceInk/AppDefaults.swift \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS settings stays out of startup migration orchestration" \
  'VoiceInkStartupPreferenceMigration\.migrateLegacyPreferences' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "shared app settings reset state lives in VoiceInkCore" \
  'VoiceInkAppSettingsResetState|appSettingsResetState' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared app settings reset state owns provider-key deletion targets" \
  'apiKeyProvidersToDelete' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_patterns \
  "shared app settings reset state owns ordered application actions" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkAppSettingsResetAction' \
  'applicationActions' \
  'applyResetState' \
  'clearCoreUserSettings' \
  'deleteProviderAPIKeys'

require_patterns \
  "core checks execute app settings reset action tests" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'UserDefaultsPreferencesTests\.testAppSettingsResetStateBuildsApplicationActionsInOrder' \
  'UserDefaultsPreferencesTests\.testAppSettingsResetStateSkipsProviderDeletionActionWhenNoProviders'

require_patterns \
  "shared iOS app settings startup state lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkIOSAppSettingsStartupState' \
  'VoiceInkIOSAppSettingsStartupPolicy' \
  'VoiceInkModeStorage\.loadModes' \
  'VoiceInkProviderAPIKeyState\.loadingStoredKeys' \
  'VoiceInkTranscriptionCleanupSettings\.current' \
  'VoiceInkTranscriptionLanguagePreference\.selectedLanguage'

require_pattern \
  "core checks execute iOS app settings startup policy test" \
  'UserDefaultsPreferencesTests\.testIOSAppSettingsStartupPolicyLoadsPersistedStateThroughAdapters' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_patterns \
  "shared iOS first-time setup policy owns mode repair and onboarding completion intent" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkIOSFirstTimeSetupPolicy' \
  'VoiceInkIOSFirstTimeSetupPlan' \
  'VoiceInkIOSFirstTimeSetupAction' \
  'applicationActions' \
  'modeSettingsRepairPlan' \
  'shouldSaveHasCompletedOnboarding' \
  'VoiceInkModeSettingsPolicy\.defaultModeRepairPlan'

require_pattern \
  "core checks execute iOS first-time setup action test" \
  'UserDefaultsPreferencesTests\.testIOSFirstTimeSetupPlanBuildsApplicationActionsInOrder' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute iOS first-time setup policy test" \
  'UserDefaultsPreferencesTests\.testIOSFirstTimeSetupPolicySeedsDefaultModeAndCompletionIntent' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared app data reset plan lives in VoiceInkCore" \
  'VoiceInkAppDataResetPlan|VoiceInkAppDataResetStep|VoiceInkAppDataResetFilePlan|VoiceInkAppDataResetDiagnostics|deleteTranscriptionRecords|cleanFiles|resetAppSettings|swiftDataResetFailedMessage' \
  VoiceInkCore/Sources/VoiceInkCore/AppDataReset.swift

require_pattern \
  "core checks execute iOS app data reset tests" \
  'AppDataResetTests\.test(IOSResetPlanPreservesRecordFileAndSettingsResetOrder|AppDataResetDiagnosticsPreserveIOSLogCopy)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared current-model preference remembers legacy macOS model key" \
  'legacyModelNameKey += +"CurrentModel"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared current-model preference clears legacy macOS model key" \
  'removeObject\(forKey: legacyModelNameKey\)' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_patterns \
  "shared current-model preference owns load plan" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkCurrentTranscriptionModelLoadPlan' \
  'VoiceInkCurrentTranscriptionModelLoadAction' \
  'shouldRestoreSavedModel' \
  'shouldClearStoredModelName'

require_patterns \
  "macOS transcription model manager delegates current-model load planning" \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift \
  'VoiceInkCurrentTranscriptionModelPreference\.loadPlan' \
  'loadPlan\.shouldClearStoredModelName' \
  'loadPlan\.shouldRestoreSavedModel'

require_patterns \
  "core checks execute current-model load plan tests" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'UserDefaultsPreferencesTests\.testCurrentTranscriptionModelLoadPlanNoOpsWhenNoModelIsSaved' \
  'UserDefaultsPreferencesTests\.testCurrentTranscriptionModelLoadPlanNoOpsWhenSavedModelIsMissingFromRegistry' \
  'UserDefaultsPreferencesTests\.testCurrentTranscriptionModelLoadPlanRestoresAvailableSavedModel' \
  'UserDefaultsPreferencesTests\.testCurrentTranscriptionModelLoadPlanClearsUnavailableSavedModel'

require_pattern \
  "macOS transcription model manager clears through shared current-model preference" \
  'VoiceInkCurrentTranscriptionModelPreference\.clearModelName\(\)' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

reject_pattern \
  "macOS transcription model manager avoids shell-only legacy model key cleanup" \
  'removeObject\(forKey: +"CurrentModel"\)|"CurrentModel"' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

reject_pattern \
  "macOS transcription model manager avoids shell-owned current-model load availability branch" \
  'guard +isAvailableOnCurrentOS\(savedModel\)|if let savedModelName = VoiceInkCurrentTranscriptionModelPreference\.modelName\(\),' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

require_pattern \
  "macOS transcription model manager delegates selected-language repair planning to shared core" \
  'transcriptionLanguageSelectionFacts\.repairPlan' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

reject_pattern \
  "macOS transcription model manager avoids shell-owned selected-language repair comparisons" \
  'validTranscriptionLanguageOrFallback|currentLanguage !=|compatibleLanguage' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

require_pattern \
  "shared audio-session timeout preference owns iOS timeout minimum" \
  'minimumSeconds = 0' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio-session timeout preference owns iOS timeout maximum" \
  'maximumSeconds = 300' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio-session timeout preference owns iOS timeout step" \
  'stepSeconds = 15' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio-session timeout preference owns iOS deactivation plan" \
  'VoiceInkAudioSessionDeactivationPlan|deactivationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio-session timeout preference owns iOS deactivation execution intent" \
  'VoiceInkAudioSessionDeactivationExecutionPlan|executionPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio-session timeout presentation lives in VoiceInkCore" \
  'VoiceInkAudioSessionTimeoutPresentation|settingsPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "iOS audio settings use shared timeout presentation" \
  'audioTimeoutPresentation|settingsPresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS audio settings use shared timeout display policy" \
  'VoiceInkAudioSessionTimeoutPreference\.displayText' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS audio settings use shared timeout range policy" \
  'VoiceInkAudioSessionTimeoutPreference\.(minimumSeconds|maximumSeconds|stepSeconds)' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "migration docs track shared iOS audio-session recording configuration" \
  'recording category/mode/options through `VoiceInkIOSAudioSessionRecordingConfiguration`' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "iOS audio settings avoid shell-only timeout range and display policy" \
  '0\.\.\.300|step: 15|audioSessionTimeoutSeconds\)s' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS audio settings avoid shell-only timeout presentation copy" \
  '"(Audio Settings|Session Timeout|How long to keep the microphone session active after recording stops\\. Longer timeouts prevent '\''session activation failed'\'' errors when recording frequently, but may use more battery\\.)"' \
  iOS/VoiceInk-ios/SettingsView.swift

section "obsolete standalone audio-session lifecycle state module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/AudioSessionLifecycleState.swift

require_pattern \
  "shared audio-session lifecycle state uses shared deactivation plan" \
  'VoiceInkAudioSessionTimeoutPreference\.deactivationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/IOSAudioConfiguration.swift

require_pattern \
  "shared audio-session timeout owns countdown update interval" \
  'countdownUpdateInterval' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio-session timeout owns countdown remaining-time policy" \
  'remainingTimeAfterCountdownTick' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio-session lifecycle state lives in VoiceInkCore" \
  'VoiceInkAudioSessionLifecycleState|markActivatedForRecording|scheduleDeactivationExecution|advanceCountdownExecution|markDeactivated' \
  VoiceInkCore/Sources/VoiceInkCore/IOSAudioConfiguration.swift

require_patterns \
  "shared iOS audio-session recording configuration lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/IOSAudioConfiguration.swift \
  'VoiceInkIOSAudioSessionRecordingConfiguration' \
  'voiceRecording' \
  'playAndRecord' \
  'spokenAudio' \
  'defaultToSpeaker' \
  'allowBluetooth' \
  'allowBluetoothA2DP' \
  'mixWithOthers'

require_pattern \
  "shared audio-session diagnostics live in VoiceInkCore" \
  'VoiceInkAudioSessionDiagnostics|activatedForRecordingMessage|activationFailedMessage|deactivationScheduledMessage|deactivatedMessage|deactivationFailedMessage' \
  VoiceInkCore/Sources/VoiceInkCore/IOSAudioConfiguration.swift

require_pattern \
  "VoiceInkCore check runner executes iOS audio-session recording configuration proof" \
  'testIOSAudioSessionRecordingConfigurationPreservesRecordingPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "VoiceInkCore check runner executes audio-session diagnostics proof" \
  'testAudioSessionDiagnosticsPreserveIOSLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "iOS audio-session manager uses shared lifecycle state" \
  'VoiceInkAudioSessionLifecycleState|lifecycleState' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

require_patterns \
  "iOS audio-session manager adapts shared recording configuration" \
  iOS/VoiceInk-ios/AudioSessionManager.swift \
  'VoiceInkIOSAudioSessionRecordingConfiguration\.voiceRecording' \
  'configuration\.category\.avCategory' \
  'configuration\.mode\.avMode' \
  'configuration\.avOptions'

require_pattern \
  "iOS audio-session manager adapts shared diagnostics" \
  'VoiceInkAudioSessionDiagnostics\.(activatedForRecordingMessage|activationFailedMessage|deactivationScheduledMessage|deactivatedMessage|deactivationFailedMessage)' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

require_pattern \
  "iOS audio-session manager delegates deactivation planning to shared lifecycle state" \
  'lifecycleState\.scheduleDeactivationExecution\(timeoutSeconds:' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

require_pattern \
  "iOS audio-session manager delegates countdown ticks to shared lifecycle state" \
  'lifecycleState\.advanceCountdownExecution\(\)' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

reject_pattern \
  "iOS audio-session manager avoids shell-owned deactivation-plan matching" \
  'case \.(immediate|delayed)|== \.immediate|VoiceInkAudioSessionDeactivationPlan' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

reject_pattern \
  "iOS audio-session manager avoids shell-only timeout scheduling policy" \
  'shouldDeactivateImmediately|deactivationInterval|timeoutSeconds > 0|TimeInterval\(timeoutSeconds\)|withTimeInterval: +1\.0|timeoutRemaining -= 1|VoiceInkAudioSessionTimeoutPreference\.(deactivationPlan|remainingTimeAfterCountdownTick)' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

reject_pattern \
  "iOS audio-session manager avoids shell-owned recording configuration literals" \
  'mode: \.spokenAudio|options: \[\.(defaultToSpeaker|allowBluetooth|allowBluetoothA2DP|mixWithOthers)' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

reject_pattern \
  "iOS audio-session manager avoids shell-owned lifecycle state mutation" \
  '@Published var +(isSessionActive|timeoutRemaining)|isSessionActive =|timeoutRemaining =' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

reject_pattern \
  "iOS audio-session manager avoids shell-owned diagnostic copy" \
  '"(Audio session activated for recording|Audio session activation failed:|Audio session deactivation scheduled in|Audio session deactivated|Failed to deactivate audio session:)' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

require_pattern \
  "iOS app settings reset consumes shared reset state" \
  'VoiceInkDefaultSettings\.iOS\.appSettingsResetState\.applicationActions' \
  iOS/VoiceInk-ios/AppSettings.swift

require_patterns \
  "iOS app settings initializer consumes shared startup state" \
  iOS/VoiceInk-ios/AppSettings.swift \
  'VoiceInkIOSAppSettingsStartupPolicy\.state' \
  'startupState\.modes' \
  'startupState\.apiKeyState' \
  'startupState\.transcriptionCleanupSettings' \
  'startupState\.selectedTranscriptionLanguage'

reject_context_pattern \
  "iOS app settings initializer avoids shell-owned startup preference loading" \
  'private init\(\)' \
  'VoiceInkModeStorage\.(loadModes|loadSelectedModeId)|VoiceInkProviderAPIKeyState\.loadingStoredKeys|VoiceInkAudioSessionTimeoutPreference\.timeoutSeconds|VoiceInkTranscriptionCleanupSettings\.current|VoiceInkFillerWordPreference\.words|VoiceInkWordReplacementPreference\.rules|VoiceInkCustomVocabularyPreference\.terms|VoiceInkTranscriptionLanguagePreference\.selectedLanguage' \
  iOS/VoiceInk-ios/AppSettings.swift

require_patterns \
  "iOS app settings first-time setup consumes shared setup plan" \
  iOS/VoiceInk-ios/AppSettings.swift \
  'VoiceInkIOSFirstTimeSetupPolicy\.plan' \
  'VoiceInkIOSFirstTimeSetupPlan' \
  'applyFirstTimeSetupPlan' \
  'plan\.applicationActions' \
  'applyModeSettingsRepair'

reject_context_pattern \
  "iOS app settings first-time setup avoids direct shared setup plan field execution" \
  'private func applyFirstTimeSetupPlan' \
  'plan\.(modeSettingsRepairPlan|shouldSaveHasCompletedOnboarding)' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_context_pattern \
  "iOS app settings first-time setup avoids shell-owned default-mode/onboarding sequencing" \
  'func completeFirstTimeSetup' \
  'ensureDefaultModeExists\(\)' \
  iOS/VoiceInk-ios/AppSettings.swift

require_patterns \
  "iOS app settings reset adapts shared reset actions" \
  iOS/VoiceInk-ios/AppSettings.swift \
  'VoiceInkAppSettingsResetAction' \
  'applyAppSettingsResetAction' \
  'applyAppSettingsResetState' \
  'deleteProviderAPIKeys'

reject_pattern \
  "iOS app settings reset avoids direct provider-key target reads" \
  'resetState\.apiKeyProvidersToDelete' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS app settings reset consumes shared app data reset plan" \
  'VoiceInkAppDataResetPlan\.iOS|for step in resetPlan\.steps|applyResetStep' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS app settings reset adapts shared app data reset diagnostics" \
  'VoiceInkAppDataResetDiagnostics\.swiftDataResetFailedMessage' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS app settings reset avoids shell-only reset state assembly" \
  'let +defaults += +VoiceInkDefaultSettings\.iOS|modes += +\[\]|selectedModeId += +nil|apiKeyState += +VoiceInkProviderAPIKeyState\(\)|wordReplacements += +\[\]|customVocabularyTerms += +\[\]' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS app settings reset avoids shell-only file reset sequence" \
  'VoiceInkAppDataResetFilePlan\.iOS|let +recordingsDir|let +modelsDir|let +cachesURL|let +tmpPath|contentsOfDirectory|removeItem\(atPath:' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS app settings reset avoids shell-owned SwiftData reset diagnostic copy" \
  '"Failed to reset SwiftData:' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS app launch registers shared macOS default values" \
  'VoiceInkDefaultSettings\.macOS\.registeredUserDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS app launch registers shared default transcription model" \
  'currentTranscriptionModel: VoiceInkTranscriptionModelCatalog\.defaultMacOSFluidAudioModelName' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS app launch uses shared Launch at Login default policy" \
  'VoiceInkMacOSLaunchAtLoginDefaultPolicy\.shouldEnableByDefaultBeforeRegisteringDefaults|VoiceInkMacOSLaunchAtLoginDefaultPolicy\.markDefaultApplied' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS Launch at Login default policy uses shared onboarding completion storage state" \
  'VoiceInkOnboardingPreference\.hasStoredCompletionState' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS Launch at Login default policy owns existing storage key" \
  'didApplyLaunchAtLoginDefault += +"DidApplyLaunchAtLoginDefault"|didApplyDefaultKey += +VoiceInkUserDefaultsKey\.didApplyLaunchAtLoginDefault' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

reject_pattern \
  "macOS app launch avoids hardcoded default transcription model" \
  '"parakeet-tdt-0\.6b-v2"' \
  VoiceInk/AppDefaults.swift

reject_pattern \
  "macOS app launch avoids raw onboarding completion storage checks" \
  'VoiceInkUserDefaultsKey\.hasCompletedOnboarding|object\(forKey: +"hasCompletedOnboarding"\)' \
  VoiceInk/AppDefaults.swift

require_patterns \
  "shared dynamic AI provider preference owns Ollama runtime defaults" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'defaultOllamaBaseURL' \
  'defaultOllamaRuntimeSelectedModel' \
  'ollamaRuntimeSelectedModel'

require_patterns \
  "macOS Ollama service uses shared runtime defaults" \
  VoiceInk/Services/OllamaService.swift \
  'VoiceInkDynamicAIProviderPreference\.ollamaBaseURL\(\)' \
  'VoiceInkDynamicAIProviderPreference\.ollamaRuntimeSelectedModel\(\)'

reject_pattern \
  "macOS Ollama default base URL shim stays deleted" \
  'defaultBaseURL|VoiceInkPreferenceDefault\.ollamaBaseURL' \
  VoiceInk/Services/OllamaService.swift \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

reject_pattern \
  "macOS Ollama service avoids duplicate selected-model fallback literals" \
  '"llama2"|ollamaSelectedModel\(fallback:|legacyOllamaServiceSelectedModelFallback' \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS app launch avoids hard-coded selected-language defaults" \
  'selectedTranscriptionLanguage: "en"' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS language selection view uses shared macOS language default" \
  'VoiceInkDefaultSettings\.macOS\.selectedTranscriptionLanguage' \
  VoiceInk/Views/AI\ Models/LanguageSelectionView.swift

require_pattern \
  "macOS cloud model card uses shared macOS language default" \
  'VoiceInkDefaultSettings\.macOS\.selectedTranscriptionLanguage' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS model settings uses shared macOS language default" \
  'VoiceInkDefaultSettings\.macOS\.selectedTranscriptionLanguage' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "shared local Whisper prompt catalog uses shared selected-language fallback" \
  'VoiceInkTranscriptionLanguagePreference\.selectedLanguage\(' \
  VoiceInkCore/Sources/VoiceInkCore/LocalWhisperPromptCatalog.swift

require_pattern \
  "shared local Whisper prompt settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSLocalWhisperPromptSettingsPresentation|macOSSettingsPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/LocalWhisperPromptCatalog.swift

require_pattern \
  "macOS local Whisper prompt persists through shared prompt preference" \
  'VoiceInkTranscriptionPromptPreference\.saveLocalWhisperPromptForSelectedLanguage\(\)' \
  VoiceInk/Transcription/Whisper/WhisperPrompt.swift

require_pattern \
  "macOS model settings uses shared local Whisper prompt presentation" \
  'localWhisperPromptPresentation\.(sectionTitle|helpText|learnMoreURLString|saveButtonTitle|editButtonTitle)' \
  VoiceInk/Views/ModelSettingsView.swift

reject_pattern \
  "macOS Whisper model manager avoids owning local prompt object" \
  'WhisperPrompt\(' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

require_pattern \
  "migration checklist tracks shared local Whisper prompt settings presentation" \
  'macOS local Whisper output-format settings labels/help/actions route through `VoiceInkLocalWhisperPromptCatalog`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared Power Mode config uses shared macOS selected-language fallback" \
  'VoiceInkTranscriptionLanguagePreference\.selectedMacOSLanguage\(\)' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode selected-language display formatting lives in VoiceInkCore" \
  'selectedLanguageDisplayText|defaultOverrideDisplayText|autoLanguageDisplayText|englishLanguageDisplayText' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode trigger-count display formatting lives in VoiceInkCore" \
  'appTriggerCountText|websiteTriggerCountText' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode delete confirmation copy lives in VoiceInkCore" \
  'deleteConfirmationTitle|deleteConfirmation\(configName:' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode validation alert copy lives in VoiceInkCore" \
  'validationAlertTitle|validationAlert\(errors:' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode no-transcription-models form copy lives in VoiceInkCore" \
  'noTranscriptionModelsAvailableText' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode AI-enhancement empty-state copy lives in VoiceInkCore" \
  'noAIProvidersConnectedText|noAIModelsAvailableText|noEnhancementPromptsAvailableText' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode row detail presentation lives in VoiceInkCore" \
  'VoiceInkPowerModeRowDetailPresentation|rowDetailPresentation|systemImageName|usesAccentStyle' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode panel sidebar popover chrome copy lives in VoiceInkCore" \
  'panelTitle|panelSubtitle|panelInfoTipText|panelLearnMoreURLString|settingsSectionTitle|settingsToggleHelpText|persistConfiguredPreferencesTitle|persistConfiguredPreferencesHelpText|settingsDisableAlertTitle|settingsDisableAlertButtonTitle|settingsDisableAlertMessage|addButtonSystemImageName|reorderButtonTitle|reorderButtonSystemImageName|reorderPanelTitle|reorderPanelCloseHelpText|reorderPanelCloseSystemImageName|reorderHandleSystemImageName|defaultBadgeTitle|disabledBadgeTitle|emptyPanelTitle|emptyPanelSystemImageName|sidebarEmptyTitle|sidebarEmptyButtonTitle|sidebarEmptySystemImageName|addIconButtonSystemImageName|popoverTitle|popoverEmptyTitle|popoverEmptySystemImageName|popoverSelectedSystemImageName|rowEditActionTitle|rowEditActionSystemImageName|rowDeleteActionTitle|rowDeleteActionSystemImageName|appTriggerSystemImageName|websiteTriggerSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode config form chrome copy lives in VoiceInkCore" \
  'formCloseSystemImageName|generalSectionTitle|nameFieldPlaceholder|triggerScenariosSectionTitle|applicationsSectionTitle|addApplicationHelpText|noApplicationsText|appPickerSearchPlaceholder|appPickerSearchSystemImageName|appPickerClearSearchSystemImageName|appPickerSelectedSystemImageName|websitesSectionTitle|websiteURLFieldPlaceholder|addWebsiteHelpText|noWebsitesText|appTriggerSystemImageName|websiteTriggerSystemImageName|removeTriggerSystemImageName|transcriptionSectionTitle|transcriptionModelPickerTitle|transcriptionLanguageTitle|autodetectedLanguageText|transcriptFormattingDisclosureSystemImageName|aiEnhancementSectionTitle|advancedSectionTitle|formSaveButtonTitle' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "shared Power Mode app trigger selection policy lives in VoiceInkCore" \
  'containsPowerModeAppConfig|togglePowerModeAppConfig' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS Power Mode rows use shared selected-language display formatting" \
  'VoiceInkPowerModePresentation\.selectedLanguageDisplayText' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

require_pattern \
  "macOS Power Mode rows use shared trigger-count display formatting" \
  'VoiceInkPowerModePresentation\.(appTriggerCountText|websiteTriggerCountText)' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

require_pattern \
  "macOS Power Mode row context menu uses shared delete confirmation copy" \
  'VoiceInkPowerModePresentation\.deleteConfirmation\(configName:' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

require_pattern \
  "macOS Power Mode rows use shared row detail presentation" \
  'VoiceInkPowerModePresentation\.rowDetailPresentation|PowerModeRowDetailChipView|chip\.(systemImageName|usesAccentStyle)' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode rows avoid shallow row presentation wrappers" \
  'private var +(selectedPromptTitle|appText|websiteText|rowDetailPresentation)\b' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

require_pattern \
  "macOS Power Mode panel uses shared chrome copy" \
  'VoiceInkPowerModePresentation\.(panelTitle|panelSubtitle|panelInfoTipText|panelLearnMoreURLString|addButtonSystemImageName|reorderButtonTitle|reorderButtonSystemImageName|emptyPanelTitle|emptyPanelMessage|emptyPanelSystemImageName|reorderPanelTitle|reorderPanelCloseHelpText|reorderPanelCloseSystemImageName|reorderHandleSystemImageName|defaultBadgeTitle|disabledBadgeTitle)' \
  VoiceInk/PowerMode/PowerModeView.swift

require_pattern \
  "macOS Power Mode settings uses shared presentation" \
  'VoiceInkPowerModePresentation\.(settingsSectionTitle|settingsToggleHelpText|panelLearnMoreURLString|persistConfiguredPreferencesTitle|persistConfiguredPreferencesHelpText|settingsDisableAlertTitle|settingsDisableAlertButtonTitle|settingsDisableAlertMessage)' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS Power Mode sidebar and row actions use shared chrome copy" \
  'VoiceInkPowerModePresentation\.(sidebarEmptyTitle|sidebarEmptyMessage|sidebarEmptyButtonTitle|sidebarEmptySystemImageName|addIconButtonSystemImageName|defaultBadgeTitle|rowEditActionTitle|rowEditActionSystemImageName|rowDeleteActionTitle|rowDeleteActionSystemImageName|appTriggerSystemImageName|websiteTriggerSystemImageName)' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

require_pattern \
  "macOS Power Mode popover uses shared chrome copy" \
  'VoiceInkPowerModePresentation\.(popoverTitle|popoverEmptyTitle|popoverEmptySystemImageName|popoverSelectedSystemImageName)' \
  VoiceInk/PowerMode/PowerModePopover.swift

require_pattern \
  "macOS recorder Power Mode button consumes shared icon fallback policy" \
  'VoiceInkPowerModePresentation\.recorderButtonIcon' \
  VoiceInk/Views/Recorder/RecorderComponents.swift

require_pattern \
  "core checks execute recorder Power Mode button icon fallback test" \
  'PowerModePresentationTests\.testRecorderButtonIconPreservesActiveEmojiFallbacks' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS recorder Power Mode button avoids shell-owned icon fallback" \
  '"✨"|activeConfiguration\?\.emoji' \
  VoiceInk/Views/Recorder/RecorderComponents.swift

require_pattern \
  "macOS Power Mode config form uses shared chrome copy" \
  'VoiceInkPowerModePresentation\.(formCloseHelpText|formCloseSystemImageName|generalSectionTitle|nameFieldPlaceholder|triggerScenariosSectionTitle|applicationsSectionTitle|addApplicationHelpText|noApplicationsText|websitesSectionTitle|websiteURLFieldPlaceholder|addWebsiteHelpText|noWebsitesText|appTriggerSystemImageName|websiteTriggerSystemImageName|removeTriggerSystemImageName|transcriptionSectionTitle|transcriptionModelPickerTitle|transcriptionLanguageTitle|autodetectedLanguageText|transcriptFormattingDisclosureSystemImageName|aiEnhancementSectionTitle|aiEnhancementToggleTitle|advancedSectionTitle|formDeleteButtonTitle|formCancelButtonTitle|formSaveButtonTitle)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS app picker uses shared search copy and app trigger selection policy" \
  'VoiceInkPowerModePresentation\.(appPickerSearchPlaceholder|appPickerSearchSystemImageName|appPickerClearSearchSystemImageName|appPickerSelectedSystemImageName)|selectedAppConfigs\.(containsPowerModeAppConfig|togglePowerModeAppConfig)' \
  VoiceInk/PowerMode/AppPicker.swift

require_pattern \
  "macOS Power Mode edit form uses shared delete confirmation copy" \
  'VoiceInkPowerModePresentation\.deleteConfirmation(Title|\(configName:)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS Power Mode edit form uses shared validation alert copy" \
  'VoiceInkPowerModePresentation\.validationAlert\(errors:' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS Power Mode edit form uses shared no-transcription-models copy" \
  'VoiceInkPowerModePresentation\.noTranscriptionModelsAvailableText' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS Power Mode edit form uses shared AI-enhancement empty-state copy" \
  'VoiceInkPowerModePresentation\.(noAIProvidersConnectedText|noAIModelsAvailableText|noEnhancementPromptsAvailableText)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode AI-enhancement form chrome copy lives in VoiceInkCore" \
  'aiProviderFormTitle|aiModelFormTitle|enhancementPromptFormTitle|refreshModelsButtonTitle|refreshModelsButtonHelp|setAsDefaultToggleTitle|setAsDefaultHelpText' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "macOS Power Mode edit form uses shared AI-enhancement form chrome copy" \
  'VoiceInkPowerModePresentation\.(aiProviderFormTitle|aiModelFormTitle|enhancementPromptFormTitle|refreshModelsButtonTitle|refreshModelsButtonHelp|contextAwarenessDisplayText|setAsDefaultToggleTitle|setAsDefaultHelpText)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode advanced form chrome copy lives in VoiceInkCore" \
  'autoSendFormTitle|autoSendHelpText|keyboardShortcutFormTitle|keyboardShortcutHelpText' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

require_pattern \
  "macOS Power Mode edit form uses shared advanced form chrome copy" \
  'VoiceInkPowerModePresentation\.(autoSendFormTitle|autoSendHelpText|keyboardShortcutFormTitle|keyboardShortcutHelpText)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode emoji catalog and input policy lives in VoiceInkCore" \
  'VoiceInkPowerModeEmojiCatalog|customEmojisKey = "userAddedEmojis"|defaultEmojis|addCustomEmoji|removeCustomEmoji|firstValidEmojiCharacter|VoiceInkPowerModeEmojiInputPresentation|VoiceInkPowerModeEmojiInputDraft|inputDraft|submitFeedbackMessage|addedEmoji|customEmojiFieldPlaceholder|addButtonTitle|cancelButtonTitle|tipText|addEmojiAccessibilityLabel|addEmojiSystemImageName|addCustomEmojiHelpText|removeCustomEmojiSystemImageName|isErrorMessage|VoiceInkPowerModeEmojiRemovalAlertPresentation|inUseAlert' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModeEmojiPolicy.swift

require_pattern \
  "shared Power Mode emoji input draft policy lives in VoiceInkCore" \
  'VoiceInkPowerModeEmojiInputDraft|inputDraft\(' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModeEmojiPolicy.swift

require_pattern \
  "shared Power Mode emoji submit feedback policy lives in VoiceInkCore" \
  'addedEmoji|submitFeedbackMessage' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModeEmojiPolicy.swift

require_pattern \
  "macOS Power Mode emoji manager consumes shared emoji policy" \
  'VoiceInkPowerModeEmojiCatalog\.(allEmojis|customEmojis|saveCustomEmojis|addCustomEmoji|removeCustomEmoji|isCustomEmoji)|VoiceInkPowerModeEmojiInputPresentation\.inputDraft' \
  VoiceInk/PowerMode/EmojiManager.swift

reject_pattern \
  "macOS Power Mode emoji manager avoids shallow load/save wrappers" \
  'private +func +(loadCustomEmojis|saveCustomEmojis)\(' \
  VoiceInk/PowerMode/EmojiManager.swift

require_pattern \
  "macOS Power Mode emoji picker consumes shared emoji validation and copy" \
  'emojiManager\.inputDraft|VoiceInkPowerModeEmojiInputPresentation\.(addEmojiSystemImageName|removeCustomEmojiSystemImageName|submitFeedbackMessage)' \
  VoiceInk/PowerMode/EmojiPickerView.swift

require_pattern \
  "macOS Power Mode emoji picker applies shared submit feedback" \
  'VoiceInkPowerModeEmojiInputPresentation\.submitFeedbackMessage' \
  VoiceInk/PowerMode/EmojiPickerView.swift

require_pattern \
  "migration checklist tracks shared Power Mode emoji policy gate" \
  'macOS Power Mode emoji catalog, custom emoji storage key, input validation, duplicate detection, add/remove mutation policy, picker input-draft feedback, submit-result feedback, picker action/icon/help copy, feedback severity, and in-use deletion alert presentation route through `VoiceInkPowerModeEmojiCatalog`/`VoiceInkPowerModeEmojiInputPresentation`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared Power Mode chrome copy gate" \
  'macOS Power Mode settings row, disable-alert copy, panel, sidebar empty state, reorder sheet, badges, row actions, manual-selection popover copy, recorder button icon fallback, panel help URL, and panel/reorder/sidebar/form/app-picker/popover/row trigger/action symbols route through `VoiceInkPowerModePresentation`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared Power Mode config form chrome gate" \
  'macOS Power Mode config form seed defaults, trigger-section labels, transcription section labels, AI toggle title, footer actions, website add planning, and trigger removal route through `VoiceInkPowerModeConfigurationFormState`/`VoiceInkPowerModePresentation`/`VoiceInkPowerModePolicy`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "migration checklist tracks shared Power Mode app picker gate" \
  'macOS Power Mode app picker search copy and app-trigger toggle policy route through `VoiceInkPowerModePresentation`/`VoiceInkPowerModeAppConfig`' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS Power Mode rows avoid shell-only selected-language fallback formatting" \
  'langCode == "auto"|langCode == "en"|langCode\.uppercased\(\)' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode edit form avoids duplicate no-transcription-models copy" \
  'No transcription models available\. Please connect to a cloud service or download a local model in the AI Models tab\.' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode edit form avoids duplicate AI-enhancement empty-state copy" \
  'No providers connected|No models loaded|No models available|No prompts available' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode edit form avoids duplicate AI-enhancement form chrome copy" \
  '"(AI Provider|AI Model|Enhancement Prompt|Context Awareness|Refresh Models|Refresh models|Set as default|Default power mode is used when no specific app or website matches are found\.)"' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode edit form avoids duplicate advanced form chrome copy" \
  '"(Auto Send|Automatically presses a key combination after pasting text\. Useful for chat applications or forms that use different send shortcuts\.|Keyboard Shortcut|Assign a unique keyboard shortcut to instantly activate this Power Mode and start recording\.)"' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode config form avoids shell-only trigger and section chrome copy" \
  '"(New Power Mode|General|Name|Trigger Scenarios|Applications|Add application|No applications added|Websites|Enter website URL|Add website|No websites added|Transcription|Model|Language|Autodetected|AI Enhancement|Advanced|Save Changes)"|Button\("(Delete|Cancel)"|help\("Close"' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode config form avoids shell-only form symbol metadata" \
  '"(xmark|app\.fill|xmark\.circle\.fill|globe|chevron\.right)"' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS app picker avoids shell-only search copy and app trigger selection policy" \
  '"Search apps\.\.\."|"(magnifyingglass|xmark\.circle\.fill|checkmark)"|selectedAppConfigs\.(contains|firstIndex|append|remove)\(' \
  VoiceInk/PowerMode/AppPicker.swift

reject_pattern \
  "macOS Power Mode emoji shell avoids raw catalog storage and validation policy" \
  '"userAddedEmojis"|private let +defaultEmojis|extension +String|var +isValidEmoji|func +firstValidEmojiCharacter|func +isErrorFeedbackMessage|TextField\("➕"|Button\("Add"\)|Button\("Cancel"\)|"(Emoji cannot be empty\.|Invalid emoji\.|Invalid emoji character\.|Emoji already exists!|Could not add emoji\.|Tip: Use ⌃⌘Space for emoji picker or paste an emoji\.|Add Emoji|Add custom emoji|Emoji in Use|The emoji \\".*\\" is currently used by one or more Power Modes and cannot be removed\.|OK|plus\.circle\.fill|xmark\.circle\.fill)"|VoiceInkPowerModeEmojiCatalog\.(firstValidEmojiCharacter|isValidEmoji)|emojiManager\.canAddCustomEmoji|if emojiManager\.removeCustomEmoji\(emojiToRemove\)' \
  VoiceInk/PowerMode/EmojiManager.swift \
  VoiceInk/PowerMode/EmojiPickerView.swift

reject_pattern \
  "macOS Power Mode rows avoid shell-only trigger-count pluralization" \
  'websiteCount == 1|appCount == 1|[0-9] (App|Apps|Website|Websites)' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode row context menu avoids shell-only delete confirmation copy" \
  'Delete Power Mode\?|Are you sure you want to delete|This action cannot be undone|addButton\(withTitle: +"(Delete|Cancel)"' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode rows avoid shell-only row detail chip policy" \
  'modelName\.count > 20|prefix\(18\)|selectedPrompt\?\.title \?\? "AI"|Text\("Context Awareness"\)|model != "Default"|language != "Default"|config\.autoSendKey\.displayName|private var iconName|Image\(systemName: iconName\)|chip\.kind == \.prompt|case \.(transcriptionModel|selectedLanguage|aiModel|autoSend|contextAwareness|prompt)' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode sidebar and rows avoid shell-only symbol metadata" \
  '"(bolt\.circle\.fill|plus\.circle\.fill|app\.fill|globe|pencil|trash)"' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode views avoid shell-only panel sidebar popover chrome copy" \
  '"(Power Modes|Automate your workflows with context-aware configurations\.|Reorder|Reorder Power Modes|Close|Default|Disabled|No Power Modes Yet|Create first power mode to automate your VoiceInk workflow based on apps/website you are using|No Power Modes|Add customized power modes for different contexts|Add New Power Mode|Select Power Mode|No Power Modes Available|Edit|Delete)"' \
  VoiceInk/PowerMode/PowerModeView.swift \
  VoiceInk/PowerMode/PowerModeViewComponents.swift \
  VoiceInk/PowerMode/PowerModePopover.swift

reject_pattern \
  "macOS Power Mode settings avoid shell-only presentation copy" \
  'label: "Power Mode"|Text\("Power Mode"\)|infoMessage: "Apply custom settings based on active app or website\."|Text\("Persist Configured Preferences"\)|InfoTip\("When enabled, Power Mode preferences stay active after you stop recording instead of reverting to your original preferences\. They will only change when a different Power Mode activates\."\)|\.alert\("Power Mode Still Active"|Button\("Got it"|Text\("Disable or remove your Power Modes first\."\)' \
  VoiceInk/Views/Settings/SettingsView.swift

reject_pattern \
  "macOS Power Mode popover avoids shell-only symbol metadata" \
  '"(sparkles|checkmark)"' \
  VoiceInk/PowerMode/PowerModePopover.swift

reject_pattern \
  "macOS Power Mode panel avoids shell-only panel action metadata" \
  '"https://tryvoiceink.com/docs/power-mode"|"plus"|"arrow\.up\.arrow\.down"|"square\.grid\.2x2\.fill"|"xmark"|"line\.3\.horizontal"' \
  VoiceInk/PowerMode/PowerModeView.swift

reject_pattern \
  "macOS Power Mode rows avoid shell-only selected-prompt title lookup" \
  'allPrompts\.first|selectedPromptUUID' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode edit form avoids shell-only delete confirmation copy" \
  'Delete Power Mode\?|Are you sure you want to delete|This action cannot be undone' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode edit form avoids shell-only validation alert copy" \
  'Cannot Save Power Mode|Please fix the validation errors before saving|firstError\.localizedDescription|Button\("OK"' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode config record lives in VoiceInkCore" \
  'struct PowerModeConfig' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode config exposes parsed prompt and provider application state" \
  'selectedPrompt\.flatMap\(UUID\.init\)|selectedAIProvider\.flatMap\(VoiceInkAIEnhancementProviderKind\.init\(storedValue:\)\)' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode config resolves selected prompt titles" \
  'selectedPromptTitle\(in prompts: \[VoiceInkCustomPrompt\]\)' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode transcription metadata selection lives in VoiceInkCore" \
  'VoiceInkPowerModeTranscriptionMetadata|active\(from config: PowerModeConfig\?\)|config\.isEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode enhancement selection default repair lives in VoiceInkCore" \
  'VoiceInkPowerModeEnhancementSelection|fillingMissingProviderAndModel|selectingPromptAfterEnabling|selectingPromptForEnhancementState' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "core checks execute Power Mode enhancement prompt-state repair test" \
  'PowerModePolicyTests\.testPowerModeEnhancementSelectionRepairsPromptOnlyWhenEnhancementIsEnabled' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS Power Mode view avoids shell-owned enhancement prompt fallback condition" \
  'isAIEnhancementEnabled && selectedPromptId == nil|selectingPromptAfterEnabling' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode provider/model picker selection repair lives in VoiceInkCore" \
  'resolvedProviderForPicker|selectedProviderForModelOptions|selectingProvider|selectingDefaultModelForSelectedProvider|selectedModelForPicker|selectingModel' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode form mode lives in VoiceInkCore" \
  'VoiceInkPowerModeConfigurationMode' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode configuration persistence lives in VoiceInkCore" \
  'VoiceInkPowerModeConfigurationPreference|activePowerModeConfigurationId' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared Power Mode top-level preference keys live in VoiceInkCore" \
  'powerModeUIFlag = "powerModeUIFlag"|powerModePersistConfig = "powerModePersistConfig"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared Power Mode top-level preference policy lives in VoiceInkCore" \
  'VoiceInkPowerModePreference|initializeUIFlagIfNeeded|canUseShortcuts|shouldPersistConfiguredPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS defaults register shared Power Mode top-level defaults" \
  'VoiceInkPowerModePreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS startup initializes Power Mode UI flag through shared preference policy" \
  'VoiceInkPowerModePreference\.initializeUIFlagIfNeeded' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS navigation observes shared Power Mode UI flag key" \
  'VoiceInkUserDefaultsKey\.powerModeUIFlag' \
  VoiceInk/Views/ContentView.swift

require_pattern \
  "macOS settings observes shared Power Mode preference keys" \
  'VoiceInkUserDefaultsKey\.(powerModeUIFlag|powerModePersistConfig)' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS mini recorder consumes shared Power Mode shortcut eligibility" \
  'VoiceInkPowerModePreference\.canUseShortcuts' \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift

require_pattern \
  "macOS Power Mode shortcut manager consumes shared UI visibility preference" \
  'VoiceInkPowerModePreference\.isUIEnabled' \
  VoiceInk/Shortcuts/PowerModeShortcutManager.swift

require_pattern \
  "macOS recording finish consumes shared Power Mode persist preference" \
  'VoiceInkPowerModePreference\.shouldPersistConfiguredPreferences' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS diagnostics use shared Power Mode top-level preferences" \
  'VoiceInkPowerModePreference\.(isUIEnabled|shouldPersistConfiguredPreferences)' \
  VoiceInk/Services/SystemInfoService.swift

reject_pattern \
  "macOS Power Mode shells avoid raw top-level preference keys" \
  '"(powerModeUIFlag|powerModePersistConfig)"' \
  VoiceInk/AppDefaults.swift \
  VoiceInk/VoiceInk.swift \
  VoiceInk/Views/ContentView.swift \
  VoiceInk/Views/Settings/SettingsView.swift \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift \
  VoiceInk/Shortcuts/PowerModeShortcutManager.swift \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "migration checklist tracks shared Power Mode top-level preference gate" \
  'macOS top-level Power Mode visibility, persist-after-recording preference, first-run visibility repair, enabled-configuration presence, and shortcut eligibility route through `VoiceInkPowerModePreference`/shared `PowerModeConfig` array helpers' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS Power Mode manager avoids shell-only config persistence mechanics" \
  'VoiceInkUserDefaultsKey\.powerModeConfigurations|activeConfigurationId|JSON(Encoder|Decoder)|data\(forKey:' \
  VoiceInk/PowerMode/PowerModeConfig.swift

require_pattern \
  "macOS Power Mode manager consumes shared configuration persistence" \
  'VoiceInkPowerModeConfigurationPreference\.(loadConfigurations|saveConfigurations|loadActiveConfigurationId|saveActiveConfigurationId)' \
  VoiceInk/PowerMode/PowerModeConfig.swift

require_pattern \
  "shared Power Mode config list policy lives in VoiceInkCore" \
  'enabledPowerModeConfigurationIds|appendPowerModeConfigurationIfMissing|savePowerModeConfiguration|movePowerModeConfigurations|setPowerModeDefaultConfiguration|addPowerModeAppConfig' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "core checks execute Power Mode configuration save mutation test" \
  'PowerModePolicyTests\.testPowerModeConfigurationListSaveAppliesDefaultAndMutationMode' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "macOS Power Mode manager consumes shared configuration save mutation policy" \
  'savePowerModeConfiguration\(config, mode: mode\)' \
  VoiceInk/PowerMode/PowerModeConfig.swift

reject_pattern \
  "macOS Power Mode form avoids shell-owned save mutation ordering" \
  'if +isDefault +\{|powerModeManager\.(setAsDefault|addConfiguration|updateConfiguration)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode backup shortcut import record lives in VoiceInkCore" \
  'VoiceInkPowerModeShortcutImport' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode backup shortcut import policy lives in VoiceInkCore" \
  'powerModeShortcutImports' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode backup export plan record lives in VoiceInkCore" \
  'VoiceInkPowerModeBackupExportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode backup export plan policy lives in VoiceInkCore" \
  'powerModeBackupExportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode backup shortcut export adapter lives in VoiceInkCore" \
  'powerModeShortcutBackups' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS backup export uses shared Power Mode export plan" \
  'VoiceInkPowerModePolicy\.powerModeBackupExportPlan' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup export uses shared Power Mode shortcut backup adapter" \
  'VoiceInkPowerModePolicy\.powerModeShortcutBackups' \
  VoiceInk/Services/ImportExportService.swift

reject_pattern \
  "macOS backup export avoids shell-owned Power Mode shortcut backup planning" \
  'let +powerConfigs = powerModeManager\.configurations|Dictionary\(uniqueKeysWithValues: powerConfigs\.compactMap|return +\(config\.id\.uuidString|powerModeShortcuts\.isEmpty \? nil : powerModeShortcuts' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "shared Power Mode backup import plan record lives in VoiceInkCore" \
  'VoiceInkPowerModeBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode backup import plan policy lives in VoiceInkCore" \
  'powerModeBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS backup importer uses shared Power Mode import plan" \
  'VoiceInkPowerModePolicy\.powerModeBackupImportPlan' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup importer avoids shell-only Power Mode shortcut import filtering" \
  'for +\(idString, +shortcutBackup\) +in +shortcuts|let +importedPowerModeIds|UUID\(uuidString: idString\)|importedPowerModeIds\.contains' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup importer avoids shell-owned Power Mode import sequencing" \
  'for config in powerModeManager\.configurations|powerModeManager\.configurations = backup\.powerModeConfigs|if let customEmojis = backup\.customEmojis|backup\.powerModeConfigs\.count|VoiceInkPowerModePolicy\.powerModeShortcutImports' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "core checks execute Power Mode shortcut import policy tests" \
  'PowerModePolicyTests\.testPowerModeShortcutImportPlanKeepsOnlyImportedConfigurationKeys' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute Power Mode backup export plan tests" \
  'PowerModePolicyTests\.testPowerModeBackupExportPlanPreservesMacOSExportInputs' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute Power Mode shortcut export adapter tests" \
  'PowerModePolicyTests\.testPowerModeShortcutBackupsReturnNilWhenNoShortcutsExist' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute Power Mode backup import sequence policy tests" \
  'PowerModePolicyTests\.testPowerModeBackupImportPlanPreservesMacOSImportSequencingInputs' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute Power Mode backup custom emoji policy tests" \
  'PowerModePolicyTests\.testPowerModeBackupImportPlanTreatsMissingCustomEmojiRecordsAsNoOps' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared Power Mode backup import and export policy" \
  'Power Mode backup import/export plan' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared Power Mode automatic resolution policy lives in VoiceInkCore" \
  'resolvedPowerModeConfiguration' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_patterns \
  "shared Power Mode browser metadata lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/PowerModeBrowser.swift \
  'VoiceInkPowerModeBrowser' \
  'VoiceInkPowerModeBrowserURLDiagnostics' \
  'VoiceInkPowerModeBrowserDetectionDiagnostics' \
  'loggerCategory' \
  'safariURL' \
  'company\.thebrowser\.Browser' \
  'com\.google\.Chrome' \
  'com\.microsoft\.edgemac' \
  'app\.zen-browser\.zen' \
  'ru\.yandex\.desktop\.yandex-browser' \
  'scriptNotFoundMessage' \
  'urlLookupFailedMessage' \
  'executionFailedMessage' \
  'runningStatusMessage'

require_pattern \
  "core checks execute Power Mode browser metadata and diagnostics tests" \
  'PowerModePolicyTests\.testPowerModeBrowserCatalogPreservesMacOSMetadata|PowerModePolicyTests\.testPowerModeBrowserCatalogPreservesCurrentDetectionSet|PowerModePolicyTests\.testPowerModeBrowserURLDiagnosticsPreserveMacOSLogCopy|PowerModePolicyTests\.testPowerModeBrowserDetectionDiagnosticsPreserveMacOSLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_patterns \
  "macOS active-window service consumes shared Power Mode browser catalog and diagnostics" \
  VoiceInk/PowerMode/ActiveWindowService.swift \
  'VoiceInkPowerModeBrowser\.allCases' \
  'VoiceInkPowerModeBrowserDetectionDiagnostics\.loggerCategory' \
  'VoiceInkPowerModeBrowserDetectionDiagnostics\.urlLookupFailedMessage'

reject_pattern \
  "macOS active-window service avoids shell-owned browser detection diagnostic copy" \
  '"browser\.detection"|"❌ Failed to get URL from ' \
  VoiceInk/PowerMode/ActiveWindowService.swift

require_patterns \
  "macOS browser URL service adapts shared Power Mode browser metadata and diagnostics" \
  VoiceInk/PowerMode/BrowserURLService.swift \
  'getCurrentURL\(from browser: VoiceInkPowerModeBrowser\)' \
  'isRunning\(_ browser: VoiceInkPowerModeBrowser\)' \
  'VoiceInkPowerModeBrowserURLDiagnostics\.loggerCategory' \
  'VoiceInkPowerModeBrowserURLDiagnostics\.(scriptNotFoundMessage|attemptingExecutionMessage|browserNotRunningMessage|executingScriptMessage|emptyOutputMessage|scriptErrorMessage|successMessage|outputDecodeFailedMessage|executionFailedMessage|runningStatusMessage)' \
  'browser\.scriptName' \
  'browser\.bundleIdentifier' \
  'browser\.displayName'

reject_pattern \
  "macOS browser URL service avoids shell-owned browser metadata" \
  'enum +BrowserType|case +(safari|arc|chrome|edge|firefox|brave|opera|vivaldi|orion|zen|yandex)|"(safariURL|arcURL|chromeURL|edgeURL|firefoxURL|braveURL|operaURL|vivaldiURL|orionURL|zenURL|yandexURL|com\.apple\.Safari|company\.thebrowser\.Browser|com\.google\.Chrome|com\.microsoft\.edgemac|org\.mozilla\.firefox|com\.brave\.Browser|com\.operasoftware\.Opera|com\.vivaldi\.Vivaldi|com\.kagi\.kagimacOS|app\.zen-browser\.zen|ru\.yandex\.desktop\.yandex-browser|Google Chrome|Microsoft Edge|Zen Browser|Yandex Browser)"' \
  VoiceInk/PowerMode/BrowserURLService.swift \
  VoiceInk/PowerMode/ActiveWindowService.swift

reject_pattern \
  "macOS browser URL service avoids shell-owned diagnostic copy" \
  '"browser\.applescript"|"❌ AppleScript file not found:|"🔍 Attempting to execute AppleScript for |"❌ Browser not running:|"▶️ Executing AppleScript for |"❌ Empty output from AppleScript for |"❌ AppleScript error for |"✅ Successfully retrieved URL from |"❌ Failed to decode output from AppleScript for |"❌ AppleScript execution failed for |running status:' \
  VoiceInk/PowerMode/BrowserURLService.swift

require_pattern \
  "migration checklist tracks shared Power Mode browser metadata and diagnostics" \
  'VoiceInkPowerModeBrowserDetectionDiagnostics|browser URL and detection diagnostic copy' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS Power Mode avoids shell-only config record and policy adapters" \
  'struct +PowerModeConfig|extension +Array +where +Element *== *PowerModeConfig|extension +PowerModeConfig' \
  VoiceInk/PowerMode/PowerModeConfig.swift

reject_pattern \
  "macOS Power Mode manager avoids shell-only config list matching and mutation policy" \
  'configurations\.first *\{|configurations\.contains *\{|configurations\.filter *\{|configurations\.move\(fromOffsets:|for +index +in +configurations\.indices|appConfigs\?\.removeAll|urlConfigs\?\.removeAll|configs\.append' \
  VoiceInk/PowerMode/PowerModeConfig.swift

require_pattern \
  "macOS Power Mode manager consumes shared config list policy" \
  'appendPowerModeConfigurationIfMissing|movePowerModeConfigurations|powerModeConfiguration\(forWebsiteURL:|enabledPowerModeConfigurationIds|containsPowerModeEmoji' \
  VoiceInk/PowerMode/PowerModeConfig.swift

reject_pattern \
  "macOS Power Mode manager avoids shell-only URL app default resolution helpers" \
  'getConfigurationFor(URL|App)|getDefaultConfiguration' \
  VoiceInk/PowerMode/PowerModeConfig.swift

reject_pattern \
  "macOS Power Mode manager avoids shell-only shared policy pass-through helpers" \
  'func +(getConfiguration|hasDefaultConfiguration|cleanURL|getAllAvailableConfigurations|isEmojiInUse)\(|var +(enabledConfigurations|currentActiveConfiguration)\b' \
  VoiceInk/PowerMode/PowerModeConfig.swift

require_pattern \
  "shared Power Mode website form config construction lives in VoiceInkCore" \
  'websiteConfigForFormInput|VoiceInkPowerModeURLConfig\(url: normalizedWebsiteURL\(input\)\)' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode website form append policy lives in VoiceInkCore" \
  'addingWebsiteConfig' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS Power Mode form consumes shared website form append policy" \
  'VoiceInkPowerModePolicy\.addingWebsiteConfig' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode form app trigger removal policy lives in VoiceInkCore" \
  'removingAppConfig' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode form website trigger removal policy lives in VoiceInkCore" \
  'removingWebsiteConfig' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS Power Mode form consumes shared app trigger removal policy" \
  'VoiceInkPowerModePolicy\.removingAppConfig' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS Power Mode form consumes shared website trigger removal policy" \
  'VoiceInkPowerModePolicy\.removingWebsiteConfig' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "core checks execute Power Mode website append policy test" \
  'PowerModePolicyTests\.testAddingWebsiteConfigAppendsSharedFormConfigAndPreservesNilInput' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute Power Mode trigger removal policy test" \
  'PowerModePolicyTests\.testRemovingPowerModeFormTriggerConfigsUsesSharedIdPolicy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared Power Mode configuration-name saveability lives in VoiceInkCore" \
  'canSaveConfigurationName' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS Power Mode form consumes shared configuration-name saveability" \
  'VoiceInkPowerModePolicy\.canSaveConfigurationName' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode form draft construction lives in VoiceInkCore" \
  'struct VoiceInkPowerModeConfigurationDraft|from draft: VoiceInkPowerModeConfigurationDraft' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS Power Mode form consumes shared draft construction" \
  'VoiceInkPowerModeConfigurationDraft|VoiceInkPowerModePolicy\.configuration\(from: draft, mode: mode\)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "shared Power Mode form state lives in VoiceInkCore" \
  'VoiceInkPowerModeConfigurationFormState|formState\(existingConfigurations:' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode form state owns add defaults" \
  'addDefaultName|addDefaultEmoji' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS Power Mode form seeds add defaults through shared form state" \
  'VoiceInkPowerModeConfigurationFormState\.(addDefaultName|addDefaultEmoji)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS Power Mode form consumes shared form state" \
  'mode\.formState\(existingConfigurations: powerModeManager\.configurations\)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only website config construction" \
  'normalizedWebsiteURL\(newWebsiteURL\)|VoiceInkPowerModeURLConfig\(url:|websiteConfigs\.append' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only trigger removal" \
  '(selectedAppConfigs|websiteConfigs)\.removeAll' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only configuration-name saveability" \
  '!configName\.isEmpty' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids local configuration-name saveability wrapper" \
  'private var +canSave\b' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only stored config construction" \
  'PowerModeConfig\(|selectedPromptId\?\.uuidString|var updatedConfig = config|selectedAppConfigs\.isEmpty \? nil : selectedAppConfigs|websiteConfigs\.isEmpty \? nil : websiteConfigs' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only add/edit form-state policy" \
  'let +newId += +UUID\(|let +latestConfig +=|_configName += +State\(initialValue: +""\)|_selectedEmoji += +State\(initialValue: +"✏️"\)|_selectedAppConfigs += +State\(initialValue: +latestConfig\.appConfigs +\?\? +\[\]\)|_isTranscriptFormattingExpanded += +State\(initialValue: +latestConfig' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only enhancement selection default repair" \
  'selectedAIProvider == nil|selectedAIModel == nil|selectedAIModel\?\.isEmpty == true|VoiceInkCustomPromptPolicy\.selectedPromptIdAfterEnablingEnhancement' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only provider/model picker selection repair" \
  'VoiceInkAIEnhancementProviderKind\(storedValue:|selectedAIProvider = newValue\.rawValue|selectedAIModel = nil|selectedAIModel = provider\.defaultModel|selectedAIProvider \?\? aiService\.selectedProvider\.rawValue|if let model = selectedAIModel, !model\.isEmpty' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode views avoid shell-only selected-prompt UUID parsing" \
  'UUID\(uuidString:' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

require_pattern \
  "shared Power Mode shortcut eligibility policy lives in VoiceInkCore" \
  'powerModeShortcutEntries|powerModeShortcutConfigurationId' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode enabled-state predicate lives in VoiceInkCore" \
  'hasEnabledPowerModeConfigurations' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS Power Mode shortcuts consume shared shortcut eligibility policy" \
  'powerModeShortcutEntries|powerModeShortcutConfigurationId' \
  VoiceInk/Shortcuts/PowerModeShortcutManager.swift

require_pattern \
  "core checks execute Power Mode shortcut eligibility tests" \
  'PowerModePolicyTests\.testPowerModeShortcutEntriesIncludeOnlyEnabledConfigurationsWithShortcuts|PowerModePolicyTests\.testPowerModeShortcutConfigurationIdRequiresEnabledConfigAndStoredShortcut' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS Power Mode shortcut manager avoids shell-owned enabled shortcut filtering" \
  'enabledPowerModeConfigurations\.reduce|config\.isEnabled' \
  VoiceInk/Shortcuts/PowerModeShortcutManager.swift

reject_pattern \
  "macOS Power Mode startup avoids shell-only enabled config checks" \
  'configurations\.contains *\{ *\$0\.isEnabled *\}' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS Power Mode startup calls shared enabled-state policy directly" \
  'configurations\.hasEnabledPowerModeConfigurations' \
  VoiceInk/VoiceInk.swift

reject_pattern \
  "macOS Power Mode visibility avoids shell-owned enabled-state predicates" \
  'enabledPowerModeConfigurations\.isEmpty|allSatisfy *\{ *!\$0\.isEnabled' \
  VoiceInk/VoiceInk.swift \
  VoiceInk/Shortcuts/MiniRecorderShortcutManager.swift \
  VoiceInk/Views/Settings/SettingsView.swift \
  VoiceInk/Views/Recorder/RecorderComponents.swift \
  VoiceInk/PowerMode/PowerModePopover.swift

reject_pattern \
  "macOS active-window adapter avoids shell-only Power Mode resolution policy" \
  'getConfigurationForURL|getConfigurationForApp|getDefaultConfiguration|configToApply' \
  VoiceInk/PowerMode/ActiveWindowService.swift

require_pattern \
  "macOS active-window adapter consumes shared Power Mode resolution policy" \
  'resolvedPowerModeConfiguration' \
  VoiceInk/PowerMode/ActiveWindowService.swift

reject_pattern \
  "macOS Power Mode popover avoids shell-only enabled config filtering" \
  'configurations\.filter *\{ *\$0\.isEnabled *\}' \
  VoiceInk/PowerMode/PowerModePopover.swift

require_pattern \
  "macOS Power Mode popover consumes shared enabled config list policy" \
  'enabledPowerModeConfigurations' \
  VoiceInk/PowerMode/PowerModePopover.swift

require_pattern \
  "shared Power Mode trigger config records live in VoiceInkCore" \
  'struct VoiceInkPowerMode(App|URL)Config' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

reject_pattern \
  "macOS Power Mode avoids shell-only trigger config records" \
  '\b(App|URL)Config\b' \
  VoiceInk/PowerMode/PowerModeConfig.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift \
  VoiceInk/PowerMode/PowerModeViewComponents.swift \
  VoiceInk/PowerMode/AppPicker.swift

require_pattern \
  "macOS Power Mode config consumes shared trigger config records" \
  'VoiceInkPowerMode(App|URL)Config' \
  VoiceInk/PowerMode/PowerModeConfig.swift

require_pattern \
  "macOS Power Mode form consumes shared trigger config records" \
  'VoiceInkPowerMode(App|URL)Config' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS Power Mode panel consumes shared form mode" \
  'VoiceInkPowerModeConfigurationMode' \
  VoiceInk/PowerMode/PowerModeView.swift

require_pattern \
  "macOS Power Mode add button consumes shared form title" \
  'VoiceInkPowerModeConfigurationMode\.add\.title' \
  VoiceInk/PowerMode/PowerModeView.swift

require_pattern \
  "macOS Power Mode config form consumes shared save mode" \
  'VoiceInkPowerModeConfigurationMode|mode\.saveMode' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode avoids shell-only form mode and save-mode adapters" \
  'enum +ConfigurationMode|powerModeSaveMode' \
  VoiceInk/PowerMode/PowerModeView.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode add button avoids shell-only form title" \
  '"Add Power Mode"' \
  VoiceInk/PowerMode/PowerModeView.swift

require_pattern \
  "macOS Power Mode cards consume shared trigger config records" \
  'VoiceInkPowerModeAppConfig' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

require_pattern \
  "macOS app picker consumes shared trigger config records" \
  'VoiceInkPowerModeAppConfig' \
  VoiceInk/PowerMode/AppPicker.swift

require_pattern \
  "shared auto-send key state lives in VoiceInkCore" \
  'enum VoiceInkAutoSendKey' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared auto-send post-paste delay policy lives in VoiceInkCore" \
  'enum VoiceInkAutoSendPolicy|delayAfterPasteNanoseconds' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "macOS transcription pipeline consumes shared auto-send delay policy" \
  'VoiceInkAutoSendPolicy\.delayAfterPasteNanoseconds' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "core checks execute shared auto-send delay policy tests" \
  'PowerModePolicyTests\.testAutoSendPolicySharesDelayAfterPasteEligibility' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS transcription pipeline avoids shell-only auto-send delay policy" \
  'autoSendAfterPasteDelayNanoseconds|120_000_000|autoSendKey\.isEnabled' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

reject_pattern \
  "macOS Power Mode avoids shell-only auto-send key state" \
  'enum +AutoSendKey|var +autoSendKey: +AutoSendKey|performAutoSend\(_ key: +AutoSendKey\)|ForEach\(AutoSendKey\.allCases' \
  VoiceInk/PowerMode/PowerModeConfig.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift \
  VoiceInk/Paste/CursorPaster.swift

require_pattern \
  "shared Power Mode config owns shared auto-send key state" \
  'VoiceInkAutoSendKey' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode session snapshot records live in VoiceInkCore" \
  'struct VoiceInkPowerMode(ApplicationState|Session)' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode begin-session lifecycle plan lives in VoiceInkCore" \
  'VoiceInkPowerModeSessionBeginPlan|shouldInstallSettingsObserver' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode snapshot-update lifecycle plan lives in VoiceInkCore" \
  'VoiceInkPowerModeSessionSnapshotPlan|shouldCaptureCurrentState' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode session snapshot construction consumes cleanup settings" \
  'cleanupSettings: VoiceInkTranscriptionCleanupSettings|selectedPromptId: selectedPromptId\?\.uuidString' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode session restore presentation exposes parsed prompt and cleanup state" \
  'selectedPromptUUID|cleanupRestore|struct VoiceInkPowerModeCleanupRestore' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode preference application plan lives in VoiceInkCore" \
  'VoiceInkPowerModePreferenceApplication|VoiceInkPowerModePromptSelectionApplication|powerModePreference(Application|Restore)' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode session application plan lives in VoiceInkCore" \
  'VoiceInkPowerModeSessionApplicationPlan|VoiceInkPowerModeSessionApplicationFacts|shouldPostConfigurationApplied' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode session diagnostics live in VoiceInkCore" \
  'VoiceInkPowerModeSessionDiagnostics|notConfiguredMessage|localModelLoadFailedMessage|recoveringAbandonedSessionMessage|saveFailedMessage|loadFailedMessage' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "core checks execute Power Mode session diagnostics tests" \
  'PowerModePolicyTests\.testPowerModeSessionDiagnosticsPreserveMacOSConsoleCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "shared Power Mode active-session persistence lives in VoiceInkCore" \
  'VoiceInkPowerModeSessionPreference|activePowerModeSession' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

reject_pattern \
  "macOS Power Mode avoids shell-only session snapshot records" \
  'struct +ApplicationState|struct +PowerModeSession' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-only session persistence mechanics" \
  'powerModeActiveSession|JSON(Encoder|Decoder)|UserDefaults\.standard|data\(forKey:|removeObject\(forKey:' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-only session snapshot construction" \
  'selectedPromptId: enhancementService\.selectedPromptId\?\.uuidString|isTextFormattingEnabled: cleanupSettings\.isTextFormattingEnabled|punctuationCleanupMode: cleanupSettings\.punctuationMode|removePunctuation: cleanupSettings\.removesAllPunctuation|lowercaseTranscription: cleanupSettings\.lowercaseTranscription' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-only session restore parsing" \
  'state\.selectedPromptId\.flatMap\(UUID\.init\)|state\.punctuationCleanupMode|state\.removePunctuation|state\.isTextFormattingEnabled|state\.lowercaseTranscription' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-only lifecycle branching" \
  'loadSession\(\) == nil|guard +!isApplyingPowerModeConfig|var +session = loadSession\(\)|session\.originalState = currentApplicationState|VoiceInkPowerModeSession\(' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-only provider raw-value parsing" \
  'VoiceInkAIEnhancementProviderKind\(storedValue:' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-only preference application policy" \
  'if +config\.isAIEnhancementEnabled|config\.selectedPromptUUID|config\.selectedAIProviderKind|state\.selectedPromptUUID|state\.selectedAIProviderKind|state\.cleanupRestore|VoiceInkTranscriptionCleanupPreferenceStorage\.saveTextFormattingEnabled\(config\.|PunctuationCleanupMode\.setCurrent\(config\.|VoiceInkTranscriptionCleanupPreferenceStorage\.saveLowercaseTranscription\(config\.|let +cleanupRestore += +state\.cleanupRestore' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-only application sequencing" \
  'applyPreferenceApplication\(config\.powerModePreferenceApplication\)|applyPreferenceApplication\(state\.powerModePreferenceRestore\)|modelResourcePlan\(|languageApplicationPlan\(' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager consumes shared session snapshot records" \
  'VoiceInkPowerMode(ApplicationState|Session)' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager consumes shared begin-session plan" \
  'VoiceInkPowerModeSessionBeginPlan\.plan|beginPlan\.sessionToSave' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager consumes shared snapshot-update plan" \
  'VoiceInkPowerModeSessionSnapshotPlan\.plan|snapshotPlan\.sessionToSave' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager consumes shared application plan" \
  'VoiceInkPowerModeSessionApplicationPlan\.(applying|restoring)|applySessionApplicationPlan' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager applies configs through shared preference application plan" \
  'plan\.preferenceApplication' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager restores state through shared preference application plan" \
  'VoiceInkPowerModeSessionApplicationPlan\.restoring' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager consumes shared session persistence" \
  'VoiceInkPowerModeSessionPreference\.(saveActiveSession|loadActiveSession|clear)' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager consumes shared session diagnostics" \
  'VoiceInkPowerModeSessionDiagnostics\.(notConfiguredMessage|localModelLoadFailedMessage|recoveringAbandonedSessionMessage|saveFailedMessage|loadFailedMessage)' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "macOS Power Mode session manager uses shared local Whisper model lookup" \
  'VoiceInkWhisperModelFiles\.downloadedLocalModelFile' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-owned local Whisper model lookup" \
  'availableModels\.first\(where:' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shell-owned session diagnostic copy" \
  '"(SessionManager not configured\.|Power Mode: Failed to load local model|Recovering abandoned Power Mode session\.|Error saving Power Mode session:|Error loading Power Mode session:)' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

reject_pattern \
  "macOS Power Mode session manager avoids shallow session clear wrapper" \
  'private +func +clearSession\(' \
  VoiceInk/PowerMode/PowerModeSessionManager.swift

require_pattern \
  "migration checklist tracks shared Power Mode session diagnostics" \
  'VoiceInkPowerModeSessionDiagnostics|session diagnostic copy' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS Power Mode form consumes shared auto-send key state" \
  'VoiceInkAutoSendKey' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

require_pattern \
  "macOS paste adapter consumes shared auto-send key state" \
  'VoiceInkAutoSendKey' \
  VoiceInk/Paste/CursorPaster.swift

require_pattern \
  "macOS diagnostics use shared macOS selected-language fallback" \
  'VoiceInkTranscriptionLanguagePreference\.selectedMacOSLanguage\(\)' \
  VoiceInk/Services/SystemInfoService.swift

reject_pattern \
  "macOS diagnostics avoid shallow selected-language wrapper" \
  'private +func +getCurrentLanguage\(' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS diagnostics use shared AI enhancement status presentation" \
  'VoiceInkAIEnhancementPreference\.statusDiagnosticDescription\(\)' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS diagnostics use shared AI provider presentation" \
  'VoiceInkAIEnhancementProviderPreference\.selectedProviderDiagnosticDescription\(\)' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS diagnostics use shared AI model presentation" \
  'VoiceInkAIEnhancementProviderPreference\.selectedModelDiagnosticDescription\(\)' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS AI service consumes shared selected AI model map" \
  'selectedModels = VoiceInkAIEnhancementProviderPreference\.selectedModels\(from: userDefaults\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI service avoids shell-only selected model loading loop" \
  'loadSavedModelSelections|for provider in VoiceInkAIEnhancementProviderKind\.allCases' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS diagnostics avoid shell-only AI preference presentation" \
  'getAI(EnhancementStatus|Provider|Model)|VoiceInkUserDefaultsKey\.isAIEnhancementEnabled|selectedProviderRawValue\(\)|selectedModel\(for:' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS diagnostics use shared rolling-buffer per-model preference" \
  'VoiceInkRollingBufferPreloadSettings\.perModelPreloadEnabled\(forModelName: currentModelName\)' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "shared rolling-buffer VAD model settings live in VoiceInkCore" \
  'VoiceInkRollingBufferPreloadSettingsPresentation|VoiceInkRollingBufferVADModel|VoiceInkRollingBufferVADSettings|modelKey = "RollingBufferVADModel"|sileroModelName|saveImportedModel' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

reject_file VoiceInkCore/Sources/VoiceInkCore/RollingAudioBuffer.swift

require_pattern \
  "shared rolling-buffer lead-in buffer lives with preload policy" \
  'VoiceInkRollingAudioBuffer' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

require_patterns \
  "shared rolling-buffer partial transcript request lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift \
  'VoiceInkRollingBufferPreloadPartialTranscriptRequest' \
  'notificationName = Notification\.Name\("rollingBufferPreloadPartialTranscript"\)' \
  'textUserInfoKey = "text"' \
  'userInfo\(text: String\)' \
  'text\(from notification: Notification\)'

require_pattern \
  "shared rolling-buffer backup preferences live in VoiceInkCore" \
  'VoiceInkRollingBufferBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

require_pattern \
  "shared rolling-buffer backup import plan lives in VoiceInkCore" \
  'VoiceInkRollingBufferBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

require_pattern \
  "shared rolling-buffer backup export policy lives in VoiceInkCore" \
  'static func backupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

require_patterns \
  "shared transcription service route classifies cloud and local providers" \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionStreamingPreference.swift \
  'isCloudTranscriptionProvider' \
  'isLocalTranscriptionProvider'

require_pattern \
  "macOS rolling preload snapshot uses shared service-route provider classification" \
  'provider\.transcriptionServiceRoute\.isCloudTranscriptionProvider' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadSettings.swift

require_patterns \
  "shared rolling-buffer buffered snapshot strategy lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift \
  'supportsRecordedFileTranscription' \
  'VoiceInkRollingBufferBufferedSnapshotTranscriptionStrategy' \
  'VoiceInkRollingBufferBufferedSnapshotTranscriptionPolicy'

require_pattern \
  "macOS rolling preload snapshot adapts recorded-file support into shared facts" \
  'supportsRecordedFileTranscription: supportsRecordedFileTranscription' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadSettings.swift

require_pattern \
  "macOS rolling-buffer quick release uses shared buffered snapshot strategy" \
  'VoiceInkRollingBufferBufferedSnapshotTranscriptionPolicy\.strategy\(' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS rolling-buffer shell avoids local buffered snapshot strategy policy" \
  'enum +RollingBufferBufferedSnapshotTranscription(Strategy|Policy)' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadSettings.swift

require_pattern \
  "core checks execute service-route provider classification test" \
  'TranscriptionStreamingPreferenceTests\.testServiceRouteClassifiesCloudAndLocalProviders' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute buffered snapshot strategy test" \
  'RollingBufferPreloadPolicyTests\.testBufferedSnapshotTranscriptionStrategyUsesRecordedFileCapability' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_patterns \
  "shared rolling-buffer quick-release diagnostics presentation lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift \
  'VoiceInkRollingBufferQuickReleaseClaimStrategy' \
  'VoiceInkRollingBufferQuickReleaseTimingStage' \
  'VoiceInkRollingBufferQuickReleaseClaimSnapshot' \
  'displaySummary' \
  'exportSummary' \
  'recordTiming'

require_pattern \
  "macOS rolling-buffer runtime diagnostics adapts shared quick-release claim snapshot" \
  'VoiceInkRollingBufferQuickReleaseClaimSnapshot|VoiceInkRollingBufferQuickReleaseClaimStrategy|VoiceInkRollingBufferQuickReleaseTimingStage' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadSettings.swift

reject_pattern \
  "macOS rolling-buffer shell avoids local quick-release claim presentation policy" \
  'enum +RollingBufferQuickRelease(ClaimStrategy|TimingStage)|struct +RollingBufferQuickReleaseClaimSnapshot|var +(displaySummary|exportSummary)|func +recordTiming\(stage: RollingBufferQuickReleaseTimingStage' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadSettings.swift

require_pattern \
  "core checks execute quick-release claim presentation tests" \
  'RollingBufferPreloadPolicyTests\.testQuickReleaseClaimStrategyPreservesDiagnosticLabels|RollingBufferPreloadPolicyTests\.testQuickReleaseClaimSnapshotFormatsDisplayAndExportSummaries' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS rolling preload avoids shell-only provider classification list" \
  'case \.groq, \.elevenLabs, \.deepgram|var isLocalTranscriptionProvider: Bool' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadSettings.swift

require_pattern \
  "shared rolling-buffer backup import policy lives in VoiceInkCore" \
  'static func backupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

require_pattern \
  "macOS defaults register shared rolling-buffer VAD model default" \
  'VoiceInkRollingBufferVADSettings\.(modelKey|sileroModelName)' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS rolling-buffer settings use shared VAD model catalog" \
  'VoiceInkRollingBufferPreloadSettings\.macOSSettingsPresentation|presentation\.(modePickerTitle|modePickerHelp|durationLabel|durationUnitLabel|preRunFinalizationTitle|preRunFinalizationHelp|vadModelPickerTitle|vadModelPickerHelp|autoDisableCloudModelsTitle|autoDisableCloudModelsHelp|autoDisableLowBatteryLocalModelsTitle|autoDisableLowBatteryLocalModelsHelp|batteryCutoffLabel)|VoiceInkRollingBufferVADSettings\.(modelKey|defaultModel)|VoiceInkRollingBufferVADModel\.allCases' \
  VoiceInk/Views/Settings/RollingBufferPreloadSettingsControls.swift

require_pattern \
  "shared rolling-buffer duration lower bound lives in VoiceInkCore" \
  'minimumBufferDurationSeconds = 0\.25' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

require_pattern \
  "shared rolling-buffer duration upper bound lives in VoiceInkCore" \
  'maximumBufferDurationSeconds = 30\.0' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

require_pattern \
  "shared rolling-buffer duration normalization lives in VoiceInkCore" \
  'normalizedBufferDurationSeconds' \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift

require_patterns \
  "shared rolling-buffer coordinator timing defaults live in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/RollingBufferPreloadPolicy.swift \
  'defaultStartingPreloadClaimWaitNanoseconds' \
  'defaultUnclaimedPreloadSilenceSeconds' \
  'defaultUnclaimedPreloadGraceSeconds' \
  'defaultPlanRefreshInterval'

require_patterns \
  "macOS rolling preload coordinator consumes shared timing defaults" \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadCoordinator.swift \
  'VoiceInkRollingBufferPreloadSettings\.defaultStartingPreloadClaimWaitNanoseconds' \
  'VoiceInkRollingBufferPreloadSettings\.defaultUnclaimedPreloadSilenceSeconds' \
  'VoiceInkRollingBufferPreloadSettings\.defaultUnclaimedPreloadGraceSeconds' \
  'VoiceInkRollingBufferPreloadSettings\.defaultPlanRefreshInterval'

reject_pattern \
  "macOS rolling preload coordinator avoids shell-owned timing defaults" \
  'static let startingPreloadClaimWaitNanoseconds|static let unclaimedPreload(Silence|Grace)Seconds|private let planRefreshInterval|Self\.(startingPreloadClaimWaitNanoseconds|unclaimedPreloadSilenceSeconds|unclaimedPreloadGraceSeconds)' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadCoordinator.swift

require_pattern \
  "macOS rolling-buffer settings use shared duration lower bound" \
  'VoiceInkRollingBufferPreloadSettings\.minimumBufferDurationSeconds' \
  VoiceInk/Views/Settings/RollingBufferPreloadSettingsControls.swift

require_pattern \
  "macOS rolling-buffer settings use shared duration upper bound" \
  'VoiceInkRollingBufferPreloadSettings\.maximumBufferDurationSeconds' \
  VoiceInk/Views/Settings/RollingBufferPreloadSettingsControls.swift

require_pattern \
  "macOS rolling-buffer settings use shared duration normalization" \
  'VoiceInkRollingBufferPreloadSettings\.normalizedBufferDurationSeconds' \
  VoiceInk/Views/Settings/RollingBufferPreloadSettingsControls.swift

require_pattern \
  "macOS settings uses shared rolling-buffer section title" \
  'VoiceInkRollingBufferPreloadSettings\.macOSSettingsPresentation|rollingBufferPresentation\.sectionTitle' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS rolling VAD detector uses shared selected-model policy" \
  'VoiceInkRollingBufferVADSettings\.usesSilero\(\)' \
  VoiceInk/Transcription/RollingPreload/SileroSpeechActivityDetector.swift

require_pattern \
  "macOS app notifications use shared rolling-buffer partial transcript request name" \
  'rollingBufferPreloadPartialTranscript = VoiceInkRollingBufferPreloadPartialTranscriptRequest\.notificationName' \
  VoiceInk/Notifications/AppNotifications.swift

require_pattern \
  "macOS rolling preload coordinator posts shared partial transcript request payload" \
  'VoiceInkRollingBufferPreloadPartialTranscriptRequest\.userInfo\(text: partial\)' \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadCoordinator.swift

require_pattern \
  "macOS engine reads shared rolling-buffer partial transcript request payload" \
  'VoiceInkRollingBufferPreloadPartialTranscriptRequest\.text\(from: notification\)' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS diagnostics avoid shell-only rolling-buffer per-model default lookup" \
  'perModelPreloadEnabledKey\(forModelName: currentModelName\)|object\(forKey: key\) as\? Bool \?\? true' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "shared general settings core import uses shared rolling-buffer import policy" \
  'VoiceInkRollingBufferPreloadSettings\.saveImportedSettings\(' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import reads shared rolling-buffer plan" \
  'importPlans\.rollingBuffer' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "shared general settings core import uses shared rolling-buffer VAD model import policy" \
  'VoiceInkRollingBufferVADSettings\.saveImportedModel' \
  VoiceInkCore/Sources/VoiceInkCore/GeneralSettingsBackupPolicy.swift

require_pattern \
  "macOS general backup adapts rolling-buffer values to shared backup preferences" \
  'rollingBufferBackupPreferences' \
  VoiceInk/Services/BackupTypes.swift

reject_pattern \
  "macOS backup import avoids shell-only rolling-buffer preload storage" \
  'VoiceInkRollingBufferPreloadSettings\.(modeKey|autoDisableCloudModelsKey|autoDisableLowBatteryLocalModelsKey|lowBatteryThresholdPercentKey|bufferDurationSecondsKey|preRunFinalizationKey|perModelPreloadEnabledKey)|min\(max\(threshold|for \(modelName, enabled\) in perModelSettings' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import delegates rolling-buffer preference writes to shared policy" \
  'VoiceInkRollingBufferPreloadSettings\.saveImportedSettings|VoiceInkRollingBufferVADSettings\.saveImportedModel' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import avoids shell-owned rolling-buffer backup field planning" \
  'general\.(rollingBufferPreloadModeRawValue|rollingBufferPreloadAutoDisableCloudModels|rollingBufferPreloadAutoDisableLowBatteryLocalModels|rollingBufferPreloadLowBatteryThresholdPercent|rollingBufferDurationSeconds|rollingBufferPreloadFinalization|rollingBufferPreloadEnabledByModel|rollingBufferVADModel)' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import avoids shell-only rolling-buffer VAD model policy" \
  '\bRollingBufferVADSettings\b|vadModel ==|UserDefaults\.standard\.set\(vadModel' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "macOS backup export uses shared rolling-buffer backup preferences" \
  'VoiceInkRollingBufferPreloadSettings\.backupPreferences' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup export uses shared rolling-buffer per-model export policy" \
  'VoiceInkRollingBufferPreloadSettings\.exportedPerModelPreloadEnabled\(\)' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup export uses shared rolling-buffer VAD selected model" \
  'VoiceInkRollingBufferVADSettings\.selectedModel\(\)' \
  VoiceInk/Services/ImportExportService.swift

reject_pattern \
  "macOS backup export avoids shell-only rolling-buffer per-model key scan" \
  'perModelEnabledKeyPrefix|dictionaryRepresentation\(\)|exportPerModelRollingBufferPreloadSettings|dropFirst\(prefix\.count\)' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "core checks execute rolling-buffer backup export policy tests" \
  'RollingBufferPreloadPolicyTests\.testBackupPreferencesPreserveMacOSExportShape' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute rolling-buffer duration normalization tests" \
  'RollingBufferPreloadPolicyTests\.testSettingsNormalizeDurationAndBatteryThresholdRanges' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute rolling-buffer settings default tests" \
  'RollingBufferPreloadPolicyTests\.testSettingsPreserveExistingStorageKeysAndDefaults' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute rolling-buffer partial transcript request tests" \
  'RollingBufferPreloadPolicyTests\.testPartialTranscriptRequestPreservesNotificationContract' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute rolling-buffer backup import policy tests" \
  'RollingBufferPreloadPolicyTests\.testBackupImportPlanValidatesAndClampsRawValues|RollingBufferPreloadPolicyTests\.testImportedBackupPlanSavesPreloadAndVADSettings' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS rolling-buffer shell avoids duplicate partial transcript notification contract" \
  'Notification\.Name\("rollingBufferPreloadPartialTranscript"\)|userInfo: \["text"|userInfo\?\["text"\]' \
  VoiceInk/Notifications/AppNotifications.swift \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadCoordinator.swift \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS rolling-buffer shell avoids local VAD model settings policy" \
  'enum +RollingBufferVADSettings|\bRollingBufferVADSettings\b|Text\("Silero"\)|"(Rolling Buffer|Buffer Preload|Runs local VAD on the rolling buffer and pre-runs supported STT models before capture is finalized\.|Rolling Duration|Pre-run Finalization|When available, use the already-running preload session to finalize text instead of starting transcription from the saved WAV\.|Buffer VAD Model|Silero runs locally on CPU and watches rolling-buffer audio for speech before STT preload starts\.|Auto: Disable Cloud Models|When enabled, Auto keeps rolling-buffer preload local and avoids cloud streaming before capture\.|Auto: Disable Local Models on Low Battery|When enabled, Auto stops local pre-run STT while running on battery below the cutoff\.|Battery cutoff:|s)"' \
  VoiceInk/Views/Settings/SettingsView.swift \
  VoiceInk/Transcription/RollingPreload/RollingBufferPreloadSettings.swift \
  VoiceInk/Views/Settings/RollingBufferPreloadSettingsControls.swift \
  VoiceInk/Transcription/RollingPreload/SileroSpeechActivityDetector.swift

reject_pattern \
  "macOS rolling-buffer settings avoid shell-owned duration bounds" \
  'formatter\.(minimum|maximum) = (0\.25|30)|min\(max\(bufferDurationSeconds, 0\.25\), 30\.0\)' \
  VoiceInk/Views/Settings/RollingBufferPreloadSettingsControls.swift

require_pattern \
  "migration checklist tracks shared rolling-buffer settings labels" \
  'macOS rolling-buffer preload settings labels/help, duration bounds/normalization, partial-transcript preview notification contract, VAD model labels, storage key/default, selected-model fallback, Silero predicate, service-route provider classification' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS Native Apple transcription uses shared source-compatible language fallback" \
  'VoiceInkTranscriptionLanguagePreference\.selectedLanguage\(source: \.nativeApple\)' \
  VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift

require_pattern \
  "macOS Native Apple transcription uses shared locale display fallback" \
  'VoiceInkLanguageCatalog\.nativeAppleDisplayName' \
  VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift

reject_pattern \
  "macOS Native Apple transcription avoids shell-only locale display fallback" \
  'private func +languageDisplayName|VoiceInkLanguageCatalog\.nativeApple\[' \
  VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift

reject_pattern \
  "macOS selected-language callers avoid shell-only fallback literals" \
  'selectedLanguage\(fallback: "(en|auto|en-US)"\)|selectedLanguage = "(en|auto)"' \
  VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift \
  VoiceInk/Transcription/Streaming/StreamingTranscriptionService.swift \
  VoiceInk/Transcription/Whisper/WhisperPrompt.swift \
  VoiceInk/Services/SystemInfoService.swift \
  VoiceInk/PowerMode/PowerModeConfig.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS selected-language AppStorage avoids hard-coded English defaults" \
  'selectedLanguage(: String)? = "en"' \
  VoiceInk/Views/AI\ Models/LanguageSelectionView.swift \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  VoiceInk/Views/ModelSettingsView.swift

reject_pattern \
  "macOS model settings avoids shell-only local Whisper prompt copy" \
  '"(Output Format|Only supported for local Whisper models\. Unlike GPT, Voice Models\(whisper\) follows the style of your prompt rather than instructions\. Use examples of your desired output format instead of commands\.|https://cookbook\.openai\.com/examples/whisper_prompting_guide#comparison-with-gpt-prompting|Save|Edit)"' \
  VoiceInk/Views/ModelSettingsView.swift

reject_pattern \
  "macOS and iOS transcriptions use shared performance session defaults" \
  'var performance(AudioDuration|TranscriptionDuration|EnhancementDuration|EnhancedText)' \
  VoiceInk/Models/Transcription.swift \
  iOS/VoiceInk-ios/Transcription.swift

reject_pattern \
  "macOS metrics avoid shell-only shared performance analysis wrapper" \
  '(^|[^A-Za-z0-9_])PerformanceAnalyzer\.analyze|static func +analyze\(transcriptions:' \
  VoiceInk/Views/Metrics/PerformanceAnalysisView.swift \
  VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift

reject_pattern \
  "performance records avoid shell-only model-name aliases" \
  'performance(Transcription|Enhancement)ModelName' \
  VoiceInk \
  iOS \
  VoiceInkCore/Sources/VoiceInkCore \
  VoiceInkCore/Tests/VoiceInkCoreTests

require_pattern \
  "shared note-list summary presentation lives in VoiceInkCore" \
  'VoiceInkNoteListSummaryPresentation|countText' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

require_pattern \
  "shared note-list summary uses shared metrics accumulator" \
  'VoiceInkDashboardMetricsAccumulator' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

require_pattern \
  "iOS note-list uses shared summary presentation" \
  'VoiceInkNoteListSummaryPresentation\.make|summaryPresentation\.countText' \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS note-list avoids shallow summary presentation wrapper" \
  'private var +noteListSummaryPresentation\b' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "shared note-list chrome presentation lives in VoiceInkCore" \
  'VoiceInkNoteListPresentation|startRecordingButtonTitle|settingsSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

require_pattern \
  "shared dashboard promotion presentation lives in VoiceInkCore" \
  'VoiceInkDashboardPromotionPresentation|VoiceInkLicenseState|VoiceInkDashboardPromotionCardPresentation|affiliateDismissedKey = "VoiceInkAffiliatePromotionDismissed"|socialShareURLString = "https://tryvoiceink\.com/social-share"|affiliateURLString = "https://tryvoiceink\.com/affiliate"|cards\(' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

require_pattern \
  "shared help resources presentation lives in VoiceInkCore" \
  'VoiceInkHelpResourcesPresentation|VoiceInkHelpResourcePresentation|recommendedModelsURLString = "https://tryvoiceink\.com/recommended-models"|videoGuidesURLString = "https://www\.youtube\.com/@tryvoiceink/videos"|documentationURLString = "https://tryvoiceink\.com/docs"|resources:' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

require_pattern \
  "macOS dashboard promotions use shared presentation" \
  'VoiceInkDashboardPromotionPresentation\.(affiliateDismissedKey|defaultIsAffiliateDismissed|cards)|VoiceInkDashboardPromotionCardPresentation' \
  VoiceInk/Views/Metrics/DashboardPromotionsSection.swift

require_pattern \
  "macOS help resources use shared presentation" \
  'VoiceInkHelpResourcesPresentation\.(title|resources|externalLinkSystemImageName)|VoiceInkHelpResourcePresentation' \
  VoiceInk/Views/Metrics/HelpAndResourcesSection.swift

reject_pattern \
  "dashboard promotions avoid duplicate license state adapters" \
  'VoiceInkDashboardPromotionLicenseState|dashboardPromotionLicenseState' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift \
  VoiceInk/Views/Metrics/DashboardPromotionsSection.swift

require_pattern \
  "core checks execute dashboard promotion tests" \
  'DashboardMetricsTests\.testDashboardPromotionPresentationPreservesMacOSCopyURLsAndDismissalKey|DashboardMetricsTests\.testDashboardPromotionPolicyMatchesMacOSLicenseVisibilityRules' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute help resources presentation tests" \
  'DashboardMetricsTests\.testHelpResourcesPresentationPreservesMacOSCopyIconsAndURLs' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS dashboard promotions avoid shell-owned promotion policy" \
  'VoiceInkAffiliatePromotionDismissed|https://tryvoiceink\.com/(social-share|affiliate)|"(30% OFF|Unlock VoiceInk Pro For Less|Share VoiceInk on your socials, and instantly unlock a 30% discount on VoiceInk Pro\.|Share & Unlock|AFFILIATE 30%|Earn With The VoiceInk Affiliate Program|Share VoiceInk with friends or your audience and receive 30% on every referral that upgrades\.|Explore Affiliate|Dismiss this promotion)"|shouldShow(Upgrade|Affiliate|Promotions)' \
  VoiceInk/Views/Metrics/DashboardPromotionsSection.swift

reject_pattern \
  "macOS help resources avoid shell-owned resource copy and URLs" \
  'https://tryvoiceink\.com/(recommended-models|docs)|https://www\.youtube\.com/@tryvoiceink/videos|"(Help & Resources|Recommended Models|YouTube Videos & Guides|Documentation|Feedback or Issues\\?|sparkles|video\.fill|book\.fill|exclamationmark\.bubble\.fill|arrow\.up\.right)"' \
  VoiceInk/Views/Metrics/HelpAndResourcesSection.swift

require_pattern \
  "iOS note-list uses shared chrome presentation" \
  'VoiceInkNoteListPresentation\.(sectionTitle|settingsSystemImageName|startRecordingButtonTitle|startRecordingSystemImageName)' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "iOS recording alert fallback uses shared cancel copy" \
  'VoiceInkRecordingSheetPresentation\.iOS\.cancelButtonTitle' \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS note-list avoids duplicate summary count formatting" \
  'summaryPresentation\.summary\.totalCount|Text\("\\\(' \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS note-list avoids shell-only dashboard metric math" \
  'VoiceInkWordCounter|VoiceInkSessionMetricPolicy|VoiceInkDashboardMetricsAccumulator|dashboardWordCount|dashboardAudioDuration|summary\.totalWords|summary\.totalDuration|words -|reduce\(' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "shared session metric migration preference lives in VoiceInkCore" \
  'VoiceInkSessionMetricDraft|recorderSource = "recorder"|completedTranscriptionStatusRawValue|VoiceInkSessionMetricMigrationPreference|completionKey = "HasCompletedStatsMigration"' \
  VoiceInkCore/Sources/VoiceInkCore/SessionMetricPolicy.swift

require_pattern \
  "macOS session metric model adapts shared draft" \
  'init\(draft: VoiceInkSessionMetricDraft\)' \
  VoiceInk/Models/SessionMetric.swift

require_pattern \
  "macOS session metric recorder uses shared draft" \
  'VoiceInkSessionMetricPolicy\.recorderDraft' \
  VoiceInk/Services/SessionMetricRecorder.swift

require_pattern \
  "macOS stats migration uses shared session metric draft" \
  'VoiceInkSessionMetricPolicy\.recorderDraft' \
  VoiceInk/Services/SessionMetricMigrationService.swift

reject_pattern \
  "macOS session metric shells avoid duplicate recorder source and metric row mapping" \
  'source: "recorder"|let metricValues = VoiceInkSessionMetricPolicy\.values|wordCount: metricValues|audioDuration: metricValues|speedFactor: metricValues' \
  VoiceInk/Services/SessionMetricRecorder.swift \
  VoiceInk/Services/SessionMetricMigrationService.swift

require_pattern \
  "macOS stats migration uses shared completion preference" \
  'VoiceInkSessionMetricMigrationPreference\.(isCompleted|markCompleted)' \
  VoiceInk/Services/SessionMetricMigrationService.swift

reject_pattern \
  "macOS stats migration avoids raw completion preference and status" \
  'HasCompletedStatsMigration|UserDefaults\.standard|transcriptionStatus == "completed"' \
  VoiceInk/Services/SessionMetricMigrationService.swift

require_pattern \
  "core checks execute session metric draft and migration preference tests" \
  'SessionMetricPolicyTests\.testRecorderDraftPreservesSourceAndMetricFields|SessionMetricPolicyTests\.testMigrationPreferencePreservesCompletionStorageKey' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared session metric migration preference" \
  'metric row drafts, recorder source, completed-status filtering, .*stats-migration completion storage through `VoiceInkSessionMetricPolicy`/`VoiceInkSessionMetricDraft`/`VoiceInkSessionMetricMigrationPreference`' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "iOS note-list avoids shell-only chrome and action copy" \
  '"(Recent|Start Recording|gearshape|mic\.fill|Cancel)"' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "shared note-list fastest-model summary uses shared performance analyzer" \
  'VoiceInkPerformanceAnalyzer\.transcriptionModelStats' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

require_pattern \
  "shared dashboard metrics owns average WPM display text" \
  'averageWordsPerMinuteDisplayText' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

require_pattern \
  "shared macOS dashboard presentation lives in VoiceInkCore" \
  'VoiceInkDashboardPresentation|VoiceInkDashboardMetricCardPresentation|heroTitle|heroSubtitle|metricCards|modelPerformanceButtonTitle' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

require_pattern \
  "macOS dashboard uses shared dashboard presentation" \
  'VoiceInkDashboardPresentation\.(emptyStateSystemImageName|emptyStateTitle|emptyStateMessage|heroSectionTitle|heroTitle|heroSubtitle|sessionsPillTitle|wordsPillTitle|formattedNumber|metricValuePlaceholder|metricCards|modelPerformanceButtonTitle|modelPerformanceSystemImageName|modelPerformanceHelpText)' \
  VoiceInk/Views/Metrics/MetricsContent.swift

require_pattern \
  "core tests pin macOS dashboard presentation copy and policy" \
  'testDashboardPresentationPreservesMacOSDashboardCopy|testDashboardPresentationBuildsHeroTitleAndSubtitle|testDashboardPresentationBuildsMacOSMetricCards|testHelpResourcesPresentationPreservesMacOSCopyIconsAndURLs' \
  VoiceInkCore/Tests/VoiceInkCoreTests/DashboardMetricsTests.swift

require_pattern \
  "core check runner executes macOS dashboard presentation tests" \
  'DashboardMetricsTests\.testDashboardPresentationPreservesMacOSDashboardCopy|DashboardMetricsTests\.testDashboardPresentationBuildsHeroTitleAndSubtitle|DashboardMetricsTests\.testDashboardPresentationBuildsMacOSMetricCards|DashboardMetricsTests\.testHelpResourcesPresentationPreservesMacOSCopyIconsAndURLs' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared dashboard promotion and help resources presentation" \
  'macOS dashboard hero/empty/action/stat-card/promotion/help-resource presentation.*VoiceInkHelpResourcesPresentation' \
  docs/ios-single-repo-migration.md

require_pattern \
  "macOS dashboard uses shared metric-card presentation" \
  'ForEach\(metricCardPresentations\)|card\.iconSystemName|card\.detail' \
  VoiceInk/Views/Metrics/MetricsContent.swift

reject_pattern \
  "macOS dashboard avoids shallow metric-card presentation wrappers" \
  'private var +metricCardPresentations\b' \
  VoiceInk/Views/Metrics/MetricsContent.swift

reject_pattern \
  "macOS dashboard avoids shell-only shared dashboard presentation copy" \
  '"(No sessions yet|Start a recording; your dictation rhythm will show here\.|Dashboard|Ready when you are|Your usage summary will appear here\.|Your first roma-just-talk recording starts the timeline\.|Time savings coming soon|Sessions|Words|Model Performance|View transcription and enhancement model performance)"|systemName: "(waveform|gauge)"|totalCount == 1 \? "session" : "sessions"' \
  VoiceInk/Views/Metrics/MetricsContent.swift

reject_pattern \
  "macOS dashboard avoids shell-only shared metric-card presentation copy" \
  '"(Sessions Recorded|Words Dictated|Words Per Minute|Keystrokes Saved|recordings completed|words generated|dictation pace|fewer keystrokes)"|icon: "(mic\.fill|text\.alignleft|speedometer|keyboard\.fill)"|private enum Formatters|NumberFormatter|private var totalKeystrokesSaved|dashboardMetrics\.averageWordsPerMinuteDisplayText' \
  VoiceInk/Views/Metrics/MetricsContent.swift

reject_pattern \
  "macOS dashboard avoids shell-only average WPM formatting" \
  'averageWordsPerMinute > 0|String\(format: +"%\.1f", averageWordsPerMinute\)|private var averageWordsPerMinute' \
  VoiceInk/Views/Metrics/MetricsContent.swift

reject_pattern \
  "iOS note-list avoids shell-only performance grouping" \
  'VoiceInkPerformanceAnalyzer|Dictionary\(grouping:|avgProcessingTime|speedFactor =|totalProcessingTime|performanceTranscriptionDuration|speedFactorRealtimeText' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "shared performance stat owns realtime presentation text" \
  'speedFactorRealtimeText|realTimeComparisonText' \
  VoiceInkCore/Sources/VoiceInkCore/PerformanceAnalysis.swift

require_pattern \
  "shared performance time filter lives in VoiceInkCore" \
  'VoiceInkPerformanceTimeFilter' \
  VoiceInkCore/Sources/VoiceInkCore/PerformanceAnalysis.swift

require_pattern \
  "shared performance time filter owns macOS panel storage and windows" \
  'userDefaultsKey = "modelPerfPanelFilter"|defaultFilter|storedFilter|startDate' \
  VoiceInkCore/Sources/VoiceInkCore/PerformanceAnalysis.swift

require_pattern \
  "shared performance panel presentation lives in VoiceInkCore" \
  'VoiceInkPerformancePresentation|modelPerformancePanelTitle|performanceAnalysisPanelTitle|averageEnhancementTimeLabel|transcriptSampleCountText|physicalMemoryText' \
  VoiceInkCore/Sources/VoiceInkCore/PerformanceAnalysis.swift

require_pattern \
  "shared performance presentation owns physical-memory text" \
  'physicalMemoryText\(byteCount: UInt64\)|ByteCountFormatter\.string\(fromByteCount: Int64\(clamping: byteCount\), countStyle: \.memory\)' \
  VoiceInkCore/Sources/VoiceInkCore/PerformanceAnalysis.swift

require_pattern \
  "macOS model performance panel uses shared time filter" \
  'VoiceInkPerformanceTimeFilter\.(userDefaultsKey|defaultFilter|storedFilter)|filter\.startDate\(' \
  VoiceInk/Views/Metrics/ModelPerformancePanel.swift

require_pattern \
  "macOS model performance panel uses shared presentation" \
  'VoiceInkPerformancePresentation\.(modelPerformancePanelTitle|emptyStateSystemImageName|sessionSampleCountText|averageProcessingLabel)' \
  VoiceInk/Views/Metrics/ModelPerformancePanel.swift

require_pattern \
  "macOS performance analysis panel uses shared presentation" \
  'VoiceInkPerformancePresentation\.(performanceAnalysisPanelTitle|summarySectionTitle|transcriptSampleCountText|averageProcessingLabel)' \
  VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift

require_pattern \
  "macOS system info uses shared physical-memory presentation" \
  'VoiceInkPerformancePresentation\.physicalMemoryText\(byteCount: totalMemory\)' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS performance helper uses shared physical-memory presentation" \
  'VoiceInkPerformancePresentation\.physicalMemoryText\(byteCount: totalMemory\)' \
  VoiceInk/Views/Metrics/PerformanceAnalysisView.swift

require_pattern \
  "core tests pin macOS performance panel presentation" \
  'testPerformancePresentationPreservesMacOSPanelCopyAndIcons' \
  VoiceInkCore/Tests/VoiceInkCoreTests/PerformanceAnalysisTests.swift

require_pattern \
  "core tests pin physical-memory presentation" \
  'physicalMemoryText\(byteCount: 1_073_741_824\)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/PerformanceAnalysisTests.swift

require_pattern \
  "core check runner executes performance panel presentation tests" \
  'PerformanceAnalysisTests\.testPerformancePresentationPreservesMacOSPanelCopyAndIcons' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS model performance panel avoids shell-only time filter policy" \
  'enum +TimeFilter|"modelPerfPanelFilter"|"Last 7 Days"|"Last 30 Days"|"This Year"|"All Time"|addingTimeInterval\(-[0-9]+ \* 24 \* 3600\)|dateInterval\(of: \.year' \
  VoiceInk/Views/Metrics/ModelPerformancePanel.swift

reject_pattern \
  "macOS performance panels avoid shell-only shared performance presentation copy" \
  '"(Model Performance|Performance Analysis|No data for this period|Summary|System Information|Transcription Models|Enhancement Models|Total|Analyzable|Enhanced|Device|Processor|Memory|Avg\. Audio|Avg\. Processing|Avg\. Enhancement Time)"|systemName: "(xmark|chart\.bar\.xaxis|doc\.text\.fill|waveform\.path\.ecg|sparkles)"|sampleCount\) (sessions|transcripts)' \
  VoiceInk/Views/Metrics/ModelPerformancePanel.swift \
  VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift

reject_pattern \
  "macOS system info and performance helpers avoid shell-only physical-memory formatting" \
  'ByteCountFormatter\.string\(fromByteCount:.*countStyle: \.memory\)' \
  VoiceInk/Services/SystemInfoService.swift \
  VoiceInk/Views/Metrics/PerformanceAnalysisView.swift

reject_pattern \
  "platform metric views avoid shell-only realtime presentation text" \
  '"Faster than Real-time"|"Slower than Real-time"|speedFactor >= 1\.0|speedFactorText\) realtime' \
  VoiceInk/Views/Metrics/ModelPerformancePanel.swift \
  VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "workspace includes iOS project" \
  'location = "group:iOS/VoiceInk-ios.xcodeproj"' \
  VoiceInk.xcworkspace/contents.xcworkspacedata

require_pattern \
  "iOS project keeps unit test target" \
  'VoiceInk-iosTests\.xctest' \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_pattern \
  "iOS project keeps UI test target" \
  'VoiceInk-iosUITests\.xctest' \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_pattern \
  "iOS shared scheme includes unit tests" \
  'BlueprintName = "VoiceInk-iosTests"' \
  VoiceInk.xcworkspace/xcshareddata/xcschemes/VoiceInk-ios.xcscheme

require_pattern \
  "iOS shared scheme includes UI tests" \
  'BlueprintName = "VoiceInk-iosUITests"' \
  VoiceInk.xcworkspace/xcshareddata/xcschemes/VoiceInk-ios.xcscheme

require_pattern \
  "macOS project resolves in-repo VoiceInkCore" \
  'relativePath = VoiceInkCore;' \
  VoiceInk.xcodeproj/project.pbxproj

require_pattern \
  "iOS project resolves in-repo VoiceInkCore from iOS/" \
  'relativePath = ../VoiceInkCore;' \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_context_pattern_count_at_least \
  "iOS app target links VoiceInkCore product" \
  'E168DF042E4B464B00F133D2 /\* Frameworks \*/' \
  'VoiceInkCore in Frameworks' \
  1 \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_context_pattern_count_at_least \
  "iOS app target declares VoiceInkCore package dependency" \
  'E168DF062E4B464B00F133D2 /\* VoiceInk-ios \*/' \
  '/\* VoiceInkCore \*/' \
  1 \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_context_pattern_count_at_least \
  "iOS app and keyboard targets include shared shell group" \
  'fileSystemSynchronizedGroups = \(' \
  '/\* Shared \*/' \
  2 \
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

require_pattern \
  "shared app identity presentation lives in VoiceInkCore" \
  'VoiceInkAppIdentity|VoiceInkStorageStartupDiagnostics|VoiceInkMacOSStorageAlertPresentation|VoiceInkMacOSNavigationDestination|VoiceInkMacOSMainViewItem|VoiceInkMacOSNavigationRequest|VoiceInkMacOSFileTranscriptionRequest|bundleIdentifier = "com\.prakashjoshipax\.VoiceInk"|loggingSubsystem = "com\.prakashjoshipax\.voiceink"|displayName = "roma just talk"|compactDisplayName = "roma-just-talk"|iOSRecordDeepLinkScheme = "voiceink"|iOSRecordDeepLinkHost = "record"|iCloudContainerIdentifier|iOSAppGroupIdentifier|iOSRecordDeepLinkURL|iOSStopRecordingDarwinNotificationName|iOSRecordingStateChangedDarwinNotificationName|iOSStopRecordingFromKeyboardNotificationName|macOSApplicationSupportDirectory|storageFallbackWarningPresentation|storageFailurePresentation|modelContainerInitializationFailedMessage|modelContainerUnavailablePreconditionMessage|iOSModelContainerCreationFailedMessage|errorDomain' \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift

section "obsolete standalone AppIntent presentation module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/AppIntentPresentation.swift

section "obsolete standalone mini-recorder request module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/MiniRecorderRequest.swift

require_patterns \
  "shared macOS AppIntent presentation lives with app identity" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkAppIntentPresentation' \
  'VoiceInkMiniRecorderAppIntentPresentation' \
  '"Toggle VoiceInk Recorder"' \
  '"Start or stop the VoiceInk mini recorder for voice transcription\."' \
  '"VoiceInk recorder toggled"' \
  '"Dismiss VoiceInk Recorder"' \
  '"Dismiss the VoiceInk mini recorder and cancel any active recording\."' \
  '"VoiceInk recorder dismissed"'

require_patterns \
  "shared mini-recorder request notifications live with app identity" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkMiniRecorderRequest' \
  'toggleNotificationName = Notification\.Name\("toggleMiniRecorder"\)' \
  'dismissNotificationName = Notification\.Name\("dismissMiniRecorder"\)'

require_patterns \
  "macOS mini-recorder intents use shared presentation" \
  VoiceInk/AppIntents/ToggleMiniRecorderIntent.swift \
  'VoiceInkMiniRecorderAppIntentPresentation\.toggle' \
  'LocalizedStringResource\(stringLiteral: presentation\.title\)' \
  'IntentDescription\(stringLiteral: presentation\.description\)' \
  'IntentDialog\(stringLiteral: Self\.presentation\.successDialog\)'

require_patterns \
  "macOS dismiss-recorder intent uses shared presentation" \
  VoiceInk/AppIntents/DismissMiniRecorderIntent.swift \
  'VoiceInkMiniRecorderAppIntentPresentation\.dismiss' \
  'LocalizedStringResource\(stringLiteral: presentation\.title\)' \
  'IntentDescription\(stringLiteral: presentation\.description\)' \
  'IntentDialog\(stringLiteral: Self\.presentation\.successDialog\)'

reject_pattern \
  "macOS mini-recorder intents avoid shell-owned presentation copy and stale error wrapper" \
  '"(Toggle VoiceInk Recorder|Start or stop the VoiceInk mini recorder for voice transcription\.|VoiceInk recorder toggled|Dismiss VoiceInk Recorder|Dismiss the VoiceInk mini recorder and cancel any active recording\.|VoiceInk recorder dismissed|VoiceInk app is not available|VoiceInk recording service is not available)"|enum +IntentError|import AppKit' \
  VoiceInk/AppIntents/ToggleMiniRecorderIntent.swift \
  VoiceInk/AppIntents/DismissMiniRecorderIntent.swift

require_pattern \
  "macOS app notifications use shared mini-recorder request names" \
  'toggleMiniRecorder = VoiceInkMiniRecorderRequest\.toggleNotificationName|dismissMiniRecorder = VoiceInkMiniRecorderRequest\.dismissNotificationName' \
  VoiceInk/Notifications/AppNotifications.swift

reject_pattern \
  "macOS app notification shell avoids duplicate mini-recorder request names" \
  'Notification\.Name\("toggleMiniRecorder"\)|Notification\.Name\("dismissMiniRecorder"\)' \
  VoiceInk/Notifications/AppNotifications.swift

reject_pattern \
  "macOS recorder window managers avoid dead legacy hide notifications" \
  'HideMiniRecorder|HideNotchRecorder|handleHideNotification' \
  VoiceInk/Views/Recorder/MiniWindowManager.swift \
  VoiceInk/Views/Recorder/NotchWindowManager.swift

require_pattern \
  "migration checklist tracks removed recorder window hide notifications" \
  'obsolete per-window recorder hide notification observers stay removed' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS model change notification avoids unused model-name payload" \
  'userInfo: \["modelName"' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

require_patterns \
  "shared storage startup diagnostics live in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkStorageStartupDiagnostics' \
  'modelContainerInitializationFailedMessage' \
  'modelContainerUnavailablePreconditionMessage' \
  'iOSModelContainerCreationFailedMessage'

require_pattern \
  "shared macOS navigation request contract lives in VoiceInkCore" \
  'VoiceInkMacOSNavigationDestination|settings = "Settings"|aiModels = "AI Models"|license = "VoiceInk Pro"|history = "History"|permissions = "Permissions"|enhancement = "Enhancement"|transcribeAudio = "Transcribe Audio"|powerMode = "Power Mode"|notificationName = Notification\.Name\("navigateToDestination"\)|destinationUserInfoKey = "destination"|defaultDestination|destination\(from notification: Notification\)|VoiceInkMacOSFileTranscriptionRequest|notificationName = Notification\.Name\("openFileForTranscription"\)|urlUserInfoKey = "url"|url\(from notification: Notification\)' \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift

require_pattern \
  "shared macOS main view item presentation lives in VoiceInkCore" \
  'VoiceInkMacOSMainViewItem|case metrics|case transcribeAudio|case audioInput|case dictionary|title|systemImageName|defaultSelection|emptySelectionTitle|visibleItems\(powerModeEnabled: Bool\)|item\(forNavigationDestination destination: String\)' \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift

reject_file VoiceInkCore/Sources/VoiceInkCore/SupportContactPolicy.swift

require_patterns \
  "shared support contact policy lives with app identity in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkSupportContactPolicy' \
  'emailAddress = "support@tryvoiceink\.com"' \
  'emailSubject = "VoiceInk Support Request"' \
  'commonIssuesURLString = "https://tryvoiceink\.com/common-issues"' \
  'emailBody\(systemInformation:' \
  'mailtoURL\(subject:'

require_pattern \
  "macOS email support adapts shared support contact policy" \
  'VoiceInkSupportContactPolicy\.(emailAddress|emailSubject|emailBody|mailtoURL)' \
  VoiceInk/EmailSupport.swift

require_pattern \
  "core checks execute support contact policy tests" \
  'SupportContactPolicyTests\.testSupportContactPolicyPreservesEmailIdentityAndSubject|SupportContactPolicyTests\.testSupportEmailBodyPreservesMacOSSupportCopyAndSystemInformationSlot|SupportContactPolicyTests\.testSupportMailtoURLPreservesRecipientAndEncodesSubject' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS EmailSupport avoids shell-owned support contact policy" \
  '"support@tryvoiceink\.com"|"VoiceInk Support Request"|SCREEN RECORDING HIGHLY RECOMMENDED|COMMON ISSUES|tryvoiceink\.com/common-issues|URL\(string: "mailto:' \
  VoiceInk/EmailSupport.swift

require_file VoiceInkCore/Sources/VoiceInkCore/SystemInformationReport.swift
require_file VoiceInkCore/Sources/VoiceInkCore/SystemArchitecture.swift

require_patterns \
  "shared system architecture policy lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/SystemArchitecture.swift \
  'VoiceInkSystemArchitecture' \
  'isIntelMac' \
  'macOSDisplayName' \
  'Apple Silicon \(ARM64\)' \
  'Intel \(x86_64\)'

require_pattern \
  "macOS model management adapts shared system architecture policy" \
  'VoiceInkSystemArchitecture\.isIntelMac' \
  'VoiceInk/Views/AI Models/ModelManagementView.swift'

require_pattern \
  "macOS system info adapts shared system architecture display name" \
  'VoiceInkSystemArchitecture\.macOSDisplayName' \
  VoiceInk/Services/SystemInfoService.swift

reject_file VoiceInk/Services/SystemArchitecture.swift

require_patterns \
  "shared macOS system information report formatting lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/SystemInformationReport.swift \
  'VoiceInkMacOSSystemInformationFacts' \
  'VoiceInkSystemInformationReport' \
  '=== VOICEINK SYSTEM INFORMATION ===' \
  'APP INFORMATION:' \
  'ROLLING BUFFER PRELOAD:' \
  'CLIPBOARD & PASTE SETTINGS:' \
  'DATA CLEANUP SETTINGS:' \
  'PERMISSIONS:'

require_patterns \
  "macOS system info service adapts shared report formatter" \
  VoiceInk/Services/SystemInfoService.swift \
  'VoiceInkSystemInformationReport\.macOS\(makeMacOSSystemInformationFacts\(\)\)' \
  'VoiceInkMacOSSystemInformationFacts'

reject_pattern \
  "macOS system info service avoids shell-owned report template" \
  '=== VOICEINK SYSTEM INFORMATION ===|APP INFORMATION:|CLIPBOARD & PASTE SETTINGS:|DATA CLEANUP SETTINGS:|PERMISSIONS:' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "core checks execute system information report tests" \
  'SystemArchitectureTests\.testSystemArchitecturePreservesMacOSDisplayNameForCompileTarget|SystemArchitectureTests\.testSystemArchitectureIntelMacPredicateMatchesCompileTarget|SystemInformationReportTests\.testMacOSSystemInformationReportPreservesSectionOrderAndLabels|SystemInformationReportTests\.testMacOSSystemInformationReportKeepsRollingBufferBlockVerbatim' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration docs describe shared macOS system information report formatting" \
  'macOS support system-information report formatting|VoiceInkSystemInformationReport' \
  docs/ios-single-repo-migration.md

section "obsolete standalone app notification presentation module stays deleted"
reject_file VoiceInkCore/Sources/VoiceInkCore/AppNotificationPresentation.swift

require_patterns \
  "shared app notification presentation lives with app identity" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkAppNotificationKind' \
  'case error' \
  'case warning' \
  'case info' \
  'case success' \
  'defaultDisplayDuration: TimeInterval = 3\.0' \
  'xmark\.octagon\.fill' \
  'exclamationmark\.triangle\.fill' \
  'info\.circle\.fill' \
  'checkmark\.circle\.fill' \
  'playsFailureSound'

require_pattern \
  "macOS app notification view adapts shared notification kind" \
  'VoiceInkAppNotificationKind|type\.systemImageName|private extension VoiceInkAppNotificationKind' \
  VoiceInk/Notifications/AppNotificationView.swift

require_pattern \
  "macOS notification manager adapts shared notification kind" \
  'VoiceInkAppNotificationKind|defaultDisplayDuration|type\.playsFailureSound' \
  VoiceInk/Notifications/NotificationManager.swift

require_pattern \
  "core checks execute app notification presentation tests" \
  'AppNotificationPresentationTests\.testAppNotificationKindsPreserveCasesAndDefaultDuration|AppNotificationPresentationTests\.testAppNotificationKindsPreserveSystemImages|AppNotificationPresentationTests\.testOnlyErrorNotificationsPlayFailureSound' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS notification shell avoids shell-owned notification kind policy" \
  'enum +NotificationType|AppNotificationView\.NotificationType|duration: TimeInterval = 3\.0|type == \.error|"xmark\.octagon\.fill"|"exclamationmark\.triangle\.fill"|"info\.circle\.fill"|"checkmark\.circle\.fill"' \
  VoiceInk/Notifications/AppNotificationView.swift \
  VoiceInk/Notifications/NotificationManager.swift

require_pattern \
  "macOS app notifications use shared navigation request contract" \
  'navigateToDestination = VoiceInkMacOSNavigationRequest\.notificationName|openFileForTranscription = VoiceInkMacOSFileTranscriptionRequest\.notificationName' \
  VoiceInk/Notifications/AppNotifications.swift

require_patterns \
  "shared macOS app event request contract lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkMacOSAppEventRequest' \
  'appSettingsDidChangeNotificationName = Notification\.Name\("appSettingsDidChange"\)' \
  'languageDidChangeNotificationName = Notification\.Name\("languageDidChange"\)' \
  'didChangeModelNotificationName = Notification\.Name\("didChangeModel"\)' \
  'openMainWindowRequestedNotificationName = Notification\.Name\("openMainWindowRequested"\)' \
  'appPermissionsDidChangeNotificationName = Notification\.Name\("appPermissionsDidChange"\)' \
  'promptSelectionChangedNotificationName = Notification\.Name\("promptSelectionChanged"\)' \
  'powerModeConfigurationAppliedNotificationName = Notification\.Name\("powerModeConfigurationApplied"\)' \
  'powerModeConfigurationsDidChangeNotificationName = Notification\.Name\("PowerModeConfigurationsDidChange"\)' \
  'powerModeShortcutAvailabilityDidChangeNotificationName = Notification\.Name\("powerModeShortcutAvailabilityDidChange"\)' \
  'transcriptionCreatedNotificationName = Notification\.Name\("transcriptionCreated"\)' \
  'transcriptionCompletedNotificationName = Notification\.Name\("transcriptionCompleted"\)' \
  'transcriptionDeletedNotificationName = Notification\.Name\("transcriptionDeleted"\)' \
  'sessionMetricsDidChangeNotificationName = Notification\.Name\("sessionMetricsDidChange"\)' \
  'enhancementToggleChangedNotificationName = Notification\.Name\("enhancementToggleChanged"\)'

require_patterns \
  "macOS app notifications use shared app event request names" \
  VoiceInk/Notifications/AppNotifications.swift \
  'AppSettingsDidChange = VoiceInkMacOSAppEventRequest\.appSettingsDidChangeNotificationName' \
  'languageDidChange = VoiceInkMacOSAppEventRequest\.languageDidChangeNotificationName' \
  'didChangeModel = VoiceInkMacOSAppEventRequest\.didChangeModelNotificationName' \
  'openMainWindowRequested = VoiceInkMacOSAppEventRequest\.openMainWindowRequestedNotificationName' \
  'appPermissionsDidChange = VoiceInkMacOSAppEventRequest\.appPermissionsDidChangeNotificationName' \
  'promptSelectionChanged = VoiceInkMacOSAppEventRequest\.promptSelectionChangedNotificationName' \
  'powerModeConfigurationApplied = VoiceInkMacOSAppEventRequest\.powerModeConfigurationAppliedNotificationName' \
  'powerModeConfigurationsDidChange = VoiceInkMacOSAppEventRequest\.powerModeConfigurationsDidChangeNotificationName' \
  'powerModeShortcutAvailabilityDidChange = VoiceInkMacOSAppEventRequest\.powerModeShortcutAvailabilityDidChangeNotificationName' \
  'transcriptionCreated = VoiceInkMacOSAppEventRequest\.transcriptionCreatedNotificationName' \
  'transcriptionCompleted = VoiceInkMacOSAppEventRequest\.transcriptionCompletedNotificationName' \
  'transcriptionDeleted = VoiceInkMacOSAppEventRequest\.transcriptionDeletedNotificationName' \
  'sessionMetricsDidChange = VoiceInkMacOSAppEventRequest\.sessionMetricsDidChangeNotificationName' \
  'enhancementToggleChanged = VoiceInkMacOSAppEventRequest\.enhancementToggleChangedNotificationName'

require_pattern \
  "core checks execute macOS app event request test" \
  'AppIdentityTests\.testMacOSAppEventRequestPreservesNotificationNames' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS app notification shell avoids duplicate app event request names" \
  'Notification\.Name\("(appSettingsDidChange|languageDidChange|didChangeModel|openMainWindowRequested|appPermissionsDidChange|promptSelectionChanged|powerModeConfigurationApplied|PowerModeConfigurationsDidChange|powerModeShortcutAvailabilityDidChange|transcriptionCreated|transcriptionCompleted|transcriptionDeleted|sessionMetricsDidChange|enhancementToggleChanged)"\)' \
  VoiceInk/Notifications/AppNotifications.swift

reject_pattern \
  "macOS shell avoids duplicate navigation payload key literals" \
  'userInfo: \["destination"|userInfo\?\["destination"\]|Notification\.Name\("navigateToDestination"\)' \
  VoiceInk/AppDelegate.swift \
  VoiceInk/MenuBarManager.swift \
  VoiceInk/Notifications/AppNotifications.swift \
  VoiceInk/Services/ImportExportService.swift \
  VoiceInk/Services/PermissionFlowGuide.swift \
  VoiceInk/Views/ContentView.swift \
  VoiceInk/Views/MenuBarView.swift \
  VoiceInk/Views/MetricsView.swift \
  VoiceInk/Views/Metrics/MetricsSetupView.swift \
  VoiceInk/VoiceInk.swift

reject_pattern \
  "macOS shell avoids duplicate file-transcription payload key literals" \
  'userInfo: \["url"|userInfo\?\["url"\]|Notification\.Name\("openFileForTranscription"\)' \
  VoiceInk/AppDelegate.swift \
  VoiceInk/Notifications/AppNotifications.swift \
  VoiceInk/Views/AudioTranscribeView.swift \
  VoiceInk/VoiceInk.swift

require_file VoiceInkCore/Sources/VoiceInkCore/DiagnosticLogExportPolicy.swift

require_pattern \
  "shared diagnostic log export policy lives in VoiceInkCore" \
  'VoiceInkDiagnosticsSettingsPresentation|VoiceInkDiagnosticLogExportPolicy|VoiceInkDiagnosticLogSessionRange|sessionStartDatesKey = "logExporter\.sessionStartDates\.v1"|maxSessionStartDatesToKeep = 3|timestampDateFormat = "yyyy-MM-dd HH:mm:ss\.SSS"|fileNameDateFormat = "yyyy-MM-dd_HH-mm-ss"|fileNamePrefix = "VoiceInk_Logs_"|headerTitle = "=== VoiceInk Diagnostic Logs ==="|noLogsFoundMessage = "No logs found for this session\."|exporterErrorDomain = "LogExporter"|downloadsDirectoryUnavailableErrorCode = 1|downloadsDirectoryUnavailableDescription = "Downloads directory unavailable"|sessionRanges|headerLines|logEntryLine|logLevelLabel|fileName|downloadsDirectoryUnavailableError|rollingBufferLastClaimLabel|exportFailedAlertTitle|exportedLogSuccessSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/DiagnosticLogExportPolicy.swift

require_patterns \
  "macOS diagnostics settings uses shared diagnostics presentation" \
  VoiceInk/Views/Settings/DiagnosticsSettingsView.swift \
  'VoiceInkDiagnosticsSettingsPresentation\.rollingBufferLastClaimLabel' \
  'VoiceInkDiagnosticsSettingsPresentation\.showInFinderButtonTitle' \
  'VoiceInkDiagnosticsSettingsPresentation\.exportButtonTitle' \
  'VoiceInkDiagnosticsSettingsPresentation\.exportLogsLabel' \
  'VoiceInkDiagnosticsSettingsPresentation\.exportFailedAlertTitle' \
  'VoiceInkDiagnosticsSettingsPresentation\.alertDismissButtonTitle' \
  'VoiceInkDiagnosticsSettingsPresentation\.exportedLogSuccessSystemImageName'

require_pattern \
  "macOS log exporter uses shared diagnostic log export policy" \
  'VoiceInkDiagnosticLogExportPolicy\.(sessionStartDates|storedSessionStartDates|saveSessionStartDates|headerLines|sessionRanges|sessionHeaderLines|logEntryLine|logLevelLabel|noLogsFoundMessage|fileName|downloadsDirectoryUnavailableError)' \
  VoiceInk/Services/LogExporter.swift

require_pattern \
  "macOS log exporter uses shared log category identity" \
  'Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem, category: VoiceInkMacOSLogCategory\.logExporter\)' \
  VoiceInk/Services/LogExporter.swift

require_pattern \
  "core checks execute diagnostic log export policy tests" \
  'DiagnosticLogExportPolicyTests\.testDiagnosticsSettingsPresentationPreservesMacOSCopyAndIcons|DiagnosticLogExportPolicyTests\.testDiagnosticLogExportPolicyPreservesMacOSStorageAndFormattingConstants|DiagnosticLogExportPolicyTests\.testDiagnosticLogExportPolicyBuildsSessionRangesWithCurrentMiddleAndOldestLabels|DiagnosticLogExportPolicyTests\.testDiagnosticLogExportPolicyOwnsOSLogLevelLabels|DiagnosticLogExportPolicyTests\.testDiagnosticLogExportPolicyBuildsMacOSExportFileName|DiagnosticLogExportPolicyTests\.testDiagnosticLogExportPolicyBuildsDownloadsUnavailableError' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared diagnostics settings presentation" \
  'diagnostic log session storage/range/header/filename/error policy, diagnostic settings copy/icons.*VoiceInkDiagnosticLogExportPolicy`/`VoiceInkDiagnosticsSettingsPresentation' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS log exporter avoids shell-owned diagnostic log export policy" \
  'logExporter\.sessionStartDates\.v1|maxSessionsToKeep|sessionRanges:|\[Date\(\)\] \+ loadedDates|prefix\(maxSessionsToKeep\)|yyyy-MM-dd HH:mm:ss\.SSS|yyyy-MM-dd_HH-mm-ss|VoiceInk_Logs_|=== VoiceInk Diagnostic Logs ===|No logs found for this session\.|Session 1 \(Current\)|Session [0-9].*\(Oldest\)|NSError\(domain: "LogExporter"|code: 1|Downloads directory unavailable|NSLocalizedDescriptionKey|logLevelString|case \.(undefined|debug|info|notice|error|fault)|return "(UNDEFINED|DEBUG|INFO|NOTICE|ERROR|FAULT|UNKNOWN)"' \
  VoiceInk/Services/LogExporter.swift

reject_pattern \
  "macOS log exporter avoids shell-owned log category literal" \
  'category: "LogExporter"' \
  VoiceInk/Services/LogExporter.swift

reject_pattern \
  "macOS diagnostics settings view avoids shell-owned diagnostics presentation copy" \
  '"(Rolling Buffer Last Claim|Show in Finder|Export|Export Logs|Export Failed|OK|checkmark\.circle\.fill)"' \
  VoiceInk/Views/Settings/DiagnosticsSettingsView.swift

require_pattern \
  "shared menu bar preference lives in VoiceInkCore" \
  'VoiceInkMenuBarPreference|showMenuBarIconKey|isMenuBarOnlyKey|defaultShowMenuBarIcon|defaultIsMenuBarOnly|registeredDefaults|saveIsMenuBarOnly' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_patterns \
  "shared macOS menu bar presentation lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift \
  'VoiceInkMacOSMenuBarPresentation' \
  'toggleRecorderTitle' \
  'transcriptionModelTitle' \
  'aiEnhancementToggleTitle' \
  'promptTitle' \
  'aiProviderTitle' \
  'aiModelTitle' \
  'dockIconTitle' \
  'selectionCheckmarkSystemImageName' \
  'pickerSystemImageName'

require_pattern \
  "shared macOS shell backup preferences live in VoiceInkCore" \
  'VoiceInkMacOSShellBackupPreferences' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared macOS shell backup import plan lives in VoiceInkCore" \
  'VoiceInkMacOSShellBackupImportPlan' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_context_pattern_count_at_least \
  "shared macOS shell backup export policy lives in VoiceInkCore" \
  'enum VoiceInkMacOSShellBackupPreference' \
  'static func backupPreferences' \
  1 \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_context_pattern_count_at_least \
  "shared macOS shell backup import policy lives in VoiceInkCore" \
  'enum VoiceInkMacOSShellBackupPreference' \
  'static func backupImportPlan' \
  1 \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS general backup adapts shell values to shared preferences" \
  'macOSShellBackupPreferences' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS backup export uses shared macOS shell backup preferences" \
  'VoiceInkMacOSShellBackupPreference\.backupPreferences' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup import reads shared macOS shell plan from grouped general settings" \
  'generalImportPlans\.macOSShell' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import avoids shell-owned macOS shell backup planning" \
  'general\.(launchAtLoginEnabled|isMenuBarOnly|recorderType)' \
  VoiceInk/Services/BackupImporter.swift

reject_context_pattern \
  "macOS backup export avoids shell-owned macOS shell backup field emission" \
  'GeneralBackup\(' \
  'launchAtLoginEnabled: LaunchAtLogin\.isEnabled|isMenuBarOnly: menuBarManager\.isMenuBarOnly|recorderType: recorderUIManager\.recorderType' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS defaults register shared menu bar preference" \
  'VoiceInkMenuBarPreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS menu bar manager uses shared menu bar preference" \
  'VoiceInkMenuBarPreference\.(saveIsMenuBarOnly|isMenuBarOnly)' \
  VoiceInk/MenuBarManager.swift

require_pattern \
  "macOS app scene uses shared menu bar icon preference" \
  'VoiceInkMenuBarPreference\.(showMenuBarIconKey|defaultShowMenuBarIcon)' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS menu bar view uses shared menu bar icon preference" \
  'VoiceInkMenuBarPreference\.(showMenuBarIconKey|defaultShowMenuBarIcon)' \
  VoiceInk/Views/MenuBarView.swift

require_patterns \
  "macOS menu bar view uses shared menu bar presentation" \
  VoiceInk/Views/MenuBarView.swift \
  'VoiceInkMacOSMenuBarPresentation\.toggleRecorderTitle' \
  'VoiceInkMacOSMenuBarPresentation\.transcriptionModelTitle' \
  'VoiceInkMacOSMenuBarPresentation\.promptTitle' \
  'VoiceInkMacOSMenuBarPresentation\.aiProviderTitle' \
  'VoiceInkMacOSMenuBarPresentation\.aiModelTitle' \
  'VoiceInkMacOSMenuBarPresentation\.dockIconTitle' \
  'VoiceInkMacOSMenuBarPresentation\.quitTitle'

require_pattern \
  "macOS settings uses shared menu bar icon preference" \
  'VoiceInkMenuBarPreference\.(showMenuBarIconKey|defaultShowMenuBarIcon)' \
  VoiceInk/Views/Settings/SettingsView.swift

require_pattern \
  "macOS diagnostics use shared menu bar preference" \
  'VoiceInkMenuBarPreference\.isMenuBarOnly' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "core checks execute menu bar preference tests" \
  'testSharedPreferenceDefaultsPreserveExistingMacOSMenuBarPolicy|testMenuBarPreferencePreservesRegisteredDefaultsAndStorage|testMacOSMenuBarPresentationPreservesMenuCopyAndIcons' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared macOS menu bar presentation" \
  'macOS menu-bar icon visibility, dock-icon hiding storage/defaults, menu labels, empty-state copy, dynamic selection labels, and picker/checkmark symbols.*VoiceInkMenuBarPreference`/`VoiceInkMacOSMenuBarPresentation' \
  docs/ios-single-repo-migration.md

require_pattern \
  "core checks execute macOS shell backup export policy tests" \
  'UserDefaultsPreferencesTests\.testMacOSShellBackupPreferencesPreserveExportShape' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute macOS shell backup import policy tests" \
  'UserDefaultsPreferencesTests\.testMacOSShellBackupImportPlanPreservesOptionalFields' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS menu bar shell avoids raw menu bar preference keys" \
  '"(IsMenuBarOnly|ShowMenuBarIcon)"|AppDefaults\.Keys\.showMenuBarIcon|showMenuBarIconDefault' \
  VoiceInk/AppDefaults.swift \
  VoiceInk/MenuBarManager.swift \
  VoiceInk/VoiceInk.swift \
  VoiceInk/Views/MenuBarView.swift \
  VoiceInk/Views/Settings/SettingsView.swift \
  VoiceInk/Services/SystemInfoService.swift

reject_pattern \
  "macOS menu bar view avoids shell-owned menu copy and symbol policy" \
  '"(Toggle Recorder|Manage Models|Transcription Model:|None|AI Enhancement|Prompt:|No providers connected|AI Provider:|No models available|AI Model:|No devices available|Audio Input|Additional|Clipboard Context|Context Awareness|Retry Last Transcription|Copy Last Transcription|History|Permissions|Settings|Show Dock Icon|Hide Dock Icon|Hide Menu Bar Icon|Launch at Login|Check for Updates|Help and Support|Quit roma-just-talk|checkmark|chevron\.up\.chevron\.down)"' \
  VoiceInk/Views/MenuBarView.swift

require_pattern \
  "shared license preference policy lives in VoiceInkCore" \
  'VoiceInkLicenseStatusChangeRequest|notificationName = Notification\.Name\("licenseStatusChanged"\)|VoiceInkLicensePreference|requiresActivationKey|hasLaunchedBeforeKey|activationsLimitKey|deviceIdentifierKey|hasUsableStoredLicense|VoiceInkLicenseStartupPolicy|VoiceInkLicenseStartupPlan|VoiceInkLicenseState|VoiceInkLicenseLinks|purchaseURLString|purchaseDisplayURLString|managementPortalURLString|VoiceInkLicenseManagementPresentation|VoiceInkLicenseManagementResourceLink|VoiceInkLicenseManagementFeature|VoiceInkLicenseTrialBannerPresentation|VoiceInkLicenseTrialBanner|VoiceInkLicenseTrialBannerTone|VoiceInkLicenseRemovalPolicy|VoiceInkLicenseRemovalPlan|VoiceInkLicenseValidationPolicy|VoiceInkLicenseValidationFeedback|VoiceInkLicenseValidationApplicationPlan|VoiceInkLicenseServicePolicy|VoiceInkLicenseOperation|VoiceInkLicenseError|VoiceInkLicenseSecureStorageAccount|VoiceInkLicenseSecureStoragePolicy' \
  VoiceInkCore/Sources/VoiceInkCore/LicensePolicy.swift

require_pattern \
  "macOS app notifications use shared license status request name" \
  'licenseStatusChanged = VoiceInkLicenseStatusChangeRequest\.notificationName' \
  VoiceInk/Notifications/AppNotifications.swift

reject_pattern \
  "macOS app notification shell avoids duplicate license status request name" \
  'Notification\.Name\("licenseStatusChanged"\)' \
  VoiceInk/Notifications/AppNotifications.swift

require_pattern \
  "macOS Polar adapter uses shared license service policy" \
  'VoiceInkLicenseServicePolicy\.(requestURL|validationRequestBody|activationRequestBody|error)|VoiceInkLicensePreference\.deviceIdentifier|VoiceInkLicenseValidationResponse|VoiceInkLicenseActivationResult' \
  VoiceInk/Services/PolarService.swift

require_pattern \
  "macOS license manager uses shared secure license storage policy" \
  'VoiceInkLicenseSecureStorage(Account|Policy)\.(licenseKey|trialStartDate|activationId|isSyncable|trialStartTimestamp)' \
  VoiceInk/Services/LicenseManager.swift

require_pattern \
  "macOS license view model catches shared license errors" \
  'catch let licenseError as VoiceInkLicenseError|failureFeedback\(for: licenseError\)' \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "macOS license view model uses shared license preference" \
  'VoiceInkLicensePreference\.(hasUsableStoredLicense|activationsLimit|hasLaunchedBefore|saveHasLaunchedBefore|saveRequiresActivation|saveActivationsLimit)' \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "macOS license view model builds shared startup plans" \
  'VoiceInkLicenseStartupPolicy\.plan' \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "macOS license view model applies shared startup plans" \
  'VoiceInkLicenseStartupPlan' \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "macOS license view model delegates shared license-state affordance" \
  'licenseState\.canUseApp' \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "macOS license view model applies shared validation policy" \
  'VoiceInkLicenseValidationPolicy\.(emptyKeyFeedback|disabledLicenseFeedback|existingActivationSuccessPlan|activatedLicenseSuccessPlan|unlimitedLicenseSuccessPlan|failureFeedback|networkFailureFeedback|unexpectedFailureFeedback)|VoiceInkLicenseValidation(ApplicationPlan|Feedback)' \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "macOS license view model opens shared purchase link" \
  'VoiceInkLicenseLinks\.purchaseURL' \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "macOS license management view opens shared license links" \
  'VoiceInkLicenseLinks\.(purchaseURL|managementPortalURL)' \
  VoiceInk/Views/LicenseManagementView.swift

require_patterns \
  "macOS license management view uses shared presentation" \
  VoiceInk/Views/LicenseManagementView.swift \
  'VoiceInkLicenseManagementPresentation\.appVersionFallback' \
  'VoiceInkLicenseManagementPresentation\.heroSystemImageName' \
  'VoiceInkLicenseManagementPresentation\.heroTitle' \
  'VoiceInkLicenseManagementPresentation\.heroSubtitle' \
  'VoiceInkLicenseManagementPresentation\.appVersionText' \
  'VoiceInkLicenseManagementPresentation\.licensedResourceLinks' \
  'VoiceInkLicenseManagementPresentation\.lifetimeBadgeSystemImageName' \
  'VoiceInkLicenseManagementPresentation\.lifetimeBadgeTitle' \
  'VoiceInkLicenseManagementPresentation\.purchaseButtonTitle' \
  'VoiceInkLicenseManagementPresentation\.purchaseFeatures' \
  'VoiceInkLicenseManagementPresentation\.activationSectionTitle' \
  'VoiceInkLicenseManagementPresentation\.licenseKeyPlaceholder' \
  'VoiceInkLicenseManagementPresentation\.activateButtonTitle' \
  'VoiceInkLicenseManagementPresentation\.existingLicenseSectionTitle' \
  'VoiceInkLicenseManagementPresentation\.existingLicenseDescription' \
  'VoiceInkLicenseManagementPresentation\.managementPortalButtonTitle' \
  'VoiceInkLicenseManagementPresentation\.activeLicenseTitle' \
  'VoiceInkLicenseManagementPresentation\.activeLicenseBadgeText' \
  'VoiceInkLicenseManagementPresentation\.activeLicenseDeviceLimitText' \
  'VoiceInkLicenseManagementPresentation\.deactivationSectionTitle' \
  'VoiceInkLicenseManagementPresentation\.deactivateButtonTitle' \
  'VoiceInkLicenseManagementPresentation\.deactivateSystemImageName' \
  'VoiceInkLicenseManagementResourceLink' \
  'VoiceInkLicenseManagementResourceID'

reject_file VoiceInk/Views/LicenseView.swift

require_pattern \
  "macOS trial message opens shared purchase link" \
  'VoiceInkLicenseLinks\.purchaseURL' \
  VoiceInk/Views/Components/TrialMessageView.swift

require_pattern \
  "macOS metrics view uses shared trial banner presentation" \
  'VoiceInkLicenseTrialBannerPresentation\.banner' \
  VoiceInk/Views/MetricsView.swift

require_patterns \
  "macOS trial message view renders shared trial banner presentation" \
  VoiceInk/Views/Components/TrialMessageView.swift \
  'let presentation: VoiceInkLicenseTrialBanner' \
  'presentation\.systemImageName' \
  'presentation\.title' \
  'presentation\.message' \
  'presentation\.enterLicenseButtonTitle' \
  'presentation\.purchaseButtonTitle'

require_pattern \
  "macOS license view model applies shared removal policy" \
  'VoiceInkLicenseRemovalPolicy\.plan|VoiceInkLicenseRemovalPlan|plan\.(requiresActivationToSave|hasLaunchedBeforeToSave|activationsLimitToSave|shouldReloadStartupState)' \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "macOS diagnostics use shared license access policy" \
  'VoiceInkLicensePreference\.hasUsableStoredLicense' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "core checks execute license preference tests" \
  'LicensePolicyTests\.testLicensePreferenceKeysPreserveExistingStorageNames|LicensePolicyTests\.testLicenseStatusChangeRequestPreservesMacOSNotificationName|LicensePolicyTests\.testLicensePreferenceStorageRoundTripsNonSensitiveFlags|LicensePolicyTests\.testDeviceIdentifierCreatesAndStoresFallbackWhenMissing|LicensePolicyTests\.testStoredLicenseAccessPreservesExistingActivationRequirementPolicy|LicensePolicyTests\.testLicenseStartupPolicyPlansStoredLicenseAndTrialLifecycle|LicensePolicyTests\.testLicenseValidationPolicyPreservesMacOSFeedbackMessages|LicensePolicyTests\.testLicenseValidationApplicationPlansPreserveMacOSStorageWritesAndSuccessCopy|LicensePolicyTests\.testLicenseLinksPreservePurchaseAndManagementDestinations|LicensePolicyTests\.testLicenseManagementPresentationPreservesMacOSCopyAndResources|LicensePolicyTests\.testLicenseTrialBannerPresentationPreservesMacOSCopyAndThreshold|LicensePolicyTests\.testLicenseRemovalPolicyPreservesMacOSResetPlan|LicensePolicyTests\.testLicenseSecureStoragePolicyPreservesDeviceLocalAccountsAndTrialDateCodec|LicensePolicyTests\.testLicenseServicePolicyPreservesPolarEndpointsAndHeaders|LicensePolicyTests\.testLicenseHTTPStatusPolicyPreservesMacOSErrorMapping' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "migration checklist tracks shared license secure storage policy" \
  'license startup/trial lifecycle.*validation feedback/application planning.*purchase/management URL policy.*support-link metadata.*activation/deactivation copy.*trial-banner presentation.*VoiceInkLicenseStartupPolicy`/`VoiceInkLicenseValidationPolicy`/`VoiceInkLicenseLinks`/`VoiceInkLicenseManagementPresentation`/`VoiceInkLicenseTrialBannerPresentation`/`VoiceInkLicenseRemovalPolicy`/`VoiceInkLicenseSecureStorageAccount`/`VoiceInkLicenseSecureStoragePolicy' \
  docs/ios-single-repo-migration.md

reject_pattern \
  "macOS license shells avoid raw non-sensitive license preference keys" \
  '"(VoiceInkLicenseRequiresActivation|VoiceInkHasLaunchedBefore|VoiceInkActivationsLimit)"|extension UserDefaults|Calendar\.current\.dateComponents|daysSinceTrialStart|trialPeriodDays' \
  VoiceInk/Models/LicenseViewModel.swift \
  VoiceInk/Services/SystemInfoService.swift

reject_pattern \
  "macOS license view model avoids raw validation feedback copy" \
  '"(Please enter a license key|This license has been revoked or disabled\. Please contact support\.|License activated successfully!|License validated successfully!|License key not found\. Please double-check your key and try again\.|This license has reached its device limit\. Visit the License Management Portal to deactivate other devices\.|Could not reach the server\. Please check your internet connection and try again\.|An unexpected error occurred\. Please try again or contact support at support@tryvoiceink\.com)"|Server error \(' \
  VoiceInk/Models/LicenseViewModel.swift

reject_pattern \
  "macOS license management view avoids shell-owned presentation copy and resource links" \
  '"(VoiceInk Pro|Upgrade to Pro|Thank you for supporting VoiceInk|Transcribe what you say to text instantly with AI|Buy Once, Own Forever|Upgrade to VoiceInk Pro|Already have a license\?|Enter your license key|Activate|Already purchased\?|Manage your license and device activations|License Management Portal|License Active|Active|This license can be activated on up to|You can use VoiceInk Pro on all your personal devices|License Management|Deactivate License|Changelog|Discord|Email Support|Docs|Tip Jar|Priority Support|Lifetime Access|Free Updates|Multiple Devices)"|github\.com/Beingpax/VoiceInk/releases|discord\.gg/xryDy57nYD|tryvoiceink\.com/docs|buymeacoffee\.com/beingpax' \
  VoiceInk/Views/LicenseManagementView.swift

reject_pattern \
  "macOS trial banner views avoid shell-owned trial copy and icon policy" \
  '"(You have .* days left in your trial|Your trial has expired\. Upgrade to continue using VoiceInk|Trial Ending Soon|Trial Expired|Trial Active|Enter License|Buy License|exclamationmark\.triangle\.fill|xmark\.circle\.fill|info\.circle\.fill)"|enum MessageType|daysRemaining <= 2' \
  VoiceInk/Views/MetricsView.swift \
  VoiceInk/Views/Components/TrialMessageView.swift

reject_pattern \
  "license consumers avoid raw license links" \
  'https://tryvoiceink\.com/buy|https://polar\.sh/beingpax/portal/request' \
  VoiceInk/Models/LicenseViewModel.swift \
  VoiceInk/Views/LicenseManagementView.swift \
  VoiceInk/Views/Components/TrialMessageView.swift \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

reject_pattern \
  "macOS license view model avoids shell-owned removal reset policy" \
  'saveRequiresActivation\(false|saveHasLaunchedBefore\(false|saveActivationsLimit\(0|licenseState = \.trial\(daysRemaining: VoiceInkLicenseStartupPolicy\.defaultTrialPeriodDays\)|activationsLimit = 0' \
  VoiceInk/Models/LicenseViewModel.swift

reject_pattern \
  "macOS license manager avoids raw secure license storage policy" \
  'voiceink\.license\.|syncable: false|String\(date\.timeIntervalSince1970\)|Date\(timeIntervalSince1970:' \
  VoiceInk/Services/LicenseManager.swift

reject_pattern \
  "macOS Polar adapter avoids raw shared license service constants" \
  '"VoiceInkDeviceIdentifier"|"https://api\.polar\.sh"|"/v1/customer-portal/license-keys/(validate|activate)"|"6f3d781d-a630-4435-9dba-058486f2d936"|enum LicenseError|(^|[^A-Za-z0-9_])LicenseError\.' \
  VoiceInk/Services/PolarService.swift \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "shared Keychain service uses shared app identity" \
  'service = VoiceInkAppIdentity\.bundleIdentifier' \
  VoiceInkCore/Sources/VoiceInkCore/KeychainQuery.swift

require_pattern \
  "macOS dictionary CloudKit uses shared app identity container" \
  'VoiceInkAppIdentity\.iCloudContainerIdentifier' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "shared iOS audio recorder start-failure errors keep AudioRecorder domain component" \
  'errorDomainComponent = "AudioRecorder"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "shared iOS audio recorder start-failure errors use shared app identity domain" \
  'VoiceInkAppIdentity\.errorDomain\(component: errorDomainComponent\)' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "macOS app startup storage path uses shared macOS storage directories" \
  'VoiceInkMacOSStorageDirectories\.(modelsDirectory|appSupportDirectory)' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS recorder storage path uses shared macOS storage directories" \
  'VoiceInkMacOSStorageDirectories\.recordingsDirectory' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS audio retry storage path uses shared macOS storage directories" \
  'VoiceInkMacOSStorageDirectories\.appSupportDirectory' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "macOS audio import storage path uses shared macOS storage directories" \
  'VoiceInkMacOSStorageDirectories\.appSupportDirectory' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS transcription cleanup storage path uses shared macOS storage directories" \
  'VoiceInkMacOSStorageDirectories\.recordingsDirectory' \
  VoiceInk/Services/TranscriptionAutoCleanupService.swift

require_pattern \
  "macOS UI uses shared app identity presentation" \
  'VoiceInkAppIdentity\.(compactDisplayName|sidebarSubtitle|onboardingWindowTitle|storageFailureMessage)|VoiceInkMacOSMainViewItem\.(defaultSelection|visibleItems|emptySelectionTitle|item)' \
  VoiceInk/Views/ContentView.swift

reject_pattern \
  "macOS content view avoids shell-owned main navigation presentation" \
  'enum +ViewType|case +(metrics|transcribeAudio|history|models|enhancement|powerMode|permissions|audioInput|dictionary|settings|license) *=|"(home|manual stt|past|models|style|Power Mode|Permissions|Audio Input|Dictionary|Settings|VoiceInk Pro|Select a view)"|systemName: "(gauge\.medium|waveform\.circle\.fill|doc\.text\.fill|brain\.head\.profile|wand\.and\.stars|sparkles\.square\.fill\.on\.square|shield\.fill|mic\.fill|character\.book\.closed\.fill|gearshape\.fill|checkmark\.seal\.fill)"' \
  VoiceInk/Views/ContentView.swift

require_pattern \
  "macOS app startup uses shared app identity presentation" \
  'VoiceInkAppIdentity\.(compactDisplayName|storageFallbackWarningPresentation|storageFailurePresentation)|VoiceInkStorageStartupDiagnostics\.(modelContainerInitializationFailedMessage|modelContainerUnavailablePreconditionMessage)' \
  VoiceInk/VoiceInk.swift

require_patterns \
  "macOS app startup uses shared storage startup diagnostics" \
  VoiceInk/VoiceInk.swift \
  'VoiceInkStorageStartupDiagnostics\.modelContainerInitializationFailedMessage' \
  'VoiceInkStorageStartupDiagnostics\.modelContainerUnavailablePreconditionMessage'

reject_pattern \
  "macOS app startup avoids shell-only storage alert copy" \
  '"(Storage Warning|VoiceInk couldn.t access its storage location\. Your transcriptions will not be saved between sessions\.|Critical Storage Error|Quit|ModelContainer initialization failed|Unable to create ModelContainer\. SwiftData is unavailable\.)"' \
  VoiceInk/VoiceInk.swift

require_patterns \
  "core checks execute app identity storage startup tests" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'AppIdentityTests\.testMacOSStorageAlertPresentationPreservesStartupCopy' \
  'AppIdentityTests\.testStorageStartupDiagnosticsPreserveAppStartupCopy'

require_patterns \
  "core checks execute AppIntent presentation tests" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'AppIntentPresentationTests\.testMiniRecorderIntentPresentationPreservesMacOSShortcutCopy' \
  'AppIntentPresentationTests\.testMiniRecorderRequestPreservesMacOSNotificationNames'

require_pattern \
  "core checks execute macOS navigation request contract tests" \
  'AppIdentityTests\.testMacOSNavigationRequestPreservesDestinationContract|AppIdentityTests\.testMacOSMainViewItemsPreserveSidebarPresentation|AppIdentityTests\.testMacOSMainViewItemsMapNavigationDestinationsAndLegacyTitles|AppIdentityTests\.testMacOSFileTranscriptionRequestPreservesPayloadContract' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_patterns \
  "macOS windows use shared app identity presentation" \
  VoiceInk/WindowManager.swift \
  'VoiceInkMacOSWindowIdentity\.mainIdentifierRawValue' \
  'VoiceInkMacOSWindowIdentity\.onboardingIdentifierRawValue' \
  'VoiceInkMacOSWindowIdentity\.mainFrameAutosaveName' \
  'VoiceInkMacOSWindowIdentity\.mainTitle' \
  'VoiceInkMacOSWindowIdentity\.onboardingTitle'

require_patterns \
  "macOS history window uses shared window identity" \
  VoiceInk/HistoryWindowController.swift \
  'VoiceInkMacOSWindowIdentity\.historyIdentifierRawValue' \
  'VoiceInkMacOSWindowIdentity\.historyFrameAutosaveName' \
  'VoiceInkMacOSWindowIdentity\.historyTitle'

require_patterns \
  "shared macOS window identity lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkMacOSWindowIdentity' \
  'mainIdentifierRawValue' \
  'onboardingIdentifierRawValue' \
  'historyIdentifierRawValue' \
  'mainFrameAutosaveName' \
  'historyFrameAutosaveName' \
  'mainTitle' \
  'onboardingTitle' \
  'historyTitle'

require_patterns \
  "shared macOS log category identity lives in VoiceInkCore" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkMacOSLogCategory' \
  'logExporter = "LogExporter"' \
  'windowManager = "WindowManager"' \
  'apiKeyManager = "APIKeyManager"' \
  'keychainService = "KeychainService"' \
  'polarService = "PolarService"' \
  'licenseViewModel = "LicenseViewModel"'

require_pattern \
  "macOS window manager uses shared log category identity" \
  'Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem, category: VoiceInkMacOSLogCategory\.windowManager\)' \
  VoiceInk/WindowManager.swift

require_patterns \
  "macOS credential and license services use shared log category identity" \
  VoiceInk/Services/APIKeyManager.swift \
  'Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem, category: VoiceInkMacOSLogCategory\.apiKeyManager\)'

require_patterns \
  "macOS Keychain service uses shared log category identity" \
  VoiceInk/Services/KeychainService.swift \
  'Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem, category: VoiceInkMacOSLogCategory\.keychainService\)'

require_patterns \
  "macOS Polar service uses shared log category identity" \
  VoiceInk/Services/PolarService.swift \
  'Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem, category: VoiceInkMacOSLogCategory\.polarService\)'

require_patterns \
  "macOS license view model uses shared log category identity" \
  VoiceInk/Models/LicenseViewModel.swift \
  'Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem, category: VoiceInkMacOSLogCategory\.licenseViewModel\)'

require_pattern \
  "core checks execute macOS window identity test" \
  'AppIdentityTests\.testMacOSWindowIdentityPreservesIdentifiersTitlesAndFrameNames' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "core checks execute macOS log category identity test" \
  'AppIdentityTests\.testMacOSLogCategoriesPreserveDiagnosticsIdentity' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

reject_pattern \
  "macOS window shells avoid raw window identity strings" \
  '"(VoiceInkMainWindowFrame|VoiceInkHistoryWindowFrame|roma-just-talk - Transcription History)"|loggingSubsystem\)\.(mainWindow|onboardingWindow|historyWindow)' \
  VoiceInk/WindowManager.swift \
  VoiceInk/HistoryWindowController.swift

reject_pattern \
  "macOS window manager avoids shell-owned log category literal" \
  'category: "WindowManager"' \
  VoiceInk/WindowManager.swift

reject_pattern \
  "macOS credential and license shells avoid shell-owned log category literals" \
  'category: "(APIKeyManager|KeychainService|PolarService|LicenseViewModel)"' \
  VoiceInk/Services/APIKeyManager.swift \
  VoiceInk/Services/KeychainService.swift \
  VoiceInk/Services/PolarService.swift \
  VoiceInk/Models/LicenseViewModel.swift

require_pattern \
  "iOS note list uses shared app identity presentation" \
  'VoiceInkAppIdentity\.displayName' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "iOS onboarding presentation uses shared app identity presentation" \
  'VoiceInkAppIdentity\.(welcomeTitle|startUsingTitle)' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS transcription diagnostics use shared app identity subsystem" \
  'VoiceInkAppIdentity\.loggingSubsystem' \
  VoiceInk/Transcription

require_pattern \
  "macOS app Swift uses shared app identity subsystem" \
  'VoiceInkAppIdentity\.loggingSubsystem' \
  VoiceInk

require_pattern \
  "macOS local Whisper logging uses shared app identity subsystem" \
  'subsystem: VoiceInkAppIdentity\.loggingSubsystem' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "macOS local Whisper logging uses shared diagnostics category" \
  'category: VoiceInkWhisperRuntimeDiagnostics\.logCategory' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper logging uses shared app identity subsystem" \
  'subsystem: VoiceInkAppIdentity\.loggingSubsystem' \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "iOS local Whisper logging uses shared diagnostics category" \
  'category: VoiceInkWhisperRuntimeDiagnostics\.logCategory' \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "iOS local Whisper service logging uses shared app identity subsystem" \
  'VoiceInkIOSLogger\.localWhisper' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift

require_pattern \
  "iOS local model manager logging uses shared app identity subsystem" \
  'VoiceInkIOSLogger\.localModelManagement' \
  iOS/VoiceInk-ios/LocalModelManager.swift

reject_pattern \
  "iOS local Whisper and model shells avoid ad-hoc Logger construction" \
  'Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift \
  iOS/VoiceInk-ios/LocalModelManager.swift

reject_pattern \
  "iOS local Whisper shell avoids clone print diagnostics" \
  'print\(' \
  iOS/VoiceInk-ios/WhisperTranscriptionService.swift \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "iOS shell logging adapter uses shared app identity subsystem" \
  'Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem' \
  iOS/Shared/VoiceInkIOSLogger.swift

require_patterns \
  "VoiceInkCore owns iOS shell logging categories" \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift \
  'VoiceInkIOSLogCategory' \
  'iOSAppGroup' \
  'iOSAudioSession' \
  'iOSLocalWhisper' \
  'iOSLocalModelManagement'

require_pattern \
  "VoiceInkCore checks cover iOS shell logging categories" \
  'AppIdentityTests\.testIOSLogCategoriesPreserveDiagnosticsIdentity' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "iOS shell logging adapter uses shared local Whisper category" \
  'localWhisper = Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem, category: VoiceInkIOSLogCategory\.localWhisper\)' \
  iOS/Shared/VoiceInkIOSLogger.swift

require_pattern \
  "iOS shell logging adapter uses shared local model manager category" \
  'localModelManagement = Logger\(subsystem: VoiceInkAppIdentity\.loggingSubsystem, category: VoiceInkIOSLogCategory\.localModelManagement\)' \
  iOS/Shared/VoiceInkIOSLogger.swift

reject_pattern \
  "iOS shell logging adapter avoids shell-owned category literals" \
  '"iOS(App|AppGroup|AudioPlayback|AudioSession|Keyboard|LocalWhisper|LocalModelManagement|Notes|Recording|Settings)"' \
  iOS/Shared/VoiceInkIOSLogger.swift

require_pattern \
  "iOS app shell diagnostics route through shared iOS logger" \
  'VoiceInkIOSLogger\.(app|appGroup|audioPlayback|audioSession|localWhisper|localModelManagement|notes|recording|settings)' \
  iOS/VoiceInk-ios iOS/Shared

require_pattern \
  "iOS keyboard URL opener diagnostics route through shared iOS logger" \
  'VoiceInkIOSLogger\.keyboard' \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift

reject_pattern \
  "iOS app and keyboard shell avoid clone print diagnostics" \
  'print\(' \
  iOS/VoiceInk-ios \
  iOS/VoiceInkKeyboard \
  iOS/Shared

require_pattern \
  "migration checklist tracks shared diagnostic log export policy" \
  'diagnostic log session storage/range/header/filename/error policy.*VoiceInkDiagnosticLogExportPolicy' \
  docs/ios-single-repo-migration.md

require_pattern \
  "VoiceInkCore owns iOS record deep-link contract" \
  'public enum VoiceInkAppDeepLink|public init\?\(url: URL\)|VoiceInkAppIdentity\.iOSRecordDeepLinkURL' \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift

require_pattern \
  "VoiceInkCore checks cover iOS record deep-link contract" \
  'testIOSRecordDeepLinkContractRoundTripsThroughSharedCore' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_context_pattern_count_at_least \
  "iOS keyboard target depends on shared app identity package product" \
  'name = VoiceInkKeyboard;' \
  'B10000032FA0000000000001 /\* VoiceInkCore \*/' \
  1 \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_context_pattern_count_at_least \
  "iOS keyboard target links shared app identity package framework" \
  'E18B9A4A2E600F9F0068773A /\* Frameworks \*/' \
  'VoiceInkCore in Frameworks' \
  1 \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_context_pattern_count_at_least \
  "iOS unit-test target links shared core package framework" \
  'E168DF152E4B464C00F133D2 /\* Frameworks \*/' \
  'VoiceInkCore in Frameworks' \
  1 \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_context_pattern_count_at_least \
  "iOS UI-test target links shared core package framework" \
  'E168DF1F2E4B464C00F133D2 /\* Frameworks \*/' \
  'VoiceInkCore in Frameworks' \
  1 \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_patterns \
  "iOS UI launch smoke uses shared identity and onboarding copy" \
  iOS/VoiceInk-iosUITests/VoiceInk_iosUITests.swift \
  'import VoiceInkCore' \
  'VoiceInkAppIdentity\.displayName' \
  'VoiceInkIOSOnboardingPresentation\.welcome\.title'

reject_pattern \
  "local Whisper adapters avoid duplicate logging subsystem literal" \
  '"com\.prakashjoshipax\.voiceink"' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

reject_pattern \
  "macOS transcription diagnostics avoid duplicate logging subsystem literal" \
  '"com\.prakashjoshipax\.voiceink"' \
  VoiceInk/Transcription

reject_pattern \
  "macOS app Swift avoids duplicate logging subsystem literal" \
  '"com\.prakashjoshipax\.voiceink' \
  -g '*.swift' \
  VoiceInk

reject_pattern \
  "Swift UI avoids duplicate app identity literals" \
  '"(roma just talk|roma-just-talk|speak before hotkey|Welcome to roma just talk|Start Using roma just talk|roma-just-talk Onboarding)"' \
  VoiceInk/Views/ContentView.swift \
  VoiceInk/VoiceInk.swift \
  VoiceInk/WindowManager.swift \
  VoiceInk/HistoryWindowController.swift \
  iOS/VoiceInk-ios/NotesListView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift \
  iOS/VoiceInk-iosUITests/VoiceInk_iosUITests.swift

reject_pattern \
  "storage, Keychain, and platform shell paths avoid duplicate bundle identifier literals" \
  '"com\.prakashjoshipax\.VoiceInk"|appendingPathComponent\("com\.prakashjoshipax\.VoiceInk|iCloud\.com\.prakashjoshipax\.VoiceInk' \
  VoiceInkCore/Sources/VoiceInkCore/KeychainQuery.swift \
  VoiceInk/VoiceInk.swift \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/TranscriptionAutoCleanupService.swift \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_context_pattern_count_at_least \
  "iOS keyboard display name stays roma just talk" \
  'INFOPLIST_FILE = VoiceInkKeyboard/Info.plist;' \
  'INFOPLIST_KEY_CFBundleDisplayName = "roma just talk";' \
  2 \
  iOS/VoiceInk-ios.xcodeproj/project.pbxproj

require_plist_value \
  "iOS record deep-link scheme stays voiceink" \
  CFBundleURLTypes.0.CFBundleURLSchemes.0 \
  voiceink \
  iOS/VoiceInk-ios/Info.plist

require_plist_value \
  "iOS app App Group entitlement matches shared shell bridge" \
  'com\.apple\.security\.application-groups.0' \
  group.com.prakashjoshipax.VoiceInk \
  iOS/VoiceInk-ios/VoiceInk_ios.entitlements

require_plist_value \
  "iOS keyboard App Group entitlement matches shared shell bridge" \
  'com\.apple\.security\.application-groups.0' \
  group.com.prakashjoshipax.VoiceInk \
  iOS/VoiceInkKeyboard/VoiceInkKeyboard.entitlements

require_pattern \
  "VoiceInkCore owns iOS App Group recording state policy" \
  'VoiceInkAppGroupRecordingStatePolicy|staleRecordingInterval|UserDefaultsKey|VoiceInkAppGroupRecordingStateReadPlan|staleStateRepairMutationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_patterns \
  "VoiceInkCore owns iOS App Group recording diagnostics" \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift \
  'VoiceInkAppGroupRecordingDiagnostics' \
  'staleRecordingStateClearedMessage' \
  'updatedRecordingStateMessage'

require_patterns \
  "VoiceInkCore owns iOS recording coordination diagnostics" \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift \
  'VoiceInkIOSRecordingCoordinationDiagnostics' \
  'clearedStaleRecordingStateOnLaunchMessage' \
  'recordDeepLinkOpenedMessage' \
  'keyboardRecordingRequestOpenedMessage' \
  'recordingManagerInitializedMessage' \
  'keyboardStopRecordingRequestedMessage'

require_pattern \
  "VoiceInkCore checks cover iOS App Group recording state policy" \
  'testAppGroupRecordingStatePolicy(PreservesIOSStorageKeysAndTimeout|KeepsFreshRecordingActive|ClearsStaleRecording|DoesNotClearInactiveRecording)|testAppGroupRecordingState(WritePlansPreserveIOSBridgeWrites|MutationPlansPreserveIOSBridgeNotifications)|testAppGroupRecordingStateReadPlan(DoesNotRepairFreshRecording|OwnsStaleRepairMutation)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "VoiceInkCore checks cover iOS App Group recording diagnostics" \
  'testAppGroupRecordingDiagnosticsPreserveIOSLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "VoiceInkCore checks cover iOS recording coordination diagnostics" \
  'testIOSRecordingCoordinationDiagnosticsPreserveIOSLogCopy' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard recording timing" \
  'VoiceInkKeyboardRecordingTiming|appLaunchRecordingStartDelay|recordingStatusPollingInterval|openAppFallbackResetDelay' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore checks cover iOS keyboard recording timing" \
  'testKeyboardRecordingTimingPreservesIOSAppAndKeyboardDelays' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "VoiceInkCore owns iOS launch recording request policy" \
  'VoiceInkLaunchRecordingRequest(State|Action)' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore checks cover iOS launch recording request policy" \
  'testLaunchRecordingRequest(StartsImmediatelyWhenOnboardingIsComplete|DefersUntilOnboardingCompletes|NoOpsWhenNothingIsPending|ClearsPendingStateWhenRecordingCanStartNow)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard recording button presentation" \
  'VoiceInkKeyboardRecordingButtonPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard idle button title" \
  'title: " Record"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard recording button title" \
  'title: " Stop"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore uses shared iOS keyboard fallback app title" \
  'VoiceInkAppIdentity\.displayName' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard idle button icon" \
  'systemImageName: "mic\.fill"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard recording button icon" \
  'systemImageName: "stop\.fill"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard fallback button icon" \
  'systemImageName: "app"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore checks cover iOS keyboard recording button presentation" \
  'testKeyboardRecordingButtonPresentation(PreservesIOSCopyAndIcons|SelectsCurrentState)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift

require_patterns \
  "VoiceInkCore owns iOS keyboard open-app fallback policy and diagnostics" \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift \
  'VoiceInkKeyboardOpenAppPolicy' \
  'VoiceInkKeyboardOpenAppDiagnostics' \
  'actionAfterExtensionContextOpen' \
  'applicationAction' \
  'responderAction'

require_patterns \
  "VoiceInkCore checks cover iOS keyboard open-app fallback policy and diagnostics" \
  VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift \
  'testKeyboardOpenAppPolicyPreservesFallbackOrder' \
  'testKeyboardOpenAppDiagnosticsPreserveIOSLogCopy'

require_pattern \
  "iOS keyboard URL opener lives in shared shell adapter" \
  'VoiceInkKeyboardURLOpener' \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift

require_pattern \
  "iOS keyboard URL opener exposes one open-main-app entry point" \
  'openMainApp' \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift

require_patterns \
  "iOS keyboard URL opener adapts shared open-app policy and diagnostics" \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift \
  'VoiceInkKeyboardOpenAppPolicy' \
  'VoiceInkKeyboardOpenAppDiagnostics'

require_pattern \
  "iOS keyboard URL opener owns extension-context opening" \
  'extensionContext\??\.open' \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift

require_pattern \
  "iOS keyboard URL opener owns UIApplication fallback" \
  'UIApplication\.value' \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift

require_pattern \
  "iOS keyboard URL opener owns responder-chain fallback" \
  'sel_registerName\("openURL:"\)' \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift

reject_pattern \
  "iOS keyboard URL opener avoids shell-owned fallback diagnostic copy" \
  '"(extensionContext unavailable, trying alternative methods|Opened main app via extensionContext|extensionContext\.open failed, trying alternative methods|Opened main app via UIApplication\.open|UIApplication\.open failed|Attempted to open main app via responder chain|All URL opening methods failed)"' \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift

reject_pattern \
  "iOS keyboard URL opener avoids shell-owned open-result branching" \
  'if +success|guard +let +extensionContext' \
  iOS/Shared/VoiceInkKeyboardURLOpener.swift

require_pattern \
  "iOS keyboard controller delegates record deep-link opening to shared adapter" \
  'VoiceInkKeyboardURLOpener\.openMainApp' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

require_pattern \
  "iOS keyboard controller passes shared record deep-link to shared adapter" \
  'VoiceInkAppDeepLink\.record\.url' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

reject_pattern \
  "iOS keyboard controller avoids shell-owned URL opening fallback chain" \
  'extensionContext\??\.open|UIApplication\.value|sel_registerName\("openURL:"\)|openURL:' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

require_pattern \
  "iOS App Group bridge uses entitlement group" \
  'static let appGroupIdentifier = VoiceInkAppIdentity\.iOSAppGroupIdentifier' \
  iOS/Shared/VoiceInkAppGroupRecordingBridge.swift

require_pattern \
  "iOS App Group bridge adapts shared recording state policy" \
  'VoiceInkAppGroupRecordingStatePolicy\.(readPlan|stopRequestedMutationPlan|recordingStateMutationPlan)' \
  iOS/Shared/VoiceInkAppGroupRecordingBridge.swift

require_pattern \
  "iOS App Group coordinator applies shared stale repair mutation plan" \
  'staleStateRepairMutationPlan|VoiceInkAppGroupRecordingBridge\.apply\(mutationPlan' \
  iOS/Shared/AppGroupCoordinator.swift

require_pattern \
  "iOS App Group coordinator adapts shared recording diagnostics" \
  'VoiceInkAppGroupRecordingDiagnostics\.(staleRecordingStateClearedMessage|updatedRecordingStateMessage)' \
  iOS/Shared/AppGroupCoordinator.swift

require_pattern \
  "VoiceInkCore owns App Group recording mutation notification plan" \
  'VoiceInkAppGroupRecordingStateMutationPlan|darwinNotificationName' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "iOS App Group bridge tests use shared recording state policy" \
  'VoiceInkAppGroupRecordingStatePolicy\.(staleRecordingInterval|UserDefaultsKey|recordingStateMutationPlan)' \
  iOS/VoiceInk-iosTests/VoiceInk_iosTests.swift

reject_pattern \
  "iOS App Group bridge avoids shell-owned recording state policy" \
  'struct VoiceInkAppGroupRecordingState|staleRecordingInterval|enum UserDefaultsKey|static let (isRecording|lastRecordingTimestamp) = "|shouldClearStaleState' \
  iOS/Shared/VoiceInkAppGroupRecordingBridge.swift

reject_pattern \
  "iOS App Group coordinator avoids shell-owned stale-state repair mutation" \
  'updateRecordingState\(false\)' \
  iOS/Shared/AppGroupCoordinator.swift

reject_pattern \
  "iOS App Group coordinator avoids shell-owned recording diagnostic copy" \
  '"(Recording state appears stale, clearing it|Updated recording state:)' \
  iOS/Shared/AppGroupCoordinator.swift

reject_pattern \
  "iOS App Group bridge tests avoid shell-owned policy aliases" \
  'VoiceInkAppGroupRecordingBridge\.(staleRecordingInterval|UserDefaultsKey)' \
  iOS/VoiceInk-iosTests/VoiceInk_iosTests.swift

require_pattern \
  "VoiceInkCore app group mutation plan owns stop-recording Darwin notification" \
  'iOSStopRecordingDarwinNotificationName' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore app group mutation plan owns recording-state Darwin notification" \
  'iOSRecordingStateChangedDarwinNotificationName' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

reject_pattern \
  "iOS shared bridge avoids duplicate app identity literals" \
  '"(voiceink|record|group\.com\.prakashjoshipax\.VoiceInk|com\.prakashjoshipax\.VoiceInk\.(stopRecording|recordingStateChanged))"' \
  iOS/Shared/VoiceInkAppGroupRecordingBridge.swift

require_pattern \
  "VoiceInkCore owns app-local keyboard stop notification" \
  'iOSStopRecordingFromKeyboardNotificationName = Notification\.Name\("stopRecordingFromKeyboard"\)' \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift

require_pattern \
  "VoiceInkCore checks cover app-local keyboard stop notification" \
  'iOSStopRecordingFromKeyboardNotificationName' \
  VoiceInkCore/Tests/VoiceInkCoreTests/AppIdentityTests.swift

require_pattern \
  "iOS keyboard controller uses shared button presentation" \
  'VoiceInkKeyboardRecordingButtonPresentation\.(idle|recording|openAppFallback|current)' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard recording button tap policy" \
  'VoiceInkKeyboardRecordingButtonTap(Policy|Plan|Action)|plan\(isRecording:' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore checks cover iOS keyboard recording button tap policy" \
  'testKeyboardRecordingButtonTapPlan(StopsActiveRecordingAndRefreshesState|OpensAppWhenIdleWithoutRefreshingState)' \
  VoiceInkCore/Tests/VoiceInkCoreTests/RecordingStatePolicyTests.swift

require_pattern \
  "iOS keyboard controller delegates tap action policy to shared core" \
  'VoiceInkKeyboardRecordingButtonTapPolicy\.plan' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

require_pattern \
  "VoiceInkCore owns iOS keyboard stop-request policy" \
  'VoiceInkKeyboardStopRecordingRequest(Policy|Action)|action\(recordingState:' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "VoiceInkCore checks cover iOS keyboard stop-request policy" \
  'testKeyboardStopRecordingRequestHandlesOnlyActiveRecording' \
  VoiceInkCore/Tests/VoiceInkCoreTests/RecordingStatePolicyTests.swift

require_pattern \
  "iOS recording manager delegates keyboard stop-request policy to shared core" \
  'VoiceInkKeyboardStopRecordingRequestPolicy\.action' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS notes list delegates keyboard stop-request policy to shared core" \
  'VoiceInkKeyboardStopRecordingRequestPolicy\.action' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "iOS keyboard controller uses shared recording timing" \
  'VoiceInkKeyboardRecordingTiming\.(recordingStatusPollingInterval|openAppFallbackResetDelay)' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

require_pattern \
  "iOS app deep-link recording uses shared core deep-link contract" \
  'VoiceInkAppDeepLink\(url: url\)' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

require_pattern \
  "iOS keyboard recording opens shared core record deep-link URL" \
  'VoiceInkAppDeepLink\.record\.url' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

require_pattern \
  "iOS app deep-link recording uses shared keyboard timing" \
  'VoiceInkKeyboardRecordingTiming\.appLaunchRecordingStartDelay' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

require_pattern \
  "iOS app deep-link recording uses shared launch request policy" \
  'VoiceInkLaunchRecordingRequest(State|Action)|requestRecording\(hasCompletedOnboarding:|consumePendingRecordingIfReady\(hasCompletedOnboarding:' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

require_pattern \
  "iOS app startup uses shared storage startup diagnostics" \
  'VoiceInkStorageStartupDiagnostics\.iOSModelContainerCreationFailedMessage' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

reject_pattern \
  "iOS app startup avoids shell-owned storage startup diagnostics" \
  '"Could not create ModelContainer:' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

require_patterns \
  "iOS app launch recording adapts shared coordination diagnostics" \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift \
  'VoiceInkIOSRecordingCoordinationDiagnostics\.clearedStaleRecordingStateOnLaunchMessage' \
  'VoiceInkIOSRecordingCoordinationDiagnostics\.recordDeepLinkOpenedMessage' \
  'VoiceInkIOSRecordingCoordinationDiagnostics\.keyboardRecordingRequestOpenedMessage'

reject_pattern \
  "iOS app launch recording avoids shallow shared-policy wrappers" \
  'private func +(requestRecordingFromDeepLink|startPendingRecordingIfNeeded)\(' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

require_pattern \
  "iOS recording manager posts shared keyboard stop notification" \
  'VoiceInkAppIdentity\.iOSStopRecordingFromKeyboardNotificationName' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_patterns \
  "iOS recording manager adapts shared coordination diagnostics" \
  iOS/VoiceInk-ios/RecordingManager.swift \
  'VoiceInkIOSRecordingCoordinationDiagnostics\.recordingManagerInitializedMessage' \
  'VoiceInkIOSRecordingCoordinationDiagnostics\.keyboardStopRecordingRequestedMessage'

require_pattern \
  "iOS notes list observes shared keyboard stop notification" \
  'VoiceInkAppIdentity\.iOSStopRecordingFromKeyboardNotificationName' \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS keyboard controller avoids shell-owned button copy" \
  'setTitle\("( Record| Stop| Open roma just talk)"|UIImage\(systemName: "(mic\.fill|stop\.fill|app)"' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

reject_pattern \
  "iOS keyboard controller avoids shell-owned recording tap action policy" \
  'if +coordinator\.isRecording|else +\{[[:space:]]*openMainAppForRecording\(\)' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

reject_pattern \
  "iOS app shell avoids shell-owned keyboard stop-request active-state policy" \
  'guard +let +self *= *self, +self\.isRecording|if +recordingManager\.isRecording' \
  iOS/VoiceInk-ios/RecordingManager.swift \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS keyboard presentation avoids duplicate app display name literal" \
  '" Open roma just talk"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

reject_pattern \
  "iOS keyboard/app recording coordination avoids raw timing literals" \
  'withTimeInterval: +0\.5|deadline: \.now\(\) \+ (0\.5|2\.0)' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

reject_pattern \
  "iOS app deep-link recording avoids shell-owned deferred request flag" \
  'shouldStartRecordingAfterOnboarding|guard hasCompletedOnboarding else' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift

reject_pattern \
  "iOS recording coordination avoids shell-owned diagnostic copy" \
  '"(Cleared stale recording state on app launch|URL scheme triggered: open app for recording|App opened via keyboard extension - recording requested|RecordingManager initialized|Stop recording requested from keyboard extension)"' \
  iOS/VoiceInk-ios/VoiceInk_iosApp.swift \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "iOS shell does not redeclare keyboard stop notification" \
  'Notification\.Name\("stopRecordingFromKeyboard"\)|extension Notification\.Name' \
  iOS/Shared/AppGroupCoordinator.swift \
  iOS/VoiceInk-ios/NotesListView.swift \
  iOS/VoiceInk-ios/RecordingManager.swift

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

run_required "VoiceInkCoreChecks" run_voiceink_core_checks
run_required "VoiceInkAudioProof builds" run_voiceink_audio_proof_help

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

if [[ ! -d "$local_whisper_xcframework_path" ]]; then
  warn "local Whisper xcframework missing at $local_whisper_xcframework_path; full app builds remain blocked"
fi

if (( full_build == 1 )); then
  section "full-build prerequisites"
  if require_full_build_prerequisites; then
    run_required "macOS app build" xcodebuild -workspace VoiceInk.xcworkspace -scheme VoiceInk -configuration Debug build
    run_required "iOS app build" xcodebuild -workspace VoiceInk.xcworkspace -scheme VoiceInk-ios -destination "generic/platform=iOS Simulator" build
  else
    fail "full app build prerequisites"
  fi
else
  warn "full app builds skipped; pass --full-build when real Xcode, app dependencies, and iOS platform are installed"
fi

if (( failures > 0 )); then
  printf '\n%d required gate(s) failed; %d warning(s).\n' "$failures" "$warnings" >&2
  exit 1
fi

printf '\nAll required single-repo migration gates passed; %d warning(s).\n' "$warnings"
