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
  DeepgramTranscriptionService.swift
  DefaultModeManager.swift
  GroqTranscriptionService.swift
  Item.swift
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
require_file iOS/VoiceInk-ios/PrivacyInfo.xcprivacy
require_file iOS/VoiceInk-ios/Resources/ggml-silero-v5.1.2.bin
require_file iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/Contents.json
for icon in 20.png 29.png 40.png 50.png 57.png 58.png 60.png 72.png 76.png 80.png 87.png 100.png 114.png 120.png 144.png 152.png 167.png 180.png 1024.png; do
  require_file "iOS/VoiceInk-ios/Assets.xcassets/AppIcon.appiconset/$icon"
done

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

reject_pattern \
  "iOS recording background transcription uses shared record updates" \
  '\b(existingAudioFileURL|markTranscriptionFailed|applyCompletedRunResult)\b' \
  iOS/VoiceInk-ios/RecordingManager.swift

require_pattern \
  "iOS live recording uses shared stored-audio filename policy" \
  'VoiceInkStoredAudioFile\.timestampedRecordingFileURL' \
  iOS/VoiceInk-ios/AudioRecorder.swift

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

reject_pattern \
  "iOS live recording avoids shell-only audio-meter history limit" \
  'levelsHistory\.count >|removeFirst\(self\.levelsHistory\.count -|0\.\.<40' \
  iOS/VoiceInk-ios/AudioRecorder.swift \
  iOS/VoiceInk-ios/AudioVisualizerView.swift

reject_pattern \
  "iOS note views avoid shell-only transcript presentation wrappers" \
  'private var +(transcriptText|statusBadgeText|relativeTimestamp|displayedTranscriptText|transcriptionStatusTitle) *:' \
  iOS/VoiceInk-ios/NoteRowView.swift \
  iOS/VoiceInk-ios/NoteDetailView.swift

reject_pattern \
  "iOS API-key view avoids shell-only stored-key presentation wrappers" \
  'private func +(currentAPIKey|obfuscatedKey)\(' \
  iOS/VoiceInk-ios/ProviderAPIKeyView.swift

require_pattern \
  "macOS local Whisper uses shared runtime policy" \
  'VoiceInkWhisperRuntimeConfiguration\.current' \
  VoiceInk/Transcription/Whisper/LibWhisper.swift

require_pattern \
  "iOS local Whisper uses shared runtime policy" \
  'VoiceInkWhisperRuntimeConfiguration\.current' \
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
  "macOS cloud API-key card uses shared draft policy" \
  'VoiceInkProviderAPIKeyDraft' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

require_pattern \
  "macOS cloud API-key card uses shared stored-key verifier" \
  'verifyStoredAPIKeyDetailed\(keyToVerify, for: provider\)' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift

reject_pattern \
  "macOS cloud API-key card avoids shell-only stored-key resolution" \
  'VoiceInkAPIKeyReference\.resolvedValue|func +verifyAPIKey\(_ key: String\)|cloudProvider\.verifyAPIKey' \
  VoiceInk/Views/AI\ Models/CloudModelCardView.swift \
  VoiceInk/Transcription/Cloud/CloudProvider.swift

require_pattern \
  "shared custom cloud model backup record owns export/import shape" \
  'struct VoiceInkCustomCloudModelBackup' \
  VoiceInkCore/Sources/VoiceInkCore/CustomCloudModelPolicy.swift

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
  'VoiceInkFillerWords\.insertPlan\(' \
  VoiceInk/Transcription/Processing/FillerWordManager.swift

require_pattern \
  "iOS filler-word insertion uses shared insert policy" \
  'VoiceInkFillerWords\.insertPlan\(' \
  iOS/VoiceInk-ios/AppSettings.swift

reject_pattern \
  "filler-word duplicate copy stays out of platform views" \
  'This filler word is already in the list\.' \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
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

reject_pattern \
  "macOS cloud batch transcription avoids pre-normalized vocabulary terms" \
  'getCustomVocabularyTerms\(from: modelContext\)' \
  VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift \
  VoiceInk/Services/CustomVocabularyService.swift

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
  "macOS session creation uses shared streaming preference directly" \
  'VoiceInkTranscriptionStreamingPreference\.shouldUseStreaming\(for: model\.streamingPreferenceSnapshot\)' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

reject_pattern \
  "macOS session creation avoids shell-only streaming support wrapper" \
  'private func supportsStreaming\(model:' \
  VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift

require_pattern \
  "macOS AI API-key view uses shared AI draft policy" \
  'VoiceInkAIEnhancementAPIKeyDraft' \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift

require_pattern \
  "macOS AI service resolves keys through shared AI draft policy" \
  'VoiceInkAIEnhancementAPIKeyDraft' \
  VoiceInk/Services/AIEnhancement/AIService.swift

reject_pattern \
  "macOS AI API-key path avoids shell-only key-reference and blank-key policy" \
  'VoiceInkAPIKeyReference\.resolvedValue|VoiceInkProviderCredential\.nonBlank\(apiKey\)' \
  VoiceInk/Services/AIEnhancement/AIService.swift \
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
  "macOS transcription pipeline uses shared failed transcript text" \
  'VoiceInkTranscriptPresentation\.failedTranscriptText' \
  VoiceInk/Transcription/Engine/TranscriptionPipeline.swift

require_pattern \
  "macOS engine uses shared failed transcript text" \
  'VoiceInkTranscriptPresentation\.failedTranscriptText' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

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
  "macOS engine canceled recording uses shared canceled text" \
  'VoiceInkTranscriptPresentation\.canceledTranscriptionText' \
  VoiceInk/Transcription/Engine/VoiceInkEngine.swift

reject_pattern \
  "macOS canceled transcription text shim stays deleted" \
  'static let canceledTranscriptionText' \
  VoiceInk/Models/Transcription.swift

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
  "iOS mode prompt-template editing uses shared mode state" \
  '\$mode\.promptTemplate\.' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

reject_pattern \
  "iOS mode prompt-template editing avoids duplicate shell draft state" \
  'selectedTemplateType|customPromptText|mode\.promptTemplate = VoiceInkPostProcessingPromptTemplate' \
  iOS/VoiceInk-ios/ModeConfigurationView.swift

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
  "macOS Power Mode config uses shared macOS selected-language fallback" \
  'VoiceInkTranscriptionLanguagePreference\.selectedMacOSLanguage\(\)' \
  VoiceInk/PowerMode/PowerModeConfig.swift

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
  iOS/VoiceInk-ios/VoiceInk-ios/Transcription.swift

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
  "iOS note-list dashboard summary uses shared metrics accumulator" \
  'VoiceInkDashboardMetricsAccumulator' \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS note-list avoids shell-only dashboard metric math" \
  'VoiceInkWordCounter|VoiceInkSessionMetricPolicy|dashboardWordCount|dashboardAudioDuration|reduce\(' \
  iOS/VoiceInk-ios/NotesListView.swift

require_pattern \
  "iOS note-list fastest-model summary uses shared performance analyzer" \
  'VoiceInkPerformanceAnalyzer\.transcriptionModelStats' \
  iOS/VoiceInk-ios/NotesListView.swift

reject_pattern \
  "iOS note-list avoids shell-only performance grouping" \
  'Dictionary\(grouping:|avgProcessingTime|speedFactor =|totalProcessingTime|performanceTranscriptionDuration' \
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
