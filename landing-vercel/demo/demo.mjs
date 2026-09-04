import { createDemoSession } from "./demo-session.mjs";
import { createBrowserSpeechAdapter } from "./browser-speech.mjs";
import { createEnvironmentCycle } from "./environment-cycle.mjs";
import { createPreviewDictationAdapter } from "./preview-dictation.mjs";
import { createSpecialHold } from "./special-hold.mjs";

const root = document.querySelector("[data-demo-root]");
const siteBarTemplate = document.querySelector("[data-site-bar-template]");
const editor = document.querySelector("[data-dictation-input]");
const writingField = document.querySelector("[data-writing-field]");
const caret = document.querySelector("[data-voice-caret]");
const statusText = document.querySelector("[data-status]");
const audioDisclosure = document.querySelector("[data-audio-disclosure]");
const recovery = document.querySelector("[data-permission-recovery]");
const recoveryCopy = document.querySelector("[data-recovery-copy]");
const userMediaControl = document.querySelector("[data-usermedia]");
const enableMicrophoneButton = document.querySelector("[data-enable-microphone]");
const previewButton = document.querySelector("[data-preview-mode]");
const touchTrigger = document.querySelector("[data-touch-trigger]");
const environments = [...document.querySelectorAll("[data-environment]")];
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

let session;
let currentSnapshot;
let currentMode = "microphone";
let permissionFailures = 0;
let pointerId = null;
let shouldResumeMicrophone = true;
let shouldResumePreview = false;
let userMediaOwnsPermission = false;
let firstAttemptStarted = false;
let armGeneration = 0;
let siteBar = null;
let siteBarToggle = null;
const heldChordKeys = new Set();

function setSiteBarOpen(open) {
  if (!siteBar || !siteBarToggle) return;
  siteBar.dataset.open = String(open);
  siteBarToggle.setAttribute("aria-expanded", String(open));
}

function closeSiteBarOutside(event) {
  if (siteBar?.dataset.open === "true" && !siteBar.contains(event.target)) {
    setSiteBarOpen(false);
  }
}

function mountSiteBar() {
  if (!siteBar) {
    siteBar = siteBarTemplate.content.firstElementChild.cloneNode(true);
    siteBarToggle = siteBar.querySelector("[data-site-bar-toggle]");

    siteBarToggle.addEventListener("click", () => setSiteBarOpen(true));

    siteBar.addEventListener("focusin", () => setSiteBarOpen(true));

    siteBar.addEventListener("focusout", (event) => {
      if (!siteBar.contains(event.relatedTarget)) setSiteBarOpen(false);
    });

    siteBar.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      setSiteBarOpen(false);
      editor.focus({ preventScroll: true });
    });
  }

  if (!siteBar.isConnected) {
    root.append(siteBar);
    document.addEventListener("pointerdown", closeSiteBarOutside);
  }
}

function setSiteBarAvailable(available) {
  if (available) {
    mountSiteBar();
    return;
  }
  if (!siteBar) return;
  setSiteBarOpen(false);
  document.removeEventListener("pointerdown", closeSiteBarOutside);
  siteBar.remove();
}

function insertionFor(value, start, end, text) {
  const before = value.slice(0, start);
  const after = value.slice(end);
  const prefix = before && !/\s$/.test(before) ? " " : "";
  const suffix = after && !/^\s/.test(after) ? " " : "";
  return `${prefix}${text}${suffix}`;
}

function insertAtCursor(text) {
  const start = editor.selectionStart ?? editor.value.length;
  const end = editor.selectionEnd ?? start;
  editor.setRangeText(insertionFor(editor.value, start, end, text), start, end, "end");
  editor.dispatchEvent(new Event("input", { bubbles: true }));
  editor.focus({ preventScroll: true });
}

function createSession(adapter) {
  return createDemoSession({
    dictation: adapter,
    onCommit: ({ text }) => insertAtCursor(text),
  });
}

session = createSession(createBrowserSpeechAdapter(window));

const leftShift = createSpecialHold({
  onPress: () => {
    firstAttemptStarted = true;
    editor.placeholder = "";
    return session.press({ source: "left-shift" });
  },
  onRelease: () => session.release({ source: "left-shift" }),
  onCancel: (reason) => session.invalidate({ reason, immediate: true }),
});

const environmentCycle = createEnvironmentCycle({
  count: environments.length,
  intervalMs: 7_000,
  reducedMotion: reducedMotion.matches,
  onChange: (activeIndex) => {
    environments.forEach((environment, index) => {
      environment.classList.toggle("is-active", index === activeIndex);
    });
  },
});

function browserLanguage() {
  return navigator.language || "en-US";
}

