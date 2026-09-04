import { expect, test } from "@playwright/test";

function installFakeSpeech(options = {}) {
  const state = {
    aborts: 0,
    abortDelayMs: Number(options.abortDelayMs || 0),
    delayFirst: Boolean(options.delayFirst),
    denyStarts: Number(options.denyStarts || 0),
    instances: [],
    invalidStarts: 0,
    serviceActive: false,
    starts: 0,
  };

  class FakeRecognition {
    static async available() { return "unavailable"; }

    constructor() {
      this.results = [];
      state.instances.push(this);
    }

    start() {
      if (state.serviceActive) {
        state.invalidStarts += 1;
        throw new DOMException("Speech recognition already started", "InvalidStateError");
      }
      state.serviceActive = true;
      state.starts += 1;
      const startNumber = state.starts;
      const begin = () => queueMicrotask(() => {
        if (startNumber <= state.denyStarts) {
          this.onerror?.({ error: "not-allowed" });
          return;
        }
        this.onstart?.();
      });
      if (state.delayFirst && startNumber === 1) this.releaseStart = begin;
      else begin();
    }

    stop() {
      state.serviceActive = false;
      queueMicrotask(() => this.onend?.());
    }

    abort() {
      state.aborts += 1;
      const finish = () => {
        state.serviceActive = false;
        this.onend?.();
      };
      if (state.abortDelayMs) setTimeout(finish, state.abortDelayMs);
      else queueMicrotask(finish);
    }

    emit(text, final = true) {
      this.results.push({ final, text });
      const results = this.results.map((value) => {
        const result = [{ transcript: value.text }];
        result.isFinal = value.final;
        return result;
      });
      this.onresult?.({ results });
    }
  }

  Object.defineProperty(window, "SpeechRecognition", {
    configurable: true,
    value: FakeRecognition,
  });
  Object.defineProperty(window, "webkitSpeechRecognition", {
    configurable: true,
    value: undefined,
  });
  window.__speech = {
    get aborts() { return state.aborts; },
    get invalidStarts() { return state.invalidStarts; },
    get starts() { return state.starts; },
    emit(text, final = true) { state.instances.at(-1)?.emit(text, final); },
    releaseFirst() { state.instances[0]?.releaseStart?.(); },
  };
}

async function installSpeech(page, options = {}) {
  await page.addInitScript(installFakeSpeech, options);
}

test("hands-on demo claims speech from before and during Left Shift", async ({ page }) => {
  await installSpeech(page);
  const siteApiRequests = [];
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.startsWith("/api/")) siteApiRequests.push(request.url());
  });
  const documentResponse = await page.goto("/demo");
  expect(documentResponse.headers()["content-security-policy"]).toContain("default-src 'self'");
  expect(documentResponse.headers()["permissions-policy"]).toBe("microphone=(self)");

  const root = page.locator("[data-demo-root]");
  const input = page.locator("[data-dictation-input]");
  await expect(root).toHaveAttribute("data-phase", "ready");
  await expect(input).toHaveAttribute("spellcheck", "false");
  await expect(input).toBeFocused();
  await expect(page.locator("[data-permission-recovery]")).toBeHidden();
  await expect(page.locator("[data-audio-disclosure]")).toContainText("Roma servers receive or store no audio or text");
  await expect(page.locator("[data-site-bar]")).toHaveCount(1);
  await expect(page.locator(".demo-intro, .demo-controls")).toHaveCount(0);
  for (let step = 0; step < 8; step += 1) {
    await page.keyboard.press("Tab");
    expect(await page.evaluate(() => Boolean(document.activeElement?.closest(".environment-stack")))).toBe(false);
  }
  await input.focus();
  const startingBox = await input.boundingBox();

  await page.evaluate(() => window.__speech.emit("The thought began before Shift"));
  await page.keyboard.down("Shift");
  await expect(root).toHaveAttribute("data-phase", "capturing");
  await expect(input).toHaveValue("");
  await expect(page.locator("[data-voice-caret] i").first()).toBeVisible();
  await page.evaluate(() => window.__speech.emit("and continued after it."));
  await page.keyboard.up("Shift");

  await expect(input).toHaveValue("The thought began before Shift and continued after it.");
  await expect(root).toHaveAttribute("data-phase", "ready");
  expect(siteApiRequests).toEqual([]);
  await expect.poll(async () => page.locator("[data-environment].is-active").getAttribute("data-environment"), {
    timeout: 8_000,
  }).not.toBe("messages");
  expect(await input.boundingBox()).toEqual(startingBox);
});

