function wordAt(text, charIndex) {
  return text.slice(charIndex).match(/^[\p{L}\p{N}']+/u)?.[0] || "";
}

export function createPreviewDictationAdapter(browser = globalThis, {
  script = "I was thinking we could move the review to Thursday because the latest build should be ready by then.",
  replayDelayMs = 1_000,
  startTimeoutMs = 2_000,
} = {}) {
  return {
    isSupported: () => Boolean(browser.speechSynthesis && browser.SpeechSynthesisUtterance),

    async arm({ lookbackMs = 3_000, onFatal = () => {}, signal } = {}) {
      if (!browser.speechSynthesis || !browser.SpeechSynthesisUtterance) {
        throw new Error("The narrated preview is unavailable in this browser.");
      }

      let active = true;
      let activeClaim = null;
      let utterance = null;
      let replayTimer = 0;
      let startTimer = 0;
      let started = false;
      let startResolve;
      let startReject;
      const recentWords = [];
      const startPromise = new Promise((resolve, reject) => {
        startResolve = resolve;
        startReject = reject;
      });
      const clock = () => browser.performance?.now?.() ?? Date.now();

      const trimWords = (now) => {
        const cutoff = now - lookbackMs;
        while (recentWords.length && recentWords[0].at < cutoff) recentWords.shift();
      };

      const hearWord = (word) => {
        if (!active || !word) return;
        const entry = { at: clock(), word };
        recentWords.push(entry);
        trimWords(entry.at);
        activeClaim?.words.push(entry);
      };

      const speak = () => {
        if (!active) return;
        let lastCharIndex = -1;
        utterance = new browser.SpeechSynthesisUtterance(script);
        utterance.rate = 0.94;
        utterance.pitch = 1;
        utterance.onstart = () => {
          if (!started) {
            started = true;
            browser.clearTimeout(startTimer);
            startResolve();
          }
        };
        utterance.onboundary = (event) => {
          if (event.charIndex === lastCharIndex) return;
          lastCharIndex = event.charIndex;
          hearWord(wordAt(script, event.charIndex));
        };
        utterance.onend = () => {
          if (active) replayTimer = browser.setTimeout(speak, replayDelayMs);
        };
        utterance.onerror = (event) => {
          if (active && event?.error !== "canceled") onFatal(new Error("The narrated preview stopped."));
        };
        browser.speechSynthesis.speak(utterance);
      };

      const onAbort = () => {
        active = false;
        browser.clearTimeout(replayTimer);
        browser.clearTimeout(startTimer);
        browser.speechSynthesis.cancel();
        if (!started) startReject(new Error("The narrated preview was cancelled."));
      };
      signal?.addEventListener("abort", onAbort, { once: true });
      speak();
      startTimer = browser.setTimeout(() => {
        if (started || !active) return;
        active = false;
        browser.speechSynthesis.cancel();
        startReject(new Error("The narrated preview could not start."));
      }, startTimeoutMs);
      try {
        await startPromise;
      } catch (error) {
        signal?.removeEventListener("abort", onAbort);
        throw error;
      }

      return {
        capabilityLabel: "narrated preview",

        begin() {
          if (!active) throw new Error("The narrated preview is not active.");
          if (activeClaim) throw new Error("A preview attempt is already active.");
          const now = clock();
          trimWords(now);
          const claim = { closed: false, discarded: false, words: [...recentWords] };
          activeClaim = claim;

          const close = () => {
            if (claim.closed) return false;
            claim.closed = true;
            if (activeClaim === claim) activeClaim = null;
            return true;
          };

          return {
            async finish() {
              if (!close() || claim.discarded) return { text: "" };
              return { text: claim.words.map(({ word }) => word).join(" ") };
            },
            async discard() {
              claim.discarded = true;
              close();
            },
          };
        },

        async dispose() {
          if (!active) return;
          active = false;
          activeClaim = null;
          browser.clearTimeout(replayTimer);
          browser.clearTimeout(startTimer);
          browser.speechSynthesis.cancel();
          signal?.removeEventListener("abort", onAbort);
        },
      };
    },
  };
}
