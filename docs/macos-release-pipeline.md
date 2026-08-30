# macOS release pipeline

How `roma just talk.app` is built, signed, notarized, packaged, validated and
published — and why the previous process shipped an app that macOS 26 refused
to launch.

## The failure this pipeline fixes

Released builds crashed at launch with:

```
Library not loaded: @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
Reason: ... code signature ... not valid for use in process:
        mapping process and mapped file (non-platform) have different Team IDs
```

The framework was present, the bundle layout was correct, and
`@executable_path/../Frameworks` was on the runpath. The signature was the
problem:

1. Releases were produced by `make local CONFIGURATION=Release`, which builds
   with `CODE_SIGN_IDENTITY="-"`, `CODE_SIGNING_REQUIRED=NO` and an empty
   `DEVELOPMENT_TEAM` — an **ad-hoc** signature, so the app and every embedded
   framework report `TeamIdentifier=not set`.
2. The app target still sets `ENABLE_HARDENED_RUNTIME = YES`, and the hardened
   runtime turns on **Library Validation**, which only lets a process map code
   that shares its Team ID (or is an Apple platform binary).
3. An ad-hoc signature has no Team ID at all, so Library Validation can never
   be satisfied. `MediaRemoteAdapter.framework` — a SwiftPM *dynamic library*
   product, built from source and embedded with `CodeSignOnCopy` — is the first
   `@rpath` load, so it is the one named in the crash.
4. Nothing in the pipeline verified the packaged artifact: the ZIP was uploaded
   straight from the build directory, never expanded, never launched.

This is reproducible in three lines and is asserted by
`scripts/tests/release-pipeline.test.sh`: an ad-hoc signature plus
`--options runtime` fails to load its own embedded framework, while the same
bundle loads once it carries a real Team ID (Developer ID) or, for development
builds only, the `com.apple.security.cs.disable-library-validation`
entitlement.

## The fix

| Path | Signing | Hardened runtime | Library Validation |
| --- | --- | --- | --- |
| Public release | Developer ID Application, one Team ID for the app and every nested item | enabled | satisfied by the matching Team ID |
| Local / CI development build | ad-hoc | enabled by the project | exempted via `com.apple.security.cs.disable-library-validation` in `VoiceInk/VoiceInk.local.entitlements` |

Ad-hoc signing remains available, but only as an explicit development
fallback: `make release-dev`, `release-macos.sh --mode adhoc`, and `make local`.
The release workflow refuses to publish an artifact that is not Developer ID
signed and notarized.

## The flow

```
scripts/release/release-macos.sh
  ├─ make setup                       whisper.xcframework
  ├─ build-macos-app.sh               xcodebuild archive + exportArchive
  │                                   (method: developer-id, manual signing,
  │                                    ENABLE_HARDENED_RUNTIME=YES)
  ├─ sign-macos-app.sh                inside-out, never `codesign --deep`:
  │     1. every nested Mach-O image, deepest first
  │     2. every nested code bundle (frameworks, Sparkle's Updater.app and
  │        XPC services, plugins), deepest first, each keeping its own
  │        entitlements
  │     3. the .app last, after all nested code is embedded
  ├─ notarize-macos-app.sh            notarytool submit --wait, then
  │                                   stapler staple + stapler validate
  ├─ package-macos-app.sh             ditto ZIP (+ optional signed DMG)
  │                                   and SHA-256 checksums
  └─ validate-macos-artifact.sh       runs against the EXACT artifact
```

`--deep` is used only to *verify*, never to produce a signature: it cannot
apply per-bundle entitlements and mis-signs helper apps and XPC services.

## What validation checks

`scripts/release/validate-macos-artifact.sh` expands the ZIP (or mounts the
DMG) into a clean temporary directory and checks that copy — never the build
directory — because the original failure only appeared once macOS loaded a
downloaded, quarantined, translocated app.

* bundle identity and main executable; no `*.debug.dylib` / `__preview.dylib`
* no broken symlinks anywhere in the bundle
* `MediaRemoteAdapter.framework` and `Sparkle.framework` are embedded, with a
  valid `Versions/A/<name>`, `Versions/Current` and top-level symlinks
* `codesign --verify --deep --strict --verbose=4` on the .app
* `codesign -dv --verbose=4`: expected Team ID, Developer ID authority,
  hardened-runtime flag
