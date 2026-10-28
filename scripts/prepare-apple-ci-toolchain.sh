#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != true || "$(uname -s)" != Darwin ]]; then
  echo "Run toolchain setup only on a disposable macOS Actions runner." >&2
  exit 2
fi
apple_ci_mode="${1:-build}"
case "$#:$apple_ci_mode" in
  0:build|1:--swift-only) ;;
  *) echo "Usage: $0 [--swift-only]" >&2; exit 2 ;;
esac
: "${GITHUB_ENV:?GitHub Actions environment file required}"

shopt -s nullglob
apple_ci_xcodes=(/Applications/Xcode_26*.app)
if (( ${#apple_ci_xcodes[@]} == 0 )); then
  echo "No installed Xcode 26 toolchain." >&2
  exit 1
fi
apple_ci_xcode="$(printf '%s\n' "${apple_ci_xcodes[@]}" | sort -V | tail -n 1)"
export DEVELOPER_DIR="$apple_ci_xcode/Contents/Developer"
sudo xcode-select -s "$DEVELOPER_DIR"
printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "$GITHUB_ENV"
xcodebuild -version
swift --version
sw_vers
uname -m

if [[ "$apple_ci_mode" == --swift-only ]]; then
  exit 0
fi
command -v cmake >/dev/null || brew install cmake
if ! xcrun metal --version >/dev/null 2>&1; then
  apple_ci_metal_log="${RUNNER_TEMP:?}/roma-metal-download.log"
  xcodebuild -downloadComponent MetalToolchain 2>&1 | tee "$apple_ci_metal_log"
  # Headless images can download the Metal asset without mounting it.
  if ! xcrun metal --version >/dev/null 2>&1; then
    apple_ci_metal_dmg="$(sed -n 's/^Downloaded asset to: //p' "$apple_ci_metal_log" | tail -n 1)"
    test -f "$apple_ci_metal_dmg"
    hdiutil attach -readonly -nobrowse "$apple_ci_metal_dmg"
  fi
fi
xcrun metal --version
