# Changelog

## v1.94 - Unreleased

- Replaced the misaligned silence-filter path with rolling buffer preload controls that use local VAD to pre-run supported STT before capture finalization, independent from final/batch transcription VAD.
- Made the fresh Special shortcut default preload-only so quick releases can commit the rolling-buffer pre-run path without opening a recorder first.
- Added configurable rolling buffer duration with decimal seconds support.
- Renamed model-card transcription mode controls to "Streaming" so they stay separate from rolling buffer preload.
- Renamed the provisional transcript UI toggle to "Show Transcript Preview" so it no longer reads like a separate live-transcription feature.
- Moved recorder audio-duration metadata work after paste so completed text reaches the cursor sooner.
- Deferred the recorder history save until after transcription work starts so quick releases do not wait on SwiftData I/O before STT.
- Removed the fixed pre-paste delay after verified clipboard writes so completed text posts to the cursor sooner.
- Skipped cursor-context Accessibility reads when capitalization logic can prove the output text cannot change.
- Reduced the fixed autosend wait after paste from 500ms to 120ms while keeping a short guard before Return is posted.
- Blocked Auto low-battery local rolling-buffer preload before loading or running the local VAD, so the low-battery opt-out now fully disables buffer pre-run work.
- Claimed ready rolling-preload sessions before Power Mode configuration work so quick releases do not wait on model/session setup when the preloaded model and language still match.
- Tightened cached rolling-preload finalization so quick releases avoid pasting stale partial hypotheses when the local ASR pass is behind the live buffer.
- Let preload-only Special shortcut quick releases commit the rolling buffer instead of being canceled as short no-evidence presses.
- Preserved pre-roll-first streaming order without holding the recorder file lock through the whole pre-roll emission.
- Released the recorder file lock before forwarding queued live chunks after pre-roll streaming emission, reducing audio-thread blocking risk during startup handoff.
- Shortened the post-commit wait for local FluidAudio streaming finalization while preserving the longer cloud streaming wait.
- Moved the rolling-buffer VAD model picker into Rolling Buffer settings and clarified active-recording streaming text so buffer preload is not presented as generic live transcription.
- Overlapped rolling-preload quick-release active-window Power Mode application with STT finalization, so ready preloads no longer wait on window rule resolution before stopping the pre-run session.
- Removed a fixed post-STT wait before trigger-word AI enhancement starts.
- Removed fixed sleeps between simulated paste key events so completed text reaches the target app sooner.
- Kept warmed local STT resources after successful transcription so the next recording and rolling-buffer preload avoid an immediate teardown/reload cycle.
- Warmed the rolling-buffer VAD model before first speech when preload is eligible, so the first VAD trigger can start STT without paying model-load delay.
- Broadcast the restored startup transcription model so rolling-buffer preload can warm immediately after launch instead of waiting for a later settings change.
- Let preload-only quick releases commit an already-ready rolling-buffer STT session directly, without opening and stopping a new recorder session first.
- Let preload-only quick releases fall back to the current rolling-buffer audio snapshot directly, avoiding a recorder open/stop cycle when no pre-run session is claimable and the model supports saved-WAV transcription.
- Preserved rolling-buffer audio for direct snapshot fallback when an existing pre-run session is canceled by a model, language, or finalization-policy mismatch.
- Preserved rolling audio collected while a preload-only quick release finalizes, so the next rolling preload does not restart from an empty lead-in after paste.
- Deferred quick-release rolling-preload history insertion until the post-paste save boundary, removing avoidable SwiftData work before the cursor paste starts.
- Warmed and cached word replacement rules outside the dictation hot path so quick-release paste no longer repeats the SwiftData lookup before every cursor paste.
- Deferred quick-release rolling-preload WAV writing until after cached stream finalization can start, while still waiting for the file before batch fallback or history metadata needs it.
- Added claim-to-paste latency tracing for rolling-preload quick releases so remaining delays can be measured from runtime logs.
- Included rolling-buffer preload mode, duration, VAD model, Auto policy, power state, and per-model preload state in diagnostic log exports.
- Added the last rolling-buffer quick-release claim strategy and claim-to-paste timing to diagnostics so packaged builds can show whether a release used ready preload, buffered audio snapshot, or missed the rolling path.
- Started Power Mode rule resolution on preload-only Special shortcut key-down, so quick releases avoid doing active-window and URL matching work after key-up.
- Cached prompt trigger-word eligibility and skipped prompt detection in the common no-trigger case, reducing transcript-ready-to-paste work.
- Pre-read cursor text context on preload-only Special shortcut key-down so contextual capitalization can avoid an Accessibility read immediately before quick-release paste.
- Pre-read clipboard restore context on preload-only Special shortcut key-down so restore-enabled quick releases avoid copying pasteboard data immediately before paste.
- Started quick-release rolling-buffer WAV writes immediately after claiming buffered audio so file I/O overlaps Power Mode resolution instead of running wholly after key-up validation.
- Used the claimed rolling-buffer PCM byte count for quick-release history duration, avoiding a post-paste AVFoundation metadata read.
- Deferred quick-release session metric recording until after the rolling-preload pipeline returns, so the app can leave the busy path before noncritical metric I/O.
- Deferred quick-release history persistence until after the rolling-preload pipeline returns and added returned/idle timing diagnostics for measuring the remaining post-paste tail.
- Deferred rolling-preload quick-release Power Mode/session restoration until after the engine marks idle, with diagnostics for the remaining session-finish tail.
- Skipped browser URL lookup during automatic Power Mode selection when no enabled URL rules exist, removing an avoidable pre-pipeline quick-release delay.
- Reduced the shortcut duplicate-press guard from 500ms to 80ms so valid back-to-back dictations are not ignored after the app is ready again.
- Skipped fallback streaming setup on immediate startup-stop recordings when the selected model can transcribe the saved WAV directly.
- Included rolling buffer preload mode, per-model opt-outs, Auto policy, duration, finalization, and VAD model settings in settings backup/import.
- Made the pre-run finalization opt-out also skip rolling-buffer STT pre-run work instead of warming an unusable session.
- Preserved the exact latest rolling-buffer preload audio when incoming chunks exceed or cross the configured duration boundary.
- Canceled warm rolling-preload sessions when the selected transcription language changes before the shortcut claims them.

