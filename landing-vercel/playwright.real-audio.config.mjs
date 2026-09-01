import { defineConfig } from "@playwright/test";
import baseConfig from "./playwright.config.mjs";

export default defineConfig(baseConfig, {
  testMatch: "**/*.real-audio.spec.mjs",
  testIgnore: [],
  timeout: 45_000,
  expect: { timeout: 15_000 },
  outputDir: `test-results/${process.env.ROMA_DEMO_E2E_PORT}-real-audio`,
  reporter: [["line"], ["html", { outputFolder: "playwright-report-real-audio", open: "never" }]],
  use: {
    ...baseConfig.use,
    channel: undefined,
    headless: false,
    permissions: ["microphone"],
    trace: "on",
    video: "on",
    launchOptions: {},
  },
});
