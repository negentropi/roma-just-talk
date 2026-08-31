export function speechError(errorLike) {
  const code = errorLike?.error || errorLike?.name || "speech-error";
  const messages = {
    "not-allowed": "Microphone access was denied. Allow it in browser settings, then try again.",
    "service-not-allowed": "The browser blocked its speech service. Check browser speech permissions.",
    "audio-capture": "No working microphone was found.",
    "language-not-supported": "The selected language is not available in this browser.",
    network: "The browser speech service could not connect. Try again.",
  };
  if (errorLike instanceof Error && !messages[code]) {
    const preserved = new Error(errorLike.message || "Browser speech recognition stopped. Try again.");
    preserved.name = errorLike.name;
    preserved.code = code;
    return preserved;
  }
  const error = new Error(messages[code] || "Browser speech recognition stopped. Try again.");
  error.code = code;
  if (["not-allowed", "service-not-allowed"].includes(code)) error.name = "NotAllowedError";
  return error;
}
