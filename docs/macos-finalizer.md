# macOS finalizer draft

The finalizer exports one authenticated unsigned production archive with an existing Developer ID identity/profile, notarizes it, staples the ticket, runs the existing four-command trust gate, then packages the final bytes. It never publishes and always reports `publicationEligible=false`. Both exact OS normal first-Open qualification rows remain required.

## Caller usage

Run only from the reviewed qualification producer's `Finalize notarized macOS app` job. Configure an existing installed provisioning profile, available private-key-backed Developer ID identity, and existing notary keychain profile beforehand. The script creates no certificate, account, profile, or keychain credential and enables no automatic provisioning updates.

```sh
bash scripts/finalize-notarized-macos-app.sh \
  --source-run-id "$SOURCE_RUN_ID" --source-run-attempt "$SOURCE_RUN_ATTEMPT" \
  --source-artifact-id "$SOURCE_ARTIFACT_ID" \
  --expected-source-sha "$APPLICATION_SHA" --expected-tooling-sha "$REVIEWED_TOOLING_SHA" \
  --developer-id-team "$DEVELOPER_ID_TEAM" --signing-identity-sha1 "$CERTIFICATE_SHA1" \
  --provisioning-profile "$INSTALLED_UUID_PROFILE" \
  --notary-keychain-profile "$EXISTING_NOTARY_PROFILE_NAME" \
  --output-dir "$NEW_OUTPUT_DIRECTORY"
```

The reviewed producer supplies expected policy independently of downloaded evidence. Certificate SHA-1 is an exact identity selector, not an artifact digest. The final app digest is SHA-256. Use a new output directory for each run. Failures retain local command evidence and a blocked result. Existing outputs are never replaced.

## Grounded build boundary

`.github/workflows/voiceink-build.yml` runs `make local CONFIGURATION=Release`. That path compiles `LOCAL_BUILD` behavior and local entitlements. Re-signing its ZIP cannot restore the compiled production CloudKit/keychain paths. The current qualification consumer still expects that workflow's source artifact; integration must change the source contract coherently before this finalizer can satisfy it.

The separate `.github/workflows/macos-production-compile-check.yml` archives Release without `LOCAL_BUILD` using Xcode 26.6 build 17F113, arm64, the 14.2.1 floor, and `VoiceInk/VoiceInk.entitlements`. Whisper is built at `60c0be6ac8fa71b1a2ae2dd938a31a34a508e774`. Package resolution remains owned by that source workflow and its reviewed repository pins. This script does not rebuild or resolve dependencies.

At initial grounding that workflow uploaded only `roma.macos.production-compile-evidence`, not its unsigned archive. The parallel packaging unit adds `roma.macos.unsigned-production-archive`, produced directly inside the completed successful `Compile Release without local behavior` job. The finalizer requires exactly these eleven top-level files.

- `roma.production.xcarchive.zip`, containing the original `roma.production.xcarchive` with its expected app under `Products/Applications`.
- Actual `build-settings.json` from the matching archive invocation's settings.
- `source-sha.txt` with the application SHA.
- `xcode.txt` with the exact reviewed Xcode version/build.
- `swift.txt`, `archive.log`, and `BOUNDARY.txt` retaining actual compiler/build output and the unsigned qualification boundary.
- `app-info.plist`, matching the archived app's actual plist.
- `Package.resolved`, byte-equal to the package lock at the authenticated application SHA. No assumed pin count.
- `whisper-source-sha.txt`, recording the observed fixed Whisper revision.
- `unsigned-app-files.sha256`, matching the shared complete app manifest, including modes and symlinks.

Do not synthesize these receipts from desired settings. The source packaging producer owns exact SDK 26.5, Swift 6.3.3, and actual compiler-receipt equality checks; the finalizer retains those authenticated receipts and independently checks Xcode and production settings. The source workflow must verify its actual build settings, dependencies, whole-run completion, and artifact contents. Merely republishing an older archive in another job is unsupported. The reviewed source SHA and workflow establish that producer's behavior; copied uploaded flags cannot establish compilation independently.

## Authentication and export

The script reads current producer and source run/attempt/job metadata through live `gh api`. It rejects forks, PR runs, unexpected workflow/head, incomplete source runs, duplicate/truncated jobs, wrong attempt, unsupported source provider, expired/wrong artifacts, and API digest/size mismatch. There is no offline manifest or caller-provided API JSON mode. It also compares its local finalizer and used gates with GitHub source at the expected reviewed tooling SHA. The actual producer must use a trusted `gh`, macOS toolchain, environment, and checkout. A local caller who can replace binaries or every API response is outside that trust boundary.

