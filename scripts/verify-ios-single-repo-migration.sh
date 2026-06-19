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

require_pattern() {
  local description="$1"
  local pattern="$2"
  local file="$3"

  section "$description"
  if ! rg -q "$pattern" "$file"; then
    fail "$description"
  fi
}

require_context_pattern_count_at_least() {
  local description="$1"
  local anchor="$2"
  local pattern="$3"
  local minimum_count="$4"
  local file="$5"

  section "$description"
  local count
  count="$(rg -A 20 "$anchor" "$file" | rg -c "$pattern" || true)"
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
require_file iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift
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
reject_file iOS/VoiceInk-ios/VoiceInk-ios
reject_file iOS/VoiceInk-ios/KeychainService.swift

section "obsolete iOS clone-side duplicates stay deleted"
for file in "${obsolete_ios_clone_files[@]}"; do
  reject_file "iOS/VoiceInk-ios/$file"
done

section "sibling iOS clone extras are documented obsolete files"
if [[ -d ../VoiceInk-iOS/VoiceInk-ios ]]; then
  sibling_ios_files="$(mktemp "${TMPDIR:-/tmp}/voiceink-sibling-ios.XXXXXX")"
  in_repo_ios_files="$(mktemp "${TMPDIR:-/tmp}/voiceink-in-repo-ios.XXXXXX")"
  actual_sibling_extras="$(mktemp "${TMPDIR:-/tmp}/voiceink-actual-sibling-extras.XXXXXX")"
  expected_sibling_extras="$(mktemp "${TMPDIR:-/tmp}/voiceink-expected-sibling-extras.XXXXXX")"

  relative_swift_file_list ../VoiceInk-iOS/VoiceInk-ios >"$sibling_ios_files"
  relative_swift_file_list iOS/VoiceInk-ios >"$in_repo_ios_files"
  comm -23 "$sibling_ios_files" "$in_repo_ios_files" >"$actual_sibling_extras"
  printf '%s\n' "${obsolete_ios_clone_files[@]}" | sort >"$expected_sibling_extras"

  if ! cmp -s "$actual_sibling_extras" "$expected_sibling_extras"; then
    printf 'Expected sibling-only Swift files:\n' >&2
    cat "$expected_sibling_extras" >&2
    printf 'Actual sibling-only Swift files:\n' >&2
    cat "$actual_sibling_extras" >&2
    rm -f "$sibling_ios_files" "$in_repo_ios_files" "$actual_sibling_extras" "$expected_sibling_extras"
    fail "sibling iOS clone has undocumented Swift extras"
  fi

  rm -f "$sibling_ios_files" "$in_repo_ios_files" "$actual_sibling_extras" "$expected_sibling_extras"
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
  iOS/VoiceInk-iosUITests

reject_pattern \
  "VoiceInkCore stays platform-neutral" \
  '^import (AppKit|UIKit|SwiftUI|SwiftData|AVFoundation|CoreAudio|AudioToolbox|ApplicationServices|Carbon|IOKit|FluidAudio|KeyboardKit|LLMKit|LLMkit|WhisperKit|whisper)$' \
  VoiceInkCore/Sources/VoiceInkCore \
  VoiceInkCore/Tests/VoiceInkCoreTests

reject_pattern \
  "iOS App Group keyboard shell stays out of VoiceInkCore" \
  '\b(VoiceInkAppGroup|VoiceInkAppDeepLink|AppGroupCoordinator|CFNotificationCenter|DarwinNotify)\b|voiceink://record|group\.com\.prakashjoshipax\.VoiceInk|com\.prakashjoshipax\.VoiceInk\.(stopRecording|recordingStateChanged)' \
  VoiceInkCore/Sources/VoiceInkCore \
  VoiceInkCore/Tests/VoiceInkCoreTests

reject_pattern \
  "API-key reference resolution stays in VoiceInkCore" \
  'resolveAPIKeyReference' \
  VoiceInk \
  iOS \
  VoiceInkCore/Sources/VoiceInkCore \
  VoiceInkCore/Tests/VoiceInkCoreTests

reject_pattern \
  "removed shared-type shell aliases stay deleted" \
  'typealias +(CustomPrompt|PromptIcon|RollingBufferPreloadMode|RollingBufferPreloadConfiguration|RollingBufferPowerState|RollingBufferPreloadPolicy|RollingBufferPreloadSettings|AIProvider|WhisperModelFile|RecordingState|RecorderAction|ShortcutPressContext|PowerModeValidationError|StreamingTranscriptionEvent|StreamingTranscriptionError)\b|PerformanceAnalyzer\.(AnalysisResult|ModelStat)' \
  VoiceInk \
  iOS

reject_pattern \
  "removed mode custom-prompt shim stays deleted" \
  'public var customPrompt' \
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
  VoiceInkCore/Sources/VoiceInkCore/TranscriptFileExport.swift

require_pattern \
  "shared transcript export owns localized time style" \
  'timeStyle = \.short' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptFileExport.swift

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
  "macOS TranscriptionModel adapts shared language selection facts" \
  'transcriptionLanguageSelectionFacts|VoiceInkTranscriptionLanguageSelectionFacts' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "iOS language settings uses shared language presentation" \
  'VoiceInkTranscriptionLanguagePresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "macOS language picker avoids shell-only language display fallback" \
  'private func +currentLanguageDisplayName|\?\? "Unknown"' \
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
  "iOS language settings avoids shell-only language presentation copy" \
  '"Transcription Language"|"Language"' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS save button uses shared timestamped markdown export" \
  'VoiceInkTranscriptFileExport\.markdownContent\(for: textToSave\)' \
  VoiceInk/Views/Common/SaveIconButton.swift

reject_pattern \
  "macOS save button avoids shell-owned transcript export date formatting" \
  'DateFormatter|localizedString' \
  VoiceInk/Views/Common/SaveIconButton.swift

require_pattern \
  "shared recording state exposes active-recording predicate" \
  'var +isActivelyRecording: +Bool' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingStatePolicy.swift

require_pattern \
  "macOS recording engine uses shared active-recording predicate" \
  'recordingState\.isActivelyRecording' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recorder preview uses shared active-recording predicate" \
  'recordingState\.isActivelyRecording' \
  VoiceInk/Views/Recorder/MiniRecorderView.swift

require_pattern \
  "iOS recording manager uses shared active-recording predicate" \
  'recordingState\.isActivelyRecording' \
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
  "iOS audio recorder uses shared recording-start failure reason" \
  'VoiceInkRecordingAlertPresentation\.iOSRecorderStartReturnedFalseDescription' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "iOS recording start gate uses shared no-mode presentation" \
  'VoiceInkRecordingAlertPresentation\.noModesAvailableIfNeeded' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "macOS recording engine uses shared recording notification presentation" \
  'VoiceInkRecordingNotificationPresentation\.(noTranscriptionModelSelected|failedToStart)' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS recorder uses shared runtime failure notification presentation" \
  'VoiceInkRecordingNotificationPresentation\.runtimeFailure' \
  VoiceInk/Recorder.swift

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

require_pattern \
  "iOS settings mode rows use shared summary presentation" \
  'summaryPresentation' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS mode configuration uses shared form presentation" \
  'formPresentation|VoiceInkModeFormPresentation' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "shared iOS settings presentation lives in VoiceInkCore" \
  'VoiceInkSettingsPresentation|addModeButtonTitle|resetAllAppDataButtonTitle' \
  VoiceInkCore/Sources/VoiceInkCore/SettingsPresentation.swift

require_pattern \
  "iOS settings uses shared settings presentation" \
  'VoiceInkSettingsPresentation\.iOS|settingsPresentation\.(navigationTitle|modesSectionTitle|addModeButtonTitle|addActionSystemImageName|debugSectionTitle|resetAllAppDataButtonTitle|resetAllAppDataSystemImageName)' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS mode selection views avoid shell-only mode-count picker branching" \
  'modes\.count > 1|settings\.modes\.count > 1|modes\.first|settings\.modes\.first|!settings\.modes\.isEmpty' \
  iOS/VoiceInk-ios/RecordingSheetView.swift \
  iOS/VoiceInk-ios/NoteDetailView.swift

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
  "iOS mode configuration avoids shell-only form presentation copy" \
  '"(Mode Details|Mode Name|Transcription|Post-processing|Enable Post-processing|Provider|Prompt Template|Custom Prompt|Edit Mode|New Mode|Save|Model)"|Configure how the raw transcription should be processed and refined\.' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

reject_pattern \
  "iOS recording views avoid shell-only recording alert copy and OSStatus mapping" \
  'ActiveRecordingAlert|Microphone Access Denied|Microphone In Use|Recording Failed|No Modes Found|Please create a new mode in Settings before recording|Could not start recording:|561017449|NSOSStatusErrorDomain' \
  iOS/VoiceInk-ios/RecordingManager.swift \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS audio recorder avoids shell-only recording-start failure reason" \
  'Failed to start AVAudioRecorder|record\(\) method returned false|audio session is not configured correctly' \
  iOS/VoiceInk-ios/AudioRecorder.swift

reject_pattern \
  "recording behavior avoids raw active-state equality" \
  'recordingState == \.recording' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift \
  VoiceInk/Views/Recorder/MiniRecorderView.swift \
  iOS/VoiceInk-ios/RecordingManager.swift

reject_pattern \
  "macOS recording engine avoids shell-only start failure notification copy" \
  '"No AI Model Selected"|"Recording failed to start"' \
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
  "shared recording transcription draft lives in VoiceInkCore" \
  'VoiceInkRecordingTranscriptionDraft' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingTranscriptionDraft.swift

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
  "iOS live recording builds shared pending recording draft" \
  'VoiceInkRecordingTranscriptionDraft\.pending' \
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
  "macOS audio cleanup clears audio references through shared helper" \
  'deleteExistingAudioFileAndClearReference\(\)' \
  VoiceInk/Views/Settings/AudioCleanupManager.swift

reject_pattern \
  "macOS audio cleanup avoids shell-only delete-and-clear sequence" \
  'audioFileURL = nil' \
  VoiceInk/Views/Settings/AudioCleanupManager.swift

require_pattern \
  "iOS live recording uses shared PCM16 sample-rate policy" \
  'AVSampleRateKey: VoiceInkPCM16Audio\.mono16kSampleRate' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "iOS live recording uses shared PCM16 channel policy" \
  'AVNumberOfChannelsKey: VoiceInkPCM16Audio\.monoChannelCount' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "iOS live recording uses shared PCM16 bit-depth policy" \
  'AVLinearPCMBitDepthKey: VoiceInkPCM16Audio\.bitsPerSample' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "iOS live recording uses shared PCM16 endian policy" \
  'AVLinearPCMIsBigEndianKey: VoiceInkPCM16Audio\.isBigEndian' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "iOS live recording uses shared PCM16 sample-type policy" \
  'AVLinearPCMIsFloatKey: VoiceInkPCM16Audio\.isFloatingPoint' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "iOS live recording uses shared audio-meter history policy" \
  'VoiceInkAudioMeterLevel\.boundedHistory' \
  iOS/VoiceInk-ios/AudioRecorder.swift

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
  "shared audio-meter visualizer accessibility label lives in VoiceInkCore" \
  'VoiceInkAudioMeterLevel|visualizerAccessibilityLabel' \
  VoiceInkCore/Sources/VoiceInkCore/AudioMeterLevel.swift

require_pattern \
  "iOS audio visualizer uses shared accessibility label" \
  'VoiceInkAudioMeterLevel\.visualizerAccessibilityLabel' \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

reject_pattern \
  "iOS live recording avoids shell-only audio-meter history limit" \
  'levelsHistory\.count >|removeFirst\(self\.levelsHistory\.count -|0\.\.<40' \
  iOS/VoiceInk-ios/AudioRecorder.swift \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

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
  'VoiceInkAudioInputMode|VoiceInkAudioInputPriorityDevice|VoiceInkAudioInputPriorityPolicy|VoiceInkAudioInputPriorityMoveDirection|firstAvailablePriorityDeviceID|reindexed|defaultMode|iconSystemName' \
  VoiceInkCore/Sources/VoiceInkCore/AudioInputPriorityPolicy.swift

require_pattern \
  "shared macOS audio input settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSAudioInputSettingsPresentation|heroTitle|prioritizedDevicesDescription|priorityDisplayText' \
  VoiceInkCore/Sources/VoiceInkCore/AudioInputPriorityPolicy.swift

require_pattern \
  "macOS audio device manager uses shared input mode" \
  'VoiceInkAudioInputMode|\.defaultMode|VoiceInkAudioInputMode\(rawValue:' \
  VoiceInk/Services/AudioDeviceManager.swift

require_pattern \
  "macOS audio device manager uses shared input priority policy" \
  'VoiceInkAudioInputPriorityDevice|VoiceInkAudioInputPriorityPolicy\.(addDevice|removeDevice|reindexed|sortedDevices|firstAvailablePriorityDeviceID)' \
  VoiceInk/Services/AudioDeviceManager.swift

require_pattern \
  "macOS audio input settings uses shared mode and priority policy" \
  'VoiceInkAudioInputMode\.allCases|VoiceInkAudioInputPriorityPolicy\.(sortedDevices|moveDevice)|VoiceInkAudioInputPriorityDevice|mode\.(title|iconSystemName|description)|VoiceInkMacOSAudioInputSettingsPresentation\.macOS|presentation\.(heroTitle|activeStatusTitle|priorityDisplayText)' \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift

reject_pattern \
  "macOS audio input avoids shell-only mode and priority policy" \
  'enum +AudioInputMode|"(System Default|Custom Device|Prioritized|Use your Mac'\''s default input|Select a specific input device|Set up device priority order)"|return "(display|mic\.circle\.fill|list\.number)"|struct +PrioritizedDevice|prioritizedDevices\.sorted|sorted *\{ *\$0\.priority < \$1\.priority *\}|swapAt\(currentIndex|prioritizedDevices\.append|prioritizedDevices\.removeAll|map *\{ *\$0\.priority *\}\.max' \
  VoiceInk/Services/AudioDeviceManager.swift \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift

