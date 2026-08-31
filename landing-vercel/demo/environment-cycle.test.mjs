import assert from "node:assert/strict";
import test from "node:test";

import { createEnvironmentCycle } from "./environment-cycle.mjs";

test("environments progress in order without waiting for microphone state", () => {
  const scheduled = [];
  const changes = [];
  const cycle = createEnvironmentCycle({
    count: 9,
    intervalMs: 7_000,
    onChange: (index) => changes.push(index),
    schedule: (callback, delay) => { scheduled.push({ callback, delay }); return scheduled.length; },
    cancelSchedule() {},
  });

  cycle.start();
  assert.deepEqual(changes, [0]);
  assert.equal(scheduled[0].delay, 7_000);
  scheduled.shift().callback();
  assert.deepEqual(changes, [0, 1]);
  scheduled.shift().callback();
  assert.deepEqual(changes, [0, 1, 2]);
});

test("reduced motion keeps one recognizable environment", () => {
  let schedules = 0;
  const changes = [];
  const cycle = createEnvironmentCycle({
    count: 9,
    reducedMotion: true,
    onChange: (index) => changes.push(index),
    schedule: () => { schedules += 1; },
  });

  cycle.start();
  assert.deepEqual(changes, [0]);
  assert.equal(schedules, 0);
});
