#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo/scripts/build-whisper-experiment.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/roma-whisper-contract.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

reject() {
  if "$@" > "$scratch/rejected.log" 2>&1; then
    echo "Expected rejection: $*" >&2
    exit 1
  fi
}

python3 - "$scratch" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
receipt = {"xcode": "Xcode 26.6\nBuild version 17F113", "sdkVersion": "26.5",
           "swift": "Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)",
           "clang": "Apple clang", "sdkPath": "/sdk", "developerDir": "/xcode",
           "cmake": "cmake version 4", "linker": "ld"}
(root / "toolchain.json").write_text(json.dumps(receipt))
for key, value in (("xcode", "Xcode 26.5\nBuild version wrong"), ("sdkVersion", "26.6"),
                   ("swift", "Apple Swift version 6.2"), ("clang", "")):
    changed = dict(receipt)
    changed[key] = value
    (root / f"bad-{key}.json").write_text(json.dumps(changed))
PY
verify_toolchain_receipt "$scratch/toolchain.json"
for key in xcode sdkVersion swift clang; do
  reject verify_toolchain_receipt "$scratch/bad-$key.json"
done

input_source="$scratch/input-source"
mkdir -p "$input_source/Tools/SwiftDataExactModelProbe"
git init --quiet "$input_source"
for lock in "$PROJECT_LOCK_PATH" VoiceInkCore/Package.resolved VoiceInkNVIDIA/Package.resolved; do
  mkdir -p "$input_source/$(dirname "$lock")"
  git -C "$repo" show "$APP_SOURCE_SHA:$lock" > "$input_source/$lock"
done
git -C "$repo" show "$APP_SOURCE_SHA:Tools/SwiftDataExactModelProbe/verify-inputs.py" \
  > "$input_source/Tools/SwiftDataExactModelProbe/verify-inputs.py"
git -C "$input_source" add "$PROJECT_LOCK_PATH" VoiceInkCore/Package.resolved VoiceInkNVIDIA/Package.resolved \
  Tools/SwiftDataExactModelProbe/verify-inputs.py
git -C "$input_source" -c user.name='Whisper experiment fixture' -c user.email='whisper-fixture@example.invalid' \
  -c commit.gpgsign=false commit --quiet -m 'test: committed input fixture'
input_sha="$(git -C "$input_source" rev-parse HEAD)"
verify_source_revision "$input_source" "$input_sha"
reject verify_source_revision "$input_source" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
seed_project_lock_union "$input_source" "$scratch/union.json" "$scratch/union-receipt.json"
python3 - "$scratch/union.json" "$scratch/union-receipt.json" <<'PYTHON'
import json, sys
union, receipt = [json.load(open(path)) for path in sys.argv[1:]]
assert len(union["pins"]) == receipt["unionPinCount"] == 41
atomics = next(pin for pin in union["pins"] if pin["identity"] == "swift-atomics")
assert atomics["state"] == {"revision": "b601256eab081c0f92f059e12818ac1d4f178ff7", "version": "1.3.0"}
assert len(receipt["conflicts"]) == 2 and len(receipt["inputs"]) == 3
PYTHON
printf '\n' >> "$input_source/$PROJECT_LOCK_PATH"
reject seed_project_lock_union "$input_source" "$scratch/rejected-union.json" "$scratch/rejected-union-receipt.json"
reject verify_source_revision "$input_source" "$input_sha"
git -C "$input_source" show "HEAD:$PROJECT_LOCK_PATH" > "$input_source/$PROJECT_LOCK_PATH"
printf 'untracked\n' > "$input_source/untracked.swift"
reject verify_source_revision "$input_source" "$input_sha"
mv "$input_source/untracked.swift" "$scratch/retained-input-untracked.swift"
verify_source_revision "$input_source" "$input_sha"
python3 - "$scratch" <<'PYTHON'
import copy, json, sys
from pathlib import Path
root = Path(sys.argv[1])
union = json.loads((root / "union.json").read_text())
normalized = copy.deepcopy(union)
normalized["version"] = 3
for pin in normalized["pins"]:
    pin["location"] = pin["location"].removesuffix(".git")
(root / "normalized-lock.json").write_text(json.dumps(normalized))
mutations = {}
value = copy.deepcopy(union); value["pins"].append(value["pins"][0]); mutations["duplicate"] = value
value = copy.deepcopy(union); value["pins"][0]["location"] = "https://example.invalid/wrong"; mutations["source"] = value
value = copy.deepcopy(union); value["pins"][0]["state"]["revision"] = "b" * 40; mutations["revision"] = value
value = copy.deepcopy(union); value["pins"].pop(); mutations["missing"] = value
value = copy.deepcopy(union); value["pins"][0]["location"] += "/"; mutations["source-spelling"] = value
for name, value in mutations.items():
    (root / f"bad-lock-{name}.json").write_text(json.dumps(value))
PYTHON
verify_project_lock "$input_source" "$scratch/union.json" "$scratch/normalized-lock.json" "$scratch/normalized-receipt.json"
for invalid in duplicate source revision missing source-spelling; do
  reject verify_project_lock "$input_source" "$scratch/union.json" "$scratch/bad-lock-$invalid.json" "$scratch/rejected-lock.json"
