# Whisper launch experiment

Diagnostic builds for the two reported first-Open failures. No release qualification.

The source is pinned to `d504e90e63035c4cb8e9597cbef9894253fdaf01`. Before dispatch, retain its actual downloaded app first-Open result on the affected OS. A build or reduced storage probe does not establish this prerequisite. Per-app-approved ad-hoc launch and normal notarized first Open are separate outcomes.

| Variant | Whisper linkage | Library Validation |
| --- | --- | --- |
| A | Static | Disabled for the ad-hoc app |
| B | Same static payload as A | Enabled |
| C | Dynamic, linked from the same Whisper objects | Disabled for the ad-hoc app |

`scripts/build-whisper-experiment.sh` pins Whisper source, Xcode, SDK, all three production package locks and the observed resolved package revisions. It compiles one common Whisper archive. Two isolated app builds supply static and dynamic executable linkage. A and B differ only in fresh signature/entitlement data; C must preserve every unrelated A payload. Every experiment app is newly ad-hoc signed. Historical downloaded apps are unchanged.

Run `bash scripts/tests/whisper-launch-experiment.test.sh` before building. The tests use real bounded Git checkouts, native static/dynamic framework fixtures and fresh signatures. They verify experiment construction, not Roma launch or transcription.

Use the diagnostic workflow through a disposable `ci/roma-whisper-experiment-*` ref. Artifacts retain package/source/toolchain receipts, component and bundle hashes, link maps, entitlements and three app ZIPs. A successful build still reports runtime proof as not run.

Test all three final ZIPs separately on Sonoma `14.2.1/23C71` and Tahoe `26.4.1/25E253`, with browser quarantine, enabled Gatekeeper/SIP, recorded per-app approval, first-PID stability and actual bundled-code maps. Perform a real Whisper file transcription with the same hashed model and audio fixture. Reject a causal conclusion if source, toolchain, unrelated payload, OS or test conditions differ. The historical Whisper and MediaRemote artifacts remain independent controls. Their truncated crash reasons do not establish the missing Team ID as the cause.
