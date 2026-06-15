# Changelog

## v1.94 - Unreleased

- Replaced the misaligned silence-filter path with rolling buffer preload controls that use local VAD to pre-run supported STT before capture finalization, independent from final/batch transcription VAD.
- Added configurable rolling buffer duration with decimal seconds support.
- Renamed model-card transcription mode controls to "Streaming" so they stay separate from rolling buffer preload.
- Moved recorder audio-duration metadata work after paste so completed text reaches the cursor sooner.
- Deferred the recorder history save until after transcription work starts so quick releases do not wait on SwiftData I/O before STT.
- Removed the fixed pre-paste delay after verified clipboard writes so completed text posts to the cursor sooner.
- Skipped cursor-context Accessibility reads when capitalization logic can prove the output text cannot change.
- Reduced the fixed autosend wait after paste from 500ms to 120ms while keeping a short guard before Return is posted.
- Moved Auto low-battery checks for rolling buffer preload to after local VAD detects speech, keeping silence cheaper and battery decisions current at preload start.
- Claimed ready rolling-preload sessions before Power Mode configuration work so quick releases do not wait on model/session setup when the preloaded model and language still match.
- Tightened cached rolling-preload finalization so quick releases avoid pasting stale partial hypotheses when the local ASR pass is behind the live buffer.

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
