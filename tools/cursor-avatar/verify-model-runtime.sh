#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
model=${1:?tiny.en model path required}
framework=${2:?directory containing the bundled whisper.framework required}
headers=${3:?matching Whisper header and module map directory required}
output=${4:?output directory required}
mkdir -p "$output"
say -o "$output/speech.caf" --data-format=LEI16@16000 "This tiny avatar follows the cursor and stays with the text caret."
compile() {
    swiftc -I "$headers" -F "$framework" -framework whisper -Xlinker -rpath -Xlinker "$framework" \
        "$1" "$root/VoiceInk/Transcription/Whisper/VADModelManager.swift" \
        "$root/VoiceInk/Transcription/Engine/VoiceInkEngineError.swift" \
        "$root/tools/cursor-avatar/verify-model-runtime.swift" -o "$2"
}
# The baseline and candidate use the same framework, model, audio and no-Metal VM.
git -C "$root" show c1da4055:VoiceInk/Transcription/Whisper/LibWhisper.swift > "$output/old-lib-whisper.swift"
compile "$output/old-lib-whisper.swift" "$output/old-verify-model"
if "$output/old-verify-model" "$model" "$output/speech.caf" > "$output/old-model.log" 2>&1; then
    echo "FAIL: known-bad GPU model initialization passed without Metal"
    exit 1
fi
if ! /usr/bin/grep -q 'GGML_ASSERT(buffer) failed' "$output/old-model.log"; then
    echo "FAIL: baseline did not reproduce the observed Metal buffer assertion"
    cat "$output/old-model.log"
    exit 1
fi
compile "$root/VoiceInk/Transcription/Whisper/LibWhisper.swift" "$output/verify-model"
"$output/verify-model" "$model" "$output/speech.caf" > "$output/model.log" 2>&1
cat "$output/model.log"
