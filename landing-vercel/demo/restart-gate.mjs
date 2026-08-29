export function createRestartGate(browser, { timeoutMs = 3_000 } = {}) {
  const waiters = new Set();

  return {
    waitForStart(expectedCycle) {
      return new Promise((resolve, reject) => {
        const waiter = {
          expectedCycle,
          resolve: () => {
            browser.clearTimeout(waiter.timer);
            waiters.delete(waiter);
            resolve();
          },
          reject: (error) => {
            browser.clearTimeout(waiter.timer);
            waiters.delete(waiter);
            reject(error);
          },
          timer: 0,
        };
        waiter.timer = browser.setTimeout(() => {
          waiter.reject(new Error("Browser speech did not restart. Enable the microphone again."));
        }, timeoutMs);
        waiters.add(waiter);
      });
    },

    resolveCycle(cycle) {
      [...waiters]
        .filter((waiter) => waiter.expectedCycle === cycle)
        .forEach((waiter) => waiter.resolve());
    },

    rejectAll(error) {
      [...waiters].forEach((waiter) => waiter.reject(error));
    },
  };
}
