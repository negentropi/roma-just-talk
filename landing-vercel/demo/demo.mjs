import { createBrowserSpeechAdapter } from "./browser-speech.mjs";
import { createDeferredHold } from "./deferred-hold.mjs";
import { createDemoSession } from "./demo-session.mjs";
import { createPageDisarm } from "./page-safety.mjs";

const contexts = [
  { id: "messages", label: "messages", glyph: "@", title: "New message", meta: "to: Mia", action: "send", placeholder: "Tell Mia what changed..." },
  { id: "ai", label: "AI chat", glyph: "AI", title: "Ask anything", meta: "roma assistant", action: "ask", placeholder: "Explain the idea in your own words..." },
  { id: "search", label: "search", glyph: "/", title: "Search", meta: "the web", action: "search", placeholder: "What are you trying to find?" },
  { id: "coding", label: "agentic coding", glyph: "<>", title: "Give the agent a task", meta: "workspace", action: "run", placeholder: "Describe the change you want..." },
  { id: "social", label: "social post", glyph: "#", title: "New post", meta: "0 / 280", action: "post", placeholder: "Share the thought before it disappears..." },
  { id: "notes", label: "notes", glyph: "Aa", title: "Untitled note", meta: "today", action: "save", placeholder: "Capture a thought..." },
  { id: "email", label: "email", glyph: "✉", title: "Compose", meta: "subject: quick update", action: "send", placeholder: "Write the email out loud..." },
  { id: "office", label: "docs, slides, sheets", glyph: "▦", title: "Working document", meta: "draft 01", action: "share", placeholder: "Add the next paragraph, slide, or cell note..." },
  { id: "forms", label: "forms", glyph: "✓", title: "Additional details", meta: "step 3 of 4", action: "continue", placeholder: "Fill this field by speaking..." },
];

const root = document.querySelector("[data-demo-root]");
const editor = document.querySelector("[data-demo-editor]");
const micButton = document.querySelector("[data-mic-button]");
const languageSelect = document.querySelector("[data-language]");
const holdButton = document.querySelector("[data-hold-button]");
const statusText = document.querySelector("[data-status-text]");
const statusDot = document.querySelector("[data-status-dot]");
const capability = document.querySelector("[data-capability]");
const interim = document.querySelector("[data-interim]");
const contextName = document.querySelector("[data-context-name]");
const contextGlyph = document.querySelector("[data-context-glyph]");
const contextTitle = document.querySelector("[data-context-title]");
const contextMeta = document.querySelector("[data-context-meta]");
const contextAction = document.querySelector("[data-context-action]");
const contextActionState = document.querySelector("[data-context-action-state]");
const shuffleButton = document.querySelector("[data-shuffle]");
const contextRail = document.querySelector("[data-context-rail]");
const shiftKey = document.querySelector("[data-shift-key]");
const browserDifference = document.querySelector("[data-browser-difference]");

let currentContext = contexts[0];
let currentSnapshot = null;
let shuffleBag = [];
let shuffleTimer = 0;
let pointerId = null;
const heldChordKeys = new Set();
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function insertAtCursor(text) {
  const start = editor.selectionStart ?? editor.value.length;
  const end = editor.selectionEnd ?? start;
  const before = editor.value.slice(0, start);
  const after = editor.value.slice(end);
  const prefix = before && !/\s$/.test(before) ? " " : "";
  const suffix = after && !/^\s/.test(after) ? " " : "";
  const insertion = `${prefix}${text}${suffix}`;
  editor.setRangeText(insertion, start, end, "end");
  editor.dispatchEvent(new Event("input", { bubbles: true }));
  editor.focus({ preventScroll: true });
}

const session = createDemoSession({
  dictation: createBrowserSpeechAdapter(window),
  onCommit: ({ text }) => insertAtCursor(text),
});
const leftShift = createDeferredHold({
  onPress: ({ contextId }) => session.press({ source: "left-shift", contextId }),
  onRelease: () => session.release({ source: "left-shift" }),
  onCancel: (reason) => session.invalidate({ reason, immediate: true }),
});
const disarmPage = createPageDisarm({
  session,
  activation: leftShift,
  clearPointer: () => {
    pointerId = null;
    heldChordKeys.clear();
  },
});