done
git -C "$repo" show "$APP_SOURCE_SHA:VoiceInk.xcodeproj/project.pbxproj" > "$scratch/project.pbxproj"
patch_whisper_reference "$scratch/project.pbxproj" "$scratch/static/whisper.xcframework"
reject patch_whisper_reference "$scratch/project.pbxproj" "$scratch/dynamic/whisper.xcframework"

checkout="$scratch/packages/checkouts/pkg"
mkdir -p "$checkout"
git init --quiet "$checkout"
printf 'original\n' > "$checkout/source.swift"
git -C "$checkout" add source.swift
git -C "$checkout" -c user.name='Whisper experiment fixture' -c user.email='whisper-fixture@example.invalid' \
  -c commit.gpgsign=false commit --quiet -m 'test: actual dependency checkout'
checkout_sha="$(git -C "$checkout" rev-parse HEAD)"
python3 - "$scratch" "$checkout_sha" <<'PYTHON'
import copy, json, sys
from pathlib import Path
root, revision = Path(sys.argv[1]), sys.argv[2]
pin = {"identity": "pkg", "kind": "remoteSourceControl", "location": "https://example.invalid/pkg.git",
       "state": {"revision": revision, "version": "1.0.0"}}
(root / "package-lock.json").write_text(json.dumps({"version": 2, "pins": [pin]}))
dependency = {"packageRef": {"identity": "pkg", "location": "https://example.invalid/pkg"}, "subpath": "pkg",
              "state": {"name": "sourceControlCheckout", "checkoutState": pin["state"]}}
(root / "packages/workspace-state.json").write_text(json.dumps({"object": {"dependencies": [dependency]}}))
for name in ("duplicate", "source", "revision"):
    changed = copy.deepcopy(dependency)
    if name == "source": changed["packageRef"]["location"] = "https://example.invalid/wrong"
    if name == "revision": changed["state"]["checkoutState"]["revision"] = "b" * 40
    dependencies = [changed, changed] if name == "duplicate" else [changed]
    (root / f"bad-workspace-{name}.json").write_text(json.dumps({"object": {"dependencies": dependencies}}))
PYTHON
verify_package_checkouts "$input_source" "$scratch/package-lock.json" "$scratch/packages" "$scratch/package-receipt.json"
cp "$scratch/packages/workspace-state.json" "$scratch/good-workspace.json"
for invalid in duplicate source revision; do
  cp "$scratch/bad-workspace-$invalid.json" "$scratch/packages/workspace-state.json"
  reject verify_package_checkouts "$input_source" "$scratch/package-lock.json" "$scratch/packages" "$scratch/rejected-package.json"
done
cp "$scratch/good-workspace.json" "$scratch/packages/workspace-state.json"
printf 'changed\n' > "$checkout/source.swift"
reject verify_package_checkouts "$input_source" "$scratch/package-lock.json" "$scratch/packages" "$scratch/rejected-package.json"
git -C "$checkout" show HEAD:source.swift > "$checkout/source.swift"
printf 'untracked\n' > "$checkout/untracked.swift"
reject verify_package_checkouts "$input_source" "$scratch/package-lock.json" "$scratch/packages" "$scratch/rejected-package.json"
mv "$checkout/untracked.swift" "$scratch/retained-checkout-untracked.swift"
verify_package_checkouts "$input_source" "$scratch/package-lock.json" "$scratch/packages" "$scratch/restored-package-receipt.json"
cmp "$scratch/package-receipt.json" "$scratch/restored-package-receipt.json"

write_variant_entitlements "$repo/VoiceInk/VoiceInk.local.entitlements" "$scratch/entitlements"
reject write_variant_entitlements "$scratch/entitlements/B.plist" "$scratch/bad-entitlements"

python3 - "$repo/.github/workflows/whisper-launch-experiment.yml" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
required = ("'ci/roma-whisper-experiment-*'", "workflow_dispatch:", "contents: read",
            "fetch-depth: 0", "persist-credentials: false", "name: roma.whisper-abc-experiment")
if any(value not in text for value in required):
    raise SystemExit("Workflow lacks diagnostic transport boundaries")
if "secrets." in text or "contents: write" in text or "name: roma.just.talk.app" in text:
    raise SystemExit("Diagnostic workflow exposes production authority")
PY

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'PASS toolchain, lock, reference, package and workflow boundaries; native signing requires macOS'
  exit 0
fi

mkdir -p "$scratch/unsigned/roma just talk.app/Contents/MacOS" "$scratch/unsigned/roma just talk.app/Contents/Frameworks"
python3 - "$scratch/unsigned/roma just talk.app/Contents/Info.plist" <<'PY'
import plistlib, sys
plistlib.dump({"CFBundleIdentifier": "com.negentropi.RomaJustTalk.WhisperExperimentFixture",
              "CFBundleExecutable": "roma just talk", "CFBundlePackageType": "APPL"}, open(sys.argv[1], "wb"))
