#!/usr/bin/env bash
set -euo pipefail

APP_SOURCE_SHA=d504e90e63035c4cb8e9597cbef9894253fdaf01
WHISPER_SOURCE_SHA=60c0be6ac8fa71b1a2ae2dd938a31a34a508e774
PROJECT_LOCK_PATH=VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
PINNED_DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer

patch_dynamic_project() {
  python3 - "$1" "$2" <<'PY'
import json, subprocess, sys
from pathlib import Path
project, framework = Path(sys.argv[1]), sys.argv[2]
if any(c in framework for c in ('"', '\\', '\n', '\r')):
    raise SystemExit("Unsupported framework path")
def parsed(text):
    return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", "--", "-"], input=text.encode()))
text = project.read_text()
before = parsed(text)
reference = 'E1A0BD052EB1E7B800266859'
phase = 'E1A8C8CD2E1257B7003E58EC'
embed = 'D10000012FA0000000000001'
if embed in before['objects']:
    raise SystemExit("Dynamic Whisper embed entry already exists")
replacements = {
    'path = "$(HOME)/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework";': f'path = "{framework}";',
    '/* End PBXBuildFile section */': '\t\t' + embed + ' /* whisper.xcframework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = ' + reference + ' /* whisper.xcframework */; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };\n/* End PBXBuildFile section */',
    '\t\t\t\tE1D7EF9A2E35E19B00640029 /* MediaRemoteAdapter in Embed Frameworks */,': '\t\t\t\tE1D7EF9A2E35E19B00640029 /* MediaRemoteAdapter in Embed Frameworks */,\n\t\t\t\t' + embed + ' /* whisper.xcframework in Embed Frameworks */,',
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f"Pinned project shape changed: {old}")
    text = text.replace(old, new)
after = parsed(text)
expected = json.loads(json.dumps(before))
expected['objects'][reference]['path'] = framework
expected['objects'][phase]['files'].append(embed)
expected['objects'][embed] = {'isa': 'PBXBuildFile', 'fileRef': reference,
    'settings': {'ATTRIBUTES': ['CodeSignOnCopy', 'RemoveHeadersOnCopy']}}
if after != expected:
    raise SystemExit("Project patch changed unrelated settings")
project.write_text(text)
PY
}

