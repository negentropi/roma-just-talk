import assert from "node:assert/strict";
import test from "node:test";

import { joinTranscriptParts } from "./transcript.mjs";

test("transcript joining drops repeated adjacent results", () => {
  assert.equal(joinTranscriptParts(["hello world", "world", "again"]), "hello world again");
  assert.equal(joinTranscriptParts(["hello", "hello"]), "hello");
  assert.equal(joinTranscriptParts(["hello", "hello world"]), "hello world");
  assert.equal(joinTranscriptParts(["hello, world", "world again"]), "hello, world again");
  assert.equal(joinTranscriptParts(["你好", "你好世界"]), "你好世界");
  assert.equal(joinTranscriptParts(["a", "and then"]), "a and then");
});
