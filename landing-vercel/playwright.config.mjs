import { defineConfig } from "@playwright/test";
import { createServer } from "node:net";

async function availablePort() {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const { port } = server.address();
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  return port;
}

const port = Number.parseInt(process.env.ROMA_DEMO_E2E_PORT || String(await availablePort()), 10);
process.env.ROMA_DEMO_E2E_PORT = String(port);
const baseURL = `http://127.0.0.1:${port}`;

export default defineConfig({
  testDir: "./e2e",
  timeout: 20_000,
  expect: { timeout: 5_000 },
  fullyParallel: false,
  workers: 1,
  outputDir: `test-results/${port}`,
  reporter: [["line"]],
  use: {
    baseURL,
    channel: "chrome",
    headless: true,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure",
    launchOptions: {
      args: [
        "--use-fake-device-for-media-stream",
        "--use-fake-ui-for-media-stream",
      ],
    },
  },
  webServer: {
    command: `ROMA_DEMO_PORT=${port} node scripts/demo-server.mjs`,
    url: `${baseURL}/demo`,
    reuseExistingServer: false,
    timeout: 10_000,
  },
});
