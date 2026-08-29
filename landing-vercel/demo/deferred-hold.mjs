export function createDeferredHold({
  delayMs = 180,
  schedule = setTimeout,
  cancelSchedule = clearTimeout,
  onPress,
  onRelease,
  onCancel,
}) {
  let timer = 0;
  let active = false;
  let pendingPayload = null;

  const clearPending = () => {
    if (!timer) return false;
    cancelSchedule(timer);
    timer = 0;
    pendingPayload = null;
    return true;
  };

  return {
    begin(payload, { chorded = false } = {}) {
      if (chorded || timer || active) return false;
      pendingPayload = payload;
      timer = schedule(() => {
        timer = 0;
        const pressPayload = pendingPayload;
        pendingPayload = null;
        active = Boolean(onPress(pressPayload));
      }, delayMs);
      return true;
    },

    chord() {
      if (clearPending()) return "pending-cancelled";
      return active ? "active" : "idle";
    },

    async end() {
      if (clearPending()) return false;
      if (!active) return false;
      active = false;
      await onRelease();
      return true;
    },

    async cancel(reason) {
      clearPending();
      if (!active) return false;
      active = false;
      await onCancel(reason);
      return true;
    },

    reset() {
      const hadIntent = clearPending() || active;
      active = false;
      return hadIntent;
    },

    isActive: () => active,
    isPending: () => Boolean(timer),
  };
}
