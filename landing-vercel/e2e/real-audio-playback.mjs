import { spawn } from "node:child_process";

function numericMarkerField(line, name) {
  const value = Number(line.match(new RegExp(`(?:^| )${name}=([^ ]+)`))?.[1]);
  if (!Number.isFinite(value)) throw new Error(`CoreAudio WAV player emitted an invalid ${name} marker: ${line}`);
  return value;
}

function bigIntMarkerField(line, name) {
  const value = line.match(new RegExp(`(?:^| )${name}=([^ ]+)`))?.[1];
  try {
    if (!value || !/^\d+$/.test(value)) throw new Error();
    const parsed = BigInt(value);
    if (parsed <= 0n) throw new Error();
    return parsed;
  } catch {
    throw new Error(`CoreAudio WAV player emitted an invalid ${name} marker: ${line}`);
  }
}

export function playWave({ executable, deviceUID, fixture, seconds }) {
  const args = [deviceUID, fixture];
  if (seconds !== undefined) args.push(String(seconds));
  const process = spawn(executable, args, { stdio: ["ignore", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
  let startError;
  let startedSettled = false;
  let resolveStarted;
  let rejectStarted;
  let resolveFinished;
  let rejectFinished;
  const started = new Promise((resolve, reject) => {
    resolveStarted = resolve;
    rejectStarted = reject;
  });
  const finished = new Promise((resolve, reject) => {
    resolveFinished = resolve;
    rejectFinished = reject;
  });

  function failStarted(error) {
    if (startedSettled) return;
    startedSettled = true;
    rejectStarted(error);
  }

  process.stdout.setEncoding("utf8");
  process.stderr.setEncoding("utf8");
  process.stdout.on("data", (chunk) => {
    stdout += chunk;
    const startLine = stdout.split("\n")
      .find((line) => line.startsWith("started marker=first-frame-played-back "));
    if (startLine && !startedSettled) {
      try {
        const callbackContinuousNanoseconds = bigIntMarkerField(startLine, "callback_continuous_ns");
        const callbackEpochNanoseconds = bigIntMarkerField(startLine, "callback_epoch_ns");
        startedSettled = true;
        resolveStarted({ callbackContinuousNanoseconds, callbackEpochNanoseconds, marker: startLine });
      } catch (error) {
        startError = error;
        failStarted(error);
      }
    }
  });
  process.stderr.on("data", (chunk) => { stderr += chunk; });
  process.once("error", (error) => {
    failStarted(error);
    rejectFinished(error);
  });
  process.once("close", (exitCode, signal) => {
    const detail = `exit ${exitCode}, signal ${signal || "none"}: ${stderr.trim()}`;
    if (exitCode === 0) {
      if (startError) {
        rejectFinished(startError);
      } else if (!startedSettled) {
        const error = new Error(`CoreAudio WAV player exited before playback started: ${detail}`);
        failStarted(error);
        rejectFinished(error);
      } else if (!stdout.split("\n").some((line) => line.startsWith("completed callback_continuous_ns="))) {
        rejectFinished(new Error(`CoreAudio WAV player exited without a completion marker: ${detail}`));
      } else {
        const completionLine = stdout.split("\n")
          .find((line) => line.startsWith("completed callback_continuous_ns="));
        try {
          resolveFinished({
            callbackContinuousNanoseconds: bigIntMarkerField(completionLine, "callback_continuous_ns"),
            callbackEpochNanoseconds: bigIntMarkerField(completionLine, "callback_epoch_ns"),
            stdout: stdout.trim(),
            stderr: stderr.trim(),
            mixerRmsDecibelsFullScale: numericMarkerField(completionLine, "mixer_rms_dbfs"),
            mixerPeakDecibelsFullScale: numericMarkerField(completionLine, "mixer_peak_dbfs"),
            mixerSampleCount: numericMarkerField(completionLine, "mixer_samples"),
          });
        } catch (error) {
          rejectFinished(error);
        }
      }
    } else {
      const error = new Error(`CoreAudio WAV player failed with ${detail}`);
      failStarted(error);
      rejectFinished(error);
    }
  });
  return { process, started, finished };
}

export async function stopWave(playback) {
  if (!playback || playback.process.exitCode !== null || playback.process.signalCode !== null) return;
  const closed = new Promise((resolve) => playback.process.once("close", resolve));
  playback.process.kill("SIGTERM");
  const stopped = await Promise.race([
    closed.then(() => true),
    new Promise((resolve) => setTimeout(resolve, 1_000, false)),
  ]);
  if (!stopped) {
    playback.process.kill("SIGKILL");
    await closed;
  }
}
