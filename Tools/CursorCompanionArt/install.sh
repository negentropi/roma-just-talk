#!/bin/bash
# usage: Tools/CursorCompanionArt/install.sh <processed.png>...  (names like anime-perch.png)
set -euo pipefail
dest="$(cd "$(dirname "$0")/../.." && pwd)/VoiceInk/Assets.xcassets"
for f in "$@"; do
  n=companion-$(basename "$f" .png)
  mkdir -p "$dest/$n.imageset"
  cp "$f" "$dest/$n.imageset/$n.png"
  printf '{\n  "images" : [\n    {\n      "filename" : "%s",\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' "$n.png" > "$dest/$n.imageset/Contents.json"
done
