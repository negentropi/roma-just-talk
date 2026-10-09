#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
output="${1:-/tmp/rjt-cursor-avatar-proof}"
mkdir -p "$output"
swiftc "$root/VoiceInk/Transcription/Engine/CaptureReadiness.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarController.swift" "$root/tools/cursor-avatar/verify.swift" -o "$output/verify"
known_bad_attachment=4fe24ff70a04b132064c3142f00dea53eaf48bae
if ! git -C "$root" cat-file -e "$known_bad_attachment^{commit}" 2>/dev/null; then
    git -C "$root" fetch --no-tags --depth=1 origin "$known_bad_attachment"
fi
git -C "$root" show "$known_bad_attachment:VoiceInk/Views/Recorder/CursorAvatarView.swift" > "$output/old-view.swift"
git -C "$root" show "$known_bad_attachment:VoiceInk/Views/Recorder/CursorAvatarController.swift" > "$output/old-controller.swift"
swiftc "$root/VoiceInk/Transcription/Engine/CaptureReadiness.swift" "$output/old-view.swift" "$output/old-controller.swift" "$root/tools/cursor-avatar/verify.swift" -o "$output/old-verify"
if "$output/old-verify" > "$output/old-attachment.log" 2>&1; then
    echo "FAIL: detached avatar passed the attachment regression"
    exit 1
fi
if ! /usr/bin/grep -q 'character feet touch the pointer hotspot without a gap' "$output/old-attachment.log"; then
    echo "FAIL: baseline did not fail at the expected attachment boundary"
    cat "$output/old-attachment.log"
    exit 1
fi
"$output/verify"
swiftc "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$root/VoiceInk/Views/Onboarding/OnboardingAvatarView.swift" "$root/tools/cursor-avatar/render.swift" -o "$output/render"
if [[ -d "$root/VoiceInk/Assets.xcassets/CursorAvatar-cartoon-greeting.imageset" ]]; then
    "$output/render" "$root/VoiceInk/Assets.xcassets" "$output"
fi
known_bad=38ab4b39be05cce5cdd19e8595c44c41d252d7e2
if ! git -C "$root" cat-file -e "$known_bad^{commit}" 2>/dev/null; then
    git -C "$root" fetch --no-tags --depth=1 origin "$known_bad"
fi
bash "$root/tools/cursor-avatar/verify-streaming.sh" "$output/streaming" "$known_bad"
