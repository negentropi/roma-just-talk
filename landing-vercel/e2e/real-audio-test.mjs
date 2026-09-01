import { expect, test as base } from "@playwright/test";

export const test = base.extend({
  browser: [async ({ playwright }, use) => {
    const endpoint = process.env.ROMA_DEMO_CDP_ENDPOINT?.trim();
    if (!endpoint) throw new Error("ROMA_DEMO_CDP_ENDPOINT is required for the real-audio E2E.");

    const browser = await playwright.chromium.connectOverCDP(endpoint);
    try {
      await use(browser);
    } finally {
      await browser.close();
    }
  }, { scope: "worker" }],
});

export { expect };
