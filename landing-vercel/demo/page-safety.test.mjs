import assert from "node:assert/strict";
import test from "node:test";

import { createPageDisarm } from "./page-safety.mjs";

test("hiding the page resets holds and disables browser speech once", async () => {
  const events = [];
  let finishDisable;
  const disarmPage = createPageDisarm({
    activation: { reset: () => events.push("reset hold") },
    clearPointer: () => events.push("reset pointer"),
    session: {
      disable: () => {
        events.push("disable speech");
        return new Promise((resolve) => { finishDisable = resolve; });
      },
    },
  });

  const first = disarmPage();
  const duplicate = disarmPage();
  await Promise.resolve();
  assert.equal(first, duplicate);
  assert.deepEqual(events, ["reset hold", "reset pointer", "disable speech"]);
  finishDisable();
  await first;
});