reject_pattern \
  "macOS audio input settings avoid shell-only presentation copy" \
  '"(Audio Input|Configure your microphone preferences|Input Mode|Current Device|No device available|Active|Available Devices|Refresh|Prioritized Devices|Devices will be used in order of priority\. If a device is unavailable, the next one will be tried\. If no prioritized device is available, the built-in microphone will be used\.|No prioritized devices|No additional devices available|No Audio Devices|Connect an audio input device to get started|Unavailable)"|"waveform"|"wave\.3\.right"|"arrow\.clockwise"|"mic\.slash\.circle\.fill"|"exclamationmark\.triangle"|"plus\.circle\.fill"|"minus\.circle\.fill"|"chevron\.up"|"chevron\.down"|Text\("-"\)|Text\("\\\(\(priority \+ 1\)\\\)"\)' \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift

reject_pattern \
  "iOS note views avoid shell-only transcript presentation wrappers" \
  'private var +(transcriptText|statusBadgeText|relativeTimestamp|displayedTranscriptText|transcriptionStatusTitle) *:' \
  iOS/VoiceInk-ios/NoteRowView.swift \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "shared date presentation owns macOS detail timestamp format" \
  'abbreviatedTimestamp' \
  VoiceInkCore/Sources/VoiceInkCore/DatePresentation.swift

require_pattern \
  "shared date presentation owns macOS history timestamp format" \
  'compactTimestamp' \
  VoiceInkCore/Sources/VoiceInkCore/DatePresentation.swift

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
  "shared transcript status presentation policy lives in VoiceInkCore" \
  'VoiceInkTranscriptStatusPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared transcript status metadata lives in VoiceInkCore" \
  'panelSystemImageName|shouldShowInlineProgress|shouldShowBadge|Tone' \
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
  "shared transcript detail presentation copy lives in VoiceInkCore" \
  'noteDetailNavigationTitle|transcriptTitle|copyTranscriptSystemImageName|retranscribingDisplayText|retryTranscriptionButtonTitle|retryTranscriptionSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "shared last-transcription notification copy lives in VoiceInkCore" \
  'noTranscriptionAvailableTitle|lastTranscriptionCopiedTitle|failedToCopyTranscriptionTitle|cannotRetryTitle|retryFailedTitle' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

require_pattern \
  "iOS note row uses shared transcript status presentation" \
  'VoiceInkTranscriptPresentation\.statusPresentation' \
  iOS/VoiceInk-ios/NoteRowView.swift

require_pattern \
  "iOS note row uses shared transcript status metadata" \
  'shouldShowInlineProgress|shouldShowBadge|\.tone' \
  iOS/VoiceInk-ios/NoteRowView.swift

require_pattern \
  "iOS note detail uses shared transcript status presentation" \
  'VoiceInkTranscriptPresentation\.statusPresentation' \
  iOS/VoiceInk-ios/NoteDetailView.swift

require_pattern \
  "iOS note detail uses shared transcript status metadata" \
  'panelSystemImageName|\.tone' \
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

require_pattern \
  "shared history presentation owns macOS delete alert copy" \
  'deleteConfirmationTitle = "Delete Selected Items\?"|deleteConfirmationPrimaryButtonTitle = "Delete"|deleteConfirmationCancelButtonTitle = "Cancel"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptPresentation.swift

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

require_pattern \
  "macOS history views use shared delete alert copy" \
  'VoiceInkHistoryPresentation\.deleteConfirmation(Title|PrimaryButtonTitle|CancelButtonTitle)' \
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
  "macOS history views avoid duplicate delete-confirmation pluralization copy" \
  'This action cannot be undone\. Are you sure you want to delete|selectedTranscriptions\.count == 1 \? "" : "s"' \
  VoiceInk/Views/History/TranscriptionHistoryView.swift \
  VoiceInk/Views/History/InlineHistoryView.swift

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
  'note\.transcriptionStatus *[!=]= *\.(pending|failed|completed|canceled)|transcriptionStatus\.needsTranscription|VoiceInkTranscriptPresentation\.status(Title|BadgeText)|statusPresentation\??\.is(Failure|Processing)' \
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

require_pattern \
  "shared provider API-key verification progress presentation lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyVerificationProgress|macOSVerifyButtonTitle|iOSResultFeedback|effectiveSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key verification application plan lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyVerificationApplicationPlan|verificationApplicationPlan' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "shared provider API-key form presentation lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyFormPresentation|apiKeyFormPresentation|saveButtonSystemImageName|verifyButtonSystemImageName|consoleLeadingSystemImageName|consoleTrailingSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderCatalog.swift

require_pattern \
  "iOS API-key view uses shared verification progress presentation" \
  'VoiceInkProviderAPIKeyVerificationProgress|verificationProgress|iOSVerifiedKeyFeedback|iOSResultFeedback|effectiveSystemImageName' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS API-key view uses shared verification application plan" \
  'verificationApplicationPlan|VoiceInkProviderAPIKeyDraft[[:space:]]*\.[[:space:]]*missingVerificationCandidatePlan' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "iOS API-key view uses shared form presentation" \
  'apiKeyFormPresentation|VoiceInkProviderAPIKeyFormPresentation|saveButtonSystemImageName|verifyButtonSystemImageName|consoleLeadingSystemImageName|consoleTrailingSystemImageName' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "shared API-key obfuscation fallback lives in VoiceInkCore" \
  'obfuscatedAPIKeyOrPlaceholder|obfuscatedAPIKeyPlaceholder' \
  VoiceInkCore/Sources/VoiceInkCore/SecretPresentation.swift

