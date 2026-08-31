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
