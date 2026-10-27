# Ollama snapshot identity proof

[Run 40545355522](https://github.com/negentropi/roma-just-talk/actions/runs/40545355522) passed for candidate `1f36a74614ac95aca70908f4be345d83f3e7886b` against baseline `830d45210816a36c2db70b09d1329a0ef8b7ddf6`.

The actual service and pinned SDK completed all six cases. The two baseline metadata mismatches reproduced after successful HTTP responses. The coherent baseline control and all three candidate cases passed.

| Case | Held wire model, both versions | Baseline result model | Candidate result model |
| --- | --- | --- | --- |
| No model keys | `llama2` | `mistral` | `llama2` |
| Divergent model keys | `new-model` | `old-model` | `new-model` |
| Coherent model keys | `chosen-model` | `chosen-model` | `chosen-model` |

Every held snapshot sent its request to endpoint A after preferences changed. Every fresh snapshot sent its request to endpoint B with `later-model`. The held snapshot's model metadata remained unchanged after fresh execution.

The raw receipts contain 24 completed HTTP 200 requests, including 12 generation requests. All six processes exited 0. All 12 results contain exactly `RJT ollama identity receipt.`. Decoded HTTP prompt and system fields match the request metadata byte for byte. The payload retains the synthetic Unicode, CRLF, newline, and tab input. No request contains an Authorization header.

All 54 preference checkpoints match the expected persistent dictionaries. Only explicit provider selection and model selection write preferences. Each case uses a unique bundle identifier and an in-memory SwiftData container. Local CLI selection precedes production initialization, and both selected providers use the credential-free resolution path.

Independent checks matched all 22 app-source hashes and 296 local-dependency source hashes against the exact Git revisions. Both versions use the same driver, package manifest, and 26 pinned external packages. The before-build and after-build receipts match across both versions, covering 9,741 tracked files per dependency closure. Fresh reads of the four immutable LLMkit blobs match the recorded source SHA-256 values.

Both retained `package-graph.json` files contain raw SwiftPM command output with a 1,373-byte warning prefix, so their complete contents are not valid JSON. The audit preserved those bytes and did not use those files for its dependency verdict. That verdict uses the exact `Package.resolved` pins and checkout revision and tracked-source receipts before and after the builds.

All six ad hoc signatures identify the expected unique arm64 bundles. Bundle file hashes match before and after execution. Signature verification succeeds before and after each case. The run also passed its listener shutdown and thread-join checks.

The audit checked the raw case receipts independently of the classifier, then reran the committed classifier over those receipts. Both checks agree with `passed-red-green`. No native build or UI ran on the user's Mac.

The proof covers synthetic HTTP routing, request identity, result metadata, and preference isolation. It does not establish real Ollama inference, app lifecycle behavior, TCC, microphone behavior, editor delivery, timeout timing, cancellation, or retry behavior.

## Retained evidence

- [Run metadata](run.json) and [runner environment](environment.txt).
- [Frozen source contract](input-contract.json) and [independent input audit](input-audit.json).
- [Independent native audit](native-audit.json) and [SDK and package audit](dependency-audit.json).
- [Raw native receipts and comparison](native/comparison.json).
- [Artifact file sizes and hashes](artifact-manifest.json).

Input artifact `12753105681` has SHA-256 `9fade7186de7d67ab1a5b0ef615cc1e86b695f02e98f9466519e9f3277d82bb6`.

Final evidence artifact `12751684342` has SHA-256 `0760d9723c55120eee87f32ac18169a195ac1a97c1a8201295dd3f44f447a46b`. It contains the full build logs, source copies, and dependency receipts. This directory retains compact receipts and their hashes without a duplicate ZIP.