test("top-edge hover reveals site navigation without disturbing dictation", async ({ page }) => {
  await installSpeech(page);
  await page.goto("/demo");

  const input = page.locator("[data-dictation-input]");
  const siteBar = page.locator("[data-site-bar-panel]");
  const startingBox = await input.boundingBox();

  await expect(siteBar).toHaveCSS("opacity", "0");
  await page.mouse.move(200, 1);
  await expect(siteBar).toHaveCSS("opacity", "1");
  await expect(page.getByRole("navigation", { name: "Site" })).toContainText("roma just talk");
  await expect(page.getByRole("link", { name: "demo", exact: true })).toHaveAttribute("aria-current", "page");
  await expect(input).toBeFocused();
  expect(await input.boundingBox()).toEqual(startingBox);

  await page.mouse.move(200, 140);
  await expect(siteBar).toHaveCSS("opacity", "0");

  await input.focus();
  await page.keyboard.press("Tab");
  const toggle = page.locator("[data-site-bar-toggle]");
  await expect(toggle).toBeFocused();
  await expect(toggle).toHaveAttribute("aria-expanded", "true");
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "roma just talk" })).toBeFocused();
  await expect(siteBar).toHaveCSS("opacity", "1");
  await page.keyboard.press("Escape");
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await expect(input).toBeFocused();
  await expect(siteBar).toHaveCSS("opacity", "0");
});

test("touch handle opens the site navigation and outside tap closes it", async ({ browser, baseURL }) => {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    hasTouch: true,
    isMobile: true,
  });
  await context.addInitScript(installFakeSpeech);
  const page = await context.newPage();
  await page.goto(`${baseURL}/demo`);

  const input = page.locator("[data-dictation-input]");
  const siteBar = page.locator("[data-site-bar-panel]");
  const toggle = page.locator("[data-site-bar-toggle]");
  const startingBox = await input.boundingBox();

  await expect(siteBar).toHaveCSS("opacity", "0");
  await expect(toggle).toBeVisible();
  expect(Math.round((await toggle.boundingBox()).height)).toBeGreaterThanOrEqual(44);
  await toggle.tap();
  await expect(toggle).toHaveAttribute("aria-expanded", "true");
  await expect(siteBar).toHaveCSS("opacity", "1");
  for (const link of await page.getByRole("navigation", { name: "Site" }).getByRole("link").all()) {
    expect(Math.round((await link.boundingBox()).height)).toBeGreaterThanOrEqual(44);
  }
  expect(await input.boundingBox()).toEqual(startingBox);

  await page.touchscreen.tap(195, 300);
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await expect(siteBar).toHaveCSS("opacity", "0");
  expect(await input.boundingBox()).toEqual(startingBox);
  await context.close();
});

test("unsupported speech exposes the secondary preview without page chrome", async ({ browser, baseURL }) => {
  const context = await browser.newContext();
  await context.addInitScript(() => {
    Object.defineProperty(window, "SpeechRecognition", { configurable: true, value: undefined });
    Object.defineProperty(window, "webkitSpeechRecognition", { configurable: true, value: undefined });
    let hidden = false;
    Object.defineProperties(Document.prototype, {
      hidden: { configurable: true, get: () => hidden },
      visibilityState: { configurable: true, get: () => (hidden ? "hidden" : "visible") },
    });
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    Object.defineProperty(window, "speechSynthesis", {
      configurable: true,
      value: {
        cancel() {},
        speak(utterance) { queueMicrotask(() => utterance.onstart?.()); },
      },
    });
    window.__previewLifecycle = {
      setHidden(value) {
        hidden = value;
        document.dispatchEvent(new Event("visibilitychange"));
      },
    };
  });
  const page = await context.newPage();
  await page.goto(`${baseURL}/demo`);

  await expect(page.locator("[data-demo-root]")).toHaveAttribute("data-phase", "unsupported");
  await expect(page.locator("[data-permission-recovery]")).toBeVisible();
  await expect(page.locator("[data-preview-mode]")).toBeVisible();
  await expect(page.locator("[data-site-bar]")).toHaveCount(0);
  await expect(page.locator(".demo-intro, .demo-controls")).toHaveCount(0);
  await expect(page.locator("[data-dictation-input]")).toBeFocused();
  await page.locator("[data-preview-mode]").click();
  await expect(page.locator("[data-demo-root]")).toHaveAttribute("data-mode", "preview");
  await expect(page.locator("[data-demo-root]")).toHaveAttribute("data-phase", "ready");
  await expect(page.locator("[data-audio-disclosure]")).toContainText("No microphone audio");
  await page.evaluate(() => window.__previewLifecycle.setHidden(true));
  await expect(page.locator("[data-demo-root]")).toHaveAttribute("data-phase", "idle");
  await page.evaluate(() => window.__previewLifecycle.setHidden(false));
  await expect(page.locator("[data-demo-root]")).toHaveAttribute("data-phase", "ready");
  await context.close();
});

