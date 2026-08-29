export function createPageDisarm({ session, activation, clearPointer = () => {} }) {
  let inFlight = null;

  return function disarmPage() {
    if (inFlight) return inFlight;
    activation.reset();
    clearPointer();
    inFlight = Promise.resolve()
      .then(() => session.disable())
      .finally(() => {
        inFlight = null;
      });
    return inFlight;
  };
}
