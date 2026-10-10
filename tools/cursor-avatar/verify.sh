#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
output="${1:-/tmp/rjt-cursor-avatar-proof}"
mkdir -p "$output"
swiftc "$root/VoiceInk/Transcription/Engine/CaptureReadiness.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarController.swift" "$root/tools/cursor-avatar/verify.swift" -o "$output/verify"
# Normalize the internal feedback rename only; retain known-bad behavior.
known_bad_attachment=4fe24ff70a04b132064c3142f00dea53eaf48bae
if ! git -C "$root" cat-file -e "$known_bad_attachment^{commit}" 2>/dev/null; then
    git -C "$root" fetch --no-tags --depth=1 origin "$known_bad_attachment"
fi
git -C "$root" show "$known_bad_attachment:VoiceInk/Views/Recorder/CursorAvatarView.swift" | sed -e 's/\.hidden/\.idle/g' -e 's/case hidden,/case idle,/' > "$output/old-view.swift"
git -C "$root" show "$known_bad_attachment:VoiceInk/Views/Recorder/CursorAvatarController.swift" | sed -e 's/\.hidden/\.idle/g' -e 's/case hidden,/case idle,/' > "$output/old-controller.swift"
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
known_bad_timing=ea5ad76f181a959ade7ec37ee8f3fd7ff3909b03
if ! git -C "$root" cat-file -e "$known_bad_timing^{commit}" 2>/dev/null; then
    git -C "$root" fetch --no-tags --depth=1 origin "$known_bad_timing"
fi
git -C "$root" show "$known_bad_timing:VoiceInk/Views/Recorder/CursorAvatarController.swift" | sed 's/\.hidden/\.idle/g' > "$output/old-timing-controller.swift"
swiftc "$root/VoiceInk/Transcription/Engine/CaptureReadiness.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$output/old-timing-controller.swift" "$root/tools/cursor-avatar/verify.swift" -o "$output/old-verify-timing"
if "$output/old-verify-timing" > "$output/old-timing.log" 2>&1; then
    echo "FAIL: disappearing idle companion passed the persistent companion regression"
    exit 1
fi
if ! /usr/bin/grep -q 'new activation clears the warning while keeping the idle companion attached' "$output/old-timing.log"; then
    echo "FAIL: timing baseline did not fail at the idle visibility boundary"
    cat "$output/old-timing.log"
    exit 1
fi
swiftc "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarController.swift" "$root/tools/cursor-avatar/verify-caret.swift" -o "$output/verify-caret"
known_bad_caret=a1fc169df63e14fb8a4eabbf7b0b6ec42b8ad967
if ! git -C "$root" cat-file -e "$known_bad_caret^{commit}" 2>/dev/null; then
    git -C "$root" fetch --no-tags --depth=1 origin "$known_bad_caret"
fi
git -C "$root" show "$known_bad_caret:VoiceInk/Views/Recorder/CursorAvatarController.swift" | sed -e 's/\.hidden/\.idle/g' -e 's/case hidden,/case idle,/' > "$output/old-caret-controller.swift"
swiftc -D RAW_CARET_BASELINE "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$output/old-caret-controller.swift" "$root/tools/cursor-avatar/verify-caret.swift" -o "$output/old-verify-caret"
if "$output/old-verify-caret" > "$output/old-native-caret.log" 2>&1; then
    echo "FAIL: raw empty-range bounds passed the drawn-caret regression; environment does not reproduce the bug"
    exit 1
fi
if ! /usr/bin/grep -q 'native character feet must touch the drawn insertion caret' "$output/old-native-caret.log"; then
    echo "FAIL: baseline did not fail at the native drawn-caret boundary"
    cat "$output/old-native-caret.log"
    exit 1
fi
"$output/verify-caret"
known_bad_zero_caret=616b0ec4fcb69ba6e4fc28540e0ec2a519abc62b
if ! git -C "$root" cat-file -e "$known_bad_zero_caret^{commit}" 2>/dev/null; then
    git -C "$root" fetch --no-tags --depth=1 origin "$known_bad_zero_caret"
fi
git -C "$root" show "$known_bad_zero_caret:VoiceInk/Views/Recorder/CursorAvatarController.swift" > "$output/old-zero-caret-controller.swift"
swiftc -D ZERO_CARET_BASELINE "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$output/old-zero-caret-controller.swift" "$root/tools/cursor-avatar/verify-sonoma-caret.swift" -o "$output/old-verify-zero-caret"
if "$output/old-verify-zero-caret" > "$output/old-zero-caret.log" 2>&1; then
    echo "FAIL: zero-height TextEdit caret passed the drawn-caret regression"
    exit 1
fi
if ! /usr/bin/grep -q 'Sonoma zero-height caret must stay at the drawn insertion point' "$output/old-zero-caret.log"; then
    echo "FAIL: baseline did not fail at the zero-height caret boundary"
    cat "$output/old-zero-caret.log"
    exit 1
fi
swiftc "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$root/VoiceInk/Views/Recorder/CursorAvatarController.swift" "$root/tools/cursor-avatar/verify-sonoma-caret.swift" -o "$output/verify-zero-caret"
"$output/verify-zero-caret"
known_bad_character_bounds=a34ae42cd3671de28ec8e80ea0fea63ccaa9de6c
if ! git -C "$root" cat-file -e "$known_bad_character_bounds^{commit}" 2>/dev/null; then
    git -C "$root" fetch --no-tags --depth=1 origin "$known_bad_character_bounds"
fi
git -C "$root" show "$known_bad_character_bounds:VoiceInk/Views/Recorder/CursorAvatarController.swift" | sed -e 's/\.hidden/\.idle/g' -e 's/case hidden,/case idle,/' > "$output/old-character-controller.swift"
swiftc -D UNBOUNDED_CHARACTER_BASELINE "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$output/old-character-controller.swift" "$root/tools/cursor-avatar/verify-caret.swift" -o "$output/old-verify-character"
if "$output/old-verify-character" > "$output/old-character-bounds.log" 2>&1; then
    echo "FAIL: out-of-range character query passed the document-end regression"
    exit 1
fi
if ! /usr/bin/grep -q 'native character feet must touch the drawn insertion caret' "$output/old-character-bounds.log"; then
    echo "FAIL: character-range baseline did not fail at the caret boundary"
    cat "$output/old-character-bounds.log"
    exit 1
fi
swiftc "$root/VoiceInk/Views/Recorder/CursorAvatarView.swift" "$root/VoiceInk/Views/Onboarding/OnboardingAvatarView.swift" "$root/tools/cursor-avatar/render.swift" -o "$output/render"
if [[ -d "$root/VoiceInk/Assets.xcassets/CursorAvatar-cartoon-greeting.imageset" ]]; then
    "$output/render" "$root/VoiceInk/Assets.xcassets" "$output"
fi
known_bad=38ab4b39be05cce5cdd19e8595c44c41d252d7e2
if ! git -C "$root" cat-file -e "$known_bad^{commit}" 2>/dev/null; then
    git -C "$root" fetch --no-tags --depth=1 origin "$known_bad"
fi
bash "$root/tools/cursor-avatar/verify-streaming.sh" "$output/streaming" "$known_bad"
