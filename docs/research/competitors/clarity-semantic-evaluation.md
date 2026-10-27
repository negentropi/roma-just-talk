# Evaluate Clarity through the actual service

Prepared 2026-10-28 Taipei. No Clarity model calls have run for this set. Keep app integration behind the [current Custom/None gate](raw-profile-plan.md). Follow the [accepted Clarity contract](clarity-run-plan-design.md) when the dedicated service method exists.

## Separate generation from grading

Use [nine synthetic inputs](fixtures/clarity-inputs.json) under `natural`, `casual`, and `formal`, for 27 actual service calls. The input file contains only local case IDs and transcripts. Pass only the transcript and chosen style into `VoiceInkClarityRequest`. Its production constructor supplies the fixed system message and JSON user message.

Keep [the private rubric](fixtures/clarity-private-rubric.json) outside generation input and the generation working directory. `private` identifies the grader-only role. It does not claim filesystem security or secret content.

Run each generation in a fresh conversation with tools, MCP, hooks, repository instruction discovery, and session persistence disabled. Use an isolated working directory containing only the input and constructed request messages. Never copy expected facts, allowed answers, rubric text, grader reasoning, or earlier outputs into that directory or generation context. Inspect the selected CLI's supported isolation options before the later model call.

Give the grader the input, style, actual decoded output, and separate rubric after generation completes. Keep the grader's conversation separate from generation. Review meaning and allowed style changes, not one golden string. Identical valid outputs across styles are acceptable.

## Call the Clarity method

1. Build the reviewed app service sources with the new Clarity wrapper. Record its actual method name and source hashes. Use a unique signed probe identity, volatile preferences, and the smallest in-memory model context required by the service. Do not launch the normal app lifecycle.
2. Select the isolated Local CLI route before constructing `AIService`. Keep ordinary enhancement, clipboard context, and screen context disabled. Do not enumerate connected providers or transfer credentials into the probe.
3. Capture the immutable provider configuration once. Construct `VoiceInkClarityRequest` from one input and one style. Call the dedicated Clarity service method through the actual provider executor.
4. Retain the raw synthetic provider response before app decoding. Decode through `VoiceInkClarityRequest.decodeResponse`. Compare the envelope's decoded string with the app result in both UTF-8 and UTF-16.
5. Grade each actual result against the separate rubric. Record envelope failures, fallback, cancellation, retries, and semantic failures. Retain all first outputs and retries.

Do not substitute `performWritingAction`, `enhance`, a direct CLI invocation, or a reconstructed prompt for the dedicated app method. The current `AIEnhancementService.makeRequest` filters Local CLI results through `VoiceInkAIEnhancementRequestPayload.enhancedText(from:)`. Clarity must receive the unfiltered provider string and decode its own envelope. Existing Custom and Writing Action filtering remains a separate contract.

Use stdin for the command's request input. The [corrected prior transport receipt](evidence/local-cli-service-40501506898/receipt.json) distinguishes exact UTF-8 stdin and request metadata from canonically equivalent environment text with different UTF-8 and UTF-16. Do not call environment transport byte-exact because Swift string equality passes.

For later pipeline cancellation checks, reuse the operation owner behind `TranscriptionPipeline.activePasteTasks` and `cancelDelivery(for:)`. A provider task must observe the canceled operation before registration and before delivery. Register ownership without an intervening await. Keep import work under its already-owned parent task. This semantic set does not establish those cancellation boundaries.

## Retain the evidence

Record these fields for each actual attempt. Use synthetic transcript content only.

- Case ID, style, source revision, request-constructor and service-source hashes, input-file hash, rubric hash, dependency lock hashes, build command, toolchain, executable hash, signature, and probe bundle identity.
- Exact system and user messages, their hashes, raw provider envelope, decoded provider text, app result, and UTF-8 and UTF-16 equality observations.
- Route and executor, actual CLI executable path and hash, CLI version, sanitized command configuration, requested model, served model if exposed, timeout, retry policy, and attempt number.
- Actual endpoint and model from the captured route when applicable. For Local CLI, mark a hidden endpoint unavailable. Never treat the app label `local-cli` as the served model identity.
- UTC start and end timestamps, elapsed time, exit or transport outcome, decoding outcome, cancellation, fallback reason, and independent invariant and style verdicts with output spans.
- Isolation settings, disabled context state, and confirmation that the unique persistent preference domain remains unchanged.

