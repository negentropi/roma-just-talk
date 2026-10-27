# Global literal dictation profile

Next unit after the first Mac writing/snippet gate passed on `ebc92f1e` in [run 40507127520](https://github.com/negentropi/roma-just-talk/actions/runs/40507127520). Final artifact review is separate from this implementation. The [four-profile proposal](cleanup-profile-design.md) remains the later target. Felix subsequently confirmed dictation polish as the next priority, including cleanup levels, styles, corrections and undo.

## Checklist

- [x] Read Poteto mode's Principles section in full.
- [x] `how` over the affected subsystem. Two source investigations and the independent contract review covered recording, import, retranscription, Power Mode ownership and final delivery.
- [x] `architect` for parallel design exploration. Compared all four profiles, a per-mode Custom/None stage, and a global Custom/None stage. Choose global Custom/None. It delivers an actual raw option without coupling it to unresolved provider, tokenizer, schema or Power Mode snapshot changes.
- [x] Write the throughput checkpoint as four todo items.
  - [x] **Blocking first steps.** The previous full gate passed before implementation fan-out. Confirm source owners and the captured enum interface first.
  - [x] **Independent workstreams.** Core preference/preparation/backup, Mac operation adapters, source-compatible tests and Claude-owned UI have disjoint paths.
  - [x] **Shared mutable state.** Core owns its public interface. Mac adapters consume it. Tests use owned defaults and stores. No worker commits or edits another owner's files.
  - [x] **Smallest safe decomposition.** One backend owner handles all operation entry points and final delivery; splitting those would create inconsistent literal semantics. Core, tests and UI remain independently reviewable.
- [ ] Delegate code-writing to scoped owners; review actual diffs.
- [ ] Verify on the matching surface. Require intended known-bad failure and candidate success with the same pipeline oracle, full relevant gates and real settings interaction.
- [ ] Keep small, ordered atomic commits. No history rewrite is needed.
- [x] Contested design resolved by independent source review. Per-mode fields would inherit the existing whole-snapshot notification hazard; defer them until that ownership is addressed.
- [x] Opening a PR skipped. The user authorizes local commits and disposable CI transport refs. Normal branch push and publication are outside this unit.

## Contract

`VoiceInkDictationProfile` has Custom and None. A global persisted preference resolves missing or unknown stored values to Custom. Old backups without the new optional field leave the current value unchanged. Invalid explicit backup values fail preflight. Profile changes preserve libraries and Custom settings; the existing full app reset retains its existing deletion semantics.

None applies to ordinary dictation across all apps and Power Modes. It preserves the exact string returned by the recognizer service, including nonblank leading/trailing whitespace. It bypasses snippets, replacement rules, cleanup filters, prompt triggers, AI enhancement, cursor recasing, trial text prefixes and added spaces. Existing explicit Writing Actions remain independent. None does not promise raw decoder tokens or recover older recognition output.

Capture the global profile once when a recording start is accepted, before permissions or Power Mode resolution can suspend. Power Modes do not own this global preference. Source inspection found a reentrant stop during Power Mode activation, so capturing only after that await would be too late. Import and retranscription capture it at entry. Changing the global profile affects the next operation. Custom retains its existing live preferences and the existing differences between recording, import and retranscription. No provider-freezing claim applies to this stage.

None makes no AI request and captures no AI clipboard or screen context. Cursor information for existing paste-target validation remains separate. Nonblank output uses the existing delivery owner with literal formatting. Blank-only recognition produces no paste and discards pending Special-mode previous-transcript fallback. It must not paste an older recording or leak that pending fallback into the next operation.

None stores recognition output in existing `Transcription.text`, with `enhancedText` absent. Existing History labels retain their meanings. No model migration, new raw variant or relabeling of old records is included. Cancellation remains cancellation, including after recognition and before audio-file record insertion/save.

## Ownership

| Owner | Paths |
| --- | --- |
| Core | `DictationProfile.swift`, `TranscriptionRunProcessor.swift`, backup/reset owners, corresponding Core tests and runner |
| Mac adapters | `VoiceInkEngine.swift`, `TranscriptionPipeline.swift`, audio-file manager/service, `LastTranscriptionService.swift` |
| Checks | New source-compatible `DictationProfilePipelineTests.swift` and isolated helpers; parent owns CI integration |
| Claude Opus 5.5 | `ModelSettingsView.swift` and new supporting Views only |
| GPT-6.1 Sol | Independent review of Claude's actual UI |
| Parent | Integration, docs, changelog, remote gates, artifact review and commits |

## Acceptance

1. Same unchanged pipeline test source on pinned `ebc92f1e` and candidate. A literal defaults key and the existing run signature keep the oracle source-compatible. Exact UTF-8/UTF-16 output must differ on the old source for the intended reason and pass on the candidate.
2. Enable incompatible cleanup, snippet, replacement and AI settings. None preserves tags/brackets, repeated whitespace, quoted command mentions, mixed scripts and emoji. AI and prompt-trigger calls remain zero. Custom control retains its current behavior.
3. Hold recognition, change the profile, then release. The current operation retains its initial profile; the next uses the changed preference. Engine capture before permission and early-stop dispatch also needs appropriate native or equivalent boundary evidence.
4. Empty/whitespace None with pending Special fallback produces no insertion and consumes the pending fallback. Cancellation produces no insertion or successful completed fallback.
5. Verify audio import and retranscription through their actual adapters, including cancellation after recognition. Shared Core tests alone do not establish adapter behavior.
6. Verify missing defaults, unknown stored values, old/new backup handling and existing reset semantics. No per-mode profile field or general settings notification is added.
7. Exercise the global settings picker, persistence and Custom-control presentation in the real Mac UI. Inspect screenshots and review through GPT-6.1 Sol.
8. Run shared core, full Mac units and the existing writing/snippet/native/UI/Release gate against the integrated source. LOCAL_BUILD fixes the license state; trial-prefix bypass can be source-reviewed but is not a forced expired-license runtime claim without an existing valid seam.

Light, Clarity, per-mode profiles, frozen provider plans and separate recognition/failure storage remain queued. Deterministic filler removal needs multilingual negatives; bare `um` is meaningful Portuguese and cannot be removed globally on an auto-language path.
