#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

local_whisper_xcframework_path="${HOME}/RomaJustTalk-Dependencies/whisper.cpp/build-apple/whisper.xcframework"
expected_whisper_project_path='$(HOME)/RomaJustTalk-Dependencies/whisper.cpp/build-apple/whisper.xcframework'
expected_app_group="group.com.negentropi.RomaJustTalk"

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

require_file_line_count() {
  local description="$1"
  local file="$2"
  local expected_line="$3"
  local expected="$4"

  section "$description"
  local actual
  if ! actual="$(
    ruby -e '
      path, expected_line = ARGV
      print File.readlines(path, chomp: true).count { |line| line.strip == expected_line }
    ' "$file" "$expected_line"
  )"; then
    fail "$description"
    return
  fi

  if [[ "$actual" != "$expected" ]]; then
    fail "$description: expected $expected line(s), got $actual"
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

require_plist_boolean() {
  local description="$1"
  local file="$2"
  local key="$3"
  local expected="$4"

  section "$description"
  if ! plutil -convert json -o - "$file" 2>/dev/null \
    | ruby -rjson -e '
        key, expected = ARGV
        value = JSON.parse(STDIN.read).fetch(key)
        exit(value.equal?(expected == "true") ? 0 : 1)
      ' "$key" "$expected"
  then
    fail "$description: expected Boolean $expected"
  fi
}

