# Cursor companion

The cursor companion confirms that roma is really listening (NEG-27). With the default recorder style of None there is no other running-state UI, so the companion is the cue users learn: if it is not on the cursor, roma did not start.

## Behavior

`VoiceInkCursorCompanionPolicy` (VoiceInkCore) owns the phases.

- **awaitingAudio.** Recording reached `.recording`. Nothing is shown until `Recorder.capturedBufferCount` advances, which proves the microphone delivers buffers.
- **arriving → listening.** The mascot pops onto the text caret (hug pose) when the focused element exposes one through Accessibility, else onto the mouse pointer (perch pose). It then settles with slow breathing. Reduce Motion fades instead.
- **leaving.** Recording ended.
- **failed.** Recording could not start: no model, microphone permission, or recorder error. Red glow, pulses, and shake for 2.6 s next to the existing error notification.
- **stalled.** No audio for 2 s while recording. Same red treatment plus a "Microphone isn't sending audio" notification, held until audio recovers or recording ends.

Users pick Cartoon, Storybook, Anime, or None in onboarding (between model setup and the tutorial) and in Settings › Interface.

## Artwork

Original mascot, three styles × three poses (`perch`, `hug`, `oops`) in `VoiceInk/Assets.xcassets/companion-<style>-<pose>.imageset`. Generated with Codex image generation from `Tools/CursorCompanionArt/prompt.md` (Cartoon was regenerated with `prompt-cartoon.md`). The hug pose is drawn around a pure-green placeholder bar, which `process.swift` removes; the app draws the caret bar into that gap.

To regenerate: produce 1024 px transparent PNGs, then

```sh
swiftc -O Tools/CursorCompanionArt/process.swift -o /tmp/companion-process
/tmp/companion-process raw/anime-hug.png out/anime-hug.png 288   # prints caretBarX / caretBarWidth
Tools/CursorCompanionArt/install.sh out/*.png
```

Copy the printed hug measurements into `CursorCompanionArtwork.geometry`. `Tools/CursorCompanionArt/render-frames.sh <dir>` renders every style and pose through the production view over time; Codemagic runs it and keeps the frames under `artifacts/cursor-companion`.
