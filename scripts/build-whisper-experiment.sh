#!/usr/bin/env bash
set -euo pipefail

# Dispatch requires an observed passing first Open of this candidate, before varying Whisper or Library Validation.
APP_SOURCE_SHA=d504e90e63035c4cb8e9597cbef9894253fdaf01
WHISPER_SOURCE_SHA=60c0be6ac8fa71b1a2ae2dd938a31a34a508e774
PROJECT_LOCK_PATH=VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
PINNED_DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer

fail() { echo "$*" >&2; return 1; }

verify_toolchain_receipt() {
  python3 - "$1" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
expected = {"xcode": "Xcode 26.6\nBuild version 17F113", "sdkVersion": "26.5"}
for key, value in expected.items():
    if r.get(key) != value:
        raise SystemExit(f"Unexpected {key}: {r.get(key)!r}")
if "Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)" not in r.get("swift", ""):
    raise SystemExit("Unexpected Swift compiler")
for key in ("sdkPath", "developerDir", "clang", "cmake", "linker"):
    if not isinstance(r.get(key), str) or not r[key].strip():
        raise SystemExit(f"Missing {key}")
PY
}

verify_source_revision() {
  local actual dirty
  actual="$(git -C "$1" rev-parse HEAD)" || return
  dirty="$(git -C "$1" status --porcelain --untracked-files=all)" || return
  [[ "$actual" == "$2" ]] || { fail 'App source revision mismatch'; return 1; }
  [[ -z "$dirty" ]] || { fail 'App source is not clean'; return 1; }
}

