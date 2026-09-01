# Landing site

Static landing pages plus the full-screen `/demo` browser experience.

```sh
npm install
npm run dev
```

The demo starts browser speech recognition when the page loads. It keeps up to
the previous three seconds of recognized words in the tab, adds speech heard
while Left Shift is held, and inserts the claimed words on release. There is no
model download, site transcription API, or Roma microphone-audio upload. The
browser may process audio on the device or send it to its own speech provider.

```sh
npm test
npm run test:e2e
```

The browser test uses installed Chrome with a deterministic SpeechRecognition
implementation so it can prove the whole interaction without a network speech
service.

The separate macOS hardware lane proves the part that suite cannot: it starts a
real WAV player 1.1 seconds before Left Shift, routes the WAV through BlackHole
into Chrome, waits for playback to finish, and then releases Shift. The expected
opening word proves pre-trigger audio reached Chrome. The lane rejects fixtures
below -30 dBFS RMS, records accuracy and key-up latency from Chrome's real speech
service, then restores and verifies the original input and output. CI uses the
public `samples/jfk.wav` fixture pinned to a whisper.cpp commit and SHA-256.

```sh
ROMA_DEMO_AUDIO_FIXTURE=/absolute/path/to/fixture.wav \
ROMA_DEMO_EXPECTED_TRANSCRIPT="expected fixture words" \
bash scripts/run-real-audio-e2e.sh
```

This lane needs macOS, Google Chrome, BlackHole 2ch, `SwitchAudioSource`, Chrome
microphone permission, and network access to Chrome's speech provider. CI runs it
on a fresh Namespace Mac and uploads the JSON timing receipt, screenshot, trace,
video, and browser logs.
