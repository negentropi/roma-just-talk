import { cleanTranscriptText, joinTranscriptParts } from "./transcript.mjs";

export function createRollingTranscript({ clock, lookbackMs }) {
  let segments = [];
  let interim = "";
  let interimAt = 0;
  let activeClaim = null;

  const prune = () => {
    const cutoff = clock() - lookbackMs;
    segments = segments.filter((segment) => segment.at >= cutoff);
    if (interimAt < cutoff) {
      interim = "";
      interimAt = 0;
    }
  };

  return {
    beginClaim() {
      prune();
      const claim = {
        prefix: joinTranscriptParts([...segments.map((segment) => segment.text), interim]),
        fresh: [],
        interim: "",
      };
      activeClaim = claim;
      return claim;
    },

    ingest(results, seenFinalIndexes) {
      let nextInterim = "";
      for (let index = 0; index < results.length; index += 1) {
        const result = results[index];
        const text = cleanTranscriptText(result?.[0]?.transcript);
        if (!text) continue;
        if (result.isFinal) {
          if (seenFinalIndexes.has(index)) continue;
          seenFinalIndexes.add(index);
          segments.push({ text, at: clock() });
          activeClaim?.fresh.push(text);
        } else {
          nextInterim = joinTranscriptParts([nextInterim, text]);
        }
      }
      interim = nextInterim;
      interimAt = nextInterim ? clock() : 0;
      if (activeClaim) activeClaim.interim = nextInterim;
      prune();
    },

    textFor(claim) {
      return joinTranscriptParts([claim.prefix, ...claim.fresh, claim.interim]);
    },

    clear() {
      segments = [];
      interim = "";
      interimAt = 0;
      activeClaim = null;
    },
  };
}