test("a denied microphone recovers through Chrome's trusted control", async ({ browser, baseURL }) => {
  const context = await browser.newContext();
  await context.addInitScript(installFakeSpeech, { denyStarts: 1 });
  const page = await context.newPage();
  await page.goto(`${baseURL}/demo`);

  const root = page.locator("[data-demo-root]");
  await expect(root).toHaveAttribute("data-phase", "permission-denied");
  await expect(page.locator("[data-site-bar]")).toHaveCount(0);
  await expect(page.locator("[data-permission-recovery]")).toBeVisible();
  await expect(page.locator("[data-recovery-copy]")).toContainText("requests audio only");
  await expect(page.locator("[data-preview-mode]")).toBeHidden();
  await page.waitForTimeout(1_500);
  await page.locator("usermedia").click();
  await expect(root).toHaveAttribute("data-phase", "ready");
  await expect(page.locator("[data-site-bar]")).toHaveCount(1);
  await expect(page.locator("[data-dictation-input]")).toBeFocused();
  await expect.poll(() => page.evaluate(() => window.__speech.starts)).toBe(2);
  await context.close();
});

test("hiding the tab stops browser speech and returning restarts it", async ({ browser, baseURL }) => {
  const context = await browser.newContext();
  await context.addInitScript(installFakeSpeech);
  await context.addInitScript(() => {
    let hidden = false;
    Object.defineProperties(Document.prototype, {
      hidden: { configurable: true, get: () => hidden },
      visibilityState: { configurable: true, get: () => (hidden ? "hidden" : "visible") },
    });
    window.__demoLifecycle = {
      setHidden(value) {
        hidden = value;
        document.dispatchEvent(new Event("visibilitychange"));
      },
    };
  });
  const page = await context.newPage();
  await page.goto(`${baseURL}/demo`);

  const root = page.locator("[data-demo-root]");
  await expect(root).toHaveAttribute("data-phase", "ready");
  await page.evaluate(() => window.__demoLifecycle.setHidden(true));
  await expect(root).toHaveAttribute("data-phase", "idle");
  await expect.poll(() => page.evaluate(() => window.__speech.aborts)).toBeGreaterThan(0);
  await page.evaluate(() => window.__demoLifecycle.setHidden(false));
  await expect(root).toHaveAttribute("data-phase", "ready");
  await expect.poll(() => page.evaluate(() => window.__speech.starts)).toBe(2);
  await context.close();
});

test("immediate tab return waits for Chrome's asynchronous speech teardown", async ({ browser, baseURL }) => {
  const context = await browser.newContext();
  await context.addInitScript(installFakeSpeech, { abortDelayMs: 150 });
  await context.addInitScript(() => {
    let hidden = false;
    Object.defineProperties(Document.prototype, {
      hidden: { configurable: true, get: () => hidden },
      visibilityState: { configurable: true, get: () => (hidden ? "hidden" : "visible") },
    });
    window.__rapidLifecycle = {
      hideAndReturn() {
        hidden = true;
        document.dispatchEvent(new Event("visibilitychange"));
        hidden = false;
        document.dispatchEvent(new Event("visibilitychange"));
      },
    };
  });
  const page = await context.newPage();
  await page.goto(`${baseURL}/demo`);

  const root = page.locator("[data-demo-root]");
  await expect(root).toHaveAttribute("data-phase", "ready");
  await page.evaluate(() => window.__rapidLifecycle.hideAndReturn());
  await expect(root).toHaveAttribute("data-phase", "ready");
  await expect.poll(() => page.evaluate(() => window.__speech.starts)).toBe(2);
  expect(await page.evaluate(() => window.__speech.invalidStarts)).toBe(0);
  await context.close();
});