function refillShuffleBag() {
  shuffleBag = contexts
    .filter((context) => context.id !== currentContext.id)
    .sort(() => Math.random() - 0.5);
}

function nextContext() {
  if (!shuffleBag.length) refillShuffleBag();
  return shuffleBag.pop() || contexts[0];
}

function selectContext(context, { announce = false } = {}) {
  currentContext = context;
  shuffleBag = shuffleBag.filter((candidate) => candidate.id !== context.id);
  root.dataset.context = context.id;
  contextName.textContent = context.label;
  contextGlyph.textContent = context.glyph;
  contextTitle.textContent = context.title;
  contextMeta.textContent = context.id === "social" ? `${editor.value.length} / 280` : context.meta;
  contextAction.textContent = context.action;
  editor.placeholder = context.placeholder;
  editor.setAttribute("aria-label", `${context.label} text field`);
  contextRail.querySelectorAll("button").forEach((button) => {
    const selected = button.dataset.contextId === context.id;
    button.classList.toggle("active", selected);
    button.setAttribute("aria-pressed", String(selected));
  });
  contextActionState.textContent = announce ? `${context.label} preview selected` : "Nothing leaves this preview.";
}

function contextCanMove() {
  return !["capturing", "finalizing", "preparing"].includes(currentSnapshot?.phase);
}

function contextCanAutoMove() {
  return contextCanMove() && document.activeElement !== editor;
}

function scheduleShuffle() {
  window.clearTimeout(shuffleTimer);
  if (reducedMotion.matches) return;
  shuffleTimer = window.setTimeout(() => {
    if (contextCanAutoMove() && !document.hidden) selectContext(nextContext());
    scheduleShuffle();
  }, 5_600);
}

function render(snapshot) {
  currentSnapshot = snapshot;
  root.dataset.phase = snapshot.phase;
  statusText.textContent = snapshot.message;
  capability.textContent = snapshot.capability;
  interim.textContent = snapshot.interim || "Your live speech preview appears here.";
  interim.classList.toggle("has-text", Boolean(snapshot.interim));
  statusDot.dataset.state = snapshot.phase;
  shiftKey.classList.toggle("pressed", snapshot.phase === "capturing");
  holdButton.classList.toggle("pressed", snapshot.phase === "capturing");
  holdButton.setAttribute("aria-pressed", String(snapshot.phase === "capturing"));
  languageSelect.disabled = snapshot.isArmed || ["preparing", "unsupported"].includes(snapshot.phase);

  const mayHold = snapshot.canPress || snapshot.phase === "capturing";
  holdButton.toggleAttribute("disabled", !mayHold);
  shuffleButton.toggleAttribute("disabled", !contextCanMove());
  contextRail.querySelectorAll("button").forEach((button) => {
    button.toggleAttribute("disabled", !contextCanMove());
  });

  if (snapshot.phase === "unsupported") micButton.textContent = "browser unsupported";
  else if (snapshot.phase === "preparing") micButton.textContent = "waiting for browser...";
  else if (snapshot.isArmed) micButton.textContent = "disable microphone";
  else if (snapshot.phase === "error") micButton.textContent = "try microphone again";
  else micButton.textContent = "enable microphone";
  micButton.disabled = ["preparing", "unsupported"].includes(snapshot.phase);

  if (snapshot.phase === "capturing") holdButton.querySelector("span").textContent = "release to add text";
  else if (snapshot.phase === "finalizing") holdButton.querySelector("span").textContent = "finishing...";
  else if (snapshot.canPress) holdButton.querySelector("span").textContent = "hold to catch it";
  else holdButton.querySelector("span").textContent = "enable mic first";

  browserDifference.hidden = snapshot.phase !== "unsupported";
}

