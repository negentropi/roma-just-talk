#!/usr/bin/env bash
set -euo pipefail

sample_capture_pid=""
cleanup_sample_capture() {
  if [[ -n "$sample_capture_pid" ]]; then
    kill -TERM "$sample_capture_pid" 2>/dev/null || true
    sleep 0.1
    kill -KILL "$sample_capture_pid" 2>/dev/null || true
    wait "$sample_capture_pid" 2>/dev/null || true
    sample_capture_pid=""
  fi
}
trap cleanup_sample_capture EXIT
trap 'cleanup_sample_capture; exit 130' INT
trap 'cleanup_sample_capture; exit 143' TERM

run_bounded_process_sample() {
  local target_pid="$1"
  local directory="$2"
  local deadline=$((SECONDS + 15))
  sample "$target_pid" 1 -file "$directory/process-sample.txt" \
    > "$directory/process-sample.stdout.txt" \
    2> "$directory/process-sample.stderr.txt" &
  sample_capture_pid=$!
  while kill -0 "$sample_capture_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      cleanup_sample_capture
      echo "timed out capturing process dyld images: $target_pid" >&2
      return 1
    fi
    sleep 0.1
  done
  local result=0
  wait "$sample_capture_pid" || result=$?
  sample_capture_pid=""
  return "$result"
}

build_dyld_cache_probe() {
  local probe_directory="$1"
  mkdir -p "$probe_directory"
  cat > "$probe_directory/dyld-cache-probe.c" <<'C'
#include <mach-o/dyld.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uuid/uuid.h>

struct dyld_shared_cache_dylib_text_info {
  uint64_t version;
  uint64_t loadAddressUnslid;
  uint64_t textSegmentSize;
  uuid_t dylibUuid;
  const char *path;
  uint64_t textSegmentOffset;
};
extern bool _dyld_get_shared_cache_uuid(uuid_t);
extern const char *_dyld_shared_cache_real_path(const char *);
extern int dyld_shared_cache_iterate_text(const uuid_t,
    void (^)(const struct dyld_shared_cache_dylib_text_info *));

int main(int argc, char **argv) {
  uuid_t observer_uuid;
  if (argc < 2 || !_dyld_get_shared_cache_uuid(observer_uuid)) return 2;
  uuid_string_t observer_text;
  uuid_unparse_upper(observer_uuid, observer_text);
  if (strcmp(argv[1], "identity") == 0 && argc == 2) {
    puts(observer_text);
    return 0;
  }
  if (strcmp(argv[1], "resolve") == 0) {
    if (argc < 3) return 2;
    for (int i = 2; i < argc; ++i) {
      bool contains = _dyld_shared_cache_contains_path(argv[i]);
      const char *canonical = _dyld_shared_cache_real_path(argv[i]);
      if (contains != (canonical != NULL)) return 3;
      uuid_string_t image_uuid = "";
      char *image_uuid_buffer = image_uuid;
      if (contains) {
        int result = dyld_shared_cache_iterate_text(observer_uuid,
            ^(const struct dyld_shared_cache_dylib_text_info *image) {
              if (strcmp(image->path, canonical) == 0)
                uuid_unparse_upper(image->dylibUuid, image_uuid_buffer);
            });
        if (result || !image_uuid[0]) {
          fprintf(stderr, "could not identify active cache image: %s\n", canonical);
          return 7;
        }
      }
      printf("%s\t%d\t%s\t%s\t%s\n", observer_text, contains, argv[i],
          canonical ? canonical : "", image_uuid);
    }
    return 0;
  }
  return 2;
}
C
  xcrun clang -arch arm64 -fblocks "$probe_directory/dyld-cache-probe.c" \
    -o "$probe_directory/dyld-cache-probe"
}

