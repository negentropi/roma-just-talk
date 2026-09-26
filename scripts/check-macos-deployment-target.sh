#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected_version="14.0"
failures=0
source "$repo_root/scripts/macos-deployment-target-lib.sh"

if [[ "$#" -gt 2 ]]; then
  echo "usage: $0 [app-path [latency-harness-app-path]]" >&2
  exit 2
fi

fail() {
  echo "$1" >&2
  failures=$((failures + 1))
}

check_mach_o_payload() {
  local payload_path="$1"
  local display_path="$2"
  local comparison="$3"
  local records
  local macos_record_count=0
  local platform
  local version

  records="$(otool -arch arm64 -l "$payload_path" | macos_load_command_records)"
  while IFS=$'\t' read -r platform version; do
    if [[ -z "$platform" && -z "$version" ]]; then
      continue
    fi

    if [[ "$platform" == "6" && "$comparison" == "maximum" ]]; then
      continue
    fi

    if [[ "$platform" != "1" ]]; then
      fail "$display_path has non-macOS platform $platform"
      continue
    fi

    macos_record_count=$((macos_record_count + 1))
    if [[ "$comparison" == "exact" && "$version" != "$expected_version" ]]; then
      fail "$display_path minimum macOS is $version, expected $expected_version"
    elif [[ "$comparison" == "maximum" ]] && ! macos_version_is_at_most "$version" "$expected_version"; then
      fail "$display_path requires macOS $version, newer than $expected_version"
    fi
  done <<<"$records"

  if [[ "$macos_record_count" -eq 0 ]]; then
    fail "$display_path has no macOS minimum-version load command"
  fi
}

deployment_target_count=0
while IFS= read -r version; do
  deployment_target_count=$((deployment_target_count + 1))
  if [[ "$version" != "$expected_version" ]]; then
    fail "Xcode deployment target is $version, expected $expected_version"
  fi
done < <(
  sed -nE 's/^[[:space:]]*MACOSX_DEPLOYMENT_TARGET = "?([^";]+)"?;/\1/p' \
    "$repo_root/VoiceInk.xcodeproj/project.pbxproj"
)

if [[ "$deployment_target_count" -eq 0 ]]; then
  fail "Xcode project has no explicit macOS deployment target"
fi

for document in README.md BUILDING.md CONTRIBUTING.md; do
  if ! grep -Fq "macOS $expected_version or later" "$repo_root/$document"; then
    fail "$document does not declare macOS $expected_version or later"
  fi
done

for info_plist in \
  Tools/RuntimeE2EHarness/Info.plist \
  Tools/VisibleTextLatencyHarness/Info.plist; do
  plist_version="$(plutil -extract LSMinimumSystemVersion raw -o - "$repo_root/$info_plist")"
  if [[ "$plist_version" != "$expected_version" ]]; then
    fail "$info_plist minimum macOS is $plist_version, expected $expected_version"
  fi
done

if ! node --test "$repo_root/scripts/tests/github-release-appcast.test.js"; then
  failures=$((failures + 1))
fi

if ! bash "$repo_root/scripts/tests/macos-deployment-target.test.sh"; then
  failures=$((failures + 1))
fi

if [[ "$#" -ge 1 ]]; then
  app_path="$1"
  info_plist="$app_path/Contents/Info.plist"

  if [[ ! -f "$info_plist" ]]; then
    fail "App Info.plist not found at $info_plist"
  else
    plist_version="$(plutil -extract LSMinimumSystemVersion raw -o - "$info_plist")"
    if [[ "$plist_version" != "$expected_version" ]]; then
      fail "Built app LSMinimumSystemVersion is $plist_version, expected $expected_version"
    fi

    executable_name="$(plutil -extract CFBundleExecutable raw -o - "$info_plist")"
    executable_path="$app_path/Contents/MacOS/$executable_name"
    if [[ ! -f "$executable_path" ]]; then
      fail "App executable not found at $executable_path"
    else
      check_mach_o_payload "$executable_path" "Built app executable" exact
    fi

    while IFS= read -r -d '' payload_path; do
      if [[ "$payload_path" == "$executable_path" ]]; then
        continue
      fi

      if ! file -b "$payload_path" | grep -Fq "Mach-O"; then
        continue
      fi

      relative_payload="${payload_path#"$app_path"/}"
      check_mach_o_payload "$payload_path" "$relative_payload" maximum
    done < <(find "$app_path/Contents" -type f -print0)
  fi
fi

if [[ "$#" -eq 2 ]]; then
  helper_path="$2"
  helper_info_plist="$helper_path/Contents/Info.plist"
  if [[ ! -f "$helper_info_plist" ]]; then
    fail "Latency helper Info.plist not found at $helper_info_plist"
  else
    helper_version="$(plutil -extract LSMinimumSystemVersion raw -o - "$helper_info_plist")"
    if [[ "$helper_version" != "$expected_version" ]]; then
      fail "Latency helper LSMinimumSystemVersion is $helper_version, expected $expected_version"
    fi
    helper_executable_name="$(plutil -extract CFBundleExecutable raw -o - "$helper_info_plist")"
    helper_executable="$helper_path/Contents/MacOS/$helper_executable_name"
    if [[ ! -f "$helper_executable" ]]; then
      fail "Latency helper executable not found at $helper_executable"
    else
      check_mach_o_payload "$helper_executable" "Latency helper executable" exact
    fi
  fi
fi

if [[ "$failures" -ne 0 ]]; then
  echo "macOS deployment target checks failed: $failures" >&2
  exit 1
fi

if [[ "$#" -eq 0 ]]; then
  echo "macOS $expected_version source checks passed. Built bundles were not checked."
else
  echo "macOS $expected_version source and built-bundle checks passed."
fi
