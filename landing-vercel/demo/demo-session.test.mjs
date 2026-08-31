import assert from "node:assert/strict";
import test from "node:test";

import { createDemoSession } from "./demo-session.mjs";

function fakeDictation({ supported = true, result = "caught thought" } = {}) {
  const state = {
    arms: 0,
    begins: 0,
    finishes: 0,
    discards: [],
    disposes: 0,
  };
  const adapter = {
    isSupported: () => supported,
    async arm(options) {
      state.arms += 1;
      state.armOptions = options;
      return {
        capabilityLabel: "fake speech",
        begin({ onInterim }) {
          state.begins += 1;
          onInterim("live words");
          return {
            async finish() {
              state.finishes += 1;
              return { text: result };
            },
            async discard(reason) {
              state.discards.push(reason);
            },
          };
        },
        async dispose() {
          state.disposes += 1;
        },
      };
    },
  };
  return { adapter, state };
}

test("clean Left Shift release commits once to the owned context", async () => {
  const { adapter, state } = fakeDictation();
  const commits = [];
  let now = 1_000;
  const session = createDemoSession({
    dictation: adapter,
    clock: () => now,
    onCommit: (commit) => commits.push(commit),
  });

  await session.enable({ language: "en-US" });
  assert.equal(session.press({ source: "left-shift", contextId: "email" }), true);
  assert.equal(session.getSnapshot().interim, "live words");
  now += 400;
  await session.release({ source: "left-shift" });

  assert.deepEqual(commits, [{ text: "caught thought", contextId: "email" }]);
  assert.equal(state.finishes, 1);
  assert.equal(session.getSnapshot().phase, "ready");
});

test("another key makes Special mode fail closed", async () => {
  const { adapter, state } = fakeDictation();
  const commits = [];
  const session = createDemoSession({ dictation: adapter, clock: () => 2_000, onCommit: (value) => commits.push(value) });

  await session.enable();
  session.press({ source: "left-shift", contextId: "coding" });
  await session.invalidate({ reason: "other-key-down" });
  await session.release({ source: "left-shift" });

  assert.deepEqual(commits, []);
  assert.deepEqual(state.discards, ["unsafe-key-evidence"]);
  assert.equal(session.getSnapshot().phase, "ready");
});

test("lost focus discards immediately and leaves no releasable attempt", async () => {
  const { adapter, state } = fakeDictation();
  const session = createDemoSession({ dictation: adapter, clock: () => 4_000 });

  await session.enable();
  session.press({ source: "left-shift", contextId: "messages" });
  await session.invalidate({ reason: "lost-focus", immediate: true });

  assert.deepEqual(state.discards, ["lost-focus"]);
  assert.equal(await session.release({ source: "left-shift" }), false);
  assert.equal(session.getSnapshot().phase, "ready");
});

test("the native 80 ms cooldown blocks a duplicate press", async () => {
  const { adapter, state } = fakeDictation();
  let now = 10_000;
  const session = createDemoSession({ dictation: adapter, clock: () => now });

  await session.enable();
  session.press();
  await session.invalidate({ immediate: true });
  now += 40;
  assert.equal(session.press(), false);
  now += 40;
  assert.equal(session.press(), true);
  assert.equal(state.begins, 2);
});

test("unsupported browsers never pretend the demo is live", async () => {
  const { adapter, state } = fakeDictation({ supported: false });
  const session = createDemoSession({ dictation: adapter });

  assert.equal(session.getSnapshot().phase, "unsupported");
  assert.equal(await session.enable(), false);
  assert.equal(state.arms, 0);
});

test("microphone denial becomes a recoverable permission state", async () => {
  const error = new DOMException("Permission denied", "NotAllowedError");
  const adapter = {
    isSupported: () => true,
    async arm() { throw error; },
  };
  const session = createDemoSession({ dictation: adapter });

  assert.equal(await session.enable({ mode: "microphone" }), false);
  assert.equal(session.getSnapshot().phase, "permission-denied");
  assert.equal(session.getSnapshot().canPress, false);
});

test("an unsupported primary adapter exposes the see-only recovery path", async () => {
  const adapter = {
    isSupported: () => true,
    async arm() { throw new DOMException("Unsupported", "NotSupportedError"); },
  };
  const session = createDemoSession({ dictation: adapter });

  assert.equal(await session.enable({ mode: "microphone" }), false);
  assert.equal(session.getSnapshot().phase, "unsupported");
});

test("arming forwards the selected mode and browser-owned stream", async () => {
  const { adapter, state } = fakeDictation();
  const stream = { id: "browser-owned-stream" };
  const session = createDemoSession({ dictation: adapter });

  await session.enable({ language: "fr-FR", mode: "microphone", stream });

  assert.equal(state.armOptions.language, "fr-FR");
  assert.equal(state.armOptions.mode, "microphone");
  assert.equal(state.armOptions.stream, stream);
});

test("a fatal recognizer error discards the owned attempt", async () => {
  const { adapter, state } = fakeDictation();
  const session = createDemoSession({ dictation: adapter, clock: () => 8_000 });

  await session.enable();
  session.press();
  state.armOptions.onFatal(new Error("speech service stopped"));
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(session.getSnapshot().phase, "error");
  assert.equal(session.getSnapshot().message, "speech service stopped");
  assert.deepEqual(state.discards, ["speech-error"]);
  assert.equal(state.disposes, 1);
});

test("a final result cannot commit after the session is disabled", async () => {
  let resolveFinish;
  const commits = [];
  const adapter = {
    isSupported: () => true,
    async arm() {
      return {
        begin() {
          return {
            finish: () => new Promise((resolve) => { resolveFinish = resolve; }),
            async discard() {},
          };
        },
        async dispose() {},
      };
    },
  };
  const session = createDemoSession({ dictation: adapter, onCommit: (value) => commits.push(value) });

  await session.enable();
  session.press();
  const release = session.release();
  await session.disable();
  resolveFinish({ text: "late result" });
  await release;

  assert.deepEqual(commits, []);
  assert.equal(session.getSnapshot().phase, "idle");
});

test("a transient transcription failure keeps the warmed microphone ready", async () => {
  let begins = 0;
  const adapter = {
    isSupported: () => true,
    async arm() {
      return {
        begin() {
          begins += 1;
          return {
            async finish() { throw new Error("Demo transcription is busy. Try once more."); },
            async discard() {},
          };
        },
        async dispose() {},
      };
    },
  };
  let now = 1_000;
  const session = createDemoSession({ dictation: adapter, clock: () => now });

  await session.enable();
  session.press();
  await session.release();
  assert.equal(session.getSnapshot().phase, "ready");
  assert.equal(session.getSnapshot().message, "Demo transcription is busy. Try once more.");
  now += 80;
  assert.equal(session.press(), true);
  assert.equal(begins, 2);
});

test("disabling an active session discards its claim and browser speech", async () => {
  const { adapter, state } = fakeDictation();
  const session = createDemoSession({ dictation: adapter, clock: () => 9_000 });

  await session.enable();
  session.press();
  await session.disable();

  assert.deepEqual(state.discards, ["disabled"]);
  assert.equal(state.disposes, 1);
  assert.equal(session.getSnapshot().phase, "idle");
});
