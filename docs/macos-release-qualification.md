# macOS release qualification input contract

`scripts/verify-macos-release-qualification.py` previews the evidence required before a macOS ZIP becomes public. The current verifier always returns `publicationEligible=false` and exits with status 1. Authenticated controller origin is not established. There is no signed positive fixture. The [draft-release consumer](macos-release-publication.md) invokes this verifier before any publication write and therefore rejects current evidence.

A completed source build and a successful per-app approval launch do not satisfy ordinary notarized first Open. The recorded `d504e90e` Sonoma app launches after explicit approval, but normal Open remains blocked by Gatekeeper. That artifact stays unqualified.

## Trusted policy

The publisher supplies the expected application SHA, reviewed qualification tooling SHA, and Developer ID team. The downloaded manifest cannot choose these values.

| Policy | Required value |
| --- | --- |
| Repository | `negentropi/roma-just-talk` |
| Source workflow | `.github/workflows/voiceink-build.yml` |
| Planned qualification workflow | `.github/workflows/qualify-macos-distribution.yml` |
| Application identifier | `com.negentropi.RomaJustTalk` |
| Direct ZIP payload | `roma just talk.app` |
| First Open contract | `notarized-first-open` |
| Sonoma row | `14.2.1`, build `23C71`, `arm64` |
| Tahoe row | `26.4.1`, build `25E253`, `arm64` |
| Stability | At least 60 seconds on the first process |

The qualification workflow is a required producer contract. It is not implemented by this verifier. An exact OS row remains required regardless of runner provider.

## CLI and output

The CLI accepts a JSON manifest and an evidence root. Python uses the standard library. Live mode also requires the existing `gh`, `jq`, and `scripts/macos-build-job.jq`.

```sh
python3 scripts/verify-macos-release-qualification.py manifest.json \
	--evidence-root "$EVIDENCE_ROOT" \
	--expected-source-sha "$EXPECTED_APP_SHA" \
	--expected-tooling-sha "$EXPECTED_TOOLING_SHA" \
	--developer-id-team "$EXPECTED_TEAM"
```

Live mode obtains run, attempt, job, and artifact metadata through authenticated `gh api` calls to GitHub. Failed API reads do not fall back to uploaded metadata. API calls have individual 10-second limits and a shared 30-second budget.

`--offline-preview` reads the referenced saved API JSON. It always adds `API_ORIGIN_UNVERIFIED`. Saved files provide diagnostic input, not authenticated origin.

The JSON result contains a preview and specific rejection records. Each rejection has `code`, `scope`, and `detail`. Input errors also produce JSON. Current output cannot authorize a release, even when the only remaining rejection is `CONTROLLER_ORIGIN_UNVERIFIED`.

## Manifest fields

`schemaVersion` is integer `1`. Evidence references are relative paths inside the evidence root. Absolute paths, traversal, and escaping symlinks are rejected. Text receipts have a 16 MiB limit.

Each origin record contains `runId`, `runAttempt`, `artifactId`, and `transportArchive`. Offline preview also requires `runMetadata`, `jobsMetadata`, and `artifactMetadata`. IDs are positive integers. `transportArchive` is the downloaded outer Actions ZIP.

| Record | Additional fields | Required API job and artifact |
| --- | --- | --- |
| `sourceBuild` | None | `Build release macOS app`; `roma.just.talk.app` |
| `qualification` | `toolingSha`, `jobId` | `Collect macOS qualification evidence`; `roma.macos.release-qualification` |
| `finalArchive` | `sourceSha`, `jobId`, `path`, `sha256`, `size` | `Finalize notarized macOS app`; `roma.macos.final-archive` |
| `rows` | Array of `name`, `jobId`, and `evidenceDirectory` | Exactly one job for each required OS |

The OS job names are `Qualify Sonoma 14.2.1 (23C71)` and `Qualify Tahoe 26.4.1 (25E253)`. `finalArchive.path` references the direct app ZIP. Its digest and size are separate from the outer Actions archive. The final archive and qualification share one exact producer run attempt.

Every required run must be completed and successful. The verifier rejects PR events, forks, unexpected workflows, mismatched heads, incomplete job lists, missing jobs, and duplicate job names. Source runner metadata passes the existing shared macOS build provider predicate. Each artifact must belong to the expected run and head, remain unexpired, and match the API digest and size. Artifact creation must fall inside the producing job's recorded attempt window.

The current source contract requires the named job to produce the source artifact directly. A reuse-only build must be followed back to its original completed producer before this contract supports it.

## Qualification archive binding

The qualification artifact contains `qualification-inputs.json` and the raw row files at their referenced paths. That JSON uses this projection of the manifest.

| Field | Recorded values |
| --- | --- |
| `sourceBuild` | `runId`, `runAttempt`, `artifactId`, and expected `sourceSha` |
| `qualification` | `runId`, `runAttempt`, and expected `toolingSha` |
| `finalArchive` | `artifactId`, `sourceSha`, `sha256`, and `size` |
| `developerIdTeam` | Expected team |
| `rows` | The array of `name`, `jobId`, and `evidenceDirectory` |

