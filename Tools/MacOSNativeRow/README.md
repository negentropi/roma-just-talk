# Native macOS row admission

This module admits immutable native evidence into the macOS release qualifier. It does not build, notarize, launch, collect, or publish an application. No production row producer or qualifier integration is implemented here. The existing unconditional publication denial remains unchanged.

`AuthenticatedNativeRow` means the supplied payload matches the externally pinned artifact bytes, signed inventory, original native calls, and first-process chronology. It does not mean the application is qualified. Trust-command semantics, OS protection state, actual browser download identity, responsive production UI, and completed transcription semantics remain required qualification checks.

## Files and ownership

| File | Responsibility |
| --- | --- |
| `protocol.py` | Canonical JSON, duplicate-key rejection, immutable bounded ZIP snapshot, detached OpenSSH signature, original native call and image reconstruction |
| `schema.py` | External expected context and the required production member set |
| `rowreader.py` | Diagnostic origin replay, strict unopened request, signed production envelope, observer chronology, first-process continuity, restricted byte reader |
| `tests/test_rowreader.py` | Controlled negative inputs and retained real diagnostic replay |

The protocol promotes the reviewed primitives from `Tools/NativeChallengeProbe` at diagnostic tooling SHA `2dee65174cfeb6ad27c43a7a41fab4d9c63a7d43`. It does not copy its broker, CLI, workflow, history exporter, or guest capture command. The old diagnostic protocol and this production admission contract use separate namespaces and return types.

## Caller API

```python
from Tools.MacOSNativeRow.rowreader import authenticate_native_row

row = authenticate_native_row(
    payload_artifact_bytes,
    challenge_artifact_bytes,
    expected=api_bound_expected_row,
    policy=reviewed_broker_policy,
)
raw_signature_output = row.bytes("macos-distribution-e2e/reference-trust/signature.txt")
runner_identity = row.text("macos-distribution-e2e/runner-identity.txt")
first_process = row.first_process
```

The caller constructs `ExpectedRow` and `BrokerPolicy` from independently authenticated context. Neither comes from the payload. Before calling, the aggregate consumer must verify:

- Successful expected workflow run and named row job, exact repository, tooling/source SHA, run ID, attempt, job ID, and API start/completion window.
- Payload and challenge artifact IDs, exact API digest, and exact transport byte size.
- Finalizer provenance, final inner ZIP bytes, artifact identity, executable/manifest hashes, Developer ID team, and bundle identifier.
- Exact guest OS/build/architecture and boot identity for the requested row.
- Reviewed policy bytes and their digest, exporter/collector code digests, fixed guest transport identity and argv, original native call code profiles, target browser, trusted key, identity, and namespace.

These data classes are context carriers, not API clients or validators of GitHub authorization. Constructing a return data class directly is not evidence admission. Consume rows only through `authenticate_native_row` and retain aggregate qualification ownership in the caller.

`row.bytes` and `row.text` accept only members reconstructed into the verified signed inventory. They return immutable byte snapshots. Signature, inventory, parsing, and later receipt consumption all use those same bytes; no authenticated path is reopened. The inventory and detached signature are exposed by the inventory digest rather than as arbitrary raw evidence paths.

`authenticate_diagnostic_origin` accepts externally bound diagnostic job/artifact metadata plus exact reviewed policy bytes. It returns `DiagnosticOrigin`, which has no first process or publication eligibility. It cannot become `AuthenticatedNativeRow`.

## Production wire contract

All JSON objects below reject unexpected fields. JSON duplicate keys and nonfinite numbers are rejected. The envelope must be canonical UTF-8 JSON with sorted keys, compact separators, and a final newline. SHA-256 and sizes always refer to exact raw bytes, including newlines.

The `challenge.json` object has exactly:

```text
schemaVersion, contract, context, nonce, titlePrefix,
createdAtMs, expiresAtMs, policySha256, exporterSha256, collectorSha256
```

`schemaVersion` is integer `1`; `contract` is `notarized-first-open`. `context` exactly equals the caller's expected job, row, guest identity, and final archive identity. A lowercase 32-hex nonce binds every observation. The title prefix is `Roma-first-open-<nonce> `. No PID, approved process, pass flag, or publication field is permitted. Setup finishes before this request; its collection interval is at most 15 minutes. Offline verification after expiry is allowed when the original work and signature finished inside that original interval and API job window.

`broker-origin.json` has exactly:

```text
schemaVersion, contract, brokerIdentity, namespace, context,
challengeArtifactId, requestSha256, policySha256, exporterSha256, collectorSha256,
collectionStartedAtMs, collectionEndedAtMs, signedAtMs, calls, files
```

The detached signature uses the externally trusted identity/key and namespace `roma-native-first-open@roma-just-talk`. `files` is a sorted exact inventory of `{path, sha256, size}`. It includes every required row receipt and each reconstructed original call/image. Only the inventory and its detached signature sit outside that inventory. Missing, duplicate, extra, escaped, linked, or encrypted members are rejected.