test("returning during interrupted startup ignores the stale recognizer", async ({ browser, baseURL }) => {
  const context = await browser.newContext();
  await context.addInitScript(installFakeSpeech, { delayFirst: true });
  await context.addInitScript(() => {
    let hidden = false;
    Object.defineProperties(Document.prototype, {
      hidden: { configurable: true, get: () => hidden },
      visibilityState: { configurable: true, get: () => (hidden ? "hidden" : "visible") },
    });
    window.__demoPreparingLifecycle = {
      setHidden(value) {
        hidden = value;
        document.dispatchEvent(new Event("visibilitychange"));
      },
    };
  });
  const page = await context.newPage();
  await page.goto(`${baseURL}/demo`);

  const root = page.locator("[data-demo-root]");
  await expect(root).toHaveAttribute("data-phase", "preparing");
  await page.evaluate(() => window.__demoPreparingLifecycle.setHidden(true));
  await expect(root).toHaveAttribute("data-phase", "idle");
  await page.evaluate(() => window.__demoPreparingLifecycle.setHidden(false));
  await expect(root).toHaveAttribute("data-phase", "ready");
  await expect.poll(() => page.evaluate(() => window.__speech.starts)).toBe(2);
  await page.evaluate(() => window.__speech.releaseFirst());
  await expect(root).toHaveAttribute("data-phase", "ready");
  await context.close();
});

test("mobile keeps the writing field and touch hold inside the viewport", async ({ browser, baseURL }) => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  await context.addInitScript(installFakeSpeech);
  const page = await context.newPage();
  await page.goto(`${baseURL}/demo`);

  const root = page.locator("[data-demo-root]");
  const input = page.locator("[data-dictation-input]");
  const trigger = page.locator("[data-touch-trigger]");
  const disclosure = page.locator("[data-audio-disclosure]");
  await expect(root).toHaveAttribute("data-phase", "ready");
  const inputBox = await input.boundingBox();
  const triggerBox = await trigger.boundingBox();
  const disclosureMetrics = await disclosure.evaluate((element) => {
    const styles = getComputedStyle(element);
    const lineHeight = Number.parseFloat(styles.lineHeight);
    return {
      fontSize: Number.parseFloat(styles.fontSize),
      lines: Math.round(element.getBoundingClientRect().height / lineHeight),
    };
  });
  expect(inputBox.x).toBeGreaterThanOrEqual(0);
  expect(inputBox.x + inputBox.width).toBeLessThanOrEqual(390);
  expect(triggerBox.y + triggerBox.height).toBeLessThanOrEqual(844);
  expect(disclosureMetrics.fontSize).toBeGreaterThanOrEqual(12);
  expect(disclosureMetrics.lines).toBeLessThanOrEqual(3);
  await page.mouse.move(triggerBox.x + triggerBox.width / 2, triggerBox.y + triggerBox.height / 2);
  await page.mouse.down();
  await expect(root).toHaveAttribute("data-phase", "capturing");
  await expect(input).toBeFocused();
  await expect(page.locator("[data-voice-caret] i").first()).toBeVisible();
  await page.mouse.up();
  await expect(root).toHaveAttribute("data-phase", "ready");
  await page.waitForTimeout(100);

  await page.mouse.down();
  await expect(root).toHaveAttribute("data-phase", "capturing");
  await page.evaluate(() => window.__speech.emit("must not survive lost capture"));
  await trigger.dispatchEvent("lostpointercapture", { pointerId: 1 });
  await expect(root).toHaveAttribute("data-phase", "ready");
  await expect(input).toHaveValue("");
  await page.mouse.up();
  await page.waitForTimeout(100);

  await page.mouse.down();
  await expect(root).toHaveAttribute("data-phase", "capturing");
  await page.evaluate(() => window.dispatchEvent(new Event("blur")));
  await expect(root).toHaveAttribute("data-phase", "ready");
  await expect(input).toHaveValue("");
  await page.mouse.up();
  await context.close();
});