if [[ "${1:-}" == "--capture-dyld-cache" ]]; then
  if [[ $# -lt 3 ]]; then
    echo "usage: $0 --capture-dyld-cache <running-pid> <evidence-directory> [path ...]" >&2
    exit 2
  fi
  capture_pid="$2"
  capture_directory="$3"
  shift 3
  if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" \
    || ! "$capture_pid" =~ ^[1-9][0-9]*$ ]] \
    || ! kill -0 "$capture_pid" 2>/dev/null; then
    echo "cache capture requires a live numeric PID on Apple Silicon macOS" >&2
    exit 2
  fi
  for capture_path in "$@"; do
    if [[ "$capture_path" != /* || "$capture_path" == *$'\t'* \
      || "$capture_path" == *$'\n'* ]]; then
      echo "cache capture dependency paths must be absolute, single-line paths" >&2
      exit 2
    fi
  done
  if [[ "$capture_directory" != /* ]] || ! mkdir "$capture_directory"; then
    echo "cache capture requires a new absolute evidence directory" >&2
    exit 2
  fi
  build_dyld_cache_probe "$capture_directory"
  "$capture_directory/dyld-cache-probe" identity \
    > "$capture_directory/observer-dyld-cache-uuid.txt"
  ps -p "$capture_pid" -o pid=,lstart= \
    > "$capture_directory/process-start-before.txt"
  if [[ $# -gt 0 ]]; then
    "$capture_directory/dyld-cache-probe" resolve "$@" \
      > "$capture_directory/dyld-cache-aliases.tsv"
  fi
  run_bounded_process_sample "$capture_pid" "$capture_directory"
  ps -p "$capture_pid" -o pid=,lstart= \
    > "$capture_directory/process-start-after.txt"
  cmp "$capture_directory/process-start-before.txt" \
    "$capture_directory/process-start-after.txt"
  exit 0
fi

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <source-app-bundle> <running-pid> <evidence-directory>" >&2
  exit 2
fi

requested_app="${1%/}"
pid="$2"
evidence="${3%/}"
require_translocation="${DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION:-true}"
stability_seconds="${DISTRIBUTION_E2E_STABILITY_SECONDS:-15}"
expected_macos_version="${DISTRIBUTION_E2E_EXPECTED_MACOS_VERSION:-}"
expected_macos_build="${DISTRIBUTION_E2E_EXPECTED_MACOS_BUILD:-}"
expected_quarantine_agent="${DISTRIBUTION_E2E_EXPECTED_QUARANTINE_AGENT:-}"
require_appkit_finished="${DISTRIBUTION_E2E_REQUIRE_APPKIT_FINISHED:-false}"
appkit_timeout_seconds="${DISTRIBUTION_E2E_APPKIT_TIMEOUT_SECONDS:-30}"
capture_until_exit="${DISTRIBUTION_E2E_CAPTURE_MAPPED_CODE_UNTIL_EXIT:-false}"
capture_timeout_seconds="${DISTRIBUTION_E2E_CAPTURE_TIMEOUT_SECONDS:-900}"
active_architecture="arm64"
script_root="$(cd "$(dirname "$0")" && pwd)"
source "$script_root/macos-bundle-manifest.sh"

mkdir -p "$evidence"
verdict_file="$evidence/distribution-launch-verdict.txt"

fail() {
  local message="$1"
  {
    printf 'launch_verdict=failed\n'
    printf 'failure=%s\n' "$message"
  } > "$verdict_file"
  echo "$message" >&2
  exit 1
}

mapped_paths_from_lsof() {
  awk '
    $0 == "ftxt" { is_text = 1; next }
    /^f/ { is_text = 0; next }
    is_text && /^n/ { print substr($0, 2) }
  ' "$1"
}

record_unique_mapped_paths() {
  local lsof_file="$1"
  local paths_file="$2"
  local mapped_path=""
  while IFS= read -r mapped_path; do
    [[ -n "$mapped_path" ]] || continue
    if ! grep -Fxq "$mapped_path" "$paths_file"; then
      printf '%s\n' "$mapped_path" >> "$paths_file"
    fi
  done < <(mapped_paths_from_lsof "$lsof_file")
}

macho_runpaths() {
  otool -arch "$active_architecture" -l "$1" 2>/dev/null | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { want_path = 1; next }
    want_path && $1 == "path" {
      runpath = $0
      sub(/^[[:space:]]*path[[:space:]]+/, "", runpath)
      sub(/[[:space:]]+\(offset[[:space:]]+[0-9]+\)[[:space:]]*$/, "", runpath)
      if (runpath != "") print runpath
      want_path = 0
    }
  '
}

macho_dependencies() {
  otool -arch "$active_architecture" -l "$1" 2>/dev/null | awk '
    $1 == "cmd" {
      kind = $2
      linked = kind ~ /^LC_(LOAD_DYLIB|LOAD_WEAK_DYLIB|REEXPORT_DYLIB|LOAD_UPWARD_DYLIB|LAZY_LOAD_DYLIB)$/
      next
    }
    linked && $1 == "name" {
      dependency = $0
      sub(/^[[:space:]]*name[[:space:]]+/, "", dependency)
      sub(/[[:space:]]+\(offset[[:space:]]+[0-9]+\)[[:space:]]*$/, "", dependency)
      if (dependency != "") printf "%s\t%s\n", kind, dependency
      linked = 0
    }
  '
}

require_active_architecture() {
  local executable="$1"
  if ! lipo "$executable" -verify_arch "$active_architecture" >/dev/null 2>&1; then
    fail "bundled Mach-O has no $active_architecture slice: $executable"
  fi
}

is_macho() {
  file -b "$1" 2>/dev/null | awk '
    index($0, "Mach-O") { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

expand_runpath() {
  local raw="$1"
  local owner="$2"
  local expanded=""
  local expanded_dir=""

  case "$raw" in
    @loader_path*)
      expanded="$(dirname "$owner")${raw#@loader_path}"
      ;;
    @executable_path*)
      expanded="$(dirname "$source_executable")${raw#@executable_path}"
      ;;
    /*)
      expanded="$raw"
      ;;
    *)
      return 1
      ;;
  esac

  if [[ -d "$expanded" ]]; then
    expanded_dir="$(cd "$expanded" && pwd -P)"
    printf '%s\n' "$expanded_dir"
  else
    printf '%s\n' "$expanded"
  fi
}

canonical_existing_file() {
  local requested="$1"
  local canonical_dir=""
  local link_target=""
  local link_count=0
  [[ -f "$requested" ]] || return 1

  while [[ -L "$requested" ]]; do
    link_count=$((link_count + 1))
    (( link_count <= 40 )) || return 1
    link_target="$(readlink "$requested")"
    case "$link_target" in
      /*) requested="$link_target" ;;
      *) requested="$(dirname "$requested")/$link_target" ;;
    esac
  done
  canonical_dir="$(cd "$(dirname "$requested")" && pwd -P)"
  printf '%s/%s\n' "$canonical_dir" "$(basename "$requested")"
}

capture_process_images() {
  local sample_pid=""
  local sample_start=""
  local expected_start=""
  local current_start=""
  current_start="$(ps -p "$pid" -o lstart= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ "$current_start" == "$initial_process_start" ]] \
    || fail "launched process start time changed before dyld image capture"
  printf '%s\n' "$current_start" > "$evidence/process-start-before-sample.txt"
  if ! run_bounded_process_sample "$pid" "$evidence"; then
    fail "could not capture launched process dyld images: $pid"
  fi
  current_start="$(ps -p "$pid" -o lstart= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s\n' "$current_start" > "$evidence/process-start-after-sample.txt"
  [[ "$current_start" == "$initial_process_start" ]] \
    || fail "launched process start time changed during dyld image capture"
  sample_pid="$(sed -n 's/^Process:.*\[\([0-9][0-9]*\)\]$/\1/p' "$evidence/process-sample.txt")"
  [[ "$sample_pid" == "$pid" ]] \
    || fail "dyld image sample does not match launched process PID"
  sample_start="$(awk '
    /^Launch Time:/ {
      start = $0
      sub(/^Launch Time:[[:space:]]*/, "", start)
      day = substr(start, 1, 10)
      sub(/^[^[:space:]]+[[:space:]]+/, "", start)
      split(start, parts, ":")
      hour = parts[1] + 0
      minute = parts[2] + 0
      second = parts[3] + 0
      if (index(start, "AM") && hour == 12) hour = 0
      if (index(start, "PM") && hour < 12) hour += 12
      printf "%s %02d:%02d:%02d\n", day, hour, minute, second
    }
  ' "$evidence/process-sample.txt")"
  expected_start="$(LC_ALL=C date -j -f '%a %b %e %T %Y' \
    "$initial_process_start" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" \
    || fail "could not normalize launched process start time"
  [[ "$sample_start" == "$expected_start" ]] \
    || fail "dyld image sample does not match launched process start time"
  awk '
    /^Binary Images:$/ { images = 1; next }
    images && /^[[:space:]]*0x[0-9a-fA-F]+[[:space:]]+-/ && /<[0-9A-Fa-f-]+> \// {
      uuid = $0
      sub(/^.*</, "", uuid)
      sub(/>.*$/, "", uuid)
      path = $0
      sub(/^.*> /, "", path)
      printf "%s\t%s\n", toupper(uuid), path
    }
  ' "$evidence/process-sample.txt" > "$evidence/process-dyld-images.tsv"
  [[ -s "$evidence/process-dyld-images.tsv" ]] \
    || fail "dyld image sample contains no process images"
  source_uuid="$(dwarfdump --uuid "$source_executable" \
    | awk '$3 == "(arm64)" { print toupper($2) }')"
  [[ -n "$source_uuid" ]] \
    || fail "source executable has no ARM64 image UUID"
  awk -F '\t' -v uuid="$source_uuid" '$1 == uuid { found = 1 } END { exit(!found) }' \
    "$evidence/process-dyld-images.tsv" \
    || fail "dyld image sample does not contain the downloaded executable UUID"
}