If text-mode CLI output does not expose the served model, record it as unavailable. Keep configured and observed identity separate. Exclude credentials, tokens, auth files, broad environment output, raw session identifiers, and unrelated user content.

## Reuse the verified setup

The [actual Local CLI service proof](evidence/local-cli-service-40496074931/summary.md) used source `f870a0b04238f338b52855b081b49087cc8966fa`. Remote CI built the signed artifact. The same artifact then ran quietly on the local Mac through `AIService`, `AIEnhancementService`, and `LocalCLIService`, using existing Claude CLI ambient API-key authentication. Three writing-action samples passed independent semantic review. Text output did not expose the served model.

Reuse the isolation and artifact checks in [`run-writing-local-cli-service-probe.sh`](../../../scripts/run-writing-local-cli-service-probe.sh), then replace its writing-action call with the dedicated Clarity method. Its semantic mode explicitly rejects `GITHUB_ACTIONS=true`. The earlier [prompt-only smoke](evidence/writing-cli-smoke/summary.md) reported `claude-opus-5-5`, but that does not identify the model served by the actual service probe or a future call.

The coordinator checked `root@decentleftover-pf` around 2026-10-27 18:50 UTC. The sanitized observation found `/usr/local/bin/codex`, version `codex-cli 0.163.0`, and no `claude`. The Codex auth-status command exited 1 and reported logged-in false. This is a current-task observation; no durable raw receipt was saved. It establishes an installed CLI and that reported auth status only. It does not establish an authenticated remote route, other CLI configuration, or future availability. No model call, OAuth file read, credential copy, or installation occurred.

At 2026-10-27 20:13:58 UTC, a new read-only remote check again found no Claude and Codex reporting `Not logged in` (exit 1). The local `/opt/homebrew/bin/claude` reports version `2.1.310`; `claude --bare auth status --json`, projected to nonsecret fields only, reports `loggedIn: true`, `authMethod: api_key`, `apiProvider: firstParty`. No auth file, token or model call was used. This confirms the quiet local route is available for the remotely built probe, subject to its actual execution checks; it does not identify a served model.

Recheck the executable/signature and nonsecret auth status at execution time. Prior authentication is historical evidence, not a guarantee of future access. Do not ask the user to install or copy credentials for this preparation.

## Keep the claims bounded

The [Core receipt](evidence/core-40562076345/receipt.json) binds all 1,707 passing checks to `aaaa286a794ac6f60773ef5149a30f214c586f23`. It proves the pure policy and JSON boundary, including exact decoded code units. It does not prove model behavior or app integration.

These 27 calls would establish actual outputs for nine synthetic utterances through the tested Clarity route, model identity where observable, and configuration. They would not establish general writing quality, broad instruction-injection resistance, ASR accuracy, microphone behavior, recording or import integration, storage durability, cancellation, editor delivery, physical input, or UI quality. Test those boundaries separately. A JSON sample does not prove that a model obeys instructions; a semantic pass does not replace the transport and native integration gates.

## First actual run and authentication correction

[Remote build 40577497741](https://github.com/negentropi/roma-just-talk/actions/runs/40577497741), exact `18552122`, compiled the actual service and signed the unique probe. The [independent build audit](evidence/clarity-semantic-build-40577497741/summary.md) verifies source, 26 canonical checkouts, signed bundle and zero CI model calls. The signed artifact then passed fresh verification on the quiet local Mac.

The [first 27 actual service attempts](evidence/clarity-semantic-40577497741/summary.md) all failed authentication: exit 1, no decoded model result, and the same OAuth-expired message. Every first attempt and raw stream remains retained. A complete observation receipt is not semantic success; no grading was performed.

The earlier auth preflight and the print route used different settings flags. At the same CLI version, `--setting-sources ''` reports no authentication; `--setting-sources user` reports the existing first-party API-key configuration. The empty setting source also failed the separate UI invocation before any edit or cost. Authentication status alone does not prove a subsequent print request succeeds.

The corrected runner uses one shared set of isolation flags for version, help, sanitized auth status and print. It retains user settings for existing authentication while `--bare`, disabled hooks/tools/MCP, a fresh input-only working directory and no session persistence keep generation context isolated. Auth status is projected to three approved fields and exit code, without retaining its raw response. The strict packaged-runner identity check is preserved, so this requires a new remote artifact rather than editing the prior signed package. A new authenticated 27-result run and independent grading remain acceptance work.