verify_packages() {
  python3 -B - "$1" "$2" "$3" "$4" <<'PY'
import importlib.util, json, sys
from pathlib import Path
source, union, packages, output = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('inputs', source / 'Tools/SwiftDataExactModelProbe/verify-inputs.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
actual = source / 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
wanted, observed = helper.pins(union), helper.pins(actual)
helper.verify_lock(union, actual)
if len(wanted) != 41 or wanted.keys() != observed.keys():
    raise SystemExit("Resolved graph is not the full 41-pin union")
for identity, pin in observed.items():
    location = wanted[identity]['location'].removesuffix('.git')
    if pin['location'] not in (location, location + '.git'):
        raise SystemExit(f"Unexpected source spelling: {identity}")
dependencies = json.loads((packages / 'workspace-state.json').read_text())['object']['dependencies']
for dependency in dependencies:
    if dependency['state']['name'] == 'sourceControlCheckout':
        identity = dependency['packageRef']['identity']
        if identity not in wanted:
            raise SystemExit(f"Unexpected package: {identity}")
        location = wanted[identity]['location'].removesuffix('.git')
        if dependency['packageRef']['location'] not in (location, location + '.git'):
            raise SystemExit(f"Unexpected checkout source spelling: {identity}")
output.write_text(json.dumps({'unionSHA256': helper.sha(union),
    'checkouts': helper.verify_checkouts(union, packages)}, indent=2, sort_keys=True) + '\n')
PY
}

record_framework() {
  local framework="$1" output="$2" binary="$1/Versions/A/whisper"
  mkdir -p "$output"
  shasum -a 256 "$binary" > "$output/binary.sha256"
  xcrun dwarfdump --uuid "$binary" > "$output/uuid.txt"
  otool -l "$binary" > "$output/load-commands.txt"
  otool -L "$binary" > "$output/dependencies.txt"
  otool -arch arm64 -s __TEXT __text "$binary" | sed '1d' | shasum -a 256 > "$output/arm64-instructions.sha256"
  codesign -d --verbose=4 "$framework" > "$output/signature.txt" 2>&1 || true
  write_macos_bundle_manifest "$framework" "$output/full-manifest.txt"
}

main() {
  [[ $# -eq 0 || ( $# -eq 1 && "$1" == --preflight ) ]] \
    || { echo 'usage: scripts/build-whisper-upstream-dynamic-experiment.sh [--preflight]' >&2; return 2; }
  local repo root output source packages union framework app main_binary
  repo="$(git rev-parse --show-toplevel)"
  root="$repo/.whisper-upstream-dynamic"
  [[ ! -e "$root" ]] || { echo "Refusing to reuse diagnostic state: $root" >&2; return 1; }
  [[ -d "$PINNED_DEVELOPER_DIR" ]] || { echo 'Pinned Xcode 26.6 is unavailable' >&2; return 1; }
  export DEVELOPER_DIR="$PINNED_DEVELOPER_DIR"
  mkdir -p "$root/output/D"
  output="$root/output"
  diagnostic_output="$output"
  trap 'result=$?; printf "exit_code=%s\ndistribution_qualification=false\nruntime_proof=not-run\n" "$result" > "$diagnostic_output/build-status.txt"' EXIT
  exec > >(tee "$output/build.log") 2>&1
  source "$repo/scripts/macos-bundle-manifest.sh"
  python3 - "$output/toolchain.json" <<'PY'
import json, os, subprocess, sys
def read(command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()
receipt = {'developerDir': os.environ['DEVELOPER_DIR'], 'xcode': read(['xcodebuild', '-version']),
    'swift': read(['xcrun', 'swift', '--version']), 'clang': read(['xcrun', 'clang', '--version']),
    'sdkVersion': read(['xcrun', '--sdk', 'macosx', '--show-sdk-version']),
    'cmake': read(['cmake', '--version']), 'linker': read(['xcrun', 'ld', '-version_details']),
    'availableSDKs': read(['xcodebuild', '-showsdks']), 'requiredSDKs': {}}
for sdk in ('macosx', 'iphoneos', 'iphonesimulator', 'xros', 'xrsimulator', 'appletvos', 'appletvsimulator'):
    receipt['requiredSDKs'][sdk] = {'path': read(['xcrun', '--sdk', sdk, '--show-sdk-path']),
        'version': read(['xcrun', '--sdk', sdk, '--show-sdk-version'])}
open(sys.argv[1], 'w').write(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
if receipt['xcode'] != 'Xcode 26.6\nBuild version 17F113' or receipt['sdkVersion'] != '26.5':
    raise SystemExit('Unexpected Xcode or macOS SDK')
if 'Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)' not in receipt['swift']:
    raise SystemExit('Unexpected Swift compiler')
PY
  source="$root/source"
  packages="$root/packages"
  union="$output/production-union-Package.resolved"
  git clone --shared --no-checkout "$repo" "$source"
  git -C "$source" checkout --detach "$APP_SOURCE_SHA"
  [[ "$(git -C "$source" rev-parse HEAD)" == "$APP_SOURCE_SHA" && -z "$(git -C "$source" status --porcelain)" ]]
  python3 -B "$source/Tools/SwiftDataExactModelProbe/verify-inputs.py" --union "$source" "$union" \
    > "$output/production-lock-union.json"
  for lock in "$PROJECT_LOCK_PATH" VoiceInkCore/Package.resolved VoiceInkNVIDIA/Package.resolved; do
    mkdir -p "$output/input-locks/$(dirname "$lock")"
    cp "$source/$lock" "$output/input-locks/$lock"
  done
  {
    printf 'variant=D\napp_source_sha=%s\nwhisper_source_sha=%s\n' "$APP_SOURCE_SHA" "$WHISPER_SOURCE_SHA"
    printf 'transport_sha=%s\ngithub_run_id=%s\n' "$(git -C "$repo" rev-parse HEAD)" "${GITHUB_RUN_ID:-local}"
    printf 'upstream_mode=BUILD_STATIC_XCFRAMEWORK=OFF\nupstream_targets=all-supported\n'
    printf 'embedding=Xcode-CodeSignOnCopy\napp_architecture=arm64\napp_minimum_os=14.2.1\n'
    printf 'diagnostic_only=true\ndistribution_qualification=false\nruntime_proof=not-run\n'
  } > "$output/inputs.txt"
  [[ $# -eq 0 ]] || { echo 'PASS pinned toolchain, required SDKs and app input union; no build executed'; return 0; }
  git clone --filter=blob:none --no-checkout https://github.com/ggml-org/whisper.cpp.git "$root/whisper"
  git -C "$root/whisper" checkout --detach "$WHISPER_SOURCE_SHA"
  [[ "$(git -C "$root/whisper" rev-parse HEAD)" == "$WHISPER_SOURCE_SHA" ]]
  git -C "$root/whisper" status --porcelain > "$output/whisper-source-before.txt"
  [[ ! -s "$output/whisper-source-before.txt" ]]
  git -C "$root/whisper" rev-parse HEAD > "$output/whisper-source-sha.txt"
  shasum -a 256 "$root/whisper/build-xcframework.sh" > "$output/upstream-script-before.sha256"
  cp "$root/whisper/build-xcframework.sh" "$output/upstream-build-xcframework.sh"
  (cd "$root/whisper" && BUILD_STATIC_XCFRAMEWORK=OFF ./build-xcframework.sh)
  shasum -a 256 "$root/whisper/build-xcframework.sh" > "$output/upstream-script-after.sha256"
  cmp "$output/upstream-script-before.sha256" "$output/upstream-script-after.sha256"
  git -C "$root/whisper" diff --exit-code > "$output/whisper-source-after.diff"
  cp "$root/whisper/build-macos/CMakeCache.txt" "$output/whisper-cmake-cache.txt"
  local library
  for library in src/libwhisper src/libparakeet ggml/src/libggml ggml/src/libggml-base ggml/src/libggml-cpu \
    ggml/src/ggml-metal/libggml-metal ggml/src/ggml-blas/libggml-blas src/libwhisper.coreml; do
    shasum -a 256 "$root/whisper/build-macos/${library%/*}/Release/${library##*/}.a" \
      >> "$output/whisper-component-hashes.txt"
  done
  framework="$root/whisper/build-apple/whisper.xcframework"
  cp "$framework/Info.plist" "$output/whisper-xcframework-info.plist"
  record_framework "$framework/macos-arm64_x86_64/whisper.framework" "$output/whisper-before-embedding"
  cp "$union" "$source/$PROJECT_LOCK_PATH"
  patch_dynamic_project "$source/VoiceInk.xcodeproj/project.pbxproj" "$framework"
  git -C "$source" diff -- VoiceInk.xcodeproj/project.pbxproj > "$output/dynamic-project.diff"
  shasum -a 256 "$source/VoiceInk.xcodeproj/project.pbxproj" > "$output/dynamic-project-before.sha256"
  xcodebuild -resolvePackageDependencies -project "$source/VoiceInk.xcodeproj" -scheme VoiceInk \
    -clonedSourcePackagesDirPath "$packages" -onlyUsePackageVersionsFromResolvedFile
  verify_packages "$source" "$union" "$packages" "$output/packages-before.json"
  local build_args=(-project "$source/VoiceInk.xcodeproj" -scheme VoiceInk -configuration Release \
    -derivedDataPath "$root/DerivedData" -clonedSourcePackagesDirPath "$packages" \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
    -xcconfig "$source/LocalBuild.xcconfig" ENABLE_CODE_COVERAGE=NO CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS="$source/VoiceInk/VoiceInk.local.entitlements" \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    MACOSX_DEPLOYMENT_TARGET=14.2.1 LD_GENERATE_MAP_FILE=YES)
  xcodebuild "${build_args[@]}" -showBuildSettings -json > "$output/build-settings.json"
  python3 - "$output/build-settings.json" "$source" <<'PY'
import json, sys
rows = [r for r in json.load(open(sys.argv[1])) if r.get('target') == 'VoiceInk']
assert len(rows) == 1
s = rows[0]['buildSettings']
assert s['CONFIGURATION'] == 'Release' and s['ARCHS'] == 'arm64'
assert s['MACOSX_DEPLOYMENT_TARGET'] == '14.2.1'
assert s['PRODUCT_BUNDLE_IDENTIFIER'] == 'com.negentropi.RomaJustTalk'
assert s['CODE_SIGNING_ALLOWED'] == 'YES' and s['CODE_SIGN_IDENTITY'] == '-'
assert s['ENABLE_HARDENED_RUNTIME'] == 'YES'
assert s['CODE_SIGN_ENTITLEMENTS'] == sys.argv[2] + '/VoiceInk/VoiceInk.local.entitlements'
assert {'LOCAL_BUILD', 'ENABLE_NATIVE_SPEECH_ANALYZER'} <= set(s['SWIFT_ACTIVE_COMPILATION_CONDITIONS'].split())
PY
  xcodebuild "${build_args[@]}" build
  shasum -a 256 "$source/VoiceInk.xcodeproj/project.pbxproj" > "$output/dynamic-project-after.sha256"
  cmp "$output/dynamic-project-before.sha256" "$output/dynamic-project-after.sha256"
  verify_packages "$source" "$union" "$packages" "$output/packages-after.json"
  cmp "$output/packages-before.json" "$output/packages-after.json"
  git -C "$source" diff --name-only > "$output/app-source-changed-paths.txt"
  python3 - "$output/app-source-changed-paths.txt" <<'PY'
from pathlib import Path
import sys
assert set(Path(sys.argv[1]).read_text().splitlines()) == {
    'VoiceInk.xcodeproj/project.pbxproj', 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'}
PY
  app="$root/DerivedData/Build/Products/Release/roma just talk.app"
  main_binary="$app/Contents/MacOS/roma just talk"
  [[ "$(xcrun lipo -archs "$main_binary")" == arm64 ]]
  otool -L "$main_binary" > "$output/D/main-dependencies.txt"
  grep -Fq '@rpath/whisper.framework/Versions/Current/whisper' "$output/D/main-dependencies.txt"
  otool -l "$main_binary" > "$output/D/main-load-commands.txt"
  xcrun dwarfdump --uuid "$main_binary" > "$output/D/main-uuid.txt"
  codesign -d --verbose=4 "$app" > "$output/D/signature.txt" 2>&1
  codesign -d --entitlements :- "$app" 2>/dev/null > "$output/D/signed-entitlements.plist"
  python3 - "$source/VoiceInk/VoiceInk.local.entitlements" "$output/D/signed-entitlements.plist" <<'PY'
import plistlib, sys
expected, actual = [plistlib.load(open(p, 'rb')) for p in sys.argv[1:]]
assert actual['com.apple.security.cs.disable-library-validation'] is True
assert all(actual.get(key) == value for key, value in expected.items())
assert set(actual) - set(expected) <= {'com.apple.security.get-task-allow'}
assert isinstance(actual.get('com.apple.security.get-task-allow', False), bool)
PY
  bash "$source/scripts/verify-adhoc-library-validation.sh" "$app"
  bash "$source/scripts/verify-macos-release-instrumentation.sh" "$app"
  python3 "$source/scripts/check-macos-deployment-target.py" "$app"
  record_framework "$app/Contents/Frameworks/whisper.framework" "$output/whisper-after-embedding"
  cmp "$output/whisper-before-embedding/arm64-instructions.sha256" "$output/whisper-after-embedding/arm64-instructions.sha256"
  write_macos_bundle_manifest "$app" "$output/D/full-manifest.txt"
  ditto -c -k --keepParent "$app" "$output/D/roma.whisper-upstream.dynamic.D.zip"
  shasum -a 256 "$output/D/roma.whisper-upstream.dynamic.D.zip" > "$output/D/archive.sha256"
  stat -f '%z' "$output/D/roma.whisper-upstream.dynamic.D.zip" > "$output/D/archive-size.txt"
  ditto -x -k "$output/D/roma.whisper-upstream.dynamic.D.zip" "$root/zip-roundtrip"
  write_macos_bundle_manifest "$root/zip-roundtrip/roma just talk.app" "$output/D/zip-roundtrip-manifest.txt"
  cmp "$output/D/full-manifest.txt" "$output/D/zip-roundtrip-manifest.txt"
  echo 'Diagnostic D packaged. Exact-OS first Open and Tiny English persistence remain untested.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
