#!/usr/bin/env bash
# Shared helpers for the macOS release pipeline.
#
# Sourced by every script in scripts/release. Written for bash 3.2 (the system
# bash on macOS runners), so no associative arrays and no `${arr[@]}` on a
# possibly-empty array without a guard.

RELEASE_APP_NAME="${RELEASE_APP_NAME:-roma just talk.app}"
RELEASE_BUNDLE_ID="${RELEASE_BUNDLE_ID:-com.negentropi.RomaJustTalk}"
RELEASE_ZIP_NAME="${RELEASE_ZIP_NAME:-roma.just.talk.app.zip}"
RELEASE_DMG_NAME="${RELEASE_DMG_NAME:-roma.just.talk.dmg}"
# Nested frameworks that must exist in every shipped build.
RELEASE_REQUIRED_FRAMEWORKS="${RELEASE_REQUIRED_FRAMEWORKS:-MediaRemoteAdapter.framework Sparkle.framework}"
RELEASE_EXPECTED_RPATH="${RELEASE_EXPECTED_RPATH:-@executable_path/../Frameworks}"

rel_step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
rel_info() { printf '    %s\n' "$*"; }
rel_ok()   { printf '    \033[32mok\033[0m   %s\n' "$*"; }
rel_warn() { printf '    \033[33mwarn\033[0m %s\n' "$*" >&2; }
rel_err()  { printf '    \033[31mFAIL\033[0m %s\n' "$*" >&2; }
rel_fail() { rel_err "$*"; exit 1; }

rel_require_macos() {
  [ "$(uname -s)" = "Darwin" ] || rel_fail "this script only runs on macOS"
}

rel_require_tool() {
  command -v "$1" >/dev/null 2>&1 || rel_fail "required tool not found: $1"
}

# True when the file is a Mach-O image (executable, dylib or bundle).
rel_is_macho() {
  [ -f "$1" ] || return 1
  [ -L "$1" ] && return 1
  case "$(file -b -- "$1" 2>/dev/null)" in
    *Mach-O*) return 0 ;;
    *) return 1 ;;
  esac
}

# Print paths deepest-first so nested code is always processed before its parent.
rel_sort_deepest_first() {
  awk -F/ '{ print NF "\t" $0 }' | sort -t"$(printf '\t')" -k1,1nr | cut -f2-
}

# All Mach-O files inside a bundle, deepest-first. Paths may contain spaces;
# they are newline separated (app bundles never contain newlines in names).
rel_nested_macho_files() {
  local root="$1"
  find "$root" -type f ! -type l -print 2>/dev/null | while IFS= read -r candidate; do
    if rel_is_macho "$candidate"; then printf '%s\n' "$candidate"; fi
  done | rel_sort_deepest_first
}

# All nested code bundles (frameworks, helper apps, XPC services, plugins),
# deepest-first. Versioned frameworks are reported as their Versions/<X>
# directory, which is what codesign expects on macOS.
rel_nested_code_bundles() {
  local root="$1"
  find "$root" -mindepth 1 \
    \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' -o -name '*.bundle' -o -name '*.plugin' \) \
    -type d -print 2>/dev/null | while IFS= read -r bundle; do
    case "$bundle" in
      *.framework)
        if [ -d "$bundle/Versions" ]; then
          find "$bundle/Versions" -mindepth 1 -maxdepth 1 -type d ! -type l -print
        else
          printf '%s\n' "$bundle"
        fi
        ;;
      *) printf '%s\n' "$bundle" ;;
    esac
  done | rel_sort_deepest_first
}

rel_main_executable() {
  local app="$1"
  local name
  name="$(plutil -extract CFBundleExecutable raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)"
  [ -n "$name" ] || rel_fail "cannot read CFBundleExecutable from $app"
  printf '%s\n' "$app/Contents/MacOS/$name"
}

# Team identifier of a signed path, or the empty string when unsigned/ad-hoc.
rel_team_id() {
  codesign -dv --verbose=4 "$1" 2>&1 \
    | awk -F'=' '/^TeamIdentifier=/ { print $2 }' \
    | sed 's/not set//' \
    | head -1
}

rel_signing_authority() {
  codesign -dv --verbose=4 "$1" 2>&1 \
    | awk -F'=' '/^Authority=/ { print $2; exit }'
}

rel_has_hardened_runtime() {
  codesign -dv --verbose=4 "$1" 2>&1 | grep -q 'flags=.*runtime'
}

# Resolve a Developer ID Application identity from the keychain.
# Honours MACOS_SIGNING_IDENTITY, then MACOS_TEAM_ID, then a unique match.
rel_resolve_developer_id_identity() {
  if [ -n "${MACOS_SIGNING_IDENTITY:-}" ]; then
    printf '%s\n' "$MACOS_SIGNING_IDENTITY"
    return 0
  fi
  local listing
  listing="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' || true)"
  [ -n "$listing" ] || return 1
  if [ -n "${MACOS_TEAM_ID:-}" ]; then
    listing="$(printf '%s\n' "$listing" | grep "($MACOS_TEAM_ID)" || true)"
    [ -n "$listing" ] || return 1
  fi
  printf '%s\n' "$listing" | head -1 | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-F]+[[:space:]]+"(.*)"$/\1/'
}

rel_team_id_from_identity() {
  printf '%s\n' "$1" | sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\))$/\1/p'
}

rel_mktemp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/roma-release.XXXXXXXX"
}
