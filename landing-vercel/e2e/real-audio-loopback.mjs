import { execFile, spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { maximumEnvelopeCorrelation, pcm16WaveEnvelope } from "./wave-audio.mjs";

const PROBE_SECONDS = 2;
const ENVELOPE_WINDOW_MILLISECONDS = 20;
const execFileAsync = promisify(execFile);

async function volumeSettings() {
  const { stdout } = await execFileAsync("/usr/bin/osascript", ["-e", "get volume settings"]);
  return stdout.trim();
}

export async function maximizeLoopbackOutput() {
  const before = await volumeSettings();
  await execFileAsync("SwitchAudioSource", ["-m", "unmute", "-t", "output"]);
  await execFileAsync("/usr/bin/osascript", [
    "-e",
    "set volume output volume 100 without output muted",
  ]);
  return { before, after: await volumeSettings() };
}

function waitForPlayback(playback) {
  return new Promise((resolve, reject) => {
    let stderr = "";
    playback.stderr.setEncoding("utf8");
    playback.stderr.on("data", (chunk) => { stderr += chunk; });
    playback.once("error", reject);
    playback.once("close", (exitCode, signal) => {
      if (exitCode === 0) resolve();
      else reject(new Error(`afplay probe failed with exit ${exitCode}, signal ${signal || "none"}: ${stderr.trim()}`));
    });
  });
}

export async function measureLoopback(page, origin, fixture) {
  const expectedEnvelope = pcm16WaveEnvelope(await readFile(fixture), {
    seconds: PROBE_SECONDS,
    windowMilliseconds: ENVELOPE_WINDOW_MILLISECONDS,
  });
  await page.goto(origin);
  const probeStarted = await page.evaluate(async () => {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        autoGainControl: false,
        echoCancellation: false,
        noiseSuppression: false,
      },
    });
    const recorder = new MediaRecorder(stream);
    const chunks = [];
    recorder.addEventListener("dataavailable", (event) => {
      if (event.data.size) chunks.push(event.data);
    });
    window.__romaLoopbackProbe = { chunks, recorder, stream };
    try {
      await new Promise((resolve, reject) => {
        recorder.addEventListener("start", resolve, { once: true });
        recorder.addEventListener("error", () => reject(recorder.error || new Error("MediaRecorder failed.")), { once: true });
        recorder.start();
      });
    } catch (error) {
      stream.getTracks().forEach((track) => track.stop());
      delete window.__romaLoopbackProbe;
      throw error;
    }
    return {
      inputLabel: stream.getAudioTracks()[0]?.label || "",
      trackSettings: stream.getAudioTracks()[0]?.getSettings?.() || {},
    };
  });
  const outputLevel = await maximizeLoopbackOutput();

  const playback = spawn("/usr/bin/afplay", ["-t", String(PROBE_SECONDS), fixture], {
    stdio: ["ignore", "ignore", "pipe"],
  });
  const playbackFinished = waitForPlayback(playback);
  let operationError;
  try {
    await playbackFinished;
    const measurement = await page.evaluate(async ({ envelopeWindowMilliseconds, outputLevel, probeSeconds, probeStarted }) => {
      const probe = window.__romaLoopbackProbe;
      if (!probe) throw new Error("The BlackHole probe was lost before completion.");
      const stopped = new Promise((resolve, reject) => {
        probe.recorder.addEventListener("stop", resolve, { once: true });
        probe.recorder.addEventListener("error", () => reject(probe.recorder.error || new Error("MediaRecorder failed.")), { once: true });
      });
      probe.recorder.stop();
      await stopped;
      probe.stream.getTracks().forEach((track) => track.stop());

      let audioContext;
      try {
        const recording = new Blob(probe.chunks, { type: probe.recorder.mimeType });
        audioContext = new AudioContext();
        const decoded = await audioContext.decodeAudioData(await recording.arrayBuffer());
        let squaredTotal = 0;
        let peak = 0;
        let sampleCount = 0;
        const framesPerWindow = Math.max(1, Math.round(decoded.sampleRate * envelopeWindowMilliseconds / 1_000));
        const envelope = [];
        for (let channel = 0; channel < decoded.numberOfChannels; channel += 1) {
          const samples = decoded.getChannelData(channel);
          sampleCount += samples.length;
          for (const sample of samples) {
            squaredTotal += sample * sample;
            peak = Math.max(peak, Math.abs(sample));
          }
        }
        for (let firstFrame = 0; firstFrame < decoded.length; firstFrame += framesPerWindow) {
          const lastFrame = Math.min(decoded.length, firstFrame + framesPerWindow);
          let windowSquaredTotal = 0;
          let windowSampleCount = 0;
          for (let channel = 0; channel < decoded.numberOfChannels; channel += 1) {
            const samples = decoded.getChannelData(channel);
            for (let frame = firstFrame; frame < lastFrame; frame += 1) {
              windowSquaredTotal += samples[frame] * samples[frame];
              windowSampleCount += 1;
            }
          }
          envelope.push(Math.sqrt(windowSquaredTotal / windowSampleCount));
        }
        const rms = Math.sqrt(squaredTotal / sampleCount);
        return {
          ...probeStarted,
          outputLevel,
          requestedPlaybackSeconds: probeSeconds,
          recordedSeconds: decoded.duration,
          encodedBytes: recording.size,
          rmsDecibelsFullScale: rms > 0 ? 20 * Math.log10(rms) : Number.NEGATIVE_INFINITY,
          peakDecibelsFullScale: peak > 0 ? 20 * Math.log10(peak) : Number.NEGATIVE_INFINITY,
          envelope,
        };
      } finally {
        await audioContext?.close();
        delete window.__romaLoopbackProbe;
      }
    }, {
      envelopeWindowMilliseconds: ENVELOPE_WINDOW_MILLISECONDS,
      probeSeconds: PROBE_SECONDS,
      probeStarted,
      outputLevel,
    });
    const fixtureEnvelopeCorrelation = maximumEnvelopeCorrelation(expectedEnvelope, measurement.envelope);
    const { envelope, ...receipt } = measurement;
    return {
      ...receipt,
      envelopeWindowMilliseconds: ENVELOPE_WINDOW_MILLISECONDS,
      envelopeWindows: envelope.length,
      fixtureEnvelopeCorrelation,
    };
  } catch (error) {
    operationError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    if (playback.exitCode === null && playback.signalCode === null) playback.kill("SIGTERM");
    await playbackFinished.catch((error) => {
      if (error !== operationError) cleanupErrors.push(error);
    });
    await page.evaluate(async () => {
      const probe = window.__romaLoopbackProbe;
      if (!probe) return;
      try {
        if (probe.recorder.state !== "inactive") {
          const stopped = new Promise((resolve) => {
            probe.recorder.addEventListener("stop", resolve, { once: true });
          });
          probe.recorder.stop();
          await stopped;
        }
      } finally {
        probe.stream.getTracks().forEach((track) => track.stop());
        delete window.__romaLoopbackProbe;
      }
    }).catch((error) => cleanupErrors.push(error));
    if (cleanupErrors.length && !operationError) throw cleanupErrors[0];
    if (cleanupErrors.length && operationError instanceof Error) {
      operationError.message += ` Cleanup also failed: ${cleanupErrors.map(String).join("; ")}`;
    }
  }
}
