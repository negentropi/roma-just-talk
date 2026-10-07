#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
output="${1:-/tmp/rjt-cursor-avatar-proof}"
mkdir -p "$output"
swiftc "$root/VoiceInk/Transcription/Engine/CaptureReadiness.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarController.swift" "$root/tools/cursor-avatar/verify.swift" -o "$output/verify"
"$output/verify"
swiftc "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$root/tools/cursor-avatar/render.swift" -o "$output/render"
if [[ -d "$root/VoiceInk/Assets.xcassets/CursorAvatar-cartoon-greeting.imageset" ]]; then
    "$output/render" "$root/VoiceInk/Assets.xcassets" "$output"
fi
