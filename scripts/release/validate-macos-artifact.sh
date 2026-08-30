#!/usr/bin/env bash
#
# Validate the EXACT artifact that will be uploaded to GitHub Releases.
#
# The artifact (ZIP or DMG) is expanded/mounted into a clean temporary
# directory and every check runs against that copy - never against the build
# directory - because the failure this guards against (nested framework
# rejected for a Team ID mismatch) only shows up once macOS loads a downloaded,
# quarantined, possibly translocated copy of the app.
#
# Usage:
#   validate-macos-artifact.sh --artifact <zip|dmg|app>
#       [--expect-team-id <id>] [--expect-notarized]
#       [--require-hardened-runtime] [--allow-adhoc]
#       [--simulate-quarantine] [--skip-launch] [--launch-timeout <seconds>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/release/lib.sh
. "$SCRIPT_DIR/lib.sh"

ARTIFACT=""
EXPECT_TEAM_ID=""
EXPECT_NOTARIZED=0
REQUIRE_HARDENED_RUNTIME=0
ALLOW_ADHOC=0
SIMULATE_QUARANTINE=0
SKIP_LAUNCH=0
LAUNCH_TIMEOUT=10
FAILURES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --artifact) ARTIFACT="$2"; shift 2 ;;
    --expect-team-id) EXPECT_TEAM_ID="$2"; shift 2 ;;
    --expect-notarized) EXPECT_NOTARIZED=1; REQUIRE_HARDENED_RUNTIME=1; SIMULATE_QUARANTINE=1; shift ;;
    --require-hardened-runtime) REQUIRE_HARDENED_RUNTIME=1; shift ;;
    --allow-adhoc) ALLOW_ADHOC=1; shift ;;
    --simulate-quarantine) SIMULATE_QUARANTINE=1; shift ;;
    --no-simulate-quarantine) SIMULATE_QUARANTINE=0; shift ;;
    --skip-launch) SKIP_LAUNCH=1; shift ;;
    --launch-timeout) LAUNCH_TIMEOUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) rel_fail "unknown argument: $1" ;;
  esac
done

rel_require_macos
[ -n "$ARTIFACT" ] || rel_fail "--artifact is required"
[ -e "$ARTIFACT" ] || rel_fail "artifact not found: $ARTIFACT"
ARTIFACT="$(cd "$(dirname "$ARTIFACT")" && pwd)/$(basename "$ARTIFACT")"

fail_check() { rel_err "$*"; FAILURES=$((FAILURES + 1)); }
pass_check() { rel_ok "$*"; }

STAGE_DIR="$(rel_mktemp_dir)"
MOUNT_POINT=""
cleanup() {
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

########################################
rel_step "Expanding the release artifact into a clean directory"
rel_info "artifact: $ARTIFACT"
rel_info "staging:  $STAGE_DIR"

EXTRACT_DIR="$STAGE_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

case "$ARTIFACT" in
  *.zip)
    ditto -x -k "$ARTIFACT" "$EXTRACT_DIR" || rel_fail "the ZIP artifact could not be expanded"
    ;;
  *.dmg)
    MOUNT_POINT="$STAGE_DIR/mnt"
    mkdir -p "$MOUNT_POINT"
    hdiutil attach "$ARTIFACT" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet \
      || rel_fail "the DMG artifact could not be mounted"
    APP_IN_DMG="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -type d | head -1)"
    [ -n "$APP_IN_DMG" ] || rel_fail "no .app found inside the DMG"
    # Copy out so the launch test exercises a writable, quarantinable copy.
    ditto "$APP_IN_DMG" "$EXTRACT_DIR/$(basename "$APP_IN_DMG")"
    hdiutil detach "$MOUNT_POINT" -quiet
    MOUNT_POINT=""
    ;;
  *.app)
    ditto "$ARTIFACT" "$EXTRACT_DIR/$(basename "$ARTIFACT")"
    ;;
  *) rel_fail "unsupported artifact type: $ARTIFACT (expected .zip, .dmg or .app)" ;;
esac

APP="$(find "$EXTRACT_DIR" -maxdepth 2 -name '*.app' -type d | head -1)"
[ -n "$APP" ] || rel_fail "no .app found in the expanded artifact"
rel_info "app: $APP"

if [ "$(basename "$APP")" = "$RELEASE_APP_NAME" ]; then
  pass_check "artifact contains $RELEASE_APP_NAME"
else
  fail_check "expected $RELEASE_APP_NAME, found $(basename "$APP")"
fi

########################################
rel_step "Bundle structure"

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist" 2>/dev/null || echo '')"
if [ "$BUNDLE_ID" = "$RELEASE_BUNDLE_ID" ]; then
  pass_check "bundle identifier $BUNDLE_ID"
