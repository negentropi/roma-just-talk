import assert from "node:assert/strict";
import test from "node:test";

import { createBrowserSpeechAdapter } from "./browser-speech.mjs";
import { createDemoSession } from "./demo-session.mjs";

test("browser adapter carries recent rolling speech into a clean claim", async () => {
  let now = 0;
  const instances = [];
  class FakeRecognition {
    static async available() {
      return "unavailable";
    }

    constructor() {
      instances.push(this);
    }

    start() {
      queueMicrotask(() => this.onstart?.());
    }

    stop() {
      queueMicrotask(() => this.onend?.());
    }

    abort() {
      queueMicrotask(() => this.onend?.());
    }

    result(values) {
      const results = values.map(({ text, final }) => {
        const result = [{ transcript: text }];
        result.isFinal = final;
        return result;
      });
      this.onresult?.({ results });
    }
  }
  const browser = {
    SpeechRecognition: FakeRecognition,
    isSecureContext: true,
    setTimeout,
    clearTimeout,
  };
  const prepared = await createBrowserSpeechAdapter(browser, { clock: () => now }).arm({
    language: "en-US",
    lookbackMs: 3_000,
  });
  const recognition = instances[0];
  now = 500;
  recognition.result([{ text: "too old", final: true }]);
  now = 3_500;
  recognition.result([
    { text: "too old", final: true },
    { text: "start talking", final: true },
  ]);
  now = 5_000;
  const claim = prepared.begin();
  recognition.result([
    { text: "too old", final: true },
    { text: "start talking", final: true },
    { text: "then hold shift", final: true },
  ]);

  assert.deepEqual(await claim.finish(), { text: "start talking then hold shift" });
  assert.equal(prepared.capabilityLabel, "browser-managed speech");
  await prepared.dispose();
});

test("browser adapter drops stale unfinished speech from the rolling preview", async () => {
  let now = 0;
  const instances = [];
  class FakeRecognition {
    constructor() {
      instances.push(this);
    }

    start() {
      queueMicrotask(() => this.onstart?.());
    }

    stop() {
      queueMicrotask(() => this.onend?.());
    }

    abort() {
      queueMicrotask(() => this.onend?.());
    }

    result(text) {
      const result = [{ transcript: text }];
      result.isFinal = false;
      this.onresult?.({ results: [result] });
    }
  }
  const prepared = await createBrowserSpeechAdapter({
    SpeechRecognition: FakeRecognition,
    isSecureContext: true,
    setTimeout,
    clearTimeout,
  }, { clock: () => now }).arm({ language: "en-US", lookbackMs: 3_000 });

  instances[0].result("an old unfinished thought");
  now = 3_001;
  const claim = prepared.begin();

  assert.deepEqual(await claim.finish(), { text: "" });
  await prepared.dispose();
});

test("discard fences late results from the aborted recognizer", async () => {
  const instances = [];
  class LateAbortRecognition {
    constructor() {
      instances.push(this);
    }

    start() {
      queueMicrotask(() => this.onstart?.());
    }

    abort() {
      this.finishAbort = () => queueMicrotask(() => this.onend?.());
    }

    result(text) {
      const result = [{ transcript: text }];
      result.isFinal = true;
      this.onresult?.({ results: [result] });
    }
  }
  const prepared = await createBrowserSpeechAdapter({
    SpeechRecognition: LateAbortRecognition,
    isSecureContext: true,
    setTimeout,
    clearTimeout,
  }).arm({ language: "en-US", lookbackMs: 3_000 });

  const firstClaim = prepared.begin();
  const discarded = firstClaim.discard("lost-focus");
  instances[0].result("late before end");
  instances[0].finishAbort();
  await discarded;
  instances[0].result("late after replacement");

  const interim = [];
  const nextClaim = prepared.begin({ onInterim: (text) => interim.push(text) });
  assert.deepEqual(interim, [""]);
  await nextClaim.discard("disabled");
  await prepared.dispose();
});

test("discard stays non-ready until the aborted recognizer restarts", async () => {
  const instances = [];
  let now = 10_000;
  class DelayedAbortRecognition {
    constructor() {
      instances.push(this);
    }

    start() {
      queueMicrotask(() => this.onstart?.());
    }

    stop() {
      queueMicrotask(() => this.onend?.());
    }

    abort() {
      this.finishAbort = () => queueMicrotask(() => this.onend?.());
    }
  }
  const browser = {
    SpeechRecognition: DelayedAbortRecognition,
    isSecureContext: true,
    setTimeout,
    clearTimeout,
  };
  const adapter = createBrowserSpeechAdapter(browser);
  const session = createDemoSession({ dictation: adapter, clock: () => now });

  await session.enable();
  assert.equal(session.press(), true);
  const discard = session.invalidate({ reason: "lost-focus", immediate: true });
  assert.notEqual(session.getSnapshot().phase, "ready");
  assert.equal(session.press(), false);
  instances[0].onstart?.();
  await Promise.resolve();
  assert.notEqual(session.getSnapshot().phase, "ready");
  instances[0].finishAbort();
  await discard;

  assert.equal(instances.length, 2);
  assert.equal(session.getSnapshot().phase, "ready");
  now += 80;
  assert.equal(session.press(), true);
  await session.disable();
  instances[1].finishAbort();
});

test("disabling during browser speech startup aborts the unowned recognizer", async () => {
  const instances = [];
  class PendingRecognition {
    constructor() {
      instances.push(this);
      this.aborts = 0;
    }

    start() {}

    abort() {
      this.aborts += 1;
    }
  }
  const adapter = createBrowserSpeechAdapter({
    SpeechRecognition: PendingRecognition,
    isSecureContext: true,
    setTimeout,
    clearTimeout,
  }, { startTimeoutMs: 5_000 });
  const session = createDemoSession({ dictation: adapter });

  const enabling = session.enable();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(instances.length, 1);
  await session.disable();

  assert.equal(await enabling, false);
  assert.equal(instances[0].aborts, 1);
  assert.equal(session.getSnapshot().phase, "idle");
});

test("browser speech startup has a deadline", async () => {
  let aborts = 0;
  class PendingRecognition {
    start() {}
    abort() { aborts += 1; }
  }
  const adapter = createBrowserSpeechAdapter({
    SpeechRecognition: PendingRecognition,
    isSecureContext: true,
    setTimeout,
    clearTimeout,
  }, { startTimeoutMs: 5 });

  await assert.rejects(
    adapter.arm({ language: "en-US", lookbackMs: 3_000 }),
    /did not start/,
  );
  assert.equal(aborts, 1);
});