contexts.forEach((context) => {
  const button = document.createElement("button");
  button.type = "button";
  button.dataset.contextId = context.id;
  button.innerHTML = `<span aria-hidden="true"></span><b></b>`;
  button.querySelector("span").textContent = context.glyph;
  button.querySelector("b").textContent = context.label;
  button.addEventListener("click", () => {
    if (contextCanMove()) selectContext(context, { announce: true });
  });
  contextRail.append(button);
});

micButton.addEventListener("click", async () => {
  if (currentSnapshot?.isArmed) await session.disable();
  else await session.enable({ language: languageSelect.value });
});

shuffleButton.addEventListener("click", () => {
  if (contextCanMove()) selectContext(nextContext(), { announce: true });
});

contextAction.addEventListener("click", () => {
  contextActionState.textContent = `${currentContext.action} is visual only in this demo`;
});

holdButton.addEventListener("pointerdown", (event) => {
  if (!currentSnapshot?.canPress || pointerId !== null) return;
  pointerId = event.pointerId;
  holdButton.setPointerCapture(pointerId);
  session.press({ source: "hold-button", contextId: currentContext.id });
});

holdButton.addEventListener("pointerup", async (event) => {
  if (event.pointerId !== pointerId) return;
  pointerId = null;
  await session.release({ source: "hold-button" });
});

holdButton.addEventListener("pointercancel", async (event) => {
  if (event.pointerId !== pointerId) return;
  pointerId = null;
  await session.invalidate({ reason: "pointer-cancel", immediate: true });
});

holdButton.addEventListener("lostpointercapture", async (event) => {
  if (event.pointerId !== pointerId) return;
  pointerId = null;
  await session.invalidate({ reason: "lost-pointer-capture", immediate: true });
});

holdButton.addEventListener("keydown", (event) => {
  if (!["Space", "Enter"].includes(event.code) || event.repeat || !currentSnapshot?.canPress) return;
  event.preventDefault();
  event.stopPropagation();
  session.press({ source: "hold-button", contextId: currentContext.id });
});

holdButton.addEventListener("keyup", async (event) => {
  if (!["Space", "Enter"].includes(event.code)) return;
  event.preventDefault();
  event.stopPropagation();
  await session.release({ source: "hold-button" });
});

holdButton.addEventListener("click", (event) => event.preventDefault());

function blocksPhysicalShortcut(target) {
  return target instanceof Element && Boolean(target.closest("button, select, a, [contenteditable='true']"));
}

window.addEventListener("keydown", (event) => {
  if (event.code === "ShiftLeft") {
    if (event.repeat || event.metaKey || event.ctrlKey || event.altKey || blocksPhysicalShortcut(event.target)) return;
    leftShift.begin(
      { contextId: currentContext.id },
      { chorded: heldChordKeys.size > 0 },
    );
    return;
  }
  heldChordKeys.add(event.code);
  leftShift.chord();
  if (currentSnapshot?.phase === "capturing") {
    session.invalidate({ reason: "other-key-down" });
  }
});

window.addEventListener("keyup", async (event) => {
  if (event.code === "ShiftLeft") {
    await leftShift.end();
    return;
  }
  heldChordKeys.delete(event.code);
  if (currentSnapshot?.phase === "capturing") {
    await session.invalidate({ reason: "other-key-up" });
  }
});

window.addEventListener("blur", () => {
  heldChordKeys.clear();
  void leftShift.cancel("lost-focus").then((didCancel) => {
    if (!didCancel) return session.invalidate({ reason: "lost-focus", immediate: true });
  });
});

document.addEventListener("visibilitychange", () => {
  if (document.hidden) void disarmPage();
});

window.addEventListener("pagehide", () => void session.dispose(), { once: true });

editor.addEventListener("input", () => {
  if (currentContext.id === "social") contextMeta.textContent = `${editor.value.length} / 280`;
});

reducedMotion.addEventListener?.("change", scheduleShuffle);
session.subscribe(render);
selectContext(currentContext);
scheduleShuffle();
