import assert from "node:assert/strict";
import test from "node:test";

import { createSpecialHold } from "./special-hold.mjs";

test("Left Shift begins capture immediately and releases the same claim", async () => {
  const events = [];
  const hold = createSpecialHold({
    onPress: () => { events.push("press"); return true; },
    onRelease: async () => { events.push("release"); },
    onCancel: async () => { events.push("cancel"); },
  });

  assert.equal(hold.begin(), true);
  assert.deepEqual(events, ["press"]);
  await hold.end();
  assert.deepEqual(events, ["press", "release"]);
});

test("a key already held blocks Special mode", () => {
  let presses = 0;
  const hold = createSpecialHold({
    onPress: () => { presses += 1; return true; },
    onRelease() {},
    onCancel() {},
  });

  assert.equal(hold.begin({}, { chorded: true }), false);
  assert.equal(presses, 0);
});

test("lost focus cancels an active Special hold", async () => {
  const events = [];
  const hold = createSpecialHold({
    onPress: () => true,
    onRelease: async () => events.push("release"),
    onCancel: async (reason) => events.push(reason),
  });

  hold.begin();
  await hold.cancel("lost-focus");
  assert.equal(await hold.end(), false);
  assert.deepEqual(events, ["lost-focus"]);
});
