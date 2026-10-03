# Unsigned production macOS archive

The production compile workflow retains the actual Release `.xcarchive` for a later Developer ID export.
It compiles the production entitlement and speech paths without `LOCAL_BUILD`.
It performs no certificate signing, notarization, launch qualification, or publication.
The archive is never a qualified distribution.

## Produce the archive

Push a unique disposable `ci/roma-production-compile-*` ref to run
`.github/workflows/macos-production-compile-check.yml`.
The `Compile Release without local behavior` job uses the hosted `macos-26` runner.
It requires Xcode 26.6 build 17F113, macOS SDK 26.5, and Apple Swift 6.3.3.
Whisper builds from `60c0be6ac8fa71b1a2ae2dd938a31a34a508e774`.

Package resolution uses the checked-in project `Package.resolved`.
Packaging compares its bytes with the Git blob at the expected source SHA and rejects tracked source mutations.
The current lock has 24 pins. Regenerate the count with this command.

```sh
python3 -c 'import json; print(len(json.load(open("VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"))["pins"]))'
```

The build uses Release, arm64, the macOS 14.2.1 floor, `VoiceInk/VoiceInk.entitlements`,
disabled signing, and disabled coverage instrumentation.
Existing deployment and instrumentation checks inspect the archived app before packaging.
The packaging command requires the source SHA and fresh output directory.

```sh
bash scripts/package-macos-production-archive.sh \
	--archive "$RUNNER_TEMP/roma.production.xcarchive" \
	--evidence-directory "$RUNNER_TEMP/roma-production-compile" \
	--whisper-source "$HOME/VoiceInk-Dependencies/whisper.cpp" \
	--expected-source-sha "$GITHUB_SHA" \
	--output-directory "$RUNNER_TEMP/roma-unsigned-production-archive"
```

## Consume the retained artifact

The successful packaging step uploads `roma.macos.unsigned-production-archive`.
It contains exactly these eleven regular files.

| File | Content |
| --- | --- |
| `roma.production.xcarchive.zip` | Original archive under the sole `roma.production.xcarchive` root |
| `source-sha.txt` | Full expected repository SHA |
| `xcode.txt` | Exact Xcode version and build |
| `swift.txt` | Actual compiler version output |
| `build-settings.json` | Actual VoiceInk Release settings |
| `app-info.plist` | Exact archived app plist bytes |
| `archive.log` | Original successful archive output |
| `BOUNDARY.txt` | Unsigned compilation qualification limit |
| `Package.resolved` | Exact source project lock bytes |
| `whisper-source-sha.txt` | Verified Whisper source SHA |
| `unsigned-app-files.sha256` | Shared bundle manifest with directories, files, modes, and symlinks |

The archive app is `Products/Applications/roma just talk.app`.
Packaging rejects unsafe paths, escaping symlinks, unsupported file types,
more than 30,000 archive entries, and more than 3 GiB of expanded archive content.
It extracts its ZIP into a disposable directory and compares the full archive inventory and shared app manifest.
The comparison preserves original content, file modes, directory modes, and symlink targets.
The output directory cannot already exist or overlap the inputs.

`roma.macos.production-compile-evidence` retains the original seven diagnostic receipts with `if: always()`.
The archive artifact is uploaded only after all producer checks succeed.
Consumers require the complete source workflow to finish successfully and bind the artifact to its live run, attempt, source SHA, and API digest.
The [macOS finalizer](macos-finalizer.md) owns that authenticated consumption and the credentialed export.
The [release qualification contract](macos-release-qualification.md) owns the remaining distribution requirements.

## Verify packaging

Run `bash scripts/tests/macos-production-archive.test.sh` on macOS.
Controlled receipts test rejection of local compilation, wrong source or toolchain,
changed locks, changed Whisper source, unsafe symlinks, and output reuse.
The accepted fixture builds a minimal native unsigned Mach-O and roundtrips its archive through the public script.
These checks prove packaging behavior only.
They do not prove the full RJT archive, production app behavior, export, notarization, or normal first Open.
