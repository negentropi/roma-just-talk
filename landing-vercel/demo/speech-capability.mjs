import { waitForOperation } from "./pending-operation.mjs";

export function speechError(errorLike) {
  const code = errorLike?.error || errorLike?.name || "speech-error";
  const messages = {
    "not-allowed": "Microphone access was denied. Allow it in browser settings, then try again.",
    "service-not-allowed": "The browser blocked its speech service. Check browser speech permissions.",
    "audio-capture": "No working microphone was found.",
    "language-not-supported": "The selected language is not available in this browser.",
    network: "The browser speech service could not connect. Try again.",
  };
  const error = new Error(messages[code] || "Browser speech recognition stopped. Try again.");
  error.code = code;
  return error;
}

export async function canUseInstalledLocalPack(Recognition, language, { browser, signal }) {
  if (typeof Recognition.available !== "function") return false;
  try {
    const status = await waitForOperation(
      Recognition.available({ langs: [language], processLocally: true }),
      {
        browser,
        signal,
        timeoutMs: 1_500,
        timeoutMessage: "Browser speech capability check timed out.",
      },
    );
    return ["available", "ready", "readily"].includes(String(status).toLowerCase());
  } catch (error) {
    if (error?.name === "AbortError") throw error;
    return false;
  }
}