require_pattern \
  "shared provider API-key list row presentation lives in VoiceInkCore" \
  'VoiceInkProviderAPIKeyListRowPresentation|listRowPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/ProviderAPIKeyState.swift

require_pattern \
  "iOS API-key list uses shared row presentation" \
  'apiKeyListRowPresentation' \
  iOS/VoiceInk-ios/APIKeysView.swift \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "shared Keychain query and data-store policy lives in VoiceInkCore" \
  'VoiceInkKeychainQuery|VoiceInkKeychainDataStore|SecItem(Add|CopyMatching|Delete)' \
  VoiceInkCore/Sources/VoiceInkCore/KeychainQuery.swift

require_pattern \
  "macOS Keychain adapter uses shared data-store policy" \
  'VoiceInkKeychainDataStore\.(saveData|loadData|delete|exists)' \
  VoiceInk/Services/KeychainService.swift

require_pattern \
  "iOS API-key settings use shared data-store policy directly" \
  'VoiceInkKeychainDataStore\.(saveData|loadData|delete)' \
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
  "macOS local Whisper uses shared runtime policy" \
  'VoiceInkWhisperRuntimeConfiguration\.current' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper uses shared runtime policy" \
  'VoiceInkWhisperRuntimeConfiguration\.current' \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "shared local Whisper context runtime plan lives in VoiceInkCore" \
  'VoiceInkWhisperContextRuntimePlan|useGPU: Bool\?|flashAttention: Bool\?' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperRuntimeDefaults.swift

require_pattern \
  "macOS local Whisper uses shared context runtime plan" \
  'VoiceInkWhisperContextRuntimePlan\.current' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper uses shared context runtime plan" \
  'VoiceInkWhisperContextRuntimePlan\.current' \
  iOS/VoiceInk-ios/LibWhisper.swift

reject_pattern \
  "local Whisper adapters avoid shell-only context runtime policy" \
  'params\.(use_gpu|flash_attn) = (false|true)|#if targetEnvironment\(simulator\)' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

require_pattern \
  "shared local Whisper diagnostics live in VoiceInkCore" \
  'VoiceInkWhisperRuntimeDiagnostics|logCategory = "WhisperContext"|simulatorCPUModeMessage = "Running on the simulator, using CPU"|metalFlashAttentionMessage = "Flash attention enabled for Metal"|vadBundleModelLoadedMessage = "VAD model loaded from bundle resources"' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperRuntimeDefaults.swift

require_pattern \
  "macOS local Whisper uses shared diagnostics" \
  'VoiceInkWhisperRuntimeDiagnostics\.(logCategory|simulatorCPUModeMessage|metalFlashAttentionMessage|vadBundleModelLoadedMessage)' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper uses shared diagnostics" \
  'VoiceInkWhisperRuntimeDiagnostics\.(logCategory|simulatorCPUModeMessage|metalFlashAttentionMessage|vadBundleModelLoadedMessage)' \
  iOS/VoiceInk-ios/LibWhisper.swift

reject_pattern \
  "local Whisper adapters avoid duplicate shared diagnostics literals" \
  '"(WhisperContext|Running on the simulator, using CPU|Flash attention enabled for Metal|VAD model loaded from bundle resources)"' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift \
  iOS/VoiceInk-ios/LibWhisper.swift

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
  "shared Whisper model download progress policy lives in VoiceInkCore" \
  'VoiceInkWhisperModelDownloadProgress|VoiceInkWhisperModelDownloadState' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model download state policy lives in VoiceInkCore" \
  'VoiceInkWhisperModelDownloadState' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model download row presentation lives in VoiceInkCore" \
  'VoiceInkWhisperModelDownloadRowPresentation|rowPresentation|actionSystemImageName|downloadButtonSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model operation alert presentation lives in VoiceInkCore" \
  'VoiceInkWhisperModelOperationAlertPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "shared Whisper model operation confirmation presentation lives in VoiceInkCore" \
  'VoiceInkWhisperModelOperationConfirmationPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

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
  'enum VoiceInkModelManagementPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/ModelManagementPresentation.swift

require_pattern \
  "shared Whisper compact download status text lives in VoiceInkCore" \
  'compactStatusText' \
  VoiceInkCore/Sources/VoiceInkCore/WhisperModelDownloadProgress.swift

require_pattern \
  "macOS Whisper downloads use shared progress keys" \
  'VoiceInkWhisperModelDownloadProgress\.(mainProgressKey|coreMLProgressKey)' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

require_pattern \
  "macOS Whisper model card uses shared download-state predicate" \
  'VoiceInkWhisperModelDownloadProgress\.isMacOSDownloading' \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift

require_pattern \
  "macOS model cards use shared compact download status copy" \
  'VoiceInkWhisperModelDownloadProgress\.compactDownloadingStatusText' \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift

require_pattern \
  "macOS Whisper download progress view uses shared progress presentation" \
  'VoiceInkWhisperModelDownloadProgress\.macOS' \
  VoiceInk/Transcription/Whisper/WhisperModelManager.swift

require_pattern \
  "macOS model management uses shared filter presentation" \
  'VoiceInkModelManagementFilter\.allCases|filter\.title' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift

require_pattern \
  "macOS TranscriptionModel adapts shared model-management facts" \
  'modelManagementFacts|VoiceInkModelManagementModelFacts|modelManagementCategory' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS model management uses shared filter membership" \
  'selectedFilter\.includes|sortRank\(forModelName:|modelManagementFacts\(for:' \
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
  'VoiceInkModelManagementPresentation\.(importLocalModelTitle|customModelsLimitationText)' \
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
  "iOS local model management uses shared download state" \
  'VoiceInkWhisperModelDownloadState\.simple' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model management uses shared operation confirmation presentation" \
  'VoiceInkWhisperModelOperationConfirmationPresentation|downloadConfirmation|deleteConfirmation' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model management uses shared compact download status text" \
  '\.progress\.compactStatusText' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model management uses shared model row presentation" \
  'rowPresentation|actionSystemImageName' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift

require_pattern \
  "iOS local model manager uses shared operation alert presentation" \
  'VoiceInkWhisperModelOperationAlertPresentation|\.(downloadFailed|serverErrorDuringDownload|noFileReceived|saveFailed)' \
  iOS/VoiceInk-ios/LocalModelManager.swift

require_pattern \
  "iOS local model deletion uses shared operation alert presentation" \
  '\.deleteFailed' \
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
  "iOS onboarding uses shared download state" \
  'VoiceInkWhisperModelDownloadState\.simple' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared operation confirmation presentation" \
  'VoiceInkWhisperModelOperationConfirmationPresentation|downloadConfirmation' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared compact download status text" \
  '\.progress\.compactStatusText' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "iOS onboarding uses shared model row presentation" \
  'rowPresentation|actionSystemImageName|downloadButtonSystemImageName' \
  iOS/VoiceInk-ios/OnboardingView.swift

require_pattern \
  "shared iOS onboarding presentation lives in VoiceInkCore" \
  'VoiceInkIOSOnboardingPresentation|VoiceInkOnboardingFeaturePresentation|VoiceInkOnboardingStepPresentation|appIconFallbackSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "iOS onboarding uses shared onboarding presentation" \
  'VoiceInkIOSOnboardingPresentation\.(appIconFallbackSystemImageName|welcome|modelDownload|ready)' \
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
  "shared macOS model-download onboarding presentation lives in VoiceInkCore" \
  'VoiceInkMacOSOnboardingPresentation|VoiceInkMacOSOnboardingModelDownloadPresentation|modelDownload|speedLabel|ramLabel|buttonTitle' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS model-download onboarding uses shared presentation" \
  'VoiceInkMacOSOnboardingPresentation\.modelDownload|presentation\.(title|subtitle|speedLabel|accuracyLabel|ramLabel)|buttonTitle\(isModelSet:' \
  VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift

reject_pattern \
  "macOS model-download onboarding avoids shell-only presentation copy" \
  '"(Download AI Model|We'\''ll download the optimized model to get you started\.|Downloading\.\.\.|Set as Default|Download Model|Speed|Accuracy|RAM)"' \
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
  "shared macOS onboarding permission presentation lives in VoiceInkCore" \
  'VoiceInkMacOSOnboardingPermissionPresentation|VoiceInkMacOSOnboardingPermissionKind|relaunchRequiredMessage|canSkipWhenNotGranted|buttonTitle' \
  VoiceInkCore/Sources/VoiceInkCore/OnboardingPresentation.swift

require_pattern \
  "macOS onboarding permissions use shared permission presentation" \
  'VoiceInkMacOSOnboardingPermissionPresentation\.all|canSkipWhenNotGranted|buttonTitle\(isGranted:|screenContextInfoMessage' \
  VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift

reject_pattern \
  "macOS onboarding permissions avoid shell-only permission presentation copy" \
  'struct +OnboardingPermission[[:space:]:{]|enum +PermissionType|"(Microphone Access|Microphone Selection|Accessibility Access|Input Monitoring|Screen Context \(Optional\)|Keyboard Shortcut|Enable your microphone to start speaking and converting your voice to text instantly\.|Select the audio input device you want to use with roma-just-talk\.|Add roma-just-talk to Accessibility, then turn its switch on\.|Allow roma-just-talk to detect your recording shortcut while other apps are active\.|Enable screen context only if you want roma-just-talk to use visible text for transcript enhancement\.|Set up a keyboard shortcut to quickly access roma-just-talk from anywhere\.|Relaunch to Apply|Set Shortcut|Grant|Enable)"' \
  VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift

