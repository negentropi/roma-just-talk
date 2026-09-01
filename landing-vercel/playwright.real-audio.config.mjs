import { defineConfig } from "@playwright/test";
import baseConfig from "./playwright.config.mjs";

const chromeExecutable = process.env.ROMA_DEMO_CHROME_EXECUTABLE?.trim();
const chromeLogFile = process.env.ROMA_DEMO_CHROME_LOG?.trim();

export default defineConfig(baseConfig, {
  testMatch: "**/*.real-audio.spec.mjs",
  testIgnore: [],
  timeout: 45_000,
  expect: { timeout: 15_000 },
  outputDir: `test-results/${process.env.ROMA_DEMO_E2E_PORT}-real-audio`,
  reporter: [["line"], ["html", { outputFolder: "playwright-report-real-audio", open: "never" }]],
  use: {
    ...baseConfig.use,
    channel: chromeExecutable ? undefined : "chrome",
    headless: false,
    permissions: ["microphone"],
    trace: "on",
    video: "on",
    launchOptions: {
      ...(chromeExecutable ? { executablePath: chromeExecutable } : {}),
      args: [
        "--use-fake-ui-for-media-stream",
        "--no-first-run",
        "--no-default-browser-check",
        ...(chromeLogFile ? [
          "--enable-logging",
          `--log-file=${chromeLogFile}`,
          "--vmodule=audio*=2,media*=2",
        ] : []),
      ],
    },
  },
});
