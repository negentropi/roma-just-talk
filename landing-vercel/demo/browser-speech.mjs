import { createRestartGate } from "./restart-gate.mjs";
import { createRollingTranscript } from "./rolling-transcript.mjs";
import { waitForOperation } from "./pending-operation.mjs";
import { canUseInstalledLocalPack, speechError } from "./speech-capability.mjs";

export function createBrowserSpeechAdapter(browser = globalThis, {
  clock = () => Date.now(),
  startTimeoutMs = 8_000,
} = {}) {
  const Recognition = browser.SpeechRecognition || browser.webkitSpeechRecognition;
  const secureEnough = browser.isSecureContext !== false;

  return {
    isSupported: () => Boolean(Recognition && secureEnough),

    async arm({ language, lookbackMs, onFatal, signal }) {
      if (!Recognition) throw new Error("This browser does not expose live speech recognition.");
      if (!secureEnough) throw new Error("Live speech needs a secure HTTPS page.");

      const useLocalPack = await canUseInstalledLocalPack(Recognition, language, { browser, signal });
      const capabilityLabel = useLocalPack
        ? "on-device browser speech"
        : "browser-managed speech";
      let active = true;
      let recognition = null;
      let recognitionStarted = false;
      let recognitionAcceptingResults = false;
      let recognitionCycle = 0;
      let restartTimer = 0;
      let currentClaim = null;
      let finishTimer = 0;
      let firstStartResolve;
      let firstStartReject;
      let firstStartPending = true;
      const restartGate = createRestartGate(browser);
      const transcript = createRollingTranscript({ clock, lookbackMs });

      const firstStart = new Promise((resolve, reject) => {
        firstStartResolve = resolve;
        firstStartReject = reject;
      });

      const emitInterim = () => {
        if (!currentClaim) return;
        currentClaim.onInterim(transcript.textFor(currentClaim.transcriptClaim));
      };

      const scheduleRestart = () => {
        if (!active || restartTimer) return;
        restartTimer = browser.setTimeout(() => {
          restartTimer = 0;
          if (active) startCycle();
        }, 80);
      };

      const settleFinish = () => {
        const claim = currentClaim;
        if (!claim || claim.state !== "finishing") return;
        browser.clearTimeout(finishTimer);
        finishTimer = 0;
        currentClaim = null;
        const text = transcript.textFor(claim.transcriptClaim);
        transcript.clear();
        claim.state = "restarting";
        const restarted = restartGate.waitForStart(recognitionCycle + 1);
        recognitionAcceptingResults = false;
        if (recognition && recognitionStarted) {
          try {
            recognition.abort();
          } catch (_error) {
            // The recognizer already ended.
          }
        }
        scheduleRestart();
        restarted.then(() => {
          claim.state = "finished";
          claim.resolve({ text });
        }, claim.reject);
      };

      const reportFatal = (errorLike) => {
        if (!active) return;
        const error = speechError(errorLike);
        active = false;
        recognitionAcceptingResults = false;
        browser.clearTimeout(restartTimer);
        browser.clearTimeout(finishTimer);
        restartGate.rejectAll(error);
        if (currentClaim?.state === "finishing") {
          currentClaim.state = "finished";
          currentClaim.reject(error);
          currentClaim = null;
        }
        if (firstStartPending) {
          firstStartPending = false;
          firstStartReject(error);
        } else {
          onFatal?.(error);
        }
        try {
          recognition?.abort();
        } catch (_error) {
          // The recognizer already ended.
        }
      };

      const startCycle = () => {
        if (!active || recognition) return;
        const cycle = recognitionCycle + 1;
        recognitionCycle = cycle;
        let nextRecognition;
        try {
          nextRecognition = new Recognition();
        } catch (error) {
          reportFatal(error);
          return;
        }
        recognition = nextRecognition;
        recognitionStarted = false;
        recognitionAcceptingResults = true;
        let finalResultIndexes = new Set();

        nextRecognition.lang = language;
        nextRecognition.continuous = true;
        nextRecognition.interimResults = true;
        nextRecognition.maxAlternatives = 1;
        if (useLocalPack && "processLocally" in nextRecognition) {
          nextRecognition.processLocally = true;
        }

        nextRecognition.onstart = () => {
          if (recognition !== nextRecognition) return;
          recognitionStarted = true;
          if (firstStartPending) {
            firstStartPending = false;
            firstStartResolve();
          }
          restartGate.resolveCycle(cycle);
        };

        nextRecognition.onresult = (event) => {
          if (!active || !recognitionAcceptingResults || recognition !== nextRecognition) return;
          transcript.ingest(event.results, finalResultIndexes);
          emitInterim();
        };

        nextRecognition.onerror = (event) => {
          const code = event?.error;
          if (!active || recognition !== nextRecognition || code === "aborted" || code === "no-speech") return;
          reportFatal(event);
        };

        nextRecognition.onend = () => {
          if (recognition !== nextRecognition) return;
          recognition = null;
          recognitionStarted = false;
          recognitionAcceptingResults = false;
          if (!active) return;
          if (currentClaim?.state === "finishing") settleFinish();
          else scheduleRestart();
        };

        try {
          nextRecognition.start();
        } catch (error) {
          recognition = null;
          reportFatal(error);
        }
      };

      try {
        startCycle();
        await waitForOperation(firstStart, {
          browser,
          signal,
          timeoutMs: startTimeoutMs,
          timeoutMessage: "Browser speech did not start. Try enabling the microphone again.",
        });
      } catch (error) {
        active = false;
        firstStartPending = false;
        recognitionAcceptingResults = false;
        browser.clearTimeout(restartTimer);
        restartGate.rejectAll(error);
        try {
          recognition?.abort();
        } catch (_abortError) {
          // The recognizer never started.
        }
        recognition = null;
        throw error;
      }

      return {
        capabilityLabel,

        begin({ onInterim = () => {} } = {}) {
          if (!active) throw new Error("Speech recognition is not armed.");
          if (currentClaim) throw new Error("A speech attempt is already active.");
          const claim = {
            transcriptClaim: transcript.beginClaim(),
            onInterim,
            state: "capturing",
            resolve: null,
            reject: null,
          };
          currentClaim = claim;
          emitInterim();

          return {
            finish() {
              if (["finished", "restarting"].includes(claim.state)) return claim.promise;
              if (claim.state !== "capturing") return Promise.resolve({ text: "" });
              claim.state = "finishing";
              claim.promise = new Promise((resolve, reject) => {
                claim.resolve = resolve;
                claim.reject = reject;
              });
              finishTimer = browser.setTimeout(settleFinish, 2_500);
              try {
                if (recognition && recognitionStarted) recognition.stop();
                else browser.setTimeout(settleFinish, 120);
              } catch (_error) {
                browser.setTimeout(settleFinish, 0);
              }
              return claim.promise;
            },

            async discard(reason = "discarded") {
              if (claim.state === "discarded" || claim.state === "finished") return;
              claim.state = "discarded";
              if (currentClaim === claim) currentClaim = null;
              browser.clearTimeout(finishTimer);
              finishTimer = 0;
              transcript.clear();
              recognitionAcceptingResults = false;
              claim.resolve?.({ text: "" });
              const shouldRestart = !["disabled", "disposed", "speech-error"].includes(reason);
              const restarted = shouldRestart
                ? restartGate.waitForStart(recognitionCycle + 1)
                : null;
              try {
                recognition?.abort();
              } catch (_error) {
                // The recognizer already ended.
              }
              if (shouldRestart) {
                scheduleRestart();
                await restarted;
              }
            },
          };
        },

        async dispose() {
          active = false;
          recognitionAcceptingResults = false;
          browser.clearTimeout(restartTimer);
          browser.clearTimeout(finishTimer);
          restartGate.rejectAll(new Error("Browser speech was disabled."));
          currentClaim?.resolve?.({ text: "" });
          currentClaim = null;
          transcript.clear();
          try {
            recognition?.abort();
          } catch (_error) {
            // The recognizer already ended.
          }
          recognition = null;
        },
      };
    },
  };
}
