import assert from "node:assert/strict";
import test from "node:test";

import { playWave, stopWave } from "../e2e/real-audio-playback.mjs";

function fakePlayback(source) {
  return playWave({ executable: process.execPath, deviceUID: "-e", fixture: source });
}

test("device playback waits for the audio-start marker", async () => {
  const playback = fakePlayback(`
    setTimeout(() => {
      process.stdout.write("started marker=first-frame-played-back fake-device\\n");
      setTimeout(() => process.stdout.write(
        "completed device_uid=fake-device mixer_rms_dbfs=-12.5 mixer_peak_dbfs=-2 mixer_samples=32000\\n",
      ), 10);
    }, 10);
  `);

  assert.equal(await playback.started, "started marker=first-frame-played-back fake-device");
  const receipt = await playback.finished;
  assert.match(receipt.stdout, /completed device_uid=fake-device/);
  assert.equal(receipt.mixerRmsDecibelsFullScale, -12.5);
  assert.equal(receipt.mixerPeakDecibelsFullScale, -2);
  assert.equal(receipt.mixerSampleCount, 32_000);
});

test("device playback rejects a successful process without a start marker", async () => {
  const playback = fakePlayback("process.stdout.write('completed without start\\n')");

  await assert.rejects(playback.started, /exited before playback started/);
  await assert.rejects(playback.finished, /exited before playback started/);
});

test("device playback rejects a successful process without a completion marker", async () => {
  const playback = fakePlayback("process.stdout.write('started marker=first-frame-played-back fake-device\\n')");

  await playback.started;
  await assert.rejects(playback.finished, /without a completion marker/);
});

test("device playback rejects a malformed mixer receipt", async () => {
  const playback = fakePlayback(`
    process.stdout.write("started marker=first-frame-played-back fake-device\\n");
    process.stdout.write("completed device_uid=fake-device mixer_rms_dbfs=nope mixer_peak_dbfs=-2 mixer_samples=1\\n");
  `);

  await playback.started;
  await assert.rejects(playback.finished, /invalid mixer_rms_dbfs marker/);
});

test("device playback reports stderr and can stop an active player", async () => {
  const failed = fakePlayback("process.stderr.write('fixture failed'); process.exit(7)");
  failed.started.catch(() => {});
  await assert.rejects(failed.finished, /exit 7.*fixture failed/);

  const active = fakePlayback(`
    process.stdout.write("started marker=first-frame-played-back long fixture\\n");
    setInterval(() => {}, 1_000);
  `);
  await active.started;
  const finished = active.finished.catch((error) => error);
  await stopWave(active);
  assert.match(String(await finished), /signal SIGTERM/);
});