require_pattern \
  "shared macOS permission settings presentation lives in VoiceInkCore" \
  'VoiceInkMacOSPermissionSettingsPresentation|VoiceInkMacOSPermissionSettingsCardPresentation|headerIconSystemName|inputMonitoringCard|screenContextCard|relaunchRequiredMessage' \
  VoiceInkCore/Sources/VoiceInkCore/PermissionPresentation.swift

require_pattern \
  "macOS permissions settings uses shared presentation" \
  'VoiceInkMacOSPermissionSettingsPresentation\.(headerIconSystemName|inputMonitoringCard|microphoneCard|accessibilityCard|screenContextCard)|presentation\.buttonTitle\(requiresRelaunch:' \
  VoiceInk/Views/PermissionsView.swift

reject_pattern \
  "macOS permissions settings avoids shell-only permission presentation copy" \
  '"(App Permissions|Microphone and shortcut access are needed for recording\. Screen context is optional\.|Input Monitoring Access|Allow roma-just-talk to listen for your recording hotkey globally|Microphone Access|Allow roma-just-talk to record your voice for transcription|Accessibility Access|Add roma-just-talk to Accessibility, then turn its switch on|Screen Context \(Optional\)|Use visible screen text to improve transcript enhancement when you choose\.|Relaunch to Apply|Grant|Enable|If you already turned this on in System Settings, relaunch roma-just-talk to activate it\.)"|systemName: "arrow\.clockwise"|systemName: "checkmark\.seal\.fill"|systemName: "xmark\.seal\.fill"|systemName: "arrow\.right"' \
  VoiceInk/Views/PermissionsView.swift

reject_pattern \
  "iOS model download views avoid shell-only downloaded/progress state assembly" \
  'model\.isDownloaded\(in:|modelManager\.isDownloading\[[^]]+\] == true|modelManager\.downloadProgress\[[^]]+\]' \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

reject_pattern \
  "iOS model download views avoid raw download-state presentation branching" \
  '(downloadState|baseModelDownloadState)\.(isDownloaded|isDownloading|progress\.isActive|progress\.compactStatusText|progress\.percentText|progress\.fraction)|VoiceInkWhisperModelDownloadProgress\.downloadActionTitle' \
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
  '"(Model Settings|Default Model|Set as Default|No model selected|Import Local Model…|Only OpenAI-compatible transcription APIs are supported\.|Local Models|Manage Local Models|Cloud Models|Manage Cloud Models)"' \
  VoiceInk/Views/AI\ Models/ModelManagementView.swift \
  VoiceInk/Views/AI\ Models/FluidAudioModelCardView.swift \
  VoiceInk/Views/AI\ Models/CustomModelCardView.swift \
  VoiceInk/Views/AI\ Models/NativeModelCardView.swift \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  VoiceInk/Views/AI\ Models/WhisperModelCardView.swift \
  iOS/VoiceInk-ios/SettingsView.swift \
  iOS/VoiceInk-ios/LocalModelManagementView.swift \
  iOS/VoiceInk-ios/APIKeysView.swift

require_pattern \
  "macOS cloud API-key card uses shared draft policy" \
  'VoiceInkProviderAPIKeyDraft' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared verification progress presentation" \
  'VoiceInkProviderAPIKeyVerificationProgress|verificationProgress|macOSVerifyButtonTitle|macOSInlineFeedback' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared verification application plan" \
  'verificationApplicationPlan' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared stored-key verifier" \
  'verifyStoredAPIKeyDetailed\(keyToVerify, for: provider\)' \
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
  "shared custom cloud model backup record owns export/import shape" \
  'struct VoiceInkCustomCloudModelBackup' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "shared custom cloud model form presentation owns defaults and copy" \
  'VoiceInkCustomCloudModelFormPresentation|defaultAPIEndpoint|defaultModelName|keychainSaveFailureMessage|submitButtonSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

require_pattern \
  "macOS custom cloud model form uses shared presentation" \
  'VoiceInkCustomCloudModelFormPresentation\.macOS|presentation\.(defaultAPIEndpoint|defaultModelName|buttonTitle|title|compatibilityWarningText|displayNameFieldTitle|apiEndpointFieldTitle|apiKeyFieldTitle|modelNameFieldTitle|multilingualToggleTitle|cancelButtonTitle|submitButtonTitle|submitButtonSystemImageName|validationAlertTitle|validationAlertDismissButtonTitle|defaultModelDescription|keychainSaveFailureMessage)' \
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
  "macOS backup file uses shared custom cloud model backup record" \
  'VoiceInkCustomCloudModelBackup' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "macOS custom model export adapts to shared backup record" \
  'VoiceInkCustomCloudModelBackup\(model: \$0\)' \
  VoiceInk/Services/ImportExportService.swift

reject_pattern \
  "macOS backup types avoid shell-only custom model backup policy" \
  'struct +CustomModelBackup|apiEndpoint\.trimmingCharacters|modelName\.trimmingCharacters|if let apiKey, !apiKey\.isEmpty' \
  VoiceInk/Services/BackupTypes.swift

require_pattern \
  "shared custom prompt presentation owns icon catalog and copy" \
  'VoiceInkCustomPromptPresentation|iconSystemNames|promptGridHelpText|deletePromptConfirmationMessage|triggerSummary' \
  VoiceInkCore/Sources/VoiceInkCore/CustomPromptPresentation.swift

require_pattern \
  "macOS custom prompt cards use shared presentation" \
  'VoiceInkCustomPromptPresentation\.(triggerSummary|editActionTitle|deletePromptConfirmationTitle|deletePromptConfirmationMessage|deleteActionTitle|cancelActionTitle|addPromptTitle)' \
  VoiceInk/Models/CustomPrompt.swift

require_pattern \
  "macOS prompt editor uses shared presentation" \
  'VoiceInkCustomPromptPresentation\.(editorTitle|defaultIconSystemName|promptNamePlaceholder|promptInstructionsPlaceholder|useSystemTemplateTitle|startWithTemplateTitle|triggerWordPlaceholder|noTriggerWordsText|iconSystemNames)' \
  VoiceInk/Views/PromptEditorView.swift

require_pattern \
  "macOS prompt grids use shared presentation" \
  'VoiceInkCustomPromptPresentation\.(promptGridEmptyText|promptGridHelpText|addPromptHelpText)' \
  VoiceInk/Views/Components/PromptSelectionGrid.swift

require_pattern \
  "macOS enhancement prompt grid uses shared presentation" \
  'VoiceInkCustomPromptPresentation\.(promptGridEmptyText|promptGridHelpText)' \
  VoiceInk/Views/EnhancementSettingsView.swift

reject_pattern \
  "macOS custom prompt shell avoids local icon catalog" \
  'enum +PromptIcons|PromptIcons\.allCases|"hand\.thumbsup\.fill"' \
  VoiceInk/Models/CustomPrompt.swift \
  VoiceInk/Views/PromptEditorView.swift

reject_pattern \
  "macOS custom prompt shell avoids duplicate prompt presentation copy" \
  '"(Add New|No prompts available|Double-click to edit • Right-click for more options|Add new prompt|Edit Trigger Words|New Prompt|Edit Prompt|You can only customize the trigger words for system prompts\.|Prompt Name|Brief description|Enter your custom prompt instructions here\.\.\.|Use System Template|Trigger Words|Start with Template|Add trigger word|No trigger words added|Delete Prompt\\?|This action cannot be undone)"' \
  VoiceInk/Models/CustomPrompt.swift \
  VoiceInk/Views/PromptEditorView.swift \
  VoiceInk/Views/Components/PromptSelectionGrid.swift \
  VoiceInk/Views/EnhancementSettingsView.swift

require_pattern \
  "migration checklist tracks shared custom prompt presentation gate" \
  'macOS custom prompt icon catalog, prompt-card trigger summary, grid empty/help copy, editor labels/placeholders/help text, and delete confirmation copy route through `VoiceInkCustomPromptPresentation`' \
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
  "macOS filler-word insertion uses shared insert policy" \
  'VoiceInkFillerWords\.add\(' \
  VoiceInk/Transcription/Processing/FillerWordManager.swift

require_pattern \
  "iOS filler-word insertion uses shared insert policy" \
  'VoiceInkFillerWords\.add\(' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "platform filler-word insertion avoids shell-only insert-plan unpacking" \
  'VoiceInkFillerWords\.insertPlan\(|wordToInsert|duplicateWordMessage' \
  VoiceInk/Transcription/Processing/FillerWordManager.swift \
  iOS/VoiceInk-ios/AppSettings.swift

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
  "macOS audio cleanup settings use shared presentation" \
  'VoiceInkMacOSCleanupSettingsPresentation\.macOS|presentation\.(transcriptToggleTitle|audioRetentionOptions|audioCleanupResultMessage)' \
  VoiceInk/Views/Settings/AudioCleanupSettingsView.swift

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
  "shared word-replacement list presentation lives in VoiceInkCore" \
  'VoiceInkWordReplacementListPresentation|originalColumnTitle|editButtonHelp' \
  VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift

require_pattern \
  "iOS settings uses shared dictionary alert presentation" \
  'VoiceInkDictionaryAlertPresentation|dictionaryAlert|\.duplicateFillerWord|\.vocabulary|\.wordReplacement' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS settings uses shared dictionary settings presentation" \
  'VoiceInkDictionarySettingsPresentation\.iOS|dictionaryPresentation|wordReplacementArrowSystemImageName' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS filler-word settings uses shared dictionary alert presentation" \
  'VoiceInkDictionaryAlertPresentation|\.duplicateFillerWord' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift

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
  "macOS word-replacement info popover uses shared presentation" \
  'VoiceInkWordReplacementInfoPresentation\.macOS|infoPresentation|WordReplacementInfoExampleRow' \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

