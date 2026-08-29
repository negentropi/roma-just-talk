import { DEMO_CONTRACT } from "./demo-contract.mjs";
import { DEMO_COPY as COPY } from "./demo-copy.mjs";

function freezeSnapshot(value) {
  return Object.freeze({ ...value });
}

export function createDemoSession({
  dictation,
  clock = () => performance.now(),
  contract = DEMO_CONTRACT,
  onCommit = () => {},
} = {}) {
  if (!dictation || typeof dictation.isSupported !== "function") {
    throw new TypeError("A dictation adapter is required.");
  }

  const subscribers = new Set();
  let prepared = null;
  let activeAttempt = null;
  let pendingArmController = null;
  let generation = 0;
  let lastPressAt = Number.NEGATIVE_INFINITY;
  let disposed = false;
  let snapshot = freezeSnapshot({
    phase: dictation.isSupported() ? "idle" : "unsupported",
    message: dictation.isSupported() ? COPY.idle : COPY.unsupported,
    capability: "not armed",
    interim: "",
    isUnsafe: false,
    isArmed: false,
    canPress: false,
  });

  const publish = (patch) => {
    if (disposed) return;
    snapshot = freezeSnapshot({ ...snapshot, ...patch });
    subscribers.forEach((subscriber) => subscriber(snapshot));
  };

  const resetReady = (message = COPY.ready) => {
    publish({
      phase: "ready",
      message,
      interim: "",
      isUnsafe: false,
      isArmed: true,
      canPress: true,
    });
  };

  const fail = async (error, expectedGeneration = generation) => {
    if (disposed || expectedGeneration !== generation) return;
    const ownedPrepared = prepared;
    const ownedAttempt = activeAttempt;
    pendingArmController?.abort();
    pendingArmController = null;
    prepared = null;
    activeAttempt = null;
    generation += 1;
    await ownedAttempt?.claim?.discard("speech-error");
    await ownedPrepared?.dispose?.();
    publish({
      phase: "error",
      message: error?.message || "Speech recognition stopped. Try enabling it again.",
      capability: "not armed",
      interim: "",
      isUnsafe: false,
      isArmed: false,
      canPress: false,
    });
  };

  const enable = async ({ language = "en-US" } = {}) => {
    if (disposed || prepared || snapshot.phase === "preparing") return false;
    if (!dictation.isSupported()) {
      publish({ phase: "unsupported", message: COPY.unsupported });
      return false;
    }

    const enableGeneration = ++generation;
    const armController = new AbortController();
    pendingArmController = armController;
    publish({
      phase: "preparing",
      message: COPY.preparing,
      capability: "checking browser",
      interim: "",
      isUnsafe: false,
      isArmed: false,
      canPress: false,
    });

    try {
      const nextPrepared = await dictation.arm({
        language,
        lookbackMs: contract.preRollMs,
        onFatal: (error) => void fail(error, enableGeneration),
        signal: armController.signal,
      });
      if (disposed || enableGeneration !== generation) {
        await nextPrepared.dispose?.();
        return false;
      }
      prepared = nextPrepared;
      publish({ capability: nextPrepared.capabilityLabel || "browser-managed speech" });
      resetReady();
      return true;
    } catch (error) {
      if (enableGeneration !== generation || disposed) return false;
      publish({
        phase: "error",
        message: error?.message || "The browser could not start speech recognition.",
        capability: "not armed",
        isArmed: false,
        canPress: false,
      });
      return false;
    } finally {
      if (pendingArmController === armController) pendingArmController = null;
    }
  };

  const press = ({ source = "left-shift", contextId = "messages" } = {}) => {
    if (disposed || !prepared || activeAttempt || snapshot.phase !== "ready") return false;
    const now = clock();
    if (now - lastPressAt < contract.pressCooldownMs) return false;
    lastPressAt = now;

    const attemptGeneration = generation;
    const attempt = {
      claim: null,
      contextId,
      source,
      unsafe: false,
      generation: attemptGeneration,
    };
    activeAttempt = attempt;
    try {
      attempt.claim = prepared.begin({
        onInterim: (text) => {
          if (activeAttempt !== attempt || attemptGeneration !== generation) return;
          publish({ interim: text });
        },
      });
    } catch (error) {
      activeAttempt = null;
      void fail(error, attemptGeneration);
      return false;
    }
    publish({
      phase: "capturing",
      message: COPY.capturing,
      isUnsafe: false,
      canPress: false,
    });
    return true;
  };

  const invalidate = async ({ reason = "lost-evidence", immediate = false } = {}) => {
    const attempt = activeAttempt;
    if (!attempt) return false;
    attempt.unsafe = true;
    publish({ isUnsafe: true, message: COPY.unsafe });
    if (!immediate) return true;

    activeAttempt = null;
    try {
      await attempt.claim.discard(reason);
      if (disposed || attempt.generation !== generation) return true;
      resetReady(COPY.discarded);
    } catch (error) {
      await fail(error, attempt.generation);
    }
    return true;
  };

  const release = async ({ source = "left-shift" } = {}) => {
    const attempt = activeAttempt;
    if (!attempt || attempt.source !== source) return false;
    activeAttempt = null;

    if (attempt.unsafe) {
      try {
        await attempt.claim.discard("unsafe-key-evidence");
        if (!disposed && attempt.generation === generation) resetReady(COPY.discarded);
      } catch (error) {
        await fail(error, attempt.generation);
      }
      return true;
    }

    publish({
      phase: "finalizing",
      message: COPY.finalizing,
      interim: "",
      canPress: false,
    });

    try {
      const result = await attempt.claim.finish();
      if (disposed || attempt.generation !== generation) return true;
      const text = String(result?.text || "").trim();
      if (text) onCommit({ text, contextId: attempt.contextId });
      resetReady(text ? COPY.ready : COPY.empty);
    } catch (error) {
      await fail(error, attempt.generation);
    }
    return true;
  };

  const disable = async () => {
    if (disposed) return;
    pendingArmController?.abort();
    pendingArmController = null;
    generation += 1;
    const ownedAttempt = activeAttempt;
    const ownedPrepared = prepared;
    activeAttempt = null;
    prepared = null;
    await ownedAttempt?.claim?.discard("disabled");
    await ownedPrepared?.dispose?.();
    publish({
      phase: dictation.isSupported() ? "idle" : "unsupported",
      message: dictation.isSupported() ? COPY.idle : COPY.unsupported,
      capability: "not armed",
      interim: "",
      isUnsafe: false,
      isArmed: false,
      canPress: false,
    });
  };

  const dispose = async () => {
    if (disposed) return;
    pendingArmController?.abort();
    pendingArmController = null;
    const ownedAttempt = activeAttempt;
    const ownedPrepared = prepared;
    activeAttempt = null;
    prepared = null;
    disposed = true;
    generation += 1;
    subscribers.clear();
    await ownedAttempt?.claim?.discard("disposed");
    await ownedPrepared?.dispose?.();
  };

  const subscribe = (subscriber) => {
    if (typeof subscriber !== "function") throw new TypeError("Subscriber must be a function.");
    subscriber(snapshot);
    subscribers.add(subscriber);
    return () => subscribers.delete(subscriber);
  };

  return {
    enable,
    press,
    release,
    invalidate,
    disable,
    dispose,
    subscribe,
    getSnapshot: () => snapshot,
  };
}
