#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
output="${1:-/tmp/rjt-streaming-readiness-proof}"
mkdir -p "$output"
swiftc "$root/VoiceInk/Transcription/Streaming/StreamingTranscriptionProvider.swift" "$root/VoiceInk/Transcription/Streaming/StreamingTranscriptionService.swift" "$root/VoiceInk/Transcription/Engine/TranscriptionSession.swift" "$root/tools/cursor-avatar/streaming-regression.swift" -o "$output/current" > "$output/current-build.log" 2>&1 || { cat "$output/current-build.log"; exit 1; }
"$output/current"
if [[ -n "${2:-}" ]]; then
    git -C "$root" show "$2:VoiceInk/Transcription/Streaming/StreamingTranscriptionService.swift" > "$output/known-bad-service.swift"
    swiftc "$root/VoiceInk/Transcription/Streaming/StreamingTranscriptionProvider.swift" "$output/known-bad-service.swift" "$root/VoiceInk/Transcription/Engine/TranscriptionSession.swift" "$root/tools/cursor-avatar/streaming-regression.swift" -o "$output/known-bad" > "$output/known-bad-build.log" 2>&1 || { cat "$output/known-bad-build.log"; exit 1; }
    if "$output/known-bad" > "$output/known-bad.log" 2>&1; then
        cat "$output/known-bad.log"
        exit 1
    fi
    cat "$output/known-bad.log"
fi
