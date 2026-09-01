import { expect, test } from "@playwright/test";
import { spawn } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { performance } from "node:perf_hooks";

const AUDIO_LEAD_MS = 1_100;
const DEFAULT_COMPLETION_BUDGET_MS = 1_500;
const DEFAULT_MAXIMUM_WORD_ERROR_RATE = 0.15;
const MINIMUM_FIXTURE_RMS_DBFS = -30;

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required for the real-audio E2E.`);
  return value;
}

function normalizedWords(text) {
  return String(text)
    .toLocaleLowerCase("en-US")
    .replace(/[’']/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

function wordErrorRate(expectedWords, actualWords) {
  const row = Array.from({ length: actualWords.length + 1 }, (_, index) => index);
  for (let expectedIndex = 1; expectedIndex <= expectedWords.length; expectedIndex += 1) {
    let previousDiagonal = row[0];
    row[0] = expectedIndex;
    for (let actualIndex = 1; actualIndex <= actualWords.length; actualIndex += 1) {
      const previousAbove = row[actualIndex];
      const substitution = previousDiagonal
        + Number(expectedWords[expectedIndex - 1] !== actualWords[actualIndex - 1]);
      row[actualIndex] = Math.min(
        row[actualIndex] + 1,
        row[actualIndex - 1] + 1,
        substitution,
      );
      previousDiagonal = previousAbove;
    }
  }
  return row.at(-1) / Math.max(1, expectedWords.length);
}

function pcm16WaveRmsDecibelsFullScale(buffer) {
  if (buffer.toString("ascii", 0, 4) !== "RIFF" || buffer.toString("ascii", 8, 12) !== "WAVE") {
    throw new Error("The real-audio fixture must be a RIFF/WAVE file.");
  }

  let format;
  let dataStart;
  let dataSize;
  for (let offset = 12; offset + 8 <= buffer.length;) {
    const chunkId = buffer.toString("ascii", offset, offset + 4);
    const chunkSize = buffer.readUInt32LE(offset + 4);
    const chunkStart = offset + 8;
    const chunkEnd = chunkStart + chunkSize;
    if (chunkEnd > buffer.length) throw new Error(`Invalid ${chunkId} chunk in the WAV fixture.`);
    if (chunkId === "fmt ") {
      format = {
        audioFormat: buffer.readUInt16LE(chunkStart),
        bitsPerSample: buffer.readUInt16LE(chunkStart + 14),
      };
    } else if (chunkId === "data") {
      dataStart = chunkStart;
      dataSize = chunkSize;
    }
    offset = chunkEnd + (chunkSize % 2);
  }

  if (format?.audioFormat !== 1 || format.bitsPerSample !== 16 || dataStart === undefined || !dataSize) {
    throw new Error("The real-audio fixture must contain 16-bit PCM samples.");
  }

  const sampleCount = Math.floor(dataSize / 2);
  let squaredTotal = 0;
  for (let offset = dataStart; offset < dataStart + sampleCount * 2; offset += 2) {
    const sample = buffer.readInt16LE(offset) / 32_768;
    squaredTotal += sample * sample;
  }
  const rms = Math.sqrt(squaredTotal / sampleCount);
  return rms > 0 ? 20 * Math.log10(rms) : Number.NEGATIVE_INFINITY;
}

function waitForPlayback(playback) {
  return new Promise((resolvePlayback, rejectPlayback) => {
    let stderr = "";
    playback.stderr.setEncoding("utf8");
    playback.stderr.on("data", (chunk) => { stderr += chunk; });
    playback.once("error", rejectPlayback);
    playback.once("close", (exitCode, signal) => {
      if (exitCode === 0) resolvePlayback();
      else rejectPlayback(new Error(`afplay failed with exit ${exitCode}, signal ${signal || "none"}: ${stderr.trim()}`));
    });
  });
}

async function stopPlayback(playback) {
  if (!playback || playback.exitCode !== null || playback.signalCode !== null) return;

  const closed = new Promise((resolveClose) => playback.once("close", resolveClose));
  playback.kill("SIGTERM");
  const stopped = await Promise.race([
    closed.then(() => true),
    new Promise((resolveTimeout) => setTimeout(resolveTimeout, 1_000, false)),
  ]);
  if (!stopped) {
    playback.kill("SIGKILL");
    await closed;
  }
}

test("afplay starts 1.1 seconds before Left Shift and finishes as timely text", async ({ page, baseURL }, testInfo) => {
  const fixture = requiredEnvironment("ROMA_DEMO_AUDIO_FIXTURE");
  const expectedTranscript = requiredEnvironment("ROMA_DEMO_EXPECTED_TRANSCRIPT");
  const audioDevice = process.env.ROMA_DEMO_AUDIO_DEVICE || "BlackHole 2ch";
  const completionBudgetMs = Number(process.env.ROMA_DEMO_COMPLETION_BUDGET_MS || DEFAULT_COMPLETION_BUDGET_MS);
  const maximumWordErrorRate = Number(process.env.ROMA_DEMO_MAXIMUM_WER || DEFAULT_MAXIMUM_WORD_ERROR_RATE);
  const artifactDirectory = resolve("test-results", "real-audio");
  const reportPath = resolve(process.env.ROMA_DEMO_AUDIO_REPORT || `${artifactDirectory}/receipt.json`);
  const screenshotPath = resolve(artifactDirectory, "completed-demo.png");
  const report = {
    fixture,
    expectedTranscript,
    audioDevice,
    playbackProcessLeadTargetMilliseconds: AUDIO_LEAD_MS,
    completionBudgetMilliseconds: completionBudgetMs,
    maximumWordErrorRate,
    startedAt: new Date().toISOString(),
    passed: false,
  };
  const browserMessages = [];
  let playback;
  let playbackFinished;
  let shiftHeld = false;

  page.on("console", (message) => browserMessages.push(`${message.type()}: ${message.text()}`));
  page.on("pageerror", (error) => browserMessages.push(`pageerror: ${error.message}`));
  await page.addInitScript(() => {
    window.__romaRealAudioTiming = {
      shiftDownAt: null,
      shiftDownEpochMs: null,
      shiftUpAt: null,
      shiftUpEpochMs: null,
      textVisibleAt: null,
    };
    window.addEventListener("keydown", (event) => {
      if (event.code === "ShiftLeft" && window.__romaRealAudioTiming.shiftDownAt === null) {
        window.__romaRealAudioTiming.shiftDownAt = performance.now();
        window.__romaRealAudioTiming.shiftDownEpochMs = Date.now();
      }
    }, true);
    window.addEventListener("keyup", (event) => {
      if (event.code === "ShiftLeft") {
        window.__romaRealAudioTiming.shiftUpAt = performance.now();
        window.__romaRealAudioTiming.shiftUpEpochMs = Date.now();
      }
    }, true);
    window.addEventListener("input", (event) => {
      if (event.target?.matches?.("[data-dictation-input]") && event.target.value) {
        const field = event.target;
        requestAnimationFrame(() => requestAnimationFrame(() => {
          const rect = field.getBoundingClientRect();
          const style = getComputedStyle(field);
          if (
            field.value
            && rect.width > 0
            && rect.height > 0
            && style.display !== "none"
            && style.visibility !== "hidden"
          ) {
            window.__romaRealAudioTiming.textVisibleAt ??= performance.now();
          }
        }));
      }
    }, true);
  });

  try {
    const fixtureRmsDecibelsFullScale = pcm16WaveRmsDecibelsFullScale(await readFile(fixture));
    report.fixtureRmsDecibelsFullScale = fixtureRmsDecibelsFullScale;
    expect(fixtureRmsDecibelsFullScale).toBeGreaterThanOrEqual(MINIMUM_FIXTURE_RMS_DBFS);

    const response = await page.goto(`${baseURL}/demo`);
    expect(response?.status()).toBe(200);
    const root = page.locator("[data-demo-root]");
    const input = page.locator("[data-dictation-input]");
    await expect(root).toHaveAttribute("data-phase", "ready", { timeout: 15_000 });
    await expect(input).toBeFocused();

    const audioInputs = await page.evaluate(async () => (await navigator.mediaDevices.enumerateDevices())
      .filter((device) => device.kind === "audioinput")
      .map(({ deviceId, label }) => ({ deviceId, label })));
    report.browserAudioInputs = audioInputs;
    const defaultInput = audioInputs.find((device) => device.deviceId === "default") || audioInputs[0];
    expect(defaultInput?.label || "").toContain(audioDevice);

    playback = spawn("/usr/bin/afplay", [fixture], { stdio: ["ignore", "ignore", "pipe"] });
    await new Promise((resolveSpawn, rejectSpawn) => {
      playback.once("spawn", resolveSpawn);
      playback.once("error", rejectSpawn);
    });
    const audioStartedAt = performance.now();
    const audioStartedEpochMs = Date.now();
    playbackFinished = waitForPlayback(playback);
    playbackFinished.catch(() => {});
    const waitBeforeShift = Math.max(0, AUDIO_LEAD_MS - (performance.now() - audioStartedAt));
    await new Promise((resolveDelay) => setTimeout(resolveDelay, waitBeforeShift));

    await page.keyboard.down("Shift");
    shiftHeld = true;
    await expect(root).toHaveAttribute("data-phase", "capturing");
    await playbackFinished;
    const audioFinishedEpochMs = Date.now();
    await page.keyboard.up("Shift");
    shiftHeld = false;

    await expect(input).not.toHaveValue("", { timeout: completionBudgetMs + 1_000 });
    await expect(root).toHaveAttribute("data-phase", "ready");
    await expect(input).toBeVisible();
    await page.waitForFunction(
      () => Number.isFinite(window.__romaRealAudioTiming.textVisibleAt),
      null,
      { timeout: completionBudgetMs + 1_000 },
    );
    const transcript = await input.inputValue();
    const timing = await page.evaluate(() => window.__romaRealAudioTiming);
    const expectedWords = normalizedWords(expectedTranscript);
    const transcriptWords = normalizedWords(transcript);
    const transcriptWordErrorRate = wordErrorRate(expectedWords, transcriptWords);
    const audioStartToShiftDownMs = timing.shiftDownEpochMs - audioStartedEpochMs;
    const playbackExitToShiftUpMs = timing.shiftUpEpochMs - audioFinishedEpochMs;
    const keyUpToTextMs = timing.textVisibleAt - timing.shiftUpAt;

    Object.assign(report, {
      transcript,
      normalizedExpected: expectedWords.join(" "),
      normalizedTranscript: transcriptWords.join(" "),
      wordErrorRate: transcriptWordErrorRate,
      playbackProcessStartToShiftDownMilliseconds: audioStartToShiftDownMs,
      playbackProcessExitToShiftUpMilliseconds: playbackExitToShiftUpMs,
      browserShiftHoldMilliseconds: timing.shiftUpAt - timing.shiftDownAt,
      keyUpToVisibleTextMilliseconds: keyUpToTextMs,
    });

    expect(audioStartToShiftDownMs).toBeGreaterThanOrEqual(1_000);
    expect(audioStartToShiftDownMs).toBeLessThanOrEqual(1_400);
    expect(playbackExitToShiftUpMs).toBeGreaterThanOrEqual(0);
    expect(playbackExitToShiftUpMs).toBeLessThanOrEqual(500);
    expect(timing.shiftDownAt).not.toBeNull();
    expect(timing.shiftUpAt).toBeGreaterThan(timing.shiftDownAt);
    expect(timing.textVisibleAt).toBeGreaterThanOrEqual(timing.shiftUpAt);
    expect(transcriptWords[0]).toBe(expectedWords[0]);
    report.preShiftExpectedWord = expectedWords[0];
    expect(transcriptWordErrorRate).toBeLessThanOrEqual(maximumWordErrorRate);
    expect(keyUpToTextMs).toBeLessThanOrEqual(completionBudgetMs);
    report.passed = true;
  } catch (error) {
    report.error = error instanceof Error ? error.stack || error.message : String(error);
    throw error;
  } finally {
    if (shiftHeld) await page.keyboard.up("Shift").catch(() => {});
    await stopPlayback(playback);
    await playbackFinished?.catch(() => {});
    report.finalBrowserState = await page.evaluate(() => ({
      inputValue: document.querySelector("[data-dictation-input]")?.value || "",
      phase: document.querySelector("[data-demo-root]")?.dataset.phase || "missing",
      status: document.querySelector("[data-status]")?.textContent || "",
      timing: window.__romaRealAudioTiming || null,
    })).catch(() => null);
    report.finishedAt = new Date().toISOString();
    report.browserMessages = browserMessages;
    await mkdir(dirname(reportPath), { recursive: true });
    await mkdir(dirname(screenshotPath), { recursive: true });
    await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => {});
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    await testInfo.attach("real-audio-receipt", {
      body: Buffer.from(JSON.stringify(report, null, 2)),
      contentType: "application/json",
    });
    await testInfo.attach("completed-demo", { path: screenshotPath, contentType: "image/png" }).catch(() => {});
  }
});