resolve_dependency_path() {
  local requested="$1"
  local receipt=""
  local observer_uuid=""
  local contains=""
  local receipt_path=""
  local canonical=""
  local image_uuid=""
  receipt="$("$evidence/dyld-cache-probe" resolve "$requested")" \
    || fail "could not query active dyld cache dependency: $requested"
  printf '%s\n' "$receipt" >> "$evidence/dyld-cache-path-queries.tsv"
  IFS=$'\t' read -r observer_uuid contains receipt_path canonical image_uuid <<< "$receipt"
  [[ "$observer_uuid" == "$active_cache_uuid" && "$receipt_path" == "$requested" ]] \
    || fail "active dyld cache identity changed during dependency resolution"
  case "$contains" in
    1)
      [[ "$canonical" == /* && "$image_uuid" =~ ^[0-9A-F-]{36}$ ]] \
        || fail "active dyld cache returned an invalid image identity: $requested"
      printf 'cache\t%s\t%s\n' "$canonical" "$image_uuid"
      ;;
    0)
      [[ -z "$canonical" && -z "$image_uuid" ]] \
        || fail "active dyld cache returned an inconsistent missing path: $requested"
      canonical="$(canonical_existing_file "$requested" 2>/dev/null || true)"
      [[ -z "$canonical" ]] || printf 'file\t%s\n' "$canonical"
      ;;
    *) fail "active dyld cache returned invalid membership: $requested" ;;
  esac
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "macOS distribution launch verification requires macOS"
fi

if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
  fail "running PID must be numeric: $pid"
fi

if [[ ! "$stability_seconds" =~ ^[0-9]+$ ]]; then
  fail "DISTRIBUTION_E2E_STABILITY_SECONDS must be a non-negative integer"
fi

case "$require_translocation" in
  true|false) ;;
  *) fail "DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION must be true or false" ;;
esac
case "$require_appkit_finished" in
  true|false) ;;
  *) fail "DISTRIBUTION_E2E_REQUIRE_APPKIT_FINISHED must be true or false" ;;
esac
case "$capture_until_exit" in
  true|false) ;;
  *) fail "DISTRIBUTION_E2E_CAPTURE_MAPPED_CODE_UNTIL_EXIT must be true or false" ;;
esac
if [[ ! "$appkit_timeout_seconds" =~ ^[0-9]+$ ]]; then
  fail "DISTRIBUTION_E2E_APPKIT_TIMEOUT_SECONDS must be a non-negative integer"
fi
if [[ ! "$capture_timeout_seconds" =~ ^[0-9]+$ ]] \
  || (( capture_timeout_seconds < 1 )); then
  fail "DISTRIBUTION_E2E_CAPTURE_TIMEOUT_SECONDS must be a positive integer"
fi

if [[ ! -d "$requested_app" ]]; then
  fail "source app bundle is missing: $requested_app"
fi
app="$(cd "$(dirname "$requested_app")" && pwd -P)/$(basename "$requested_app")"

info_plist="$app/Contents/Info.plist"
if [[ ! -f "$info_plist" ]]; then
  fail "source app is missing Info.plist: $info_plist"
fi

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist" 2>/dev/null)" \
  || fail "source app has no CFBundleExecutable"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null)" \
  || fail "source app has no CFBundleIdentifier"
source_executable="$app/Contents/MacOS/$executable_name"
if [[ ! -x "$source_executable" ]]; then
  fail "source app executable is missing: $source_executable"
fi
if [[ "$(uname -m)" != "$active_architecture" ]]; then
  fail "distribution launch verifier requires an Apple Silicon host"
fi
require_active_architecture "$source_executable"

product_version="$(sw_vers -productVersion)"
build_version="$(sw_vers -buildVersion)"
{
  sw_vers
  uname -a
  printf 'architecture=%s\n' "$(uname -m)"
  printf 'expected_product_version=%s\n' "${expected_macos_version:-not-enforced}"
  printf 'expected_build_version=%s\n' "${expected_macos_build:-not-enforced}"
} > "$evidence/macos-version.txt"

if [[ -n "$expected_macos_version" && "$product_version" != "$expected_macos_version" ]]; then
  fail "expected macOS $expected_macos_version, got $product_version"
fi
if [[ -n "$expected_macos_build" && "$build_version" != "$expected_macos_build" ]]; then
  fail "expected macOS build $expected_macos_build, got $build_version"
fi

if ! quarantine="$(xattr -p com.apple.quarantine "$app" 2>/dev/null)"; then
  fail "source app is missing download quarantine"
fi
printf '%s\n' "$quarantine" > "$evidence/source-app-quarantine.txt"

IFS=';' read -r quarantine_flags quarantine_timestamp quarantine_agent quarantine_origin <<< "$quarantine"
if [[ -z "${quarantine_flags:-}" || -z "${quarantine_timestamp:-}" || -z "${quarantine_agent:-}" ]]; then
  fail "source app has malformed download quarantine: $quarantine"
fi
if [[ -n "$expected_quarantine_agent" && "$quarantine_agent" != "$expected_quarantine_agent" ]]; then
  fail "expected quarantine agent $expected_quarantine_agent, got $quarantine_agent"
fi

if ! codesign --verify --deep --strict --verbose=4 "$app" \
  > "$evidence/codesign-verify.txt" 2>&1; then
  fail "source app fails strict deep signature verification"
fi
codesign -dvvv "$app" > "$evidence/app-signature.txt" 2>&1 \
  || fail "could not inspect source app signature"

process_state() {
  ps -p "$pid" -o stat= 2>/dev/null | tr -d '[:space:]'
}

assert_process_running() {
  local state
  if ! kill -0 "$pid" 2>/dev/null; then
    fail "launched process is not running: $pid"
  fi
  state="$(process_state)"
  if [[ -z "$state" ]]; then
    fail "could not inspect launched process state: $pid"
  fi
  if [[ "$state" == *T* ]]; then
    fail "launched process is stopped: $pid ($state)"
  fi
  if [[ "$state" == *Z* || "$state" == *X* ]]; then
    fail "launched process is not usable: $pid ($state)"
  fi
  printf '%s\n' "$state"
}

initial_state="$(assert_process_running)"
initial_process_start="$(ps -p "$pid" -o lstart= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[[ -n "$initial_process_start" ]] || fail "could not inspect launched process start time"
printf '%s\n' "$initial_process_start" > "$evidence/process-start.txt"

if ! vmmap -summary "$pid" > "$evidence/process-vmmap-summary.txt" 2>&1; then
  fail "could not inspect launched process architecture: $pid"
fi
process_code_type="$(
  sed -n 's/^Code Type:[[:space:]]*//p' \
    "$evidence/process-vmmap-summary.txt" \
    | awk 'NR == 1 { print; exit }'
)"
if [[ -z "$process_code_type" ]] \
  || ! grep -Eiq '^ARM-?64(E)?([[:space:]]|$)' <<< "$process_code_type" \
  || grep -Eiq 'translated|x86' <<< "$process_code_type"; then
  fail "launched process is not native Apple Silicon: ${process_code_type:-unknown}"
fi

if [[ "$require_appkit_finished" == "true" ]]; then
  appkit_deadline=$((SECONDS + appkit_timeout_seconds))
  appkit_finished="false"
  while (( SECONDS <= appkit_deadline )); do
    appkit_finished="$(
      DISTRIBUTION_E2E_RUNNING_PID="$pid" /usr/bin/osascript -l JavaScript -e '
        ObjC.import("AppKit")
        const value = $.NSProcessInfo.processInfo.environment.objectForKey(
          "DISTRIBUTION_E2E_RUNNING_PID"
        )
        const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(
          Number(ObjC.unwrap(value))
        )
        app ? ObjC.unwrap(app.finishedLaunching) : false
      ' 2>/dev/null || true
    )"
    if [[ "$appkit_finished" == "true" ]]; then
      break
    fi
    sleep 1
  done
  printf 'is_finished_launching=%s\n' "$appkit_finished" \
    > "$evidence/appkit-running-application.txt"
  if [[ "$appkit_finished" != "true" ]]; then
    fail "launched process did not finish AppKit launch"
  fi
