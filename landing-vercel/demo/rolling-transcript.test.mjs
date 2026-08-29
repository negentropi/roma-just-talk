import assert from "node:assert/strict";
import test from "node:test";

import { createRollingTranscript } from "./rolling-transcript.mjs";

function finalResult(text) {
  const result = [{ transcript: text }];
  result.isFinal = true;
  return result;
}

test("an active claim keeps speech after the rolling window moves", () => {
  let now = 0;
  const seen = new Set();
  const transcript = createRollingTranscript({ clock: () => now, lookbackMs: 3_000 });
  transcript.ingest([finalResult("lead in")], seen);

  now = 1_000;
  const claim = transcript.beginClaim();
  now = 2_000;
  transcript.ingest([finalResult("lead in"), finalResult("middle")], seen);
  now = 7_000;
  transcript.ingest([
    finalResult("lead in"),
    finalResult("middle"),
    finalResult("ending"),
  ], seen);

  assert.equal(transcript.textFor(claim), "lead in middle ending");
});