require_pattern \
  "macOS dictionary settings chrome uses shared dictionary settings presentation" \
  'VoiceInkDictionarySettingsPresentation\.macOS|dictionaryPresentation|section\.presentation' \
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
  "macOS dictionary list views avoid shell-only presentation copy" \
  '"(Vocabulary Words|Sort alphabetically|Remove word|Original|Replacement|Sort by original|Sort by replacement|Edit replacement|Remove replacement)"' \
  VoiceInk/Views/Dictionary/VocabularyView.swift \
  VoiceInk/Views/Dictionary/WordReplacementView.swift

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
  "macOS backup import uses shared word-replacement import plan" \
  'VoiceInkDictionaryPolicy\.wordReplacementBackupImportPlan\(' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import avoids shell-only word-replacement import planning" \
  'for \(original, replacement\) in replacements|VoiceInkDictionaryPolicy\.wordReplacementInsertPlan\(|plan\.errorMessage|plan\.shouldInsert|existingOriginalTexts\.append' \
  VoiceInk/Services/BackupImporter.swift

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

require_pattern \
  "macOS custom cloud empty-response error uses shared run error description" \
  'VoiceInkTranscriptionRunError\.noTranscriptionReturned\.errorDescription' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift

reject_pattern \
  "macOS cloud batch transcription avoids pre-normalized vocabulary terms" \
  'getCustomVocabularyTerms\(from: modelContext\)' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift \
  VoiceInk/Services/CustomVocabularyService.swift

reject_pattern \
  "macOS custom cloud avoids duplicate empty-response error copy" \
  'The API returned an empty or invalid response\.' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift

require_pattern \
  "shared AI enhancement vocabulary context normalizes post-processing terms" \
  'VoiceInkCustomVocabularyTerms\.normalized\(terms, for: \.postProcessingContext\)' \
  VoiceInkCore/Sources/VoiceInkCore/AIPrompts.swift

require_pattern \
  "shared run processor uses shared transcription run preparation" \
  'VoiceInkTranscriptionRunPreparation\.prepareRawText' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift

require_pattern \
  "macOS live recording uses shared transcription run preparation" \
  'VoiceInkTranscriptionRunPreparation\.prepareFilteredText' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS audio-file import uses shared transcription run preparation" \
  'VoiceInkTranscriptionRunPreparation\.prepareFilteredText' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS retry transcription uses shared transcription run preparation" \
  'VoiceInkTranscriptionRunPreparation\.prepareFilteredText' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "macOS audio-file import builds completed records through shared draft" \
  'VoiceInkCompletedTranscriptionDraft' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS retry transcription builds completed records through shared draft" \
  'VoiceInkCompletedTranscriptionDraft' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

reject_pattern \
  "macOS transcription run callers use shared post-processing skip decision" \
  'VoiceInkPostProcessingSkipPolicy\.shouldSkipPostProcessing' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "shared enhancement settings presentation lives in VoiceInkCore" \
  'VoiceInkEnhancementSettingsPresentation|shortEnhancementWordOptions|timeoutRetryOptions' \
  VoiceInkCore/Sources/VoiceInkCore/EnhancementSettingsPresentation.swift

require_pattern \
  "macOS enhancement settings use shared presentation" \
  'VoiceInkEnhancementSettingsPresentation\.macOS|presentation\.(skipShortEnhancementTitle|timeoutOptions|timeoutRetryOptions)' \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift

reject_pattern \
  "macOS enhancement settings avoid shell-only presentation copy and option ranges" \
  '"(Enhancement Settings|Close|Clipboard Context|Use clipboard text to understand context for better enhancement\.|Screen Context|Capture on-screen text to understand context for better enhancement\.|Context|Skip short transcriptions|Minimum words|Timeout duration|On timeout|Fail immediately|Retry|Request Timeout|Set how long to wait for the AI provider to respond\.|Shortcuts)"|ForEach\(1\.\.\.15|\[3, 5, 7, 10, 15, 20, 30, 40, 50, 60\]' \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift

require_pattern \
  "shared core owns transcription session route planning" \
  'VoiceInkTranscription(SessionRouteFacts|SessionRoutePlan)|VoiceInkTranscriptionStreamingAdapterKind' \
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
  "macOS session creation passes shared streaming adapter kind" \
  'streamingAdapterKind: streamingAdapterKind' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

require_pattern \
  "macOS streaming service uses shared streaming adapter kind" \
  'VoiceInkTranscriptionStreamingAdapterKind|streamingAdapterKind' \
  VoiceInk/Transcription/Streaming/StreamingTranscriptionService.swift

require_pattern \
  "shared core owns transcription runtime resource planning" \
  'VoiceInkTranscriptionRuntimeResourcePlan|VoiceInkTranscriptionRecordingStartupLoadAction' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRuntimeResourcePolicy.swift

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

require_pattern \
  "shared core owns transcription model availability policy" \
  'VoiceInkTranscriptionModelAvailability(Facts|Requirement)' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionModelAvailability.swift

require_pattern \
  "macOS model adapts shared transcription model availability facts" \
  'transcriptionModelAvailability(Facts|Requirement)' \
  VoiceInk/Models/TranscriptionModel.swift

require_pattern \
  "macOS transcription model manager uses shared availability facts" \
  'availabilityFacts\(for: .*\)\.isUsable|transcriptionModelAvailabilityFacts' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

require_pattern \
  "macOS transcription model manager uses shared selection resource action" \
  'modelSelectionResourceAction == \.clearLocalWhisperModelAndMarkLoaded' \
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

reject_pattern \
  "macOS transcription model manager avoids shell-owned provider availability routing" \
  'switch +model\.provider|model\.provider != \.whisper|CloudProviderRegistry\.provider\(for: model\.provider\)|case +\.nativeApple|case +\.custom' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

reject_pattern \
  "macOS session creation avoids shell-only streaming support wrapper" \
  'private func supportsStreaming\(model:' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

require_pattern \
  "macOS AI API-key view uses shared AI draft policy" \
  'VoiceInkAIEnhancementAPIKeyDraft' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "shared macOS AI API-key failure messages live in VoiceInkCore" \
  'missingVerificationCandidateMessage|invalidOrMissingBaseURLConfigurationMessage|unsupportedAPIKeyVerificationMessage' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI API-key view uses shared verification progress type" \
  'VoiceInkProviderAPIKeyVerificationProgress\.failure' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS AI API-key view uses shared verification feedback copy" \
  'macOSInlineFeedback' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS AI API-key view uses shared obfuscated-key fallback" \
  'VoiceInkSecretPresentation\.obfuscatedAPIKeyOrPlaceholder' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS AI service resolves keys through shared AI draft policy" \
  'VoiceInkAIEnhancementAPIKeyDraft' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service uses shared API-key failure messages" \
  'VoiceInkAIEnhancementProviderKind\.(missingVerificationCandidateMessage|invalidOrMissingBaseURLConfigurationMessage)|selectedProvider\.unsupportedAPIKeyVerificationMessage' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "shared AI enhancement credential-state policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementCredentialState|textEnhancementCredentialState' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI service credential-state selection uses shared policy" \
  'textEnhancementCredentialState' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS AI service Local CLI credential refresh uses shared policy" \
  'applyCredentialStateForSelectedProvider' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "shared AI enhancement default text model policy lives in VoiceInkCore" \
  'defaultTextEnhancementModel|defaultOllamaTextEnhancementModel|legacyOllamaServiceSelectedModelFallback|localCLITextEnhancementModel' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

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
  'legacyOllamaServiceSelectedModelFallback' \
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
  'textEnhancementRequestURL' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "shared AI enhancement refresh model-selection policy lives in VoiceInkCore" \
  'textEnhancementModelToSelectAfterRefresh' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI service refresh model selection uses shared policy" \
  'textEnhancementModelToSelectAfterRefresh' \
  VoiceInk/Services/AIEnhancement/AIService.swift

require_pattern \
  "macOS Ollama service refresh model selection uses shared policy" \
  'textEnhancementModelToSelectAfterRefresh' \
  VoiceInk/Services/OllamaService.swift

require_pattern \
  "shared AI enhancement execution route policy lives in VoiceInkCore" \
  'VoiceInkAIEnhancementExecutionRoute|textEnhancementExecutionRoute' \
  VoiceInkCore/Sources/VoiceInkCore/AIProviderCatalog.swift

require_pattern \
  "macOS AI enhancement service execution routing uses shared policy" \
  'textEnhancementExecutionRoute' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "shared AI chat request parameter planning lives in VoiceInkCore" \
  'VoiceInkAIChatRequestParameters|chatRequestParameters' \
  VoiceInkCore/Sources/VoiceInkCore/AIReasoningConfig.swift

require_pattern \
  "macOS AI enhancement request tuning uses shared policy" \
  'chatRequestParameters' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

require_pattern \
  "iOS post-processing request tuning uses shared policy" \
  'chatRequestParameters' \
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
  'currentModel == .*defaultTextEnhancementModel|models\.first!' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS Ollama service avoids duplicate refresh model-selection policy" \
  'models\.contains\(where: \{ \$0\.name == selectedModel \}\)|models\[0\]\.name' \
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
  "macOS AI enhancement service returns shared enhancement result" \
  'VoiceInkAIEnhancementResult' \
  VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

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
  "shared transcription paste output owns trial-expired prefix" \
  'trialExpiredPrefix = "Your trial has expired\. Upgrade to VoiceInk Pro at tryvoiceink\.com/buy"' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "shared transcription paste output owns trailing-space preference" \
  'VoiceInkAppendTrailingSpacePreference' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionPasteOutputPolicy.swift

require_pattern \
  "macOS transcription pipeline uses shared paste output policy" \
  'VoiceInkTranscriptionPasteOutputPolicy\.finalPastedText' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

