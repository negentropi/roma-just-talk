#!/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: $0 fresh-artifact-directory fresh-build-directory" >&2
  exit 2
fi
PROBE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$PROBE/../.." && pwd -P)
OUTPUT=$1
SCRATCH=$2
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
test -d "$DEVELOPER_DIR"
test "$(xcodebuild -version)" = $'Xcode 26.6\nBuild version 17F113'
test "$(xcrun --sdk macosx --show-sdk-version)" = "26.5"
xcrun swiftc --version | grep -Fq 'Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)'
test ! -e "$OUTPUT"
test ! -e "$SCRATCH"
mkdir -p "$OUTPUT/VoiceInkSwiftDataExactProbe.app/Contents/MacOS" "$OUTPUT/VoiceInkSwiftDataExactProbe.app/Contents/Frameworks" "$SCRATCH"
OUTPUT=$(cd "$OUTPUT" && pwd -P)
SCRATCH=$(cd "$SCRATCH" && pwd -P)
APP="$OUTPUT/VoiceInkSwiftDataExactProbe.app"
EXECUTABLE="$APP/Contents/MacOS/voiceink-swiftdata-probe"
APP_LOCK="$ROOT/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
python3 "$PROBE/verify-inputs.py" --models "$ROOT" "$PROBE" > "$OUTPUT/production-model-hashes.json"
cp "$APP_LOCK" "$OUTPUT/app-Package.resolved"
cp "$APP_LOCK" "$PROBE/Package.resolved"
{
  git -C "$ROOT" rev-parse HEAD
  xcodebuild -version
  xcrun swiftc --version
  xcrun --sdk macosx --show-sdk-version
  xcrun --sdk macosx --show-sdk-path
  sw_vers
  uname -m
  printf 'product_module=VoiceInk\nprobe_swift_language=5\nfloor=14.2.1\ncloudkit=none\ndistribution_qualification=false\n'
} > "$OUTPUT/build-identity.txt"
shasum -a 256 "$(xcrun --find swiftc)" "$(xcrun --find clang)" "$(xcrun --find ld)" \
  "$PROBE/Package.swift" "$PROBE/Sources/VoiceInk/Probe.swift" "$APP_LOCK" > "$OUTPUT/toolchain-and-input.sha256"
python3 - "$ROOT" "$OUTPUT/core-source-hashes.json" <<'PY'
import hashlib, json, pathlib, subprocess, sys
root, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
paths = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "VoiceInkCore", "VoiceInkNVIDIA"]).split(b"\0")
result = {path.decode(): hashlib.sha256((root / path.decode()).read_bytes()).hexdigest() for path in paths if path}
output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
PY
swift package --package-path "$PROBE" --scratch-path "$SCRATCH" resolve > "$OUTPUT/resolve.log" 2>&1
python3 "$PROBE/verify-inputs.py" --locks "$APP_LOCK" "$PROBE/Package.resolved" > "$OUTPUT/resolved-pins.json"
cp "$PROBE/Package.resolved" "$OUTPUT/probe-Package.resolved"
ARGS=(--package-path "$PROBE" --scratch-path "$SCRATCH" -c release --force-resolved-versions --triple arm64-apple-macosx14.2.1 -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
swift build "${ARGS[@]}" --product voiceink-swiftdata-probe > "$OUTPUT/build.log" 2>&1
python3 "$PROBE/verify-inputs.py" --locks "$APP_LOCK" "$PROBE/Package.resolved" > "$OUTPUT/resolved-pins-after-build.json"
python3 "$PROBE/verify-inputs.py" --models "$ROOT" "$PROBE" > "$OUTPUT/production-model-hashes-after-build.json"
cmp "$OUTPUT/production-model-hashes.json" "$OUTPUT/production-model-hashes-after-build.json"
BIN_PATH=$(swift build "${ARGS[@]}" --show-bin-path)
cp "$BIN_PATH/voiceink-swiftdata-probe" "$EXECUTABLE"
python3 - "$APP/Contents/Info.plist" <<'PY'
import pathlib, plistlib, sys
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps({
    "CFBundleName": "VoiceInkSwiftDataExactProbe", "CFBundleDisplayName": "RJT SwiftData diagnostic probe",
    "CFBundleIdentifier": "com.negentropi.RomaJustTalk.SwiftDataExactProbe",
    "CFBundleExecutable": "voiceink-swiftdata-probe", "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "LSMinimumSystemVersion": "14.2.1",
    "LSUIElement": True,
}))
PY
xcrun swift-stdlib-tool --copy --platform macosx \
  --scan-executable "$EXECUTABLE" \
  --destination "$APP/Contents/Frameworks" > "$OUTPUT/swift-stdlib-copy.log" 2>&1
for library in "$APP"/Contents/Frameworks/*.dylib; do
  [[ -f "$library" ]] || continue
  codesign --force --sign - --timestamp=none "$library"
done
codesign --force --sign - --timestamp=none "$APP"
otool -L "$EXECUTABLE" > "$OUTPUT/linked-libraries.txt"
otool -l "$EXECUTABLE" > "$OUTPUT/load-commands.txt"
codesign --verify --deep --strict "$APP" > "$OUTPUT/signature-verification.txt" 2>&1
codesign -dv --verbose=4 "$APP" > "$OUTPUT/signature-identity.txt" 2>&1
python3 - "$APP" "$OUTPUT/bundle-hashes.json" <<'PY'
import hashlib, json, pathlib, sys
root, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
output.write_text(json.dumps({str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
    for path in sorted(root.rglob("*")) if path.is_file()}, sort_keys=True, indent=2) + "\n")
PY
"$EXECUTABLE" --list-modes > "$OUTPUT/modes.json"