fi

if ! lsof -p "$pid" -Ffn > "$evidence/process-open-files.txt" 2>&1; then
  fail "could not inspect launched process files: $pid"
fi

process_executable="$({
  mapped_paths_from_lsof "$evidence/process-open-files.txt" \
    | awk -v suffix="/Contents/MacOS/$executable_name" \
      'substr($0, length($0) - length(suffix) + 1) == suffix && !found {
        result = $0
        found = 1
      }
      END { if (found) print result }'
} || true)"
if [[ -z "$process_executable" ]]; then
  fail "running process does not map the expected app executable"
fi
process_app="${process_executable%/Contents/MacOS/$executable_name}"

process_info_plist="$process_app/Contents/Info.plist"
if [[ ! -f "$process_info_plist" ]]; then
  fail "running process bundle is missing Info.plist: $process_info_plist"
fi
process_bundle_identifier="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$process_info_plist" 2>/dev/null
)" || fail "running process bundle has no CFBundleIdentifier"
if [[ "$process_bundle_identifier" != "$bundle_identifier" ]]; then
  fail "running process bundle identifier does not match the downloaded app"
fi

if [[ "$require_translocation" == "true" ]]; then
  case "$process_app" in
    */AppTranslocation/*/d/*.app) ;;
    *) fail "launched process is not running through App Translocation: $process_app" ;;
  esac
fi

source_executable_sha="$(shasum -a 256 "$source_executable" | awk '{print $1}')"
process_executable_sha="$(shasum -a 256 "$process_executable" | awk '{print $1}')"
observed_translocation=false
case "$process_app" in
  */AppTranslocation/*/d/*.app) observed_translocation=true ;;
esac
{
  printf 'pid=%s\n' "$pid"
  printf 'bundle_identifier=%s\n' "$bundle_identifier"
  printf 'source_app=%s\n' "$app"
  printf 'process_app=%s\n' "$process_app"
  printf 'process_executable=%s\n' "$process_executable"
  printf 'source_executable_sha256=%s\n' "$source_executable_sha"
  printf 'process_executable_sha256=%s\n' "$process_executable_sha"
  printf 'process_code_type=%s\n' "$process_code_type"
  printf 'initial_state=%s\n' "$initial_state"
  printf 'observed_translocation=%s\n' "$observed_translocation"
} > "$evidence/launch-identity.txt"

if [[ "$source_executable_sha" != "$process_executable_sha" ]]; then
  fail "running executable does not match the downloaded app"
fi

write_macos_bundle_manifest "$app" "$evidence/source-bundle-files.sha256"
write_macos_bundle_manifest "$process_app" "$evidence/process-bundle-files.sha256"
if ! cmp -s \
  "$evidence/source-bundle-files.sha256" \
  "$evidence/process-bundle-files.sha256"; then
  diff -u \
    "$evidence/source-bundle-files.sha256" \
    "$evidence/process-bundle-files.sha256" \
    > "$evidence/source-process-bundle.diff" || true
  fail "running process bundle does not match the downloaded app bundle"
fi
if ! codesign --verify --deep --strict --verbose=4 "$process_app" \
  > "$evidence/process-app-codesign-verify.txt" 2>&1; then
  fail "running process app fails strict deep signature verification"
fi

expected_code="$evidence/expected-mapped-bundle-code.txt"
observed_code="$evidence/observed-mapped-bundle-code.txt"
mapped_paths="$evidence/process-mapped-paths-through-runtime.txt"
: > "$expected_code"
: > "$observed_code"
: > "$mapped_paths"
: > "$evidence/mapped-code-signatures.txt"
: > "$evidence/bundle-dependency-resolution.txt"
: > "$evidence/unresolved-external-or-cache-dependencies.txt"
: > "$evidence/optional-weak-dependencies.txt"
: > "$evidence/dyld-cache-path-queries.tsv"
: > "$evidence/cache-dependency-resolution.tsv"

if ! build_dyld_cache_probe "$evidence" \
  > "$evidence/dyld-cache-probe-build.stdout.txt" \
  2> "$evidence/dyld-cache-probe-build.stderr.txt"; then
  fail "could not build native active dyld cache observer"
fi
active_cache_uuid="$("$evidence/dyld-cache-probe" identity)" \
  || fail "could not identify active dyld cache"
[[ "$active_cache_uuid" =~ ^[0-9A-F-]{36}$ ]] \
  || fail "active dyld cache has an invalid UUID"
printf '%s\n' "$active_cache_uuid" > "$evidence/observer-dyld-cache-uuid.txt"
capture_process_images

record_unique_mapped_paths "$evidence/process-open-files.txt" "$mapped_paths"
if [[ "$capture_until_exit" == "true" ]]; then
  capture_lsof="$evidence/process-open-files-runtime-sample.txt"
  capture_deadline=$((SECONDS + capture_timeout_seconds))
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS >= capture_deadline )); then
      fail "timed out waiting for the runtime process to finish: $pid"
    fi
    if lsof -p "$pid" -Ffn > "$capture_lsof" 2>/dev/null; then
      record_unique_mapped_paths "$capture_lsof" "$mapped_paths"
    fi
    sleep 1
  done
fi

while IFS= read -r mapped_path; do
  case "$mapped_path" in
    "$process_app"/Contents/*)
      relative_mapped_path="${mapped_path#"$process_app"/}"
      if is_macho "$app/$relative_mapped_path"; then
        printf '%s\n' "$relative_mapped_path" >> "$observed_code"
      fi
      ;;
  esac
done < "$mapped_paths"
LC_ALL=C sort -u -o "$observed_code" "$observed_code"

queue=("$source_executable")
queue_runpaths=("")
queue_index=0
while (( queue_index < ${#queue[@]} )); do
  candidate="${queue[$queue_index]}"
  inherited_runpaths="${queue_runpaths[$queue_index]}"
  queue_index=$((queue_index + 1))

  if ! is_macho "$candidate"; then
    continue
  fi
  require_active_architecture "$candidate"
  if ! otool -arch "$active_architecture" -l "$candidate" >/dev/null 2>&1; then
    fail "could not inspect bundled Mach-O dependencies: $candidate"
  fi

  current_runpaths=""
  while IFS= read -r raw_runpath; do
    [[ -n "$raw_runpath" ]] || continue
    expanded_runpath="$(expand_runpath "$raw_runpath" "$candidate" 2>/dev/null || true)"
    [[ -n "$expanded_runpath" ]] || continue
    if ! grep -Fxq "$expanded_runpath" <<< "$current_runpaths"; then
      if [[ -n "$current_runpaths" ]]; then
        current_runpaths+=$'\n'
      fi
      current_runpaths+="$expanded_runpath"
    fi
  done < <(macho_runpaths "$candidate")
  while IFS= read -r inherited_runpath; do
    [[ -n "$inherited_runpath" ]] || continue
    if ! grep -Fxq "$inherited_runpath" <<< "$current_runpaths"; then
      [[ -z "$current_runpaths" ]] || current_runpaths+=$'\n'
      current_runpaths+="$inherited_runpath"
    fi
  done <<< "$inherited_runpaths"

  while IFS=$'\t' read -r dependency_kind reference; do
    [[ -n "$reference" ]] || continue
    resolved=""
    resolution_kind=""
    resolved_uuid=""
    bundle_required="false"
    requested_path=""
    case "$reference" in
      @executable_path/*)
        requested_path="$(dirname "$source_executable")/${reference#@executable_path/}"
        resolved="$(
          resolve_dependency_path "$requested_path"
        )" || exit 1
        ;;
      @loader_path/*)
        requested_path="$(dirname "$candidate")/${reference#@loader_path/}"
        resolved="$(
          resolve_dependency_path "$requested_path"
        )" || exit 1
        ;;
      @rpath/*)
        suffix="${reference#@rpath/}"
        while IFS= read -r runpath; do
          [[ -n "$runpath" ]] || continue
          resolved="$(resolve_dependency_path "$runpath/$suffix")" \
            || exit 1
          [[ -n "$resolved" ]] && break
        done <<< "$current_runpaths"
        if find "$app/Contents" \( -type f -o -type l \) -print 2>/dev/null \
          | awk -v suffix="/$suffix" '
              substr($0, length($0) - length(suffix) + 1) == suffix { found = 1 }
              END { exit(found ? 0 : 1) }
            '; then
          bundle_required="true"
        fi
        ;;
      "$app"/Contents/*)
        bundle_required="true"
        requested_path="$reference"
        resolved="$(resolve_dependency_path "$reference")" \
          || exit 1
        ;;
      /*)
        resolved="$(resolve_dependency_path "$reference")" \
          || exit 1
        ;;
    esac

    IFS=$'\t' read -r resolution_kind resolved resolved_uuid <<< "$resolved"
    if [[ "$resolution_kind" == "cache" ]]; then
      if ! awk -F '\t' -v uuid="$resolved_uuid" -v path="$resolved" \
        '$1 == uuid && $2 == path { found = 1 } END { exit(!found) }' \
        "$evidence/process-dyld-images.tsv"; then
        if [[ "$dependency_kind" == "LC_LOAD_WEAK_DYLIB" ]]; then
          printf '%s\t%s\t%s\t%s\tunmapped-cache\n' \
            "${candidate#"$app"/}" "$dependency_kind" "$reference" "$resolved" \
            >> "$evidence/optional-weak-dependencies.txt"
          continue
        fi
        fail "launched process did not map active cache dependency: $resolved ($resolved_uuid)"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${candidate#"$app"/}" "$dependency_kind" "$reference" "$resolved" \
        "$resolved_uuid" "$active_cache_uuid" \
        >> "$evidence/cache-dependency-resolution.tsv"
      continue
    fi

    if [[ -n "$requested_path" ]]; then
      case "$requested_path" in
        "$app"/Contents/*) bundle_required="true" ;;
      esac
    fi

    if [[ -z "$resolved" || ! -f "$resolved" ]]; then
      if [[ "$dependency_kind" == "LC_LOAD_WEAK_DYLIB" ]]; then
        printf '%s\t%s\t%s\t\tunresolved\n' \
          "${candidate#"$app"/}" "$dependency_kind" "$reference" \
          >> "$evidence/optional-weak-dependencies.txt"
        continue
      fi
      if [[ "$bundle_required" == "true" ]]; then
        fail "could not resolve bundled dependency: $reference from ${candidate#"$app"/}"
      fi
      printf '%s\t%s\n' \
        "${candidate#"$app"/}" \
        "$reference" \
        >> "$evidence/unresolved-external-or-cache-dependencies.txt"
      continue
    fi
    case "$resolved" in
      "$app"/Contents/*) ;;
      *)
        printf '%s\t%s\t%s\n' \
          "${candidate#"$app"/}" \
          "$reference" \
          "$resolved" \
          >> "$evidence/unresolved-external-or-cache-dependencies.txt"
        continue
        ;;
    esac

    relative="${resolved#"$app"/}"
    printf '%s\t%s\t%s\n' \
      "${candidate#"$app"/}" \
      "$reference" \
      "$relative" \
      >> "$evidence/bundle-dependency-resolution.txt"
    if [[ "$dependency_kind" == "LC_LOAD_WEAK_DYLIB" ]]; then
      weak_mapping="mapped"
      if ! grep -Fxq "$relative" "$observed_code"; then
        weak_mapping="unmapped"
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "${candidate#"$app"/}" "$dependency_kind" "$reference" \
        "$relative" "$weak_mapping" \
        >> "$evidence/optional-weak-dependencies.txt"
      # dyld permits absent weak images and only loads children of images it maps.
      [[ "$weak_mapping" == "mapped" ]] || continue
    fi
    if ! grep -Fxq "$relative" "$expected_code"; then
      printf '%s\n' "$relative" >> "$expected_code"
      queue+=("$resolved")
      queue_runpaths+=("$current_runpaths")
    fi
  done < <(macho_dependencies "$candidate")
done

while IFS= read -r expected_relative; do
  [[ -n "$expected_relative" ]] || continue
  if ! grep -Fxq "$expected_relative" "$observed_code"; then
    fail "launched process did not map bundled dependency: $expected_relative"
  fi
done < "$expected_code"

while IFS= read -r observed_relative; do
  [[ -n "$observed_relative" ]] || continue
  require_active_architecture "$app/$observed_relative"
  if ! codesign --verify --strict --verbose=2 "$app/$observed_relative" \
    >> "$evidence/mapped-code-signatures.txt" 2>&1; then
    fail "mapped bundled code fails signature verification: $observed_relative"
  fi
done < "$observed_code"

if command -v log >/dev/null 2>&1; then
  log show --style compact --last 5m \
    --predicate "processIdentifier == $pid" \
    > "$evidence/process-unified-log.txt" 2>&1 || true
  if grep -Eiq 'Library not loaded|code signature .*not valid for use in process|Namespace DYLD|DYLD, Code 1' \
    "$evidence/process-unified-log.txt"; then
    fail "dyld or code-signature failure appears in the launched process log"
  fi
fi

if [[ "$capture_until_exit" == "true" ]]; then
  final_state="exited-after-runtime-observation"
else
  if (( stability_seconds > 0 )); then
    sleep "$stability_seconds"
  fi
  final_state="$(assert_process_running)"
  if ! lsof -p "$pid" -Ffn > "$evidence/process-open-files-after-stability.txt" 2>&1; then
    fail "could not reinspect launched process after stability interval"
  fi
  if ! mapped_paths_from_lsof "$evidence/process-open-files-after-stability.txt" \
    | awk -v expected="$process_executable" \
      '$0 == expected { found = 1 } END { exit(found ? 0 : 1) }'; then
    fail "launched process executable changed during stability interval"
  fi
fi

{
  printf 'launch_verdict=passed\n'
  printf 'pid=%s\n' "$pid"
  printf 'product_version=%s\n' "$product_version"
  printf 'build_version=%s\n' "$build_version"
  printf 'quarantine_agent=%s\n' "$quarantine_agent"
  printf 'process_app=%s\n' "$process_app"
  printf 'process_code_type=%s\n' "$process_code_type"
  printf 'active_architecture=%s\n' "$active_architecture"
  printf 'capture_mapped_code_until_exit=%s\n' "$capture_until_exit"
  printf 'initial_state=%s\n' "$initial_state"
  printf 'final_state=%s\n' "$final_state"
  printf 'stability_seconds=%s\n' "$stability_seconds"
  printf 'expected_bundle_dependency_count=%s\n' "$(awk 'NF { count++ } END { print count + 0 }' "$expected_code")"
  printf 'observed_bundle_code_count=%s\n' "$(awk 'NF { count++ } END { print count + 0 }' "$observed_code")"
} > "$verdict_file"

echo "macOS distribution launch verified for PID $pid"
