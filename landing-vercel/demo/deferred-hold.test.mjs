import assert from "node:assert/strict";
import test from "node:test";

import { createDeferredHold } from "./deferred-hold.mjs";

test("ordinary capitalization cancels before browser capture starts", async () => {
  let scheduled;
  let presses = 0;
  let releases = 0;
  const hold = createDeferredHold({
    schedule: (callback) => { scheduled = callback; return 1; },
    cancelSchedule: () => { scheduled = null; },
    onPress: () => { presses += 1; return true; },
    onRelease: async () => { releases += 1; },
    onCancel: async () => {},
  });

  hold.begin({ contextId: "messages" });
  assert.equal(hold.chord(), "pending-cancelled");
  await hold.end();

  assert.equal(scheduled, null);
  assert.equal(presses, 0);
  assert.equal(releases, 0);
});

test("a key held before Left Shift blocks browser capture", () => {
  const scheduled = [];
  let presses = 0;
  const hold = createDeferredHold({
    schedule: (callback) => scheduled.push(callback),
    cancelSchedule: () => {},
    onPress: () => { presses += 1; },
    onRelease: () => {},
    onCancel: () => {},
  });

  assert.equal(hold.begin({}, { chorded: true }), false);
  assert.equal(scheduled.length, 0);
  assert.equal(presses, 0);
});

test("holding Left Shift past the intent delay starts and releases capture", async () => {
  let scheduled;
  const events = [];
  const hold = createDeferredHold({
    schedule: (callback) => { scheduled = callback; return 1; },
    cancelSchedule: () => { scheduled = null; },
    onPress: (payload) => { events.push(["press", payload.contextId]); return true; },
    onRelease: async () => { events.push(["release"]); },
    onCancel: async () => {},
  });

  hold.begin({ contextId: "email" });
  scheduled();
  await hold.end();

  assert.deepEqual(events, [["press", "email"], ["release"]]);
});

test("page disarm resets an active hold without releasing it", async () => {
  let scheduled;
  let releases = 0;
  const hold = createDeferredHold({
    schedule: (callback) => { scheduled = callback; return 1; },
    cancelSchedule: () => {},
    onPress: () => true,
    onRelease: async () => { releases += 1; },
    onCancel: async () => {},
  });

  hold.begin();
  scheduled();
  assert.equal(hold.reset(), true);
  assert.equal(await hold.end(), false);
  assert.equal(releases, 0);
});
