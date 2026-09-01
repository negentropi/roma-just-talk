import assert from "node:assert/strict";
import test from "node:test";

import {
  maximumEnvelopeCorrelation,
  pcm16WaveEnvelope,
  pcm16WaveRmsDecibelsFullScale,
} from "../e2e/wave-audio.mjs";

function pcm16Wave(samples, { channels = 1, sampleRate = 1_000 } = {}) {
  const dataSize = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataSize);
  buffer.write("RIFF", 0);
  buffer.writeUInt32LE(buffer.length - 8, 4);
  buffer.write("WAVE", 8);
  buffer.write("fmt ", 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(channels, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * channels * 2, 28);
  buffer.writeUInt16LE(channels * 2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write("data", 36);
  buffer.writeUInt32LE(dataSize, 40);
  samples.forEach((sample, index) => buffer.writeInt16LE(sample, 44 + index * 2));
  return buffer;
}

test("PCM16 WAV measurements use complete frames and deterministic windows", () => {
  const fixture = pcm16Wave([1_000, -1_000, 2_000, -2_000]);

  assert.ok(Math.abs(pcm16WaveRmsDecibelsFullScale(fixture) - (-26.32959861247398)) < 1e-12);
  assert.deepEqual(
    pcm16WaveEnvelope(fixture, { seconds: 0.004, windowMilliseconds: 2 }),
    [1_000 / 32_768, 2_000 / 32_768],
  );

  assert.throws(
    () => pcm16WaveRmsDecibelsFullScale(pcm16Wave([1, 2, 3], { channels: 2 })),
    /complete 16-bit PCM frames/,
  );
});

test("envelope correlation finds a shifted copy", () => {
  const expected = [0.01, 0.05, 0.4, 0.1, 0.8, 0.2, 0.6, 0.03];
  const actual = [0.9, 0.7, ...expected, 0.2];

  assert.ok(maximumEnvelopeCorrelation(expected, actual) > 0.999999999999);
});

test("envelope correlation rejects constant and insufficient recordings", () => {
  const expected = [0.01, 0.05, 0.4, 0.1, 0.8];

  assert.equal(maximumEnvelopeCorrelation(expected, [1, 1, 1, 1, 1]), Number.NEGATIVE_INFINITY);
  assert.equal(maximumEnvelopeCorrelation(expected, [0.01, 0.05, 0.4]), Number.NEGATIVE_INFINITY);
});