reject_plist_key() {
  local description="$1"
  local file="$2"
  local key="$3"

  section "$description"
  if ! plutil -convert json -o - "$file" 2>/dev/null \
    | ruby -rjson -e 'exit(JSON.parse(STDIN.read).key?(ARGV.fetch(0)) ? 1 : 0)' "$key"
  then
    fail "$description: unexpected key '$key'"
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
  tmp="$(mktemp "${TMPDIR:-/tmp}/roma-project.XXXXXX.xml")"
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

require_target_framework() {
  local description="$1"
  local project_file="$2"
  local target_name="$3"
  local framework_path="$4"

  section "$description"
  if ! plutil -convert json -o - "$project_file" | ruby -rjson -e '
    objects = JSON.parse(STDIN.read).fetch("objects")
    target_name, framework_path = ARGV
    target = objects.values.find do |object|
      object["isa"] == "PBXNativeTarget" && object["name"] == target_name
    end
    exit 1 unless target

    linked = Array(target["buildPhases"]).any? do |phase_id|
      phase = objects[phase_id]
      next false unless phase && phase["isa"] == "PBXFrameworksBuildPhase"

      Array(phase["files"]).any? do |build_file_id|
        build_file = objects[build_file_id]
        file = build_file && objects[build_file["fileRef"]]
        file && file["sourceTree"] == "SDKROOT" && file["path"] == framework_path
      end
    end

    exit(linked ? 0 : 1)
  ' "$target_name" "$framework_path"
  then
    fail "$description: '$framework_path' is not in target '$target_name' Frameworks phase"
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
require_dir RomaJustTalk.xcodeproj
require_dir RomaJustTalk.xcworkspace
require_dir RomaCore
require_dir iOS/RomaJustTalk-ios.xcodeproj
require_dir iOS/RomaJustTalk-ios
require_dir iOS/RomaKeyboard
require_dir iOS/Shared

section "required project files"
require_file RomaJustTalk.xcworkspace/contents.xcworkspacedata
require_file RomaJustTalk.xcworkspace/xcshareddata/xcschemes/RomaJustTalk-ios.xcscheme
require_file RomaJustTalk.xcodeproj/project.pbxproj
require_file RomaJustTalk.xcodeproj/project.xcworkspace/contents.xcworkspacedata
require_file RomaJustTalk.xcodeproj/xcshareddata/xcschemes/RomaJustTalk.xcscheme
require_file iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj
require_file iOS/RomaJustTalk-ios.xcodeproj/project.xcworkspace/contents.xcworkspacedata
require_file RomaCore/Package.swift
require_file Makefile
require_file LocalBuild.xcconfig
require_file .github/workflows/roma-ios-single-repo-migration.yml
require_file scripts/tests/verify-adhoc-library-validation.test.sh
require_file scripts/verify-adhoc-library-validation.sh
require_file scripts/verify-static-whisper-app.sh
require_file scripts/verify-static-whisper-xcframework.sh

section "required app configuration files"
require_file RomaJustTalk/Info.plist
require_file RomaJustTalk/RomaJustTalk.entitlements
require_file RomaJustTalk/RomaJustTalk.local.entitlements
require_file iOS/RomaJustTalk-ios/Info.plist
require_file iOS/RomaJustTalk-ios/PrivacyInfo.xcprivacy
require_file iOS/RomaJustTalk-ios/RomaJustTalk_ios.entitlements
require_file iOS/RomaKeyboard/Info.plist
require_file iOS/RomaKeyboard/RomaKeyboard.entitlements

section "required iOS shared shell files"
require_file iOS/Shared/AppGroupCoordinator.swift
require_file iOS/Shared/RomaIOSLogger.swift
require_file iOS/Shared/RomaKeyboardURLOpener.swift

section "required iOS resources"
require_file iOS/RomaJustTalk-ios/Assets.xcassets/AppIcon.appiconset/Contents.json
require_file iOS/RomaJustTalk-ios/Resources/ggml-silero-v5.1.2.bin

section "abandoned root-level shared-core shape stays absent"
reject_path ../RomaCore
reject_path ../Package.swift
reject_path ../Sources/RomaCore
reject_path ../Tests/RomaCoreTests

run_required "project/plist/entitlements lint" plutil -lint \
  RomaJustTalk.xcodeproj/project.pbxproj \
  iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
  RomaJustTalk/Info.plist \
  RomaJustTalk/RomaJustTalk.entitlements \
  RomaJustTalk/RomaJustTalk.local.entitlements \
  iOS/RomaJustTalk-ios/Info.plist \
  iOS/RomaJustTalk-ios/PrivacyInfo.xcprivacy \
  iOS/RomaJustTalk-ios/RomaJustTalk_ios.entitlements \
  iOS/RomaKeyboard/Info.plist \
  iOS/RomaKeyboard/RomaKeyboard.entitlements

run_required "iOS app icon JSON lint" plutil -convert xml1 \
  -o /tmp/RomaAppIconContents.plist \
  iOS/RomaJustTalk-ios/Assets.xcassets/AppIcon.appiconset/Contents.json

run_required "workspace and scheme XML lint" xmllint --noout \
  RomaJustTalk.xcworkspace/contents.xcworkspacedata \
  RomaJustTalk.xcworkspace/xcshareddata/xcschemes/RomaJustTalk-ios.xcscheme \
  RomaJustTalk.xcodeproj/xcshareddata/xcschemes/RomaJustTalk.xcscheme \
  RomaJustTalk.xcodeproj/project.xcworkspace/contents.xcworkspacedata \
  iOS/RomaJustTalk-ios.xcodeproj/project.xcworkspace/contents.xcworkspacedata

require_xml_xpath_value \
  "workspace includes in-repo iOS project" \
  RomaJustTalk.xcworkspace/contents.xcworkspacedata \
  "/Workspace/FileRef[contains(@location, 'iOS/RomaJustTalk-ios.xcodeproj')]/@location" \
  "group:iOS/RomaJustTalk-ios.xcodeproj"

require_xml_xpath_value \
  "iOS workspace scheme includes unit-test bundle" \
  RomaJustTalk.xcworkspace/xcshareddata/xcschemes/RomaJustTalk-ios.xcscheme \
  "//BuildableReference[@BlueprintName='RomaJustTalk-iosTests']/@BlueprintName" \
  "RomaJustTalk-iosTests"

require_xml_xpath_value \
  "iOS workspace scheme enables unit-test bundle" \
  RomaJustTalk.xcworkspace/xcshareddata/xcschemes/RomaJustTalk-ios.xcscheme \
  "//TestableReference[BuildableReference[@BlueprintName='RomaJustTalk-iosTests']]/@skipped" \
  "NO"

require_xml_xpath_value \
  "iOS workspace scheme includes UI-test bundle" \
  RomaJustTalk.xcworkspace/xcshareddata/xcschemes/RomaJustTalk-ios.xcscheme \
  "//BuildableReference[@BlueprintName='RomaJustTalk-iosUITests']/@BlueprintName" \
  "RomaJustTalk-iosUITests"

require_xml_xpath_value \
  "iOS workspace scheme enables UI-test bundle" \
  RomaJustTalk.xcworkspace/xcshareddata/xcschemes/RomaJustTalk-ios.xcscheme \
  "//TestableReference[BuildableReference[@BlueprintName='RomaJustTalk-iosUITests']]/@skipped" \
  "NO"

require_plist_value \
  "iOS app display name stays roma just talk" \
  iOS/RomaJustTalk-ios/Info.plist \
  CFBundleDisplayName \
  "roma just talk"

require_plist_value \
  "iOS app bundle name stays roma just talk" \
  iOS/RomaJustTalk-ios/Info.plist \
  CFBundleName \
  "roma just talk"

require_plist_value \
  "iOS record deep-link scheme stays romajusttalk" \
  iOS/RomaJustTalk-ios/Info.plist \
  CFBundleURLTypes.0.CFBundleURLSchemes.0 \
  romajusttalk

require_plist_value \
  "iOS app keeps audio background mode" \
  iOS/RomaJustTalk-ios/Info.plist \
  UIBackgroundModes.0 \
  audio

require_plist_value \
  "keyboard extension point stays keyboard service" \
  iOS/RomaKeyboard/Info.plist \
  NSExtension.NSExtensionPointIdentifier \
  com.apple.keyboard-service

require_plist_value \
  "keyboard open access stays enabled" \
  iOS/RomaKeyboard/Info.plist \
  NSExtension.NSExtensionAttributes.RequestsOpenAccess \
  true

require_json_array_value \
  "iOS app entitlement uses shared App Group" \
  iOS/RomaJustTalk-ios/RomaJustTalk_ios.entitlements \
  "com.apple.security.application-groups" \
  0 \
  "$expected_app_group"

require_json_array_value \
  "keyboard entitlement uses shared App Group" \
  iOS/RomaKeyboard/RomaKeyboard.entitlements \
  "com.apple.security.application-groups" \
  0 \
  "$expected_app_group"

require_file_string_count \
  "iOS CI allows Simulator signing for builds and tests" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "CODE_SIGNING_ALLOWED=YES" \
  2

require_file_string_count \
  "iOS CI uses the ad-hoc Simulator signing identity" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "CODE_SIGN_IDENTITY=-" \
  2

require_file_string_count \
  "iOS CI keeps Simulator entitlements in builds and tests" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "ENTITLEMENTS_ALLOWED=YES" \
  2

require_file_string_count \
  "iOS CI does not disable signing for Simulator artifacts" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "CODE_SIGNING_ALLOWED=NO" \
  0

require_file_string_count \
  "iOS CI does not exclude test source files" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "EXCLUDED_SOURCE_FILE_NAMES" \
  0

require_file_line_count \
  "iOS CI runs the complete unit-test bundle" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "-only-testing:RomaJustTalk-iosTests \\" \
  1

require_file_string_count \
  "iOS CI avoids class-level unit-test allowlists" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "-only-testing:RomaJustTalk-iosTests/" \
  0

require_file_line_count \
  "iOS CI runs the complete UI-test bundle" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "-only-testing:RomaJustTalk-iosUITests" \
  1

require_file_string_count \
  "iOS CI avoids class-level UI-test allowlists" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "-only-testing:RomaJustTalk-iosUITests/" \
  0

require_file_string_count \
  "iOS CI has only the two complete-bundle selectors" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "-only-testing:" \
  2

require_file_string_count \
  "iOS CI does not skip tests inside either bundle" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "-skip-testing:" \
  0

for broad_path in 'docs/**' 'scripts/**' 'RomaJustTalk/**'; do
  require_file_line_count \
    "iOS CI avoids broad unrelated trigger $broad_path" \
    .github/workflows/roma-ios-single-repo-migration.yml \
    "- \"$broad_path\"" \
    0
done

for shared_ios_input in \
  .github/workflows/roma-build.yml \
  LocalBuild.xcconfig \
  Makefile \
  scripts/check-find-reusable-ci-run.sh \
  scripts/find-reusable-ci-run.sh \
  scripts/verify-ios-single-repo-migration.sh \
  scripts/verify-static-whisper-app.sh \
  scripts/verify-static-whisper-xcframework.sh \
  'RomaCore/**' \
  'iOS/**' \
  RomaJustTalk/Info.plist \
  'RomaJustTalk/Resources/Sounds/**' \
  RomaJustTalk/Transcription/FluidAudio/FluidAudioModelManager.swift \
  RomaJustTalk/Transcription/Streaming/FluidAudioStreamingProvider.swift \
  RomaJustTalk/Transcription/Streaming/FluidAudioWordTimingAdapter.swift \
  RomaJustTalk/RomaJustTalk.entitlements \
  RomaJustTalk/RomaJustTalk.local.entitlements \
  'RomaJustTalk.xcodeproj/**' \
  'RomaJustTalk.xcworkspace/**'
do
  require_file_line_count \
    "iOS CI watches shared input $shared_ios_input" \
    .github/workflows/roma-ios-single-repo-migration.yml \
    "- \"$shared_ios_input\"" \
    2
done

require_file_line_count \
  "macOS build watches shared core" \
  .github/workflows/roma-build.yml \
  '- "RomaCore/**"' \
  2

for static_whisper_input in \
  scripts/verify-static-whisper-app.sh \
  scripts/verify-static-whisper-xcframework.sh
do
  require_file_line_count \
    "macOS build watches $static_whisper_input" \
    .github/workflows/roma-build.yml \
    "- \"$static_whisper_input\"" \
    2
done

require_file_line_count \
  "macOS build watches the ad-hoc Library Validation check" \
  .github/workflows/roma-build.yml \
  '- "scripts/verify-adhoc-library-validation.sh"' \
  2

require_file_line_count \
  "macOS build watches the ad-hoc Library Validation regression test" \
  .github/workflows/roma-build.yml \
  '- "scripts/tests/verify-adhoc-library-validation.test.sh"' \
  2

require_file_string_count \
  "macOS build runs the ad-hoc Library Validation regression test" \
  .github/workflows/roma-build.yml \
  'bash scripts/tests/verify-adhoc-library-validation.test.sh' \
  1

require_file_string_count \
  "local build verifies its DerivedData app before installation" \
  Makefile \
  'if ! bash "$(ADHOC_LIBRARY_VALIDATION_CHECK)" "$$APP_PATH"; then exit 1; fi' \
  1

require_file_string_count \
  "local build fails before installation when static Whisper verification fails" \
  Makefile \
  'if ! bash "$(STATIC_WHISPER_APP_CHECK)" "$$APP_PATH"; then exit 1; fi' \
  1

require_file_string_count \
  "local build verifies the staged install before replacing the current app" \
  Makefile \
  'if ! bash "$(ADHOC_LIBRARY_VALIDATION_CHECK)" "$$STAGED_APP"; then exit 1; fi' \
  1

require_file_string_count \
  "local build fails when staging the verified app fails" \
  Makefile \
  'if ! ditto "$$APP_PATH" "$$STAGED_APP"; then exit 1; fi' \
  1

require_file_string_count \
  "standalone ad-hoc Library Validation check targets the installed app" \
  Makefile \
  'bash "$(ADHOC_LIBRARY_VALIDATION_CHECK)" "$(LOCAL_APP_DEST)"' \
  1

require_plist_boolean \
  "local entitlements disable Library Validation for ad-hoc dynamic frameworks" \
  RomaJustTalk/RomaJustTalk.local.entitlements \
  com.apple.security.cs.disable-library-validation \
  true

reject_plist_key \
  "certificate-signed release entitlements keep Library Validation enabled" \
  RomaJustTalk/RomaJustTalk.entitlements \
  com.apple.security.cs.disable-library-validation

require_file_string_count \
  "iOS CI does not duplicate the macOS build" \
  .github/workflows/roma-ios-single-repo-migration.yml \
  "make local CONFIGURATION=Release" \
  0

require_file_line_count \
  "macOS build checks pull requests" \
  .github/workflows/roma-build.yml \
  "pull_request:" \
  1

require_file_line_count \
  "macOS pull requests never reuse prior proof" \
  .github/workflows/roma-build.yml \
  "if: github.event_name != 'pull_request' && inputs.force != true" \
  1

require_project_string \
  "macOS project references RomaCore" \
  RomaJustTalk.xcodeproj/project.pbxproj \
  RomaCore

require_project_string \
  "iOS project references RomaCore" \
  iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
  RomaCore

require_project_string \
  "iOS project references shared shell group" \
  iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
  Shared

require_project_string \
  "macOS project product name stays roma just talk" \
  RomaJustTalk.xcodeproj/project.pbxproj \
  "roma just talk"

require_project_string \
  "iOS project product name stays roma just talk" \
  iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
  "roma just talk"

reject_project_string \
  "macOS project avoids sibling RomaJustTalk-iOS references" \
  RomaJustTalk.xcodeproj/project.pbxproj \
  RomaJustTalk-iOS

reject_project_string \
  "iOS project avoids sibling RomaJustTalk-iOS references" \
  iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
  RomaJustTalk-iOS

require_project_string \
  "macOS project uses canonical local Whisper framework path" \
  RomaJustTalk.xcodeproj/project.pbxproj \
  "$expected_whisper_project_path"

require_project_string \
  "iOS project uses canonical local Whisper framework path" \
  iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
  "$expected_whisper_project_path"

reject_project_string \
  "macOS project does not embed static Whisper" \
  RomaJustTalk.xcodeproj/project.pbxproj \
  "whisper.xcframework in Embed Frameworks"

reject_project_string \
  "iOS project does not embed static Whisper" \
  iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
  "whisper.xcframework in Embed Frameworks"

require_file_string_count \
  "Makefile requests upstream static Whisper packaging" \
  Makefile \
  "BUILD_STATIC_XCFRAMEWORK=ON" \
  1

require_target_framework \
  "macOS app explicitly links CoreML required by static Whisper" \
  RomaJustTalk.xcodeproj/project.pbxproj \
  RomaJustTalk \
  System/Library/Frameworks/CoreML.framework

require_target_framework \
  "iOS app explicitly links CoreML required by static Whisper" \
  iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
  RomaJustTalk-ios \
  System/Library/Frameworks/CoreML.framework

for obsolete_framework_path in \
  "../Downloads/build-apple/whisper.xcframework" \
  "../whisper.cpp/build-apple/whisper.xcframework" \
  "../build-apple/whisper.xcframework"
do
  reject_project_string \
    "macOS project avoids obsolete framework path $obsolete_framework_path" \
    RomaJustTalk.xcodeproj/project.pbxproj \
    "$obsolete_framework_path"
  reject_project_string \
    "iOS project avoids obsolete framework path $obsolete_framework_path" \
    iOS/RomaJustTalk-ios.xcodeproj/project.pbxproj \
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
