# Broker-signed native collection

This diagnostic binds original native calls and guest observations to one reviewed Mac broker key. Every result keeps `publicationEligible` false. The production release qualifier remains unchanged.

## Files and actors

`native_challenge.py make` creates a fresh challenge from the authenticated Actions run and job metadata. The challenge binds the repository, workflow, tooling SHA, attempt, job, nonce, reviewed policy, and target.

`broker.py arm` reads the challenge artifact through authenticated GitHub APIs. It checks the artifact digest and compares the local broker and protocol bytes with the reviewed tooling commit.

`broker.py export` rechecks the active job, source bytes, and fixed exporter hash. It accepts guest receipts only from the fixed shared `proof/native-challenge/<nonce>` directory. Every ancestor must be an ordinary directory. It runs the supported native history exporter. The exporter retains complete original API responses privately. The broker copies only the selected original calls, their images, and the guest observations.

`broker.py export` then signs `broker-origin.json` with the dedicated task key. The public key is pinned in `policy.json` before the challenge starts. The private key stays outside the checkout in the private task proof directory.

The Actions job reads exact Git blobs from a response commit whose sole parent is the tooling commit. It verifies the signature and reconstructs the inventory from the payload. A supplied pass flag cannot satisfy verification.

## Signed inventory

The canonical UTF-8 JSON uses sorted object keys, compact separators, and one final newline. Its file list uses sorted relative paths.

The inventory binds these fields.

- Repository, workflow, job name, run ID, attempt, job ID, tooling SHA, and nonce.
- Fixed exporter SHA-256, reviewed policy SHA-256, target OS, boot UUID, PID, executable hash, and ZIP hash.
- Collection start, collection end, signing time, and each original call identity and timestamp.
- The size and SHA-256 of the challenge, broker execution receipt, every selected original entry and image, and all six guest files.

The signature uses `ssh-keygen -Y sign` with namespace `roma-native-origin@roma-just-talk`. Verification uses an allowed-signers file containing the pinned public key and identity `roma-native-origin-task-broker`.

Unsigned payloads, changed bytes, changed metadata, duplicate or omitted inventory entries, path escapes, symlinks, and signatures from another key or namespace fail. Verification does not execute code from the response commit.

## Collection lifetime

A new collection has a 15-minute deadline. The calls, guest observations, export, and signature must finish inside that window. The broker checks the clock again after the signing process exits. A late result retains its completion time, exit code, and signature digest in `broker-sign-failure.json`. Signature bytes stay in memory and are withheld from the failed response.

A completed signed collection remains verifiable after its challenge expires. Verification still requires the signed collection and signing timestamps to precede the original deadline. The current time must follow the signing time.

## Trust limits

The public key identifies the declared Mac broker. The signature does not attest to the Mac hardware, guest hardware, or exclusive control of the private key. The trusted broker can sign false observations if its code, host, or key is compromised.

The history exporter proves that the selected bytes match the original supported API output available to the broker. The signature preserves that broker assertion across transport. Guest command origin remains inside the declared broker trust boundary.

The target PID comes from the separate first-open collector. This diagnostic does not establish that a supplied PID was the first process after Finder Open. The diagnostic also does not establish notarization, normal first-open success, transcription accuracy, or release eligibility.

Only a fresh live collection can verify the operational signing path. Fixture signatures and the earlier unsigned successful diagnostic run cannot establish that result.

## References

The signing interface is documented in [OpenSSH ssh-keygen](https://man.openbsd.org/ssh-keygen#Y).

The local fresh-roundtrip guide and controlled tests are in `/Users/atalphalnmomhappyhouse/.codex/task-artifacts/roma-macos-proof/release-qualification/native-origin-proof/README.md`.