Production entitlements contain restricted CloudKit, APS, and keychain capabilities. [Apple's provisioning guidance](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) explains that restricted claims need profile authorization. The draft uses the existing profile and Xcode Developer ID export to perform nested signing and capability expansion. It verifies the expected team, explicit app ID, profile validity, and certificate selector. The App ID prefix comes from the profile; it need not be invented from the team ID.

The fixed export options use `developer-id`, manual signing, the explicit certificate/profile, and the production CloudKit environment. The expanded production entitlement contract includes production APS and CloudKit values and app/team identifiers. The exported claims must exactly match this contract and their restricted values must be permitted by the selected profile. Library Validation stays enabled. Unexpected Xcode-generated entitlements fail for review; there is no local-entitlement or ad-hoc fallback.

[Apple's supported distribution path](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) is archive then `xcodebuild -exportArchive`. Whether this particular unsigned archive exports with the verified profile is unproved. Some archive or capability configurations may require a fresh credentialed archive. A rejected export remains blocked with its actual output. Do not patch missing capabilities into an ad-hoc/local app or silently switch compilation paths. If export requires a fresh archive, return to the reviewed source producer and preserve exact source/dependency/settings provenance.

## Byte and trust checks

The script checks app identity, release instrumentation, nested arm64 availability, main arm64-only architecture, and each Mach-O's deployment floor. Xcode owns inside-out nested signing; the script verifies each actual nested code object with the expected Developer ID team and validates the app deeply through the existing trust gate.

Source/export comparison happens only on disposable copies. `codesign --remove-signature` normalizes Mach-O signature changes on those comparison copies, then file bytes, modes, and symlinks must match, excluding signature resources, the newly embedded profile, and the app's stapled ticket at `Contents/CodeResources`. The comparison repeats after stapling. Original source and exported apps are not normalized or re-signed by this check. This strict normalization contract still needs a real unsigned-to-signed export experiment; a legitimate mismatch stays visible for redesign. It is not yet proof that every valid Xcode export will pass.

The notary submission ZIP is distinct from the final distributable ZIP. Actual `notarytool submit --wait` must exit zero and return `Accepted`. The retained notary log must match the submission ID and submitted ZIP SHA-256. The script staples the app and runs `verify-macos-notarized-app.sh`, retaining actual ordered argv, exit status, UTC times, timeout state, stdout, and stderr for codesign verify/display, stapler validate, and spctl assess. Normal notarized assessment must have no override. [Apple documents the submit/wait/staple sequence](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Only after stapling and trust checks does the script freeze the full bundle inventory and create `roma.just.talk.app.zip`. It validates the ZIP contents, re-extracts with metadata-preserving `ditto`, compares bytes, file/directory modes, and symlinks with the verified app, then repeats the actual four-command trust gate on the extracted app. Mutation during packaging or loss of the ticket fails. `finalization-result.json` contains the source producer, current qualification job/run/attempt, team, notary submission, and final direct ZIP SHA-256/size.

The future qualification workflow uploads only that direct ZIP as `roma.macos.final-archive` from the named finalizer job. GitHub assigns its artifact ID afterward. The workflow records that API ID, outer archive digest, and direct ZIP digest/size before issuing row challenges. Finalization receipts remain private by default; they may contain account/profile metadata and notary details. No password, private key, credential import/export, or broad environment dump is part of the interface.

## Verification and remaining prerequisites

```sh
bash scripts/tests/macos-finalizer.test.sh
RJT_FINALIZER_RECORDED_SOURCE_ARCHIVE="$RETAINED_UNQUALIFIED_ARCHIVE" \
  bash scripts/tests/macos-finalizer.test.sh
```

Controlled subprocess tests exercise the actual public script, API/byte binding, corrupt or unsupported compressed transport, missing identity, wrong team, local compile/entitlement rejection, source/export mutation, rejected export/notary/stapler, policy override, and mutation during packaging. A controlled accepted path exercises receipts and final ZIP roundtrip only. It establishes no certificate, membership, signed positive, Apple notarization, or normal launch. The optional retained-artifact test requires actual current unsigned/ad-hoc evidence bytes to fail before identity access.

Actual Developer Program membership, matching available private-key-backed Developer ID identity, authorized installed profile, working notary profile, full production archive artifact, exact source contract integration, and two signed normal-Open rows remain unverified prerequisites. No credentials were inspected or signing/notary commands performed to prepare this draft.
