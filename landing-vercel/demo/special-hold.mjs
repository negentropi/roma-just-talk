export function createSpecialHold({ onPress, onRelease, onCancel }) {
  let active = false;

  return {
    begin(payload, { chorded = false } = {}) {
      if (chorded || active) return false;
      active = Boolean(onPress(payload));
      return active;
    },
    async end() {
      if (!active) return false;
      active = false;
      await onRelease();
      return true;
    },
    async cancel(reason) {
      if (!active) return false;
      active = false;
      await onCancel(reason);
      return true;
    },
    reset() {
      const wasActive = active;
      active = false;
      return wasActive;
    },
    isActive: () => active,
  };
}
