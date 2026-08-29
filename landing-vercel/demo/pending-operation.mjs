export function operationAbortError() {
  const error = new Error("Browser speech startup was cancelled.");
  error.name = "AbortError";
  return error;
}

export function waitForOperation(operation, {
  browser,
  signal,
  timeoutMs,
  timeoutMessage,
}) {
  if (signal?.aborted) return Promise.reject(operationAbortError());

  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      browser.clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      callback(value);
    };
    const onAbort = () => finish(reject, operationAbortError());
    const timer = browser.setTimeout(() => {
      finish(reject, new Error(timeoutMessage));
    }, timeoutMs);
    signal?.addEventListener("abort", onAbort, { once: true });
    Promise.resolve(operation).then(
      (value) => finish(resolve, value),
      (error) => finish(reject, error),
    );
  });
}
