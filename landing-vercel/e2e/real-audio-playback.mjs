import { spawn } from "node:child_process";

export function playWave({ executable, deviceUID, fixture, seconds }) {
  const args = [deviceUID, fixture];
  if (seconds !== undefined) args.push(String(seconds));
  const process = spawn(executable, args, { stdio: ["ignore", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
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
      startedSettled = true;
      resolveStarted(startLine);
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
      if (!startedSettled) {
        const error = new Error(`CoreAudio WAV player exited before playback started: ${detail}`);
        failStarted(error);
        rejectFinished(error);
      } else if (!stdout.split("\n").some((line) => line.startsWith("completed device_uid="))) {
        rejectFinished(new Error(`CoreAudio WAV player exited without a completion marker: ${detail}`));
      } else {
        resolveFinished({ stdout: stdout.trim(), stderr: stderr.trim() });
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
