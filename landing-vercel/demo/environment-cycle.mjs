export function createEnvironmentCycle({
  count,
  intervalMs = 7_000,
  onChange,
  reducedMotion = false,
  schedule = setTimeout,
  cancelSchedule = clearTimeout,
} = {}) {
  if (!Number.isInteger(count) || count < 1) throw new TypeError("Environment count must be positive.");
  if (typeof onChange !== "function") throw new TypeError("An environment change listener is required.");

  let index = 0;
  let timer = 0;
  let running = false;

  const queueNext = () => {
    if (!running || reducedMotion) return;
    timer = schedule(() => {
      timer = 0;
      if (!running) return;
      index = (index + 1) % count;
      onChange(index);
      queueNext();
    }, intervalMs);
  };

  return {
    start() {
      if (running) return;
      running = true;
      onChange(index);
      queueNext();
    },
    stop() {
      running = false;
      if (timer) cancelSchedule(timer);
      timer = 0;
    },
  };
}