`calls` is reconstructed from the original completed `cua_repl.js` entries. Each entry must match the externally pinned exact code, nonce-bearing title, browser URL/backend/ID, timestamps, turn/item identity, and original image bytes. Phases are `download`, `extract`, `finder-open`, `ui-before`, `ui-action`, `ui-after`, and `smoke`, in that order. A reviewed `normal-open-dialog` phase may occur immediately after `finder-open`. Images must decode with the declared format and be nonblack; that alone does not establish responsive UI. The future exporter must also reject unprofiled guest actions throughout collection rather than merely selecting matching entries.

`broker-execution.json` has exactly:

```text
schemaVersion, transportIdentity, collectorSha256, argv, startedAtMs,
completedAtMs, exitStatus, timedOut, stdoutSha256, stderrSha256
```

It binds the reviewed transport and fixed collector invocation to zero actual exit status, no timeout, bounded collection time, and preserved `collector.stdout`/`collector.stderr`. This receipt must originate from broker-owned subprocess execution. A shared guest file or supplied success label cannot establish that origin. The transport and execution producer remain unimplemented.

The required trust files include the existing four-command receipt JSON and exact raw stdout/stderr/text files for reference, before, and after checks. Their admission authenticates bytes and command collector provenance. The existing trust verifier must still check exact argv, exit status, app/team/bundle binding, output digests, and actual command windows. This module does not duplicate those semantics.

## Observer and runtime continuity

`observer/clock.json` contains integer version `1`, the nonce, and exactly two roundtrip samples. A sample has `controllerBeforeMs`, `controllerAfterMs`, `guestUtcMs`, and `guestMonotonicMs`. Each roundtrip is at most two seconds. The before/after offset intervals must intersect, and monotonic elapsed time must fit the controller interval. Samples surround readiness and the final observation, and sit inside actual collector execution. These are proposed collector receipts, not evidence that a production collector already emits them.

`observer/readiness.json` contains integer version `1`, nonce/boot identity, `scanCompletedGuestMs`, `acknowledgedControllerMs`, `initialScanExitStatus`, `initialPids`, `logStartedGuestMs`, and `crashBaselineGuestMs`. The actual scan exits zero and finds no process. Log and crash baselines precede that scan; broker acknowledgement follows it and precedes Finder Open.

`observer/process-events.json` contains integer version `1`, nonce/boot identity, and ordered `events`. Each event has exactly `pid`, `startTimeMs`, `observedGuestMs`, `observedMonotonicMs`, `state`, `executableSha256`, and `manifestSha256`. The first process must start after normal Open, match the externally expected executable/bundle, and keep the same PID/start identity. An earlier suspended first process is retained; a later survivor cannot replace it. At least 60 seconds of monotonic observation and a healthy final state are required. The producer must continuously retain failures and all correlated processes; a selected pair of healthy samples is insufficient producer behavior.

`manual-whisper-smoke/result.json` binds pre/post process identities to that observer-derived first process. Raw before/after SQLite query stdout must show a new row ID. This is a continuity check, not completed speech proof. The next producer/semantic unit must bind actual read-only query commands, pinned audio/model hashes, expected Tiny English transcript, completion state, and before/after runtime to the same first PID. The existing separate-relaunch helper cannot supply this contract by changing a path or label.

## Bounds and failure behavior

The default compressed transport cap is 12 MiB, with at most 20,000 ZIP entries, 512 MiB total expanded bytes, 16 MiB per member, and 64 MiPixels per decoded image. A complete real production row has not been measured. The caller must choose a reviewed measured transport cap; overflow rejects without dropping required raw evidence. Payload bytes are held as an immutable in-memory snapshot; signature verification uses bounded temporary files and a ten-second `ssh-keygen` timeout.

`Rejected` is the expected invalid-evidence exception. Missing Pillow or `ssh-keygen` is an environment prerequisite failure, not a qualified row. The module performs no credential access, VM control, browser action, API request, or publication write.

## Verification

Use the repository's Python with Pillow and OpenSSH signing support:

```sh
python3 -B Tools/MacOSNativeRow/tests/test_rowreader.py
RJT_NATIVE_ROW_REPLAY_ROOT=/absolute/path/to/cases/live-37158262982 \
  python3 -B Tools/MacOSNativeRow/tests/test_rowreader.py
```

Without the retained live case, its single replay test is skipped and no real-origin positive is claimed. With it, the tests authenticate the original signed diagnostic payload from run `37158262982`, job `111306109060`, against the retained API artifact digest/size and reviewed policy. The exact same payload must fail production unopened-request admission. The diagnostic positive has no eligibility field.

Negative cases use disposable explicitly test-only keys and synthetic call shapes. Their trust files deliberately contain invalid placeholder receipts. They establish rejection behavior, not a qualified positive. The suite covers requested/preexisting/replaced PID, relaunch, old transcript, failed/replaced collector, late signature, wrong context/key/namespace, clock mismatch, malformed original-call metadata, duplicate identity, image substitution/black image, missing/extra raw receipt, immutable API bytes, and unsafe ZIP/JSON inputs.

A real full positive still requires both protected exact OS guests to download and normally open the same final Developer ID ZIP, actual broker-owned trust/runtime commands, first-PID stability, responsive production UI, a new completed same-PID Tiny English transcript, and complete API-bound signed rows. Keep publication denial until that producer, semantic admission, and full positive are independently verified.