reject_pattern \
  "macOS transcription pipeline avoids shell-only paste output policy" \
  'Your trial has expired|"AppendTrailingSpace"|textToPaste \+ \(appendSpace \? " " : ""\)' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS trailing-space settings use shared preference key" \
  'VoiceInkUserDefaultsKey\.appendTrailingSpace' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "migration checklist tracks shared paste output gate" \
  'macOS final paste text assembly routes trial-expired prefix and trailing-space storage through `VoiceInkTranscriptionPasteOutputPolicy`/`VoiceInkAppendTrailingSpacePreference`' \
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
  "macOS defaults register shared paste defaults" \
  'VoiceInkPastePreference\.registeredDefaults|VoiceInkPasteMethod\.migrateLegacyUserDefaultIfNeeded' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS diagnostics use shared paste preferences" \
  'VoiceInkPastePreference\.(shouldRestoreClipboardAfterPaste|clipboardRestoreDelay)|VoiceInkPasteMethod\.current' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS backup export uses shared paste preferences" \
  'VoiceInkPastePreference\.(shouldRestoreClipboardAfterPaste|clipboardRestoreDelay)' \
  VoiceInk/Services/ImportExportService.swift

require_pattern \
  "macOS backup import uses shared paste preferences" \
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

require_pattern \
  "migration checklist tracks shared paste preference gate" \
  'macOS paste method and clipboard restore settings route through `VoiceInkPasteMethod`/`VoiceInkPastePreference`' \
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
  "shared recording feedback preference owns macOS storage keys" \
  'systemMuteModeKey = "systemMuteMode"|isPauseMediaEnabledKey = "isPauseMediaEnabled"|isSoundFeedbackEnabledKey = "isSoundFeedbackEnabled"' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

require_pattern \
  "shared recording feedback preference preserves legacy mute boolean compatibility" \
  'legacyIsSystemMuteEnabledKey = "isSystemMuteEnabled"|saveSystemMuteEnabled' \
  VoiceInkCore/Sources/VoiceInkCore/RecordingFeedbackPreferences.swift

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
  "macOS defaults register shared recording feedback defaults" \
  'VoiceInkRecordingFeedbackPreference\.registeredDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS diagnostics use shared recording feedback preferences" \
  'VoiceInkRecordingFeedbackPreference\.(isSoundFeedbackEnabled|isPauseMediaEnabled|systemMuteMode|audioResumptionDelay)' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS settings uses shared system mute mode" \
  'VoiceInkSystemMuteMode\.allCases' \
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

require_pattern \
  "migration checklist tracks shared recording feedback preference gate" \
  'macOS recording feedback preferences route through `VoiceInkSystemMuteMode`/`VoiceInkRecordingFeedbackPreference`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared model runtime preference key lives in VoiceInkCore" \
  'prewarmModelOnWake = "PrewarmModelOnWake"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recorder preview preference key lives in VoiceInkCore" \
  'showLiveTextPreview = "showLiveTextPreview"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared model runtime preference module lives in VoiceInkCore" \
  'public enum VoiceInkModelRuntimePreference' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

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
  "macOS model settings observes shared model runtime key" \
  'VoiceInkUserDefaultsKey\.prewarmModelOnWake' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "macOS model settings observes shared recorder preview key" \
  'VoiceInkUserDefaultsKey\.showLiveTextPreview' \
  VoiceInk/Views/ModelSettingsView.swift

require_pattern \
  "macOS mini recorder observes shared recorder preview key" \
  'VoiceInkUserDefaultsKey\.showLiveTextPreview' \
  VoiceInk/Views/Recorder/MiniRecorderView.swift

require_pattern \
  "macOS notch recorder observes shared recorder preview key" \
  'VoiceInkUserDefaultsKey\.showLiveTextPreview' \
  VoiceInk/Views/Recorder/NotchRecorderView.swift

reject_pattern \
  "macOS model runtime shells avoid raw runtime preference keys" \
  '"(PrewarmModelOnWake|showLiveTextPreview)"' \
  VoiceInk/AppDefaults.swift \
  VoiceInk/Services/ModelPrewarmService.swift \
  VoiceInk/Views/ModelSettingsView.swift \
  VoiceInk/Views/Recorder/MiniRecorderView.swift \
  VoiceInk/Views/Recorder/NotchRecorderView.swift

require_pattern \
  "migration checklist tracks shared model runtime preference gate" \
  'macOS model prewarm and recorder transcript-preview preferences route through `VoiceInkModelRuntimePreference`/`VoiceInkRecorderPreviewPreference`' \
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
  "shared recording shortcut selection values live in VoiceInkCore" \
  'public enum VoiceInkRecordingShortcutSelection' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut mode values live in VoiceInkCore" \
  'public enum VoiceInkRecordingShortcutMode' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared recording shortcut preference module lives in VoiceInkCore" \
  'public enum VoiceInkRecordingShortcutPreference' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

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
  "shared recording shortcut preference saves middle-click delay" \
  'saveMiddleClickActivationDelay' \
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
  "macOS shortcut migration uses shared current shortcut selection keys" \
  'VoiceInkRecordingShortcutPreference\.selectionKey' \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "macOS shortcut migration uses shared current shortcut mode keys" \
  'VoiceInkRecordingShortcutPreference\.modeKey' \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "macOS shortcut migration uses shared shortcut selection default" \
  'VoiceInkRecordingShortcutPreference\.defaultSelection' \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "macOS shortcut migration uses shared shortcut mode default" \
  'VoiceInkRecordingShortcutPreference\.defaultMode' \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "macOS diagnostics use shared middle-click enabled preference" \
  'VoiceInkRecordingShortcutPreference\.isMiddleClickToggleEnabled' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS diagnostics use shared middle-click delay preference" \
  'VoiceInkRecordingShortcutPreference\.middleClickActivationDelay' \
  VoiceInk/Services/SystemInfoService.swift

reject_pattern \
  "macOS recording shortcut shells avoid raw current shortcut preference keys" \
  '"(primaryRecordingShortcut|secondaryRecordingShortcut|primaryRecordingShortcutMode|secondaryRecordingShortcutMode|isMiddleClickToggleEnabled|middleClickActivationDelay)"|enum +(Mode|ShortcutSelection)' \
  VoiceInk/AppDefaults.swift \
  VoiceInk/Services/SystemInfoService.swift \
  VoiceInk/Shortcuts/RecordingShortcutManager.swift \
  VoiceInk/Shortcuts/ShortcutMigration.swift

require_pattern \
  "migration checklist tracks shared recording shortcut preference gate" \
  'macOS recording shortcut selection/mode and middle-click preferences route through `VoiceInkRecordingShortcutSelection`/`VoiceInkRecordingShortcutMode`/`VoiceInkRecordingShortcutPreference`' \
  docs/ios-single-repo-migration.md

require_pattern \
  "shared transcription run result carries post-processing enhancement result" \
  'postProcessingResult: VoiceInkAIEnhancementResult\?' \
  VoiceInkCore/Sources/VoiceInkCore/TranscriptionRunProcessor.swift

require_pattern \
  "shared transcription run processor builds post-processing enhancement result" \
  'postProcessingResult = VoiceInkAIEnhancementResult' \
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

require_pattern \
  "macOS recorder enhancement stores request metadata from shared result" \
  'enhancement\.requestSystemMessage' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS audio-file import enhancement stores request metadata from shared result" \
  'enhancementResult: enhancement' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS retry enhancement stores request metadata from shared result" \
  'enhancementResult: enhancement' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "shared completed transcription draft stores request metadata from shared result" \
  'enhancementResult\.requestSystemMessage' \
  VoiceInkCore/Sources/VoiceInkCore/CompletedTranscriptionDraft.swift

require_pattern \
  "macOS re-enhance action stores request metadata from shared result" \
  'enhancement\.requestSystemMessage' \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS enhancement callers avoid tuple metadata and mutable service side reads" \
  'let \(enhancedText, enhancementDuration, promptName\)|lastSystemMessageSent|lastUserMessageSent|getAIService\(\)\.currentModel' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift \
  VoiceInk/Services/AudioFileTranscriptionManager.swift \
  VoiceInk/Services/AudioFileTranscriptionService.swift \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "shared transcription failure plan type lives in core" \
  'public struct VoiceInkTranscriptionRecordFailurePlan' \
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
  "macOS canceled transcription record uses shared canceled text" \
  'VoiceInkTranscriptPresentation\.canceledTranscriptionText' \
  VoiceInk/Models/Transcription.swift

reject_pattern \
  "macOS last-transcription shell avoids shared policy pass-through wrappers" \
  'private static func +isPasteable\(|static func +shouldFallback\(' \
  VoiceInk/Services/LastTranscriptionService.swift

require_pattern \
  "macOS last-transcription retry uses shared missing-audio error vocabulary" \
  'VoiceInkEngineError\.audioFileNotFound' \
  VoiceInk/Services/LastTranscriptionService.swift

require_pattern \
  "macOS last-transcription retry uses shared no-model error vocabulary" \
  'VoiceInkEngineError\.noTranscriptionModelSelected' \
  VoiceInk/Services/LastTranscriptionService.swift

require_pattern \
  "macOS last-transcription notifications use shared transcript presentation" \
  'VoiceInkTranscriptPresentation\.(noTranscriptionAvailableTitle|lastTranscriptionCopiedTitle|failedToCopyTranscriptionTitle|cannotRetryTitle|copiedToClipboardTitle|retryFailedTitle)' \
  VoiceInk/Services/LastTranscriptionService.swift