seed_project_lock_union() {
  python3 -B - "$1" "$2" "$3" <<'PYTHON'
import importlib.util, json, sys
from pathlib import Path
repo, destination, receipt = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("production_inputs", repo / "Tools/SwiftDataExactModelProbe/verify-inputs.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
receipt.write_text(json.dumps(helper.seed_union(repo, destination), indent=2, sort_keys=True) + "\n")
PYTHON
}

verify_project_lock() {
  python3 -B - "$1" "$2" "$3" "$4" <<'PYTHON'
import importlib.util, json, sys
from pathlib import Path
repo, expected, actual, receipt = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("production_inputs", repo / "Tools/SwiftDataExactModelProbe/verify-inputs.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
helper.verify_lock(expected, actual)
wanted, observed = helper.pins(expected), helper.pins(actual)
if wanted.keys() != observed.keys():
    raise SystemExit("Resolved package lock does not contain the exact 41-pin production union")
for identity, pin in observed.items():
    location = wanted[identity]["location"].removesuffix(".git")
    if pin["location"] not in (location, location + ".git"):
        raise SystemExit(f"Package source spelling changed beyond .git: {identity}")
canonical = {identity: {"kind": pin["kind"], "location": helper.canonical_location(pin["location"]), "state": pin["state"]}
             for identity, pin in observed.items()}
receipt.write_text(json.dumps({"rawSHA256": helper.sha(actual), "unionSHA256": helper.sha(expected),
    "canonicalPins": canonical}, indent=2, sort_keys=True) + "\n")
PYTHON
}

patch_whisper_reference() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys
project = Path(sys.argv[1])
replacement = sys.argv[2]
if any(c in replacement for c in ('"', '\\', '\n', '\r')):
    raise SystemExit("Unsupported framework path")
old = 'path = "$(HOME)/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework";'
text = project.read_text()
if text.count(old) != 1:
    raise SystemExit("Expected exactly one pinned Whisper reference")
project.write_text(text.replace(old, f'path = "{replacement}";'))
PY
}

write_variant_entitlements() {
  python3 - "$1" "$2" <<'PY'
import plistlib, sys
from pathlib import Path
base = plistlib.load(open(sys.argv[1], "rb"))
key = "com.apple.security.cs.disable-library-validation"
if base.get(key) is not True:
    raise SystemExit("Base entitlement must explicitly disable Library Validation")
out = Path(sys.argv[2])
out.mkdir()
for variant in ("A", "B", "C"):
    value = dict(base)
    if variant == "B":
        del value[key]
    (out / f"{variant}.plist").write_bytes(plistlib.dumps(value, sort_keys=True))
PY
}

verify_package_checkouts() {
  python3 -B - "$1" "$2" "$3" "$4" <<'PYTHON'
import importlib.util, json, sys
from pathlib import Path
repo, lock, packages, output = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("production_inputs", repo / "Tools/SwiftDataExactModelProbe/verify-inputs.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
expected = helper.pins(lock)
dependencies = json.loads((packages / "workspace-state.json").read_text())["object"]["dependencies"]
for dependency in dependencies:
    if dependency["state"]["name"] == "sourceControlCheckout":
        identity = dependency["packageRef"]["identity"]
        if identity not in expected:
            raise SystemExit(f"Unexpected source checkout: {identity}")
        location = expected[identity]["location"].removesuffix(".git")
        if dependency["packageRef"]["location"] not in (location, location + ".git"):
            raise SystemExit(f"Checkout source spelling changed beyond .git: {identity}")
output.write_text(json.dumps(helper.verify_checkouts(lock, packages), indent=2, sort_keys=True) + "\n")
PYTHON
}

write_payload_manifest() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import hashlib, json, os, stat, sys
root, output = Path(sys.argv[1]), Path(sys.argv[2])
rows = {}
for directory, dirs, files in os.walk(root, followlinks=False):
    for name in dirs + files:
        path = Path(directory) / name
        relative = str(path.relative_to(root))
        info = path.lstat()
        row = {"mode": stat.S_IMODE(info.st_mode)}
        if path.is_symlink():
            row.update(type="symlink", target=os.readlink(path))
        elif path.is_dir():
            row.update(type="directory")
        elif path.is_file():
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            row.update(type="file", sha256=digest.hexdigest())
        else:
            raise SystemExit(f"Unsupported payload entry: {relative}")
        rows[relative] = row
output.write_text(json.dumps(rows, indent=2, sort_keys=True) + "\n")
PY
}

verify_static_pair() {
  local first="$1" second="$2" output="$3" base_entitlements="$4"
  mkdir -p "$output"
  write_payload_manifest "$first" "$output/A-manifest.json" || return
  write_payload_manifest "$second" "$output/B-manifest.json" || return
  codesign -d --entitlements :- "$first" 2>/dev/null > "$output/A-entitlements.plist" || return
  codesign -d --entitlements :- "$second" 2>/dev/null > "$output/B-entitlements.plist" || return
  python3 - "$output" "$base_entitlements" <<'PY' || return
import json, plistlib, sys
from pathlib import Path
root = Path(sys.argv[1])
a, b = [json.loads((root / f"{v}-manifest.json").read_text()) for v in ("A", "B")]
expected = plistlib.load(open(sys.argv[2], "rb"))
if expected.get("com.apple.security.cs.disable-library-validation") is not True:
    raise SystemExit("Unexpected base entitlement")
for variant in ("A", "B"):
    wanted = dict(expected)
    if variant == "B":
        del wanted["com.apple.security.cs.disable-library-validation"]
    actual = plistlib.loads((root / f"{variant}-entitlements.plist").read_bytes())
    if actual != wanted:
        raise SystemExit(f"Incorrect {variant} entitlement dimension")
if a.keys() != b.keys():
    raise SystemExit("A/B payload paths differ")
main = "Contents/MacOS/roma just talk"
allowed = {main, "Contents/_CodeSignature/CodeResources"}
differences = sorted(k for k in a if a[k] != b[k])
if not differences or any(k not in allowed for k in differences):
    raise SystemExit(f"Unmatched A/B payload differences: {differences}")
(root / "signature-only-differences.json").write_text(json.dumps(differences) + "\n")
PY
  otool -s __TEXT __text "$first/Contents/MacOS/roma just talk" | sed '1d' > "$output/A-instructions.txt" || return
  otool -s __TEXT __text "$second/Contents/MacOS/roma just talk" | sed '1d' > "$output/B-instructions.txt" || return
  [[ -s "$output/A-instructions.txt" ]] || { fail 'Missing A instruction section'; return 1; }
  cmp "$output/A-instructions.txt" "$output/B-instructions.txt"
}

sign_experiment_app() {
  local app="$1" entitlements="$2"
  python3 - "$app" <<'PY' || return
from pathlib import Path
import subprocess, sys
app = Path(sys.argv[1])
frameworks = app / "Contents/Frameworks"
targets = []
if frameworks.exists():
    for path in frameworks.rglob("*"):
        if path.is_symlink():
            continue
        if path.is_file() and "Mach-O" in subprocess.check_output(["file", "-b", str(path)], text=True):
            targets.append(path)
        elif path.is_dir() and path.suffix in (".framework", ".app", ".xpc", ".bundle"):
            targets.append(path)
for target in sorted(set(targets), key=lambda p: (-len(p.parts), str(p))):
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(target)], check=True)
PY
  codesign --force --sign - --options runtime --timestamp=none --entitlements "$entitlements" "$app" || return
  codesign --verify --deep --strict "$app"
}

