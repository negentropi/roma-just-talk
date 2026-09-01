import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { maximizeLoopbackOutput, measureLoopback } from "./real-audio-loopback.mjs";
import { playWave, stopWave } from "./real-audio-playback.mjs";
import { expect, test } from "./real-audio-test.mjs";
import { pcm16WaveDurationSeconds, pcm16WaveRmsDecibelsFullScale } from "./wave-audio.mjs";

const AUDIO_LEAD_MS = 1_100;
const DEFAULT_COMPLETION_BUDGET_MS = 1_500;
const DEFAULT_MAXIMUM_WORD_ERROR_RATE = 0.15;
const MINIMUM_FIXTURE_RMS_DBFS = -30;
const MINIMUM_LOOPBACK_RMS_DBFS = -35;
const MINIMUM_LOOPBACK_CORRELATION = 0.65;
const MAXIMUM_CALLBACK_DURATION_ERROR_MS = 250;
const MAXIMUM_CLOCK_ALIGNMENT_ERROR_MS = 25;

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required for the real-audio E2E.`);
  return value;
}

function elapsedMilliseconds(laterNanoseconds, earlierNanoseconds) {
  return Number(laterNanoseconds - earlierNanoseconds) / 1_000_000;
}

function receiveCallbackTimestamp(callbackContinuousNanoseconds, callbackEpochNanoseconds) {
  const receivedEpochNanoseconds = BigInt(Date.now()) * 1_000_000n;
  const receivedContinuousNanoseconds = process.hrtime.bigint();
  const continuousDeliveryMilliseconds = elapsedMilliseconds(
    receivedContinuousNanoseconds,
    callbackContinuousNanoseconds,
  );
  const epochDeliveryMilliseconds = elapsedMilliseconds(
    receivedEpochNanoseconds,
    callbackEpochNanoseconds,
  );
  return {
    alignmentErrorMilliseconds: Math.abs(continuousDeliveryMilliseconds - epochDeliveryMilliseconds),
    continuousDeliveryMilliseconds,
    epochDeliveryMilliseconds,
  };
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

test("WAV starts 1.1 seconds before Left Shift and finishes as timely text", async ({ page, baseURL }, testInfo) => {
  const fixture = requiredEnvironment("ROMA_DEMO_AUDIO_FIXTURE");
  const audioPlayer = requiredEnvironment("ROMA_DEMO_AUDIO_PLAYER");
  const audioDeviceUID = requiredEnvironment("ROMA_DEMO_AUDIO_DEVICE_UID");
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
    audioDeviceUID,
    playbackLeadTargetMilliseconds: AUDIO_LEAD_MS,
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
    const fixtureBuffer = await readFile(fixture);
    const fixtureRmsDecibelsFullScale = pcm16WaveRmsDecibelsFullScale(fixtureBuffer);
    const fixtureDurationMilliseconds = pcm16WaveDurationSeconds(fixtureBuffer) * 1_000;
    report.fixtureRmsDecibelsFullScale = fixtureRmsDecibelsFullScale;
    report.fixtureDurationMilliseconds = fixtureDurationMilliseconds;
    expect(fixtureRmsDecibelsFullScale).toBeGreaterThanOrEqual(MINIMUM_FIXTURE_RMS_DBFS);

    const probePage = await page.context().newPage();
    const loopback = await measureLoopback(probePage, baseURL, {
      fixture,
    })
      .finally(() => probePage.close());
    report.loopback = loopback;
    expect(loopback.inputLabel).toContain(audioDevice);
    expect(loopback.recordedSeconds).toBeGreaterThanOrEqual(1.5);
    expect(loopback.rmsDecibelsFullScale).toBeGreaterThanOrEqual(MINIMUM_LOOPBACK_RMS_DBFS);
    expect(loopback.fixtureEnvelopeCorrelation).toBeGreaterThanOrEqual(MINIMUM_LOOPBACK_CORRELATION);

    const response = await page.goto(`${baseURL}/demo`);
    expect(response?.status()).toBe(200);
    const root = page.locator("[data-demo-root]");
    const input = page.locator("[data-dictation-input]");
    await expect(root).toHaveAttribute("data-phase", "ready", { timeout: 15_000 });
    await expect(input).toBeFocused();
    report.outputLevelBeforePlayback = await maximizeLoopbackOutput();

    const audioInputs = await page.evaluate(async () => (await navigator.mediaDevices.enumerateDevices())
      .filter((device) => device.kind === "audioinput")
      .map(({ deviceId, label }) => ({ deviceId, label })));
    report.browserAudioInputs = audioInputs;
    const defaultInput = audioInputs.find((device) => device.deviceId === "default") || audioInputs[0];
    expect(defaultInput?.label || "").toContain(audioDevice);

    playback = playWave({
      executable: audioPlayer,
      deviceUID: audioDeviceUID,
      fixture,
    });
    playbackFinished = playback.finished;
    playbackFinished.catch(() => {});
    const playbackStart = await playback.started;
    const startClockAlignment = receiveCallbackTimestamp(
      playbackStart.callbackContinuousNanoseconds,
      playbackStart.callbackEpochNanoseconds,
    );
    report.audioPlaybackStarted = playbackStart.marker;
    report.audioPlaybackStartContinuousNanoseconds = playbackStart.callbackContinuousNanoseconds.toString();
    report.audioPlaybackStartEpochNanoseconds = playbackStart.callbackEpochNanoseconds.toString();
    report.audioPlaybackStartClockAlignment = startClockAlignment;
    expect(startClockAlignment.continuousDeliveryMilliseconds).toBeGreaterThanOrEqual(0);
    expect(startClockAlignment.continuousDeliveryMilliseconds).toBeLessThanOrEqual(500);
    expect(startClockAlignment.epochDeliveryMilliseconds).toBeGreaterThanOrEqual(-2);
    expect(startClockAlignment.epochDeliveryMilliseconds).toBeLessThanOrEqual(500);
    expect(startClockAlignment.alignmentErrorMilliseconds).toBeLessThanOrEqual(MAXIMUM_CLOCK_ALIGNMENT_ERROR_MS);
    const waitBeforeShift = Math.max(0, AUDIO_LEAD_MS - elapsedMilliseconds(
      process.hrtime.bigint(),
      playbackStart.callbackContinuousNanoseconds,
    ));
    await new Promise((resolveDelay) => setTimeout(resolveDelay, waitBeforeShift));

    const shiftDownSendStartedEpochNanoseconds = BigInt(Date.now()) * 1_000_000n;
    const shiftDownSendStartedNanoseconds = process.hrtime.bigint();
    await page.keyboard.down("Shift");
    const shiftDownSendFinishedNanoseconds = process.hrtime.bigint();
    const shiftDownSendFinishedEpochNanoseconds = BigInt(Date.now()) * 1_000_000n;
    shiftHeld = true;
    await expect(root).toHaveAttribute("data-phase", "capturing");
    const audioPlayback = await playbackFinished;
    const completionClockAlignment = receiveCallbackTimestamp(
      audioPlayback.callbackContinuousNanoseconds,
      audioPlayback.callbackEpochNanoseconds,
    );
    report.audioPlayback = {
      ...audioPlayback,
      callbackContinuousNanoseconds: audioPlayback.callbackContinuousNanoseconds.toString(),
      callbackEpochNanoseconds: audioPlayback.callbackEpochNanoseconds.toString(),
    };
    report.audioPlaybackCompletionClockAlignment = completionClockAlignment;
    expect(audioPlayback.mixerRmsDecibelsFullScale).toBeGreaterThanOrEqual(MINIMUM_FIXTURE_RMS_DBFS);
    expect(completionClockAlignment.continuousDeliveryMilliseconds).toBeGreaterThanOrEqual(0);
    expect(completionClockAlignment.continuousDeliveryMilliseconds).toBeLessThanOrEqual(500);
    expect(completionClockAlignment.epochDeliveryMilliseconds).toBeGreaterThanOrEqual(-2);
    expect(completionClockAlignment.epochDeliveryMilliseconds).toBeLessThanOrEqual(500);
    expect(completionClockAlignment.alignmentErrorMilliseconds).toBeLessThanOrEqual(MAXIMUM_CLOCK_ALIGNMENT_ERROR_MS);
    const shiftUpSendStartedEpochNanoseconds = BigInt(Date.now()) * 1_000_000n;
    const shiftUpSendStartedNanoseconds = process.hrtime.bigint();
    await page.keyboard.up("Shift");
    const shiftUpSendFinishedNanoseconds = process.hrtime.bigint();
    const shiftUpSendFinishedEpochNanoseconds = BigInt(Date.now()) * 1_000_000n;
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
    const audioStartToShiftDownMinimumMs = elapsedMilliseconds(
      shiftDownSendStartedNanoseconds,
      playbackStart.callbackContinuousNanoseconds,
    );
    const audioStartToShiftDownMaximumMs = elapsedMilliseconds(
      shiftDownSendFinishedNanoseconds,
      playbackStart.callbackContinuousNanoseconds,
    );
    const audioStartToShiftDownMs = (audioStartToShiftDownMinimumMs + audioStartToShiftDownMaximumMs) / 2;
    const audioStartToShiftDownEpochMinimumMs = elapsedMilliseconds(
      shiftDownSendStartedEpochNanoseconds,
      playbackStart.callbackEpochNanoseconds,
    );
    const audioStartToShiftDownEpochMaximumMs = elapsedMilliseconds(
      shiftDownSendFinishedEpochNanoseconds,
      playbackStart.callbackEpochNanoseconds,
    );
    const audioStartToShiftDownClockAlignmentErrorMs = Math.max(
      Math.abs(audioStartToShiftDownMinimumMs - audioStartToShiftDownEpochMinimumMs),
      Math.abs(audioStartToShiftDownMaximumMs - audioStartToShiftDownEpochMaximumMs),
    );
    const playbackCompletionToShiftUpMinimumMs = elapsedMilliseconds(
      shiftUpSendStartedNanoseconds,
      audioPlayback.callbackContinuousNanoseconds,
    );
    const playbackCompletionToShiftUpMaximumMs = elapsedMilliseconds(
      shiftUpSendFinishedNanoseconds,
      audioPlayback.callbackContinuousNanoseconds,
    );
    const playbackCompletionToShiftUpMs = (
      playbackCompletionToShiftUpMinimumMs + playbackCompletionToShiftUpMaximumMs
    ) / 2;
    const playbackCompletionToShiftUpEpochMinimumMs = elapsedMilliseconds(
      shiftUpSendStartedEpochNanoseconds,
      audioPlayback.callbackEpochNanoseconds,
    );
    const playbackCompletionToShiftUpEpochMaximumMs = elapsedMilliseconds(
      shiftUpSendFinishedEpochNanoseconds,
      audioPlayback.callbackEpochNanoseconds,
    );
    const playbackCompletionToShiftUpClockAlignmentErrorMs = Math.max(
      Math.abs(playbackCompletionToShiftUpMinimumMs - playbackCompletionToShiftUpEpochMinimumMs),
      Math.abs(playbackCompletionToShiftUpMaximumMs - playbackCompletionToShiftUpEpochMaximumMs),
    );
    const callbackPlaybackDurationMs = elapsedMilliseconds(
      audioPlayback.callbackContinuousNanoseconds,
      playbackStart.callbackContinuousNanoseconds,
    );
    const callbackPlaybackEpochDurationMs = elapsedMilliseconds(
      audioPlayback.callbackEpochNanoseconds,
      playbackStart.callbackEpochNanoseconds,
    );
    const keyUpToTextMs = timing.textVisibleAt - timing.shiftUpAt;

    Object.assign(report, {
      transcript,
      normalizedExpected: expectedWords.join(" "),
      normalizedTranscript: transcriptWords.join(" "),
      wordErrorRate: transcriptWordErrorRate,
      playbackStartToShiftDownMilliseconds: audioStartToShiftDownMs,
      playbackStartToShiftDownMinimumMilliseconds: audioStartToShiftDownMinimumMs,
      playbackStartToShiftDownMaximumMilliseconds: audioStartToShiftDownMaximumMs,
      playbackStartToShiftDownEpochMinimumMilliseconds: audioStartToShiftDownEpochMinimumMs,
      playbackStartToShiftDownEpochMaximumMilliseconds: audioStartToShiftDownEpochMaximumMs,
      playbackStartToShiftDownClockAlignmentErrorMilliseconds: audioStartToShiftDownClockAlignmentErrorMs,
      playbackCompletionToShiftUpMilliseconds: playbackCompletionToShiftUpMs,
      playbackCompletionToShiftUpMinimumMilliseconds: playbackCompletionToShiftUpMinimumMs,
      playbackCompletionToShiftUpMaximumMilliseconds: playbackCompletionToShiftUpMaximumMs,
      playbackCompletionToShiftUpEpochMinimumMilliseconds: playbackCompletionToShiftUpEpochMinimumMs,
      playbackCompletionToShiftUpEpochMaximumMilliseconds: playbackCompletionToShiftUpEpochMaximumMs,
      playbackCompletionToShiftUpClockAlignmentErrorMilliseconds: playbackCompletionToShiftUpClockAlignmentErrorMs,
      callbackPlaybackDurationMilliseconds: callbackPlaybackDurationMs,
      callbackPlaybackEpochDurationMilliseconds: callbackPlaybackEpochDurationMs,
      browserShiftHoldMilliseconds: timing.shiftUpAt - timing.shiftDownAt,
      keyUpToVisibleTextMilliseconds: keyUpToTextMs,
    });

    expect(audioStartToShiftDownMinimumMs).toBeGreaterThanOrEqual(1_000);
    expect(audioStartToShiftDownMaximumMs).toBeLessThanOrEqual(1_400);
    expect(audioStartToShiftDownEpochMinimumMs).toBeGreaterThanOrEqual(1_000);
    expect(audioStartToShiftDownEpochMaximumMs).toBeLessThanOrEqual(1_400);
    expect(audioStartToShiftDownClockAlignmentErrorMs).toBeLessThanOrEqual(MAXIMUM_CLOCK_ALIGNMENT_ERROR_MS);
    expect(playbackCompletionToShiftUpMinimumMs).toBeGreaterThanOrEqual(0);
    expect(playbackCompletionToShiftUpMaximumMs).toBeLessThanOrEqual(500);
    expect(playbackCompletionToShiftUpEpochMinimumMs).toBeGreaterThanOrEqual(-2);
    expect(playbackCompletionToShiftUpEpochMaximumMs).toBeLessThanOrEqual(500);
    expect(playbackCompletionToShiftUpClockAlignmentErrorMs).toBeLessThanOrEqual(
      MAXIMUM_CLOCK_ALIGNMENT_ERROR_MS,
    );
    expect(callbackPlaybackDurationMs).toBeGreaterThanOrEqual(
      fixtureDurationMilliseconds - MAXIMUM_CALLBACK_DURATION_ERROR_MS,
    );
    expect(callbackPlaybackDurationMs).toBeLessThanOrEqual(
      fixtureDurationMilliseconds + MAXIMUM_CALLBACK_DURATION_ERROR_MS,
    );
    expect(callbackPlaybackEpochDurationMs).toBeGreaterThanOrEqual(
      fixtureDurationMilliseconds - MAXIMUM_CALLBACK_DURATION_ERROR_MS,
    );
    expect(callbackPlaybackEpochDurationMs).toBeLessThanOrEqual(
      fixtureDurationMilliseconds + MAXIMUM_CALLBACK_DURATION_ERROR_MS,
    );
    expect(Math.abs(callbackPlaybackDurationMs - callbackPlaybackEpochDurationMs)).toBeLessThanOrEqual(
      MAXIMUM_CLOCK_ALIGNMENT_ERROR_MS,
    );
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
    await stopWave(playback);
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