require_pattern \
  "macOS audio player retranscribe uses shared no-model error vocabulary" \
  'VoiceInkEngineError\.noTranscriptionModelSelected' \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS retry surfaces avoid shell-only no-model and missing-audio text" \
  'Cannot retry: Audio file not found|No transcription model selected' \
  VoiceInk/Services/LastTranscriptionService.swift \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS last-transcription notifications avoid shell-only copy" \
  '"No transcription available"|"Last transcription copied"|"Failed to copy transcription"|"Copied to clipboard"|"Cannot retry:|"Retry failed:' \
  VoiceInk/Services/LastTranscriptionService.swift

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

require_pattern \
  "shared audio playback timeline owns update cadence" \
  'updateInterval' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "shared audio playback presentation lives in VoiceInkCore" \
  'VoiceInkAudioPlaybackPresentation|timestampSystemImageName|durationSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/AudioPlaybackTimeline.swift

require_pattern \
  "macOS audio player uses shared playback-rate policy" \
  'VoiceInkAudioPlaybackRate' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "iOS audio player shell uses shared playback-rate policy" \
  'VoiceInkAudioPlaybackRate' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_pattern \
  "iOS audio player shell uses shared playback update cadence" \
  'VoiceInkAudioPlaybackTimeline\.updateInterval' \
  iOS/VoiceInk-ios/AudioPlayer.swift

require_pattern \
  "iOS audio player view uses shared playback-rate policy" \
  'VoiceInkAudioPlaybackRate' \
  iOS/VoiceInk-ios/AudioPlayerView.swift

require_pattern \
  "macOS audio player uses shared playback presentation" \
  'VoiceInkAudioPlaybackPresentation' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS audio player uses shared playback update cadence" \
  'VoiceInkAudioPlaybackTimeline\.updateInterval' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS audio player action status uses shared transcript presentation" \
  'VoiceInkTranscriptPresentation\.audioFile(ReEnhancement|Retranscription)(SuccessMessage|FailureMessage)' \
  VoiceInk/Views/AudioPlayerView.swift

require_pattern \
  "macOS audio player re-enhance guard uses shared post-processing presentation" \
  'VoiceInkPostProcessingFailurePresentation\.enhancementUnavailableMessage' \
  VoiceInk/Views/AudioPlayerView.swift

reject_pattern \
  "macOS audio player avoids shell-only action status and re-enhance guard copy" \
  '"Retranscription successful"|"Re-enhancement successful"|"Retranscription failed"|"Re-enhancement failed"|"AI Enhancement is not enabled or configured"' \
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
  "platform audio player views avoid duplicate loading and play-pause presentation" \
  '"Loading\.\.\."|"pause\.fill"|"play\.fill"|"calendar"|"waveform"' \
  VoiceInk/Views/AudioPlayerView.swift \
  iOS/VoiceInk-ios/AudioPlayerView.swift

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
  "macOS filler-word add button uses shared draft policy" \
  'VoiceInkFillerWords\.hasDraft\(newWord\)' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift

require_pattern \
  "iOS filler-word add button uses shared draft policy" \
  'VoiceInkFillerWords\.hasDraft\(newFillerWord\)' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS mode provider availability comes from shared provider-key state" \
  'VoiceInkProviderKind\.availableProviders' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "iOS mode transcription provider list uses settings adapter" \
  'settings\.availableProviders\(for: \.transcription\)' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

require_pattern \
  "iOS mode post-processing provider list uses settings adapter" \
  'settings\.availableProviders\(for: \.postProcessing\)' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

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

reject_pattern \
  "macOS cloud model card avoids shell-only streaming presentation and registry lookup" \
  'CloudProviderRegistry\.provider\(for: model\.provider\)|"Streaming"|"Buffer Preload"|active-recording streaming|Saved-file batch mode|Rolling buffer can pre-run|Rolling buffer preload disabled' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

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

require_pattern \
  "shared app settings reset state lives in VoiceInkCore" \
  'VoiceInkAppSettingsResetState|appSettingsResetState' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared app data reset file plan lives in VoiceInkCore" \
  'VoiceInkAppDataResetFilePlan' \
  VoiceInkCore/Sources/VoiceInkCore/AppDataReset.swift

require_pattern \
  "shared current-model preference remembers legacy macOS model key" \
  'legacyModelNameKey += +"CurrentModel"' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared current-model preference clears legacy macOS model key" \
  'removeObject\(forKey: legacyModelNameKey\)' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "macOS transcription model manager clears through shared current-model preference" \
  'VoiceInkCurrentTranscriptionModelPreference\.clearModelName\(\)' \
  VoiceInk/Transcription/Engine/TranscriptionModelManager.swift

reject_pattern \
  "macOS transcription model manager avoids shell-only legacy model key cleanup" \
  'removeObject\(forKey: +"CurrentModel"\)|"CurrentModel"' \
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

reject_pattern \
  "iOS audio settings avoid shell-only timeout range and display policy" \
  '0\.\.\.300|step: 15|audioSessionTimeoutSeconds\)s' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS audio settings avoid shell-only timeout presentation copy" \
  '"(Audio Settings|Session Timeout|How long to keep the microphone session active after recording stops\\. Longer timeouts prevent '\''session activation failed'\'' errors when recording frequently, but may use more battery\\.)"' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "iOS audio-session manager uses shared deactivation plan" \
  'VoiceInkAudioSessionTimeoutPreference\.deactivationPlan' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

require_pattern \
  "shared audio-session timeout owns countdown update interval" \
  'countdownUpdateInterval' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "shared audio-session timeout owns countdown remaining-time policy" \
  'remainingTimeAfterCountdownTick' \
  VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift

require_pattern \
  "iOS audio-session manager uses shared countdown tick policy" \
  'VoiceInkAudioSessionTimeoutPreference\.(countdownUpdateInterval|remainingTimeAfterCountdownTick)' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

reject_pattern \
  "iOS audio-session manager avoids shell-only timeout scheduling policy" \
  'shouldDeactivateImmediately|deactivationInterval|timeoutSeconds > 0|TimeInterval\(timeoutSeconds\)|withTimeInterval: +1\.0|timeoutRemaining -= 1' \
  iOS/VoiceInk-ios/AudioSessionManager.swift

require_pattern \
  "iOS app settings reset consumes shared reset state" \
  'VoiceInkDefaultSettings\.iOS\.appSettingsResetState' \
  iOS/VoiceInk-ios/AppSettings.swift

require_pattern \
  "iOS app settings reset consumes shared file reset plan" \
  'VoiceInkAppDataResetFilePlan\.iOS' \
  iOS/VoiceInk-ios/SettingsView.swift

reject_pattern \
  "iOS app settings reset avoids shell-only reset state assembly" \
  'let +defaults += +VoiceInkDefaultSettings\.iOS|modes += +\[\]|selectedModeId += +nil|apiKeyState += +VoiceInkProviderAPIKeyState\(\)|wordReplacements += +\[\]|customVocabularyTerms += +\[\]' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "iOS app settings reset avoids shell-only file reset sequence" \
  'let +recordingsDir|let +modelsDir|let +cachesURL|let +tmpPath|contentsOfDirectory|removeItem\(atPath:' \
  iOS/VoiceInk-ios/SettingsView.swift

require_pattern \
  "macOS app launch registers shared macOS default values" \
  'VoiceInkDefaultSettings\.macOS\.registeredUserDefaults' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS app launch uses shared onboarding completion storage state" \
  'VoiceInkOnboardingPreference\.hasStoredCompletionState' \
  VoiceInk/AppDefaults.swift

reject_pattern \
  "macOS app launch avoids raw onboarding completion storage checks" \
  'VoiceInkUserDefaultsKey\.hasCompletedOnboarding|object\(forKey: +"hasCompletedOnboarding"\)' \
  VoiceInk/AppDefaults.swift

require_pattern \
  "macOS Ollama service uses shared default base URL" \
  'VoiceInkPreferenceDefault\.ollamaBaseURL' \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS Ollama default base URL shim stays deleted" \
  'defaultBaseURL' \
  VoiceInk/Services/OllamaService.swift

reject_pattern \
  "macOS Ollama service avoids duplicate selected-model fallback literals" \
  '"llama2"|ollamaSelectedModel\(fallback: +"[^"]+"\)' \
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
  "macOS local Whisper prompt persists through shared prompt preference" \
  'VoiceInkTranscriptionPromptPreference\.saveLocalWhisperPromptForSelectedLanguage\(\)' \
  VoiceInk/Transcription/Whisper/WhisperPrompt.swift

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
  'VoiceInkPowerModeRowDetailPresentation|rowDetailPresentation' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePresentation.swift

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
  'VoiceInkPowerModePresentation\.rowDetailPresentation|PowerModeRowDetailChipView' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

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
  "macOS Power Mode rows avoid shell-only trigger-count pluralization" \
  'websiteCount == 1|appCount == 1|[0-9] (App|Apps|Website|Websites)' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode row context menu avoids shell-only delete confirmation copy" \
  'Delete Power Mode\?|Are you sure you want to delete|This action cannot be undone|addButton\(withTitle: +"(Delete|Cancel)"' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

reject_pattern \
  "macOS Power Mode rows avoid shell-only row detail chip policy" \
  'modelName\.count > 20|prefix\(18\)|selectedPrompt\?\.title \?\? "AI"|Text\("Context Awareness"\)|model != "Default"|language != "Default"|config\.autoSendKey\.displayName' \
  VoiceInk/PowerMode/PowerModeViewComponents.swift

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
  "shared Power Mode enhancement selection default repair lives in VoiceInkCore" \
  'VoiceInkPowerModeEnhancementSelection|fillingMissingProviderAndModel|selectingPromptAfterEnabling' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

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
  'macOS top-level Power Mode visibility, persist-after-recording preference, first-run visibility repair, and shortcut eligibility route through `VoiceInkPowerModePreference`' \
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
  'enabledPowerModeConfigurationIds|appendPowerModeConfigurationIfMissing|movePowerModeConfigurations|setPowerModeDefaultConfiguration|addPowerModeAppConfig' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

