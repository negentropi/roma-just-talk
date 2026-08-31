import assert from "node:assert/strict";
import test from "node:test";

import { createPreviewDictationAdapter } from "./preview-dictation.mjs";

test("the narrated preview applies the same three-second claim window", async () => {
  let now = 0;
  let utterance;
  class FakeUtterance {
    constructor(text) { this.text = text; }
  }
  const browser = {
    SpeechSynthesisUtterance: FakeUtterance,
    performance: { now: () => now },
    setTimeout,
    clearTimeout,
    speechSynthesis: {
      speak(value) { utterance = value; queueMicrotask(() => value.onstart?.()); },
      cancel() {},
    },
  };
  const adapter = createPreviewDictationAdapter(browser, {
    script: "The thought began before Shift and kept going after it.",
  });
  const prepared = await adapter.arm({ lookbackMs: 3_000 });

  now = 400;
  utterance.onboundary({ charIndex: 0, name: "word" });
  now = 800;
  utterance.onboundary({ charIndex: 4, name: "word" });
  now = 1_200;
  const claim = prepared.begin();
  utterance.onboundary({ charIndex: 12, name: "word" });
  now = 1_600;
  utterance.onboundary({ charIndex: 18, name: "word" });

  assert.deepEqual(await claim.finish(), { text: "The thought began before" });
  await prepared.dispose();
});

test("discarding the narrated preview returns no text", async () => {
  let utterance;
  class FakeUtterance { constructor(text) { this.text = text; } }
  const browser = {
    SpeechSynthesisUtterance: FakeUtterance,
    performance: { now: () => 100 },
    setTimeout,
    clearTimeout,
    speechSynthesis: {
      speak(value) { utterance = value; queueMicrotask(() => value.onstart?.()); },
      cancel() {},
    },
  };
  const prepared = await createPreviewDictationAdapter(browser, { script: "One two three." }).arm({ lookbackMs: 3_000 });
  utterance.onboundary({ charIndex: 0, name: "word" });
  const claim = prepared.begin();
  await claim.discard("typing");

  assert.deepEqual(await claim.finish(), { text: "" });
  await prepared.dispose();
});

test("the narrated preview fails instead of hanging when speech never starts", async () => {
  class FakeUtterance { constructor(text) { this.text = text; } }
  const browser = {
    SpeechSynthesisUtterance: FakeUtterance,
    performance: { now: () => 100 },
    setTimeout,
    clearTimeout,
    speechSynthesis: {
      speak() {},
      cancel() {},
    },
  };
  const adapter = createPreviewDictationAdapter(browser, { startTimeoutMs: 5 });

  await assert.rejects(adapter.arm({ lookbackMs: 3_000 }), /could not start/);
});