function setRecovery(snapshot) {
  const recoverable = ["permission-denied", "unsupported", "error"].includes(snapshot.phase);
  recovery.hidden = !recoverable || currentMode === "preview";
  if (!recoverable) return;

  if (snapshot.phase === "permission-denied") {
    recoveryCopy.textContent = permissionFailures > 1
      ? "Allow Microphone in your browser settings, or use the see-only preview."
      : "Allow microphone for the hands-on demo. Chrome's recovery control covers both permissions, but this demo requests audio only.";
  } else if (snapshot.phase === "unsupported") {
    recoveryCopy.textContent = "The hands-on demo needs current Chrome or Edge.";
  } else {
    recoveryCopy.textContent = snapshot.message;
  }

  previewButton.hidden = permissionFailures < 2 && snapshot.phase !== "unsupported";
  userMediaControl.hidden = snapshot.phase === "unsupported";
}

function render(snapshot) {
  currentSnapshot = snapshot;
  root.dataset.phase = snapshot.phase;
  root.dataset.mode = currentMode;
  const siteBarAvailable = ["ready", "capturing", "finalizing"].includes(snapshot.phase);
  setSiteBarAvailable(siteBarAvailable);
  statusText.textContent = snapshot.message;
  audioDisclosure.textContent = currentMode === "preview"
    ? "See-only preview. No microphone audio is captured or sent."
    : "Your browser's speech provider may receive audio. Roma servers receive or store no audio or text. Closing this tab clears text. Shift claims 3 seconds back.";
  touchTrigger.disabled = !(snapshot.canPress || snapshot.phase === "capturing");
  touchTrigger.setAttribute("aria-pressed", String(snapshot.phase === "capturing"));
  touchTrigger.textContent = snapshot.phase === "capturing" ? "release when done" : "hold to catch this";
  setRecovery(snapshot);
  updateCaret();

  if (snapshot.phase === "ready") {
    shouldResumeMicrophone = currentMode === "microphone";
    editor.focus({ preventScroll: true });
  }
}

session.subscribe(render);

function mirrorCaretPosition() {
  const styles = getComputedStyle(editor);
  const mirror = document.createElement("div");
  const marker = document.createElement("span");
  const properties = [
    "borderLeftWidth",
    "borderTopWidth",
    "fontFamily",
    "fontSize",
    "fontStyle",
    "fontWeight",
    "letterSpacing",
    "lineHeight",
    "paddingLeft",
    "paddingTop",
    "tabSize",
    "textTransform",
    "whiteSpace",
    "wordBreak",
    "wordSpacing",
  ];
  properties.forEach((property) => { mirror.style[property] = styles[property]; });
  mirror.style.position = "absolute";
  mirror.style.visibility = "hidden";
  mirror.style.overflow = "hidden";
  mirror.style.top = "0";
  mirror.style.left = "0";
  mirror.style.width = `${editor.clientWidth}px`;
  mirror.style.height = `${editor.clientHeight}px`;
  mirror.style.whiteSpace = "pre-wrap";
  mirror.style.overflowWrap = "break-word";
  mirror.textContent = editor.value.slice(0, editor.selectionStart ?? editor.value.length);
  marker.textContent = "\u200b";
  mirror.append(marker);
  writingField.append(mirror);
  const position = {
    left: marker.offsetLeft - editor.scrollLeft,
    top: marker.offsetTop - editor.scrollTop,
  };
  mirror.remove();
  return position;
}

function updateCaret() {
  const start = editor.selectionStart ?? 0;
  const end = editor.selectionEnd ?? start;
  root.dataset.selection = start === end ? "caret" : "range";
  root.dataset.focus = document.activeElement === editor ? "editor" : "away";
  if (start !== end) return;
  const position = mirrorCaretPosition();
  caret.style.setProperty("--caret-x", `${position.left}px`);
  caret.style.setProperty("--caret-y", `${position.top}px`);
}

async function armMicrophone() {
  const ownGeneration = ++armGeneration;
  shouldResumeMicrophone = true;
  shouldResumePreview = false;
  currentMode = "microphone";
  root.dataset.mode = currentMode;
  await session.disable();
  if (ownGeneration !== armGeneration || document.hidden) {
    return false;
  }
  const armed = await session.enable({
    language: browserLanguage(),
    mode: currentMode,
  });
  if (ownGeneration !== armGeneration || document.hidden) {
    if (armed) await session.disable();
    return false;
  }
  if (!armed) {
    shouldResumeMicrophone = false;
    const failedSnapshot = session.getSnapshot();
    if (["permission-denied", "unsupported", "error"].includes(failedSnapshot.phase)) {
      permissionFailures += 1;
      setRecovery(failedSnapshot);
    }
  }
  return armed;
}

async function startPreview() {
  armGeneration += 1;
  await session.dispose();
  currentMode = "preview";
  shouldResumeMicrophone = false;
  shouldResumePreview = true;
  recovery.hidden = true;
  session = createSession(createPreviewDictationAdapter(window));
  session.subscribe(render);
  shouldResumePreview = await session.enable({ language: browserLanguage(), mode: currentMode });
  editor.focus({ preventScroll: true });
}

function supportsUserMediaElement() {
  return "HTMLUserMediaElement" in window && typeof userMediaControl?.setConstraints === "function";
}