require_pattern \
  "shared Power Mode automatic resolution policy lives in VoiceInkCore" \
  'resolvedPowerModeConfiguration' \
  VoiceInkCore/Sources/VoiceInkCore/PowerModePolicy.swift

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
  "macOS Power Mode form consumes shared website form config policy" \
  'VoiceInkPowerModePolicy\.websiteConfigForFormInput' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

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
  "macOS Power Mode form consumes shared form state" \
  'mode\.formState\(existingConfigurations: powerModeManager\.configurations\)' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only website config construction" \
  'normalizedWebsiteURL\(newWebsiteURL\)|VoiceInkPowerModeURLConfig\(url:' \
  VoiceInk/PowerMode/PowerModeConfigView.swift

reject_pattern \
  "macOS Power Mode form avoids shell-only configuration-name saveability" \
  '!configName\.isEmpty' \
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
  "macOS Power Mode shortcuts call shared enabled-list policy directly" \
  'configurations\.enabledPowerModeConfigurations' \
  VoiceInk/Shortcuts/PowerModeShortcutManager.swift

reject_pattern \
  "macOS Power Mode startup avoids shell-only enabled config checks" \
  'configurations\.contains *\{ *\$0\.isEnabled *\}' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS Power Mode startup calls shared enabled-list policy directly" \
  'configurations\.enabledPowerModeConfigurations' \
  VoiceInk/VoiceInk.swift

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

reject_pattern \
  "macOS diagnostics avoid shell-only AI preference presentation" \
  'getAI(EnhancementStatus|Provider|Model)|VoiceInkUserDefaultsKey\.isAIEnhancementEnabled|selectedProviderRawValue\(\)|selectedModel\(for:' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS diagnostics use shared rolling-buffer per-model preference" \
  'VoiceInkRollingBufferPreloadSettings\.perModelPreloadEnabled\(forModelName: currentModelName\)' \
  VoiceInk/Services/SystemInfoService.swift

reject_pattern \
  "macOS diagnostics avoid shell-only rolling-buffer per-model default lookup" \
  'perModelPreloadEnabledKey\(forModelName: currentModelName\)|object\(forKey: key\) as\? Bool \?\? true' \
  VoiceInk/Services/SystemInfoService.swift

require_pattern \
  "macOS backup import uses shared rolling-buffer import policy" \
  'VoiceInkRollingBufferPreloadSettings\.saveImportedSettings\(' \
  VoiceInk/Services/BackupImporter.swift

reject_pattern \
  "macOS backup import avoids shell-only rolling-buffer preload storage" \
  'VoiceInkRollingBufferPreloadSettings\.(modeKey|autoDisableCloudModelsKey|autoDisableLowBatteryLocalModelsKey|lowBatteryThresholdPercentKey|bufferDurationSecondsKey|preRunFinalizationKey|perModelPreloadEnabledKey)|min\(max\(threshold|for \(modelName, enabled\) in perModelSettings' \
  VoiceInk/Services/BackupImporter.swift

require_pattern \
  "macOS backup export uses shared rolling-buffer per-model export policy" \
  'VoiceInkRollingBufferPreloadSettings\.exportedPerModelPreloadEnabled\(\)' \
  VoiceInk/Services/ImportExportService.swift

reject_pattern \
  "macOS backup export avoids shell-only rolling-buffer per-model key scan" \
  'perModelEnabledKeyPrefix|dictionaryRepresentation\(\)|exportPerModelRollingBufferPreloadSettings|dropFirst\(prefix\.count\)' \
  VoiceInk/Services/ImportExportService.swift

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

require_pattern \
  "shared note-list chrome presentation lives in VoiceInkCore" \
  'VoiceInkNoteListPresentation|startRecordingButtonTitle|settingsSystemImageName' \
  VoiceInkCore/Sources/VoiceInkCore/DashboardMetrics.swift

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
  "macOS dashboard uses shared average WPM display text" \
  'dashboardMetrics\.averageWordsPerMinuteDisplayText' \
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

require_pattern \
  "shared app identity presentation lives in VoiceInkCore" \
  'VoiceInkAppIdentity|bundleIdentifier = "com\.prakashjoshipax\.VoiceInk"|loggingSubsystem = "com\.prakashjoshipax\.voiceink"|displayName = "roma just talk"|compactDisplayName = "roma-just-talk"|iCloudContainerIdentifier|macOSApplicationSupportDirectory|errorDomain' \
  VoiceInkCore/Sources/VoiceInkCore/AppIdentity.swift

require_pattern \
  "shared Keychain service uses shared app identity" \
  'service = VoiceInkAppIdentity\.bundleIdentifier' \
  VoiceInkCore/Sources/VoiceInkCore/KeychainQuery.swift

require_pattern \
  "macOS dictionary CloudKit uses shared app identity container" \
  'VoiceInkAppIdentity\.iCloudContainerIdentifier' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "iOS audio recorder errors use shared app identity domain" \
  'VoiceInkAppIdentity\.errorDomain\(component: "AudioRecorder"\)' \
  iOS/VoiceInk-ios/AudioRecorder.swift

require_pattern \
  "macOS app startup storage path uses shared app identity directory" \
  'VoiceInkAppIdentity\.macOSApplicationSupportDirectory' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS recorder storage path uses shared app identity directory" \
  'VoiceInkAppIdentity\.macOSApplicationSupportDirectory' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

require_pattern \
  "macOS audio retry storage path uses shared app identity directory" \
  'VoiceInkAppIdentity\.macOSApplicationSupportDirectory' \
  VoiceInk/Services/AudioFileTranscriptionService.swift

require_pattern \
  "macOS audio import storage path uses shared app identity directory" \
  'VoiceInkAppIdentity\.macOSApplicationSupportDirectory' \
  VoiceInk/Services/AudioFileTranscriptionManager.swift

require_pattern \
  "macOS transcription cleanup storage path uses shared app identity directory" \
  'VoiceInkAppIdentity\.macOSApplicationSupportDirectory' \
  VoiceInk/Services/TranscriptionAutoCleanupService.swift

require_pattern \
  "macOS UI uses shared app identity presentation" \
  'VoiceInkAppIdentity\.(compactDisplayName|sidebarSubtitle|onboardingWindowTitle|storageFailureMessage)' \
  VoiceInk/Views/ContentView.swift

require_pattern \
  "macOS app startup uses shared app identity presentation" \
  'VoiceInkAppIdentity\.(compactDisplayName|storageFailureMessage)' \
  VoiceInk/VoiceInk.swift

require_pattern \
  "macOS windows use shared app identity presentation" \
  'VoiceInkAppIdentity\.(compactDisplayName|onboardingWindowTitle)' \
  VoiceInk/WindowManager.swift

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
  iOS/VoiceInk-ios/NotesListView.swift \
  iOS/VoiceInk-ios/OnboardingView.swift

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
  "iOS App Group bridge uses entitlement group" \
  'static let appGroupIdentifier = "group\.com\.prakashjoshipax\.VoiceInk"' \
  iOS/Shared/VoiceInkAppGroupRecordingBridge.swift

require_pattern \
  "iOS App Group bridge owns stop-recording Darwin notification" \
  'static let stopRecording = "com\.prakashjoshipax\.VoiceInk\.stopRecording"' \
  iOS/Shared/VoiceInkAppGroupRecordingBridge.swift

require_pattern \
  "iOS App Group bridge owns recording-state Darwin notification" \
  'static let recordingStateChanged = "com\.prakashjoshipax\.VoiceInk\.recordingStateChanged"' \
  iOS/Shared/VoiceInkAppGroupRecordingBridge.swift

require_pattern \
  "iOS shared coordinator owns app-local keyboard stop notification" \
  'static let stopRecordingFromKeyboard = Notification\.Name\("stopRecordingFromKeyboard"\)' \
  iOS/Shared/AppGroupCoordinator.swift

require_pattern \
  "iOS shared keyboard presentation owns button copy" \
  'VoiceInkKeyboardRecordingButtonPresentation' \
  iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift

require_pattern \
  "iOS shared keyboard presentation owns idle title" \
  'title: " Record"' \
  iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift

require_pattern \
  "iOS shared keyboard presentation owns recording title" \
  'title: " Stop"' \
  iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift

require_pattern \
  "iOS shared keyboard presentation owns fallback title" \
  'title: " Open roma just talk"' \
  iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift

require_pattern \
  "iOS shared keyboard presentation owns idle icon" \
  'systemImageName: "mic\.fill"' \
  iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift

require_pattern \
  "iOS shared keyboard presentation owns recording icon" \
  'systemImageName: "stop\.fill"' \
  iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift

require_pattern \
  "iOS shared keyboard presentation owns fallback icon" \
  'systemImageName: "app"' \
  iOS/Shared/VoiceInkKeyboardRecordingButtonPresentation.swift

require_pattern \
  "iOS keyboard controller uses shared button presentation" \
  'VoiceInkKeyboardRecordingButtonPresentation\.(idle|recording|openAppFallback|current)' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

reject_pattern \
  "iOS keyboard controller avoids shell-owned button copy" \
  'setTitle\("( Record| Stop| Open roma just talk)"|UIImage\(systemName: "(mic\.fill|stop\.fill|app)"' \
  iOS/VoiceInkKeyboard/KeyboardViewController.swift

reject_pattern \
  "iOS recording manager does not redeclare keyboard stop notification" \
  'Notification\.Name\("stopRecordingFromKeyboard"\)|extension Notification\.Name' \
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

run_required "VoiceInkCoreChecks" swift run --package-path VoiceInkCore VoiceInkCoreChecks
run_required "VoiceInkAudioProof builds" swift run --package-path VoiceInkCore VoiceInkAudioProof --help

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