verify_linkage_pair() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
from pathlib import Path
a, c = [json.loads(Path(p).read_text()) for p in sys.argv[1:3]]
allowed = {"Contents/MacOS/roma just talk", "Contents/_CodeSignature/CodeResources"}
whisper = "Contents/Frameworks/whisper.framework"
for path in a.keys() | c.keys():
    if path in allowed or path == whisper or path.startswith(whisper + "/"):
        continue
    if a.get(path) != c.get(path):
        raise SystemExit(f"A/C changed unrelated payload: {path}")
if whisper not in c or any(p == whisper or p.startswith(whisper + "/") for p in a):
    raise SystemExit("Incorrect Whisper embedding dimension")
Path(sys.argv[3]).write_text("unrelated_payloads=identical\n")
PY
}

create_matched_whisper_frameworks() {
  local root="$1" framework="$2" archive="$3" sdk="$4" output="$5"
  [[ ! -e "$root/static/whisper.framework" && ! -e "$root/dynamic/whisper.framework" ]] \
    || { fail 'Refusing to reuse Whisper framework payloads'; return 1; }
  mkdir -p "$root/static" "$root/dynamic" || return
  ditto "$framework" "$root/static/whisper.framework" || return
  cp "$archive" "$root/static/whisper.framework/Versions/A/whisper" || return
  cmp "$archive" "$root/static/whisper.framework/Versions/A/whisper" || return
  ditto "$root/static/whisper.framework" "$root/dynamic/whisper.framework" || return
  xcrun --sdk macosx clang++ -dynamiclib -isysroot "$sdk" -arch arm64 -arch x86_64 \
    -mmacosx-version-min=13.3 -Wl,-force_load,"$archive" \
    -framework Foundation -framework Metal -framework Accelerate -framework CoreML \
    -install_name '@rpath/whisper.framework/Versions/Current/whisper' \
    -Wl,-map,"$output/whisper-dynamic-link.map" -o "$root/dynamic/whisper.framework/Versions/A/whisper" || return
  shasum -a 256 "$archive" > "$output/whisper-common-archive.sha256"
}