This projection excludes the qualification artifact's own ID. GitHub assigns that ID after upload. The producer records the final archive ID before collecting qualification evidence.

The verifier compares this projection with the requested inputs. It also hashes each consumed raw receipt and compares it with the same member in the API-bound qualification ZIP. A locally replaced file produces `RAW_RECEIPT_UNBOUND`. A changed source, final digest, row, or team produces `QUALIFICATION_INPUTS_UNBOUND`.

The qualification ZIP permits at most 20,000 entries and 512 MiB of uncompressed evidence. Duplicate paths, unsafe paths, encrypted entries, and symlinks are rejected. The direct app ZIP permits at most 20,000 entries and 2 GiB of uncompressed content. App symlinks must remain inside the app. The finalization transport must contain exactly one `roma.just.talk.app.zip` whose bytes match the direct ZIP.

## Existing raw row representation

Each `evidenceDirectory` contains the existing `macos-distribution-e2e` directory and `runtime-chain-verdict.txt`. The verifier reuses the collector's field names and full bundle manifest format.

| Evidence | Checked relation |
| --- | --- |
| `runner-identity.txt`, `gatekeeper-status.txt`, `sip-status.txt` | Exact OS, build, and architecture; enabled protections |
| `source-artifact.txt`, `browser-downloaded-artifact.txt` | Normal contract; exact finalizer artifact; browser download equals the direct final ZIP digest and size |
| `downloaded-archive-quarantine.txt`, `launch-verification/source-app-quarantine.txt` | Safari quarantine on ZIP and app |
| `reference-trust`, `extracted-trust-before`, `extracted-trust-after` | Expected team, identifier, Hardened Runtime, stapler success text, notarized assessment, and no policy override |
| Expected, extracted, source, and process `*-files.sha256` | Full manifests equal the manifest derived from the final ZIP |
| `launch-verification/launch-identity.txt`, `launched-pid.txt` | One first PID; final executable hash and bundle identifier |
| `distribution-launch-verdict.txt`, `appkit-running-application.txt` | First process finishes AppKit launch and remains stable for at least 60 seconds |
| Guest observation start, end, PID, crash, and log files | Bounded observation; one PID; no new crash or DYLD signature failure |
| Mapped code inventories and both `process-open-files` samples | Required bundled code and executable mapping |
| `runtime-chain-verdict.txt` | Same first PID, executable, and full bundle through the separate runtime smoke |

Trust text and verdict files remain command output. Their authenticated production and command exit status still require the reviewed producer and controller adapter. Hashes establish byte equality after origin is known. Hashes alone cannot authenticate a command or screenshot.

## Remaining producer and publication prerequisites

The consumer has no positive controller adapter. Marker files, uploaded `passed=true`, user-selected controller labels, and successful job status cannot replace one. An actual Cua Driver `browser_click` round trip exported action and before-and-after image files. Those exported images were black desktop pixels, while the separate browser snapshot showed the correct guest. A `captured` status did not establish valid GUI evidence.

A trusted runner must obtain valid automatic screenshots from the same exact browser transport and bind those daemon-generated files to the final digest, guest, actions, and job. The observed browser action export does not fill that capture gap.

The producer must also preserve fresh app-state checks, actual trust-command exit results, ordinary Archive Utility extraction, Finder first Open, and visible startup through that controller. Existing raw process proof continues alongside GUI proof. Build success or a rewritten evidence file cannot establish normal launch.

The draft-release consumer downloads the app asset by ID and rechecks the qualified ZIP digest before publication. The feed and final app asset consume the same verification result. `publish-update-feed.yml` now requires an explicit default-branch dispatch. It no longer runs after `release.published`. Manual administrator publication remains a separate bypass unless repository controls prevent it.

Signing credentials, Developer Program membership, the qualification producer, both exact normal notarized runtime rows, and the authenticated controller bridge remain prerequisites. The verifier makes those gaps visible without accepting current ad-hoc evidence as a signed positive.

## Verification

`scripts/tests/macos-release-qualification.test.py` invokes the public CLI. It rejects changed final bytes, replaced transport contents, incomplete builds, wrong identity, missing exact OS rows, duplicate jobs, wrong attempt artifacts, changed raw receipts, and marker-only controller assertions.

Sanitized source metadata comes from completed build `37140159415` at `d504e90e63035c4cb8e9597cbef9894253fdaf01`. The ad-hoc signature and failed first-process records remain rejection cases. The unsigned ZIP fixture tests byte containment only.

The optional `RJT_QUALIFICATION_RECORDED_EVIDENCE` path enables a check of the retained actual d504 Actions archive and inner ZIP. That test parses the real bundle and still requires public eligibility to remain false.