if (supportsUserMediaElement()) {
  userMediaOwnsPermission = true;
  userMediaControl.setConstraints({
    audio: {
      autoGainControl: true,
      channelCount: 1,
      echoCancellation: true,
      noiseSuppression: true,
    },
  });
  userMediaControl.addEventListener("stream", (event) => {
    const stream = event.stream || userMediaControl.stream;
    stream?.getTracks?.().forEach((track) => track.stop());
    if (stream && currentMode === "microphone") void armMicrophone();
  });
  userMediaControl.addEventListener("error", () => {
    permissionFailures += 1;
    previewButton.hidden = permissionFailures < 2;
  });
  userMediaControl.addEventListener("cancel", () => {
    permissionFailures += 1;
    previewButton.hidden = permissionFailures < 2;
  });
} else {
  userMediaOwnsPermission = false;
  enableMicrophoneButton.addEventListener("click", () => void armMicrophone());
}

previewButton.addEventListener("click", () => void startPreview());

function blocksPhysicalShortcut(event) {
  return event.target instanceof Element
    && Boolean(event.target.closest("button, select, a, usermedia"));
}

window.addEventListener("keydown", (event) => {
  if (event.code === "ShiftLeft") {
    if (event.repeat || event.metaKey || event.ctrlKey || event.altKey || blocksPhysicalShortcut(event)) return;
    leftShift.begin({}, { chorded: heldChordKeys.size > 0 });
    return;
  }
  heldChordKeys.add(event.code);
  if (currentSnapshot?.phase === "capturing") void session.invalidate({ reason: "other-key-down" });
});

window.addEventListener("keyup", async (event) => {
  if (event.code === "ShiftLeft") {
    await leftShift.end();
    return;
  }
  heldChordKeys.delete(event.code);
  if (currentSnapshot?.phase === "capturing") await session.invalidate({ reason: "other-key-up" });
});

async function cancelTouch(reason, eventPointerId) {
  if (pointerId === null) return false;
  if (Number.isInteger(eventPointerId) && eventPointerId !== pointerId) return false;
  pointerId = null;
  await session.invalidate({ reason, immediate: true });
  return true;
}

window.addEventListener("blur", () => {
  heldChordKeys.clear();
  void leftShift.cancel("lost-focus");
  void cancelTouch("lost-focus");
});

touchTrigger.addEventListener("pointerdown", (event) => {
  if (!currentSnapshot?.canPress || pointerId !== null) return;
  event.preventDefault();
  pointerId = event.pointerId;
  touchTrigger.setPointerCapture(pointerId);
  firstAttemptStarted = true;
  editor.placeholder = "";
  if (!session.press({ source: "touch" })) pointerId = null;
});

touchTrigger.addEventListener("pointerup", async (event) => {
  if (event.pointerId !== pointerId) return;
  pointerId = null;
  await session.release({ source: "touch" });
});

touchTrigger.addEventListener("pointercancel", async (event) => {
  await cancelTouch("pointer-cancel", event.pointerId);
});

touchTrigger.addEventListener("lostpointercapture", async (event) => {
  await cancelTouch("lost-pointer-capture", event.pointerId);
});

editor.addEventListener("input", updateCaret);
editor.addEventListener("click", updateCaret);
editor.addEventListener("keyup", updateCaret);
editor.addEventListener("select", updateCaret);
editor.addEventListener("focus", updateCaret);
editor.addEventListener("blur", () => {
  root.dataset.focus = "away";
  window.setTimeout(() => {
    if (document.activeElement === document.body && !document.hidden) editor.focus({ preventScroll: true });
  }, 0);
});
window.addEventListener("resize", updateCaret);

document.addEventListener("visibilitychange", async () => {
  if (document.hidden) {
    armGeneration += 1;
    leftShift.reset();
    heldChordKeys.clear();
    pointerId = null;
    const resume = currentMode === "microphone"
      && !["permission-denied", "unsupported", "error"].includes(currentSnapshot?.phase);
    shouldResumeMicrophone = resume;
    shouldResumePreview = currentMode === "preview"
      && !["unsupported", "error"].includes(currentSnapshot?.phase);
    await session.disable();
    return;
  }
  if (shouldResumeMicrophone) {
    await armMicrophone();
  } else if (shouldResumePreview) {
    shouldResumePreview = await session.enable({ language: browserLanguage(), mode: currentMode });
  }
  editor.focus({ preventScroll: true });
});

window.addEventListener("pagehide", () => {
  environmentCycle.stop();
  void session.dispose();
}, { once: true });

environmentCycle.start();
editor.focus({ preventScroll: true });
updateCaret();
void armMicrophone();

window.__romaDemo = {
  get mode() { return currentMode; },
  get snapshot() { return currentSnapshot; },
  get permissionFailures() { return permissionFailures; },
  get userMediaOwnsPermission() { return userMediaOwnsPermission; },
  get firstAttemptStarted() { return firstAttemptStarted; },
};