main() {
  [[ $# -eq 0 ]] || fail 'usage: scripts/build-whisper-experiment.sh'
  local repo root output source packages sdk union_lock
  repo="$(git rev-parse --show-toplevel)"
  root="$repo/.whisper-experiment"
  [[ ! -e "$root" ]] || fail "Refusing to reuse experiment state: $root"
  [[ -d "$PINNED_DEVELOPER_DIR" ]] || fail 'Pinned Xcode 26.6 is unavailable'
  export DEVELOPER_DIR="$PINNED_DEVELOPER_DIR"
  mkdir -p "$root/output"
  output="$root/output"
  experiment_output="$output"
  trap 'result=$?; printf "exit_code=%s\ndistribution_qualification=false\nruntime_proof=not-run\n" "$result" > "$experiment_output/build-status.txt"' EXIT
  exec > >(tee "$output/build.log") 2>&1
  python3 - "$output/toolchain.json" <<'PY'
import json, os, subprocess, sys
def read(command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()
receipt = {"developerDir": os.environ["DEVELOPER_DIR"], "xcode": read(["xcodebuild", "-version"]),
           "swift": read(["xcrun", "swift", "--version"]), "clang": read(["xcrun", "clang", "--version"]),
           "sdkVersion": read(["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
           "sdkPath": read(["xcrun", "--sdk", "macosx", "--show-sdk-path"]),
           "cmake": read(["cmake", "--version"]), "linker": read(["xcrun", "ld", "-version_details"])}
open(sys.argv[1], "w").write(json.dumps(receipt, indent=2) + "\n")
PY
  verify_toolchain_receipt "$output/toolchain.json"
  sdk="$(xcrun --sdk macosx --show-sdk-path)"
  source="$root/source"
  packages="$root/packages"
  git clone --shared --no-checkout "$repo" "$source"
  git -C "$source" checkout --detach "$APP_SOURCE_SHA"
  verify_source_revision "$source" "$APP_SOURCE_SHA"
  union_lock="$output/production-union-Package.resolved"
  seed_project_lock_union "$source" "$union_lock" "$output/production-lock-union.json"
  for lock in "$PROJECT_LOCK_PATH" VoiceInkCore/Package.resolved VoiceInkNVIDIA/Package.resolved; do
    mkdir -p "$output/input-locks/$(dirname "$lock")"
    git -C "$source" show "$APP_SOURCE_SHA:$lock" > "$output/input-locks/$lock"
  done
  {
    printf 'app_source_sha=%s\nwhisper_source_sha=%s\n' "$APP_SOURCE_SHA" "$WHISPER_SOURCE_SHA"
    printf 'transport_sha=%s\n' "$(git -C "$repo" rev-parse HEAD)"
    printf 'github_run_id=%s\nunion_lock_sha256=%s\n' "${GITHUB_RUN_ID:-local}" "$(shasum -a 256 "$union_lock" | awk '{print $1}')"
    printf 'app_architecture=arm64\napp_minimum_os=14.2.1\nwhisper_minimum_os=13.3\n'
    printf 'diagnostic_only=true\nhistorical_artifacts_modified=false\n'
    printf 'app_source_first_open=external_prerequisite_not_proved_by_this_build\n'
  } > "$output/inputs.txt"
  git clone --filter=blob:none --no-checkout https://github.com/ggml-org/whisper.cpp.git "$root/whisper"
  git -C "$root/whisper" checkout --detach "$WHISPER_SOURCE_SHA"
  [[ "$(git -C "$root/whisper" rev-parse HEAD)" == "$WHISPER_SOURCE_SHA" ]] || fail 'Whisper revision mismatch'
  [[ -z "$(git -C "$root/whisper" status --porcelain)" ]] || fail 'Whisper source is not clean'
  python3 - "$root/whisper/build-xcframework.sh" "$root/upstream-macos.sh" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = 'setup_framework_structure() {'
end = '# Create dynamic libraries from static libraries.'
if text.count(start) != 1 or text.count(end) != 1 or text.count('XCODE_VERSION=') != 1:
    raise SystemExit("Pinned upstream helper shape changed")
head = text[:text.index('XCODE_VERSION=')]
body = text[text.index(start):text.index(end)]
Path(sys.argv[2]).write_text(head + body)
PY
  (
    cd "$root/whisper"
    source "$root/upstream-macos.sh"
    cmake -B build-macos -G Xcode "${COMMON_CMAKE_ARGS[@]}" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 -DCMAKE_OSX_ARCHITECTURES='arm64;x86_64' \
      -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_C_FLAGS="$COMMON_C_FLAGS" \
      -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" -DWHISPER_COREML=ON -DWHISPER_COREML_ALLOW_FALLBACK=ON -S .
    cmake --build build-macos --config Release -- -quiet
    setup_framework_structure build-macos 13.3 macos
  )
  mkdir -p "$output/whisper-objects"
  local libraries=() name path
  for name in src/libwhisper src/libparakeet ggml/src/libggml ggml/src/libggml-base ggml/src/libggml-cpu \
    ggml/src/ggml-metal/libggml-metal ggml/src/ggml-blas/libggml-blas src/libwhisper.coreml; do
    path="$root/whisper/build-macos/${name%/*}/Release/${name##*/}.a"
    [[ -f "$path" ]] || fail "Missing common archive: $path"
    libraries+=("$path")
    shasum -a 256 "$path" >> "$output/whisper-component-hashes.txt"
    cp "$path" "$output/whisper-objects/${name##*/}.a"
  done
  libtool -static -o "$output/whisper-objects/combined.a" "${libraries[@]}"
  write_payload_manifest "$root/whisper/build-macos" "$output/whisper-build-manifest.json"
  cp "$root/whisper/build-macos/CMakeCache.txt" "$output/whisper-cmake-cache.txt"
  create_matched_whisper_frameworks "$root" "$root/whisper/build-macos/framework/whisper.framework" \
    "$output/whisper-objects/combined.a" "$sdk" "$output"
  local kind tree built
  for kind in static dynamic; do
    xcodebuild -create-xcframework -framework "$root/$kind/whisper.framework" -output "$root/$kind/whisper.xcframework"
    tree="$root/$kind/source"
    mkdir -p "$tree"
    git -C "$source" archive "$APP_SOURCE_SHA" | tar -x -C "$tree"
    cp "$union_lock" "$tree/$PROJECT_LOCK_PATH"
    verify_project_lock "$source" "$union_lock" "$tree/$PROJECT_LOCK_PATH" "$output/$kind-lock-seeded.json"
    patch_whisper_reference "$tree/VoiceInk.xcodeproj/project.pbxproj" "$root/$kind/whisper.xcframework"
    diff -u "$source/VoiceInk.xcodeproj/project.pbxproj" "$tree/VoiceInk.xcodeproj/project.pbxproj" \
      > "$output/$kind-project.diff" || [[ $? -eq 1 ]]
    if [[ "$kind" == static ]]; then
      xcodebuild -resolvePackageDependencies -project "$tree/VoiceInk.xcodeproj" -scheme VoiceInk \
        -clonedSourcePackagesDirPath "$packages" -onlyUsePackageVersionsFromResolvedFile
    fi
    verify_project_lock "$source" "$union_lock" "$tree/$PROJECT_LOCK_PATH" "$output/$kind-lock-before.json"
    verify_package_checkouts "$source" "$union_lock" "$packages" "$output/$kind-packages-before.json"
    verify_source_revision "$source" "$APP_SOURCE_SHA"
    xcodebuild -project "$tree/VoiceInk.xcodeproj" -scheme VoiceInk -configuration Release \
      -derivedDataPath "$root/$kind/DerivedData" -clonedSourcePackagesDirPath "$packages" \
      -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
      -xcconfig "$tree/LocalBuild.xcconfig" ENABLE_CODE_COVERAGE=NO CODE_SIGN_IDENTITY=- \
      CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= \
      CODE_SIGN_ENTITLEMENTS="$tree/VoiceInk/VoiceInk.local.entitlements" \
      SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' ARCHS=arm64 \
      MACOSX_DEPLOYMENT_TARGET=14.2.1 LD_GENERATE_MAP_FILE=YES build
    verify_project_lock "$source" "$union_lock" "$tree/$PROJECT_LOCK_PATH" "$output/$kind-lock-after.json"
    verify_package_checkouts "$source" "$union_lock" "$packages" "$output/$kind-packages-after.json"
    cmp "$output/$kind-packages-before.json" "$output/$kind-packages-after.json"
    verify_source_revision "$source" "$APP_SOURCE_SHA"
    built="$root/$kind/DerivedData/Build/Products/Release/roma just talk.app"
    [[ -d "$built" ]] || fail "Missing $kind app"
    ditto "$built" "$root/$kind/unsigned.app"
    write_payload_manifest "$root/$kind/unsigned.app" "$output/$kind-unsigned-manifest.json"
    python3 "$source/scripts/check-macos-deployment-target.py" "$root/$kind/unsigned.app"
  done
  write_variant_entitlements "$source/VoiceInk/VoiceInk.local.entitlements" "$output/entitlements"
  local variant app
  for variant in A B C; do
    mkdir "$output/$variant"
    app="$root/variants/$variant/roma just talk.app"
    ditto "$root/static/unsigned.app" "$app"
    if [[ "$variant" == C ]]; then
      cp "$root/dynamic/unsigned.app/Contents/MacOS/roma just talk" "$app/Contents/MacOS/roma just talk"
      ditto "$root/dynamic/whisper.framework" "$app/Contents/Frameworks/whisper.framework"
      otool -L "$app/Contents/MacOS/roma just talk" | grep -Fq '@rpath/whisper.framework/Versions/Current/whisper' \
        || fail 'C does not load the common-object dynamic Whisper framework'
    else
      bash "$source/scripts/verify-static-whisper-app.sh" "$app"
    fi
    sign_experiment_app "$app" "$output/entitlements/$variant.plist"
    codesign -d --verbose=4 "$app" > "$output/$variant/signature.txt" 2>&1
    grep -Fxq 'Signature=adhoc' "$output/$variant/signature.txt"
    grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' "$output/$variant/signature.txt"
    codesign -d --entitlements :- "$app" 2>/dev/null > "$output/$variant/signed-entitlements.plist"
    python3 - "$output/entitlements/$variant.plist" "$output/$variant/signed-entitlements.plist" <<'PY'
import plistlib, sys
if plistlib.load(open(sys.argv[1], "rb")) != plistlib.load(open(sys.argv[2], "rb")):
    raise SystemExit("Final signing changed experiment entitlements")
PY
    python3 "$source/scripts/check-macos-deployment-target.py" "$app"
    bash "$source/scripts/verify-macos-release-instrumentation.sh" "$app"
    write_payload_manifest "$app" "$output/$variant/full-manifest.json"
    otool -l "$app/Contents/MacOS/roma just talk" > "$output/$variant/main-load-commands.txt"
    otool -L "$app/Contents/MacOS/roma just talk" > "$output/$variant/main-dependencies.txt"
    xcrun dwarfdump --uuid "$app/Contents/MacOS/roma just talk" > "$output/$variant/main-uuid.txt"
    [[ "$(xcrun lipo -archs "$app/Contents/MacOS/roma just talk")" == arm64 ]] || fail "$variant is not arm64"
    otool -s __TEXT __text "$app/Contents/MacOS/roma just talk" | sed '1d' > "$output/$variant/main-instructions.txt"
  done
  verify_static_pair "$root/variants/A/roma just talk.app" "$root/variants/B/roma just talk.app" \
    "$output/static-pair" "$source/VoiceInk/VoiceInk.local.entitlements"
  verify_linkage_pair "$output/A/full-manifest.json" "$output/C/full-manifest.json" "$output/linkage-pair.txt"
  for variant in A B C; do
    ditto -c -k --keepParent "$root/variants/$variant/roma just talk.app" "$output/$variant/roma.whisper-experiment.$variant.zip"
    shasum -a 256 "$output/$variant/roma.whisper-experiment.$variant.zip" >> "$output/archive-hashes.txt"
    stat -f '%z %N' "$output/$variant/roma.whisper-experiment.$variant.zip" >> "$output/archive-sizes.txt"
  done
  git -C "$root/whisper" diff --exit-code
  echo 'Diagnostic builds complete. Both exact-OS launch and Whisper transcription rows remain untested.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