else
  fail_check "bundle identifier is '$BUNDLE_ID', expected '$RELEASE_BUNDLE_ID'"
fi

MAIN_EXECUTABLE="$(rel_main_executable "$APP")"
if [ -x "$MAIN_EXECUTABLE" ]; then
  pass_check "main executable $(basename "$MAIN_EXECUTABLE")"
else
  fail_check "main executable missing: $MAIN_EXECUTABLE"
fi

for debris in "$APP"/Contents/MacOS/*.debug.dylib "$APP"/Contents/MacOS/__preview.dylib; do
  if [ -e "$debris" ]; then
    fail_check "debug-only payload present in the release artifact: $debris"
  fi
done

BROKEN_LINKS="$(find "$APP" -type l ! -exec test -e {} \; -print 2>/dev/null || true)"
if [ -n "$BROKEN_LINKS" ]; then
  fail_check "broken symlinks inside the bundle:"
  printf '%s\n' "$BROKEN_LINKS" | sed 's/^/         /' >&2
else
  pass_check "no broken symlinks"
fi

for framework in $RELEASE_REQUIRED_FRAMEWORKS; do
  FW="$APP/Contents/Frameworks/$framework"
  NAME="${framework%.framework}"
  if [ ! -d "$FW" ]; then
    fail_check "$framework is missing from Contents/Frameworks"
    continue
  fi
  pass_check "$framework is embedded"
  if [ -d "$FW/Versions" ]; then
    VERSION_DIR="$(find "$FW/Versions" -mindepth 1 -maxdepth 1 -type d ! -type l | head -1)"
    if [ -z "$VERSION_DIR" ]; then
      fail_check "$framework has no versioned directory"
    elif [ ! -f "$VERSION_DIR/$NAME" ]; then
      fail_check "$framework is missing $(basename "$VERSION_DIR")/$NAME"
    else
      pass_check "$framework/$(basename "$VERSION_DIR")/$NAME exists"
    fi
    if [ -L "$FW/Versions/Current" ] && [ -e "$FW/Versions/Current" ]; then
      pass_check "$framework Versions/Current resolves"
    else
      fail_check "$framework Versions/Current is missing or broken"
    fi
    if [ -L "$FW/$NAME" ] && [ -e "$FW/$NAME" ]; then
      pass_check "$framework/$NAME symlink resolves"
    elif [ -f "$FW/$NAME" ]; then
      pass_check "$framework/$NAME is a regular file"
    else
      fail_check "$framework/$NAME is missing or a broken symlink"
    fi
  fi
done

########################################
rel_step "Application signature"

if codesign --verify --deep --strict --verbose=4 "$APP" 2>&1 | sed 's/^/      /'; then
  pass_check "codesign --verify --deep --strict passed"
else
  fail_check "codesign --verify --deep --strict FAILED for the packaged app"
fi

codesign -dv --verbose=4 "$APP" 2>&1 | sed 's/^/      /' || true

APP_TEAM_ID="$(rel_team_id "$APP")"
APP_AUTHORITY="$(rel_signing_authority "$APP")"
rel_info "team identifier: ${APP_TEAM_ID:-<not set / ad-hoc>}"
rel_info "authority:       ${APP_AUTHORITY:-<none>}"

if [ -n "$EXPECT_TEAM_ID" ]; then
  if [ "$APP_TEAM_ID" = "$EXPECT_TEAM_ID" ]; then
    pass_check "team identifier matches $EXPECT_TEAM_ID"
  else
    fail_check "team identifier is '${APP_TEAM_ID:-not set}', expected '$EXPECT_TEAM_ID'"
  fi
elif [ -z "$APP_TEAM_ID" ]; then
  if [ "$ALLOW_ADHOC" -eq 1 ]; then
    rel_warn "app is ad-hoc signed (no Team ID). Development build only - never publish this."
  else
    fail_check "app has no Team ID (ad-hoc signed). Public releases require Developer ID signing; pass --allow-adhoc for a development check."
  fi
fi

case "$APP_AUTHORITY" in
  "Developer ID Application"*) pass_check "signed with $APP_AUTHORITY" ;;
  *) [ "$ALLOW_ADHOC" -eq 1 ] || fail_check "app is not signed with a Developer ID Application certificate (authority: ${APP_AUTHORITY:-none})" ;;
esac

if rel_has_hardened_runtime "$APP"; then
  pass_check "hardened runtime enabled"
elif [ "$REQUIRE_HARDENED_RUNTIME" -eq 1 ]; then
  fail_check "hardened runtime is not enabled on the app"
else
  rel_warn "hardened runtime is not enabled (expected for ad-hoc development builds)"
fi

########################################
rel_step "Nested code signatures"

NESTED_LIST="$STAGE_DIR/nested.txt"
{
  rel_nested_code_bundles "$APP"
  rel_nested_macho_files "$APP"
} > "$NESTED_LIST"

NESTED_COUNT=0
UNSIGNED_COUNT=0
MISMATCH_COUNT=0

while IFS= read -r item; do
  [ -n "$item" ] || continue
  [ "$item" = "$MAIN_EXECUTABLE" ] && continue
  NESTED_COUNT=$((NESTED_COUNT + 1))
  REL_PATH="${item#"$APP"/}"

  if ! codesign --verify --strict --verbose=2 "$item" >/dev/null 2>&1; then
    fail_check "nested code fails signature verification: $REL_PATH"
    UNSIGNED_COUNT=$((UNSIGNED_COUNT + 1))
    codesign --verify --strict --verbose=2 "$item" 2>&1 | sed 's/^/         /' >&2 || true
    continue
  fi

  ITEM_TEAM_ID="$(rel_team_id "$item")"
  if [ "$ITEM_TEAM_ID" != "$APP_TEAM_ID" ]; then
    # This is the exact condition that made macOS refuse to map
    # MediaRemoteAdapter.framework into the app process.
    fail_check "Team ID mismatch: $REL_PATH is '${ITEM_TEAM_ID:-not set}' but the app is '${APP_TEAM_ID:-not set}'"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
  fi
done < "$NESTED_LIST"

rel_info "checked $NESTED_COUNT nested code items"
[ "$UNSIGNED_COUNT" -eq 0 ] && pass_check "every nested executable and bundle carries a valid signature"
[ "$MISMATCH_COUNT" -eq 0 ] && pass_check "every nested code item shares the app's Team ID"

########################################
rel_step "Load commands and @rpath resolution"

RPATHS="$(otool -l "$MAIN_EXECUTABLE" | awk '/cmd LC_RPATH/{f=1} f&&/path /{print $2; f=0}')"
printf '%s\n' "$RPATHS" | sed 's/^/      LC_RPATH /'
if printf '%s\n' "$RPATHS" | grep -qx "$RELEASE_EXPECTED_RPATH"; then
  pass_check "LC_RPATH contains $RELEASE_EXPECTED_RPATH"
else
  fail_check "LC_RPATH does not contain $RELEASE_EXPECTED_RPATH"
fi

resolve_rpath_dependency() {
  # $1 = dependency install name beginning with @rpath/
  local dep="${1#@rpath/}"
  local candidate
  printf '%s\n' "$RPATHS" | while IFS= read -r rpath; do
    [ -n "$rpath" ] || continue
    case "$rpath" in
      @executable_path/*) candidate="$APP/Contents/MacOS/${rpath#@executable_path/}/$dep" ;;
      @loader_path/*) candidate="$APP/Contents/MacOS/${rpath#@loader_path/}/$dep" ;;
      *) candidate="$rpath/$dep" ;;
    esac
    if [ -e "$candidate" ]; then printf 'found\n'; return 0; fi
  done | grep -q found
}

UNRESOLVED=0
MEDIAREMOTE_LINKED=0
while IFS= read -r dep; do
  [ -n "$dep" ] || continue
  case "$dep" in
    *MediaRemoteAdapter*) MEDIAREMOTE_LINKED=1 ;;
  esac
  if resolve_rpath_dependency "$dep"; then
    rel_info "resolved $dep"
  else
    fail_check "unresolved @rpath dependency in the main executable: $dep"
    UNRESOLVED=$((UNRESOLVED + 1))
  fi
done <<DEPS
$(otool -L "$MAIN_EXECUTABLE" | awk 'NR>1 && $1 ~ /^@rpath\// { print $1 }')
DEPS

[ "$UNRESOLVED" -eq 0 ] && pass_check "every @rpath dependency of the main executable resolves inside the bundle"

if [ "$MEDIAREMOTE_LINKED" -eq 1 ]; then
  pass_check "main executable links MediaRemoteAdapter through @rpath"
else
  rel_warn "the main executable does not link MediaRemoteAdapter directly (it may be loaded by a nested framework)"
fi

########################################
rel_step "Gatekeeper assessment"

SPCTL_OUTPUT="$(spctl --assess --type exec -vvv "$APP" 2>&1 || true)"
printf '%s\n' "$SPCTL_OUTPUT" | sed 's/^/      /'
if printf '%s\n' "$SPCTL_OUTPUT" | grep -q 'accepted'; then
  pass_check "Gatekeeper accepts the app"
elif [ "$EXPECT_NOTARIZED" -eq 1 ]; then
  fail_check "Gatekeeper rejected the app"
else
  rel_warn "Gatekeeper rejected the app (expected for an unnotarized development build)"
fi

if [ "$EXPECT_NOTARIZED" -eq 1 ]; then
  if xcrun stapler validate "$APP" >/dev/null 2>&1; then
    pass_check "notarization ticket is stapled"
  else
    fail_check "no stapled notarization ticket on the packaged app"
  fi
fi

########################################
if [ "$SKIP_LAUNCH" -eq 1 ]; then
  rel_step "Launch test skipped (--skip-launch)"
else
  rel_step "Launching the extracted app"

  if [ "$SIMULATE_QUARANTINE" -eq 1 ]; then
    rel_info "marking the copy as downloaded so Gatekeeper and App Translocation apply"
    /usr/bin/xattr -w com.apple.quarantine "0083;00000000;ReleaseValidation;" "$APP" 2>/dev/null || \
      rel_warn "could not set the quarantine attribute"
  fi

  # Stage 1: exec the main binary. A rejected embedded framework (the
  # MediaRemoteAdapter Team ID failure) aborts here before any UI appears.
  LAUNCH_LOG="$STAGE_DIR/launch.log"
  "$MAIN_EXECUTABLE" >"$LAUNCH_LOG" 2>&1 &
  LAUNCH_PID=$!
  elapsed=0
  ALIVE=1
  while [ "$elapsed" -lt "$LAUNCH_TIMEOUT" ]; do
    if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
      ALIVE=0
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [ "$ALIVE" -eq 1 ]; then
    pass_check "the extracted app stayed running for ${elapsed}s after exec"
    kill "$LAUNCH_PID" 2>/dev/null || true
    wait "$LAUNCH_PID" 2>/dev/null || true
  else
    fail_check "the extracted app exited during launch"
  fi

  if [ -s "$LAUNCH_LOG" ]; then
    rel_info "launch output:"
    sed 's/^/      /' "$LAUNCH_LOG"
  fi
  if grep -qE 'Library not loaded|code signature.*not valid|different Team IDs|Abort trap|Symbol not found' "$LAUNCH_LOG" 2>/dev/null; then
    fail_check "the dynamic loader rejected an embedded library at launch"
  else
    pass_check "no dynamic loader or code-signature errors at launch"
  fi

  # Stage 2: launch through LaunchServices so Gatekeeper and, for a quarantined
  # copy, App Translocation are exercised exactly as on a user's machine.
  rel_step "Launching through LaunchServices"
  if open -n -a "$APP" >"$STAGE_DIR/open.log" 2>&1; then
    launched=0
    elapsed=0
    while [ "$elapsed" -lt "$LAUNCH_TIMEOUT" ]; do
      if pgrep -f "$(basename "$MAIN_EXECUTABLE")" >/dev/null 2>&1; then
        launched=1
        break
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done
    if [ "$launched" -eq 1 ]; then
      pass_check "LaunchServices started the app (Gatekeeper allowed it)"
      sleep 3
      if pgrep -f "$(basename "$MAIN_EXECUTABLE")" >/dev/null 2>&1; then
        pass_check "the app was still running 3s after LaunchServices start"
      else
        fail_check "the app terminated shortly after being launched by LaunchServices"
      fi
      pkill -f "$(basename "$MAIN_EXECUTABLE")" >/dev/null 2>&1 || true
    else
      fail_check "LaunchServices never started the app"
      sed 's/^/      /' "$STAGE_DIR/open.log" >&2 || true
    fi
  else
    fail_check "open(1) refused to launch the extracted app"
    sed 's/^/      /' "$STAGE_DIR/open.log" >&2 || true
  fi

  # Only dynamic-loader / code-signature crashes matter here; the validator
  # terminates the app itself, and that termination is also written to
  # DiagnosticReports.
  CRASH_REPORTS="$(find "$HOME/Library/Logs/DiagnosticReports" -name "$(basename "$MAIN_EXECUTABLE")*.ips" -newermt '-3 minutes' 2>/dev/null || true)"
  LOADER_CRASHES=""
  while IFS= read -r report; do
    [ -n "$report" ] || continue
    if grep -qE 'Library not loaded|code signature|DYLD|different Team IDs' "$report" 2>/dev/null; then
      LOADER_CRASHES="$LOADER_CRASHES
$report"
    fi
  done <<REPORTS
$CRASH_REPORTS
REPORTS
  if [ -n "$(printf '%s' "$LOADER_CRASHES" | tr -d '[:space:]')" ]; then
    fail_check "the app crashed with a loader or code-signature failure:"
    printf '%s\n' "$LOADER_CRASHES" | sed 's/^/         /' >&2
  else
    pass_check "no loader or code-signature crash reports"
  fi
fi

########################################
rel_step "Validation summary"
if [ "$FAILURES" -eq 0 ]; then
  rel_ok "the release artifact passed every check"
  exit 0
fi
rel_err "$FAILURES check(s) failed - this artifact must not be published"
exit 1
