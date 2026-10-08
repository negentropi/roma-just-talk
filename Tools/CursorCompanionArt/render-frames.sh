#!/bin/bash
# usage: Tools/CursorCompanionArt/render-frames.sh <output-dir>
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mkdir -p "$1" && cd "$1" && pwd)"
build="$(mktemp -d)"
cp "$root/VoiceInkCore/Sources/VoiceInkCore/CursorCompanionPolicy.swift" "$build/"
for f in CursorCompanionArtwork CursorCompanionView; do
  sed '/^import VoiceInkCore/d' "$root/VoiceInk/Views/CursorCompanion/$f.swift" > "$build/$f.swift"
done
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -o "$build/preview" \
  "$build"/*.swift "$root/Tools/CursorCompanionArt/preview.swift"
"$build/preview" "$root/VoiceInk/Assets.xcassets" "$out"
ls "$out"