PY
printf 'int main(void) { return 0; }\n' > "$scratch/main.c"
xcrun clang -arch arm64 "$scratch/main.c" -o "$scratch/unsigned/roma just talk.app/Contents/MacOS/roma just talk"
mkdir -p "$scratch/framework/whisper.framework/Versions/A/Resources" "$scratch/framework-output"
python3 - "$scratch/framework/whisper.framework/Versions/A/Resources/Info.plist" <<'PY'
import plistlib, sys
plistlib.dump({"CFBundleIdentifier": "org.ggml.whisper.fixture", "CFBundleExecutable": "whisper",
              "CFBundleName": "whisper", "CFBundlePackageType": "FMWK", "CFBundleVersion": "1"}, open(sys.argv[1], "wb"))
PY
ln -s A "$scratch/framework/whisper.framework/Versions/Current"
ln -s Versions/Current/whisper "$scratch/framework/whisper.framework/whisper"
ln -s Versions/Current/Resources "$scratch/framework/whisper.framework/Resources"
printf 'int whisper_fixture(void) { return 7; }\n' > "$scratch/whisper.c"
for arch in arm64 x86_64; do
  xcrun clang -arch "$arch" -mmacosx-version-min=13.3 -c "$scratch/whisper.c" -o "$scratch/$arch.o"
done
libtool -static -o "$scratch/combined.a" "$scratch/arm64.o" "$scratch/x86_64.o"
create_matched_whisper_frameworks "$scratch/matched" "$scratch/framework/whisper.framework" \
  "$scratch/combined.a" "$(xcrun --sdk macosx --show-sdk-path)" "$scratch/framework-output"
cmp "$scratch/combined.a" "$scratch/matched/static/whisper.framework/Versions/A/whisper"
otool -D "$scratch/matched/dynamic/whisper.framework/Versions/A/whisper" \
  | grep -Fxq '@rpath/whisper.framework/Versions/Current/whisper'
xcrun nm -arch arm64 -gU "$scratch/matched/dynamic/whisper.framework/Versions/A/whisper" | grep -Eq ' _whisper_fixture$'
reject create_matched_whisper_frameworks "$scratch/matched" "$scratch/framework/whisper.framework" \
  "$scratch/combined.a" "$(xcrun --sdk macosx --show-sdk-path)" "$scratch/framework-output"
for variant in A B; do
  ditto "$scratch/unsigned/roma just talk.app" "$scratch/$variant/roma just talk.app"
  sign_experiment_app "$scratch/$variant/roma just talk.app" "$scratch/entitlements/$variant.plist"
done
verify_static_pair "$scratch/A/roma just talk.app" "$scratch/B/roma just talk.app" "$scratch/pair" \
  "$repo/VoiceInk/VoiceInk.local.entitlements"
ditto "$scratch/unsigned/roma just talk.app" "$scratch/C/roma just talk.app"
printf 'extern int whisper_fixture(void); int main(void) { return whisper_fixture(); }\n' > "$scratch/dynamic-main.c"
xcrun clang -arch arm64 -mmacosx-version-min=13.3 "$scratch/dynamic-main.c" -F"$scratch/matched/dynamic" -framework whisper \
  -o "$scratch/C/roma just talk.app/Contents/MacOS/roma just talk"
ditto "$scratch/matched/dynamic/whisper.framework" "$scratch/C/roma just talk.app/Contents/Frameworks/whisper.framework"
sign_experiment_app "$scratch/C/roma just talk.app" "$scratch/entitlements/C.plist"
write_payload_manifest "$scratch/C/roma just talk.app" "$scratch/C-manifest.json"
verify_linkage_pair "$scratch/pair/A-manifest.json" "$scratch/C-manifest.json" "$scratch/linkage-pair.txt"
printf 'unrelated resource\n' > "$scratch/C/roma just talk.app/Contents/extra.txt"
write_payload_manifest "$scratch/C/roma just talk.app" "$scratch/C-unmatched-manifest.json"
reject verify_linkage_pair "$scratch/pair/A-manifest.json" "$scratch/C-unmatched-manifest.json" "$scratch/linkage-pair.txt"
printf 'unexpected payload\n' > "$scratch/B/roma just talk.app/Contents/extra.txt"
reject verify_static_pair "$scratch/A/roma just talk.app" "$scratch/B/roma just talk.app" "$scratch/mismatched-pair" \
  "$repo/VoiceInk/VoiceInk.local.entitlements"
ditto "$scratch/unsigned/roma just talk.app" "$scratch/wrong/roma just talk.app"
sign_experiment_app "$scratch/wrong/roma just talk.app" "$scratch/entitlements/A.plist"
reject verify_static_pair "$scratch/A/roma just talk.app" "$scratch/wrong/roma just talk.app" "$scratch/wrong-entitlements-pair" \
  "$repo/VoiceInk/VoiceInk.local.entitlements"
echo 'PASS experiment boundaries, common-archive static/dynamic packaging and actual fresh ad-hoc A/B signing; no app launch or transcription proof'
