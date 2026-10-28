# Next Mac unit: dictation cleanup profiles

Historical four-profile proposal. The accepted [global Custom/None contract](raw-profile-plan.md) and [global Light/Clarity plan](clarity-run-plan-design.md) supersede its after-Power-Mode capture and per-mode scope below. Capture is before permission work; per-mode profile/style/provider overrides remain deferred. Target: existing Swift Mac app.

## Contract

Resolve one profile for each operation. Recordings capture it after Power Mode resolution; imported audio and retranscription capture it when processing starts. Later settings changes affect the next operation.

| Profile | Output |
| --- | --- |
| Custom | Existing scalar cleanup, custom fillers, replacements, prompts, context and enhancement behavior. Upgrade default. |
| None | Exact recognizer-returned text. Skip snippets, replacements, filters, AI, cursor recasing and added spaces. Libraries remain saved. |
| Light | Deterministic cleanup of a small documented hesitation set outside quoted/code/protected text. Preserve substantive repetitions, names, numbers and command mentions. Explicit snippets and replacements remain available. Custom filler lists remain Custom-only. |
| Clarity | Fixed bounded cleanup request through the existing provider. Style belongs to this profile. Snippet matches retain literal delivery precedence. |

Clarity failure delivers the exact recognizer-returned text once, warns that the original was inserted, and retains the original and failure reason in History. It must not silently apply Light. Cancellation inserts nothing. Explicit Writing Actions retain their existing no-insertion failure contract because their transcripts are instructions rather than dictated content.

None is an explicit opt-out from personalization transforms. Custom remains the default so the new setting does not change existing snippet or formatting behavior.

## Why scalar presets are insufficient

- `VoiceInkTranscriptionCleanupConfiguration.disabled` still removes tag and bracket content through `filterRawOutput`. Preparation also trims the result.
- The pipeline applies replacements, prompt detection, cursor case and trailing-space changes after cleanup.
- Current cleanup preferences are read after recognition, allowing an in-flight operation to change behavior.
- Existing arbitrary enhancement prompts can summarize or translate. Existing Email templates add greetings and sign-offs. A bounded cleanup request must preserve the dictated facts and language.

These are source findings, not competitor runtime observations. [Wispr's cleanup documentation](https://docs.wisprflow.ai/articles/4283510616-auto-cleanup-control-how-much-flow-edits-your-dictation-beta) provides precedent for raw output, next-dictation settings and raw fallback after formatting failure. [Its styles documentation](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles) distinguishes category formatting. RJT can retain its existing app/URL Power Mode selection rather than adding another resolver in this unit.

## Ownership

Use a single typed profile with Custom, None, Light and Clarity with its style. Keep deterministic transformations and fixed request construction in VoiceInkCore. Reuse the current provider retry and immutable snapshot machinery. Do not temporarily change the selected prompt.

Extend the existing global preference, Power Mode configuration/form, active-session snapshot, apply/restore/crash recovery, backup/import and reset owners. Missing global or old mode fields mean Custom. Missing backup fields leave current preferences unchanged. Changing profiles must preserve the user's Custom settings.

Recording, audio import and retranscription must share the same resolution and output contract. Avoid three independent implementations.

Store actual recognition output separately from the existing processed `Transcription.text` value. Historical records cannot recover discarded recognition text and must not be relabeled as raw. None promises the text returned by the selected recognizer; it does not promise unnormalized decoder tokens.

Claude Opus 5.5 owns settings, Power Mode and History UI. GPT-6.1 Sol reviews it. Initial styles should remain small and demonstrable; they apply only to Clarity. Category inference remains separate work.

## Acceptance

1. Same matched pipeline fixture against a pinned bad commit and candidate. With an enabled snippet and replacement, None delivers exact recognition text including bracket/tag content, repeated whitespace, quoted commands, mixed languages and emoji. The bad source must fail that assertion.
2. Light removes only documented hesitation cases. Preserve quoted `um`, code, URLs, email, repeated names, Traditional Chinese and meaningful phrases from arbitrary Custom filler preferences.
3. None and Light make no AI request or prompt-trigger intent switch. Snippets remain literal in profiles that enable them.
4. Change profile/provider while recognition waits. The in-flight operation retains its snapshot; the next operation uses new settings.
5. Clarity missing configuration, timeout and empty output each produce one exact raw fallback and a warning. Cancellation produces no delivery. Real provider fixtures check facts, language, literal command mentions, lists and email structure.
6. Power Mode exit, mode switching and persisted recovery restore the profile and Custom settings. Verify old JSON decoding, backup round-trip, missing-field import and reset.
7. Exercise the same contract through audio import and retranscription. Inspect actual settings and History screenshots, persistence, keyboard navigation and failure recovery.

## Design review

Two independent source investigations rejected scalar presets because they cannot preserve literal text. Their disputed snippet and provider-failure contracts went through an independent judgment. The chosen None contract gives a dependable literal opt-out. Exact raw fallback keeps ordinary dictation useful without adding a second implicit transform after Clarity fails.

This document records a proposed next unit. No profile implementation or runtime proof is claimed.