* every nested Mach-O image and code bundle verifies **and shares the app's
  Team ID** — the exact condition that broke MediaRemoteAdapter
* `otool -l`: `LC_RPATH` contains `@executable_path/../Frameworks`
* `otool -L`: every `@rpath` dependency resolves inside the bundle
* `spctl --assess --type exec` and, for notarized builds, a stapled ticket
* launch: the extracted binary is executed, then the app is launched through
  LaunchServices with the quarantine attribute set so Gatekeeper and App
  Translocation apply; a loader or code-signature crash fails the release

## Commands

```bash
# What is configured on this machine / in CI
make release-credentials

# Full public release (fails without Developer ID + notarization credentials)
make release

# Same pipeline, ad-hoc, for development only — never publish the output
make release-dev

# Also produce and validate a DMG
make release RELEASE_ARGS=--dmg

# Re-validate an artifact you already have
make release-validate RELEASE_ARTIFACT=build/release/roma.just.talk.app.zip
scripts/release/validate-macos-artifact.sh \
  --artifact ~/Downloads/roma.just.talk.app.zip --expect-notarized

# Regression tests for the pipeline itself (no Xcode, no certificate, no network)
make release-test
```

Artifacts land in `build/release/`: `roma.just.talk.app.zip`, optionally
`roma.just.talk.dmg`, and `checksums.txt`.

## GitHub Actions

`.github/workflows/macos-release.yml` runs the same scripts. It fails — and
publishes nothing — when signing fails, nested framework signing fails,
notarization fails, validation fails, `MediaRemoteAdapter.framework` is
missing, the artifact is malformed, or the extracted app cannot be launched.

* `push` of a `v*` tag, or `workflow_dispatch` with `publish: true`, is a
  **production** release: credentials are required (`--require`), and the
  validated ZIP is uploaded to the release with `gh release upload`.
* `workflow_dispatch` without `publish` builds and validates without
  publishing. With `allow_unsigned_dev_build: true` it falls back to an ad-hoc
  build and clearly marks the artifact as unpublishable in the job summary.
* When credentials are missing, `check-signing-credentials.sh` prints exactly
  which variables are unset before the job fails.

`.github/workflows/voiceink-build.yml` (the development build) now also runs
the pipeline tests and validates its ZIP structurally with `--allow-adhoc`.

## Required GitHub secrets

Signing — all three required for a production release:

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | `base64 -i DeveloperID.p12` of the exported **Developer ID Application** certificate *and* its private key |
| `MACOS_CERTIFICATE_PASSWORD` | password used when exporting that `.p12` |
| `MACOS_TEAM_ID` | 10-character Apple Developer Team ID |

Notarization — provide **either** the API-key set (preferred) or the Apple ID
set:

| Secret | What it is |
| --- | --- |
| `AC_API_KEY_ID` | App Store Connect API key id |
| `AC_API_ISSUER_ID` | App Store Connect issuer id |
| `AC_API_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` |
| `AC_APPLE_ID` | Apple ID email (fallback) |
| `AC_APP_PASSWORD` | app-specific password for that Apple ID (fallback) |
| `AC_TEAM_ID` | Team ID for the Apple ID (fallback) |

Optional:

| Secret | What it is |
| --- | --- |
| `MACOS_SIGNING_IDENTITY` | exact identity name, e.g. `Developer ID Application: Example (TEAMID)`; resolved from the keychain when unset |
| `MACOS_KEYCHAIN_PASSWORD` | password for the temporary CI keychain; a random one is generated when unset |

Export the certificate once with:

```bash
security find-identity -v -p codesigning        # confirm the identity exists
# Keychain Access -> My Certificates -> right-click the Developer ID
# Application certificate -> Export -> .p12
base64 -i DeveloperID.p12 | pbcopy              # paste into the secret
```

Nothing else needs configuring; no certificate, password, Apple ID or key is
stored in the repository.

## Notes

* The production entitlements (`VoiceInk/VoiceInk.entitlements`) request
  iCloud, CloudKit, push and a keychain access group. Those capabilities need a
  **Developer ID** provisioning profile on the signing account; if the account
  does not have them, either enable them in the developer portal or point the
  release at a reduced entitlements file with
  `sign-macos-app.sh --entitlements <plist>`.
* `/usr/bin/xattr` is called by absolute path: a pip-installed `xattr` earlier
  in `PATH` does not support `-r` and silently breaks attribute stripping.