## v1.93 - 2026-06-15

- Improved cursor-context capitalization in editors that expose focused text but not an exact Accessibility cursor range.
- Made Special shortcuts fail closed when key evidence is unreliable, including secure text entry, held companion keys at Shift release, and very short no-evidence Shift presses, so hidden typing does not start dictation.
- Removed the Keyboard Shortcut setup card from App Permissions so the page only lists macOS permission grants.
- Renamed the main sidebar items to home, manual stt, past, models, and style.

## v1.92 - 2026-06-13

- Fixed Special shortcut typing detection for Karabiner mappings that emit bare function keys, including `Left Shift` + `X` and `Left Shift` + `S/D/F`.
- Fixed Special shortcut empty taps so they only paste the previous transcription after the current tap transcribes empty, instead of treating every short tap as paste-only.

## v1.91 - 2026-06-12

- Polished the app shell and dashboard with cleaner native glass surfaces, quieter accent use, and a less marketing-heavy metrics layout.
- Added cursor-context capitalization for dictation paste so mid-sentence inserts lower an auto-capitalized first word while sentence starts stay capitalized.
- Fixed Special shortcut typing detection so fast held Shift chords such as `Shift` down, `S` down, `Shift` up reliably cancel instead of pasting last text or committing an empty recording.
- Made Special shortcut empty taps paste the last transcription immediately instead of waiting for an empty recording to transcribe.
- Reused the PermissionFlow grant path for shortcut warning banners and metrics permission actions instead of direct System Settings deep links.

## v1.90 - 2026-06-10

- Released a branch that excludes the nine post-v1.82 ad-hoc packaging, entitlement-proof, notarized DMG, and PermissionFlow routing commits while preserving the later shortcut fixes.

## v1.89 - 2026-06-10

- Fixed Special shortcut flex-off handling so modifier-only shortcuts fail closed when the key-evidence event tap is unavailable.
- Updated the app bundle version metadata to 1.89 / 189 for the release artifact.

## v1.88 - 2026-06-10

- Added Special shortcut sub-settings for keydown preload behavior, key-down-only flex, and empty-tap paste-last fallback.

## v1.87 - 2026-06-09

- Fixed a post-keyup latency regression by finalizing the recording file without restarting the pre-roll AudioUnit on every stop.

## v1.86 - 2026-06-09

- Reissued the release as v1.86 after the v1.84 and v1.85 tags failed before publishing an app asset.
- Hid the menu bar icon by default for fresh installs while keeping Dock-icon hiding as a separate setting.
- Added Special shortcut mode as the fresh default with Left Shift: start recording on keydown, decide on keyup, and cancel typing cases where another key was released during the hold.

## v1.83 - 2026-06-08

- Switched release packaging to a simple Airpods-style ad-hoc signed `.app.zip` build.
- Removed dashes from the generated app wrapper and bundle name so macOS shows roma just talk.

## v1.82 - 2026-06-08

- Renamed the generated app wrapper and bundle name to roma-just-talk so macOS system dialogs use the fork name.

## v1.81 - 2026-06-08

- Replaced the README, source app icon, and menu bar logo with the roma-just-talk split-keyboard mark.
- Changed fresh defaults to Parakeet V2, menu-bar-only mode, muted sound feedback, and launch-at-login, with Parakeet auto-downloaded for the selected default.
- Renamed the visible app shell to roma-just-talk while leaving bundle identifiers and update infrastructure unchanged.

## v1.80 - 2026-06-01

- Added guided macOS permission grants with PermissionFlow.
- Fixed permission refresh so Microphone and Accessibility grants update while VoiceInk is running.
- Added an inline "Relaunch to Apply" path for macOS permissions that TCC grants but only activates for a fresh process.
- Made Screen Context optional and removed it from the required setup gate.
- Avoided disruptive direct Screen Recording prompts and removed the noisy floating screen-recording hint.
- Added GitHub Actions build artifact packaging for the macOS app.
- Updated the project pitch toward pre-roll voice capture and rolling voice buffer language.
